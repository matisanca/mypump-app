package com.pumpteam.mypump.fotos

import java.time.OffsetDateTime
import java.time.ZoneId
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** La fecha de captura de la original (`tomada_en` de las fotos de inicio), como la escribe la cámara en el EXIF. */
class FechaExifTest {
    private val baires = ZoneId.of("America/Argentina/Buenos_Aires")

    @Test fun conYSinZona() {
        assertEquals(OffsetDateTime.parse("2026-11-09T18:30:05+02:00"), ReduccionFoto.fechaExif("2026:11:09 18:30:05", "+02:00", baires))
        // Sin la zona de la cámara, la del teléfono.
        assertEquals(OffsetDateTime.parse("2026-11-09T18:30:05-03:00"), ReduccionFoto.fechaExif("2026:11:09 18:30:05", null, baires))
        assertEquals(OffsetDateTime.parse("2026-11-09T18:30:05-03:00"), ReduccionFoto.fechaExif(" 2026:11:09 18:30:05 ", "  ", baires))
    }

    @Test fun loQueNoSeEntiendeEsNulo() {
        assertNull(ReduccionFoto.fechaExif(null, null, baires))
        assertNull(ReduccionFoto.fechaExif("0000:00:00 00:00:00", null, baires))
        assertNull(ReduccionFoto.fechaExif("ayer", null, baires))
        assertNull(ReduccionFoto.fechaExif("2026:11:09 18:30:05", "zona rara", baires))
    }
}
