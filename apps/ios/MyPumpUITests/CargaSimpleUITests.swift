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
        app.traerArribaDelPanel(app.buttons["kg-mas-2"])
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))   // un toque mientras frena solo frena el scroll
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
        // Al confirmar, la lista baja sola hasta el descanso: un toque mientras se mueve solo la frena.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        app.traerArribaDelPanel(app.filaSerie(1))
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

    /// Las capturas de diseño, de corrido. Solo corre con `TEST_RUNNER_CARGA_GALERIA=<prefijo>`, y las deja en `CARGA_DIR`.
    func testGaleriaDeDiseno() throws {
        guard let pre = ProcessInfo.processInfo.environment["CARGA_GALERIA"], !pre.isEmpty else { throw XCTSkip("Solo para capturas") }
        let letra = ProcessInfo.processInfo.environment["CARGA_LETRA"].map { ["-UIPreferredContentSizeCategoryName", $0] } ?? []

        lanzar(extra: letra)
        foto("\(pre)-01-serie-actual")
        try? app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription]) { p in
            print("AUDITORIA \(p.auditType.rawValue) \(p.element?.identifier ?? "") \(p.element?.label ?? "") | \(p.compactDescription)")
            return true
        }
        // Un gesto real sostenido: a mitad de camino, con la foto sacada desde otro hilo.
        let d = app.descendants(matching: .any)["reps-dial"]
        let inicio = d.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let ruta = "\(dir ?? "/tmp")/\(pre)-03-deslizando.png"
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 2.2)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: ruta))
        }
        inicio.press(forDuration: 0.1, thenDragTo: inicio.withOffset(CGVector(dx: 0, dy: -66)), withVelocity: .slow, thenHoldForDuration: 2.5)
        foto("\(pre)-03b-sumo-dos")
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        foto("\(pre)-04-serie-hecha")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        app.okSerie.tap()
        espera("label BEGINSWITH '¿Ya hiciste'", app.okSerie, 3)
        foto("\(pre)-05-guardia")
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(2))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        foto("\(pre)-06-varias-hechas")
        for n in 3...4 {
            // En un simulador cargado la ventana de 3 s de la guardia puede vencer entre los dos toques.
            for _ in 0..<4 where !etiqueta(n).contains("hecha") { app.darOK() }
            espera("label CONTAINS 'hecha'", app.filaSerie(n))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        foto("\(pre)-07-completo")

        app.terminate()
        lanzar(extra: letra + ["-aumento", "prueba"])
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        app.traerArribaDelPanel(app.buttons["aumento-subir"])
        foto("\(pre)-02-aumento-sugerido")
        app.buttons["aumento-subir"].tap()
        foto("\(pre)-02b-aumento-aceptado")

        app.terminate()
        lanzar(extra: letra)
        let mismo = app.switches["toggle-mismo-peso"].firstMatch
        if letra.isEmpty { for _ in 0..<4 where !mismo.isHittable { app.swipeUp(velocity: .slow) } } else { app.traerArribaDelPanel(mismo) }
        mismo.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["kg-serie-2"].waitForExistence(timeout: 3))
        app.traerArribaDelPanel(app.buttons["kg-mas-2"])
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        app.buttons["kg-mas-2"].tap()
        foto("\(pre)-08-peso-por-serie")

        app.terminate()
        lanzar(extra: letra)
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        app.traerArribaDelPanel(app.filaSerie(1))
        app.filaSerie(1).tap()
        XCTAssertTrue(app.buttons["correccion-guardar"].waitForExistence(timeout: 3))
        foto("\(pre)-09-correccion")

        // La otra forma de llegar: el ejercicio abierto dentro de la lista del día.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-entrar", "demo", "-pestana", "entreno", "-sinOnboarding", "YES", "-descanso", "no", "-historial", "muestra4"] + letra
        app.launch()
        let ejercicio = app.staticTexts["Remo con barra"].firstMatch
        XCTAssertTrue(ejercicio.waitForExistence(timeout: 20))
        for _ in 0..<5 where !ejercicio.isHittable { app.swipeUp(velocity: .slow) }
        ejercicio.tap()
        XCTAssertTrue(app.filaSerie(1).waitForExistence(timeout: 8))
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        foto("\(pre)-10-en-la-lista")
    }

    /// El gesto y la confirmación, para grabarlos: `h/video.sh` graba entre `.grabar` y `.fin`.
    func testVideoDeDiseno() throws {
        guard let dir, ProcessInfo.processInfo.environment["CARGA_VIDEO"] != nil else { throw XCTSkip("Solo para el video") }
        lanzar()
        try Data().write(to: URL(fileURLWithPath: "\(dir)/.grabar"))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let inicio = app.descendants(matching: .any)["reps-dial"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        inicio.press(forDuration: 0.05, thenDragTo: inicio.withOffset(CGVector(dx: 0, dy: -80)), withVelocity: 60, thenHoldForDuration: 0.3)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        inicio.press(forDuration: 0.05, thenDragTo: inicio.withOffset(CGVector(dx: 0, dy: 30)), withVelocity: 50, thenHoldForDuration: 0.3)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.buttons["reps-mas"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        app.darOK()
        RunLoop.current.run(until: Date().addingTimeInterval(1.8))
        app.buttons["reps-menos"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        for _ in 0..<3 where !etiqueta(2).contains("hecha") { app.darOK() }
        RunLoop.current.run(until: Date().addingTimeInterval(1.8))
        try Data().write(to: URL(fileURLWithPath: "\(dir)/.fin"))
    }

    func testSinRIREnPantalla() {
        lanzar()
        let conRIR = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'RIR' OR label CONTAINS 'en reserva'"))
        XCTAssertEqual(conRIR.count, 0, "Quedó RIR en pantalla")
    }
}
