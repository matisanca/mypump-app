import XCTest

/// «Tu próximo control de salud» (`controles_app`) contra el doble del servidor (`-estudiosDePrueba`, sin red y con datos
/// inventados; hoy = 10/11): palanca apagada, sin control, control lejano y control dentro de la ventana de aviso.
@MainActor
final class ControlesUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ escenario: String, pestana: String = "entreno") {
        app = XCUIApplication()
        let token = "tkcontroles" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana, "-estudiosDePrueba", escenario]
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
    private func conEtiqueta(_ s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }
    private func foto(_ nombre: String) {
        pausa(0.7)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(letraGrande ? "letra-grande" : oscuro ? "oscuro" : "claro")-ios-\(nombre).png")) }
    }
    /// Sube de a poco hasta que se pueda tocar y no quede pegado al borde de abajo.
    private func traer(_ id: String) {
        var b = 0
        while !e(id).waitForExistence(timeout: b == 0 ? 6 : 1) && b < 12 { arrastrar(); b += 1 }
        esperar(id)
        var n = 0
        while (!e(id).isHittable || e(id).frame.maxY > app.frame.maxY - 90) && n < 25 { arrastrar(0.25); n += 1 }
        pausa(0.8)
    }
    private func arrastrar(_ cuanto: CGFloat = 0.5) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75 - cuanto)))
        pausa(0.3)
    }
    private func abrirEstudios() {
        // «Mi salud» (11/11) está arriba de todo en la pestaña Revisión.
        let revision = app.tabBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Revisi")).firstMatch
        XCTAssertTrue(revision.waitForExistence(timeout: 20))
        revision.tap()
        esperar("tarjeta-mi-salud")
        e("tarjeta-mi-salud").tap()
        esperar("estudios-subir")
    }

    // MARK: Palanca apagada y sin control: nada nuevo

    func testPalancaApagadaNoMuestraNada() {
        lanzar("controlesApagado")
        // Simplificar (11/11): una sola tarjeta «Mi salud» arriba de Entreno; con estudios pendientes y sin control, una sola cosa.
        esperar("tarjeta-mi-salud-inicio-boton")
        pausa(2)
        XCTAssertTrue(e("tarjeta-mi-salud-inicio-texto").label.contains("1 para hacer"), e("tarjeta-mi-salud-inicio-texto").label)
        XCTAssertFalse(conEtiqueta("Tu próximo control de salud").exists)
        XCTAssertFalse(conEtiqueta("Ver mis estudios").exists)
        abrirEstudios()
        esperar("estudios-proximo-control")
        // El bloque queda como siempre, con lo de Estudios.
        XCTAssertTrue(conEtiqueta("Semana del 23/11").exists)
        XCTAssertFalse(conEtiqueta("Te vamos a mandar las órdenes").exists)
    }

    func testSinControlNoMuestraNada() {
        lanzar("sinControl")
        esperar("tarjeta-mi-salud-inicio-boton")
        pausa(2)
        XCTAssertTrue(e("tarjeta-mi-salud-inicio-texto").label.contains("1 para hacer"), e("tarjeta-mi-salud-inicio-texto").label)
        XCTAssertFalse(conEtiqueta("Tu próximo control de salud").exists)
        abrirEstudios()
        esperar("estudios-proximo-control")
        XCTAssertTrue(conEtiqueta("Semana del 23/11").exists)
        XCTAssertFalse(conEtiqueta("Control de salud").exists)
    }

    // MARK: Control lejano: solo en Estudios

    private func lejano() {
        lanzar("controlLejano")
        esperar("tarjeta-mi-salud-inicio-boton")
        pausa(2)
        XCTAssertTrue(e("tarjeta-mi-salud-inicio-texto").label.contains("1 para hacer"), "falta para avisar: no va arriba")
        XCTAssertFalse(conEtiqueta("Tu próximo control de salud").exists)
        abrirEstudios()
        esperar("estudios-proximo-control")
        XCTAssertTrue(conEtiqueta("Control de salud").exists)
        XCTAssertTrue(conEtiqueta("El miércoles 30/12").exists)
        XCTAssertTrue(conEtiqueta("Te vamos a mandar las órdenes unos días antes.").exists)
        XCTAssertFalse(conEtiqueta("Semana del 23/11").exists, "un solo próximo control")
        for _ in 0..<3 { app.swipeDown(); pausa(0.3) }
        foto("controles-1-estudios-lejano")
    }

    func testControlLejanoSoloEnEstudios() { lejano() }

    // MARK: Dentro de la ventana: arriba de todo y un toque a Estudios

    private func enVentana() {
        lanzar("controlEnVentana")
        // Simplificar (11/11): el control cuenta en la tarjeta única «Mi salud» de arriba de Entreno.
        esperar("tarjeta-mi-salud-inicio-boton")
        let texto = e("tarjeta-mi-salud-inicio-texto").label
        XCTAssertTrue(texto.contains("Tu próximo control de salud") || conEtiqueta("Y 1 cosa más").exists, texto)
        let boton = e("tarjeta-mi-salud-inicio-boton")
        // Lleva al bloque «Próximo control»: «Ver mi control».
        if texto.contains("Tu próximo control de salud") { XCTAssertTrue(boton.label.hasPrefix("Ver mi control"), boton.label) }
        traer("tarjeta-mi-salud-inicio-boton")
        XCTAssertGreaterThanOrEqual(boton.frame.height, 44)
        XCTAssertGreaterThan(boton.frame.width, app.frame.width * 0.6, "botón de ancho completo")
        foto("controles-2-inicio")
        boton.tap()
        // Un toque: directo a Mi salud, con el bloque «Próximo control» arriba y Estudios debajo.
        esperar("estudios-proximo-control", 15)
        XCTAssertTrue(e("estudios-subir").exists)
        XCTAssertTrue(conEtiqueta("El lunes 16/11").exists)
        // El bloque «Próximo control» queda arriba de la lista: la foto, desde el principio.
        for _ in 0..<3 { app.swipeDown(); pausa(0.3) }
        foto("controles-3-estudios")
    }

    func testControlEnVentanaVaArribaYLlevaAEstudios() { enVentana() }
    func testCapturasOscuro() { oscuro = true; enVentana(); lejano() }
    func testCapturasLetraGrande() { letraGrande = true; enVentana() }
    func testCapturasClaro() { enVentana(); lejano() }

    func testOrdenesEnviadasNoVaArriba() {
        lanzar("controlOrdenes")
        esperar("tarjeta-mi-salud-inicio-boton")
        pausa(2)
        XCTAssertTrue(e("tarjeta-mi-salud-inicio-texto").label.contains("1 para hacer"), e("tarjeta-mi-salud-inicio-texto").label)
        XCTAssertFalse(conEtiqueta("Tu próximo control de salud").exists)
        abrirEstudios()
        esperar("estudios-proximo-control")
        XCTAssertTrue(conEtiqueta("Ya te mandamos las órdenes").exists)
    }
}
