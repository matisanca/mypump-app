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

    /**
     * Desvío a propósito (15-oct): la web borraba la foto al octavo error del servidor. Con la Mini caída Cloudflare contesta
     * 502/530, y abriendo la app unas cuantas veces la foto se perdía. Ahora espera a que el servidor vuelva.
     */
    @Test
    fun conElServidorCaidoLaFotoNoSePierde() = enUnHilo {
        val caida = Array<Pair<Int, String>?>(10) { 502 to "{\"ok\":false,\"error\":\"no se pudo guardar la foto\"}" } +
            Array<Pair<Int, String>?>(11) { 530 to "<html>error code: 1033</html>" }
        val g = Guion(*caida, 200 to "{\"ok\":true,\"semana_lunes\":\"2026-10-12\",\"pose\":\"perfil\"}")
        val m = modelo(g)
        assertEquals(ModeloFotos.Resultado.SinConexion, m.subir("perfil", jpeg))
        repeat(20) { m.drenar() }
        assertEquals(1, m.pendientes.value.size, "con el servidor caído la foto se borraba al octavo intento")
        assertEquals(1, modelo(g).pendientes.value.size, "y tiene que seguir en el disco")
        m.drenar()
        assertTrue(m.pendientes.value.isEmpty(), "cuando el servidor vuelve, sube")
    }

    /**
     * El servicio deja 12 fotos por día y por link (429, «probá mañana»). La foto queda para mañana sin gastarse, y la pasada
     * se corta: con el tope no entra ninguna.
     */
    @Test
    fun conElTopeDelDiaQuedaParaManana() = enUnHilo {
        val tope = 429 to "{\"ok\":false,\"error\":\"muchas fotos por hoy, probá mañana\"}"
        val g = Guion(*Array<Pair<Int, String>?>(2 + 12) { tope }, 200 to "{\"ok\":true}", 200 to "{\"ok\":true}")
        val m = modelo(g)
        assertEquals(ModeloFotos.Resultado.TopeDelDia, m.subir("frente", jpeg))
        assertEquals(ModeloFotos.Resultado.TopeDelDia, m.subir("perfil", jpeg))
        val subidas = { synchronized(g) { g.pedidos.count { it.endsWith("upload") } } }
        m.drenar()
        assertEquals(3, subidas(), "con el tope del día la pasada siguió probando las demás")
        repeat(11) { m.drenar() }
        assertEquals(2, m.pendientes.value.size, "con el tope del día las fotos se borraban")
        m.drenar()
        assertTrue(m.pendientes.value.isEmpty())
    }

    /** Una foto que el servidor no puede guardar (un 5xx cada vez) no traba a las que vienen atrás. */
    @Test
    fun unaFotoQueNoEntraNoTrabaALasDemas() = enUnHilo {
        val g = Guion(null, null, 502 to "{\"ok\":false,\"error\":\"no se pudo guardar la foto\"}", 200 to "{\"ok\":true}")
        val m = modelo(g)
        m.subir("espalda", jpeg)
        m.subir("frente", jpeg)
        m.drenar()   // espalda va primero (por la clave): 502, sigue; frente: ok
        assertEquals(listOf(true), m.pendientes.value.keys.map { it.endsWith("|espalda") })
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
