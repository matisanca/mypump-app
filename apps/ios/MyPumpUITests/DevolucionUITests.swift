import XCTest

/// «Devolución de Mati» en Revisión contra el doble del servidor (`-devolucionDePrueba`, sin red). Lo fino (qué llega, qué se
/// guarda, palanca) está en el kit; acá va lo que solo se ve con la pantalla de verdad, en claro, oscuro y letra grande.
@MainActor
final class DevolucionUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["DEVOLUCION_DIR"] }

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ escenario: String, oscuro: Bool = false, letraGrande: Bool = false) {
        app = XCUIApplication()
        let token = "tkdevolucion" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", "revision", "-devolucionDePrueba", escenario]
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] }
        app.launch()
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(nombre).png")) }
    }

    func testArribaDeTodoConHistorial() {
        lanzar("dos")
        XCTAssertTrue(e("devolucion-tarjeta").waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["Devolución de Mati"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Semana del'")).firstMatch.exists)
        XCTAssertTrue(e("devolucion-nueva").exists)
        XCTAssertTrue(e("devolucion-texto").label.contains("enfocate en llegar a los pasos"))
        // Arriba de todo: antes que Recuperación.
        let rec = e("tarjeta-recuperacion-revision")
        if rec.exists { XCTAssertLessThan(e("devolucion-tarjeta").frame.minY, rec.frame.minY) }
        // Nunca un aviso de IA ni un tercero.
        for prohibido in ["IA", "inteligencia", "tu coach", "tu entrenador", "automático"] {
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", prohibido)).firstMatch.exists, prohibido)
        }
        foto("claro-dos")
        XCTAssertTrue(e("devolucion-historial").exists)
        e("devolucion-anterior-d2").tap()
        XCTAssertTrue(app.staticTexts["para esta sumale una fruta a la merienda"].waitForExistence(timeout: 3))
        foto("claro-historial-abierto")
    }

    func testOscuro() {
        lanzar("dos", oscuro: true)
        XCTAssertTrue(e("devolucion-tarjeta").waitForExistence(timeout: 60))
        foto("oscuro-dos")
    }

    func testLetraGrande() {
        lanzar("una", letraGrande: true)
        XCTAssertTrue(e("devolucion-tarjeta").waitForExistence(timeout: 60))
        XCTAssertFalse(e("devolucion-historial").exists)
        foto("grande-una")
    }

    func testSinDevolucionNoHayNada() {
        for caso in ["vacio", "apagado", "noHabilitado", "sinServidor"] {
            lanzar(caso)
            XCTAssertTrue(app.navigationBars["Revisión"].waitForExistence(timeout: 60), caso)
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            XCTAssertFalse(e("devolucion-tarjeta").exists, caso)
            XCTAssertFalse(app.staticTexts["Devolución de Mati"].exists, caso)
            if caso == "vacio" { foto("claro-sin-devolucion") }
        }
    }
}
