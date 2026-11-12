package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.Progresion
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** 2.3.1: el slug de cinta gana sobre el tipo y el cardio con progresión por tiempo no arma filas. Gemelo de Cardio231Tests.swift. */
class Cardio231Test {
    @Test fun elSlugDeCardioGanaSobreElTipo() {
        assertTrue(ReglasEjercicio.esCardio("Cinta", "compuesto", listOf("walking_treadmill")))
        assertTrue(ReglasEjercicio.esCardio("Lo que sea", "accesorio", listOf(null, "Elliptical_Trainer")))
        assertFalse(ReglasEjercicio.esCardio("Cinta", "compuesto", emptyList()), "el nombre solo respeta el tipo")
        assertTrue(ReglasEjercicio.esCardio("Cinta", "calentamiento", emptyList()))
        assertFalse(ReglasEjercicio.esCardio("Press banca", "compuesto", listOf("bench_press")))
    }

    @Test fun repsQueSonTiempo() {
        for (r in listOf("10 min", "10min", "20'", "30 s", "45 seg", "1 h", "15-20 min", "12 minutos", "8,5 min")) assertTrue(ReglasEjercicio.repsEsTiempo(r), r)
        for (r in listOf("12", "8-10", "6 × 30 s / 30 s", "AMRAP", "", "10 reps", null)) assertFalse(ReglasEjercicio.repsEsTiempo(r), "$r")
    }

    @Test fun laCintaConProgresionPorTiempoNoArmaFilas() {
        val cinta = Ejercicio("c", "Cinta", "cardio", progresion = listOf(Progresion(1, 1, "10 min"), Progresion(2, 3, "12 min", "1")))
        assertEquals(Pauta(null, "12 min", null), Progresiones.pauta(cinta, 2))
        assertNull(Progresiones.pauta(cinta.copy(tipo = "compuesto", catalogoSlug = "Walking_Treadmill"), 1).series)
        val intervalos = Ejercicio("b", "Bici", "cardio", progresion = listOf(Progresion(1, 6, "6 × 30 s / 30 s")))
        assertEquals(6, Progresiones.pauta(intervalos, 1).series, "los intervalos siguen con las series del plan")
        val plancha = Ejercicio("p", "Plancha", "core", progresion = listOf(Progresion(1, 3, "30 s")))
        assertEquals(3, Progresiones.pauta(plancha, 1).series, "la plancha por tiempo sigue con series")
    }
}
