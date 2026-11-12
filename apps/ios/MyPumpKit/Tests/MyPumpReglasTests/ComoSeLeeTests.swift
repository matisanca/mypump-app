import XCTest
@testable import MyPumpReglas

/// «¿Cómo se lee?» con los mismos textos que Android y la web (`apps/shared/vectores/como_se_lee.json`).
final class ComoSeLeeTests: XCTestCase {
    func testTextosIgualesALosVectores() throws {
        let v = try JSONSerialization.jsonObject(with: Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/como_se_lee.json"))) as! [String: Any]
        XCTAssertEqual(ComoSeLee.boton, v["boton"] as? String)
        XCTAssertEqual(ComoSeLee.titulo, v["titulo"] as? String)
        XCTAssertEqual(ComoSeLee.pasos, v["pasos"] as? [String])
        XCTAssertEqual(ComoSeLee.verVideo, v["verVideo"] as? String)
        XCTAssertEqual(ComoSeLee.cerrar, v["cerrar"] as? String)
        XCTAssertEqual(ComoSeLee.video, v["video"] as? String)
        for p in ComoSeLee.pasos { XCTAssertFalse(p.localizedCaseInsensitiveContains("RIR")); XCTAssertFalse(p.contains("entrenador")) }
    }

    func testVideoSoloHttps() {
        XCTAssertNil(ComoSeLee.urlVideo(nil))
        XCTAssertNil(ComoSeLee.urlVideo("http://x.com/v"))
        XCTAssertNil(ComoSeLee.urlVideo("javascript:alert(1)"))
        XCTAssertNil(ComoSeLee.urlVideo("https://x.com/v\"onload=\"x"))
        XCTAssertEqual(ComoSeLee.urlVideo(" https://x.com/v ")?.absoluteString, "https://x.com/v")
    }
}
