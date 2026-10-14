import XCTest

/// Entreno en la demo (sin cuenta ni token): lo que se toca en la tabla de series.
@MainActor
final class EntrenoUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno", "-abrir", "ejercicio"]
        app.launch()
    }

    /// SER-04: al tocar un campo se selecciona todo y lo que se escribe reemplaza lo anterior (como `select()` en la
    /// web). Sin eso, 80 kg corregido a 7 quedaba "807" (revisión del 14-oct, hallazgo 2).
    func testTocarUnCampoLoSeleccionaEntero() throws {
        let campos = app.textFields
        XCTAssertTrue(campos.firstMatch.waitForExistence(timeout: 15), "No abrió el ejercicio")
        XCTAssertGreaterThanOrEqual(campos.count, 2, "El ejercicio no tiene columna de kg")
        let reps = campos.element(boundBy: 0), kg = campos.element(boundBy: 1)
        kg.tap()
        kg.typeText("80")
        reps.tap()   // el foco se va
        kg.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))   // la selección llega 0,08 s después del foco
        kg.typeText("7")
        XCTAssertEqual(kg.value as? String, "7", "lo nuevo no reemplazó a lo anterior")
    }
}
