import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

let raizRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let carpetaPrivada = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/nativa-evidencia/privado/vectores")

/// Vectores generados con las funciones REALES de la web (scripts/nativa/generar-vectores.mjs).
struct ArchivoVectores: Decodable {
    let fuente: String
    let ejercicios: [JSONValue]
    let casos: [Caso]

    struct Caso: Decodable {
        let e: Int
        let semana: Int
        let actual: JSONValue
        let nota: JSONValue
    }
}

/// Igualdad entre lo que devolvió JS (número, texto o null) y lo que da Swift.
func igual(_ esperado: JSONValue?, _ swift: String?) -> Bool {
    switch esperado {
    case .none, .some(.null): return swift == nil
    case .some(.texto(let s)): return s == swift
    case .some(.numero(let d)): return swift == (d == d.rounded() ? String(Int(d)) : String(d))
    default: return false
    }
}

func igual(_ esperado: JSONValue?, _ swift: Int?) -> Bool {
    switch esperado {
    case .none, .some(.null): return swift == nil
    case .some(.numero(let d)): return swift == Int(d)
    case .some(.texto(let s)): return swift == Int(s)
    default: return false
    }
}

func verificar(_ archivo: URL) throws -> (total: Int, fallas: [String]) {
    let v = try JSONDecoder().decode(ArchivoVectores.self, from: Data(contentsOf: archivo))
    let ejercicios = try v.ejercicios.map { try JSONDecoder().decode(Ejercicio.self, from: JSONEncoder().encode($0)) }
    var fallas: [String] = []
    for c in v.casos {
        let e = ejercicios[c.e]
        let p = Progresiones.pauta(e, semana: c.semana)
        if !(igual(c.actual["series"], p.series) && igual(c.actual["reps"], p.reps) && igual(c.actual["rir"], p.rir)) {
            fallas.append("pauta \(e.id) sem \(c.semana): esperado \(c.actual), swift \(p)")
        }
        let n = Progresiones.nota(e, semanaActual: c.semana)
        switch c.nota {
        case .null:
            if n != nil { fallas.append("nota \(e.id) sem \(c.semana): esperado null, swift \(String(describing: n))") }
        default:
            let ok = n?.texto == c.nota["texto"]?.comoTexto
                && n?.cambia == (c.nota["cambia"] == .bool(true))
                && n?.calibracion == (c.nota["calibracion"] == .bool(true))
            if !ok { fallas.append("nota \(e.id) sem \(c.semana): esperado \(c.nota), swift \(String(describing: n))") }
        }
    }
    return (v.casos.count, fallas)
}

@Suite("Progresión: misma salida que la web")
struct ProgresionVectoresTests {
    @Test func vectoresPublicos() throws {
        let r = try verificar(raizRepo.appendingPathComponent("apps/shared/vectores/progresion.json"))
        #expect(r.total > 500)
        #expect(r.fallas.isEmpty, "\(r.fallas.count) de \(r.total): \(r.fallas.prefix(5))")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: carpetaPrivada.appendingPathComponent("progresion.json").path)))
    func vectoresDeLosPlanesReales() throws {
        let r = try verificar(carpetaPrivada.appendingPathComponent("progresion.json"))
        #expect(r.total > 10_000)
        #expect(r.fallas.isEmpty, "\(r.fallas.count) de \(r.total): \(r.fallas.prefix(5))")
    }

    @Test func topeComoElUpperDeJS() {
        #expect(Progresiones.tope("8-10") == 10)
        #expect(Progresiones.tope("10 min") == 10)
        #expect(Progresiones.tope("0 (al fallo)") == 0)
        #expect(Progresiones.tope(nil) == nil)
        #expect(Progresiones.tope("AMRAP") == nil)
        #expect(Progresiones.tope("12/15/20") == 20)
    }
}
