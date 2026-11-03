import XCTest

/// La recuperación con `confianza` y `motivo_falta` (nativa_007, R1 de la 2.0.3). La serie es inventada
/// (`-recuperacionDePrueba`, solo Debug); lo demás va a la cuenta de prueba, cuyo token llega por `TEST_RUNNER_MYPUMP_TOKEN`.
/// Gemelo de `RecuperacionConfianzaUiTest.kt`.
@MainActor
final class RecuperacionConfianzaUITests: XCTestCase {
    private var app = XCUIApplication()
    private var token = ""

    override func setUp() async throws {
        continueAfterFailure = false
        guard let t = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !t.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan una cuenta de prueba, nunca un cliente.")
        }
        token = t
    }

    private func abrir(_ caso: String, oscuro: Bool = false) {
        app.launchArguments = ["-token", token, "-pestana", "revision", "-sinOnboarding", "YES", "-recuperacionDePrueba", caso]
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        app.launch()
    }

    /// Baja la lista hasta que [e] quede tocable y lejos del borde de abajo (la barra de pestañas).
    private func hasta(_ e: XCUIElement) {
        XCTAssertTrue(app.otherElements["card-recuperacion"].firstMatch.waitForExistence(timeout: 20) || e.waitForExistence(timeout: 1),
                      "No apareció la card de recuperación")
        let alto = app.windows.firstMatch.frame.maxY
        for _ in 0..<12 where !(e.exists && e.isHittable && e.frame.maxY < alto - 140) { app.swipeUp() }
        XCTAssertTrue(e.isHittable, "No se llegó a \(e)")
    }

    func testConfianzaBajaEnClaro() throws { try confianzaBaja(oscuro: false) }

    func testConfianzaBajaEnOscuro() throws { try confianzaBaja(oscuro: true) }

    private func confianzaBaja(oscuro: Bool) throws {
        let tema = oscuro ? "oscuro" : "claro"
        abrir("baja", oscuro: oscuro)
        let pastilla = app.buttons["confianza-recuperacion"].firstMatch
        hasta(app.buttons["ver-todos-mis-datos"].firstMatch)
        XCTAssertTrue(pastilla.waitForExistence(timeout: 5), "Falta la pastilla de confianza")
        XCTAssertEqual(pastilla.label, "Confianza baja")
        XCTAssertTrue(app.staticTexts["41"].exists, "Falta el score")
        let explicacion = app.staticTexts["Para mejorarla, usá el reloj para dormir."]
        XCTAssertFalse(explicacion.exists, "La explicación tiene que esperar al toque")
        adjuntarCaptura("r203-recuperacion-confianza-baja-\(tema)")
        pastilla.tap()
        XCTAssertTrue(explicacion.waitForExistence(timeout: 3), "Tocar la pastilla no mostró cómo mejorarla")
        adjuntarCaptura("r203-recuperacion-confianza-abierta-\(tema)")
        pastilla.tap()
        XCTAssertTrue(explicacion.waitForNonExistence(timeout: 3), "La pastilla no la volvió a cerrar")
        // En el detalle, a la vista.
        app.buttons["ver-todos-mis-datos"].firstMatch.tap()
        let detalle = app.descendants(matching: .any)["detalle-confianza"].firstMatch
        XCTAssertTrue(detalle.waitForExistence(timeout: 10), "El detalle no muestra la confianza")
        adjuntarCaptura("r203-recuperacion-detalle-\(tema)")
    }

    func testCalibrandoMuestraElMotivo() throws {
        abrir("calibrando")
        let falta = app.staticTexts["Calibrando, hay 5 de 14 días con datos del reloj. Faltan 9 días."]
        hasta(falta)
        adjuntarCaptura("r203-recuperacion-calibrando-claro")
    }

    func testConfianzaAltaQuedaComoSiempre() throws {
        abrir("alta")
        hasta(app.buttons["ver-todos-mis-datos"].firstMatch)
        XCTAssertTrue(app.staticTexts["74"].exists, "Falta el score")
        XCTAssertFalse(app.buttons["confianza-recuperacion"].exists, "Con confianza alta no va la pastilla")
    }

    private func adjuntarCaptura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
