import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// 2.1, S2: el historial de Progreso como registros del volumen (la regla está en el kit, con vectores).
@Suite("Volumen por músculo: datos")
struct VolumenDatosTests {
    private func filas(_ json: String) throws -> [RegistroHistorico] {
        try JSONDecoder().decode([RegistroHistorico].self, from: Data(json.utf8))
    }

    @Test func elHistorialSaleSinNumeroYConElMusculoDeSuClave() throws {
        let zona = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        let h = try ["press banca": filas(#"[{"clave":"press banca","registrado_en":"2026-11-03T02:30:00+00:00","serie_numero":1},{"clave":"press banca","registrado_en":"2026-11-03T13:00:00+00:00","serie_numero":1}]"#),
                     "cinta": filas(#"[{"clave":"cinta","registrado_en":"2026-11-03T13:00:00+00:00","serie_numero":1}]"#),
                     "viejo": filas(#"[{"clave":"viejo","registrado_en":"2026-11-03T13:00:00+00:00","serie_numero":1}]"#)]
        let info = ["press banca": VolumenDatos.Info(musculo: "chest", tipo: "compuesto"), "cinta": .init(musculo: nil, tipo: "cardio")]
        let r = VolumenDatos.registros(historial: h, ejercicios: info, zona: zona)
        #expect(r.map(\.lugar) == ["cinta", "press banca", "press banca", "viejo"])
        #expect(r.allSatisfy { $0.serie == nil })
        // 02:30 UTC del 3 es el 2 a la noche en Buenos Aires.
        #expect(r.filter { $0.lugar == "press banca" }.map(\.fecha) == ["2026-11-02", "2026-11-03"])
        let v = VolumenMusculo.calcular(historial: r, hoy: "2026-11-04")
        // Las dos series de press cuentan (mismo número, otro día); la cinta no; lo que ya no está en el plan, sin músculo.
        #expect(v.filas.map(\.nombre) == ["Pecho", VolumenMusculo.sinMusculo])
        #expect(v.filas.map(\.semana) == [2, 1])
    }
}
