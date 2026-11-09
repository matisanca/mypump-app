import XCTest

/// «Lo que más te importa» con la guía de muestra (sin token ni red): con `dolor` arriba de todo y sin `dolor` como siempre.
@MainActor
final class GuiaDolorUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws { continueAfterFailure = false }

    private func abrir(_ extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-bocetos", "YES", "-guiaMuestra", "YES", "-sinOnboarding", "YES", "-pestana", "entreno",
                               "-abrir", "guia", "-audioSinServidor", "YES", "-guiaBienvenida", "no"] + extra
        app.launch()
        XCTAssertTrue(elemento("guia-avance").waitForExistence(timeout: 20), "No abrió la guía")
    }

    private func elemento(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func conDolor(_ extra: [String] = []) { abrir(["-guiaDolor", "YES"] + extra) }

    private func textosVisibles() -> [String] { app.staticTexts.allElementsBoundByIndex.map(\.label) }

    func testSinDolorEsLaGuiaDeSiempre() {
        abrir()
        XCTAssertFalse(elemento("guia-dolor").exists)
        XCTAssertFalse(elemento("guia-intro").exists)
        XCTAssertFalse(app.buttons["guia-paso-videos"].exists)
        XCTAssertTrue(app.staticTexts["Mati"].exists)
        XCTAssertFalse(app.staticTexts["Lo que más te importa"].exists)
    }

    func testConDolorVaArribaConSusPartes() {
        conDolor()
        let d = elemento("guia-dolor")
        XCTAssertTrue(d.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Lo que más te importa"].exists)
        XCTAssertTrue(app.staticTexts["Bajar la panza sin perder fuerza"].exists)
        let p = app.staticTexts["guia-dolor-parrafo-0"]
        XCTAssertTrue(p.label.contains("la panza y que"), p.label)
        for t in textosVisibles() { XCTAssertFalse(t.contains("**") || t.contains("##"), t) }
        // Arriba del reproductor, como en el celular en la web.
        XCTAssertTrue(app.buttons["guia-bloque-Lo que más te importa"].exists, "Faltan «Tus videos sobre esto»")
        XCTAssertEqual(app.buttons["guia-bloque-Lo que más te importa"].label.hasPrefix("Tus videos sobre esto"), true)
        XCTAssertLessThan(d.frame.minY, elemento("guia-titulo-actual").frame.minY)
        XCTAssertTrue(elemento("guia-parte-0").exists)
        XCTAssertTrue(app.staticTexts["Tu plan para estas semanas"].exists)
    }

    func testIntroSinFechaNoInventaNinguna() {
        conDolor()
        XCTAssertEqual(app.staticTexts["guia-intro"].label, "Antes de nuestra videollamada, hacé estos dos pasos.")
        XCTAssertEqual(app.buttons["guia-paso-videos"].label, "Paso 1 de 2, Mirá tus videos, es el que sigue")
        XCTAssertEqual(app.buttons["guia-paso-dudas"].label, "Paso 2 de 2, Dejá tus dudas, hecho")
        XCTAssertFalse(app.staticTexts["Mati"].exists)
    }

    func testIntroConFecha() {
        conDolor(["-guiaDolorFecha", "2035-03-07T14:00:00-03:00"])
        XCTAssertEqual(app.staticTexts["guia-intro"].label, "Antes de nuestra videollamada del miércoles 7/3, hacé estos dos pasos.")
    }

    func testDespuesDeLaLlamadaSinIntro() {
        conDolor(["-guiaDolorFecha", "2020-03-07T14:00:00-03:00"])
        XCTAssertFalse(elemento("guia-intro").exists)
        XCTAssertFalse(app.buttons["guia-paso-videos"].exists)
        XCTAssertTrue(elemento("guia-dolor").exists)
    }

    func testPasoDudasLlevaALasDudas() {
        conDolor()
        app.buttons["guia-paso-dudas"].tap()
        let dudas = elemento("guia-dudas-llamada").firstMatch
        XCTAssertTrue(dudas.waitForExistence(timeout: 5))
        let bajo = NSPredicate { _, _ in dudas.frame.minY > 0 && dudas.frame.minY < self.app.frame.maxY * 0.7 }
        wait(for: [XCTNSPredicateExpectation(predicate: bajo, object: nil)], timeout: 5)
    }

    func testLetraGrandeNoCorta() {
        conDolor(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let p = app.buttons["guia-paso-videos"]
        XCTAssertTrue(p.exists)
        XCTAssertLessThanOrEqual(p.frame.width, app.frame.width)
        XCTAssertGreaterThanOrEqual(p.frame.height, 44)
    }
}
