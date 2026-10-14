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

    /// Con la `nativa_002` en la base, Mis datos ofrece el asistente de IA (D7). Solo se mira: no se cambia nada.
    func testMisDatosOfreceElAsistenteDeIA() throws {
        let misDatos = app.buttons["Mis datos"].firstMatch
        XCTAssertTrue(misDatos.waitForExistence(timeout: 20), "No apareció el acceso a Mis datos")
        misDatos.tap()
        let ia = app.switches["asistente-ia"].firstMatch
        for _ in 0..<6 where !ia.exists { app.swipeUp() }
        XCTAssertTrue(ia.waitForExistence(timeout: 5), "Mis datos no muestra el asistente de IA: ¿la app no ve la nativa_002?")
        adjuntarCaptura("mis-datos-asistente-ia")
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
