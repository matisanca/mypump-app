import XCTest

/// «Tu cambio» en Revisión (detrás de `check_guiado`) contra el doble del check guiado (`-checkGuiadoDePrueba`, sin red)
/// con fotos inventadas (`-tuCambio`). Lo fino de la regla está en el kit (`TuCambioVectoresTests`); acá, lo que se ve.
@MainActor
final class TuCambioUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CG_DIR"] }
    private var variante = "claro"

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ fotos: String, palanca: String = "general") {
        app = XCUIApplication()
        let token = "tkcambio" + UUID().uuidString.prefix(10).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", "revision", "-checkGuiadoDePrueba", palanca, "-tuCambio", fotos]
        if variante == "oscuro" { app.launchArguments += ["-mypump-theme", "dark"] }
        if variante == "grande" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] }
        app.launch()
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func esperar(_ id: String, _ t: TimeInterval = 25, file: StaticString = #filePath, line: UInt = #line) {
        if e(id).waitForExistence(timeout: t) { return }
        foto("fallo-\(id)")
        XCTFail("No apareció \(id)", file: file, line: line)
    }
    private func tocar(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        esperar(id, file: file, line: line)
        var n = 0
        while !e(id).isHittable && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
        e(id).tap()
    }
    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(variante)-\(nombre).png")) }
    }
    /// Lleva la tarjeta arriba de la pantalla (para la captura).
    private func verTarjeta() {
        // De a poco (un swipe se pasaba y dejaba el título bajo la barra): el título queda visible, debajo de la barra.
        var n = 0
        while e("tucambio-tarjeta").frame.minY > 300 && n < 12 {
            let desde = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            desde.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
            n += 1
        }
    }

    func testPalancaApagadaEsLaRevisionDeSiempre() {
        lanzar("dos", palanca: "apagado")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ver mis fotos · 2 semanas'")).firstMatch.waitForExistence(timeout: 25))
        XCTAssertFalse(e("tucambio-tarjeta").exists)
        XCTAssertFalse(e("check-guiado-tarjeta").exists)
        XCTAssertTrue(app.staticTexts["El comparador antes/después se abre en 2 semanas más."].exists, "Apagada, el aviso de las 4 semanas sigue")
    }

    func testUnaSemanaMuestraLaFotoYElTextoDeEspera() {
        lanzar("una")
        esperar("tucambio-tarjeta")
        XCTAssertGreaterThan(e("tucambio-tarjeta").frame.minY, e("check-guiado-tarjeta").frame.minY, "Va debajo del check")
        XCTAssertTrue(app.staticTexts["Tu cambio se va a ver acá desde tu segunda semana de fotos"].exists)
        XCTAssertEqual(e("tucambio-antes").label, "Foto de la semana 1")
        XCTAssertFalse(e("tucambio-despues").exists)
        XCTAssertFalse(e("tucambio-pose-frente").exists, "Con una semana no hay nada que elegir")
        XCTAssertFalse(app.buttons["Compartir"].exists)
    }

    func testDosSemanasMuestraElParYAbreElComparador() {
        lanzar("dos")
        esperar("tucambio-tarjeta")
        XCTAssertGreaterThan(e("tucambio-tarjeta").frame.minY, e("check-guiado-tarjeta").frame.minY, "Va debajo del check")
        XCTAssertEqual(e("tucambio-antes").label, "Foto de la semana 1")
        XCTAssertTrue(e("tucambio-despues").label.hasPrefix("Foto de la semana del "), e("tucambio-despues").label)
        XCTAssertTrue(e("tucambio-pie").label.hasPrefix("7 semanas · "), e("tucambio-pie").label)
        XCTAssertTrue(e("tucambio-pose-frente").isSelected)
        tocar("tucambio-pose-perfil")
        XCTAssertTrue(e("tucambio-pose-perfil").isSelected)
        XCTAssertFalse(e("tucambio-pose-frente").isSelected)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'El comparador antes/después se abre'")).firstMatch.exists)
        tocar("tucambio-ver")
        esperar("tucambio-comparador")
        XCTAssertTrue(e("tucambio-pose-perfil").isSelected, "El comparador abre en la pose elegida")
        XCTAssertEqual(e("tucambio-antes").label, "Foto de la semana 1")
        app.buttons["Listo"].firstMatch.tap()
        esperar("tucambio-tarjeta")
    }

    func testConFotosDeInicioLaSemanaUnoEsLaDeInicio() {
        // Sin las de inicio sería una sola semana (espera): el par sale porque la semana 1 es la de inicio.
        lanzar("unaConInicio")
        esperar("tucambio-pie")
        XCTAssertTrue(e("tucambio-pie").label.hasPrefix("7 semanas"), e("tucambio-pie").label)
        XCTAssertEqual(e("tucambio-antes").label, "Foto de la semana 1")
        XCTAssertFalse(app.staticTexts["Tu cambio se va a ver acá desde tu segunda semana de fotos"].exists)
    }

    func testSoloFotosDeInicioEspera() {
        lanzar("soloInicio")
        esperar("tucambio-espera")
        XCTAssertEqual(e("tucambio-antes").label, "Foto de la semana 1")
    }

    func testListoMuestraElParDeFrente() {
        lanzar("dos")
        enviarCheck()
        esperar("cg-listo")
        esperar("cg-listo-tucambio")
        XCTAssertEqual(e("tucambio-antes").label, "Foto de la semana 1")
        XCTAssertTrue(e("cg-listo-pie").label.hasPrefix("7 semanas"))
        tocar("cg-cerrar-listo")
        esperar("tucambio-tarjeta")
    }

    func testListoSinDosSemanasEsElDeSiempre() {
        lanzar("una")
        enviarCheck()
        esperar("cg-listo")
        XCTAssertFalse(e("cg-listo-tucambio").exists)
    }

    private func enviarCheck() {
        tocar("check-guiado-abrir")
        esperar("cg-peso")
        tocar("cg-omitir")                                   // «Hoy no me pesé»
        for (clave, n) in [("energia", 4), ("descanso", 3), ("hambre", 2), ("adherencia", 5)] { tocar("cg-escala-\(clave)-\(n)") }
        tocar("cg-seguir")
        tocar("cg-omitir")                                   // «Las subo después»
        tocar("cg-senal-ninguno")
        tocar("cg-seguir")
        tocar("cg-seguir")                                   // la nota es opcional
        tocar("cg-enviar")
    }

    /// Las capturas en claro, oscuro y letra grande (datos inventados).
    func testCapturas() {
        for v in ["claro", "oscuro", "grande"] {
            variante = v
            lanzar("dos")
            esperar("tucambio-tarjeta")
            verTarjeta(); foto("01-par")
            tocar("tucambio-ver"); esperar("tucambio-comparador"); foto("02-comparador")
            app.buttons["Listo"].firstMatch.tap()
            lanzar("una")
            esperar("tucambio-tarjeta"); verTarjeta(); foto("03-una-semana")
            lanzar("unaConInicio")
            esperar("tucambio-pie"); verTarjeta(); foto("04-con-inicio")
            lanzar("dos")
            enviarCheck(); esperar("cg-listo-tucambio"); foto("05-listo")
        }
    }
}
