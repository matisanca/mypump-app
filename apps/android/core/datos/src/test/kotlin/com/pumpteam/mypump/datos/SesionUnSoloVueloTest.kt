package com.pumpteam.mypump.datos

import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 5 (gemelo de SesionUnSoloVueloTests.swift): al confirmar la primera serie del día salían
 * juntos `asegurarSesion` (la pantalla) y `resolverSesion` (la cola), y cada uno mandaba su `iniciar_sesion`. La web
 * comparte la llamada en vuelo (`_sesionInflight`): acá, un solo vuelo por día y semana para los dos.
 */
class SesionUnSoloVueloTest {
    private val raiz = carpetaTemporal("sesion-vuelo")

    private suspend fun esperar(condicion: suspend () -> Boolean): Boolean {
        repeat(150) {
            if (condicion()) return true
            delay(20)
        }
        return condicion()
    }

    @Test
    fun confirmarLaPrimeraSerieCreaLaSesionUnaSolaVez() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_rutina_activa" -> 200 to "[${filaRutina(semana = 5)}]"
                "mypump_get_sesion_dia" -> 200 to "[]"
                "mypump_iniciar_sesion" -> {
                    delay(100)
                    200 to "\"ses-1\""
                }
                "mypump_registrar_carga" -> 200 to "\"fila-1\""
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raiz, PreferenciasEnMemoria(), alcance)
        m.cargar()
        val e = m.entreno.value!!
        // La carga del motor (restaurar la sesión, el historial, los comentarios) corre aparte: que termine antes de tocar.
        assertTrue(esperar { "mypump_get_comentarios" in t.llamadas })
        e.escribir("jal-d1-0", 0, "reps", "10")
        e.escribir("jal-d1-0", 0, "kg", "60")
        e.confirmarSerie("jal-d1-0", 0) { true }
        assertTrue(esperar { "mypump_registrar_carga" in t.llamadas && m.outbox!!.pendientes() == 0 })
        assertTrue(esperar { e.dia.value.sesionId == "ses-1" })
        assertEquals(1, t.llamadas.count { it == "mypump_iniciar_sesion" }, "la pantalla y la cola crearon cada una la suya")
    }
}
