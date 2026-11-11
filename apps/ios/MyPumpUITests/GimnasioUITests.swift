import XCTest

/// Gimnasio por fotos contra el doble del servidor (`-gimnasioDePrueba`, sin red). Lo fino de la cola está en el kit; acá va
/// lo que solo se ve con la pantalla de verdad.
@MainActor
final class GimnasioUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ escenario: String, pestana: String = "entreno", extra: [String] = []) {
        app = XCUIApplication()
        // Un token distinto por prueba: la cola queda en disco y no se mezcla.
        let token = "tkgimnasio" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana, "-gimnasioDePrueba", escenario] + extra
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
    private func tocar(_ id: String) { esperar(id); e(id).tap() }
    /// Sube la pantalla de a poco hasta que el elemento quede lejos del borde de abajo (ahí el toque se lo queda el sistema).
    private func tocarLejosDelBorde(_ id: String) {
        esperar(id)
        var n = 0
        while e(id).frame.maxY > app.frame.maxY - 90 && n < 10 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            n += 1
        }
        e(id).tap()
    }

    /// Para un botón que con letra grande o en pantalla chica puede quedar debajo del borde.
    private func tocarDebajo(_ id: String) { esperar(id); app.swipeUp(velocity: .slow); RunLoop.current.run(until: Date().addingTimeInterval(0.4)); e(id).tap() }
    private func texto(_ s: String) -> XCUIElement { app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(UIDeviceTamano.nombre)-\(letraGrande ? "grande" : oscuro ? "oscuro" : "claro")-\(nombre).png")) }
    }
    private func volver() { app.navigationBars.buttons.element(boundBy: 0).tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }

    private func abrirTarjeta() { tocar("gimnasio-tarjeta") }

    private func recorridoCompleto() {
        lanzar("vacio")
        abrirTarjeta()
        esperar("gimnasio-zona-poleas")
        foto("2-zonas")
        tocar("gimnasio-zona-poleas")
        esperar("gimnasio-consejo")
        tocar("gimnasio-agregar-foto")
        XCTAssertTrue(e("gimnasio-borrar-foto").waitForExistence(timeout: 5))
        foto("3-zona")
        volver()
        for z in ["accesorios_polea", "piernas", "empuje", "tiron", "barras_racks", "discos", "mancuernas", "bancos"] {
            tocarLejosDelBorde("gimnasio-zona-\(z)")
            tocar("gimnasio-no-hay")
            volver()
        }
        tocarDebajo("gimnasio-revisar")
        esperar("gimnasio-nota")
        e("gimnasio-nota").tap()
        e("gimnasio-nota").typeText("Hay una polea rota")
        foto("4-revisar")
        app.swipeUpSiHaceFalta(e("gimnasio-enviar"))
        XCTAssertTrue(e("gimnasio-enviar").isEnabled)
        e("gimnasio-enviar").tap()
        esperar("gimnasio-recibido")
        foto("5-recibido")
    }

    func testEnvioCompleto() { recorridoCompleto() }

    func testFaltanFotos() {
        lanzar("borrador")
        abrirTarjeta()
        esperar("gimnasio-zona-poleas")
        XCTAssertTrue(texto("Te faltan 9 zonas").waitForExistence(timeout: 5))
        tocarDebajo("gimnasio-revisar")
        esperar("gimnasio-faltan")
        XCTAssertFalse(e("gimnasio-enviar").isEnabled)
    }

    func testCorteDeRedAMitadYReanuda() {
        lanzar("corte")
        abrirTarjeta()
        tocar("gimnasio-zona-poleas")
        tocar("gimnasio-agregar-foto")
        tocar("gimnasio-agregar-foto")
        XCTAssertTrue(texto("Esperando señal").waitForExistence(timeout: 8), "Sin el cartel de espera")
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.activate()
        let sigue = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: sigue, evaluatedWith: texto("Esperando señal"))], timeout: 12), .completed, "No reanudó al volver")
    }

    func testReintentoConEspera() {
        lanzar("reintento")
        abrirTarjeta()
        tocar("gimnasio-zona-poleas")
        tocar("gimnasio-agregar-foto")
        XCTAssertTrue(e("gimnasio-borrar-foto").waitForExistence(timeout: 5))
        let sigue = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: sigue, evaluatedWith: texto("Esperando señal"))], timeout: 12), .completed, "No se reintentó")
    }

    func testFotoRechazada() {
        lanzar("rechazo")
        abrirTarjeta()
        tocar("gimnasio-zona-poleas")
        tocar("gimnasio-agregar-foto")
        esperar("gimnasio-aviso-foto")
        XCTAssertFalse(e("gimnasio-borrar-foto").exists, "La foto rechazada no tiene que quedar")
    }

    func testPalancaApagadaNoSeVe() {
        lanzar("apagado")
        XCTAssertTrue(app.pestana("Entreno").waitForExistence(timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertFalse(e("gimnasio-tarjeta").exists)
    }

    func testSinElServidorNuevoNoSeVe() {
        lanzar("sinServidor")
        XCTAssertTrue(app.pestana("Entreno").waitForExistence(timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertFalse(e("gimnasio-tarjeta").exists)
    }

    func testTarjetaSinRutina() {
        lanzar("vacio", extra: ["-gimnasioSinRutina", "YES"])
        esperar("gimnasio-tarjeta")
        foto("0-tarjeta-sin-rutina")
    }

    private func preguntas() {
        lanzar("preguntas")
        abrirTarjeta()
        esperar("gimnasio-numero-pregunta")
        XCTAssertTrue(texto("Necesitamos 1 foto más").exists)
        foto("6-pregunta-elegir")
        tocar("gimnasio-opcion-remo_t")
        tocar("gimnasio-siguiente")
        tocar("gimnasio-opcion-barra_v")
        tocar("gimnasio-siguiente")
        tocar("gimnasio-opcion-2.5")
        tocar("gimnasio-siguiente")
        esperar("gimnasio-kilos")
        foto("7-pregunta-numero")
        e("gimnasio-kilos").tap()
        e("gimnasio-kilos").typeText("50")
        app.toolbars.buttons["Listo"].firstMatch.tap()
        tocar("gimnasio-siguiente")
        tocar("gimnasio-pec_deck-si")
        foto("8-pregunta-confirmar")
        tocar("gimnasio-press_inclinado-no_se")
        tocar("gimnasio-siguiente")
        tocar("gimnasio-agregar-foto")
        foto("9-pregunta-foto")
        tocar("gimnasio-enviar-respuestas")
        esperar("gimnasio-recibido")
    }

    func testPreguntas() { preguntas() }

    /// Una vez cargado no hay tarjeta: se entra desde Mis datos y dice «Adaptado por Mati».
    func testListoEnMisDatos() {
        lanzar("listo")
        abrirMiGimnasio()
        esperar("gimnasio-resultado")
        XCTAssertTrue(texto("Adaptado por Mati el 12/11").exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "inteligencia")).firstMatch.exists)
        XCTAssertTrue(texto("Cruce de poleas").exists)
        foto("listo")
        app.swipeUpSiHaceFalta(e("gimnasio-cambie"))
        esperar("gimnasio-falta-algo")
        esperar("gimnasio-cambie")
        tocar("gimnasio-ya-no-esta")
        esperar("gimnasio-enviar-quitar")
        foto("ya-no-esta")
    }

    func testListoSinCambios() {
        lanzar("listoSinCambios")
        abrirMiGimnasio()
        esperar("gimnasio-resultado")
        XCTAssertTrue(texto("Mati revisó tu gimnasio y tu rutina encaja tal cual").exists)
    }

    private func abrirMiGimnasio() {
        XCTAssertFalse(e("gimnasio-tarjeta").waitForExistence(timeout: 4), "Con el gimnasio cargado no va la tarjeta")
        // Simplificar (11/11): ya no está en Mis datos; está en «Mi gimnasio y mi técnica», al final de Entreno.
        app.abrirDondeEntreno()
        tocar("donde-entreno-gimnasio")
    }

    func testEnProcesoSinHoras() {
        lanzar("enProceso")
        abrirTarjeta()
        esperar("gimnasio-recibido")
    }

    /// Con una ronda de preguntas abierta sale la tarjeta: si no, nadie contesta.
    func testPreguntasMuestranLaTarjeta() {
        lanzar("preguntas")
        esperar("gimnasio-tarjeta")
    }

    /// Las capturas: claro y oscuro, con letra grande en el oscuro.
    func testCapturasOscuro() { oscuro = true; recorridoCompleto(); preguntas() }
    func testCapturasLetraGrande() { letraGrande = true; recorridoCompleto() }
}

private enum UIDeviceTamano {
    static var nombre: String { "\(Int(XCUIScreen.main.screenshot().image.size.width))" }
}

private extension XCUIApplication {
    func swipeUpSiHaceFalta(_ e: XCUIElement) {
        var n = 0
        while !(e.exists && e.isHittable) && n < 8 { swipeUp(velocity: .slow); n += 1 }
    }
}
