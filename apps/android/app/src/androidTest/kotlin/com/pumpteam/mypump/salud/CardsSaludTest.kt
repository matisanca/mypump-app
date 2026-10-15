package com.pumpteam.mypump.salud

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.datos.ClaveSalud
import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.datos.PreferenciasEnMemoria
import com.pumpteam.mypump.diseno.TemaMyPump
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.ui.FuenteDeMentira
import com.pumpteam.mypump.ui.ServidorDePrueba
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las tarjetas de Recuperación y Salud de Revisión (SAL-09, SAL-10), gemelas de CardsSalud.swift. La pantalla de Revisión
 * de Android todavía no existe: acá se arman sueltas, con un `ModeloSalud` de verdad sobre las respuestas grabadas.
 */
@RunWith(AndroidJUnit4::class)
class CardsSaludTest {
    @get:Rule
    val regla = createAndroidComposeRule<ComponentActivity>()

    private val alcance = CoroutineScope(Dispatchers.Main + SupervisorJob())

    @After
    fun cerrar() {
        alcance.cancel()
        EstadoHealthConnect.forzado = null
    }

    private fun salud(conDatos: Boolean, conectada: Boolean): ModeloSalud {
        val servidor = ServidorDePrueba()
        if (conDatos) {
            for (f in listOf("get_salud", "get_recuperacion", "get_mostrar_recuperacion")) {
                servidor.respuestas["mypump_$f"] = InstrumentationRegistry.getInstrumentation().context.assets.open("test-nativa-ios/$f.json")
                    .use { it.readBytes().toString(Charsets.UTF_8) }
            }
        } else {
            servidor.respuestas["mypump_get_salud"] = "[]"
            servidor.respuestas["mypump_get_recuperacion"] = "[]"
        }
        val almacen = PreferenciasEnMemoria(if (conectada) mapOf(ClaveSalud.CONECTADO to "1") else emptyMap())
        val s = ModeloSalud(ClienteRpc(transporte = servidor), ServidorDePrueba.TOKEN, FuenteDeMentira(), almacen, alcance)
        runBlocking { s.cargar() }
        return s
    }

    @Test
    fun conScoreMuestraElNumeroLaBandaYVerTodo() {
        val s = salud(conDatos = true, conectada = true)
        var verTodo = false
        regla.setContent {
            TemaMyPump {
                CompositionLocalProvider(LocalAlcanceApp provides alcance) {
                    Column {
                        CardRecuperacion(s, alVerTodo = { verTodo = true })
                        CardSalud(s)
                    }
                }
            }
        }
        regla.onNodeWithTag("card-recuperacion").assertIsDisplayed()
        val enLaDeRecuperacion = hasAnyAncestor(hasTestTag("card-recuperacion"))
        regla.onNode(hasText("45") and enLaDeRecuperacion).assertIsDisplayed()
        regla.onNode(hasText("Medio") and enLaDeRecuperacion).assertIsDisplayed()
        regla.onNodeWithTag("card-salud").assertIsDisplayed()
        regla.onNodeWithText("pasos hoy").assertIsDisplayed()
        regla.onNodeWithText("HRV (recuperación)").assertIsDisplayed()
        regla.onNodeWithTag("ver-todos-mis-datos").performClick()
        assertTrue(verTodo)
    }

    /** Sin conectar: Recuperación explica y ofrece Health Connect; Salud no repite el botón. */
    @Test
    fun sinConectarOfreceHealthConnectUnaSolaVez() {
        EstadoHealthConnect.forzado = EstadoHealthConnect.DISPONIBLE
        val s = salud(conDatos = false, conectada = false)
        regla.setContent {
            TemaMyPump {
                CompositionLocalProvider(LocalAlcanceApp provides alcance) {
                    Column {
                        CardRecuperacion(s, alVerTodo = {})
                        CardSalud(s)
                    }
                }
            }
        }
        regla.onNodeWithText("Tu recuperación se calcula con lo que mide tu reloj mientras dormís: pulso en reposo, sueño y variabilidad.").assertIsDisplayed()
        regla.onNodeWithText("Conectar Health Connect").assertIsDisplayed()
        regla.onNodeWithTag("conectar-salud").assertIsDisplayed()
        assertTrue(regla.onAllNodesWithTag("conectar-salud").fetchSemanticsNodes().size == 1)
    }
}
