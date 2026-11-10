package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasMolestia
import com.pumpteam.mypump.reglas.ReglasSupleEstado.Estado
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Feedback del alumno contra el doble que sigue el SQL propuesto. Gemelo de FeedbackModeloTests.swift. */
class FeedbackModeloTest {
    private val token = "tk-prueba-feedback"
    private fun raiz() = Files.createTempDirectory("feedback").toFile()
    private fun armar(d: DobleFeedback, r: File = raiz()) = ModeloFeedback(ClienteRpc(transporte = d), token, Disco(r, token))
    private fun borrador(intensidad: Int = 5) =
        ReglasMolestia.Borrador(zona = "hombro", lado = "derecho", desde = "hoy", cuando = "al_subir", tipo = "sordo", intensidad = intensidad)

    @Test fun avisarUnaMolestia(): Unit = runBlocking {
        val d = DobleFeedback()
        val m = armar(d)
        m.refrescar()
        assertTrue(m.dueleHabilitado && m.supleHabilitado)
        assertNull(m.molestia("press-d1-0"))
        val b = borrador().copy(nota = "  " + "x".repeat(600))
        assertEquals(ModeloFeedback.Salida.OK, m.avisar("id-1", "press-d1-0", "Press", "d1", b, "2.3.0"))
        assertEquals("Hombro derecho", m.molestia("press-d1-0")?.nombreZona)
        assertEquals(true, m.molestia("press-d1-0")?.abierta)
        val j = d.ultimoRegistro
        assertEquals(500, j?.get("p_nota")?.comoTexto?.length)
        assertEquals("android", j?.get("p_plataforma")?.comoTexto)
        assertEquals(5.0, j?.get("p_intensidad")?.comoNumero)
        assertEquals(token, j?.get("p_token")?.comoTexto)
        assertEquals("d1", j?.get("p_dia_id")?.comoTexto)
        assertEquals("2.3.0", j?.get("p_version")?.comoTexto)
        // Los catorce parámetros del contrato, ni uno más.
        assertEquals(
            setOf("p_token", "p_id", "p_ejercicio_id", "p_ejercicio_nombre", "p_dia_id", "p_zona", "p_lado", "p_desde", "p_cuando", "p_tipo", "p_intensidad", "p_nota", "p_plataforma", "p_version"),
            (j as ValorJson.Objeto).campos.keys,
        )
        // Corregirla no crea otra.
        val c = borrador(9).copy(zona = "codo")
        assertEquals(ModeloFeedback.Salida.OK, m.avisar("id-2", "press-d1-0", "Press", "d1", c, null))
        assertEquals(1, m.estado.value?.molestias?.size)
        assertEquals("codo", m.molestia("press-d1-0")?.zona)
        assertEquals(ValorJson.Nulo, d.ultimoRegistro?.get("p_nota"))
        assertEquals(ValorJson.Nulo, d.ultimoRegistro?.get("p_version"))
        // «Me duele» no escribe comentarios ni nada que no sea lo suyo.
        assertEquals(listOf("mypump_feedback_get", "mypump_molestia_registrar", "mypump_molestia_registrar"), d.llamadas.toList())
    }

    @Test fun incompletaNoSale(): Unit = runBlocking {
        val d = DobleFeedback()
        val m = armar(d)
        m.refrescar()
        assertEquals(ModeloFeedback.Salida.ERROR, m.avisar("x", "e", "E", null, borrador().copy(tipo = null), null))
        assertFalse("mypump_molestia_registrar" in d.llamadasFeedback)
    }

    @Test fun sinSenalYTope(): Unit = runBlocking {
        val d = DobleFeedback()
        val m = armar(d)
        m.refrescar()
        d.sinRed = true
        assertEquals(ModeloFeedback.Salida.SIN_SENAL, m.avisar("x", "e", "E", null, borrador(), null))
        assertNull(m.molestia("e"))
        d.sinRed = false
        d.tope = true
        assertEquals(ModeloFeedback.Salida.TOPE, m.avisar("x", "e", "E", null, borrador(), null))
        assertNull(m.molestia("e"))
    }

    @Test fun sinServidorNoSeVeNada(): Unit = runBlocking {
        val d = DobleFeedback().apply { sinFuncion = true }
        val m = armar(d)
        m.refrescar()
        assertTrue(m.estado.value == null && !m.dueleHabilitado && !m.supleHabilitado)
    }

    @Test fun sinRedQuedaLoGuardado(): Unit = runBlocking {
        val d = DobleFeedback.escenario("marcado")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        assertEquals(mapOf("creatina monohidrato" to Estado.TOMANDO, "omega 3" to Estado.COMPRADO), m.marcas)
        d.sinRed = true
        val otro = armar(d, r)
        otro.refrescar()
        assertEquals(Estado.COMPRADO, otro.marcas["omega 3"])
        // Si después el servidor ya no tiene la función, se apaga y no queda la copia.
        d.sinRed = false
        d.sinFuncion = true
        otro.refrescar()
        assertNull(otro.estado.value)
        d.sinRed = true
        val tercero = armar(d, r)
        tercero.refrescar()
        assertNull(tercero.estado.value)
    }

    @Test fun marcarUnSuplemento(): Unit = runBlocking {
        val d = DobleFeedback()
        val m = armar(d)
        m.refrescar()
        assertTrue(m.marcar("Creatina  Monohidrato", Estado.COMPRADO))
        assertTrue(m.marcas["creatina monohidrato"] == Estado.COMPRADO && d.marcas["creatina monohidrato"] == "comprado")
        assertTrue(m.marcar("Creatina monohidrato", Estado.TOMANDO))
        assertEquals(mapOf("creatina monohidrato" to "tomando"), d.marcas.toMap())
        // Igual a lo que ya está: no viaja.
        val antes = d.llamadasFeedback.size
        assertTrue(m.marcar("Creatina monohidrato", Estado.TOMANDO))
        assertEquals(antes, d.llamadasFeedback.size)
    }

    @Test fun siFallaVuelveAComoEstaba(): Unit = runBlocking {
        val d = DobleFeedback.escenario("marcado")
        val m = armar(d)
        m.refrescar()
        d.fallaMarcar = true
        assertFalse(m.marcar("Omega 3", Estado.LO_DEJE))
        assertEquals(Estado.COMPRADO, m.marcas["omega 3"])
        assertTrue(m.marcando.value.isEmpty())
        // Un protector: el servidor dice que no y la marca no queda.
        assertFalse(m.marcar("Telmisartán", Estado.TOMANDO))
        assertNull(m.marcas["telmisartan"])
        // Sin red tampoco queda, y sin estado (apagado) ni viaja.
        d.sinRed = true
        assertFalse(m.marcar("Cafeína", Estado.COMPRADO))
        assertNull(m.marcas["cafeina"])
        m.apagar()
        val antes = d.llamadas.size
        assertFalse(m.marcar("Cafeína", Estado.COMPRADO))
        assertEquals(antes, d.llamadas.size)
    }

    @Test fun palancas() {
        assertTrue(!PalancaRemota.deFabrica.meDuele && !PalancaRemota.deFabrica.supleEstado)
        val p = PalancaRemota.desde(ValorJson.objeto("me_duele" to ValorJson.Booleano(true), "suple_estado" to ValorJson.Texto("true")))
        assertTrue(p.meDuele && !p.supleEstado)
    }

    // ── El cableado en ModeloApp ──

    private fun app(d: DobleFeedback, alcance: kotlinx.coroutines.CoroutineScope): ModeloApp {
        val t = Transporte { pedido ->
            val f = pedido.ruta.substringAfterLast('/')
            when {
                DobleFeedback.esSuya(f) -> d.enviar(pedido)
                f == "mypump_get_cliente_info" -> Respuesta(200, """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]""".toByteArray())
                else -> Respuesta(200, "[]".toByteArray())
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), carpetaTemporal("feedback-app"), PreferenciasEnMemoria(), alcance)
    }

    @Test fun conLasDosPalancasApagadasNoSeLlamaANada() = enUnHilo { alcance ->
        val d = DobleFeedback.escenario("apagado")
        val m = app(d, alcance)
        m.cargar()
        m.alVolverAPrimerPlano()
        assertTrue(d.llamadasFeedback.isEmpty(), d.llamadasFeedback.toString())
        assertNull(m.feedback.value?.estado?.value)
    }

    @Test fun conUnaPalancaPrendidaSeLeeElEstado() = enUnHilo { alcance ->
        val d = DobleFeedback.escenario("marcado").apply { meDuele = false }
        val m = app(d, alcance)
        m.cargar()
        assertEquals(listOf("mypump_feedback_get"), d.llamadasFeedback)
        val f = m.feedback.value!!
        assertTrue(f.supleHabilitado && !f.dueleHabilitado)
        assertEquals(Estado.COMPRADO, f.marcas["omega 3"])
        // La palanca se apaga desde el servidor: al volver deja de verse y no se pregunta más.
        d.supleEstado = false
        m.cargar()
        assertNull(f.estado.value)
        assertEquals(1, d.llamadasFeedback.size)
    }

    @Test fun conLaPalancaPrendidaYSinLaFuncionNoSeVeNada() = enUnHilo { alcance ->
        val d = DobleFeedback().apply { sinFuncion = true }
        val m = app(d, alcance)
        m.cargar()
        assertNull(m.feedback.value?.estado?.value)
    }
}
