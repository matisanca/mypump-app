package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.Aproximacion
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** La nota de una serie de preparación del plan llega al alumno sin RIR, salvo reserva clínica (como iOS). */
class NotaPreparacionTest {
    @Test fun laNotaDeLaPreparacionPasaPorSinRir() {
        val plan = listOf(Aproximacion("8", 60.0, nota = "Con RIR 2."), Aproximacion("5", 80.0, nota = "Lento abajo."))
        assertEquals(listOf(null, "Lento abajo."), aproximacionesParaAlumno(plan, "0")?.map { it.nota })
        assertEquals(listOf(null, "Lento abajo."), aproximacionesParaAlumno(plan, null)?.map { it.nota })
        assertEquals(listOf("Con RIR 2.", "Lento abajo."), aproximacionesParaAlumno(plan, "2-3")?.map { it.nota })
        assertNull(aproximacionesParaAlumno(null, "0"))
    }
}
