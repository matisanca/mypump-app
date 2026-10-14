import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

private func reg(_ fecha: String, _ kg: Double?) -> RegistroHistorico {
    var o: [String: JSONValue] = ["registrado_en": .texto(fecha), "clave": .texto("x")]
    o["peso_kg"] = kg.map(JSONValue.numero) ?? .null
    return try! JSONDecoder().decode(RegistroHistorico.self, from: JSONEncoder().encode(JSONValue.objeto(o)))
}

@Suite("Progreso: el resumen por ejercicio de la web")
struct ProgresoTests {
    let ar = TimeZone(identifier: "America/Argentina/Buenos_Aires")!

    @Test func maximoPorSesionUltimasOchoYVariacion() throws {
        // 10 sesiones (de la más nueva a la más vieja, como llegan), dos series por sesión.
        var filas: [RegistroHistorico] = []
        for d in (1...10).reversed() {
            filas.append(reg(String(format: "2026-09-%02dT14:00:00+00:00", d), Double(50 + d)))
            filas.append(reg(String(format: "2026-09-%02dT14:05:00+00:00", d), Double(45 + d)))
        }
        let r = try #require(ProgresoEjercicio.resumen(filas, zona: ar))
        #expect(r.serie == [53, 54, 55, 56, 57, 58, 59, 60])
        #expect(r.tope == 60)
        #expect(r.variacion == 13.2)          // (60-53)/53 = 13,207…
        #expect(r.esPR)
        #expect(ProgresoEjercicio.sesiones(filas, zona: ar).count == 10)
    }

    @Test func sinPRSiLaUltimaNoSuperaYUnaSolaSesion() throws {
        let r = try #require(ProgresoEjercicio.resumen([reg("2026-09-02T14:00:00+00:00", 60), reg("2026-09-01T14:00:00+00:00", 60)], zona: ar))
        #expect(!r.esPR)
        #expect(r.variacion == 0)
        let una = try #require(ProgresoEjercicio.resumen([reg("2026-09-01T14:00:00+00:00", 60)], zona: ar))
        #expect(una.variacion == nil && !una.esPR)
        #expect(ProgresoEjercicio.resumen([], zona: ar) == nil)
    }

    @Test func laFechaEsLaLocal() {
        // 01:30 UTC del 2/9 es el 1/9 en Buenos Aires.
        #expect(FechaLocal.de("2026-09-02T01:30:00.123456+00:00", zona: ar) == "2026-09-01")
        #expect(FechaLocal.de("basura", zona: ar) == "basura")
        #expect(FechaLocal.de("", zona: ar) == "")
    }

    @Test func pesoNuloCuentaComoCero() throws {
        let r = try #require(ProgresoEjercicio.resumen([reg("2026-09-02T14:00:00+00:00", 40), reg("2026-09-01T14:00:00+00:00", nil)], zona: ar))
        #expect(r.serie == [0, 40])
        #expect(r.variacion == nil)           // arranca en 0
        #expect(r.esPR)
    }
}
