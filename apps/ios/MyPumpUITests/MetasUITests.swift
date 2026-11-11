import XCTest

/// «Pump del día» (2.3.0) con la muestra (`-metas muestra`, sin cuenta ni datos de nadie). Con `METAS_CAPTURAS=<carpeta>`
/// en el entorno del runner deja `ios-<nombre>.png`.
@MainActor
final class MetasUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws { continueAfterFailure = false }

    private func abrir(_ extra: [String], pestana: String = "entreno") {
        app.terminate()
        app.launchArguments = ["-bocetos", "YES", "-guiaBienvenida", "no", "-sinOnboarding", "YES", "-pestana", pestana] + extra
        app.launch()
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func captura(_ nombre: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = nombre; a.lifetime = .keepAlways; add(a)
        guard let dir = ProcessInfo.processInfo.environment["METAS_CAPTURAS"], !dir.isEmpty else { return }
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ios-\(nombre).png"))
    }

    private func traer(_ e: XCUIElement) {
        for _ in 0..<8 where !(e.exists && e.isHittable && e.frame.maxY < app.frame.height - 110) { app.swipeUp(velocity: .slow) }
    }

    /// Sin la muestra (que hace las veces de la palanca prendida y la meta), no aparece nada nuevo.
    func testSinMetaNoHayPumpNiRitmo() {
        abrir([])
        XCTAssertTrue(app.tabBars.buttons["Entreno"].waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertFalse(el("pump-del-dia").exists)
        XCTAssertFalse(el("pump-celebracion").exists)
    }

    /// La tarjeta con los pasos y la racha; al llegar, la celebración una sola vez, aunque la app vaya y vuelva.
    func testCelebraUnaSolaVezPorDia() {
        abrir(["-metas", "muestra", "-pasos", "7420"])
        var tarjeta = el("pump-del-dia")
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 20))
        XCTAssertTrue(tarjeta.label.contains("7.420 de 10.000 pasos"), tarjeta.label)
        XCTAssertTrue(tarjeta.label.contains("Te faltan 2.580 pasos"), tarjeta.label)
        XCTAssertTrue(tarjeta.label.contains("3 días seguidos"), tarjeta.label)
        captura("metas-tarjeta")
        sleep(2)
        XCTAssertFalse(el("pump-celebracion").exists, "Celebró sin llegar")
        abrir(["-metas", "muestra", "-pasos", "9100", "-pasosLuego", "10240"])
        tarjeta = el("pump-del-dia")
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 20))
        let seguir = el("pump-seguir")
        XCTAssertTrue(seguir.waitForExistence(timeout: 30), "No llegó la celebración")
        XCTAssertTrue(app.staticTexts["Pump lleno"].exists)
        XCTAssertTrue(app.staticTexts["Llegaste a tus 10.000 pasos de hoy"].exists)
        sleep(2)
        captura("metas-celebracion")
        seguir.tap()
        XCTAssertTrue(el("pump-celebracion").waitForNonExistence(timeout: 5))
        XCTAssertTrue(el("pump-del-dia").label.contains("Llegaste a tus pasos de hoy"))
        // Segundo plano y vuelta: no se repite.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(el("pump-del-dia").waitForExistence(timeout: 10))
        sleep(3)
        XCTAssertFalse(el("pump-celebracion").exists, "Se celebró dos veces el mismo día")
    }

    /// Sin Salud: la meta y el botón para conectar, sin torso lleno ni celebración.
    func testSinSaludMuestraLaMetaYConectar() {
        abrir(["-metas", "sinsalud"])
        XCTAssertTrue(el("pump-conectar").waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Tu meta es de 10.000 pasos por día"].exists)
        sleep(2)
        XCTAssertFalse(el("pump-celebracion").exists)
    }

    /// Con letra de accesibilidad: todo dentro del ancho, sin cortar el número.
    func testLetraGrande() {
        abrir(["-metas", "muestra", "-pasos", "7420", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        let tarjeta = el("pump-del-dia")
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 20))
        traer(tarjeta)
        XCTAssertLessThanOrEqual(tarjeta.frame.maxX, app.frame.width + 0.5)
        XCTAssertGreaterThanOrEqual(tarjeta.frame.minX, -0.5)
        captura("metas-letra-ax")
    }

    /// El ritmo de peso en Cuerpo, con la muestra.
    func testRitmoEnCuerpo() {
        abrir(["-metas", "muestra", "-segmento", "cuerpo"], pestana: "salud")
        let ritmo = el("ritmo-peso")
        XCTAssertTrue(ritmo.waitForExistence(timeout: 20))
        XCTAssertTrue(ritmo.label.contains("Buscamos bajar medio kilo por semana"), ritmo.label)
    }
}
