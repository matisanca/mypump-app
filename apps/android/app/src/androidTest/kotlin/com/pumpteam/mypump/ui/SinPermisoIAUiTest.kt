package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Sin permiso para la IA (D7 se sacó el 14-oct, decisión de Mati: la IA trabaja bajo su aprobación y no es algo que el
 * cliente acepte), gemelo de `testMisDatosNoTieneInterruptorDeIANiDeRecordatorios` de iOS. El servidor sigue sabiendo de
 * permisos (la `nativa_002` queda en la base) y contesta "nunca decidió", que es cuando antes aparecía la hoja: igual no
 * se pregunta nada, no se lee nada y en Mis datos no hay nada que prender.
 */
@RunWith(AndroidJUnit4::class)
class SinPermisoIAUiTest : PruebaUi() {
    @Before
    fun conLaTablaEnLaBase() {
        servidor.respuestas["mypump_get_consentimiento_ia"] = """{"acepta":null}"""
    }

    @Test
    fun misDatosNoTieneElInterruptorDeLaIA() {
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("tema-oscuro"))
        p.nodo(etiqueta("mis-datos-respaldo"))
        assertFalse("volvió el interruptor de la IA", p.existe(etiqueta("asistente-ia")))
        assertFalse(p.existe(texto("Asistente de IA")))
        assertFalse(p.existe(texto("Inteligencia artificial")))
        assertFalse("el aviso del domingo no se configura", p.existe(etiqueta("recordatorio-domingo")))
        assertTrue("${servidor.llamadas.map { it.funcion }}", servidor.llamadas.none { "consentimiento" in it.funcion })
    }

    /**
     * El primer mensaje del chat, como lo manda el cliente: escribirlo y tocar Enviar. Sale por la cola sin preguntar nada.
     * Una hoja o un diálogo es otra ventana de Compose: no tiene que aparecer ninguna.
     */
    @Test
    fun mandarUnMensajeDelChatNoAbreNingunaHoja() {
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-chat"))
        p.esperar("Chat a la vista") { p.seleccionado(etiqueta("pestana-chat")) }
        p.nodo(etiqueta("chat-campo"))
        val ventanas = p.enPrincipal { Raices.activas().size }
        p.escribir(etiqueta("chat-campo"), MENSAJE)
        p.tocar(etiqueta("chat-enviar"))
        p.esperar("el mensaje salió") { servidor.a("mypump_agregar_comentario").any { MENSAJE in it } }
        p.nodo(texto("Vos: $MENSAJE"))
        p.quieto(600)
        assertEquals("se abrió otra ventana (una hoja o un diálogo)", ventanas, p.enPrincipal { Raices.activas().size })
        assertFalse(p.existe(textoQueContiene("asistente de IA")))
        assertTrue("${servidor.llamadas.map { it.funcion }}", servidor.llamadas.none { "consentimiento" in it.funcion })
    }

    private companion object {
        const val MENSAJE = "Hola Mati, te paso el peso de hoy"
    }
}
