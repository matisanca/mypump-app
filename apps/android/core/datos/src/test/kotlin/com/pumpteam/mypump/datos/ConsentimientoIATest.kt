package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * D7 del lado de la app (`nativa_002`), gemelo de ConsentimientoIATests.swift: sin la migración todo sigue como hoy; con
 * ella se pregunta antes del primer uso, el "no" sale por la cola y la foto no sale del teléfono.
 */
class ConsentimientoIATest {
    private class Estado {
        @Volatile var respuesta: Pair<Int, String> = 200 to """{"acepta":null}"""
        @Volatile var conRed = true
        val guardados = mutableListOf<ValorJson>()
        @Volatile var visiones = 0
    }

    private fun modelo(e: Estado, raiz: File, alcance: CoroutineScope): ModeloApp {
        val t = TransporteProgramado { fn, cuerpo ->
            if (!e.conRed) throw IOException("sin conexión a internet")
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_consentimiento_ia" -> e.respuesta
                "mypump_guardar_consentimiento_ia" -> {
                    synchronized(e.guardados) { e.guardados += cuerpo }
                    200 to "true"
                }
                "mypump_get_rutina_activa" -> 200 to """[{"id":"r1","semana_actual":1,"estructura":{"dias":[]}}]"""
                "mypump_agregar_comentario" -> 200 to "\"00000000-0000-4000-8000-0000000000aa\""
                "vision" -> {
                    e.visiones++
                    200 to "{}"
                }
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raiz, PreferenciasEnMemoria(), alcance, versionApp = "2.0.0")
    }

    @Test
    fun sinLaMigracionTodoSigueComoHoy() = enUnHilo { alcance ->
        val e = Estado().apply { respuesta = 404 to """{"code":"PGRST202","message":"Could not find the function"}""" }
        val m = modelo(e, carpetaTemporal("consentimiento"), alcance)
        m.cargar()
        assertFalse(m.consentimientoIADisponible.value)
        assertFalse(m.faltaConsentimientoIA)
        assertTrue(m.analisisDeFotoPermitido)
    }

    @Test
    fun nuncaSeLePreguntoPidePermisoYFrenaLaFoto() = enUnHilo { alcance ->
        val e = Estado()
        val m = modelo(e, carpetaTemporal("consentimiento"), alcance)
        m.cargar()
        assertTrue(m.faltaConsentimientoIA)
        assertFalse(m.analisisDeFotoPermitido)
        val foto = m.analizarFoto(byteArrayOf(0xFF.toByte()), ClienteRpc.TipoVision.PLATO)
        assertEquals("SIN_PERMISO_IA", foto.errorONull()?.codigo, "la foto salió sin permiso")
        assertEquals(0, e.visiones)
    }

    @Test
    fun elNoSalePorLaColaYQueda() = enUnHilo { alcance ->
        val e = Estado()
        val raiz = carpetaTemporal("consentimiento")
        val m = modelo(e, raiz, alcance)
        m.cargar()
        m.decidirConsentimientoIA(false)
        assertEquals(false, m.consentimientoIA.value)
        assertFalse(m.faltaConsentimientoIA)
        val guardado = synchronized(e.guardados) { e.guardados.first() }
        assertEquals(ValorJson.Booleano(false), guardado["p_acepta"])
        assertEquals(ValorJson.Texto("android"), guardado["p_plataforma"])
        assertEquals(ValorJson.Texto("2.0.0"), guardado["p_app"])
        // Otro arranque, sin red: la decisión se conserva.
        e.conRed = false
        val otro = modelo(e, raiz, alcance)
        otro.cargar()
        assertEquals(false, otro.consentimientoIA.value)
        assertFalse(otro.analisisDeFotoPermitido)
    }

    @Test
    fun loDecididoSinRedGanaSobreElServidor() = enUnHilo { alcance ->
        val e = Estado()
        val m = modelo(e, carpetaTemporal("consentimiento"), alcance)
        m.cargar()
        e.conRed = false
        m.decidirConsentimientoIA(true)   // queda en la cola
        e.conRed = true
        e.respuesta = 200 to """{"acepta":null}"""
        // Recarga antes de que la cola salga: lo pendiente gana.
        m.cargar()
        assertEquals(true, m.consentimientoIA.value)
        assertTrue(m.analisisDeFotoPermitido)
    }

    /** "Antes de lo que lo dispara": con `drenar = false` la decisión queda primera en la cola y sale antes que el mensaje. */
    @Test
    fun laDecisionSaleAntesQueLoQueLaDisparo() = enUnHilo { alcance ->
        val e = Estado()
        val m = modelo(e, carpetaTemporal("consentimiento"), alcance)
        m.cargar()
        e.conRed = false
        m.decidirConsentimientoIA(true, drenar = false)
        m.outbox!!.encolar("chat", ValorJson.objeto("contenido" to ValorJson.Texto("hola Mati")), "chat_1_hola Mati")
        assertEquals(listOf("consentimiento_ia", "chat"), m.outbox!!.operaciones().map { it.kind })
        e.conRed = true
        m.drenarCola()
        assertEquals(0, m.outbox!!.pendientes())
        assertEquals(1, synchronized(e.guardados) { e.guardados.size })
    }

    /** Con el token caído la RPC devuelve `null`: vale lo último guardado (no "nunca se le preguntó"). */
    @Test
    fun conElTokenCaidoValeLoGuardado() = enUnHilo { alcance ->
        val e = Estado()
        val raiz = carpetaTemporal("consentimiento")
        val m = modelo(e, raiz, alcance)
        m.cargar()
        m.decidirConsentimientoIA(true)
        e.respuesta = 200 to "null"
        val otro = modelo(e, raiz, alcance)
        otro.cargar()
        assertEquals(true, otro.consentimientoIA.value)
        assertTrue(otro.consentimientoIADisponible.value)
    }

    /** La demo y la bienvenida no preguntan ni encolan nada. */
    @Test
    fun sinCuentaNoSePregunta() = enUnHilo { alcance ->
        val e = Estado()
        val m = ModeloApp(ClienteRpc(transporte = SinRed), TokenEnMemoria(), carpetaTemporal("consentimiento"), PreferenciasEnMemoria(), alcance)
        m.decidirConsentimientoIA(false)
        assertNull(m.consentimientoIA.value)
        assertFalse(m.faltaConsentimientoIA)
        assertEquals(0, e.guardados.size)
    }
}
