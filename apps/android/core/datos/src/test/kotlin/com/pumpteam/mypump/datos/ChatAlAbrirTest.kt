package com.pumpteam.mypump.datos

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * El Chat abierto antes de que termine la carga de la cuenta (desde f0f6ab1): la pantalla pide la última página al abrirse,
 * para no mostrar el hilo vacío, y la carga, al llegar al chat, la pedía otra vez. No perdía ni repetía mensajes, pero era
 * un pedido de más en cada arranque que abre el Chat (por ejemplo, al tocar un aviso de Mati).
 */
class ChatAlAbrirTest {
    private val hola = """[{"id":"m1","autor":"coach","contenido":"hola","leido_por_cliente":false,"created_at":"2026-10-15T10:00:00+00:00"}]"""

    /** El servidor: la carga queda frenada en las comidas libres (ya con las pestañas a la vista) hasta [sigue]. */
    private fun transporte(sigue: CompletableDeferred<Unit>) = TransporteProgramado { fn, _ ->
        when (fn) {
            "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
            "mypump_get_comidas_libres" -> {
                sigue.await()
                200 to "[]"
            }
            "mypump_get_chat" -> 200 to hola
            else -> 200 to "[]"
        }
    }

    private fun modelo(t: TransporteProgramado, alcance: CoroutineScope) =
        ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(TOKEN), carpetaTemporal("chat-al-abrir"), PreferenciasEnMemoria(), alcance)

    private fun pedidosDelHilo(t: TransporteProgramado) = t.llamadas.count { it == "mypump_get_chat" }

    @Test
    fun abrirElChatMientrasCargaLaCuentaPideLaUltimaPaginaUnaSolaVez() = enUnHilo { alcance ->
        val sigue = CompletableDeferred<Unit>()
        val t = transporte(sigue)
        val m = modelo(t, alcance)
        val carga = alcance.launch { m.cargar() }
        // La carga ya mostró las pestañas y quedó esperando las comidas libres: el chat todavía no se pidió.
        repeat(500) { if ("mypump_get_comidas_libres" !in t.llamadas) delay(10) }
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertEquals(0, pedidosDelHilo(t))
        // El cliente abre el Chat (lo que hace ChatPantalla): se trae en el momento.
        val chat = m.chat.value!!
        chat.abierto = true
        chat.alAbrir()
        assertEquals(1, pedidosDelHilo(t))
        assertEquals(listOf("m1"), chat.hilo.value.mensajes.map { it.id })
        // La carga sigue y llega al chat: ya está traído, no lo pide otra vez.
        sigue.complete(Unit)
        carga.join()
        assertEquals(1, pedidosDelHilo(t), "la carga volvió a pedir la última página: ${t.llamadas}")
        assertEquals(listOf("m1"), chat.hilo.value.mensajes.map { it.id })
    }

    /** Sin abrir el Chat la carga lo trae como siempre, abrirlo después no lo pide, y otra carga (tirar para actualizar) sí. */
    @Test
    fun sinAbrirElChatLaCargaLoTraeYOtraCargaLoVuelveATraer() = enUnHilo { alcance ->
        val t = transporte(CompletableDeferred(Unit))
        val m = modelo(t, alcance)
        m.cargar()
        assertEquals(1, pedidosDelHilo(t))
        assertEquals(listOf("m1"), m.chat.value!!.hilo.value.mensajes.map { it.id })
        m.chat.value!!.alAbrir()
        assertEquals(1, pedidosDelHilo(t))
        m.cargar()
        assertEquals(2, pedidosDelHilo(t))
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
    }
}
