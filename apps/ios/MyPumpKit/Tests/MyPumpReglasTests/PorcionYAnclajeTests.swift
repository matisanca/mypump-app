import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

private struct ArchivoPorcion: Decodable {
    struct Caso: Decodable { let alimento: JSONValue; let porcion: String? }
    let casos: [Caso]
}

private struct ArchivoAnclaje: Decodable {
    struct Caso: Decodable {
        let dieta: Int
        let comidaId: String
        let optIdx: Int
        let foodIdx: Int
        let original: JSONValue
        let current: JSONValue
        let aplica: Bool
        let aplicaSinComida: Bool
    }
    let casos: [Caso]
}

private func fallasPorcion(_ url: URL) throws -> (Int, [String]) {
    let v = try JSONDecoder().decode(ArchivoPorcion.self, from: Data(contentsOf: url))
    var fallas: [String] = []
    for c in v.casos {
        let a = c.alimento
        // Number(food.qty) / Number(food.unitGrams) de JS sobre lo que vino en el JSON.
        let swift = PorcionCasera.referencia(nombre: AnclajeSwaps.textoJS(a["name"]) ?? "",
                                             qty: a["qty"].map { AnclajeSwaps.numero($0) ?? .nan } ?? .nan,
                                             unidad: a["unit"]?.comoTexto,
                                             gramosPorUnidad: a["unitGrams"].flatMap { AnclajeSwaps.numero($0) })
        if swift != c.porcion { fallas.append("\(a): web \(String(describing: c.porcion)), swift \(String(describing: swift))") }
    }
    return (v.casos.count, fallas)
}

private func alimento(_ v: JSONValue) throws -> Alimento {
    try JSONDecoder().decode(Alimento.self, from: JSONEncoder().encode(v))
}

private func fallasAnclaje(_ url: URL) throws -> (Int, [String]) {
    let v = try JSONDecoder().decode(ArchivoAnclaje.self, from: Data(contentsOf: url))
    // Los alimentos de esa posición en todos los tipos de día se reconstruyen de los mismos vectores, agrupando por
    // (dieta, comida, opción, índice): el generador evaluó cada caso contra su propia dieta.
    var porPosicion: [String: [Alimento]] = [:]
    for c in v.casos {
        let k = "\(c.dieta)|\(c.comidaId)|\(c.optIdx)|\(c.foodIdx)"
        let a = try alimento(c.original)
        if !(porPosicion[k] ?? []).contains(where: { AnclajeSwaps.huella($0) == AnclajeSwaps.huella(a) }) {
            porPosicion[k, default: []].append(a)
        }
    }
    var fallas: [String] = []
    for c in v.casos {
        let original = try alimento(c.original)
        let k = "\(c.dieta)|\(c.comidaId)|\(c.optIdx)|\(c.foodIdx)"
        let con = AnclajeSwaps.aplica(foodData: c.current, original: original, comidaId: c.comidaId) { porPosicion[k] ?? [] }
        let sin = AnclajeSwaps.aplica(foodData: c.current, original: original, comidaId: nil) { porPosicion[k] ?? [] }
        if con != c.aplica || sin != c.aplicaSinComida {
            fallas.append("\(original.nombre) \(c.current): web \(c.aplica)/\(c.aplicaSinComida), swift \(con)/\(sin)")
        }
    }
    return (v.casos.count, fallas)
}

@Suite("Porción casera y anclaje de swaps: mismo resultado que la web")
struct PorcionYAnclajeTests {
    @Test func porcionPublica() throws {
        let (n, fallas) = try fallasPorcion(raizRepo.appendingPathComponent("apps/shared/vectores/porcion_casera.json"))
        #expect(n > 1000)
        #expect(fallas.isEmpty, "\(fallas.count) de \(n): \(fallas.prefix(6))")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: carpetaPrivada.appendingPathComponent("porcion_casera.json").path)))
    func porcionDietasReales() throws {
        let (n, fallas) = try fallasPorcion(carpetaPrivada.appendingPathComponent("porcion_casera.json"))
        #expect(n > 100)
        #expect(fallas.isEmpty, "\(fallas.count) de \(n): \(fallas.prefix(6))")
    }

    @Test func anclajePublico() throws {
        let (n, fallas) = try fallasAnclaje(raizRepo.appendingPathComponent("apps/shared/vectores/anclaje_swaps.json"))
        #expect(n > 100)
        #expect(fallas.isEmpty, "\(fallas.count) de \(n): \(fallas.prefix(6))")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: carpetaPrivada.appendingPathComponent("anclaje_swaps.json").path)))
    func anclajeDietasReales() throws {
        let (n, fallas) = try fallasAnclaje(carpetaPrivada.appendingPathComponent("anclaje_swaps.json"))
        #expect(n > 1000)
        #expect(fallas.isEmpty, "\(fallas.count) de \(n): \(fallas.prefix(6))")
    }

    @Test func avenaDeEntrenoVistaEnDescanso() throws {
        let avena50 = Alimento(nombre: "Avena", qty: 50, unidad: "g")
        let avena80 = Alimento(nombre: "Avena", qty: 80, unidad: "g")
        let swap: JSONValue = .objeto(["name": .texto("Granola"), "_orig": .objeto(["name": .texto("Avena"), "qty": .numero(80), "unit": .texto("g")])])
        #expect(AnclajeSwaps.aplica(foodData: swap, original: avena50, comidaId: "desayuno") { [avena80, avena50] })
        #expect(!AnclajeSwaps.aplica(foodData: swap, original: avena50, comidaId: nil) { [avena80, avena50] })
        // Mati publicó 60 → 80 sin que quede ningún 60: el swap ya no vale.
        #expect(!AnclajeSwaps.aplica(foodData: swap, original: avena50, comidaId: "desayuno") { [avena50] })
    }
}
