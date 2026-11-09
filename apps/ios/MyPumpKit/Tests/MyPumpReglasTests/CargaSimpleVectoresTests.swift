import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

private struct V: Decodable {
    struct Prog: Decodable { let semana: Int; let series: Int; let reps: String; let titulo: String? }
    struct Corr: Decodable { let caso: String; let progresion: [Prog]; let semana: Int; let mensaje: String?; let tipo: String?; let espera: Bool }
    struct H: Decodable { let desde: Double; let equipo: String; let espera: Double? }
    struct M: Decodable { let desde: Double; let pasos: Int; let equipo: String; let espera: Double }
    struct Mo: Decodable { let kilos: [Double]; let espera: Double? }
    struct Gu: Decodable { struct E: Decodable { let doble: Bool; let segundo: Bool }; let caso: String; let desde: Double?; let serie: Int; let ahora: Double; let espera: E }
    struct Ref: Decodable { let reps: Int; let kg: Double? }
    struct Espera: Decodable { let res: String?; let reps: Int?; let kg: Double?; let aumento: String?; let carga: Double? }
    struct Paso: Decodable { let accion: String; let i: Int?; let valor: JV?; let ahora: Double?; let espera: Espera? }
    struct Final: Decodable { let carga: Double?; let aumento: String?; let reps: [Int]?; let kg: [Double]?; let confirmadas: Int?; let hechasConOtraCarga: Int? }
    struct Esc: Decodable { let caso: String; let progresion: [Prog]; let semana: Int; let equipo: String; let nombre: String?; let ultimaVez: [Ref]; let pasos: [Paso]; let final: Final? }
    struct JV: Decodable {
        let n: Double?; let b: Bool?
        init(from d: Decoder) throws { let c = try d.singleValueContainer(); n = try? c.decode(Double.self); b = try? c.decode(Bool.self) }
    }
    let corresponde: [Corr]; let hasta: [H]; let mover: [M]; let moda: [Mo]; let guardia: [Gu]; let escenarios: [Esc]
}

/// Los vectores que comparte con Android (`apps/shared/vectores/carga_simple.json`): las mismas respuestas en las dos apps.
final class CargaSimpleVectoresTests: XCTestCase {
    private func cargar() throws -> V {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("shared/vectores/carga_simple.json")
        return try JSONDecoder().decode(V.self, from: Data(contentsOf: url))
    }
    private func equipo(_ s: String) -> Preparacion.Equipo { Preparacion.Equipo(rawValue: s)! }
    private func ejercicio(_ p: [V.Prog], nombre: String = "Press banca con barra", tipo: String = "compuesto") -> Ejercicio {
        Ejercicio(id: "x", nombre: nombre, tipo: tipo, progresion: p.map { Progresion(semana: $0.semana, series: $0.series, reps: $0.reps, titulo: $0.titulo) })
    }
    private func texto(_ a: CargaSimple.Aumento) -> String {
        switch a {
        case .noCorresponde: "noCorresponde"
        case .descartado: "descartado"
        case let .sugerido(d, h): "sugerido:\(JS.texto(d)):\(JS.texto(h))"
        case let .aceptado(d, h): "aceptado:\(JS.texto(d)):\(JS.texto(h))"
        }
    }

    func testCorresponde() throws {
        for c in try cargar().corresponde {
            XCTAssertEqual(AumentoCarga.corresponde(ejercicio(c.progresion, tipo: c.tipo ?? "compuesto"), semana: c.semana, mensajeSemana: c.mensaje), c.espera, c.caso)
        }
    }

    func testHastaMoverModaGuardia() throws {
        let v = try cargar()
        for h in v.hasta { XCTAssertEqual(AumentoCarga.hasta(desde: h.desde, equipo: equipo(h.equipo)), h.espera, "\(h.desde) \(h.equipo)") }
        for m in v.mover { XCTAssertEqual(AumentoCarga.mover(m.desde, pasos: m.pasos, equipo: equipo(m.equipo)), m.espera, "\(m.desde) \(m.pasos)") }
        for m in v.moda { XCTAssertEqual(AumentoCarga.moda(m.kilos), m.espera) }
        for g in v.guardia {
            var s = GuardiaOK()
            if let d = g.desde { s.levantar(serie: 1, ahora: d) }
            XCTAssertEqual(s.esDobleToque(serie: g.serie, ahora: g.ahora), g.espera.doble, g.caso)
            XCTAssertEqual(s.esSegundoToque(serie: g.serie, ahora: g.ahora), g.espera.segundo, g.caso)
        }
    }

    func testEscenarios() throws {
        for e in try cargar().escenarios {
            var s = CargaSimple(ejercicio: ejercicio(e.progresion, nombre: e.nombre ?? "Press banca con barra"), semana: e.semana,
                                ultimaVez: e.ultimaVez.map { .init(reps: $0.reps, kg: $0.kg) }, equipo: equipo(e.equipo))
            for p in e.pasos {
                switch p.accion {
                case "moverCarga": s.moverCarga(Int(p.valor!.n!))
                case "fijarCarga": s.fijarCarga(p.valor!.n)
                case "aceptar": s.aceptarAumento()
                case "descartar": s.descartarAumento()
                case "ajustarReps": s.ajustarReps(p.i!, Int(p.valor!.n!))
                case "mismoPeso": s.usarMismoPeso(p.valor!.b!)
                case "mirar":
                    if let a = p.espera?.aumento { XCTAssertEqual(texto(s.aumento), a, e.caso) }
                    if let c = p.espera?.carga { XCTAssertEqual(s.carga, c, e.caso) }
                case "ok", "okInsistir":
                    let r = s.evaluarOK(p.i!, ahora: p.ahora!, insistio: p.accion == "okInsistir")
                    switch (r, p.espera?.res) {
                    case (.faltanDatos, "faltanDatos"), (.guardia, "guardia"): break
                    case let (.lista(reps, kg), "lista"):
                        XCTAssertEqual(reps, p.espera?.reps, e.caso)
                        XCTAssertEqual(kg, p.espera?.kg, e.caso)
                        s.series[p.i!].reps = reps
                        s.series[p.i!].kg = kg
                        s.series[p.i!].confirmada = true
                        s.anotarOK(ahora: p.ahora!)
                    default: XCTFail("\(e.caso): \(r) ≠ \(p.espera?.res ?? "")")
                    }
                default: XCTFail(p.accion)
                }
            }
            guard let f = e.final else { continue }
            if let c = f.carga { XCTAssertEqual(s.carga, c, e.caso) }
            if let a = f.aumento { XCTAssertEqual(texto(s.aumento), a, e.caso) }
            if let r = f.reps { XCTAssertEqual(s.series.indices.map { s.reps($0) }, r, e.caso) }
            if let k = f.kg { XCTAssertEqual(s.series.map(\.kg), k, e.caso) }
            if let c = f.confirmadas { XCTAssertEqual(s.confirmadas, c, e.caso) }
            if let h = f.hechasConOtraCarga { XCTAssertEqual(s.hechasConOtraCarga, h, e.caso) }
        }
    }
}
