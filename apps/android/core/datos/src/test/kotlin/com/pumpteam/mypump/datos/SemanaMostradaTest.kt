package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

/**
 * GEN-02: el "SEM x/y" del encabezado con el `semana_offset` del macrociclo (cliente.html:8862-8865). En el segundo bloque
 * de un plan de 12 semanas (offset 12), la semana 5 se muestra "SEM 17/24", y lo que se escribe sigue siendo la 5: el
 * offset solo cambia rótulos (ENT-09).
 */
class SemanaMostradaTest {
    private fun rutina(semanaActual: Int, offset: String) = RutinaActiva.desde(
        ValorJson.parsear(
            """{"id":"rut-macro","version":1,"semana_actual":$semanaActual,"estructura":{"semanas_total":12,"semana_offset":$offset,"dias":[
              {"id":"d1","n":1,"nombre":"TIRÓN","bloques":[{"titulo":"A","ejercicios":[
                {"id":"jal-d1-0","nombre":"Jalón al pecho","tipo":"compuesto","progresion":[{"semana":1,"series":2,"reps":"10","rir":"1"}]}]}]}]}}""",
        ).aJson(),
    )

    @Test
    fun conOffsetElEncabezadoSigueLaCuentaDelMacrociclo() = enUnHilo { alcance ->
        val m = Banco(alcance).modelo(rutina(5, "12"))
        assertEquals(5, m.semana)   // la que se escribe
        assertEquals(17, m.semanaMostrada)
        assertEquals(24, m.totalMostrado)
        assertEquals("Pasar a Semana 18 →", m.botonAvanzar)
        assertEquals("Pasar a Semana 18", m.preguntaAvanzar?.titulo)
    }

    @Test
    fun laPrimeraSemanaDelSegundoBloqueEsLaTrece() = enUnHilo { alcance ->
        // `semana_actual || 1` y `Number(est.semana_offset) || 0`, como la web: la semana 0 es la 1 y el offset puede
        // venir como texto.
        val m = Banco(alcance).modelo(rutina(0, "\"12\""))
        assertEquals(1, m.semana)
        assertEquals(13, m.semanaMostrada)
        assertEquals(24, m.totalMostrado)
        // La de calibración es solo la semana 1 del primer macrociclo.
        assertFalse(m.banner.calibracion)
    }
}
