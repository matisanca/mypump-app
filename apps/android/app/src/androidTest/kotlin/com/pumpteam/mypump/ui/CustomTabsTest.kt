package com.pumpteam.mypump.ui

import android.app.Instrumentation
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.diseno.TemaMyPump
import com.pumpteam.mypump.diseno.abrirEnNavegador
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las fuentes y las páginas legales se abren DENTRO de la app con una Custom Tab, como el SFSafariViewController de iOS
 * (antes iban al navegador y el cliente quedaba fuera de MyPump). Es también la primera prueba con `ui-test-junit4`.
 * El intent se captura con un monitor: no se abre ningún navegador de verdad.
 */
@RunWith(AndroidJUnit4::class)
class CustomTabsTest {
    @get:Rule
    val regla = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun unaFuenteSeAbreEnUnaCustomTab() {
        var capturado: Intent? = null
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action == Intent.ACTION_VIEW) {
                    capturado = intent
                    return Instrumentation.ActivityResult(0, null)
                }
                return null
            }
        }
        val instrumentacion = InstrumentationRegistry.getInstrumentation()
        instrumentacion.addMonitor(monitor)
        try {
            regla.setContent {
                val contexto = LocalContext.current
                TemaMyPump { Button(onClick = { abrirEnNavegador(contexto, "https://pubmed.ncbi.nlm.nih.gov/") }) { Text("Abrir fuente") } }
            }
            regla.onNodeWithText("Abrir fuente").performClick()
            regla.waitUntil(5_000) { capturado != null }
        } finally {
            instrumentacion.removeMonitor(monitor)
        }
        assertNotNull("no se abrió nada", capturado)
        val i = capturado!!
        assertEquals("https://pubmed.ncbi.nlm.nih.gov/", i.dataString)
        // Una Custom Tab con el navegador fijo (un link de app.mypumpteam.com no puede volver a la app:
        // NavegadorFueraDeLaAppTest) o, sin un navegador con Custom Tabs (Android 9 del emulador), el selector de navegadores.
        comprobarQueVaAlNavegador(i, InstrumentationRegistry.getInstrumentation().targetContext)
    }
}
