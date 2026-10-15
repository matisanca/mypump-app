import XCTest

/// La hoja de permisos de la primera vez (GEN-06): aparece sola con una cuenta, "Ahora no" la cierra sin pedir nada
/// al sistema, y no vuelve a aparecer.
@MainActor
final class OnboardingUITests: XCTestCase {
    func testAhoraNoCierraSinPedirNadaYNoVuelve() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-token", token, "-pestana", "dieta", "-reiniciarOnboarding", "YES"]
        app.launch()
        let ahoraNo = app.buttons["Ahora no"]
        XCTAssertTrue(ahoraNo.waitForExistence(timeout: 20), "No apareció la hoja de permisos")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "onboarding"; a.lifetime = .keepAlways; add(a)
        while ahoraNo.exists { ahoraNo.tap(); _ = ahoraNo.waitForNonExistence(timeout: 1) || true }
        XCTAssertTrue(app.pestana("Dieta").waitForExistence(timeout: 5))
        // Ya se vio: al volver a abrir no aparece.
        app.terminate()
        app.launchArguments = ["-token", token, "-pestana", "dieta"]
        app.launch()
        XCTAssertTrue(app.pestana("Dieta").waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Ahora no"].waitForExistence(timeout: 4), "La hoja de permisos volvió a aparecer")
    }

    /// Revisión del 15-oct, hallazgo 12: cerrarla deslizando hacia abajo no la marcaba como vista y volvía en cada
    /// arranque. Como en Android, cuenta como "Ahora no": queda vista y no pide nada.
    func testCerrarlaDeslizandoCuentaComoAhoraNoYNoVuelve() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-token", token, "-pestana", "dieta", "-reiniciarOnboarding", "YES"]
        app.launch()
        let ahoraNo = app.buttons["Ahora no"]
        XCTAssertTrue(ahoraNo.waitForExistence(timeout: 20), "No apareció la hoja de permisos")
        // Se arrastra la hoja hacia abajo, sin tocar ningún botón.
        let arriba = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        arriba.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        XCTAssertTrue(ahoraNo.waitForNonExistence(timeout: 5), "La hoja no se cerró deslizando")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "onboarding-cerrada"; a.lifetime = .keepAlways; add(a)
        XCTAssertTrue(app.pestana("Dieta").waitForExistence(timeout: 5))
        // Ya se vio: al volver a abrir no aparece.
        app.terminate()
        app.launchArguments = ["-token", token, "-pestana", "dieta"]
        app.launch()
        XCTAssertTrue(app.pestana("Dieta").waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Ahora no"].waitForExistence(timeout: 4), "Cerrada deslizando, la hoja volvió a aparecer")
    }
}
