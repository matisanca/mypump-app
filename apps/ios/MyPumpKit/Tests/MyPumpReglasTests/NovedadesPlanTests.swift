import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// «Novedades de tu plan»: los mismos casos que Android y la web (`apps/shared/fixtures/novedades/casos.json`).
@Suite("Novedades de tu plan")
struct NovedadesPlanTests {
    private static let archivo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../../shared/fixtures/novedades/casos.json").standardized

    struct Caso: Decodable {
        let nombre: String
        let antes: [String: JSONValue]
        let despues: [String: JSONValue]
        let esperado: ResumenNovedad?
    }

    static func area<T: Decodable>(_ o: [String: JSONValue], _ k: String, _ t: T.Type) -> AreaPlan<T> {
        guard let v = o[k] else { return .desconocida }
        if v == .null { return .ninguna }
        guard let d = try? JSONEncoder().encode(v), let x = try? JSONDecoder().decode(T.self, from: d) else { return .desconocida }
        return .hay(x)
    }

    static func foto(_ o: [String: JSONValue]) -> FotoPlan {
        let s = area(o, "suplementacion", RespuestaSuplementacion.self)
        let supl: AreaPlan<SuplementacionGuia> = switch s {
        case .desconocida: .desconocida
        case .ninguna: .ninguna
        case .hay(let r): r.suplementacion.map { .hay($0) } ?? .ninguna
        }
        return FotoPlan(rutina: area(o, "rutina", RutinaActiva.self), dieta: area(o, "dieta", DietaActiva.self), suplementacion: supl)
    }

    static func casos() throws -> [Caso] {
        try JSONDecoder().decode([Caso].self, from: Data(contentsOf: archivo))
    }

    /// «Sin dosis»: la misma tabla que Android y la web (`apps/shared/fixtures/novedades/sin_dosis.json`).
    @Test func sinDosisDaLoMismoQueLaReferencia() throws {
        struct Par: Decodable { let entrada: String; let salida: String }
        let u = Self.archivo.deletingLastPathComponent().appendingPathComponent("sin_dosis.json")
        let pares = try JSONDecoder().decode([Par].self, from: Data(contentsOf: u))
        #expect(pares.count >= 40)
        for p in pares { #expect(NovedadesPlan.sinDosis(p.entrada) == p.salida, "«\(p.entrada)»") }
    }

    @Test func losCasosCompartidos() throws {
        let cs = try Self.casos()
        #expect(cs.count >= 30)
        for c in cs {
            let r = NovedadesPlan.calcular(antes: Self.foto(c.antes), despues: Self.foto(c.despues))
            #expect(r == c.esperado, "\(c.nombre): \(String(describing: r))")
        }
    }

    /// Ningún texto con dos puntos, guiones, RIR, «fallo», «coach» o «entrenador», ni una dosis de la suplementación.
    @Test func losTextosCumplenLasReglas() throws {
        for c in try Self.casos() {
            guard let r = NovedadesPlan.calcular(antes: Self.foto(c.antes), despues: Self.foto(c.despues)) else { continue }
            let textos = [r.titular, r.resumen] + r.partes.flatMap { [$0.titular] + $0.lineas }
            for t in textos {
                let b = t.lowercased()
                #expect(!t.contains(":") && !t.contains(" - ") && !t.contains("—") && !t.contains("–"), "\(c.nombre): \(t)")
                #expect(!b.contains("rir") && !b.contains("fallo") && !b.contains("coach") && !b.contains("entrenador"), "\(c.nombre): \(t)")
            }
            // Ninguna cantidad de la suplementación (de antes o de ahora) aparece en el texto.
            let dosis = [c.antes, c.despues].compactMap { o -> SuplementacionGuia? in
                if case .hay(let s) = Self.foto(o).suplementacion { return s }; return nil
            }.flatMap { $0.items.flatMap { [$0.cantidad, $0.antes] + $0.tomas.map(\.cantidad) } }.compactMap { $0 }
            for p in r.partes { for l in p.lineas { for d in dosis { #expect(!l.contains(d), "dosis en \(l)") } } }
            for p in r.partes { #expect(p.lineas.count <= NovedadesPlan.maxLineas) }
        }
    }

    @Test func formatos() {
        #expect(NovedadesPlan.formatoKcal(980) == "980")
        #expect(NovedadesPlan.formatoKcal(12345.6) == "12.346")
        #expect(NovedadesPlan.formatoCantidad(1, "u") == "1 unidad")
        #expect(NovedadesPlan.formatoCantidad(1.25, "g") == "1,3 g")
        #expect(NovedadesPlan.formatoCantidad(1.04, "u") == "1 unidad")
        #expect(NovedadesPlan.formatoPauta(3, "10-12 al fallo") == "3 series")
        #expect(NovedadesPlan.formatoPauta(3, "AMRAP") == "3 series, AMRAP")
        #expect(NovedadesPlan.formatoKcal(1e20) == "100000000000000000000")
        #expect(NovedadesPlan.formatoCantidad(250, "ml") == "250 ml")
        #expect(NovedadesPlan.formatoCantidad(30, nil) == "30 g")
        #expect(NovedadesPlan.repsNormal(" 8–10 ") == "8 a 10")
        #expect(NovedadesPlan.lista(["a"]) == "a")
        #expect(NovedadesPlan.lista(["a", "b", "c"]) == "a, b y c")
    }
}
