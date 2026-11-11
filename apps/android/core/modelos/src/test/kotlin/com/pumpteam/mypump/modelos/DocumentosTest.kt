package com.pumpteam.mypump.modelos

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Documentos: la respuesta de `mypump_contrato_get` y la del servicio de firma. Datos ficticios. */
class DocumentosTest {
    @Test
    fun laRespuestaDelContratoSeLeeEntera() {
        val docs = DocumentoFirma.lista(
            ValorJson.parsear(
                """
                {"documentos":[
                  {"id":"0b6f3c1e-0000-4000-8000-000000000001","tipo":"servicio_ar","titulo":"Contrato","estado":"pendiente","firmado_en":null,"revocado_en":null},
                  {"id":"0b6f3c1e-0000-4000-8000-000000000002","tipo":"consentimiento_ar","titulo":"Consentimiento","estado":"firmado","firmado_en":"2026-11-10T15:03:22.123456+00:00","revocado_en":null}
                ],"pendientes":1}
                """,
            ),
        )
        assertEquals(listOf(TipoDocumento.SERVICIO_AR, TipoDocumento.CONSENTIMIENTO_AR), docs.map { it.tipo })
        assertEquals(listOf(EstadoDocumento.PENDIENTE, EstadoDocumento.FIRMADO), docs.map { it.estado })
        assertEquals("2026-11-10T15:03:22.123456+00:00", docs[1].firmadoEn)
        assertNull(docs[0].firmadoEn)
    }

    @Test
    fun loDesconocidoSeDescartaSinTirarLoDemas() {
        val docs = DocumentoFirma.lista(
            ValorJson.parsear(
                """
                {"documentos":[
                  {"id":"a","tipo":"servicio_ext","estado":"anulado"},
                  {"id":"b","tipo":"otro_tipo","estado":"pendiente"},
                  {"tipo":"servicio_ar","estado":"pendiente"},
                  null, 7,
                  {"id":"c","tipo":"servicio_ext","estado":"revocado","revocado_en":"2026-11-12 03:30:00+00"}
                ]}
                """,
            ),
        )
        assertEquals(listOf("c"), docs.map { it.id })
        assertTrue(DocumentoFirma.lista(ValorJson.parsear("""{"documentos":"nada"}""")).isEmpty())
        assertTrue(DocumentoFirma.lista(ValorJson.parsear("{}")).isEmpty())
        assertTrue(DocumentoFirma.lista(ValorJson.parsear("[]")).isEmpty())
        assertTrue(DocumentoFirma.lista(ValorJson.Nulo).isEmpty())
        assertTrue(DocumentoFirma.lista(null as ValorJson?).isEmpty())
    }

    @Test
    fun losEnlacesDelServicio() {
        val e = EnlaceDocumento.lista(
            ValorJson.parsear(
                """{"documentos":[{"id":"d1","tipo":"servicio_ar","estado":"pendiente","firmado_en":null,"url":"https://firma.mypumpteam.com/f/x"},{"id":"d2","url":null},{"url":"https://firma.mypumpteam.com/f/y"}]}""",
            ),
        )
        assertEquals(listOf(EnlaceDocumento("d1", "https://firma.mypumpteam.com/f/x")), e)
        assertTrue(EnlaceDocumento.lista(ValorJson.parsear("""{"error":"token"}""")).isEmpty())
    }
}
