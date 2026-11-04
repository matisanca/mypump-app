package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** «Tu guía»: la respuesta de `entregas_app_get` y de `entregas_app_resumen` (fixtures en `apps/shared/fixtures/guia`). */
class GuiaTest {
    private fun fixture(n: String) = Json.parseToJsonElement(Rutas.leer(Rutas.compartido("fixtures/guia/$n.json")))

    @Test
    fun decodificaLaGuiaEntera() {
        val g = Guia.desde(fixture("get-marcelo"))
        assertNotNull(g)
        g!!
        assertEquals("Marcelo", g.nombrePila)
        assertNull(g.fechaEntrega)
        assertEquals(20, g.clips.size)
        assertEquals(5, g.clips.map { it.bloque }.distinct().size)
        val c = g.clips.first()
        assertEquals("FT-25a", c.id)
        assertEquals(0.7, c.minutos)
        assertFalse(c.visto)
        assertTrue(c.sePuedeVer)
        val s = g.suplementacion!!
        assertEquals(7, s.items.size)
        assertEquals(4, s.dia.size)
        assertEquals(3, s.items.count { it.videoId != null })
        assertEquals(listOf("Que diga *L-citrulina* sola.", "Mezclala con agua."), s.items[1].detalle)
        assertEquals(listOf("Seguí con la que venís usando."), s.items[0].detalle)
        assertEquals(2, s.items[0].tomas.size)
        assertTrue(s.items[4].opcional)
    }

    @Test
    fun conAvanceDudasYUnVideoSinSubir() {
        val g = Guia.desde(fixture("get-marcelo-avanzado"))!!
        assertEquals(4, g.clips.count { it.visto })
        assertEquals(12, g.clips[4].segundos)
        assertEquals("¿Puedo cambiar el orden de los ejercicios?", g.clips[4].duda)
        assertFalse(g.clips[19].sePuedeVer)
        assertEquals(2, g.dudasLlamada.size)
        assertEquals("2026-11-06T14:00:00-03:00", g.fechaEntrega)
    }

    @Test
    fun sinGuiaEsNull() {
        assertNull(Guia.desde(fixture("sin-guia")))
        assertNull(Guia.desde(Json.parseToJsonElement("false")))
        assertNull(Guia.desde(Json.parseToJsonElement("null")))
        assertNull(Guia.desde(Json.parseToJsonElement("""{"ok":"true","clips":[]}""")))
        assertNull(ResumenGuia.desde(fixture("sin-guia")))
    }

    @Test
    fun toleraCamposQueFaltanONulos() {
        val g = Guia.desde(
            Json.parseToJsonElement(
                """{"ok":true,"clips":[null,{"id":"a"},{"titulo":"sin id"},{"id":"b","titulo":" ¿Qué? ","minutos":"0,5","visto":null,
                "segundos":"12","duda":"","bloque":null,"url":""},{"id":"c","titulo":"x","minutos":-3,"segundos":-1,"visto":1}],
                "dudas_llamada":null,"suplementacion":{"items":[]}}""",
            ),
        )!!
        assertNull(g.nombrePila)
        assertEquals(listOf("b", "c"), g.clips.map { it.id })
        val b = g.clips[0]
        assertEquals("¿Qué?", b.titulo)
        assertEquals(0.5, b.minutos)
        assertEquals(12, b.segundos)
        assertNull(b.duda)
        assertNull(b.bloque)
        assertFalse(b.sePuedeVer)
        assertEquals(0.0, g.clips[1].minutos)
        assertEquals(0, g.clips[1].segundos)
        assertTrue(g.clips[1].visto)
        assertTrue(g.dudasLlamada.isEmpty())
        assertNull(g.suplementacion)
    }

    @Test
    fun laCacheSeLeeIgual() {
        val g = Guia.desde(fixture("get-marcelo-avanzado"))!!
        val vuelta = Guia.desde(g.aValor())
        assertEquals(g.copy(suplementacion = null), vuelta!!.copy(suplementacion = null))
        assertEquals(g.suplementacion!!.items, vuelta.suplementacion!!.items)
    }

    @Test
    fun resumen() {
        val r = ResumenGuia.desde(fixture("resumen-marcelo"))!!
        assertEquals(ResumenGuia(20, 4, 11.6), r)
        assertEquals(r, ResumenGuia.desde(r.aValor()))
        assertNull(ResumenGuia.desde(Json.parseToJsonElement("""{"ok":true,"total":0}""")))
        assertEquals(ResumenGuia(3, 3, 0.0), ResumenGuia.desde(Json.parseToJsonElement("""{"ok":true,"total":3,"vistos":9}""")))
        val g = Guia.desde(fixture("get-marcelo-avanzado"))!!
        val local = ResumenGuia.de(g)!!
        assertEquals(20, local.total)
        assertEquals(4, local.vistos)
        assertEquals(Math.round(g.clips.filter { !it.visto }.sumOf { it.minutos } * 10) / 10.0, local.minutosRestantes)
    }
}
