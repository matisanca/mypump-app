package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.EstructuraDieta
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Gemelo de MetasTests.swift: metas de pasos y ritmo de peso (2.3.0) con los mismos vectores (metas_pasos.json). */
class MetasTest {
    private val v by lazy { Vectores.json(Vectores.publico("metas_pasos")).jsonObject }
    private fun lista(k: String) = v[k]!!.jsonArray.map { it.jsonObject }
    private fun numero(o: JsonObject, k: String): Double? = o[k]?.takeIf { it !is JsonNull }?.jsonPrimitive?.double
    private fun texto(o: JsonObject, k: String): String? = o[k]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content
    private fun pasos(o: JsonObject, k: String): Map<String, Double> = o[k]!!.jsonObject.mapValues { it.value.jsonPrimitive.double }

    @Test
    fun metasDelPlan() {
        val casos = lista("metas")
        assertTrue(casos.size >= 10)
        for (c in casos) {
            val m = MetasPlan.desde(EstructuraDieta.desde(c["estructura"]!!))
            assertEquals(numero(c, "metaPasos")?.toInt(), m.metaPasos, texto(c, "nombre"))
            assertEquals(numero(c, "ritmo"), m.ritmoKgSemana, texto(c, "nombre"))
        }
    }

    @Test
    fun vista() {
        val casos = lista("vista")
        assertTrue(casos.size >= 8)
        for (c in casos) {
            val n = texto(c, "nombre")
            val esp = c["esperado"]!!.jsonObject
            val r = PumpDelDia.vista(pasos(c, "pasos"), numero(c, "meta")!!.toInt(), texto(c, "hoy")!!)!!
            assertEquals(esp["pasosHoy"]!!.jsonPrimitive.int, r.pasosHoy, n)
            assertEquals(esp["fraccion"]!!.jsonPrimitive.double, r.fraccion, 1e-5, n)
            assertEquals(esp["falta"]!!.jsonPrimitive.int, r.falta, n)
            assertEquals(esp["cumplido"]!!.jsonPrimitive.boolean, r.cumplido, n)
            assertEquals(esp["racha"]!!.jsonPrimitive.int, r.racha, n)
            assertEquals(esp["semana"]!!.jsonArray.map { it.jsonPrimitive.content }, r.semana.map { it.estado.clave }, n)
            assertEquals(numero(esp, "promedio7")?.toInt(), r.promedio7, n)
            assertEquals(listOf("L", "M", "M", "J", "V", "S", "D"), r.semana.map { it.inicial })
        }
    }

    @Test
    fun celebrarUnaVezPorDia() {
        for (c in lista("celebrar")) {
            val cel = c["celebrados"]!!.jsonArray.map { it.jsonPrimitive.content }
            val r = PumpDelDia.debeCelebrar(PumpDelDia.Registro(cel), texto(c, "hoy")!!, numero(c, "pasos")!!.toInt(), numero(c, "meta")!!.toInt())
            assertEquals(c["celebra"]!!.jsonPrimitive.boolean, r, texto(c, "nombre"))
        }
    }

    @Test
    fun ritmo() {
        for (c in lista("ritmo")) {
            val n = texto(c, "nombre")
            val serie = pasos(c, "pesos").map { PesoCorporal.Punto(it.key, it.value) }.sortedBy { it.fecha }
            val r = RitmoPeso.resumen(numero(c, "ritmo")!!, serie, texto(c, "hoy")!!)
            val esp = c["esperado"]!!.jsonObject
            assertEquals(texto(esp, "meta"), r.meta, n)
            assertEquals(texto(esp, "tendencia"), r.tendencia, n)
            assertEquals(esp["enRitmo"]!!.jsonPrimitive.boolean, r.enRitmo, n)
        }
        for (c in lista("cantidad")) assertEquals(texto(c, "texto"), RitmoPeso.cantidad(numero(c, "kg")!!))
    }

    @Test
    fun marcarGuardaUnaVezYPoda() {
        var r = PumpDelDia.Registro()
        r = PumpDelDia.marcar(r, "2026-11-10")
        r = PumpDelDia.marcar(r, "2026-11-10")
        assertEquals(listOf("2026-11-10"), r.celebrados)
        assertFalse(PumpDelDia.debeCelebrar(r, "2026-11-10", 20000, 10000))
        for (i in 0 until 80) r = PumpDelDia.marcar(r, DiaCalendario.texto(21_000L + i))
        assertEquals(60, r.celebrados.size)
        assertEquals(DiaCalendario.texto(21_079L), r.celebrados.last())
    }

    /** El cambio de día con la zona del teléfono: las 23:30 en Buenos Aires ya son mañana en Madrid. */
    @Test
    fun hoyDependeDeLaZona() {
        val instante = Instant.ofEpochSecond(1_762_828_200)
        val hoyBA = instante.atZone(ZoneId.of("America/Argentina/Buenos_Aires")).toLocalDate().toString()
        val hoyMadrid = instante.atZone(ZoneId.of("Europe/Madrid")).toLocalDate().toString()
        assertEquals("2025-11-10", hoyBA)
        assertEquals("2025-11-11", hoyMadrid)
        val r = PumpDelDia.marcar(PumpDelDia.Registro(), hoyMadrid)
        assertFalse(PumpDelDia.debeCelebrar(r, hoyBA, 12000, 10000))
    }

    @Test
    fun textosSinDosPuntosNiGuiones() {
        val vi = PumpDelDia.vista(mapOf("2026-11-12" to 7420.0), 10000, "2026-11-12")!!
        val todos = listOf(PumpDelDia.deMeta(vi), PumpDelDia.estado(vi), PumpDelDia.racha(3)!!, PumpDelDia.sinSalud(10000),
            PumpDelDia.CONECTAR, PumpDelDia.CONECTAR_BOTON, PumpDelDia.celebracion(10000), PumpDelDia.celebracionRacha(4)!!,
            PumpDelDia.lineaSalud(10000, 8700), RitmoPeso.textoMeta(-0.5), RitmoPeso.EN_RITMO)
        for (t in todos) {
            assertFalse(t.contains(":") || t.contains(" - ") || t.contains("—"), t)
            assertFalse(t.lowercase().contains("coach") || t.lowercase().contains("entrenador") || t.contains("IA"), t)
        }
        assertEquals("Te faltan 2.580 pasos", PumpDelDia.estado(vi))
        assertEquals("Meta 10.000 pasos por día, tu promedio 8.700", PumpDelDia.lineaSalud(10000, 8700))
    }
}
