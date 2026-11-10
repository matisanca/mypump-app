package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.reglas.ReglasChatAdjuntos.Subida
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

/** Las reglas de fotos y audios del chat, con los casos de iOS (`ReglasChatAdjuntosTests`). */
class ChatAdjuntosTest {
    @Test
    fun loQueContestaMiniVision() {
        val r = ReglasChatAdjuntos
        assertEquals(Subida.OK, r.subida(200, true, null))
        assertEquals(Subida.REINTENTAR, r.subida(200, false, null))
        assertEquals(Subida.REINTENTAR, r.subida(0, false, null))
        assertEquals(Subida.REINTENTAR, r.subida(503, false, "no se pudo subir"))
        assertEquals(Subida.REINTENTAR, r.subida(408, false, null))
        assertEquals(Subida.TOPE, r.subida(429, false, null))
        assertEquals(Subida.ID_REPETIDO, r.subida(409, false, "id repetido"))
        assertEquals(Subida.TOKEN, r.subida(403, false, "token inválido"))
        assertEquals(Subida.RECHAZO, r.subida(403, false, "no habilitado"))
        assertEquals(Subida.RECHAZO, r.subida(413, false, "archivo muy grande"))
        assertEquals(Subida.RECHAZO, r.subida(400, false, "la imagen debe ser JPEG"))
    }

    @Test
    fun duraciones() {
        assertEquals("0:07", ReglasChatAdjuntos.duracion(7.0))
        assertEquals("0:42", ReglasChatAdjuntos.duracion(42.4))
        assertEquals("2:00", ReglasChatAdjuntos.duracion(120.0))
        assertEquals("0:00", ReglasChatAdjuntos.duracion(-3.0))
        assertEquals("0:00", ReglasChatAdjuntos.duracion(Double.NaN))
        assertEquals("Audio de 1:05", ReglasChatAdjuntos.textoAudio(65.0))
        assertEquals("1 segundo", ReglasChatAdjuntos.duracionHablada(1.0))
        assertEquals("1 minuto 5 segundos", ReglasChatAdjuntos.duracionHablada(65.0))
        assertEquals("2 minutos", ReglasChatAdjuntos.duracionHablada(120.0))
    }

    /** Ningún texto de la pantalla nombra a la IA, la transcripción ni a «tu entrenador»; sin «:» ni guiones ni emojis. */
    @Test
    fun losTextosNoNombranNadaInterno() {
        val prohibidos = listOf("ia", "inteligencia", "transcrib", "texto", "entrenador", "coach", "automátic", "robot")
        for (t in ReglasChatAdjuntos.TEXTOS) {
            val palabras = t.lowercase().split(Regex("[^\\p{L}]+"))
            for (p in prohibidos) assertFalse(palabras.any { it.startsWith(p) }, "«$t» dice $p")
            assertFalse(":" in t || " - " in t || "—" in t, "«$t»")
        }
    }
}
