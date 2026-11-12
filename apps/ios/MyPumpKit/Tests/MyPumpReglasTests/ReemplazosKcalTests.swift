import XCTest
@testable import MyPumpReglas

/// 2.3.1: reemplazos de comida sin subir kcal en silencio (vectores `apps/shared/vectores/reemplazos_kcal.json`,
/// iguales en la web y Android).
final class ReemplazosKcalTests: XCTestCase {
    private struct Item { let nombre: String; let kcal: Double?; let universal: Bool; let propio: Bool }

    private func vectores() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/reemplazos_kcal.json"))) as! [String: Any]
    }

    private func num(_ x: Any?) -> Double? { x is NSNull ? nil : (x as? NSNumber)?.doubleValue }

    func testTextos() throws {
        let t = try vectores()["textos"] as! [String: String]
        XCTAssertEqual(ReemplazosKcal.usarIgual, t["usarIgual"])
        XCTAssertEqual(ReemplazosKcal.elegirOtro, t["elegirOtro"])
        XCTAssertEqual(ReemplazosKcal.deshacer, t["deshacer"])
    }

    func testOrdenar() throws {
        for c in try vectores()["ordenar"] as! [[String: Any]] {
            let items = (c["subs"] as! [[String: Any]]).map {
                Item(nombre: $0["nombre"] as! String, kcal: num($0["kcal"]), universal: $0["universal"] as! Bool, propio: $0["propio"] as! Bool)
            }
            let o = ReemplazosKcal.ordenar(items, kcalOriginal: num(c["kcalOriginal"]), kcal: \.kcal, universal: \.universal, propio: \.propio)
            XCTAssertEqual(o.universales.map(\.nombre), c["universales"] as! [String], c["nombre"] as! String)
            XCTAssertEqual(o.resto.map(\.nombre), c["resto"] as! [String], c["nombre"] as! String)
        }
    }

    func testConfirmar() throws {
        for c in try vectores()["confirmar"] as! [[String: Any]] {
            let o = num(c["kcalOriginal"]), r = num(c["kcalReemplazo"])
            let k = "\(String(describing: o))→\(String(describing: r))"
            XCTAssertEqual(ReemplazosKcal.desvioPct(original: o, reemplazo: r), (c["desvioPct"] as? NSNumber)?.intValue, k)
            XCTAssertEqual(ReemplazosKcal.pideConfirmacion(original: o, reemplazo: r), c["pide"] as! Bool, k)
            XCTAssertEqual(ReemplazosKcal.suma(original: o, reemplazo: r), (c["suma"] as! NSNumber).intValue, k)
            if let t = c["texto"] as? String { XCTAssertEqual(ReemplazosKcal.textoConfirmacion(original: o, reemplazo: r), t, k) }
        }
    }

    func testRenglon() throws {
        for c in try vectores()["renglon"] as! [[String: Any]] {
            XCTAssertEqual(ReemplazosKcal.renglon(suma: num(c["suma"])!), c["texto"] as? String, "\(c["suma"]!)")
        }
    }
}
