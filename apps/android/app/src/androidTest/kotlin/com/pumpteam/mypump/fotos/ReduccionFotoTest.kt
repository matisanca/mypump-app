package com.pumpteam.mypump.fotos

import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.fotos.FotoDePrueba.esRojo
import com.pumpteam.mypump.fotos.FotoDePrueba.imagen
import com.pumpteam.mypump.fotos.FotoDePrueba.propiedades
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * REV-02, gemela de `ReduccionFotoTests` de iOS: lo que sale del teléfono es un JPEG con el lado mayor ≤ 900 px (fotos de
 * progreso, calidad 0,7), con la orientación de la cámara aplicada y sin EXIF ni ubicación. Las fotos se arman acá
 * ([FotoDePrueba]); la HEIC es un archivo de prueba (`androidTest/assets/fotos/con-gps.heic`, 2400×1600 con GPS y un
 * comentario EXIF), porque Android no sabe codificar HEIC sin librerías.
 */
@RunWith(AndroidJUnit4::class)
class ReduccionFotoTest {
    private val instr = InstrumentationRegistry.getInstrumentation()

    private fun archivo(ancho: Int, alto: Int, orientacion: Int = ExifInterface.ORIENTATION_NORMAL, conGps: Boolean = true): ByteArray {
        val img = imagen(ancho, alto)
        try {
            return FotoDePrueba.jpegDeCamara(instr.targetContext, img, orientacion, conGps)
        } finally {
            img.recycle()
        }
    }

    @Test
    fun unaFotoDeCamaraSaleChicaDerechaYSinUbicacion() {
        // 4032×3024 apaisada con orientación 6: en pantalla es vertical (3024×4032), con el bloque rojo arriba a la derecha.
        val original = archivo(4032, 3024, orientacion = ExifInterface.ORIENTATION_ROTATE_90)
        assertNotNull("la original no tiene GPS: la prueba no probaría nada", propiedades(original).exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
        val jpeg = ReduccionFoto.jpeg(original, maxPx = 900, calidad = 0.7)
        assertNotNull(jpeg)
        val r = propiedades(jpeg!!)
        assertEquals("image/jpeg", r.tipo)
        assertEquals("quedó ${r.ancho}×${r.alto}", 675 to 900, r.ancho to r.alto)
        assertNull("salió con la ubicación", r.exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
        assertNull("salió con el EXIF de la original", r.exif.getAttribute(ExifInterface.TAG_USER_COMMENT))
        val orientacion = r.exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_UNDEFINED)
        assertTrue(
            "la orientación no quedó aplicada ($orientacion)",
            orientacion == ExifInterface.ORIENTATION_UNDEFINED || orientacion == ExifInterface.ORIENTATION_NORMAL,
        )
        // Girada para el lado correcto: lo de arriba a la izquierda de la guardada queda arriba a la derecha.
        val b = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
        try {
            assertTrue("el bloque rojo no quedó arriba a la derecha", esRojo(b.getPixel(650, 50)))
            assertFalse("arriba a la izquierda no tendría que ser rojo", esRojo(b.getPixel(20, 20)))
            assertFalse("abajo a la izquierda (girada al revés) no tendría que ser rojo", esRojo(b.getPixel(40, 860)))
        } finally {
            b.recycle()
        }
    }

    @Test
    fun unaHEICTambien() {
        // BitmapFactory lee HEIC desde Android 9.
        assumeTrue("este Android no lee HEIC", Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        val heic = instr.context.assets.open("fotos/con-gps.heic").use { it.readBytes() }
        assertEquals("image/heif", propiedades(heic).tipo)
        val jpeg = ReduccionFoto.jpeg(heic, maxPx = 900, calidad = 0.7)
        assertNotNull(jpeg)
        val r = propiedades(jpeg!!)
        assertEquals("image/jpeg", r.tipo)
        assertEquals(900 to 600, r.ancho to r.alto)
        assertNull("salió con la ubicación", r.exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
        assertNull("salió con el EXIF de la original", r.exif.getAttribute(ExifInterface.TAG_USER_COMMENT))
    }

    @Test
    fun unaMasChicaNoSeAgranda() {
        val r = propiedades(ReduccionFoto.jpeg(archivo(400, 300, conGps = false), maxPx = 900, calidad = 0.7)!!)
        assertEquals(400 to 300, r.ancho to r.alto)
    }

    @Test
    fun laCalidadPesa() {
        val original = archivo(1600, 1200, conGps = false)
        val a = ReduccionFoto.jpeg(original, maxPx = 900, calidad = 0.7)!!
        val b = ReduccionFoto.jpeg(original, maxPx = 900, calidad = 0.95)!!
        assertTrue("0,7 pesa ${a.size} y 0,95 ${b.size}", a.size < b.size)
    }

    @Test
    fun loQueNoEsUnaImagenDaNull() {
        assertNull(ReduccionFoto.jpeg("no es una foto".toByteArray(), maxPx = 900, calidad = 0.7))
        assertNull(ReduccionFoto.jpeg(ByteArray(0), maxPx = 900, calidad = 0.7))
    }

    /**
     * Las 8 orientaciones de EXIF (iOS lo resuelve ImageIO; acá es a mano): las que giran cambian ancho por alto, y el
     * bloque rojo de arriba a la izquierda de la guardada termina en la esquina que corresponde.
     */
    @Test
    fun lasOchoOrientaciones() {
        // Dónde queda lo de arriba a la izquierda: 1 y 5 arriba a la izquierda, 2 y 6 arriba a la derecha, 3 y 7 abajo a
        // la derecha, 4 y 8 abajo a la izquierda.
        val esquina = mapOf(1 to "↖", 2 to "↗", 3 to "↘", 4 to "↙", 5 to "↖", 6 to "↗", 7 to "↘", 8 to "↙")
        for (o in 1..8) {
            val jpeg = ReduccionFoto.jpeg(archivo(800, 600, orientacion = o, conGps = false), maxPx = 400, calidad = 0.7)!!
            val r = propiedades(jpeg)
            val gira = o in listOf(
                ExifInterface.ORIENTATION_TRANSPOSE, ExifInterface.ORIENTATION_ROTATE_90,
                ExifInterface.ORIENTATION_TRANSVERSE, ExifInterface.ORIENTATION_ROTATE_270,
            )
            assertEquals("orientación $o", if (gira) 300 to 400 else 400 to 300, r.ancho to r.alto)
            val b = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
            try {
                val (w, h) = b.width to b.height
                val esquinas = mapOf("↖" to (15 to 15), "↗" to (w - 16 to 15), "↘" to (w - 16 to h - 16), "↙" to (15 to h - 16))
                val roja = esquinas.filterValues { (x, y) -> esRojo(b.getPixel(x, y)) }.keys
                assertEquals("orientación $o: el rojo quedó en $roja", setOf(esquina.getValue(o)), roja)
            } finally {
                b.recycle()
            }
        }
    }
}
