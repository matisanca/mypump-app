import XCTest
@testable import MyPumpModelos
@testable import MyPumpReglas

/// Los protectores van aparte de «Tu día» (vectores `apps/shared/vectores/protectores.json`, iguales en la web y Android).
final class ProtectoresTests: XCTestCase {
    private func vectores() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/protectores.json"))) as! [String: Any]
    }

    private func vista(_ s: Any) throws -> VistaSuplementacion {
        let data = try JSONSerialization.data(withJSONObject: s)
        return try XCTUnwrap(VistaSuplementacion(try JSONDecoder().decode(SuplementacionGuia.self, from: data)))
    }

    private func momentos(_ v: VistaSuplementacion) -> [[String: AnyHashable]] {
        v.momentos.map { ["id": $0.id, "nombres": $0.filas.map(\.nombre)] }
    }

    private func esperados(_ x: Any?) -> [[String: AnyHashable]] {
        (x as! [[String: Any]]).map { ["id": $0["id"] as! String, "nombres": $0["nombres"] as! [String]] }
    }

    func testLosProtectoresVanAparte() throws {
        let v = try vectores()
        let vs = try vista(v["suplementacion"]!)
        XCTAssertEqual(VistaSuplementacion.tituloProtectores, v["titulo"] as? String)
        XCTAssertEqual(momentos(vs), esperados(v["momentos"]))
        let esp = (v["protectores"] as! [[String: Any]]).map { p in
            [p["nombre"] as? String, p["cantidad"] as? String, p["momento"] as? String, p["nota"] as? String, "\(p["item"]!)"]
        }
        XCTAssertEqual(vs.protectores.map { [$0.nombre, $0.cantidad, $0.momento, $0.nota, "\($0.item)"] }, esp)
        XCTAssertEqual(vs.sale.map(\.nombre), v["sale"] as? [String])
    }

    func testSinElCampoLaVistaQuedaComoAntes() throws {
        let v = try vectores()
        var s = v["suplementacion"] as! [String: Any]
        s["items"] = (s["items"] as! [[String: Any]]).map { var i = $0; i["protector"] = nil; i["tipo"] = nil; return i }
        let vs = try vista(s)
        XCTAssertTrue(vs.protectores.isEmpty)
        XCTAssertEqual(momentos(vs), esperados((v["sinCampo"] as! [String: Any])["momentos"]))
    }
}
