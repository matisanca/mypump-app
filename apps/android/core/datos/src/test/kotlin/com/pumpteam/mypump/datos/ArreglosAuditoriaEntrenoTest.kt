package com.pumpteam.mypump.datos

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de ArreglosAuditoriaEntrenoTests.swift. Auditoría del 10/11, F1: las series que ya subieron solo las conocía el
// servidor. Al reabrir la app sin señal se veían vacías y un toque en OK pisaba la buena con una cargada de memoria.
class ArreglosAuditoriaEntrenoTest {
    @Test
    fun serieSubidaSeVeAlReabrirSinRed() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-1", iniciada = "2026-10-14T17:30:00Z"))
        b.servidor.cuando("registrar_carga", "\"fila-1\"")
        val m = b.modelo()
        m.restaurarSesion()
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        m.confirmarSerie("jal-d1-0", 0) { true }
        b.cola.drenar()
        assertEquals(0, b.cola.pendientes(), "la serie ya subió")

        // La app se cierra y se abre sin señal: el servidor no contesta nada.
        for (fn in listOf("get_sesion_dia", "get_registros_sesion", "get_ejercicios_estado")) b.servidor.sinRed(fn)
        val otra = b.modelo()
        otra.restaurarSesion()
        val s = otra.dia.value.ejercicios["jal-d1-0"]!!.series.first()
        assertTrue(s.confirmada && s.kg == "60" && s.reps == "10", "$s")
        assertTrue(otra.seriesSinConfirmar.value)
    }

    @Test
    fun conRespuestaDelServidorMandaElServidor() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-1", iniciada = "2026-10-14T17:30:00Z"))
        b.servidor.cuando("registrar_carga", "\"fila-1\"")
        val m = b.modelo()
        m.restaurarSesion()
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        m.confirmarSerie("jal-d1-0", 0) { true }
        b.cola.drenar()
        b.servidor.cuando(
            "get_registros_sesion",
            """[{"ejercicio_id":"jal-d1-0","serie":1,"peso_kg":62.5,"reps":10,"registrado_en":"2026-10-14T18:00:00Z"}]""",
        )
        val otra = b.modelo()
        otra.restaurarSesion()
        assertEquals("62.5", otra.dia.value.ejercicios["jal-d1-0"]!!.series.first().kg)
        assertFalse(otra.seriesSinConfirmar.value)
    }

    @Test
    fun loAnotadoViejoSePoda() {
        val viejo = ModeloEntreno.EscrituraAnotada("carga", com.pumpteam.mypump.modelos.ValorJson.Nulo, AHORA - 8 * 24 * 3600 * 1000, "r")
        val nuevo = ModeloEntreno.EscrituraAnotada("carga", com.pumpteam.mypump.modelos.ValorJson.Nulo, AHORA - 3600 * 1000, "r")
        assertEquals(setOf("b"), podarAnotadas(mapOf("a" to viejo, "b" to nuevo), AHORA).keys)
    }
}
