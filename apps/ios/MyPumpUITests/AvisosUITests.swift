import XCTest

/// NOT-05: "Activar notificaciones" pide el permiso del sistema y, con el sí, deja agendado el aviso del domingo (id 1002,
/// como la Capacitor). Lo agendado no se ve desde la prueba: lo lee `scripts/nativa/avisos_programados.py` en la carpeta
/// de avisos del simulador.
@MainActor
final class AvisosUITests: XCTestCase {
    func testActivarNotificacionesPideElPermisoYCierraLaHoja() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-token", token, "-pestana", "revision", "-reiniciarOnboarding", "YES"]
        app.launch()
        let ahoraNo = app.buttons["Ahora no"]
        XCTAssertTrue(ahoraNo.waitForExistence(timeout: 20), "No apareció la hoja de permisos")
        // Si el simulador ofrece Salud, va primero: se saltea sin pedir nada.
        let activar = app.buttons["Activar notificaciones"]
        if !activar.exists { ahoraNo.tap() }
        XCTAssertTrue(activar.waitForExistence(timeout: 5), "No llegó el paso de los avisos")
        activar.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permitir = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Permitir"])).firstMatch
        if permitir.waitForExistence(timeout: 8) { permitir.tap() }
        // Con permiso la hoja se cierra sola (sin permiso diría "Quedó sin permiso").
        XCTAssertTrue(activar.waitForNonExistence(timeout: 10), "La hoja sigue abierta: ¿se negó el permiso?")
        XCTAssertTrue(app.pestana("Revisión").waitForExistence(timeout: 5))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "despues-de-activar"; a.lifetime = .keepAlways; add(a)
    }
}
