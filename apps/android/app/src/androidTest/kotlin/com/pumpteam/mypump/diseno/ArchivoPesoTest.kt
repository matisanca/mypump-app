package com.pumpteam.mypump.diseno

import android.graphics.Bitmap
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.Paragraph
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.createFontFamilyResolver
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Archivo es una letra variable (`wght` de 100 a 900, 600 por defecto). Los títulos de día y los números grandes la piden
 * en 800, como iOS; el 15-oct se vio que en Android salían todos en el 600 de fábrica: el peso no llegaba a la letra y
 * los títulos se veían flojos al lado del iPhone. Se dibuja el mismo texto en 500 y en 900 y se cuenta la tinta.
 */
@RunWith(AndroidJUnit4::class)
class ArchivoPesoTest {
    private val contexto = InstrumentationRegistry.getInstrumentation().targetContext
    private val resolver = createFontFamilyResolver(contexto)

    private fun tinta(peso: FontWeight): Int {
        val p = Paragraph(
            text = "Tirón A — Ancho 2.454",
            style = TextStyle(fontFamily = Archivo, fontWeight = peso, fontSize = 40.sp, color = Color.Black),
            constraints = Constraints(maxWidth = 4_000),
            density = Density(1f),
            fontFamilyResolver = resolver,
        )
        val bmp = Bitmap.createBitmap(4_000, p.height.toInt() + 4, Bitmap.Config.ARGB_8888)
        p.paint(Canvas(bmp.asImageBitmap()))
        val px = IntArray(bmp.width * bmp.height)
        bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
        return px.count { (it ushr 24) > 128 }
    }

    @Test
    fun elPesoLlegaALaLetra() {
        val liviana = tinta(FontWeight.W500)
        val pesada = tinta(FontWeight.W900)
        assertTrue("500: $liviana px de tinta, 900: $pesada (tienen que diferir mucho)", pesada > liviana * 1.25)
    }

    @Test
    fun losTitulosYLosNumerosVanEn800() {
        val pedido = tinta(FontWeight.W800)
        val porDefecto = tinta(FontWeight.W600)
        assertTrue("800: $pedido px de tinta, 600: $porDefecto", pedido > porDefecto * 1.08)
    }
}
