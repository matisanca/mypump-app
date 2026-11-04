import Foundation
import Testing
@testable import MyPumpReglas

/// La semana de revisión y el día del aviso (R2 de la 2.0.3), contra apps/shared/vectores/aviso_revision.json: los mismos
/// casos que lee SemanaRevisionTest.kt.
struct SemanaRevisionTests {
    private struct Archivo: Decodable {
        struct Caso: Decodable {
            let hoy: String
            let hora: String
            let completa: Bool
            let revisionDia: Int
            let semana: String
            let aviso: String
        }
        let casos: [Caso]
    }

    @Test func vectores() throws {
        let url = raizRepo.appendingPathComponent("apps/shared/vectores/aviso_revision.json")
        let a = try JSONDecoder().decode(Archivo.self, from: Data(contentsOf: url))
        #expect(!a.casos.isEmpty)
        for c in a.casos {
            let p = c.hora.split(separator: ":").compactMap { Int($0) }
            let minutos = p[0] * 60 + p[1]
            #expect(SemanaRevision.lunes(c.hoy, dia: c.revisionDia) == c.semana, "\(c.hoy) día \(c.revisionDia)")
            #expect(SemanaRevision.fechaAviso(hoy: c.hoy, minutos: minutos, completa: c.completa, dia: c.revisionDia) == c.aviso,
                    "\(c.hoy) \(c.hora) completa=\(c.completa) día \(c.revisionDia)")
        }
    }

    @Test func conElDomingoEsLaSemanaISO() {
        for f in ["2026-10-26", "2026-10-29", "2026-11-01", "2026-11-02"] {
            #expect(SemanaRevision.lunes(f) == FotosProgreso.lunes(f))
        }
    }

    @Test func completaEsLoMismoQueElBadgeEnCero() {
        let todas: Set<String> = ["frente", "perfil", "espalda"]
        #expect(SemanaRevision.completa(checkinEnviado: true, posesDeLaSemana: todas))
        #expect(!SemanaRevision.completa(checkinEnviado: false, posesDeLaSemana: todas))
        #expect(!SemanaRevision.completa(checkinEnviado: true, posesDeLaSemana: ["frente", "perfil"]))
        #expect(!SemanaRevision.completa(checkinEnviado: false, posesDeLaSemana: []))
    }

    @Test func unDiaRaroValeElDomingo() {
        #expect(SemanaRevision.normalizado(nil) == 7)
        #expect(SemanaRevision.normalizado(0) == 7)
        #expect(SemanaRevision.normalizado(8) == 7)
        #expect(SemanaRevision.normalizado(6) == 6)
        #expect(SemanaRevision.fechaAviso(hoy: "2026-10-31", minutos: 600, completa: false, dia: 99) == "2026-11-01")
        #expect(SemanaRevision.fechaAviso(hoy: "no es fecha", minutos: 600, completa: false) == nil)
    }
}
