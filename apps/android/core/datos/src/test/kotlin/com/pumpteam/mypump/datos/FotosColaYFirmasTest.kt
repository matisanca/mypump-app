package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.util.concurrent.atomic.AtomicInteger
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Las firmas de `progreso/urls` (cuenta los pedidos) y las subidas, siempre OK; lo demás, `[]` (Firmas de FotosTests.swift). */
private class Firmas : Transporte {
    private val pedidas = AtomicInteger(0)
    val pedidosDeUrls: Int get() = pedidas.get()

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val cuerpo = when {
            pedido.ruta.endsWith("progreso/urls") -> {
                pedidas.incrementAndGet()
                """{"ok":true,"fotos":[{"semana_lunes":"2026-10-12","pose":"frente","url":"https://fotos.test/f.jpg"}]}"""
            }
            pedido.ruta.endsWith("upload") -> """{"ok":true}"""
            else -> "[]"
        }
        return Respuesta(200, cuerpo.toByteArray())
    }
}

/** Fotos de progreso: las pruebas de FotosTests.swift que no tenían gemela (REV-03 y REV-05). */
class FotosColaYFirmasTest {
    private val raiz = carpetaTemporal("mypump-fotos")
    private val token = "tokenDePrueba_0000000000"
    private val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0x00, 0x10)

    /**
     * REV-05: las URLs firmadas duran 1 h y se guardan 50 minutos: la segunda firma no pide; `forzar` sí, y subir una foto
     * invalida lo guardado (que aparezca la miniatura nueva). Hasta ahora solo lo veía la integración con
     * `MYPUMP_PROBAR_FOTOS=1`.
     */
    @Test
    fun lasUrlsFirmadasSeGuardan() = enUnHilo {
        val t = Firmas()
        val m = ModeloFotos(ClienteRpc(transporte = t), token, Disco(raiz, token))
        assertTrue(m.firmar())
        assertNotNull(m.urls.value["2026-10-12|frente"])
        assertTrue(m.firmar())
        assertEquals(1, t.pedidosDeUrls, "la segunda no tenía que pedir")
        assertTrue(m.firmar(forzar = true))
        assertEquals(2, t.pedidosDeUrls)
        assertEquals(ModeloFotos.Resultado.Guardada, m.subir("perfil", jpeg))
        assertTrue(m.firmar())
        assertEquals(3, t.pedidosDeUrls)
    }

    /**
     * REV-03: el tope es de 3 en la cola, de cualquier semana. Con 3 de la semana pasada que no salieron (por ejemplo, las
     * que trajo la migración), una de esta semana no entra ni sale: "cola llena". Es la "cuarta pose (otra clave)" del
     * comentario de FotosTest.rechazadaAlSubirYLimites, que esa prueba no intentaba.
     */
    @Test
    fun conTresEnLaColaUnaCuartaNoEntra() = enUnHilo {
        val g = Guion(null)
        val disco = Disco(raiz, token)
        val viejas = listOf("frente", "perfil", "espalda").associate { p ->
            "2026-10-05|$p" to FotoPendiente(p, "2026-10-07", "data:image/jpeg;base64,/9j/").aValor()
        }
        disco.guardar(FotoPendiente.ARCHIVO, ValorJson.Objeto(viejas))
        val m = ModeloFotos(ClienteRpc(transporte = g), token, disco)
        assertEquals(3, m.pendientes.value.size)
        assertEquals(ModeloFotos.Resultado.ColaLlena, m.subir("frente", jpeg))
        assertEquals(3, m.pendientes.value.size)
        assertTrue(g.pedidos.none { it.endsWith("upload") }, "${g.pedidos}")
    }
}
