import XCTest

/// El prototipo de la carga simple y el conteo real de toques: la pantalla de hoy (demo) contra el prototipo, ejercicio
/// de 4 series, con escenarios iguales. Cuenta toques, deslizamientos y teclas. Sin cuenta y sin red.
@MainActor
final class CargaSimpleUITests: XCTestCase {
    private var app = XCUIApplication()
    private var gestos = 0
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }

    override func setUp() async throws { continueAfterFailure = false; gestos = 0 }

    // MARK: Ayudas

    private func toque(_ e: XCUIElement) { XCTAssertTrue(e.waitForExistence(timeout: 8), e.debugDescription); e.tap(); gestos += 1 }
    private func tipear(_ t: String) { app.typeText(t); gestos += t.count }
    private func anotar(_ nombre: String) {
        guard let dir else { return }
        let linea = "\(nombre)\t\(gestos)\n"
        let url = URL(fileURLWithPath: dir + "/conteo.tsv")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(linea.utf8)); try? h.close() }
        else { try? linea.write(to: url, atomically: true, encoding: .utf8) }
        print("CONTEO \(nombre) = \(gestos)")
    }
    private func foto(_ nombre: String) {
        guard let dir else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let modo = XCUIDevice.shared.appearance == .dark ? "oscuro" : "claro"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(nombre)-\(modo).png"))
    }

    // MARK: Hoy

    private func abrirHoy(historial: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-entrar", "demo", "-pestana", "entreno", "-abrir", "ejercicio", "-ir", "series", "-descanso", "no", "-sinOnboarding", "YES"]
            + (historial ? ["-historial", "muestra4"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["confirmar-serie-1"].waitForExistence(timeout: 20))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(app.buttons["confirmar-serie-4"].exists, "la demo necesita 4 series")
    }
    private func repsHoy(_ n: Int) -> XCUIElement { app.textFields["Repeticiones de la serie \(n)"] }
    private func kgHoy(_ n: Int) -> XCUIElement { app.textFields["Kilos de la serie \(n)"] }
    private func checkHoy(_ n: Int) { toque(app.buttons["confirmar-serie-\(n)"]) }
    private func hoy(_ n: Int, reps: String?, kg: String?) {
        if let reps { toque(repsHoy(n)); tipear(reps) }
        if let kg { toque(kgHoy(n)); tipear(kg) }
        checkHoy(n)
    }
    private func hechasHoy() -> Int {
        (1...4).filter { app.buttons["confirmar-serie-\($0)"].label.contains("hecha") }.count
    }

    func testHoy_A_repite() {
        abrirHoy(historial: true)
        for n in 1...4 { checkHoy(n) }
        XCTAssertEqual(hechasHoy(), 4); anotar("hoy-A-repite")
    }
    func testHoy_B_subeCarga() {
        abrirHoy(historial: true)
        hoy(1, reps: "10", kg: "82,5"); hoy(2, reps: "10", kg: nil); hoy(3, reps: "10", kg: nil); hoy(4, reps: "10", kg: nil)
        XCTAssertEqual(hechasHoy(), 4); anotar("hoy-B-sube-carga")
    }
    func testHoy_C_repsDistintas() {
        abrirHoy(historial: true)
        hoy(1, reps: "11", kg: "80"); checkHoy(2); hoy(3, reps: "8", kg: nil); checkHoy(4)
        XCTAssertEqual(hechasHoy(), 4); anotar("hoy-C-reps-distintas")
    }
    func testHoy_D_primeraVez() {
        abrirHoy(historial: false)
        hoy(1, reps: "12", kg: "60"); hoy(2, reps: "11", kg: nil); hoy(3, reps: "10", kg: nil); hoy(4, reps: "9", kg: nil)
        XCTAssertEqual(hechasHoy(), 4); anotar("hoy-D-primera-vez")
    }
    func testHoy_E_unaSerieConMenos() {
        abrirHoy(historial: true)
        checkHoy(1); checkHoy(2); checkHoy(3); hoy(4, reps: "8", kg: "75")
        XCTAssertEqual(hechasHoy(), 4); anotar("hoy-E-una-serie-con-menos")
    }

    // MARK: Prototipo

    private func abrir(_ escenario: String, guardia: Int = 0) {
        app = XCUIApplication()
        app.launchArguments = ["-cargaSimple", escenario, "-guardiaOK", "\(guardia)"]
        app.launch()
        XCTAssertTrue(ok.waitForExistence(timeout: 20))
    }
    private var ok: XCUIElement { app.buttons["ok-serie"] }
    private var dial: XCUIElement { app.descendants(matching: .any)["reps-dial"] }
    private func fila(_ n: Int) -> String { app.descendants(matching: .any)["fila-serie-\(n)"].label }
    /// `pasos` positivos: hacia arriba. Un solo gesto, sin importar cuántos escalones.
    private func deslizar(_ pasos: Int) {
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        let c = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        // El arrastre sintético se come los primeros puntos (la zona muerta del toque): se le da margen para caer en el escalón.
        c.press(forDuration: 0.05, thenDragTo: c.withOffset(CGVector(dx: 0, dy: CGFloat(-pasos) * 26.0 + (pasos > 0 ? -13 : 13))), withVelocity: .slow, thenHoldForDuration: 0.1)
        gestos += 1
    }
    private func filaDice(_ n: Int, _ texto: String) { XCTAssertTrue(fila(n).contains(texto), "fila \(n): \(fila(n)) ≠ \(texto)") }

    func testNuevo_A_repite() {
        abrir("normal")
        for _ in 1...4 { toque(ok) }
        XCTAssertTrue(app.descendants(matching: .any)["ejercicio-completo"].waitForExistence(timeout: 3))
        filaDice(1, "10 repeticiones, 80 kilos"); filaDice(3, "9 repeticiones"); filaDice(4, "8 repeticiones, 80 kilos")
        anotar("nuevo-A-repite")
    }
    func testNuevo_B_subeCarga() {
        abrir("aumento")
        foto("01-aumento-sugerido")
        toque(app.buttons["aumento-subir"])
        foto("02-aumento-aceptado")
        for _ in 1...4 { toque(ok) }
        for n in 1...4 { filaDice(n, "8 repeticiones, 82,5 kilos") }
        anotar("nuevo-B-sube-carga")
    }
    func testNuevo_C_repsDistintas() {
        abrir("normal")
        foto("03-carga-unica")
        deslizar(1)
        foto("04-dial-mas-uno")
        toque(ok); toque(ok); deslizar(-1); toque(ok); toque(ok)
        filaDice(1, "11 repeticiones"); filaDice(2, "10 repeticiones"); filaDice(3, "8 repeticiones"); filaDice(4, "8 repeticiones")
        foto("05-completo")
        anotar("nuevo-C-reps-distintas")
    }
    func testNuevo_D_primeraVez() {
        abrir("primera")
        foto("06-primera-vez")
        toque(app.textFields["carga-valor"]); tipear("60"); toque(app.buttons["teclado-listo"])
        toque(ok); toque(app.buttons["reps-menos"]); toque(ok); deslizar(-2); toque(ok); deslizar(-3); toque(ok)
        for n in 1...4 { XCTAssertTrue(fila(n).contains("60 kilos"), fila(n)) }
        filaDice(1, "12 repeticiones"); filaDice(2, "11 repeticiones"); filaDice(3, "10 repeticiones"); filaDice(4, "9 repeticiones")
        anotar("nuevo-D-primera-vez")
    }
    func testNuevo_E_unaSerieConMenos() {
        abrir("normal")
        toque(ok); toque(ok); toque(ok)
        toque(app.switches["toggle-mismo-peso"].switches.firstMatch)
        foto("07-peso-por-serie")
        toque(app.buttons["kg-menos-4"]); toque(app.buttons["kg-menos-4"])
        toque(ok)
        filaDice(3, "80 kilos"); filaDice(4, "75 kilos")
        anotar("nuevo-E-una-serie-con-menos")
    }

    // MARK: Casos que pueden falsear datos

    func testGuardia_OKSeguidoSinTocarPideOtroToque() {
        abrir("normal", guardia: 10)
        ok.tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        ok.tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(fila(2).contains("pendiente"), "el segundo OK sin mirar no registra")
        XCTAssertEqual(ok.label, "¿Ya hiciste la serie? Tocá de nuevo para registrarla")
        foto("08-guardia")
        ok.tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(fila(2).contains("hecha"))
    }
    func testSubirCargaNoReescribeLoHecho() {
        abrir("normal")
        ok.tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.buttons["carga-mas"].tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        filaDice(1, "80 kilos")
        XCTAssertTrue(fila(2).contains("82,5 kilos"), fila(2))
        foto("09-hechas-siguen")
        app.buttons["aplicar-a-hechas"].tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        filaDice(1, "82,5 kilos")
    }
    func testCorregirUnaHechaNoLaDesconfirma() {
        abrir("normal")
        ok.tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.descendants(matching: .any)["fila-serie-1"].tap()
        XCTAssertTrue(app.buttons["correccion-guardar"].waitForExistence(timeout: 3))
        foto("10-corrigiendo")
        filaDice(1, "hecha")
        app.buttons["reps-mas"].tap(); app.buttons["correccion-kg-menos"].tap(); app.buttons["correccion-guardar"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        filaDice(1, "11 repeticiones, 77,5 kilos")
        filaDice(2, "pendiente")
    }
    func testDeslizarElDialNoMueveLaPantallaYDesplazarNoCambiaReps() {
        abrir("normal")
        let carga = app.textFields["carga-valor"]
        XCTAssertTrue(carga.waitForExistence(timeout: 5))
        let antes = carga.frame.minY
        deslizar(3)
        XCTAssertEqual(carga.frame.minY, antes, accuracy: 1, "el dial no desplaza la pantalla")
        XCTAssertTrue(ok.label.contains("13 repeticiones"), ok.label)
        app.scrollViews.firstMatch.swipeUp(); RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(ok.label.contains("13 repeticiones"), "desplazar la lista no cambia las reps")
    }
    func testAmrapNoDejaOKHastaMarcar() {
        abrir("amrap")
        XCTAssertFalse(ok.isEnabled)
        foto("11-amrap")
        app.buttons["reps-mas"].tap()
        XCTAssertTrue(ok.isEnabled)
    }
    func testAuditoriaAccesibilidad() throws {
        abrir("normal")
        var tipos: XCUIAccessibilityAuditType = [.dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .contrast]
        tipos.remove(.contrast)
        try app.performAccessibilityAudit(for: tipos)
    }

    func testCapturasOscuro() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        abrir("aumento"); foto("01-aumento-sugerido")
        abrir("normal"); foto("03-carga-unica"); deslizar(1); foto("04-dial-mas-uno")
        toque(ok); toque(ok); toque(ok)
        toque(app.switches["toggle-mismo-peso"].switches.firstMatch)
        foto("07-peso-por-serie")
        abrir("normal", guardia: 10); ok.tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.5)); ok.tap(); foto("08-guardia")
    }
    func testDeshacerTambienEnLaUltimaSerie() {
        abrir("normal")
        for _ in 1...4 { ok.tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
        XCTAssertTrue(app.descendants(matching: .any)["ejercicio-completo"].exists)
        app.buttons["deshacer-ok"].tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        filaDice(4, "pendiente")
        XCTAssertTrue(ok.exists)
    }
    func testGrabacionDeslizar() {
        abrir("normal")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        deslizar(2); RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        deslizar(-1); RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        ok.tap(); RunLoop.current.run(until: Date().addingTimeInterval(1))
        deslizar(-2); RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }
}
