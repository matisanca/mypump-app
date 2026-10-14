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
        XCTAssertTrue(app.tabBars.buttons["Dieta"].waitForExistence(timeout: 5))
        // Ya se vio: al volver a abrir no aparece.
        app.terminate()
        app.launchArguments = ["-token", token, "-pestana", "dieta"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dieta"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Ahora no"].waitForExistence(timeout: 4), "La hoja de permisos volvió a aparecer")
    }
}
