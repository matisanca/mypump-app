import XCTest

/// SER-01 con una cuenta de prueba (la demo no tiene historial): "Tocá para registrar lo de la última vez" es un botón,
/// como en la web (`data-sugconfirm`), y tocarlo registra la serie. En la 101 era solo texto y no hacía nada (lo encontró
/// Mati el 14-oct). Deja esa serie registrada en la semana actual de la cuenta de prueba. Recorre los ejercicios del día
/// hasta encontrar uno con la pista (cada corrida gasta una serie): solo se saltea si a ninguno le queda.
@MainActor
final class UltimaVezUITests: XCTestCase {
    func testTocarLaPistaDeLaUltimaVezRegistraLaSerie() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-token", token, "-pestana", "entreno", "-sinOnboarding", "YES"]
        app.launch()
        let pista = app.buttons["registrar-ultima-vez"]
        var encontrada = false
        for n in 1...14 {
            let fila = app.buttons["fila-ejercicio-\(n)"]
            guard fila.waitForExistence(timeout: n == 1 ? 25 : 5) else { break }
            for _ in 0..<8 where !fila.isHittable { app.swipeUp() }
            fila.tap()
            if pista.waitForExistence(timeout: 6) { encontrada = true; break }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        guard encontrada else {
            throw XCTSkip("A ningún ejercicio del día le quedan series por registrar con historial esta semana")
        }
        let hechas = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Serie' AND label CONTAINS 'hecha'"))
        let antes = hechas.count
        for _ in 0..<4 where !pista.isHittable { app.swipeUp() }
        pista.tap()
        // Si el día estaba cerrado de una corrida anterior, pregunta si se reabre (SES-07).
        let reabrir = app.buttons["Reabrir día"]
        if reabrir.waitForExistence(timeout: 2) { reabrir.tap() }
        let registrada = expectation(for: NSPredicate(format: "count > %d", antes), evaluatedWith: hechas)
        wait(for: [registrada], timeout: 10)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "ultima-vez-registrada"; a.lifetime = .keepAlways; add(a)
    }
}
