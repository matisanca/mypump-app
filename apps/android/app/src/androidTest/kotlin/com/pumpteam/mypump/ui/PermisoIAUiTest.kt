package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ModeloApp
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * El permiso para la IA (D7), gemelo de PermisoIA.swift: la hoja aparece antes del primer uso, la decisión sale por la
 * cola ANTES de lo que la disparó, los dos caminos siguen, no se puede cerrar sin elegir, y el interruptor de Mis datos la
 * cambia.
 *
 * En Android todavía no están las pantallas que la disparan (el chat, la foto de una comida, el check): acá la dispara un
 * botón de prueba que hace lo que va a hacer el chat (`antesDeUsarIA` y, al seguir, mandar el mensaje).
 */
@RunWith(AndroidJUnit4::class)
class PermisoIAUiTest : PruebaUi() {
    @Test
    fun aceptoGuardaLaDecisionAntesQueElMensajeYSigue() {
        val (m, alcance) = modeloConCuenta()
        assertTrue(m.faltaConsentimientoIA)
        val decisiones = CopyOnWriteArrayList<Boolean>()
        armarPermisoIA(m, alcance, decisiones)
        p.tocar(etiqueta("mandar"))
        p.nodo(texto("Antes de seguir: el asistente de IA"))
        p.nodo(textoQueContiene("Mati usa herramientas de inteligencia artificial de OpenAI y Anthropic"))
        for (fila in listOf("Chat", "Fotos", "Revisión semanal")) p.nodo(texto(fila))
        p.nodo(textoQueContiene("Si decís que no, ninguna IA lee tus datos"))
        assertTrue("la hoja no tiene que esperar a la red para mostrarse", decisiones.isEmpty())
        p.tocar(etiqueta("ia-acepto"))
        p.esperarQueNoEste(texto("Antes de seguir: el asistente de IA"))
        p.esperar("siguió con lo que eligió") { decisiones.toList() == listOf(true) }
        p.esperar("el mensaje salió") { servidor.a("mypump_agregar_comentario").isNotEmpty() }
        val guardado = servidor.a("mypump_guardar_consentimiento_ia").single()
        assertTrue(guardado, guardado.contains("\"p_acepta\":true") && guardado.contains("\"p_plataforma\":\"android\""))
        // La decisión salió ANTES que el mensaje: el servidor ya la tiene cuando le llega lo que la IA podría leer.
        val orden = servidor.llamadas.map { it.funcion }
        assertTrue("$orden", orden.indexOf("mypump_guardar_consentimiento_ia") < orden.indexOf("mypump_agregar_comentario"))
        assertEquals(true, m.consentimientoIA.value)
        assertFalse(m.faltaConsentimientoIA)
        // Ya decidido: el próximo mensaje sale sin preguntar.
        p.tocar(etiqueta("mandar"))
        p.quieto(600)
        assertFalse(p.existe(texto("Antes de seguir: el asistente de IA")))
        assertEquals(listOf(true, true), decisiones.toList())
    }

    @Test
    fun conNoSinIATambienSigueYNoVuelveAPreguntar() {
        val (m, alcance) = modeloConCuenta()
        val decisiones = CopyOnWriteArrayList<Boolean>()
        armarPermisoIA(m, alcance, decisiones)
        p.tocar(etiqueta("mandar"))
        p.tocar(etiqueta("ia-no"))
        p.esperarQueNoEste(texto("Antes de seguir: el asistente de IA"))
        // El "no" también manda el mensaje: lo contesta Mati.
        p.esperar("siguió") { decisiones.toList() == listOf(false) }
        p.esperar("el mensaje salió") { servidor.a("mypump_agregar_comentario").isNotEmpty() }
        assertTrue(servidor.a("mypump_guardar_consentimiento_ia").single().contains("\"p_acepta\":false"))
        assertEquals(false, m.consentimientoIA.value)
        assertFalse("sin permiso la foto no sale del teléfono", m.analisisDeFotoPermitido)
        p.tocar(etiqueta("mandar"))
        p.quieto(600)
        assertFalse(p.existe(texto("Antes de seguir: el asistente de IA")))
        assertEquals(listOf(false, false), decisiones.toList())
    }

    @Test
    fun hayQueElegirAtrasNoLaCierra() {
        val (m, alcance) = modeloConCuenta()
        val decisiones = CopyOnWriteArrayList<Boolean>()
        armarPermisoIA(m, alcance, decisiones)
        p.tocar(etiqueta("mandar"))
        p.nodo(etiqueta("ia-acepto"))
        p.atras()
        p.quieto(800)
        p.nodo(texto("Antes de seguir: el asistente de IA"))
        assertTrue(decisiones.isEmpty())
        assertTrue(servidor.a("mypump_guardar_consentimiento_ia").isEmpty())
        assertTrue(servidor.a("mypump_agregar_comentario").isEmpty())
        p.tocar(etiqueta("ia-acepto"))
        p.esperar("siguió") { decisiones.toList() == listOf(true) }
    }

    @Test
    fun sinLaMigracionEnElServidorNoSePregunta() {
        // Sin `nativa_002` (PGRST202) un "no" no se podría respetar del otro lado: no se pregunta y todo sigue como hoy.
        servidor.respuestas["mypump_get_consentimiento_ia"] = ServidorDePrueba.SIN_FUNCION
        val (m, alcance) = modeloConCuenta(esperarPermiso = false)
        assertFalse(m.faltaConsentimientoIA)
        val decisiones = CopyOnWriteArrayList<Boolean>()
        armarPermisoIA(m, alcance, decisiones)
        p.tocar(etiqueta("mandar"))
        p.esperar("siguió sin preguntar") { decisiones.toList() == listOf(true) }
        p.quieto(500)
        assertFalse(p.existe(texto("Antes de seguir: el asistente de IA")))
        assertTrue(servidor.a("mypump_guardar_consentimiento_ia").isEmpty())
    }

    @Test
    fun elInterruptorDeMisDatosCambiaLaDecision() {
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(texto("Inteligencia artificial"))
        assertFalse(p.prendido(etiqueta("asistente-ia")))
        p.nodo(textoQueContiene("Todavía no elegiste: te lo preguntamos antes de tu primer mensaje"))
        p.tocar(etiqueta("asistente-ia"))
        p.esperar("prendido") { p.prendido(etiqueta("asistente-ia")) }
        p.nodo(textoQueContiene("Lee tus mensajes del chat, las fotos que mandes a analizar y tu check"))
        p.esperar("salió el sí") { servidor.a("mypump_guardar_consentimiento_ia").any { it.contains("\"p_acepta\":true") } }
        p.tocar(etiqueta("asistente-ia"))
        p.esperar("apagado") { !p.prendido(etiqueta("asistente-ia")) }
        p.nodo(texto("Apagado: ninguna IA lee tus datos. Te contesta Mati y las fotos no se analizan."))
        p.esperar("salió el no") { servidor.a("mypump_guardar_consentimiento_ia").any { it.contains("\"p_acepta\":false") } }
    }

    @Test
    fun enLaDemoNoEstaElInterruptorDeLaIA() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("tema-oscuro"))
        assertFalse(p.existe(etiqueta("asistente-ia")))
        assertFalse(p.existe(texto("Inteligencia artificial")))
    }
}
