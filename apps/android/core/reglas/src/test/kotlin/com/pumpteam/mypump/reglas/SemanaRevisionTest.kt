package com.pumpteam.mypump.reglas

import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Gemelo de SemanaRevisionTests.swift: la semana de revisión y el día del aviso (R2 de la 2.0.3), con los mismos vectores. */
class SemanaRevisionTest {
    @Test
    fun vectores() {
        val casos = Vectores.json(Vectores.publico("aviso_revision"))["casos"]!!.jsonArray.map { it.jsonObject }
        assertTrue(casos.isNotEmpty())
        for (c in casos) {
            val hoy = c["hoy"]!!.jsonPrimitive.content
            val (h, m) = c["hora"]!!.jsonPrimitive.content.split(":").map { it.toInt() }
            val dia = c["revisionDia"]!!.jsonPrimitive.int
            val completa = c["completa"]!!.jsonPrimitive.boolean
            assertEquals(c["semana"]!!.jsonPrimitive.content, FotosProgreso.lunes(hoy), "$hoy día $dia")
            assertEquals(c["aviso"]!!.jsonPrimitive.content, SemanaRevision.fechaAviso(hoy, h * 60 + m, completa, dia), "$c")
        }
    }

    @Test
    fun elTextoDelDiaSoloApareceParaQuienNoRevisaElDomingo() {
        assertEquals(null, SemanaRevision.textoDia(7))
        assertEquals(null, SemanaRevision.textoDia(null))
        assertEquals(null, SemanaRevision.textoDia(99))
        assertEquals("Tu día de revisión es el sábado", SemanaRevision.textoDia(6))
        assertEquals("Tu día de revisión es el lunes", SemanaRevision.textoDia(1))
    }

    /** Un alumno del sábado: el domingo es todavía la misma semana, y lo cargado ese domingo no le adelanta el próximo aviso. */
    @Test
    fun elDomingoSigueSiendoDeLaMismaSemana() {
        assertEquals("2026-11-07", SemanaRevision.fechaAviso("2026-11-01", 600, true, 6))
        assertEquals("2026-11-07", SemanaRevision.fechaAviso("2026-10-30", 600, true, 6))
        assertEquals("2026-10-31", SemanaRevision.fechaAviso("2026-10-30", 600, false, 6))
    }

    @Test
    fun completaEsLoMismoQueElBadgeEnCero() {
        val todas = setOf("frente", "perfil", "espalda")
        assertTrue(SemanaRevision.completa(true, todas))
        assertFalse(SemanaRevision.completa(false, todas))
        assertFalse(SemanaRevision.completa(true, setOf("frente", "perfil")))
        assertFalse(SemanaRevision.completa(false, emptySet()))
    }

    @Test
    fun unDiaRaroValeElDomingo() {
        assertEquals(7, SemanaRevision.normalizado(null))
        assertEquals(7, SemanaRevision.normalizado(0))
        assertEquals(7, SemanaRevision.normalizado(8))
        assertEquals(6, SemanaRevision.normalizado(6))
        assertEquals("2026-11-01", SemanaRevision.fechaAviso("2026-10-31", 600, false, 99))
        assertNull(SemanaRevision.fechaAviso("no es fecha", 600, false))
    }
}
