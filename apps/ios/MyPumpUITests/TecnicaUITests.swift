import XCTest

/// Técnica por video contra el doble del servidor (`-tecnicaDePrueba`, sin red). Lo fino de la cola está en el kit; acá va lo que
/// solo se ve con la pantalla de verdad.
@MainActor
final class TecnicaUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ escenario: String, pestana: String = "entreno", extra: [String] = []) {
        app = XCUIApplication()
        let token = "tktecnica" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana, "-tecnicaDePrueba", escenario] + extra
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] }
        app.launch()
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func esperar(_ id: String, _ t: TimeInterval = 15) {
        if e(id).waitForExistence(timeout: t) { return }
        foto("fallo-\(id)")
        XCTFail("No apareció \(id)")
    }
    private func tocar(_ id: String) {
        esperar(id)
        var n = 0
        while !e(id).isHittable && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
        e(id).tap()
    }
    /// La fila puede estar más abajo y una lista perezosa todavía no la tiene.
    private func haciaAbajo(_ id: String) {
        var n = 0
        while !e(id).waitForExistence(timeout: 2.5) && n < 6 { app.swipeUp(velocity: .slow); n += 1 }
    }
    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(UIDevice.current.name.replacingOccurrences(of: " ", with: ""))-\(letraGrande ? "grande" : oscuro ? "oscuro" : "claro")-\(nombre).png")) }
    }

    private func abrirDesdeEjercicio(_ escenario: String) {
        lanzar(escenario, extra: ["-abrir", "ejercicio"])
        tocar("tecnica-mandar-ejercicio")
    }

    private func abrirMiTecnica(_ escenario: String) {
        lanzar(escenario, pestana: "revision", extra: ["-abrir", "misdatos"])
        haciaAbajo("mis-datos-tecnica")
        tocar("mis-datos-tecnica")
    }

    private func elegirYEnviar() {
        esperar("tecnica-consejo")
        tocar("tecnica-agregar-video")
        esperar("tecnica-video-listo")
        tocar("tecnica-enviar")
    }

    private func recorridoCompleto() {
        abrirDesdeEjercicio("vacio")
        esperar("tecnica-aviso")
        foto("1-aviso")
        tocar("tecnica-aviso-ok")
        esperar("tecnica-consejo")
        foto("2-consejo")
        tocar("tecnica-agregar-video")
        esperar("tecnica-video-listo")
        e("tecnica-nota").tap()
        e("tecnica-nota").typeText("Mirá la bajada")
        foto("3-listo")
        tocar("tecnica-enviar")
        esperar("tecnica-recibido", 20)
        foto("4-recibido")
    }

    func testRecorridoClaro() { recorridoCompleto() }
    func testRecorridoOscuro() { oscuro = true; recorridoCompleto() }
    func testRecorridoLetraGrande() { letraGrande = true; recorridoCompleto() }

    func testDesdeMisDatosEligeEjercicio() {
        abrirMiTecnica("vacio")
        esperar("tecnica-vacio")
        foto("5-lista-vacia")
        tocar("tecnica-mandar")
        tocar("tecnica-ejercicio-0")
        foto("6-eligio")
        tocar("tecnica-aviso-ok")
        elegirYEnviar()
        esperar("tecnica-recibido", 20)
        tocar("tecnica-listo")
        esperar("tecnica-fila-enviado")
        foto("7-lista-enviado")
        XCTAssertFalse(e("tecnica-mandar").exists, "con uno en revisión no se manda otro")
    }

    func testAvisoUnaSolaVez() {
        abrirDesdeEjercicio("corte")   // ya aceptado en el servidor
        esperar("tecnica-consejo")
        XCTAssertFalse(e("tecnica-aviso").exists)
    }

    func testCorteEsperaYSePuedeCancelar() {
        abrirDesdeEjercicio("corte")
        elegirYEnviar()
        esperar("tecnica-cancelar", 20)
        foto("8-esperando-senal")
        XCTAssertFalse(e("tecnica-recibido").exists)
        tocar("tecnica-cancelar")
        esperar("tecnica-consejo")
    }

    func testReintentaSoloAnte503Y429() {
        abrirDesdeEjercicio("reintento")
        elegirYEnviar()
        esperar("tecnica-recibido", 25)
    }

    func testRechazoSeVeYDejaProbarDeNuevo() {
        abrirDesdeEjercicio("rechazo")
        elegirYEnviar()
        esperar("tecnica-aviso-envio", 20)
        foto("9-rechazo")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "muy corto")).firstMatch.exists)
        XCTAssertTrue(e("tecnica-agregar-video").exists)
    }

    func testTopeSemanal() {
        abrirDesdeEjercicio("tope")
        elegirYEnviar()
        esperar("tecnica-aviso-envio", 20)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "3 videos")).firstMatch.exists)
    }

    func testPalancaApagadaNoHayNada() {
        lanzar("apagado", extra: ["-abrir", "ejercicio"])
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertFalse(e("tecnica-mandar-ejercicio").exists)
        lanzar("apagado", pestana: "revision", extra: ["-abrir", "misdatos"])
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        XCTAssertFalse(e("mis-datos-tecnica").exists)
    }

    func testSinServidorNoHayNada() {
        lanzar("sinServidor", pestana: "revision", extra: ["-abrir", "misdatos"])
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        XCTAssertFalse(e("mis-datos-tecnica").exists)
    }

    func testEnRevisionNoDejaMandarOtro() {
        abrirDesdeEjercicio("enRevision")
        esperar("tecnica-en-curso")
        foto("10-en-curso")
    }

    private func publicado() {
        abrirMiTecnica("publicado")
        tocar("tecnica-fila-publicado")
        esperar("tecnica-credito")
        foto("11-devolucion")
        XCTAssertEqual(e("tecnica-credito").label, "Lo revisó Mati el 12/11")
        tocar("tecnica-ver-en-video")
        esperar("tecnica-video")
        foto("12-video")
    }

    func testPublicadoClaro() { publicado() }
    func testPublicadoOscuro() { oscuro = true; publicado() }
    func testPublicadoLetraGrande() { letraGrande = true; publicado() }

    func testSinCorrecciones() {
        abrirMiTecnica("publicadoSinCorrecciones")
        tocar("tecnica-fila-publicado")
        esperar("tecnica-sin-correcciones")
        foto("13-sin-correcciones")
    }

    func testRechazadoEnLaLista() {
        abrirMiTecnica("rechazado")
        esperar("tecnica-fila-rechazado")
        foto("14-rechazado")
    }

    func testSacarVideo() {
        abrirMiTecnica("publicado")
        tocar("tecnica-fila-publicado")
        // Pegado al borde de abajo, el toque se lo queda el gesto del sistema.
        esperar("tecnica-sacar")
        app.swipeUp(velocity: .slow)
        tocar("tecnica-sacar")
        // La hoja de confirmación tiene su propio botón con el mismo nombre: el último.
        let botones = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Sacar mi video", "tecnica-sacar"))
        XCTAssertTrue(botones.firstMatch.waitForExistence(timeout: 5))
        foto("15-sacar-confirmar")
        botones.firstMatch.tap()
        let desaparecio = NSPredicate(format: "exists == false")
        expectation(for: desaparecio, evaluatedWith: e("tecnica-ver-en-video"), handler: nil)
        waitForExpectations(timeout: 10)
    }
}
