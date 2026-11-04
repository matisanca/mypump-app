import XCTest

/// La pestaña Suplementación (2.1.0) con la demo («Ver demo», lo que ve la revisión de Apple): sin cuenta ni red. La
/// muestra ficticia es `apps/shared/demo/suplementacion.json`.
@MainActor
final class SuplementacionUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno"]
        app.launch()
    }

    func testDemoMuestraLaPestanaYSaludPasaAMas() throws {
        let pestana = app.pestana("Suplementación")
        XCTAssertTrue(pestana.waitForExistence(timeout: 15), "La demo no muestra la pestaña Suplementación")
        XCTAssertFalse(app.tabBars.buttons["Salud"].exists, "Con suplementación, Salud no va en la barra")
        XCTAssertTrue(app.pestana("Revisión").exists && app.pestana("Chat").exists && app.pestana("Dieta").exists)

        // Tu día: los momentos de la muestra, en el orden de dia[].
        pestana.tap()
        let desayuno = app.descendants(matching: .any)["supl-momento-desayuno"]
        XCTAssertTrue(desayuno.waitForExistence(timeout: 5), "No se ve «Tu día»")
        XCTAssertTrue(app.staticTexts["Con el desayuno"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["supl-momento-pre"].exists)
        captura("suplementacion-dia")

        // El detalle de la creatina: lo que dice cómo tomarla, por qué y qué comprar.
        let creatina = app.buttons["supl-fila-desayuno-0-0"]
        XCTAssertTrue(creatina.exists)
        XCTAssertTrue(creatina.label.hasPrefix("Creatina monohidrato, 5 g, Nuevo"), "La fila dice otra cosa: \(creatina.label)")
        creatina.tap()
        let nombre = app.staticTexts["supl-detalle-nombre"]
        XCTAssertTrue(nombre.waitForExistence(timeout: 5), "No abrió el detalle")
        XCTAssertEqual(nombre.label, "Creatina monohidrato")
        XCTAssertTrue(app.staticTexts["Te ayuda a rendir más en las series pesadas"].exists)
        captura("suplementacion-detalle")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // «Dejás de tomar», aparte y con su porqué.
        let sale = app.buttons["supl-sale-4"]
        for _ in 0..<6 where !sale.isHittable { app.swipeUp() }
        XCTAssertTrue(sale.isHittable, "No se ve «Dejás de tomar»")
        XCTAssertTrue(sale.label.contains("Multivitamínico"))

        // Salud, desde arriba de Revisión, al lado de Mis datos.
        app.pestana("Revisión").tap()
        let abrirSalud = app.buttons["abrir-salud"]
        XCTAssertTrue(abrirSalud.waitForExistence(timeout: 5), "Falta el acceso a Salud en Revisión")
        abrirSalud.tap()
        XCTAssertTrue(app.descendants(matching: .any)["segmento-salud"].waitForExistence(timeout: 5), "No abrió Salud")
        captura("suplementacion-salud-en-mas")
        app.buttons["salud-cerrar"].tap()
        XCTAssertTrue(abrirSalud.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["segmento-salud"].exists, "«Listo» no cerró Salud")
    }

    private func captura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
