import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas

@Suite("Documentos: decodificación y textos")
struct DocumentosTests {
    let ba = TimeZone(identifier: "America/Argentina/Buenos_Aires")!

    private func decodificar(_ json: String) throws -> RespuestaDocumentos {
        try JSONDecoder().decode(RespuestaDocumentos.self, from: Data(json.utf8))
    }

    @Test func laRespuestaDelContratoSeLeeEntera() throws {
        let r = try decodificar("""
        {"documentos":[
          {"id":"0b6f3c1e-0000-4000-8000-000000000001","tipo":"servicio_ar","titulo":"Contrato","estado":"pendiente","firmado_en":null,"revocado_en":null},
          {"id":"0b6f3c1e-0000-4000-8000-000000000002","tipo":"consentimiento_ar","titulo":"Consentimiento","estado":"firmado","firmado_en":"2026-11-10T15:03:22.123456+00:00","revocado_en":null}
        ],"pendientes":1}
        """)
        #expect(r.documentos.map(\.tipo) == [.servicioAR, .consentimientoAR])
        #expect(r.documentos.map(\.estado) == [.pendiente, .firmado])
        #expect(r.documentos[1].firmadoEn == "2026-11-10T15:03:22.123456+00:00")
        #expect(r.documentos[0].firmadoEn == nil)
    }

    @Test func loDesconocidoSeDescartaSinTirarLoDemas() throws {
        let r = try decodificar("""
        {"documentos":[
          {"id":"a","tipo":"servicio_ext","estado":"anulado"},
          {"id":"b","tipo":"otro_tipo","estado":"pendiente"},
          {"tipo":"servicio_ar","estado":"pendiente"},
          null, 7,
          {"id":"c","tipo":"servicio_ext","estado":"revocado","revocado_en":"2026-11-12 03:30:00+00"}
        ]}
        """)
        #expect(r.documentos.map(\.id) == ["c"])
        #expect(try decodificar(#"{"documentos":"nada"}"#).documentos.isEmpty)
        #expect(try decodificar("{}").documentos.isEmpty)
    }

    @Test func nombresPorTipo() {
        #expect(TextosDocumentos.nombre(.servicioAR) == "Contrato de coaching")
        #expect(TextosDocumentos.nombre(.servicioExt) == "Contrato de coaching")
        #expect(TextosDocumentos.nombre(.consentimientoAR) == "Consentimiento de atención médica")
    }

    @Test func estadoATexto() {
        let p = DocumentoFirma(id: "1", tipo: .servicioAR, estado: .pendiente)
        #expect(TextosDocumentos.estado(p, zona: ba) == "Pendiente de firma")
        #expect(TextosDocumentos.boton(.pendiente) == "Leer y firmar")
        let f = DocumentoFirma(id: "2", tipo: .servicioAR, estado: .firmado, firmadoEn: "2026-11-10T15:03:22.123456+00:00")
        #expect(TextosDocumentos.estado(f, zona: ba) == "Firmado el 10/11/2026")
        #expect(TextosDocumentos.boton(.firmado) == "Ver documento")
        // 02:30 UTC del 12 son las 23:30 del 11 en Argentina: la fecha es la del teléfono.
        let r = DocumentoFirma(id: "3", tipo: .consentimientoAR, estado: .revocado, revocadoEn: "2026-11-12 02:30:00+00")
        #expect(TextosDocumentos.estado(r, zona: ba) == "Revocado el 11/11/2026")
        #expect(TextosDocumentos.boton(.revocado) == "Ver documento")
        // Sin fecha legible, el estado solo.
        let sin = DocumentoFirma(id: "4", tipo: .servicioAR, estado: .firmado, firmadoEn: "ayer")
        #expect(TextosDocumentos.estado(sin, zona: ba) == "Firmado")
    }

    @Test func elAvisoSoloConUnContratoPendiente() {
        #expect(!TextosDocumentos.hayContratoPendiente([]))
        #expect(!TextosDocumentos.hayContratoPendiente([DocumentoFirma(id: "1", tipo: .consentimientoAR, estado: .pendiente)]))
        #expect(!TextosDocumentos.hayContratoPendiente([DocumentoFirma(id: "1", tipo: .servicioAR, estado: .firmado)]))
        #expect(TextosDocumentos.hayContratoPendiente([DocumentoFirma(id: "1", tipo: .servicioExt, estado: .pendiente)]))
    }

    @Test func sinPagosNiPrecios() {
        let textos = [TextosDocumentos.titulo, TextosDocumentos.pie, TextosDocumentos.avisoContrato, TextosDocumentos.avisoContratoDetalle,
                      TextosDocumentos.errorAbrir, TextosDocumentos.leerYFirmar, TextosDocumentos.verDocumento]
            + TipoDocumento.allCases.map(TextosDocumentos.nombre)
        for t in textos {
            for palabra in ["pago", "pagar", "precio", "cuota", "$", "usd", "comprar", "suscrip"] {
                #expect(!t.lowercased().contains(palabra), "«\(t)» nombra «\(palabra)»")
            }
        }
    }
}
