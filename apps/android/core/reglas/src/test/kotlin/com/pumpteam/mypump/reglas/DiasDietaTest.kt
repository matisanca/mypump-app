package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.ComidaLibre
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CopiaDeComidas.Estado.CONFLICTO
import com.pumpteam.mypump.reglas.CopiaDeComidas.Estado.IGUAL
import com.pumpteam.mypump.reglas.CopiaDeComidas.Estado.NUEVA
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Los días que se pueden cargar en Dieta y copiar a hoy. Gemelo de DiasDietaTests.swift. */
class DiasDietaTest {
    @Test
    fun seleccionablesHoyYSieteAtras() {
        val f = DiasDieta.seleccionables("2026-11-09", "2026-11-09")
        assertEquals(8, f.size)
        assertEquals("2026-11-09", f.first())
        assertEquals("2026-11-02", f.last())
    }

    @Test
    fun unTelefonoAtrasadoNoOfreceUnDiaQueLaBaseRechaza() {
        // En Argentina ya es el 10: el 2 quedó afuera de −7.
        val f = DiasDieta.seleccionables("2026-11-09", "2026-11-10")
        assertEquals("2026-11-09", f.first())
        assertEquals("2026-11-03", f.last())
    }

    @Test
    fun cruzaElMesYElAnio() {
        assertEquals("2025-12-30", DiasDieta.sumar("2026-01-02", -3))
        assertEquals("2026-02-28", DiasDieta.sumar("2026-03-01", -1))
    }

    @Test
    fun ventanaDeMarcar() {
        assertTrue(DiasDieta.permiteMarcar("2026-11-07", "2026-11-09", 2))
        assertFalse(DiasDieta.permiteMarcar("2026-11-06", "2026-11-09", 2))
        assertTrue(DiasDieta.permiteMarcar("2026-11-02", "2026-11-09", 7))
        assertFalse(DiasDieta.permiteMarcar("2026-11-10", "2026-11-09", 7))
    }

    @Test
    fun rotulos() {
        assertEquals("Hoy", DiasDieta.rotuloCorto("2026-11-09", "2026-11-09"))
        assertEquals("Ayer", DiasDieta.rotuloCorto("2026-11-08", "2026-11-09"))
        assertEquals("Sáb 7", DiasDieta.rotuloCorto("2026-11-07", "2026-11-09"))
        assertEquals("sábado 7 de noviembre", DiasDieta.rotuloLargo("2026-11-07"))
    }

    // ── Copia ──

    private fun comida(id: String, opciones: List<String> = listOf("A", "B"), alimentos: Int = 2): Comida {
        val foods = (0 until alimentos).joinToString(",") { """{"name":"x$it","qty":100,"unit":"g","kcal":100,"prot":10,"carb":10,"fat":1}""" }
        val ops = opciones.joinToString(",") { """{"name":"$it","foods":[$foods]}""" }
        return Comida.desde(ValorJson.parsear("""{"id":"$id","name":"$id","options":[$ops]}""").aJson())
    }

    private fun libre(id: String, desc: String, kcal: Double) = ComidaLibre(id, null, null, desc, kcal, null, null, null, null)

    private fun plan(
        c: List<Comida>,
        om: Map<String, MarcaComida> = emptyMap(),
        oa: Map<String, AjusteComida> = emptyMap(),
        ol: List<ComidaLibre> = emptyList(),
        hm: Map<String, MarcaComida> = emptyMap(),
        ha: Map<String, AjusteComida> = emptyMap(),
        hl: List<ComidaLibre> = emptyList(),
        otro: Boolean = false,
    ) = CopiaDeComidas.plan(c, om, oa, ol, hm, ha, hl, otro) { _, _, _, _ -> 500.0 }

    @Test
    fun seCopiaLoComidoNoLoSalteadoNiLoOmitido() {
        val c = listOf(comida("d"), comida("a"), comida("m"))
        val p = plan(
            c,
            om = mapOf("d" to MarcaComida("B", MarcaComida.Estado.COMIDO, listOf(1)), "a" to MarcaComida("A", MarcaComida.Estado.SALTADO)),
            oa = mapOf("m" to AjusteComida(omitida = true)),
        )
        assertEquals(listOf("d"), p.comidas.map { it.comidaId })
        assertEquals(1, p.comidas[0].opcion)
        assertEquals(listOf(1), p.comidas[0].marca?.excluidos)
        assertEquals(NUEVA, p.comidas[0].estado)
    }

    @Test
    fun soloAjusteSinMarcaTambienSeOfrece() {
        val a = AjusteComida(deltaKcal = 50, opcion = 1)
        val p = plan(listOf(comida("d")), oa = mapOf("d" to a))
        assertEquals(1, p.comidas.size)
        assertNull(p.comidas[0].marca)
        assertEquals(a, p.comidas[0].ajuste)
        assertEquals(1, p.comidas[0].opcion)
    }

    @Test
    fun loQueHoyTieneAlgoEsConflictoYLoIgualNoSeRepite() {
        val m = MarcaComida("A", MarcaComida.Estado.COMIDO)
        val c = listOf(comida("d"), comida("a"))
        val p = plan(c, om = mapOf("d" to m, "a" to m), hm = mapOf("d" to m, "a" to MarcaComida("B", MarcaComida.Estado.COMIDO)))
        assertEquals(IGUAL, p.comidas.first { it.comidaId == "d" }.estado)
        assertEquals(CONFLICTO, p.comidas.first { it.comidaId == "a" }.estado)
    }

    @Test
    fun unaOpcionQueYaNoExisteNoSeCopia() {
        val p = plan(listOf(comida("d", opciones = listOf("A"))), om = mapOf("d" to MarcaComida("Vieja", MarcaComida.Estado.COMIDO)))
        assertTrue(p.comidas.isEmpty())
    }

    @Test
    fun tildesFueraDeRangoSeCaen() {
        val p = plan(listOf(comida("d", alimentos = 2)), om = mapOf("d" to MarcaComida("A", MarcaComida.Estado.COMIDO, listOf(1, 7))))
        assertEquals(listOf(1), p.comidas[0].marca?.excluidos)
    }

    @Test
    fun cadaLibreDeHoyCubreUnaSolaDelOrigen() {
        val p = plan(emptyList(), ol = listOf(libre("1", "Yogur", 100.0), libre("2", "Yogur", 100.0)), hl = listOf(libre("9", "yogur ", 100.0)))
        assertEquals(listOf(IGUAL, NUEVA), p.libres.map { it.estado })
    }

    @Test
    fun libresRepetidasNoSeDuplican() {
        val p = plan(emptyList(), ol = listOf(libre("1", "Pizza ", 800.0), libre("2", "Helado", 300.0)), hl = listOf(libre("9", "pizza", 800.2)))
        assertEquals(listOf(IGUAL, NUEVA), p.libres.map { it.estado })
    }

    @Test
    fun conOtroPlanSoloLibres() {
        val p = plan(listOf(comida("d")), om = mapOf("d" to MarcaComida("A", MarcaComida.Estado.COMIDO)), ol = listOf(libre("1", "Pizza", 800.0)), otro = true)
        assertTrue(p.comidas.isEmpty())
        assertEquals(1, p.libres.size)
        assertTrue(p.otroPlan)
    }
}
