import XCTest

/// La cola B de la 2.3.0 contra el servidor de mentira (`-colaBDePrueba`, sin red y con datos inventados): «Tu recorrido con
/// Mati», «Dónde comprarlo» y «Entreno en casa». Las reglas finas están en el kit (`ColaBTests`); acá, lo que se ve.
@MainActor
final class ColaBUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ escenario: String, pestana: String = "entreno") {
        app = XCUIApplication()
        let token = "tkcolab" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(13).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana, "-colaBDePrueba", escenario]
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
        app.launch()
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func esperar(_ id: String, _ t: TimeInterval = 20) {
        if e(id).waitForExistence(timeout: t) { return }
        foto("fallo-\(id)")
        XCTFail("No apareció \(id)")
    }
    private func noEsta(_ id: String, _ t: TimeInterval = 3) { XCTAssertFalse(e(id).waitForExistence(timeout: t), "No tenía que verse \(id)") }
    private func subirHasta(_ id: String) {
        var n = 0
        while !(e(id).exists && e(id).isHittable) && n < 14 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38)))
            n += 1
        }
    }
    /// En una lista larga (o con letra grande) el elemento puede no existir hasta bajar.
    private func tocar(_ id: String) {
        if !e(id).waitForExistence(timeout: 8) { subirHasta(id) }
        esperar(id); subirHasta(id); e(id).tap()
    }
    private func texto(_ s: String) -> XCUIElement { app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
    private func pausa(_ s: TimeInterval = 0.6) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    private func foto(_ nombre: String) {
        pausa()
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(letraGrande ? "grande" : oscuro ? "oscuro" : "claro")-\(nombre).png")) }
    }
    private func escribir(_ id: String, _ t: String) {
        tocar(id)
        e(id).typeText(t)
    }
    private func cerrarTeclado() {
        // El «Listo» de arriba del teclado (arrastrar hacia abajo cerraría la hoja).
        let listo = app.buttons["teclado-listo"].firstMatch
        if listo.waitForExistence(timeout: 5) { listo.tap() }
        pausa(0.4)
    }
    /// El interruptor de verdad está a la derecha de su texto.
    private func tocarInterruptor() {
        esperar("casa-interruptor")
        let s = e("casa-interruptor")
        let interno = s.switches.firstMatch
        if interno.exists { interno.tap() } else { s.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
    }
    private func valorInterruptor() -> String { (e("casa-interruptor").value as? String) ?? "" }

    /// La pestaña aparece cuando llega la suplementación: no se puede arrancar en ella.
    private func irASuplementacion() {
        let b = app.tabBars.buttons["Suplementación"].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 30))
        b.tap()
    }

    // MARK: Tu recorrido

    private func recorrido() {
        lanzar("todo")
        // Se abre sola la primera vez.
        esperar("recorrido-hoja", 30)
        esperar("recorrido-logro-0")
        XCTAssertTrue(texto("Tu recorrido").exists || e("recorrido-titulo").exists)
        foto("recorrido-1-hoja")
        subirHasta("recorrido-mejor")
        foto("recorrido-2-preguntas")
        escribir("recorrido-mejor", "La constancia")
        cerrarTeclado()
        tocar("recorrido-agendar")
        esperar("recorrido-listo")
        XCTAssertTrue(texto("Te escribe para coordinar el horario.").exists)
        noEsta("recorrido-agendar", 1)
        foto("recorrido-3-pedido")
        tocar("recorrido-cerrar")
        // La tarjeta queda arriba de Entreno, con su botón.
        esperar("recorrido-tarjeta")
        XCTAssertTrue(texto("Mati ya recibió tu pedido.").exists)
        foto("recorrido-4-tarjeta")
        tocar("recorrido-abrir")
        esperar("recorrido-listo")
        tocar("recorrido-cerrar")
    }

    func testRecorridoSeAbreSoloSePideYQuedaLaTarjeta() { recorrido() }

    func testRecorridoNoSeAbreSoloDosVeces() {
        lanzar("todo")
        esperar("recorrido-hoja", 30)
        tocar("recorrido-cerrar")
        esperar("recorrido-tarjeta")
        XCTAssertTrue(texto("Mirá todo lo que hiciste en estos meses.").exists)
        foto("recorrido-5-tarjeta-publicado")
        app.terminate()
        app.launch()   // los mismos argumentos: la misma cuenta
        esperar("recorrido-tarjeta", 30)
        noEsta("recorrido-hoja", 5)
    }

    func testRecorridoUnCorteAvisaYSeReintenta() {
        lanzar("falla")
        esperar("recorrido-hoja", 30)
        tocar("recorrido-agendar")
        esperar("recorrido-error")
        XCTAssertTrue(texto("No se pudo enviar. Probá de nuevo.").exists)
        foto("recorrido-6-error")
        tocar("recorrido-agendar")
        esperar("recorrido-listo")
    }

    func testRecorridoAgendadoYDesdeMisDatos() {
        lanzar("agendado", pestana: "revision")
        let datos = app.buttons["Mis datos"].firstMatch
        XCTAssertTrue(datos.waitForExistence(timeout: 20))
        datos.tap()
        tocar("mis-datos-recorrido")
        esperar("recorrido-listo")
        XCTAssertTrue(texto("Tu videollamada con Mati ya está agendada.").exists)
        noEsta("recorrido-agendar", 1)
        noEsta("recorrido-mejor", 1)
        foto("recorrido-7-agendado")
    }

    // MARK: Apagado

    func testApagadoNoSeVeNada() {
        lanzar("apagado")
        esperar("gimnasio-tarjeta")
        noEsta("recorrido-tarjeta", 4)
        noEsta("recorrido-hoja", 1)
        tocar("gimnasio-tarjeta")
        esperar("gimnasio-zona-poleas")
        noEsta("casa-interruptor", 2)
        app.terminate()
        lanzar("apagado")
        irASuplementacion()
        esperar("supl-momento-desayuno")
        noEsta("compras-ayuda", 3)
        noEsta("compras-abrir-0", 1)
        foto("apagado-suplementacion")
    }

    func testSinElServidorNuevoNoSeVeNada() {
        lanzar("sinServidor")
        esperar("gimnasio-tarjeta")
        noEsta("recorrido-tarjeta", 4)
        tocar("gimnasio-tarjeta")
        esperar("gimnasio-zona-poleas")
        noEsta("casa-interruptor", 2)
    }

    // MARK: Dónde comprarlo

    private func compras() {
        lanzar("pedido")
        irASuplementacion()
        esperar("compras-ayuda")
        esperar("compras-abrir-0")
        foto("compras-1-pestana")
        tocar("compras-abrir-0")
        esperar("compras-hoja")
        esperar("compras-tienda-0")
        XCTAssertTrue(texto("Son lugares que Mati revisó.").exists || e("compras-pie").exists)
        // La segunda opción no tiene dirección: sin botón.
        esperar("compras-opcion-1")
        noEsta("compras-tienda-1", 1)
        foto("compras-2-hoja")
        tocar("compras-cerrar")
        noEsta("compras-hoja", 2)
    }

    func testComprasBotonHojaYCierre() { compras() }

    // MARK: Entreno en casa

    private func casa() {
        lanzar("pedido")
        // El botón de la tarjeta de Entreno lleva directo al interruptor.
        tocar("casa-tarjeta")
        esperar("gimnasio-zona-poleas")
        esperar("casa-interruptor")
        XCTAssertEqual(valorInterruptor(), "0")
        foto("casa-1-interruptor")
        tocarInterruptor()
        esperar("casa-lista")
        XCTAssertEqual(valorInterruptor(), "1")
        noEsta("gimnasio-zona-poleas", 1)
        XCTAssertFalse(e("casa-enviar").isEnabled)
        foto("casa-2-lista")
        tocar("casa-tipo-mancuernas")
        escribir("casa-kg-mancuernas", "20")
        cerrarTeclado()
        tocar("casa-tipo-banco_plano")
        foto("casa-3-marcado")
        XCTAssertTrue(e("casa-enviar").isEnabled)
        // «No tengo nada de esto» desmarca lo demás, y marcar algo lo saca.
        tocar("casa-sin-equipo")
        XCTAssertTrue(e("casa-enviar").isEnabled)
        noEsta("casa-kg-mancuernas", 1)
        tocar("casa-tipo-bandas_elasticas")
        e("casa-enviar").tap()
        esperar("casa-recibido")
        XCTAssertTrue(texto("Ya lo recibimos.").exists || !e("casa-interruptor").isEnabled)
        foto("casa-4-recibido")
    }

    func testCasaPrenderMarcarYEnviar() { casa() }

    func testCasaApagarVuelveAlGimnasio() {
        lanzar("casaBorrador")
        tocar("gimnasio-tarjeta")
        esperar("casa-lista")
        tocarInterruptor()
        esperar("gimnasio-zona-poleas")
        noEsta("casa-lista", 1)
        XCTAssertEqual(valorInterruptor(), "0")
    }

    private func casaVigente() {
        lanzar("casaVigente", pestana: "revision")
        let datos = app.buttons["Mis datos"].firstMatch
        XCTAssertTrue(datos.waitForExistence(timeout: 20))
        datos.tap()
        tocar("mis-datos-gimnasio")
        esperar("casa-vigente")
        XCTAssertTrue(texto("Entrenás en casa").exists)
        XCTAssertTrue(texto("hasta 20 kg").exists)
        noEsta("gimnasio-falta-algo", 1)
        foto("casa-5-vigente")
        tocar("casa-cambiar")
        esperar("casa-lista")
    }

    func testCasaVigenteYCambiar() { casaVigente() }

    func testCasaEnRevisionNoSePuedeCambiar() {
        lanzar("casaRecibido")
        tocar("gimnasio-tarjeta")
        esperar("casa-recibido")
        XCTAssertFalse(e("casa-interruptor").isEnabled)
        XCTAssertEqual(valorInterruptor(), "1")
    }

    /// Con el gimnasio ya cargado no hay tarjeta, pero el botón de casa sigue en Entreno: dos toques hasta el interruptor.
    func testCasaConGimnasioCargadoQuedaADosToques() {
        lanzar("gimnasioListo")
        esperar("casa-tarjeta")
        noEsta("gimnasio-tarjeta", 2)
        foto("casa-6-boton-con-gimnasio")
        tocar("casa-tarjeta")
        esperar("casa-interruptor")
        XCTAssertEqual(valorInterruptor(), "0")
    }

    /// Entrenando en casa (o con la carga en revisión) el botón no hace falta.
    func testCasaVigenteNoOfreceElBoton() {
        lanzar("casaVigente")
        esperar("recorrido-tarjeta")
        noEsta("casa-tarjeta", 4)
    }

    // MARK: Capturas en oscuro y con letra grande

    func testCapturasOscuro() { oscuro = true; recorrido(); app.terminate(); compras(); app.terminate(); casa(); app.terminate(); casaVigente() }
    func testCapturasLetraGrande() { letraGrande = true; recorrido(); app.terminate(); compras(); app.terminate(); casa(); app.terminate(); casaVigente() }
}
