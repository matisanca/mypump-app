import XCTest

/// Corre la comparación del banco sin manos: abre la app con `-comparar`, acepta la hoja de permisos de Salud si
/// aparece (la primera vez en cada simulador) y espera el veredicto. La app deja el informe en Documents/salud-e2e.json.
final class BancoSaludUITests: XCTestCase {
    @MainActor
    func testLaNativaMandaLoMismoQueLaWeb() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-comparar", "YES"]
        // Las vistas con la cuenta de prueba (nunca un cliente): el token llega por TEST_RUNNER_MYPUMP_TOKEN. Se arranca
        // "conectado" y con el historial hecho: al abrir sube los 7 días sembrados a esa cuenta y las cards los leen.
        if let t = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !t.isEmpty {
            app.launchArguments += ["-token", t, "-mypump_health_connected", "1", "-mypump_health_backfill_v1", "1"]
        }
        app.launch()
        aceptarSalud(app)

        let estado = app.staticTexts["estado-banco"]
        XCTAssertTrue(estado.waitForExistence(timeout: 30), "la app no arrancó")
        let veredicto = NSPredicate(format: "label == %@ OR label == %@ OR label BEGINSWITH %@", "IGUALES", "DISTINTOS", "Sin permiso")
        let espera = XCTNSPredicateExpectation(predicate: veredicto, object: estado)
        XCTAssertEqual(XCTWaiter().wait(for: [espera], timeout: 900), .completed, "no terminó: \(estado.label)")
        adjuntar(app, "veredicto")
        XCTAssertEqual(estado.label, "IGUALES")

        // Con la cuenta de prueba: las vistas de salud con datos reales (capturas en el .xcresult).
        guard ProcessInfo.processInfo.environment["MYPUMP_TOKEN"] != nil else { return }
        let card = app.descendants(matching: .any).matching(identifier: "card-recuperacion").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "no apareció la card de Recuperación")
        // La card Salud aparece cuando la sincronización subió los 7 días y get_salud los trajo de vuelta.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "card-salud").firstMatch.waitForExistence(timeout: 120),
                      "no llegaron los datos a la card Salud")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.swipeUp()
        adjuntar(app, "cards-1")
        app.swipeUp()
        adjuntar(app, "cards-2")
        let misDatos = app.buttons["Mis datos de salud"]
        if misDatos.waitForExistence(timeout: 5) {
            misDatos.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            adjuntar(app, "mis-datos-1")
            for i in 2...5 { app.swipeUp(); adjuntar(app, "mis-datos-\(i)") }
        }
    }

    /// La hoja de Salud: "Activar todo" y "Permitir" (o en inglés). Si ya se había dado, no aparece. En iOS 26 el
    /// "Permitir" es un botón grande abajo que no siempre se expone como `.button`: se busca en todo el árbol.
    @MainActor
    private func aceptarSalud(_ app: XCUIApplication) {
        let activar = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Turn On All", "Activar todo", "Activar todos", "Activar todas"])).firstMatch
        guard activar.waitForExistence(timeout: 25) else { return }
        adjuntar(app, "hoja-salud")
        activar.tap()
        let permitir = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Allow", "Permitir"])).firstMatch
        guard permitir.waitForExistence(timeout: 10) else {
            let a = XCTAttachment(string: app.debugDescription)
            a.name = "arbol-hoja-salud"
            a.lifetime = .keepAlways
            add(a)
            XCTFail("no encontré \"Permitir\" en la hoja de Salud")
            return
        }
        permitir.tap()
        // Si la hoja sigue (el primer toque cayó en el texto y no en el botón), un toque más en el centro del botón.
        if activar.waitForExistence(timeout: 2) && permitir.exists {
            permitir.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    @MainActor
    private func adjuntar(_ app: XCUIApplication, _ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
