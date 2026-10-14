import XCTest

/// Revisión tocada de verdad contra el backend. Corre SOLO con una cuenta de prueba: el token llega por
/// `TEST_RUNNER_MYPUMP_TOKEN` (ej.: `scripts/nativa/probar-ui.sh <udid> real`), nunca escrito en el repo.
@MainActor
final class RevisionUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-pestana", "revision", "-sinOnboarding", "YES"]
        app.launch()
    }

    /// Pedido de Mati (14-oct): ni la IA ni el aviso del domingo son algo que el cliente configure. La IA trabaja bajo
    /// su aprobación y el recordatorio llega como un mensaje suyo: en Mis datos no hay interruptores de ninguno de los dos.
    func testMisDatosNoTieneInterruptorDeIANiDeRecordatorios() throws {
        let misDatos = app.buttons["Mis datos"].firstMatch
        XCTAssertTrue(misDatos.waitForExistence(timeout: 20), "No apareció el acceso a Mis datos")
        misDatos.tap()
        let respaldo = app.buttons["Respaldo científico del plan"].firstMatch
        XCTAssertTrue(app.navigationBars["Mis datos"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !respaldo.isHittable { app.swipeUp() }
        XCTAssertTrue(respaldo.exists, "No se recorrió Mis datos")
        XCTAssertFalse(app.switches["asistente-ia"].exists, "Volvió el interruptor de la IA")
        XCTAssertFalse(app.switches["recordatorio-domingo"].exists, "Volvió el interruptor del recordatorio")
        XCTAssertFalse(app.staticTexts["Inteligencia artificial"].exists)
        adjuntarCaptura("mis-datos-sin-interruptores")
    }

    /// 5.1.1(i) y 1.4.1: desde Mis datos se abren el respaldo científico y la política de privacidad. Las dos hojas
    /// cuelgan de la misma vista, así que vale correrlo también en iOS 17.
    func testMisDatosAbreElRespaldoYLaPolitica() throws {
        let misDatos = app.buttons["Mis datos"].firstMatch
        XCTAssertTrue(misDatos.waitForExistence(timeout: 20), "No apareció el acceso a Mis datos")
        misDatos.tap()
        let respaldo = app.buttons["Respaldo científico del plan"].firstMatch
        for _ in 0..<6 where !respaldo.isHittable { app.swipeUp() }
        XCTAssertTrue(respaldo.isHittable, "No está el respaldo en Mis datos")
        respaldo.tap()
        XCTAssertTrue(app.navigationBars["Respaldo científico"].waitForExistence(timeout: 5), "El respaldo no se abrió")
        app.buttons["Listo"].tap()
        XCTAssertTrue(app.navigationBars["Respaldo científico"].waitForNonExistence(timeout: 5))
        let politica = app.buttons["Política de privacidad"].firstMatch
        XCTAssertTrue(politica.waitForExistence(timeout: 3))
        politica.tap()
        // SFSafariViewController con el botón de cerrar (el contenido corre en otro proceso).
        let cerrar = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cerrar", "Close", "OK", "Listo"])).firstMatch
        XCTAssertTrue(cerrar.waitForExistence(timeout: 10), "La política de privacidad no se abrió")
        adjuntarCaptura("politica-de-privacidad")
        cerrar.tap()
    }

    /// Un hábito se marca y, tocado otra vez, se borra (DIA-03). La cuenta queda como estaba.
    func testUnHabitoSeMarcaYSeBorra() throws {
        let si = app.buttons["Dormí bien: sí"].firstMatch
        XCTAssertTrue(si.waitForExistence(timeout: 20), "No apareció el hábito \"Dormí bien\"")
        // Bien arriba de la barra de pestañas, que en iOS 26 flota encima del contenido: si no, el toque cae en ella.
        let alto = app.windows.firstMatch.frame.maxY
        for _ in 0..<10 where !(si.isHittable && si.frame.maxY < alto - 180) { app.swipeUp() }
        let antes = marcado(si)
        si.tap()
        XCTAssertTrue(esperar(si, seleccionado: !antes), "Tocar \"sí\" no cambió el hábito")
        adjuntarCaptura("habito-tocado")
        si.tap()
        XCTAssertTrue(esperar(si, seleccionado: antes), "Tocarlo otra vez no lo devolvió a como estaba")
    }

    /// El botón dice "marcado" en su valor de accesibilidad (`isSelected` no llega desde un botón de SwiftUI).
    private func marcado(_ e: XCUIElement) -> Bool { (e.value as? String) == "marcado" }

    private func esperar(_ e: XCUIElement, seleccionado: Bool, timeout: TimeInterval = 4) -> Bool {
        let fin = Date().addingTimeInterval(timeout)
        while Date() < fin {
            if marcado(e) == seleccionado { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return marcado(e) == seleccionado
    }

    private func adjuntarCaptura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
