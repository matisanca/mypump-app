package com.pumpteam.mypump.datos

import java.io.IOException
import java.time.Instant
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 7, con el modelo entero (la cola, las escrituras y el hilo), gemelo de
 * ChatRepetidosTests.swift:
 * - un mensaje igual a uno mandado en los últimos 2 minutos quedaba "enviando…" hasta reiniciar: el servidor deduplica
 *   (mig 075) y devuelve la fila vieja, así que nunca llega una fila nueva que saque la burbuja;
 * - con el reloj del teléfono atrasado, `yaLlego` tomaba un mensaje igual de hasta una hora antes como este y el nuevo no
 *   salía nunca.
 */
class ChatRepetidosTest {
    private val raiz = carpetaTemporal("chat-repetidos")

    private suspend fun esperar(condicion: suspend () -> Boolean): Boolean {
        repeat(150) {
            if (condicion()) return true
            delay(20)
        }
        return condicion()
    }

    private fun modelo(t: TransporteProgramado, alcance: CoroutineScope) =
        ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raiz, PreferenciasEnMemoria(), alcance)

    private fun fila(id: String, texto: String, fecha: Instant): String =
        """{"id":"$id","autor":"cliente","contenido":"$texto","leido_por_cliente":true,"created_at":"${FechaIso.texto(fecha)}"}"""

    private val info = """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""

    @Test
    fun unRepetidoQueElServidorDeduplicaNoQuedaEnviando() = enUnHilo { alcance ->
        val hace90Segundos = Instant.now().minusSeconds(90)
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to info
                "mypump_get_chat" -> 200 to "[${fila("m5", "dale", hace90Segundos)}]"
                "mypump_agregar_comentario" -> 200 to "\"m5\""   // 075: el mismo texto en 2 minutos es la fila que ya estaba
                else -> 200 to "[]"
            }
        }
        val m = modelo(t, alcance)
        m.cargar()
        val chat = m.chat.value!!
        assertEquals(listOf("m5"), chat.hilo.value.mensajes.map { it.id })
        chat.enviar("dale")
        assertTrue(esperar { "mypump_agregar_comentario" in t.llamadas && "mypump_chat_nuevos" in t.llamadas })
        assertTrue(esperar { chat.hilo.value.mensajes.none { it.pendiente } }, "quedó \"enviando…\" para siempre")
        assertEquals(listOf("m5"), chat.hilo.value.mensajes.map { it.id })
    }

    @Test
    fun conElRelojAtrasadoUnRepetidoDeHaceMediaHoraSale() = enUnHilo { alcance ->
        // El teléfono atrasa una hora: para el servidor el "dale" anterior fue hace media hora, que en el reloj del teléfono
        // es media hora en el futuro.
        val anterior = Instant.now().plusSeconds(30 * 60)
        val nuevo = Instant.now().plusSeconds(60 * 60)
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to info
                "mypump_get_chat" -> 200 to "[${fila("m5", "dale", anterior)}]"
                "mypump_agregar_comentario" -> 200 to "\"m6\""
                "mypump_chat_nuevos" -> 200 to "[${fila("m6", "dale", nuevo)}]"
                else -> 200 to "[]"
            }
        }
        val m = modelo(t, alcance)
        m.cargar()
        val chat = m.chat.value!!
        chat.enviar("dale")
        assertTrue(esperar { "mypump_chat_nuevos" in t.llamadas })
        assertTrue(esperar { m.outbox!!.pendientes() == 0 })
        assertEquals(1, t.llamadas.count { it == "mypump_agregar_comentario" }, "el mensaje nuevo no salió: se tomó el de hace media hora")
        assertTrue(esperar { chat.hilo.value.mensajes.map { it.id } == listOf("m5", "m6") })
    }

    @Test
    fun unReintentoDeAlgoQueYaHabiaLlegadoNoSeMandaDosVeces() = enUnHilo { alcance ->
        // La primera vez el mensaje llega pero la respuesta se pierde; el reintento lo encuentra en el hilo (con el reloj del
        // teléfono atrasado una hora, como en la de arriba).
        val anterior = Instant.now().plusSeconds(30 * 60)
        val llego = Instant.now().plusSeconds(60 * 60)
        val yaLlego = AtomicBoolean(false)
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to info
                "mypump_get_chat" -> 200 to "[" + (if (yaLlego.get()) fila("m6", "dale", llego) + "," else "") + fila("m5", "dale", anterior) + "]"
                "mypump_agregar_comentario" -> {
                    yaLlego.set(true)
                    throw IOException("se cortó la conexión")
                }
                else -> 200 to "[]"
            }
        }
        val m = modelo(t, alcance)
        m.cargar()
        val chat = m.chat.value!!
        chat.enviar("dale")
        assertTrue(esperar { yaLlego.get() })
        // El reintento (la cola lo programa sola; acá se fuerza).
        repeat(3) { m.outbox!!.drenar() }
        assertTrue(esperar { m.outbox!!.pendientes() == 0 })
        assertEquals(1, t.llamadas.count { it == "mypump_agregar_comentario" }, "se mandó de nuevo algo que ya estaba")
    }
}
