import XCTest

/// «Mi salud» (11/11): la tarjeta de Revisión, la pantalla con sus bloques y los destinos viejos, contra los dobles de
/// estudios y de presión (`-miSaludDePrueba <estudios>/<presión>`, sin red y con datos inventados). Que la tarjeta no esté
/// sin ningún bloque lo prueba el kit (`MiSaludTests`): en el iPhone la Recuperación siempre está, como estaba en Revisión.
@MainActor
final class MiSaludUITests: XCTestCase {
    private var app = XCUIApplication()
    /// `TEST_RUNNER_MISALUD_DIR`: dónde dejar las capturas.
    private var dir: String? { ProcessInfo.processInfo.environment["MISALUD_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ caso: String = "completo/serie0", pestana: String = "revision", extra: [String] = []) {
        app = XCUIApplication()
        let token = "tkmisalud" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana, "-miSaludDePrueba", caso] + extra
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func pausa(_ s: TimeInterval = 0.5) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    private func esperar(_ id: String, _ t: TimeInterval = 40) {
        if e(id).waitForExistence(timeout: t) { return }
        foto("fallo-\(id)")
        XCTFail("No apareció \(id)")
    }
    private func foto(_ nombre: String) {
        pausa(0.8)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir {
            let modo = letraGrande ? "letra-grande" : oscuro ? "oscuro" : "claro"
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(modo)-\(nombre).png"))
        }
    }
    private func subir() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        pausa(0.6)
    }
    /// Con letra grande la nota de la semana empuja la tarjeta abajo: para la foto, entera a la vista.
    private func alaVista(_ x: XCUIElement) {
        var n = 0
        while x.frame.maxY > app.frame.maxY - 140 && n < 10 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            pausa(0.5); n += 1
        }
    }
    private func abrirMiSalud() {
        esperar("tarjeta-mi-salud")
        e("tarjeta-mi-salud").tap()
        XCTAssertTrue(app.navigationBars["Mi salud"].waitForExistence(timeout: 10))
    }

    // MARK: Tarjeta y pantalla completa

    private func completa() {
        lanzar()
        esperar("tarjeta-mi-salud")
        // Arriba de todo, sin deslizar, con lo primero pendiente y el número de cosas por hacer (estudios y presión).
        let tarjeta = e("tarjeta-mi-salud")
        let pendiente = NSPredicate(format: "label CONTAINS %@", "Tenés un estudio para hacer")
        expectation(for: pendiente, evaluatedWith: tarjeta)
        waitForExpectations(timeout: 20)
        XCTAssertTrue(tarjeta.isHittable, "se ve sin deslizar")
        XCTAssertTrue(tarjeta.label.contains("2 para hacer"), tarjeta.label)
        XCTAssertGreaterThanOrEqual(tarjeta.frame.height, 88)
        XCTAssertFalse(e("tarjeta-recuperacion-revision").exists, "Recuperación se mudó a Mi salud")
        alaVista(tarjeta)
        foto("1-revision-tarjeta")

        tarjeta.tap()
        XCTAssertTrue(app.navigationBars["Mi salud"].waitForExistence(timeout: 10))
        for b in ["control", "estudios", "presion", "recuperacion"] { esperar("mi-salud-bloque-\(b)") }
        // En orden: control, estudios, presión, recuperación.
        let y = ["control", "estudios", "presion", "recuperacion"].map { e("mi-salud-bloque-\($0)").frame.minY }
        XCTAssertEqual(y, y.sorted(), "orden de los bloques: \(y)")
        XCTAssertTrue(e("estudios-proximo-control").exists)
        XCTAssertTrue(e("estudios-subir").exists)
        XCTAssertTrue(e("tarjeta-presion").exists)
        XCTAssertTrue(e("mi-salud-ver-presion").exists)
        XCTAssertTrue(e("tarjeta-recuperacion-revision").exists)
        // Nunca «tu entrenador», RIR ni avisos de IA.
        for prohibido in ["tu entrenador", "RIR", "inteligencia artificial"] {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", prohibido)).firstMatch.exists, prohibido)
        }
        foto("2-mi-salud-a")
        var n = 0
        while !(e("tarjeta-recuperacion-revision").isHittable && e("tarjeta-recuperacion-revision").frame.maxY < app.frame.maxY - 90) && n < 25 {
            subir(); n += 1
            if n % 3 == 0 { foto("2-mi-salud-\(["b", "c", "d", "e", "f", "g", "h", "i"][min(n / 3 - 1, 7)])") }
        }
        foto("2-mi-salud-fin")
    }

    func testCompletaClaro() { completa() }
    func testCompletaOscuro() { oscuro = true; completa() }
    func testCompletaLetraGrande() { letraGrande = true; completa() }

    /// Con estudios y presión apagados queda un solo bloque (Recuperación): la tarjeta lo dice y no lleva número.
    private func unBloque() {
        lanzar("apagado/apagado")
        esperar("tarjeta-mi-salud")
        pausa(3)
        XCTAssertTrue(e("tarjeta-mi-salud").label.contains("Recuperación"), e("tarjeta-mi-salud").label)
        XCTAssertFalse(e("tarjeta-mi-salud-cuenta").exists)
        alaVista(e("tarjeta-mi-salud"))
        foto("3-revision-un-bloque")
        abrirMiSalud()
        esperar("mi-salud-bloque-recuperacion")
        for b in ["control", "estudios", "presion"] { XCTAssertFalse(e("mi-salud-bloque-\(b)").exists, b) }
        foto("4-mi-salud-un-bloque")
    }

    func testUnBloqueClaro() { unBloque() }
    func testUnBloqueOscuro() { oscuro = true; unBloque() }
    func testUnBloqueLetraGrande() { letraGrande = true; unBloque() }

    // MARK: Un solo lugar

    /// Mis datos ya no tiene Recuperación, Estudios ni Presión: una fila «Mi salud» que lleva ahí.
    func testMisDatosTieneUnaSolaFila() {
        lanzar(extra: ["-abrir", "misdatos"])
        XCTAssertTrue(app.navigationBars["Mis datos"].waitForExistence(timeout: 20))
        esperar("mis-datos-mi-salud")
        for viejo in ["mis-datos-salud", "mis-datos-estudios", "mis-datos-presion"] { XCTAssertFalse(e(viejo).exists, viejo) }
        e("mis-datos-mi-salud").tap()
        XCTAssertTrue(app.navigationBars["Mi salud"].waitForExistence(timeout: 10))
        esperar("mi-salud-bloque-estudios")
        // Atrás vuelve a Mis datos, de donde se entró.
        app.navigationBars["Mi salud"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Mis datos"].waitForExistence(timeout: 10))
    }

    // MARK: Destinos viejos → Mi salud

    func testAvisoDeEstudiosAbreMiSaludEnEstudios() {
        lanzar("novedad/serie0", pestana: "entreno", extra: ["-destinoDePrueba", "estudios"])
        XCTAssertTrue(app.navigationBars["Mi salud"].waitForExistence(timeout: 30))
        let nueva = e("estudios-pendiente-00000002-0000-4000-8000-000000000000")
        XCTAssertTrue(nueva.waitForExistence(timeout: 20))
        pausa(1.5)
        XCTAssertTrue(nueva.isHittable, "la tarjeta nueva queda a la vista")
    }

    func testAvisoDePresionAbrePresionSobreMiSalud() {
        lanzar("completo/pendienteAlta", pestana: "entreno", extra: ["-destinoDePrueba", "presion"])
        esperar("presion-alta", 60)
        XCTAssertTrue(e("mi-salud-bloque-presion").exists, "debajo queda Mi salud")
    }

    func testAvisoDeRecuperacionAbreMiSalud() {
        lanzar(pestana: "entreno", extra: ["-destinoDePrueba", "myday"])
        XCTAssertTrue(app.navigationBars["Mi salud"].waitForExistence(timeout: 30))
        esperar("tarjeta-recuperacion-revision")
        pausa(1.5)
        XCTAssertTrue(e("tarjeta-recuperacion-revision").isHittable, "llega al bloque de recuperación")
    }

    /// Lo que no es salud sigue a donde iba: `progress` abre Salud en Fuerza, sin pasar por Mi salud.
    func testAvisoDeProgresoSigueEnFuerza() {
        lanzar(pestana: "entreno", extra: ["-destinoDePrueba", "progress"])
        let control = app.descendants(matching: .any)["segmento-salud"]
        XCTAssertTrue(control.waitForExistence(timeout: 30))
        XCTAssertTrue(control.buttons["Fuerza"].isSelected)
        XCTAssertFalse(app.navigationBars["Mi salud"].exists)
    }

    /// Las tarjetas de Entreno siguen, solo con algo para hacer, y llevan a Mi salud.
    func testTarjetasDeEntrenoLlevanAMiSalud() {
        lanzar(pestana: "entreno")
        esperar("estudios-tarjeta-inicio-boton")
        e("estudios-tarjeta-inicio-boton").tap()
        XCTAssertTrue(app.navigationBars["Mi salud"].waitForExistence(timeout: 15))
        esperar("estudios-subir-00000001-0000-4000-8000-000000000000")
        app.terminate()

        lanzar(pestana: "entreno")
        esperar("tarjeta-presion-boton")
        e("tarjeta-presion-boton").tap()
        // Presión directo en la toma de hoy, y debajo Mi salud.
        esperar("presion-cuando", 30)
        XCTAssertTrue(e("mi-salud-bloque-presion").exists)
    }
}
