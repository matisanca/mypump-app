import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

// La línea de «Tu progreso» en Revisión, contra los vectores compartidos con Android (progreso_semana.json).
private struct ArchivoProgreso: Decodable {
    struct Ejercicio: Decodable { let nombre: String; let sesiones: [String: Double] }
    struct Esperado: Decodable { let texto: String; let record: Bool }
    struct Caso: Decodable { let nombre: String; let hoy: String; let ejercicios: [Ejercicio]; let esperado: Esperado? }
    struct Kilo: Decodable {
        let kg: Double; let texto: String
        init(from d: Decoder) throws { var c = try d.unkeyedContainer(); kg = try c.decode(Double.self); texto = try c.decode(String.self) }
    }
    let kilos: [Kilo]
    let casos: [Caso]
}

@Suite("Tu progreso en Revisión")
struct ProgresoSemanaTests {
    private func archivo() throws -> ArchivoProgreso {
        try JSONDecoder().decode(ArchivoProgreso.self, from: Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/progreso_semana.json")))
    }

    @Test func comoLosVectores() throws {
        let a = try archivo()
        #expect(a.casos.count == 9)
        for c in a.casos {
            let r = ProgresoSemana.linea(c.ejercicios.map { .init(nombre: $0.nombre, sesiones: $0.sesiones) }, hoy: c.hoy)
            #expect(r?.texto == c.esperado?.texto, "\(c.nombre)")
            #expect(r?.record == c.esperado?.record, "\(c.nombre)")
            #expect(!(r?.texto.contains("🏆") ?? false), "Sin emojis en el texto")
        }
        for k in a.kilos { #expect(ProgresoSemana.kilos(k.kg) == k.texto) }
    }

    @Test func desdeElHistorial() throws {
        let filas = try JSONDecoder().decode([RegistroHistorico].self, from: Data("""
        [{"registrado_en":"2026-11-03T15:00:00Z","peso_kg":80},{"registrado_en":"2026-11-03T15:05:00Z","peso_kg":82.5},
         {"registrado_en":"2026-10-27T15:00:00Z","peso_kg":null}]
        """.utf8))
        let e = ProgresoSemana.ejercicio(nombre: "Press banca", filas: filas, zona: TimeZone(identifier: "America/Argentina/Buenos_Aires")!)
        #expect(e.sesiones == ["2026-11-03": 82.5, "2026-10-27": 0])
    }
}
