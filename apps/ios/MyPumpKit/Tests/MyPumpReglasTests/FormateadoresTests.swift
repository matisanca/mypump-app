import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// Progreso creaba dos `ISO8601DateFormatter` por fila: con el historial más largo que deja el servidor (48 filas por
/// ejercicio, 2.880 en total) tardaba 1,5 s en el hilo principal (15-oct). Con los formateadores compartidos, 0,25 s.
@Suite("Formateadores compartidos")
struct FormateadoresTests {
    static let filas: [RegistroHistorico] = {
        var t: [String] = []
        for e in 0..<60 {
            for s in 0..<12 { for serie in 1...4 {
                let dia = String(format: "2026-%02d-%02d %02d:00:00.123456+00", 1 + s % 9, 1 + s * 2 % 27, 8 + serie)
                t.append(#"{"clave":"ejercicio-\#(e)","registrado_en":"\#(dia)","peso_kg":\#(40 + s),"reps_realizadas":8,"rir_real":2,"serie_numero":\#(serie),"notas":null,"ejercicio_nombre":"E\#(e)"}"#)
            } }
        }
        return try! JSONDecoder().decode([RegistroHistorico].self, from: Data(("[" + t.joined(separator: ",") + "]").utf8))
    }()

    /// Antes 0,8 s; con los formateadores compartidos, unos 0,15 s en debug. Con un formateador por fila vuelve a 0,4 s:
    /// el umbral está en el medio, y se toma la mejor de tres corridas para que la carga de la máquina no la haga fallar.
    @Test func lasFechasDeTodoElHistorialSalenRapido() {
        let reloj = ContinuousClock()
        var dias = 0
        let mejor = (0..<3).map { _ in
            reloj.measure { dias = ProgresoEjercicio.sesiones(Self.filas, zona: TimeZone(identifier: "UTC")!).count }
        }.min()!
        #expect(dias == 12)
        #expect(mejor < .milliseconds(300), "las fechas locales de \(Self.filas.count) filas tardaron \(mejor)")
    }

    /// Lo que leen: PostgREST con espacio, microsegundos y `+00`; ISO con `Z`; sin decimales; y lo que no es una fecha.
    @Test func leenLoMismoQueAntes() {
        let t = 1_791_986_340.0   // 2026-10-14T13:59:00Z
        func cerca(_ d: Date?, _ x: Double) -> Bool { d.map { abs($0.timeIntervalSince1970 - x) < 0.0005 } ?? false }
        #expect(cerca(Formateadores.instante("2026-10-14 13:59:00.123456+00"), t + 0.123))
        #expect(cerca(Formateadores.instante("2026-10-14T13:59:00.123Z"), t + 0.123))
        #expect(cerca(Formateadores.instante("2026-10-14T13:59:00Z"), t))
        #expect(cerca(Formateadores.instante("2026-10-14T10:59:00-03:00"), t))
        #expect(Formateadores.instante("2026-10-14") == nil)
        #expect(Formateadores.instante("") == nil)
        let ba = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        #expect(FechaLocal.de("2026-10-15 01:30:00+00", zona: ba) == "2026-10-14")
        #expect(FechaLocal.de("2026-10-15", zona: ba) == "2026-10-15")
        #expect(Formateadores.gregoriano(ba).timeZone == ba)
        #expect(Formateadores.fecha("dd-MMM", zona: ba, locale: "es_AR") === Formateadores.fecha("dd-MMM", zona: ba, locale: "es_AR"))
    }
}
