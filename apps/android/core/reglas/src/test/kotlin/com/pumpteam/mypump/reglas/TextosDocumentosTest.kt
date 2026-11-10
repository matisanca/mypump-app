package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.DocumentoFirma
import com.pumpteam.mypump.modelos.EstadoDocumento
import com.pumpteam.mypump.modelos.TipoDocumento
import java.time.ZoneId
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Documentos: nombres, estado a texto (iguales a `DocumentosTests.swift`) y cuándo va el aviso. */
class TextosDocumentosTest {
    private val ba = ZoneId.of("America/Argentina/Buenos_Aires")

    @Test
    fun nombresPorTipo() {
        assertEquals("Contrato de coaching", TextosDocumentos.nombre(TipoDocumento.SERVICIO_AR))
        assertEquals("Contrato de coaching", TextosDocumentos.nombre(TipoDocumento.SERVICIO_EXT))
        assertEquals("Consentimiento de atención médica", TextosDocumentos.nombre(TipoDocumento.CONSENTIMIENTO_AR))
    }

    @Test
    fun estadoATexto() {
        assertEquals("Pendiente de firma", TextosDocumentos.estado(DocumentoFirma("1", TipoDocumento.SERVICIO_AR, EstadoDocumento.PENDIENTE), ba))
        assertEquals("Leer y firmar", TextosDocumentos.boton(EstadoDocumento.PENDIENTE))
        val f = DocumentoFirma("2", TipoDocumento.SERVICIO_AR, EstadoDocumento.FIRMADO, firmadoEn = "2026-11-10T15:03:22.123456+00:00")
        assertEquals("Firmado el 10/11/2026", TextosDocumentos.estado(f, ba))
        assertEquals("Ver documento", TextosDocumentos.boton(EstadoDocumento.FIRMADO))
        // 02:30 UTC del 12 son las 23:30 del 11 en Argentina: la fecha es la del teléfono.
        val r = DocumentoFirma("3", TipoDocumento.CONSENTIMIENTO_AR, EstadoDocumento.REVOCADO, revocadoEn = "2026-11-12 02:30:00+00")
        assertEquals("Revocado el 11/11/2026", TextosDocumentos.estado(r, ba))
        assertEquals("Ver documento", TextosDocumentos.boton(EstadoDocumento.REVOCADO))
        // Sin fecha legible, el estado solo.
        assertEquals("Firmado", TextosDocumentos.estado(DocumentoFirma("4", TipoDocumento.SERVICIO_AR, EstadoDocumento.FIRMADO, firmadoEn = "ayer"), ba))
    }

    @Test
    fun elAvisoSoloConUnContratoPendiente() {
        assertFalse(TextosDocumentos.hayContratoPendiente(emptyList()))
        assertFalse(TextosDocumentos.hayContratoPendiente(listOf(DocumentoFirma("1", TipoDocumento.CONSENTIMIENTO_AR, EstadoDocumento.PENDIENTE))))
        assertFalse(TextosDocumentos.hayContratoPendiente(listOf(DocumentoFirma("1", TipoDocumento.SERVICIO_AR, EstadoDocumento.FIRMADO))))
        assertTrue(TextosDocumentos.hayContratoPendiente(listOf(DocumentoFirma("1", TipoDocumento.SERVICIO_EXT, EstadoDocumento.PENDIENTE))))
    }

    @Test
    fun elErrorEsElPedido() {
        assertEquals(
            "No pudimos abrir el documento. Probá de nuevo en un rato o usá el enlace que te llegó por correo.",
            TextosDocumentos.errorAbrir,
        )
    }
}
