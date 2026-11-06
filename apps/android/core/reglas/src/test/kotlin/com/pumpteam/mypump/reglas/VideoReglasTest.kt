package com.pumpteam.mypump.reglas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** La caja del reproductor toma la proporción del clip: vertical, horizontal y cuadrado, sin franjas. */
class VideoReglasTest {
    @Test
    fun laProporcionSaleDelTamanoYDelPixel() {
        assertEquals(570f / 720f, ReglasVideo.proporcion(570, 720)!!, 1e-4f)
        assertEquals(1280f / 720f, ReglasVideo.proporcion(1280, 720)!!, 1e-4f)
        assertEquals(1f, ReglasVideo.proporcion(720, 720)!!, 1e-4f)
        // Píxel no cuadrado (anamórfico): 720×720 con píxel 4:3.
        assertEquals(4f / 3f, ReglasVideo.proporcion(720, 720, 4f / 3f)!!, 1e-4f)
        // Todavía sin tamaño (VideoSize.UNKNOWN) o un píxel roto.
        assertNull(ReglasVideo.proporcion(0, 0))
        assertEquals(1f, ReglasVideo.proporcion(720, 720, Float.NaN)!!, 1e-4f)
        assertNull(ReglasVideo.proporcion(10_000, 10))
    }

    @Test
    fun laCajaUsaElAnchoYTopaLosVerticalesAl60PorCiento() {
        // Teléfono de 360×780 dp, tarjeta de 328 dp de ancho.
        val (wh, hh) = ReglasVideo.caja(1280f / 720f, 328f, 780f)
        assertEquals(328f, wh, 0.01f)
        assertEquals(184.5f, hh, 0.01f)
        // Vertical: 328 / 0,79 = 414 dp, entra (tope 468): todo el ancho.
        val (wv, hv) = ReglasVideo.caja(570f / 720f, 328f, 780f)
        assertEquals(328f, wv, 0.01f)
        assertEquals(414.3f, hv, 0.1f)
        // En una tableta (o apaisado) el vertical topa al 60 % del alto y queda angosto, centrado.
        val (wt, ht) = ReglasVideo.caja(570f / 720f, 700f, 900f)
        assertEquals(540f, ht, 0.01f)
        assertEquals(540f * 570f / 720f, wt, 0.01f)
        // El cuadrado, igual.
        assertEquals(328f to 328f, ReglasVideo.caja(1f, 328f, 780f))
        // Una proporción rota cae en 16:9.
        assertEquals(ReglasVideo.caja(ReglasVideo.POR_DEFECTO, 328f, 780f), ReglasVideo.caja(Float.NaN, 328f, 780f))
    }

    @Test
    fun enPantallaCompletaEntraSinDeformarse() {
        assertEquals(360f to 202.5f, ReglasVideo.completa(16f / 9f, 360f, 780f))
        val (w, h) = ReglasVideo.completa(570f / 720f, 360f, 780f)
        assertEquals(360f, w, 0.01f)
        assertEquals(360f * 720f / 570f, h, 0.01f)
        assertEquals(780f * 16f / 9f to 780f, ReglasVideo.completa(16f / 9f, 2000f, 780f))
    }

    /** Un cuadro de [w]×[h] negro (con ruido de compresión, luma 10) y contenido (luma 120) en [x0, x1) × [y0, y1). */
    private fun cuadro(w: Int, h: Int, x0: Int, x1: Int, y0: Int = 0, y1: Int = h): IntArray =
        IntArray(w * h) { i -> val x = i % w; val y = i / w; if (x in x0 until x1 && y in y0 until y1) 120 else if ((x * 31 + y * 17) % 211 == 0) 40 else 10 }

    @Test
    fun detectaLasFranjasMetidasEnElArchivo() {
        // Como FT-2b: 1280×720 con contenido solo en las columnas 422 a 855.
        val r = ReglasVideo.recuadroDe(cuadro(1280, 720, 422, 856), 1280, 720)!!
        assertEquals(422f / 1280f, r.izquierda, 1e-4f)
        assertEquals(856f / 1280f, r.derecha, 1e-4f)
        assertEquals(0f, r.arriba)
        assertEquals(1f, r.abajo)
        // Se recorta con 1 px hacia adentro en los lados recortados (arriba y abajo quedan enteros), y la caja queda
        // vertical (432×720).
        val recorte = ReglasVideo.recorte(r, 1280, 720)!!
        assertEquals(423f / 1280f, recorte.izquierda, 1e-4f)
        assertEquals(855f / 1280f, recorte.derecha, 1e-4f)
        assertEquals(0f, recorte.arriba)
        assertEquals(1f, recorte.abajo)
        assertEquals(432f / 720f, ReglasVideo.proporcionVisible(1280f / 720f, recorte), 1e-3f)
        // La unión de tres cuadros (uno es un fundido a negro).
        val u = ReglasVideo.union(listOf(
            ReglasVideo.recuadroDe(cuadro(1280, 720, 430, 850), 1280, 720),
            null,
            ReglasVideo.recuadroDe(cuadro(1280, 720, 422, 856), 1280, 720),
        ))
        assertEquals(r, u)
        assertNull(ReglasVideo.recuadroDe(IntArray(1280 * 720) { 10 }, 1280, 720))
        assertNull(ReglasVideo.union(listOf(null, null)))
        // La caché en disco.
        assertEquals(recorte, ReglasVideo.Recuadro.desde(recorte.aTexto()))
        assertNull(ReglasVideo.Recuadro.desde("1,2"))
        assertNull(ReglasVideo.Recuadro.desde("0.5,0,0.4,1"))
    }

    @Test
    fun unClipSinFranjasNoSeRecorta() {
        val r = ReglasVideo.recuadroDe(cuadro(1280, 720, 0, 1280), 1280, 720)!!
        assertEquals(ReglasVideo.Recuadro(0f, 0f, 1f, 1f), r)
        assertNull(ReglasVideo.recorte(r, 1280, 720))
        assertEquals(16f / 9f, ReglasVideo.proporcionVisible(16f / 9f, null))
        // Contenido oscuro pero con textura en el borde (no parejo): no se toca.
        val texturado = IntArray(1280 * 720) { i -> val x = i % 1280; val y = i / 1280; if ((x / 3 + y / 3) % 2 == 0) 60 else 5 }
        assertNull(ReglasVideo.recorte(ReglasVideo.recuadroDe(texturado, 1280, 720), 1280, 720))
    }

    @Test
    fun quitaUnBordeOscuroParejoFinoComoIOS() {
        // Bordes negros de 40 px (3 %) a los costados: el umbral solo no los quitaría (ocupa el 94 %), el borde parejo sí.
        val r = ReglasVideo.recuadroDe(cuadro(1280, 720, 40, 1240), 1280, 720)!!
        assertEquals(40f / 1280f, r.izquierda, 1e-4f)
        assertEquals(1240f / 1280f, r.derecha, 1e-4f)
        val recorte = ReglasVideo.recorte(r, 1280, 720)!!
        assertEquals(41f / 1280f, recorte.izquierda, 1e-4f)
        // Un borde gris parejo (media 30 < 40) de 20 px arriba también; uno más ancho que el 4 % se quita solo hasta el 4 %.
        val gris = IntArray(1280 * 720) { i -> val y = i / 1280; if (y < 20) 30 else 120 }
        assertEquals(20f / 720f, ReglasVideo.recuadroDe(gris, 1280, 720)!!.arriba, 1e-4f)
        val ancho = IntArray(1280 * 720) { i -> val y = i / 1280; if (y < 60) 30 else 120 }
        assertEquals(28f / 720f, ReglasVideo.recuadroDe(ancho, 1280, 720)!!.arriba, 1e-4f)
        // Letterbox de verdad (arriba y abajo 90 px): por el umbral, sin límite del 4 %.
        val lb = ReglasVideo.recorte(ReglasVideo.recuadroDe(cuadro(1280, 720, 0, 1280, 90, 630), 1280, 720), 1280, 720)!!
        assertEquals(1280f / 538f, ReglasVideo.proporcionVisible(16f / 9f, lb), 0.01f)
    }

    @Test
    fun laTransformacionLlenaLaCajaConLaZonaUtil() {
        // Caja de 300×493 (la proporción de lo útil); la vista de Media3 en FIT: 300×169 centrada (y = 162).
        val r = ReglasVideo.Recuadro(422f / 1280f, 0f, 856f / 1280f, 1f)
        val (sx, sy, tx, ty) = ReglasVideo.transformacion(r, 0f, 162f, 300f, 168.75f, 300f, 493f)
        // El borde izquierdo de lo útil (x = 98,9 en la vista) cae en 0, y el derecho en 300.
        assertEquals(0f, tx + sx * (r.izquierda * 300f), 0.01f)
        assertEquals(300f, tx + sx * (r.derecha * 300f), 0.01f)
        assertEquals(0f, 162f + ty + sy * 0f, 0.01f)
        assertEquals(493f, 162f + ty + sy * 168.75f, 0.01f)
    }
}
