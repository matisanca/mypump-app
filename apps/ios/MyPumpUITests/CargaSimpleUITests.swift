import XCTest

/// La carga simple en la pantalla real de Entreno (demo, sin cuenta ni red). `-historial muestra4` deja la vez pasada en
/// 4 series. Lo fino (aumentos, guardia a los 10 s, relanzar) está en el kit; acá va lo que solo se ve con la vista.
@MainActor
final class CargaSimpleUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(historial: Bool = true, irASeries: Bool = true, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-entrar", "demo", "-pestana", "entreno", "-abrir", "ejercicio"] + (irASeries ? ["-ir", "series"] : [])
            + ["-sinOnboarding", "YES", "-descanso", "no"] + (historial ? ["-historial", "muestra4"] : []) + extra
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

    // MARK: 2.3.3, salir del peso sin registrar nada (Sebastián, 19/11)

    private var teclado: XCUIElement { app.keyboards.firstMatch }

    /// Abre el teclado del kilo y escribe. Con el teclado arriba el panel (y su OK) se esconde.
    private func escribirKilo(_ texto: String) {
        XCTAssertTrue(app.cargaValor.waitForExistence(timeout: 15), "Sin el campo de la carga")
        app.traerArribaDelPanel(app.cargaValor)
        app.cargaValor.tap()
        XCTAssertTrue(teclado.waitForExistence(timeout: 4), "No abrió el teclado")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))   // la selección llega 0,08 s después del foco
        app.cargaValor.typeText(texto)
    }

    /// Toca el «kg» de al lado del número: es parte de la tarjeta, no del campo.
    private func tocarAfueraDelPeso() {
        app.cargaValor.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 26, dy: 0)).tap()
    }

    func testListoArribaDelTecladoLoCierra() {
        lanzar()
        escribirKilo("83")
        XCTAssertFalse(app.okSerie.exists, "Con el teclado arriba el OK tiene que estar escondido")
        XCTAssertTrue(app.buttons["teclado-listo"].waitForExistence(timeout: 3), "Sin «Listo» arriba del teclado")
        foto("carga-5-listo")
        app.buttons["teclado-listo"].tap()
        XCTAssertTrue(teclado.waitForNonExistence(timeout: 4), "«Listo» no cerró el teclado")
        XCTAssertTrue(app.okSerie.waitForExistence(timeout: 4), "El panel no volvió")
        XCTAssertEqual(app.cargaValor.value as? String, "83")
        XCTAssertTrue(etiqueta(1).contains("pendiente"), "Cerrar el teclado registró la serie: \(etiqueta(1))")
    }

    func testTocarAfueraDelPesoCierraElTeclado() {
        lanzar()
        escribirKilo("83")
        // Tocar el mismo campo (mover el cursor) no lo cierra.
        app.cargaValor.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(teclado.exists, "Tocar el campo cerró el teclado")
        tocarAfueraDelPeso()
        XCTAssertTrue(teclado.waitForNonExistence(timeout: 4), "Tocar afuera no cerró el teclado")
        XCTAssertTrue(app.okSerie.waitForExistence(timeout: 4), "El panel no volvió")
        XCTAssertTrue(etiqueta(1).contains("83 kilos"), etiqueta(1))
        XCTAssertTrue(etiqueta(1).contains("pendiente"), etiqueta(1))
    }

    /// Con la espera alargada a 4 s (`-esperaOK`): el simulador tarda más de medio segundo entre dos toques. El OK tocado
    /// enseguida de cerrar el teclado no registra; pasada la espera, sí, con el peso escrito.
    func testElToqueQueCierraElTecladoNoRegistraLaSerie() {
        lanzar(extra: ["-esperaOK", "4000"])
        escribirKilo("83")
        app.buttons["teclado-listo"].tap()
        XCTAssertTrue(app.okSerie.waitForExistence(timeout: 3), "El panel no volvió")
        app.okSerie.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertTrue(etiqueta(1).contains("pendiente"), "El toque apurado registró la serie: \(etiqueta(1))")
        XCTAssertFalse(app.buttons["deshacer-ok"].exists)
        // Lo mismo cerrando con un toque afuera.
        escribirKilo("84")
        tocarAfueraDelPeso()
        XCTAssertTrue(app.okSerie.waitForExistence(timeout: 3), "El panel no volvió")
        app.okSerie.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertTrue(etiqueta(1).contains("pendiente"), "El toque apurado registró la serie: \(etiqueta(1))")
        RunLoop.current.run(until: Date().addingTimeInterval(3.5))
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        XCTAssertTrue(etiqueta(1).contains("84 kilos"), etiqueta(1))
    }

    /// El peso de la corrección vive en el panel: con el teclado arriba el panel sigue, y «Listo» también lo cierra.
    func testLaCorreccionDelPesoTieneListo() {
        lanzar()
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        app.traerArribaDelPanel(app.filaSerie(1))
        app.filaSerie(1).tap()
        let kg = app.textFields["correccion-kg"]
        XCTAssertTrue(kg.waitForExistence(timeout: 3), "No abrió la corrección")
        // Al borde derecho: el cursor queda al final y los borrados se llevan el peso anterior.
        kg.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(teclado.waitForExistence(timeout: 4), "No abrió el teclado")
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(kg.exists && app.buttons["correccion-guardar"].exists, "El panel de la corrección se escondió con el teclado")
        XCTAssertTrue(app.buttons["teclado-listo"].firstMatch.waitForExistence(timeout: 3), "Sin «Listo» al corregir")
        kg.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "85")
        foto("carga-7-correccion-teclado")
        app.buttons["teclado-listo"].firstMatch.tap()
        XCTAssertTrue(teclado.waitForNonExistence(timeout: 4), "«Listo» no cerró el teclado de la corrección")
        XCTAssertEqual(kg.value as? String, "85")
        app.buttons["correccion-guardar"].tap()
        XCTAssertTrue(app.buttons["correccion-guardar"].waitForNonExistence(timeout: 4))
        XCTAssertTrue(etiqueta(1).contains("85 kilos"), etiqueta(1))
    }

    // MARK: 2.3.3, qué serie va (Nicolás, 19/11)

    private func esLaActiva(_ n: Int) -> Bool { (app.filaSerie(n).value as? String) == "La que toca ahora" }

    func testLaFilaActivaSeDistingue() {
        lanzar()
        let ahora = app.staticTexts["serie-ahora"]
        XCTAssertTrue(ahora.waitForExistence(timeout: 5), "Sin «Ahora: serie N de M»")
        XCTAssertEqual(ahora.label, "Ahora: serie 1 de 4")
        XCTAssertTrue(esLaActiva(1), "La fila 1 no tiene la marca: \(app.filaSerie(1).value ?? "nil")")
        for n in 2...4 { XCTAssertFalse(esLaActiva(n), "La fila \(n) no es la que toca") }
        app.traerArribaDelPanel(app.filaSerie(1))
        foto("carga-6-fila-activa")
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        espera("label == 'Ahora: serie 2 de 4'", ahora)
        XCTAssertFalse(esLaActiva(1), "La hecha sigue marcada como la que toca")
        XCTAssertTrue(esLaActiva(2), "La fila 2 no tiene la marca")
    }

    // MARK: 2.3.3, letra más cómoda

    func testCapturasLetraNormal() { capturas(modo: "normal", letra: nil) }

    /// accessibility1 por defecto; `CARGA_LETRA` elige otra (p. ej. UICTContentSizeCategoryXXXL).
    func testCapturasLetraGrande() {
        capturas(modo: "grande", letra: ProcessInfo.processInfo.environment["CARGA_LETRA"] ?? "UICTContentSizeCategoryAccessibilityM")
    }

    /// Las capturas de la 2.3.3, y lo que importa en un iPhone SE con la letra grande: después de dar OK, el descanso y el
    /// OK se ven enteros sin desplazar.
    private func capturas(modo: String, letra: String?) {
        let extra = letra.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? []
        lanzar(irASeries: false, extra: extra + ["-nota", "prueba"])
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertTrue(app.descendants(matching: .any)["nota-semana"].firstMatch.exists, "Sin el objetivo de la semana")
        foto("s3-\(modo)-1-ejercicio")
        app.darOK()
        espera("label CONTAINS 'hecha'", app.filaSerie(1))
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        let ventana = app.windows.firstMatch.frame
        for e in [app.descendants(matching: .any)["descanso-chip"].firstMatch, app.okSerie] {
            XCTAssertTrue(e.waitForExistence(timeout: 4), "Sin \(e.identifier) con la letra \(modo)")
            XCTAssertTrue(e.frame.minY >= ventana.minY && e.frame.maxY <= ventana.maxY && e.isHittable,
                          "\(e.identifier) fuera de la pantalla con la letra \(modo): \(e.frame) en \(ventana)")
        }
        foto("s3-\(modo)-2-descanso")
        app.traerArribaDelPanel(app.filaSerie(4))
        foto("s3-\(modo)-3-series")
        app.traerArribaDelPanel(app.cargaValor)
        app.cargaValor.tap()
        XCTAssertTrue(app.buttons["teclado-listo"].waitForExistence(timeout: 4), "Sin «Listo» con la letra \(modo)")
        foto("s3-\(modo)-4-listo")
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
