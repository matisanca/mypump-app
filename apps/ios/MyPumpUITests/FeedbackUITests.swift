import XCTest

/// Feedback del alumno contra el doble del servidor (`-feedbackDePrueba`, sin red): «Me duele» desde el ejercicio y las marcas
/// de «¿Ya lo tenés?» en Suplementación. La decodificación y los reintentos están en el kit.
@MainActor
final class FeedbackUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ escenario: String, pestana: String = "entreno", extra: [String] = []) {
        app = XCUIApplication()
        let token = "tkfeedback" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana, "-feedbackDePrueba", escenario] + extra
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
        // «Hittable» no alcanza: debajo de la barra de avisar o del título el toque cae en la barra. Se lleva al medio.
        let alto = app.windows.firstMatch.frame.height
        var n = 0
        var antes = -CGFloat.infinity
        while n < 12 {
            let y = e(id).frame.midY
            if abs(y - antes) < 1 { break }   // no se mueve: está en una barra fija
            antes = y
            if e(id).isHittable && y > alto * 0.2 && y < alto * 0.72 { break }
            let desde = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y < alto * 0.2 ? 0.4 : 0.6))
            let hasta = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y < alto * 0.2 ? 0.6 : 0.4))
            desde.press(forDuration: 0.05, thenDragTo: hasta)
            n += 1
        }
        e(id).tap()
    }
    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(letraGrande ? "grande" : oscuro ? "oscuro" : "claro")-\(nombre).png")) }
    }

    /// La pestaña aparece cuando llega la suplementación: se entra tocándola.
    private func abrirSuplementacion(_ escenario: String) {
        lanzar(escenario)
        let p = app.pestana("Suplementación")
        XCTAssertTrue(p.waitForExistence(timeout: 20), "No apareció la pestaña Suplementación")
        p.tap()
    }

    private func completarYEnviar(nivel: Int = 5, capturas: Bool = false) {
        esperar("duele-dibujo")
        XCTAssertFalse(e("duele-enviar").isEnabled, "Sin completar no se puede avisar")
        if capturas { foto("duele-1-vacio") }
        tocar("duele-pieza-frente-hombro-derecho")
        esperar("duele-zona")
        XCTAssertEqual(e("duele-zona").label, "Hombro derecho")
        if capturas { foto("duele-2-zona") }
        tocar("duele-desde-esta_semana")
        tocar("duele-cuando-al_subir")
        tocar("duele-tipo-sordo")
        tocar("duele-nivel-\(nivel)")
        if capturas { foto("duele-3-completo") }
        XCTAssertTrue(e("duele-enviar").isEnabled)
        tocar("duele-enviar")
        esperar("duele-recibido")
    }

    func testAvisarUnaMolestiaYCorregirla() {
        lanzar("vacio", extra: ["-abrir", "ejercicio"])
        tocar("duele-abrir")
        completarYEnviar(capturas: true)
        XCTAssertTrue(app.staticTexts["Lo veo y te ajusto el ejercicio."].exists)
        XCTAssertFalse(e("duele-listo-fuerte").exists, "Con «Bastante» no va la línea de dejar el ejercicio")
        foto("duele-4-recibido")
        tocar("duele-listo")
        // En la tarjeta queda avisada y el botón de la fila de acciones se va: se corrige desde ahí.
        esperar("duele-avisada")
        XCTAssertFalse(e("duele-abrir").exists)
        foto("duele-5-tarjeta")
        tocar("duele-cambiar")
        esperar("duele-zona")
        XCTAssertEqual(e("duele-zona").label, "Hombro derecho", "Corregir abre con lo que ya avisó")
        tocar("duele-vista")
        app.segmentedControls.buttons["Espalda"].tap()
        tocar("duele-pieza-espalda-espalda_baja-centro")
        XCTAssertEqual(e("duele-zona").label, "Espalda baja")
        XCTAssertFalse(e("duele-lado-ambos").exists, "Una zona del centro no pregunta el lado")
        tocar("duele-nivel-9")
        tocar("duele-enviar")
        esperar("duele-recibido")
        XCTAssertTrue(e("duele-listo-fuerte").exists)
        tocar("duele-listo")
        esperar("duele-avisada")
        XCTAssertTrue(app.staticTexts["Espalda baja. Lo veo y te ajusto el ejercicio."].exists)
    }

    func testLosDosLados() {
        lanzar("vacio", extra: ["-abrir", "ejercicio"])
        tocar("duele-abrir")
        tocar("duele-pieza-frente-rodilla-izquierdo")
        XCTAssertEqual(e("duele-zona").label, "Rodilla izquierda")
        tocar("duele-lado-ambos")
        XCTAssertEqual(e("duele-zona").label, "Rodilla, los dos lados")
    }

    func testSinPalanca() {
        lanzar("apagado", extra: ["-abrir", "ejercicio"])
        XCTAssertTrue(app.staticTexts["Comentarios"].waitForExistence(timeout: 15))
        XCTAssertFalse(e("duele-abrir").exists, "Con la palanca apagada no hay «Me duele»")
        XCTAssertFalse(e("duele-avisada").exists)
    }

    func testYaRevisada() {
        lanzar("resuelta", extra: ["-abrir", "ejercicio"])
        esperar("duele-resuelta")
        XCTAssertTrue(e("duele-abrir").exists, "Con la anterior cerrada puede avisar otra")
        foto("duele-6-resuelta")
    }

    func testOscuroYLetraGrande() {
        oscuro = true
        lanzar("vacio", extra: ["-abrir", "ejercicio"])
        tocar("duele-abrir")
        completarYEnviar(nivel: 7, capturas: true)
        foto("duele-4-recibido")
        app.terminate()
        oscuro = false; letraGrande = true
        lanzar("vacio", extra: ["-abrir", "ejercicio"])
        tocar("duele-abrir")
        completarYEnviar(capturas: true)
    }

    func testMarcarSuplementos() {
        abrirSuplementacion("vacio")
        tocar("supl-estado-0")
        foto("suple-1-menu")
        app.buttons["Lo compré"].tap()
        XCTAssertTrue(e("supl-estado-0").label.contains("Comprado"), e("supl-estado-0").label)
        XCTAssertEqual(e("supl-estado-resumen").label, "1 de 4 marcados")
        tocar("supl-estado-0")
        app.buttons["Lo estoy tomando"].tap()
        XCTAssertTrue(e("supl-estado-0").label.contains("Lo estás tomando"))
        tocar("supl-estado-1")
        app.buttons["No lo consigo"].tap()
        esperar("supl-estado-no-consigo")
        foto("suple-2-marcado")
        // El protector de la muestra (un fármaco) y lo que sale no se marcan: 4 filas, no 6.
        XCTAssertFalse(e("supl-estado-4").exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'supl-estado' AND label CONTAINS 'Telmisartán'")).firstMatch.exists)
    }

    func testSuplementosYaMarcadosOscuroYSinPalanca() {
        oscuro = true
        abrirSuplementacion("marcado")
        esperar("supl-estado")
        XCTAssertEqual(e("supl-estado-resumen").label, "2 de 4 marcados")
        var n = 0
        while !e("supl-estado-0").isHittable && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
        foto("suple-2-marcado")
        app.terminate()
        oscuro = false
        abrirSuplementacion("apagado")
        XCTAssertTrue(e("supl-momento-desayuno").waitForExistence(timeout: 15))
        XCTAssertFalse(e("supl-estado").exists, "Con la palanca apagada no hay sección")
    }
}
