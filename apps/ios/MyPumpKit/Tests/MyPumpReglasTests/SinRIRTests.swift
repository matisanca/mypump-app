import XCTest
@testable import MyPumpReglas

/// REGLA DURA: RIR no aparece nunca en una pantalla del alumno. Los 25 textos reales (sin nombres) de
/// `apps/shared/vectores/sin_rir.json`, iguales en la web y en Android, y la excepción de la reserva clínica de Mati.
final class SinRIRTests: XCTestCase {
    private var vectores: [String: Any] {
        get throws {
            let url = raizRepo.appendingPathComponent("apps/shared/vectores/sin_rir.json")
            return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        }
    }

    func testLos25TextosRealesQuedanSinRIR() throws {
        let v = try vectores
        let prohibido = try NSRegularExpression(pattern: v["prohibido"] as! String, options: .caseInsensitive)
        let reales = v["reales"] as! [[String: String]]
        XCTAssertEqual(reales.count, 25)
        for c in reales + (v["otros"] as! [[String: String]]) {
            let sale = TextoAlumno.sinRIR(c["entra"]!)
            XCTAssertEqual(sale, c["sale"]!, c["entra"]!)
            XCTAssertNil(prohibido.firstMatch(in: sale, range: NSRange(sale.startIndex..., in: sale)), sale)
        }
        for t in v["sinCambio"] as! [String] { XCTAssertEqual(TextoAlumno.sinRIR(t), t) }
    }

    func testReservaClinicaDejaLaNotaEntera() throws {
        let r = try vectores["reserva"] as! [String: Any]
        func texto(_ x: Any) -> String? { x is NSNull ? nil : (x as? String) ?? (x as? NSNumber).map { "\($0)" } }
        for x in r["conReserva"] as! [Any] { XCTAssertTrue(TextoAlumno.conReserva(texto(x)), "\(x)") }
        for x in r["sinReserva"] as! [Any] { XCTAssertFalse(TextoAlumno.conReserva(texto(x)), "\(x)") }
        for c in r["casos"] as! [[String: Any]] {
            XCTAssertEqual(TextoAlumno.notaParaAlumno(c["entra"] as? String, rir: texto(c["rir"]!)), c["sale"] as? String)
        }
        XCTAssertNil(TextoAlumno.notaParaAlumno("Quedate con 2 repeticiones en reserva.", rir: "0"), "vacía: no se dibuja")
        XCTAssertNil(TextoAlumno.notaParaAlumno(nil, rir: nil))
    }
}
