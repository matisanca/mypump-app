import XCTest
@testable import MyPumpDatos

/// El borrador de Gimnasio de la 2.3.0 (sin `vistas`) se sigue leyendo en la 2.3.1, y las vistas se guardan.
final class BorradorGimnasioVistasTests: XCTestCase {
    func testUnBorradorViejoSinVistasSeLee() throws {
        let viejo = #"{"gimnasioId":"g1","noHay":["otros"],"nota":"","quitar":[],"respuestas":{"par_1":["a"]}}"#
        let b = try JSONDecoder().decode(BorradorGimnasio.self, from: Data(viejo.utf8))
        XCTAssertEqual(b.gimnasioId, "g1")
        XCTAssertNil(b.vistas)
        var n = b
        n.vistas = ["par_2"]
        let ida = try JSONDecoder().decode(BorradorGimnasio.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(ida.vistas, ["par_2"])
    }
}
