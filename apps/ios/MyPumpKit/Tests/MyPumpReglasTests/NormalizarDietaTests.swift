import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

private struct Archivo: Decodable {
    struct Caso: Decodable { let entrada: JSONValue; let salida: JSONValue }
    let casos: [Caso]
}

private func resumen(_ r: NormalizarDieta.Resultado) -> JSONValue {
    let e = r.estructura
    func plan(_ m: Macros?, _ comidas: [Comida]) -> JSONValue {
        let macros: JSONValue = m.map { m in .lista([m.kcal, m.prot, m.carb, m.fat].map { $0.map(JSONValue.numero) ?? .null }) } ?? .null
        return .objeto(["macros": macros, "comidas": .lista(comidas.map { c in
            .objeto(["id": c.id.isEmpty ? .null : .texto(c.id), "opciones": .lista(c.opciones.map { o in
                .objeto(["nombre": o.nombre.map(JSONValue.texto) ?? .null, "alimentos": .lista(o.alimentos.map { .texto($0.nombre) })])
            })])
        })])
    }
    let planes = e.tiposDia.isEmpty ? [plan(e.macrosTarget, e.comidas)] : e.tiposDia.map { plan($0.macrosTarget, $0.comidas) }
    return .objeto(["usable": .bool(r.usable), "problemas": .lista(r.problemas.map(JSONValue.texto)), "planes": .lista(planes)])
}

private func fallas(_ url: URL) throws -> (Int, [String]) {
    let a = try JSONDecoder().decode(Archivo.self, from: Data(contentsOf: url))
    var fallas: [String] = []
    for (i, c) in a.casos.enumerated() {
        let e = try JSONDecoder().decode(EstructuraDieta.self, from: JSONEncoder().encode(c.entrada))
        let mio = resumen(NormalizarDieta.normalizar(e))
        if mio != c.salida { fallas.append("caso \(i): \(mio) ≠ \(c.salida)") }
    }
    return (a.casos.count, fallas)
}

@Suite("normalizarDieta: las mismas comidas, opciones y objetivo que la web")
struct NormalizarDietaTests {
    let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../shared/vectores")
    static let privado = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/nativa-evidencia/privado/vectores/normalizar_dieta.json")

    @Test func vectoresPublicos() throws {
        let (n, f) = try fallas(raiz.appendingPathComponent("normalizar_dieta.json"))
        #expect(n >= 11)
        #expect(f.isEmpty, "\(f.prefix(3))")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: privado.path)))
    func dietasReales() throws {
        let (n, f) = try fallas(Self.privado)
        #expect(n >= 90)
        #expect(f.isEmpty, "\(f.count) de \(n): \(f.prefix(2))")
    }
}
