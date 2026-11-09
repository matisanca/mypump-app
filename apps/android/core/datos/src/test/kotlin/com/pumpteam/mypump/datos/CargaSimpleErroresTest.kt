package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.ClaveEjercicio
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Los tres errores de producción que corrige la carga simple (2.3.0; gemelo de CargaSimpleErroresTests.swift). Están escritos
// contra la API que ya existía: fallaron sobre la 2.2.0 (la corrida está en nativa-evidencia/logs) y pasan con el arreglo.

class CargaSimpleErroresTest {
    private val lugar = "jal-d1-0"

    /** 80 kg × 10 la vez pasada, en la serie 1 y en la 2. */
    private fun conHistorial(b: Banco): ModeloEntreno {
        fun fila(n: Int) = """{"clave":"${ClaveEjercicio.de("Jalón al pecho")}","ejercicio_id":"$lugar","registrado_en":"2026-10-07T18:00:00Z","peso_kg":80,"reps_realizadas":10,"rir_real":1,"serie_numero":$n,"notas":null,"ejercicio_nombre":"Jalón al pecho"}"""
        b.servidor.cuando("get_historico_por_clave", "[${fila(1)},${fila(2)}]")
        return b.modelo()
    }

    private suspend fun pesosEnCola(b: Banco): List<Double?> =
        b.cola.operaciones().filter { it.kind == "carga" }.map { it.payload["datos"]?.get("peso")?.comoNumero }

    private fun serie(m: ModeloEntreno, i: Int) = m.dia.value.ejercicios.getValue(lugar).series[i]

    @Test
    fun subirElKiloEnLa1YTildeEnLa2GrabaElKiloNuevo() = enUnHilo { alcance: CoroutineScope ->
        val b = Banco(alcance)
        val m = conHistorial(b)
        m.precargarHistorial()
        m.escribir(lugar, 0, "kg", "82.5")
        m.escribir(lugar, 0, "reps", "10")
        m.confirmarSerie(lugar, 0) { true }
        m.confirmarSerie(lugar, 1) { true }
        assertEquals("82.5", serie(m, 1).kg, "grababa los 80 de la semana pasada")
        assertEquals(listOf<Double?>(82.5, 82.5), pesosEnCola(b))
    }

    @Test
    fun cambiarSoloLasRepsDeLa1NoPideElKilo() = enUnHilo { alcance: CoroutineScope ->
        val b = Banco(alcance)
        val m = conHistorial(b)
        m.precargarHistorial()
        m.escribir(lugar, 0, "reps", "11")
        m.confirmarSerie(lugar, 0) { true }
        val s = serie(m, 0)
        assertTrue(s.confirmada, "no dejaba confirmar sin escribir el kilo")
        assertEquals("80" to "11", s.kg to s.reps)
    }

    /**
     * Tocar una serie hecha la desmarcaba en el teléfono, pero el servidor no la borra y al recargar volvía: ahora abre la
     * corrección y la serie sigue hecha, sin prometer un borrado que no ocurre.
     */
    @Test
    fun desmarcarNoPrometeUnBorradoQueNoOcurre() = enUnHilo { alcance: CoroutineScope ->
        val b = Banco(alcance)
        val m = conHistorial(b)
        m.precargarHistorial()
        m.escribir(lugar, 0, "reps", "10")
        m.escribir(lugar, 0, "kg", "80")
        m.confirmarSerie(lugar, 0) { true }
        m.editarSerie(lugar, 0)
        assertTrue(serie(m, 0).confirmada, "la desmarcaba y al recargar volvía")
    }
}
