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
            fila.tap()   // la cierra: desde el 15-oct el ejercicio se abre en la lista, no en otra página
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

    /// Pedido de Mati (15-oct): tocar un ejercicio lo abre ahí mismo, en la lista de Entreno (la tabla de series a la
    /// vista), sin ir a otra página; la página queda para «Técnica y notas». Tocarlo de nuevo lo cierra.
    func testElEjercicioSeAbreEnLaLista() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-token", token, "-pestana", "entreno", "-sinOnboarding", "YES"]
        app.launch()
        let fila = app.buttons["fila-ejercicio-1"]
        XCTAssertTrue(fila.waitForExistence(timeout: 25), "No apareció el primer ejercicio")
        for _ in 0..<8 where !fila.isHittable { app.swipeUp() }
        fila.tap()
        let tecnica = app.buttons["tecnica-y-notas"]
        XCTAssertTrue(tecnica.waitForExistence(timeout: 6), "El ejercicio no se abrió en la lista")
        XCTAssertTrue(fila.exists, "La lista desapareció: se fue a otra página")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "ejercicio-en-la-lista"; a.lifetime = .keepAlways; add(a)
        for _ in 0..<4 where !fila.isHittable { app.swipeDown() }
        fila.tap()
        let cerrado = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: tecnica)
        wait(for: [cerrado], timeout: 6)
    }
}
