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
}
