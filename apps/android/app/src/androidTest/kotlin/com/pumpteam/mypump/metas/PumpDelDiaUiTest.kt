package com.pumpteam.mypump.metas

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.diseno.TemaMyPump
import com.pumpteam.mypump.reglas.PumpDelDia
import com.pumpteam.mypump.reglas.RitmoPeso
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * «Pump del día» suelto (gemelo de MetasUITests.swift): la tarjeta, sin Salud, la celebración y el ritmo de peso, en claro
 * y oscuro. Las capturas quedan en los archivos de la app (metas/), para `adb pull` (ver nativa-evidencia/metas).
 */
@RunWith(AndroidJUnit4::class)
class PumpDelDiaUiTest {
    @get:Rule
    val regla = createAndroidComposeRule<ComponentActivity>()

    private val hoy = "2026-11-12"
    private val pasos = mapOf("2026-11-09" to 11200.0, "2026-11-10" to 10400.0, "2026-11-11" to 12100.0, hoy to 7420.0)
    private fun vista(p: Map<String, Double> = pasos) = PumpDelDia.vista(p, 10_000, hoy)!!

    private fun guardar(tag: String, nombre: String) {
        val img = regla.onNodeWithTag(tag).captureToImage().asAndroidBitmap()
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "metas").apply { mkdirs() }
        File(dir, "$nombre.png").outputStream().use { img.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test
    fun tarjetaYRitmoEnClaroYOscuro() {
        var oscuro by mutableStateOf(false)
        regla.setContent {
            TemaMyPump(oscuro = oscuro) {
                Column(Modifier.testTag("lienzo").background(MaterialTheme.colorScheme.background).padding(16.dp)) {
                    TarjetaPumpDelDia(vista(), conectado = true, modifier = Modifier.fillMaxWidth())
                    TarjetaPumpDelDia(vista(), conectado = true, enSalud = true, modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
                    TarjetaPumpDelDia(vista(emptyMap()), conectado = false, modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
                    RitmoPesoCaja(RitmoPeso.Resumen(RitmoPeso.textoMeta(-0.5), "Venís bajando medio kilo por semana", true),
                        Modifier.fillMaxWidth().padding(top = 12.dp))
                }
            }
        }
        // La tarjeta se lee entera de una vez (TalkBack): los números van en la descripción.
        val leido = "Pump del día, 7.420 de 10.000 pasos. Te faltan 2.580 pasos. 3 días seguidos. Esta semana, 3 de 4 días con la meta."
        regla.onNodeWithContentDescription(leido).assertExists()
        regla.onNodeWithContentDescription("$leido Meta 10.000 pasos por día, tu promedio 11.233.").assertExists()
        regla.onNodeWithText("Tu meta es de 10.000 pasos por día").assertExists()
        regla.onNodeWithText("Buscamos bajar medio kilo por semana").assertExists()
        regla.onNodeWithText(RitmoPeso.EN_RITMO).assertExists()
        regla.mainClock.advanceTimeBy(7_000)
        guardar("lienzo", "android-tarjetas-claro")
        oscuro = true
        regla.mainClock.advanceTimeBy(7_000)
        guardar("lienzo", "android-tarjetas-oscuro")
    }

    @Test
    fun celebracionSeCierraConSeguir() {
        val v = vista(pasos + (hoy to 10240.0))
        assertEquals(4, v.racha)
        var abierta by mutableStateOf(true)
        regla.setContent {
            TemaMyPump(oscuro = false) {
                Box(Modifier.fillMaxSize().testTag("lienzo")) {
                    if (abierta) CelebracionPump(v) { abierta = false }
                }
            }
        }
        regla.mainClock.advanceTimeBy(3_000)
        regla.onNodeWithText(PumpDelDia.LLENO).assertExists()
        regla.onNodeWithText("Llegaste a tus 10.000 pasos de hoy").assertExists()
        regla.onNodeWithText("Van 4 días seguidos").assertExists()
        guardar("lienzo", "android-celebracion-claro")
        regla.onNodeWithText(PumpDelDia.SEGUIR).performClick()
        regla.mainClock.advanceTimeBy(1_000)
        regla.onNodeWithText(PumpDelDia.LLENO).assertDoesNotExist()
    }
}
