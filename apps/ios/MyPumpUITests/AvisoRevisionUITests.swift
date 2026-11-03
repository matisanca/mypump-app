import XCTest

/// R2 de la 2.0.3: el aviso local de revisión no sale si la semana ya está completa (el check y las tres fotos). El check
/// y las fotos son inventados (`-semanaDePrueba`, solo Debug) y lo agendado se lee con `-verAvisoDomingo`. Lo demás va a
/// la cuenta de prueba, cuyo token llega por `TEST_RUNNER_MYPUMP_TOKEN`. Gemelo de `AvisoRevisionUiTest.kt`.
@MainActor
final class AvisoRevisionUITests: XCTestCase {
    private var app = XCUIApplication()
    private var token = ""

    override func setUp() async throws {
        continueAfterFailure = false
        guard let t = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !t.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        token = t
    }

    /// El domingo que viene a las 11:00 (hoy, si es domingo antes de las 11); con la semana completa, el siguiente.
    private func esperado(completa: Bool) -> String {
        let cal = Calendar.current
        let ahora = Date()
        var patron = DateComponents()
        patron.weekday = 1; patron.hour = 11; patron.minute = 0
        var d = cal.nextDate(after: ahora, matching: patron, matchingPolicy: .nextTime)!
        let domingoTarde = cal.component(.weekday, from: ahora) == 1 && cal.component(.hour, from: ahora) >= 11
        if completa && !domingoTarde { d = cal.date(byAdding: .day, value: 7, to: d)! }
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d 11:00", c.year!, c.month!, c.day!)
    }

    private func abrir(_ semana: String) -> XCUIElement {
        app.launchArguments = ["-token", token, "-pestana", "revision", "-sinOnboarding", "YES", "-semanaDePrueba", semana,
                               "-verAvisoDomingo", "YES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permitir = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Permitir"])).firstMatch
        if permitir.waitForExistence(timeout: 5) { permitir.tap() }
        return app.staticTexts["aviso-domingo"].firstMatch
    }

    private func esperar(_ e: XCUIElement, texto: String, timeout: TimeInterval = 25) -> Bool {
        let fin = Date().addingTimeInterval(timeout)
        while Date() < fin {
            if e.exists && e.label == texto { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return e.exists && e.label == texto
    }

    func testConLaSemanaCompletaSeSalteaElDeEstaSemana() throws {
        let aviso = abrir("completa")
        let quiero = esperado(completa: true)
        XCTAssertTrue(esperar(aviso, texto: quiero), "Agendado: \(aviso.exists ? aviso.label : "nada"); esperaba \(quiero)")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "r203-aviso-semana-completa"; a.lifetime = .keepAlways; add(a)
    }

    func testConLaSemanaIncompletaSigueComoHoy() throws {
        let aviso = abrir("incompleta")
        let quiero = esperado(completa: false)
        XCTAssertTrue(esperar(aviso, texto: quiero), "Agendado: \(aviso.exists ? aviso.label : "nada"); esperaba \(quiero)")
    }
}
