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

    /// El NavigationLink al detalle (con `.buttonStyle(.plain)` no siempre queda como botón en el árbol de accesibilidad).
    private var verTodo: XCUIElement { app.descendants(matching: .any)["ver-todos-mis-datos"].firstMatch }

    private func abrir(_ caso: String, oscuro: Bool = false) {
        app.launchArguments = ["-token", token, "-pestana", "revision", "-sinOnboarding", "YES", "-recuperacionDePrueba", caso]
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        app.launch()
    }

    /// Baja la lista hasta que [e] quede tocable y lejos del borde de abajo (la barra de pestañas).
    private func hasta(_ e: XCUIElement) {
        XCTAssertTrue(app.otherElements["card-recuperacion"].firstMatch.waitForExistence(timeout: 20) || e.waitForExistence(timeout: 1),
                      "No apareció la card de recuperación")
        // De a poco (un swipeUp entero se pasaba de largo): arrastres cortos hasta que quede entre la barra de arriba y la
        // de pestañas; si se pasó, vuelve.
        let ventana = app.windows.firstMatch
        let alto = ventana.frame.maxY
        let medio = ventana.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        var antes = CGRect.null
        for _ in 0..<30 {
            // La barra de pestañas flota sobre los últimos ~90 pt; al final de la lista ya no baja más y vale como está.
            if e.exists && e.isHittable && e.frame.minY > 120 && (e.frame.maxY < alto - 90 || e.frame == antes) { break }
            antes = e.exists ? e.frame : .null
            let arriba = e.exists && e.frame.minY <= 120 && e.frame.height > 0
            medio.press(forDuration: 0.05, thenDragTo: medio.withOffset(CGVector(dx: 0, dy: arriba ? 220 : -220)))
        }
        XCTAssertTrue(e.isHittable, "No se llegó a \(e) (existe: \(e.exists), \(e.frame))")
    }

    func testConfianzaBajaEnClaro() throws { try confianzaBaja(oscuro: false) }

    func testConfianzaBajaEnOscuro() throws { try confianzaBaja(oscuro: true) }

    private func confianzaBaja(oscuro: Bool) throws {
        let tema = oscuro ? "oscuro" : "claro"
        abrir("baja", oscuro: oscuro)
        let pastilla = app.descendants(matching: .any)["confianza-recuperacion"].firstMatch
        hasta(verTodo)
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
        verTodo.tap()
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
        hasta(verTodo)
        XCTAssertTrue(app.staticTexts["74"].exists, "Falta el score")
        XCTAssertFalse(app.descendants(matching: .any)["confianza-recuperacion"].exists, "Con confianza alta no va la pastilla")
    }

    private func adjuntarCaptura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
