package com.pumpteam.mypump.datos

import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión adversarial del 14-oct, hallazgos 3 y 4 (RevisionDiaNuevoTests.swift): con la app abierta de un día para otro
 * (o de una semana para la otra) y sin señal, lo de ayer no puede quedar como si fuera de hoy. Un toque sobre los 8 vasos
 * de ayer encolaba 9 para hoy, y el check de la semana pasada se veía "Enviado" (o quedaba listo para mandarse de nuevo).
 */
class RevisionDiaNuevoTest {
    private class Servidor {
        @Volatile var conRed = true
        @Volatile var habitos = """[{"fecha":"2026-10-13","entrenamiento":"entrene","vasos_agua":8}]"""
        @Volatile var check = """[{"semana_lunes":"2026-10-12","energia":4,"descanso":3,"hambre":2,"adherencia":5,"nota":"me molestó el hombro"}]"""
    }

    private class Reloj(@Volatile var hoy: String)

    private fun modelo(s: Servidor, reloj: Reloj, alcance: CoroutineScope): Pair<ModeloRevision, Outbox> {
        val t = TransporteProgramado { fn, _ ->
            if (!s.conRed) throw IOException("sin conexión a internet")
            when (fn) {
                "mypump_get_habitos_dia" -> 200 to s.habitos
                "mypump_get_checkin_semana" -> 200 to s.check
                "mypump_get_streak" -> 200 to """[{"streak":3}]"""
                else -> 200 to "[]"
            }
        }
        val cola = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { _ ->
            ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin red")))
        }
        val m = ModeloRevision(ClienteRpc(transporte = t), "tok", cola, alcance)
        m.diaDeHoy = { reloj.hoy }
        return m to cola
    }

    @Test
    fun losHabitosDeAyerNoSonLosDeHoy() = enUnHilo { alcance ->
        val s = Servidor()
        val reloj = Reloj("2026-10-13")
        val (m, cola) = modelo(s, reloj, alcance)
        m.cargarMiDia()
        assertTrue(m.habitos.value.vasosAgua == 8 && m.habitos.value.entrenamiento == "entrene")
        // Medianoche con la app abierta, y sin señal.
        reloj.hoy = "2026-10-14"
        s.conRed = false
        m.cargarMiDia()
        assertEquals(HabitosHoy(), m.habitos.value)
        assertTrue(m.miDiaCargado.value)   // se puede marcar igual: sale por la cola
        m.cambiarAgua(1)
        // Se guarda 600 ms después del último toque.
        var op: Operacion? = null
        repeat(50) {
            if (op == null) {
                delay(100)
                op = cola.pendientesPorClave()["habito|2026-10-14|vasos_agua"]
            }
        }
        assertEquals("1", op?.payload?.get("valor")?.comoTexto)   // antes: 9 (los 8 de ayer + 1)
    }

    @Test
    fun mismoDiaSinRedConservaLoDeHoy() = enUnHilo { alcance ->
        val s = Servidor()
        val (m, _) = modelo(s, Reloj("2026-10-13"), alcance)
        m.cargarMiDia()
        s.conRed = false
        m.cargarMiDia()
        assertEquals(8, m.habitos.value.vasosAgua)
    }

    @Test
    fun elCheckDeLaSemanaPasadaNoQuedaEnviado() = enUnHilo { alcance ->
        val s = Servidor()
        val reloj = Reloj("2026-10-18")   // domingo
        val (m, _) = modelo(s, reloj, alcance)
        m.cargarRevision()
        assertTrue(m.checkinEnviado)
        reloj.hoy = "2026-10-19"           // lunes, sin señal
        s.conRed = false
        m.cargarRevision()
        assertNull(m.checkin.value)
        assertFalse(m.checkinEnviado)
        assertEquals("2026-10-19", m.semana)
    }

    @Test
    fun unCheckMandadoSinSenalSeVeEnviado() = enUnHilo { alcance ->
        val s = Servidor()
        s.check = "[]"
        val (m, _) = modelo(s, Reloj("2026-10-20"), alcance)
        m.cargarRevision()
        assertFalse(m.checkinEnviado)
        m.enviarCheckin(Checkin(mapOf("energia" to 3, "descanso" to 3, "hambre" to 3, "adherencia" to 3), "bien"))
        // Otra carga con el servidor todavía sin el check (la cola no salió): lo pendiente gana.
        m.cargarRevision()
        assertTrue(m.checkinEnviado)
        assertEquals("bien", m.checkin.value?.nota)
    }
}
