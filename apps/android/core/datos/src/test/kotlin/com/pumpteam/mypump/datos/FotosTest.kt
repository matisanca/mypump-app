package com.pumpteam.mypump.datos

import java.io.IOException
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Contesta lo que se le programa a las subidas (`null` = sin red); lo demás, `[]`. */
class Guion(vararg respuestas: Pair<Int, String>?) : Transporte {
    private val cola = ArrayDeque(respuestas.toList())
    val pedidos = mutableListOf<String>()

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val r = synchronized(this) {
            pedidos += pedido.ruta
            if (!pedido.ruta.endsWith("upload")) return Respuesta(200, "[]".toByteArray())
            cola.removeFirstOrNull()
        } ?: throw IOException("sin conexión a internet")
        return Respuesta(r.first, r.second.toByteArray())
    }
}

/** Fotos de progreso: la cola como la web, con los casos de FotosTests.swift. */
class FotosTest {
    private val raiz = carpetaTemporal("mypump-fotos")
    private val token = "tokenDePrueba_0000000000"
    private val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0x00, 0x10)

    private fun modelo(g: Guion) = ModeloFotos(ClienteRpc(transporte = g), token, Disco(raiz, token))

    @Test
    fun sinRedQuedaGuardadaYNoGastaIntentos() = enUnHilo {
        val g = Guion(null, null)
        val m = modelo(g)
        assertEquals(ModeloFotos.Resultado.SinConexion, m.subir("frente", jpeg))
        m.drenar()
        assertEquals(0, m.pendientes.value.values.first().intentos)
        // Sobrevive a cerrar la app.
        assertEquals(1, modelo(g).pendientes.value.size)
    }

    @Test
    fun elServidorCaidoGastaIntentosYAlOctavoSeDeja() = enUnHilo {
        val g = Guion(*Array(9) { 503 to "{\"ok\":false}" })
        val m = modelo(g)
        m.subir("perfil", jpeg)
        repeat(7) { m.drenar() }
        assertEquals(7, m.pendientes.value.values.first().intentos)
        m.drenar()
        assertTrue(m.pendientes.value.isEmpty())
    }

    @Test
    fun unRechazoNoTrabaLaCola() = enUnHilo {
        val g = Guion(
            null, null,
            400 to "{\"ok\":false,\"error\":\"no es un JPEG\"}",
            200 to "{\"ok\":true,\"semana_lunes\":\"2026-10-12\",\"pose\":\"perfil\"}",
        )
        val m = modelo(g)
        m.subir("frente", jpeg)
        m.subir("perfil", jpeg)
        assertEquals(2, m.pendientes.value.size)
        m.drenar()   // frente: 400 → se descarta y sigue; perfil: ok
        assertTrue(m.pendientes.value.isEmpty())
    }

    @Test
    fun rechazadaAlSubirYLimites() = enUnHilo {
        // Un rechazo que no es del token se descarta (como la web). El del token queda guardado: FotosTokenCaidoTest.
        val g = Guion(400 to "{\"ok\":false,\"error\":\"imagen inválida\"}", null, null, null)
        val m = modelo(g)
        assertEquals(ModeloFotos.Resultado.Rechazada("imagen inválida"), m.subir("frente", jpeg))
        assertTrue(m.pendientes.value.isEmpty())
        for (p in listOf("frente", "perfil", "espalda")) m.subir(p, jpeg)
        assertEquals(3, m.pendientes.value.size)
        // Una cuarta pose (otra clave) no entra; reemplazar una de las tres sí.
        assertEquals(3, modelo(g).pendientes.value.size)
        assertEquals(ModeloFotos.Resultado.MuyPesada, m.subir("frente", ByteArray(1_900_000)))
    }
}
