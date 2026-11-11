package com.pumpteam.mypump.guia

import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.reglas.ReglasNovedad
import java.time.Instant
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La guía va grande hasta completar la base, y una novedad va grande 7 días desde `novedad_en` (Mati, 10/11). */
class TamanoGuiaTest {
    private val ahora = Instant.parse("2026-11-20T15:00:00Z")
    private val nuevos = ReglasNovedad.Tarjeta(total = 2, vistos = 0, minutosRestantes = 3.0)
    private fun resumen(total: Int, vistos: Int, en: String?) = ResumenGuia(total, vistos, 3.0, novedadEn = en)

    @Test
    fun conLaBaseCompletaYMasDeSieteDiasVaEnFila() {
        assertTrue(TamanoGuia.vaEnFila(nuevos, resumen(12, 10, "2026-11-10T12:00:00-03:00"), ahora))
    }

    @Test
    fun laNovedadDeLaPrimeraSemanaVaGrande() {
        assertFalse(TamanoGuia.vaEnFila(nuevos, resumen(12, 10, "2026-11-14T12:00:00-03:00"), ahora))
        // Justo a los 7 días todavía grande; pasa a fila después.
        assertFalse(TamanoGuia.vaEnFila(nuevos, resumen(12, 10, "2026-11-13T15:00:00Z"), ahora))
        assertTrue(TamanoGuia.vaEnFila(nuevos, resumen(12, 10, "2026-11-13T14:59:00Z"), ahora))
    }

    @Test
    fun sinTerminarLaGuiaDeBaseVaGrandeAunqueLaNovedadSeaVieja() {
        assertFalse(TamanoGuia.vaEnFila(nuevos, resumen(12, 4, "2026-09-01T12:00:00-03:00"), ahora))
    }

    @Test
    fun sinFechaLegibleOSinSaberCuantosSonVaGrande() {
        assertFalse(TamanoGuia.vaEnFila(nuevos, resumen(12, 10, null), ahora))
        assertFalse(TamanoGuia.vaEnFila(nuevos, resumen(12, 10, "ayer"), ahora))
        assertFalse(TamanoGuia.vaEnFila(ReglasNovedad.Tarjeta(null, 0, null), resumen(12, 10, "2026-09-01T12:00:00-03:00"), ahora))
    }

    @Test
    fun conUnNuevoYaVistoSigueContandoSoloLoQueFalta() {
        val uno = ReglasNovedad.Tarjeta(total = 2, vistos = 1, minutosRestantes = 1.0)
        assertTrue(TamanoGuia.vaEnFila(uno, resumen(12, 11, "2026-11-01T12:00:00-03:00"), ahora))
        assertFalse(TamanoGuia.vaEnFila(uno, resumen(12, 9, "2026-11-01T12:00:00-03:00"), ahora))
    }
}
