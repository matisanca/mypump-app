package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.MensajeChat
import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

private fun fila(id: String, autor: String, texto: String, fecha: String, leido: Boolean? = null): MensajeChat {
    val o = linkedMapOf<String, ValorJson>("id" to texto(id), "autor" to texto(autor), "contenido" to texto(texto), "created_at" to texto(fecha))
    if (leido != null) o["leido_por_cliente"] = ValorJson.Booleano(leido)
    return MensajeChat.desde(ValorJson.Objeto(o).aJson())
}

private fun optimista(id: String, texto: String, fecha: String) =
    BurbujaChat(id = id, autor = "cliente", contenido = texto, leidoPorCliente = null, createdAt = fecha, pendiente = true)

/** `chatMerge` de la web, con los casos de ChatTests.swift. */
class ChatTest {
    @Test
    fun noRepiteYOrdenaPorFecha() {
        // get_chat devuelve de la más nueva a la más vieja.
        val m = HiloChat().mezclar(
            listOf(
                fila("3", "coach", "dale", "2026-10-13T10:02:00.123456+00:00"),
                fila("2", "cliente", "hola", "2026-10-13T10:01:00+00:00"),
                fila("1", "coach", "buenas", "2026-10-13T10:00:00.5+00:00"),
            ),
        )
        assertEquals(3, m.entraron)
        assertEquals(listOf("1", "2", "3"), m.hilo.mensajes.map { it.id })
        assertEquals("2026-10-13T10:02:00.123456+00:00", m.hilo.cursor)
        // El sondeo y la paginación se solapan: la misma fila no entra dos veces.
        val repetidas = m.hilo.mezclar(listOf(fila("3", "coach", "dale", "2026-10-13T10:02:00.123456+00:00")))
        assertEquals(0, repetidas.entraron)
        assertEquals(3, repetidas.hilo.mensajes.size)
    }

    @Test
    fun laFilaRealSeLlevaTodasLasOptimistasDelMismoTexto() {
        val h = HiloChat()
            .agregarPendiente(optimista("tmp_1", "ya entrené", "2026-10-13T12:00:00.000Z"))
            .agregarPendiente(optimista("tmp_2", "ya entrené", "2026-10-13T12:00:01.000Z"))
            .mezclar(listOf(fila("9", "cliente", "ya entrené", "2026-10-13T12:00:02+00:00"))).hilo
        assertEquals(listOf("9"), h.mensajes.map { it.id })
        assertEquals("2026-10-13T12:00:02+00:00", h.cursor)
    }

    @Test
    fun elCursorIgnoraLasPendientes() {
        val h = HiloChat()
            .mezclar(listOf(fila("1", "coach", "hola", "2026-10-13T10:00:00+00:00"))).hilo
            .agregarPendiente(optimista("tmp", "x", "2026-10-13T11:00:00.000Z"))
            .mezclar(emptyList()).hilo
        assertEquals("2026-10-13T10:00:00+00:00", h.cursor)
    }

    @Test
    fun fallidoYReintento() {
        val h = HiloChat().agregarPendiente(optimista("tmp", "x", "2026-10-13T11:00:00.000Z")).marcarFallido("x")
        assertTrue(h.mensajes[0].fallo)
        val (despues, reintento) = h.desmarcarFallido("tmp")
        assertEquals("x", reintento?.contenido)
        assertFalse(despues.mensajes[0].fallo)
    }

    @Test
    fun sinLeerYMarcarLeidos() {
        val h = HiloChat().mezclar(
            listOf(
                fila("1", "coach", "a", "2026-10-13T10:00:00+00:00", leido = false),
                fila("2", "coach", "b", "2026-10-13T10:01:00+00:00", leido = true),
                fila("3", "cliente", "c", "2026-10-13T10:02:00+00:00"),
            ),
        ).hilo
        assertEquals(1, h.sinLeer)
        val (leido, habia) = h.marcarLeidos()
        assertTrue(habia)
        assertEquals(0, leido.sinLeer)
        assertFalse(leido.marcarLeidos().second)
    }

    @Test
    fun fechasComoJs() {
        assertEquals(1_791_885_600_123.0, FechaIso.ms("2026-10-13T10:00:00.123456+00:00"))
        assertEquals(1_791_885_600_000.0, FechaIso.ms("2026-10-13T07:00:00-03:00"))
        assertEquals(1_791_885_600_000.0, FechaIso.ms("2026-10-13 10:00:00+00"))
        assertEquals(0.0, FechaIso.ms(""))
    }

    @Test
    fun unaFilaQueYaEstabaTraeSuLeido() {
        // get_chat trae el "leído"; chat_nuevos no: la que entró por el sondeo se corrige al recargar.
        val h = HiloChat()
            .mezclar(listOf(fila("m2", "coach", "¿cómo venís?", "2026-10-14T11:00:00+00:00"))).hilo
            .mezclar(listOf(fila("m2", "coach", "¿cómo venís?", "2026-10-14T11:00:00+00:00", leido = false))).hilo
        assertEquals(1, h.sinLeer)
        // Y una fila sin el campo no borra el que ya tenía.
        val sigue = h.mezclar(listOf(fila("m2", "coach", "¿cómo venís?", "2026-10-14T11:00:00+00:00"))).hilo
        assertEquals(1, sigue.sinLeer)
    }
}

/**
 * Revisión del 14-oct, hallazgo 7 (ChatLeidoAlLlegarTests de iOS): lo que manda Mati con el chat abierto llega por
 * `mypump_chat_nuevos`, que no trae `leido_por_cliente`. Antes `marcarLeido` no veía nada sin leer y no avisaba al
 * servidor: Mati lo veía sin leer y el badge volvía a prenderse en el próximo arranque.
 */
class ChatLeidoAlLlegarTest {
    private fun transporte() = TransporteProgramado { fn, _ ->
        when (fn) {
            "mypump_get_chat" -> 200 to """[{"id":"1","autor":"cliente","contenido":"hola","leido_por_cliente":true,"created_at":"2026-10-14T10:00:00+00:00"}]"""
            "mypump_chat_nuevos" -> 200 to """[{"id":"2","autor":"coach","contenido":"¿cómo venís?","created_at":"2026-10-14T10:05:00+00:00"}]"""
            else -> 200 to "true"
        }
    }

    @Test
    fun loNuevoDeMatiConElChatAbiertoSeMarcaEnElServidor() = enUnHilo { alcance ->
        val t = transporte()
        val chat = ModeloChat(ClienteRpc(transporte = t), "tok", null, alcance)
        chat.cargar()
        chat.abierto = true
        chat.sondear()
        assertTrue("mypump_marcar_leidos_cliente" in t.llamadas)
        assertEquals(0, chat.noLeidos.value)
    }

    @Test
    fun conElChatCerradoSumaAlBadgeYNoMarca() = enUnHilo { alcance ->
        val t = transporte()
        val chat = ModeloChat(ClienteRpc(transporte = t), "tok", null, alcance)
        chat.cargar()
        chat.sondear()
        assertFalse("mypump_marcar_leidos_cliente" in t.llamadas)
        assertEquals(1, chat.noLeidos.value)
    }

    /** Abrir el chat con el sondeo andando lo vuelve a arrancar (la espera de 45 s no sigue). */
    @Test
    fun abrirElChatReiniciaElSondeo() = enUnHilo { alcance ->
        val t = transporte()
        val chat = ModeloChat(ClienteRpc(transporte = t), "tok", null, alcance)
        chat.cargar()
        chat.empezarSondeo()
        val antes = chat.sondeoEnCurso
        chat.abierto = true
        assertTrue(chat.sondeoEnCurso != null && chat.sondeoEnCurso !== antes && antes?.isCancelled == true)
        chat.pararSondeo()
        chat.abierto = false
        assertTrue(chat.sondeoEnCurso == null)   // sin sondeo, cerrar no lo arranca
    }
}
