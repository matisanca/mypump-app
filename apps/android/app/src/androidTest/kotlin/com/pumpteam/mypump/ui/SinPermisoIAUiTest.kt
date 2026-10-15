package com.pumpteam.mypump.ui

import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.ModeloAppViewModel
import com.pumpteam.mypump.datos.ModeloApp
import kotlinx.coroutines.launch
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
     * Android todavía no tiene la pantalla del chat: con Chat a la vista, el mensaje sale como lo va a mandar ella
     * (`ModeloChat.enviar` en el alcance de la app). Cuando esté, esto pasa a escribir y tocar Enviar. Una hoja o un
     * diálogo es otra ventana de Compose: no tiene que aparecer ninguna.
     */
    @Test
    fun mandarUnMensajeDelChatNoAbreNingunaHoja() {
        guardarCuenta()
        val e = abrir()
        p.tocar(etiqueta("pestana-chat"))
        p.esperar("Chat a la vista") { p.seleccionado(etiqueta("pestana-chat")) }
        val (vm, m) = modeloDe(e)
        val ventanas = p.enPrincipal { Raices.activas().size }
        p.enPrincipal { vm.viewModelScope.launch { m.chat.value!!.enviar(MENSAJE) } }
        p.esperar("el mensaje salió") { servidor.a("mypump_agregar_comentario").any { MENSAJE in it } }
        p.quieto(600)
        assertEquals("se abrió otra ventana (una hoja o un diálogo)", ventanas, p.enPrincipal { Raices.activas().size })
        assertFalse(p.existe(textoQueContiene("asistente de IA")))
        assertTrue("${servidor.llamadas.map { it.funcion }}", servidor.llamadas.none { "consentimiento" in it.funcion })
    }

    /** El ViewModel de la app abierta y su modelo, con la cuenta ya cargada. */
    private fun modeloDe(e: ActivityScenario<MainActivity>): Pair<ModeloAppViewModel, ModeloApp> {
        var vm: ModeloAppViewModel? = null
        e.onActivity { a -> vm = ViewModelProvider(a)[ModeloAppViewModel::class.java] }
        val v = vm!!
        return v to p.esperar("la cuenta cargó") { v.modelo.value?.takeIf { it.fase.value == ModeloApp.Fase.LISTO } }
    }

    private companion object {
        const val MENSAJE = "Hola Mati, te paso el peso de hoy"
    }
}
