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
            #expect(FotosProgreso.lunes(c.hoy) == c.semana, "\(c.hoy) día \(c.revisionDia)")
            #expect(SemanaRevision.fechaAviso(hoy: c.hoy, minutos: minutos, completa: c.completa, dia: c.revisionDia) == c.aviso,
                    "\(c.hoy) \(c.hora) completa=\(c.completa) día \(c.revisionDia)")
        }
    }

    @Test func elTextoDelDiaSoloApareceParaQuienNoRevisaElDomingo() {
        #expect(SemanaRevision.textoDia(7) == nil)
        #expect(SemanaRevision.textoDia(nil) == nil)
        #expect(SemanaRevision.textoDia(99) == nil)
        #expect(SemanaRevision.textoDia(6) == "Tu día de revisión es el sábado")
        #expect(SemanaRevision.textoDia(1) == "Tu día de revisión es el lunes")
    }

    /// Un alumno del sábado: el domingo es todavía la misma semana, y lo cargado ese domingo no le adelanta el próximo aviso.
    @Test func elDomingoSigueSiendoDeLaMismaSemana() {
        #expect(SemanaRevision.fechaAviso(hoy: "2026-11-01", minutos: 600, completa: true, dia: 6) == "2026-11-07")
        #expect(SemanaRevision.fechaAviso(hoy: "2026-10-30", minutos: 600, completa: true, dia: 6) == "2026-11-07")
        #expect(SemanaRevision.fechaAviso(hoy: "2026-10-30", minutos: 600, completa: false, dia: 6) == "2026-10-31")
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

    /// El entreno que el reloj de MyPump guarda en Salud vuelve al iPhone por HealthKit: no se ingiere como si fuera externo.
    @Test func elEntrenoDelRelojDeMyPumpNoSeIngiere() {
        let propio = EntrenoCrudo(tipo: "strengthTraining", duracion: 3600, inicio: 1_000, fin: 3_601_000, kcal: 300,
                                  fuenteId: PuenteSalud.bundleDelReloj)
        let ajeno = EntrenoCrudo(tipo: "strengthTraining", duracion: 1800, inicio: 5_000_000, fin: 6_800_000, kcal: 150,
                                 fuenteId: "com.apple.health.ABC")
        let sinFuente = EntrenoCrudo(tipo: "walking", duracion: 600, inicio: 9_000_000, fin: 9_600_000)
        let filas = PuenteSalud.entrenos([propio, ajeno, sinFuente], fc: [])
        #expect(filas.map(\.tipo) == ["strengthTraining", "walking"])
        #expect(filas.first?.kcal == 150)
    }
}
