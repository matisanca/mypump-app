import XCTest

/// La carga simple en la pantalla real de Entreno (demo, sin cuenta ni red). `-historial muestra4` deja la vez pasada en
/// 4 series. Lo fino (aumentos, guardia a los 10 s, relanzar) está en el kit; acá va lo que solo se ve con la vista.
@MainActor
final class CargaSimpleUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(historial: Bool = true, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-entrar", "demo", "-pestana", "entreno", "-abrir", "ejercicio", "-ir", "series", "-sinOnboarding", "YES", "-descanso", "no"]
            + (historial ? ["-historial", "muestra4"] : []) + extra
        app.launch()
        XCTAssertTrue(app.filaSerie(1).waitForExistence(timeout: 20), "No abrió el ejercicio")
    }
    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(nombre).png")) }
    }
    private func etiqueta(_ n: Int) -> String { app.filaSerie(n).label }
    private func espera(_ formato: String, _ e: XCUIElement, _ t: TimeInterval = 5) {
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: formato), evaluatedWith: e)], timeout: t), .completed, "\(formato) ← \(e.exists ? e.label : "no existe")")
    }

    func testLaCargaUnicaSeAplicaATodasLasPendientes() {
        lanzar()
        foto("carga-1-pantalla")
        app.buttons["carga-mas"].tap()
        let tras = app.cargaValor.value as? String ?? ""
        XCTAssertFalse(tras.isEmpty)
        for n in 1...4 { XCTAssertTrue(etiqueta(n).contains("\(tras) kilos"), etiqueta(n)) }
        XCTAssertTrue(app.buttons["reps-mas"].exists && app.buttons["reps-menos"].exists, "El − y el + tienen que estar a la vista")
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        XCTAssertTrue(etiqueta(1).contains("\(tras) kilos"), "Grabó otro kilo: \(etiqueta(1))")
        // La serie 2 sale con el kilo nuevo (el error de producción era el kilo viejo).
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(2))
        XCTAssertTrue(etiqueta(2).contains("\(tras) kilos"), etiqueta(2))
    }

    func testDeshacerVuelveLaSeriePendiente() {
        lanzar()
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        XCTAssertTrue(app.buttons["deshacer-ok"].waitForExistence(timeout: 2), "Sin Deshacer")
        foto("carga-2-deshacer")
        app.buttons["deshacer-ok"].tap()
        espera("label CONTAINS 'pendiente'", app.filaSerie(1))
        XCTAssertFalse(app.buttons["deshacer-ok"].exists)
    }

    func testPesoPorSerieSoloCambiaEsaSerie() {
        lanzar()
        let mismo = app.switches["toggle-mismo-peso"].firstMatch
        for _ in 0..<4 where !mismo.isHittable { app.swipeUp(velocity: .slow) }
        mismo.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["kg-serie-2"].waitForExistence(timeout: 3), "Sin peso por serie")
        let antes1 = app.textFields["kg-serie-1"].value as? String ?? ""
        let antes3 = app.textFields["kg-serie-3"].value as? String ?? ""
        let antes2 = app.textFields["kg-serie-2"].value as? String ?? ""
        for _ in 0..<4 where !app.buttons["kg-mas-2"].isHittable { app.swipeUp(velocity: .slow) }
        app.buttons["kg-mas-2"].tap()
        XCTAssertNotEqual(app.textFields["kg-serie-2"].value as? String, antes2)
        XCTAssertEqual(app.textFields["kg-serie-1"].value as? String, antes1)
        XCTAssertEqual(app.textFields["kg-serie-3"].value as? String, antes3)
        foto("carga-3-por-serie")
    }

    func testUnaSerieHechaSeCorrigeYNoSeDesmarca() {
        lanzar()
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        app.filaSerie(1).tap()
        XCTAssertTrue(app.buttons["correccion-guardar"].waitForExistence(timeout: 3), "No abrió la corrección")
        XCTAssertTrue(etiqueta(1).contains("hecha"), "Tocar una serie hecha la desmarcó")
        app.buttons["reps-menos"].tap()
        foto("carga-4-correccion")
        app.buttons["correccion-guardar"].tap()
        XCTAssertTrue(app.buttons["correccion-guardar"].waitForNonExistence(timeout: 4))
        XCTAssertTrue(etiqueta(1).contains("hecha"), etiqueta(1))
    }

    func testRepetirElOKAlInstantePideUnSegundoToque() {
        lanzar()
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        app.okSerie.tap()
        espera("label BEGINSWITH '¿Ya hiciste'", app.okSerie, 3)
        XCTAssertTrue(etiqueta(2).contains("pendiente"), "La guardia no frenó el OK")
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        app.okSerie.tap()
        espera("label CONTAINS 'hecha'", app.filaSerie(2))
    }

    func testSinRIREnPantalla() {
        lanzar()
        let conRIR = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'RIR' OR label CONTAINS 'en reserva'"))
        XCTAssertEqual(conRIR.count, 0, "Quedó RIR en pantalla")
    }
}
