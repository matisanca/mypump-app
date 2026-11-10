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
 * (o de una semana para la otra) y sin señal, lo de la semana pasada no puede quedar como si fuera de esta: el check de
 * la semana pasada se veía "Enviado" (o quedaba listo para mandarse de nuevo). Lo de Mi Día se fue con Mi Día (2.1).
 */
class RevisionDiaNuevoTest {
    private class Servidor {
        @Volatile var conRed = true
        @Volatile var check = """[{"semana_lunes":"2026-10-12","energia":4,"descanso":3,"hambre":2,"adherencia":5,"nota":"me molestó el hombro"}]"""
    }

    private class Reloj(@Volatile var hoy: String)

    private fun modelo(s: Servidor, reloj: Reloj, alcance: CoroutineScope): Pair<ModeloRevision, Outbox> {
        val t = TransporteProgramado { fn, _ ->
            if (!s.conRed) throw IOException("sin conexión a internet")
            when (fn) {
                "mypump_get_checkin_semana" -> 200 to s.check
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

    /** El día de revisión: lo que manda el servidor, y sin la función (nativa_008 sin aplicar) el domingo. */
    private fun modeloDia(alcance: CoroutineScope, disco: Disco? = null, respuesta: () -> Pair<Int, String>): ModeloRevision {
        val t = TransporteProgramado { fn, _ -> if (fn == "mypump_get_revision_dia") respuesta() else 200 to "[]" }
        return ModeloRevision(ClienteRpc(transporte = t), "tok", null, alcance, disco)
    }

    private val sinFuncion = """{"code":"PGRST202","message":"Could not find the function"}"""

    private fun discoNuevo() = Disco(java.nio.file.Files.createTempDirectory("revdia").toFile())

    @Test
    fun elDiaDeRevisionVieneDelServidor() = enUnHilo { alcance ->
        val m = modeloDia(alcance) { 200 to "6" }
        assertEquals(7, m.revisionDia.value)
        m.cargarRevision()
        assertEquals(6, m.revisionDia.value)
    }

    @Test
    fun sinLaFuncionEnLaBaseEsElDomingo() = enUnHilo { alcance ->
        val m = modeloDia(alcance) { 404 to sinFuncion }
        m.cargarRevision()
        assertEquals(7, m.revisionDia.value)
    }

    @Test
    fun sinRedQuedaElUltimoDiaConocido() = enUnHilo { alcance ->
        val d = discoNuevo()
        modeloDia(alcance, d) { 200 to "6" }.cargarRevision()
        val b = modeloDia(alcance, d) { throw IOException("sin conexión a internet") }
        assertEquals(6, b.revisionDia.value)
        b.cargarRevision()
        assertEquals(6, b.revisionDia.value)
    }

    /** Si la función desaparece (se revirtió la 008), lo guardado no queda pisando el domingo. */
    @Test
    fun alRevertirseLaFuncionVuelveAlDomingo() = enUnHilo { alcance ->
        val d = discoNuevo()
        modeloDia(alcance, d) { 200 to "3" }.cargarRevision()
        val b = modeloDia(alcance, d) { 404 to sinFuncion }
        b.cargarRevision()
        assertEquals(7, b.revisionDia.value)
        assertEquals(7, modeloDia(alcance, d) { 200 to "7" }.revisionDia.value)
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
