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

    /// Alan Fried, 17-oct: tocó «Permitir acceso a Salud», en la hoja de Salud bajó hasta abajo, tocó «No permitir» y
    /// el botón quedó cargando. Con todo rechazado, la hoja de permisos tiene que pasar enseguida a los avisos.
    /// Con la app recién instalada (si Salud ya preguntó, no muestra la hoja): `simctl uninstall` antes.
    func testSaludNoPermitirSigueEnseguida() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-token", token, "-pestana", "dieta", "-reiniciarOnboarding", "YES"]
        app.launch()
        let permitir = app.buttons["Permitir acceso a Salud"]
        XCTAssertTrue(permitir.waitForExistence(timeout: 20), "No apareció el paso de Salud")
        permitir.tap()
        let avisos = app.staticTexts["Que no se te pase nada"]
        var hojas = 0
        var ultimoToque = Date()
        let inicio = Date()
        while Date().timeIntervalSince(inicio) < 45, !avisos.exists {
            if let b = noPermitir(app) {
                hojas += 1
                let s = XCTAttachment(screenshot: app.screenshot()); s.name = "hoja-salud-\(hojas)"; s.lifetime = .keepAlways; add(s)
                b.tap()
                // iOS 26: «Puedes activar las categorías de datos de salud en otro momento desde la app Salud» y «OK».
                let ok = app.buttons["OK"]
                if ok.waitForExistence(timeout: 3) { ok.tap() }
                ultimoToque = Date()
                sleep(1)
                let d = XCTAttachment(screenshot: app.screenshot()); d.name = "despues-de-no-permitir-\(hojas)"; d.lifetime = .keepAlways; add(d)
            }
            _ = avisos.waitForExistence(timeout: 1)
        }
        let espera = Date().timeIntervalSince(ultimoToque)
        XCTAssertGreaterThan(hojas, 0, "No apareció la hoja de Salud")
        XCTAssertTrue(avisos.exists, "Después de «No permitir» no pasó a los avisos (hojas: \(hojas))")
        XCTAssertLessThan(espera, 5, "Después de «No permitir» quedó \(Int(espera)) s cargando (hojas: \(hojas))")
    }

    /// El «No permitir» de la hoja de Salud, en castellano o en inglés; si está más abajo, baja hasta verlo.
    private func noPermitir(_ app: XCUIApplication) -> XCUIElement? {
        for nombre in ["No permitir", "Don’t Allow", "Don't Allow"] {
            let b = app.buttons[nombre]
            guard b.exists else { continue }
            var intentos = 0
            while !b.isHittable, intentos < 4 { app.swipeUp(); intentos += 1 }
            if b.isHittable { return b }
        }
        return nil
    }
}
