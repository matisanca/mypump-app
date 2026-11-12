package com.pumpteam.mypump.reglas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** 2.3.1: el código de la reunión, el respaldo de «Entrar» (gemelo de CodigoMeetTests de iOS). */
class CodigoMeetTest {
    private fun codigo(s: String?) = ReglasAgenda.codigoMeet(s)

    @Test
    fun elCodigoSaleDelLink() {
        assertEquals("abc-defg-hij", codigo("https://meet.google.com/abc-defg-hij"))
        assertEquals("abc-defg-hij", codigo(" https://meet.google.com/abc-defg-hij/ "))
        assertEquals("abc-defg-hij", codigo("https://meet.google.com/ABC-DEFG-HIJ?authuser=1&hs=122"))
        assertEquals("abc-defg-hij", codigo("https://MEET.google.com/abc-defg-hij#x"))
        assertEquals("abc-defg-hij", codigo("https://www.meet.google.com/abc-defg-hij"))
    }

    @Test
    fun sinGuionesLosPone() = assertEquals("abc-defg-hij", codigo("https://meet.google.com/abcdefghij"))

    @Test
    fun loQueNoEsUnaReunionDaNull() {
        listOf(
            null, "", "http://meet.google.com/abc-defg-hij", "https://meet.google.com/", "https://meet.google.com",
            "https://meet.google.com/abc", "https://meet.google.com/new", "https://meet.google.com/lookup/abc-defg-hij",
            "https://meet.google.com/abcd-efg-hij", "https://meet.google.com/abc-defg-hi1", "https://meet.google.com/abc-defg-hijk",
            "https://meet.google.com.evil.com/abc-defg-hij", "https://evil.com/abc-defg-hij", "https://meet.google.com/abc-dé-fghij",
        ).forEach { assertNull(codigo(it), "$it") }
    }

    @Test
    fun losTextosDelRespaldoNombranAMati() {
        val todos = listOf(
            ReglasAgenda.TITULO_CODIGO, ReglasAgenda.TEXTO_COPIAR_CODIGO, ReglasAgenda.TEXTO_CODIGO_COPIADO,
            ReglasAgenda.TEXTO_PEGAR_CODIGO,
        ) + ReglasAgenda.AYUDA_ENTRAR
        todos.forEach {
            assertFalse(it.lowercase().contains("entrenador"), it)
            assertFalse(it.lowercase().contains("whatsapp"), it)
            assertFalse(it.contains("IA"), it)
        }
        assertTrue(ReglasAgenda.AYUDA_ENTRAR.any { it.contains("Unirse con un código") })
    }
}
