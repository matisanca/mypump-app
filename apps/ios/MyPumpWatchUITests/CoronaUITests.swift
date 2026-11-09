import XCTest

/// La corona del Apple Watch después del descanso. Para el simulador (`MyPumpWatchUITests` contra la demo, sin iPhone ni
/// cuenta): la rotación simulada es el único modo de probar el foco de verdad, un test del kit no lo ve.
final class CoronaUITests: XCTestCase {
    private func valor(_ app: XCUIApplication, _ campo: String) -> String {
        let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(campo):")).firstMatch
        return b.exists ? b.label : "(no está)"
    }

    private func abrir() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-pantalla", "ejercicio"]
        app.launch()
        XCTAssertTrue(app.buttons["Confirmar serie"].waitForExistence(timeout: 15))
        sleep(2)
        return app
    }

    private func girar() {
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.5)
        sleep(2)
    }

    private func saltarDescanso(_ app: XCUIApplication) {
        let saltar = app.buttons["Saltar"].firstMatch
        XCTAssertTrue(saltar.waitForExistence(timeout: 5))
        saltar.tap()
        sleep(2)
    }

    func testLaCoronaCambiaRepsYKg() {
        let app = abrir()
        let reps = valor(app, "Reps"), kg = valor(app, "Kg")
        girar()
        XCTAssertNotEqual(valor(app, "Reps"), reps, "la corona no cambió las reps")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kg:'")).firstMatch.tap()
        sleep(1)
        girar()
        XCTAssertNotEqual(valor(app, "Kg"), kg, "la corona no cambió los kg")
    }

    /// El descanso se abre a pantalla completa y se llevaba el foco: desde la segunda serie la corona no hacía nada.
    func testLaCoronaSigueAndandoDespuesDelDescanso() {
        let app = abrir()
        app.buttons["Confirmar serie"].firstMatch.tap()
        saltarDescanso(app)
        let reps = valor(app, "Reps")
        girar()
        XCTAssertNotEqual(valor(app, "Reps"), reps, "tras el descanso la corona no cambia las reps")
        // Y otra vuelta: la segunda serie confirmada, y el campo Kg.
        app.buttons["Confirmar serie"].firstMatch.tap()
        saltarDescanso(app)
        let kg = valor(app, "Kg")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kg:'")).firstMatch.tap()
        sleep(1)
        girar()
        XCTAssertNotEqual(valor(app, "Kg"), kg, "tras el segundo descanso la corona no cambia los kg")
    }
}
