import XCTest

/// Las fotos de inicio contra el doble del servidor (`-fotosInicioDePrueba`, sin red). Lo fino de la cola y del control de
/// calidad está en el kit; acá va lo que solo se ve con la pantalla de verdad.
@MainActor
final class FotosInicioUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ escenario: String, foto: String = "buena", pestana: String = "revision", extra: [String] = []) {
        app = XCUIApplication()
        // Un token distinto por prueba: la cola queda en disco y no se mezcla.
        let token = "tkfotosinicio" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana, "-fotosInicioDePrueba", escenario, "-fotosInicioFoto", foto] + extra
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
    /// Lo trae a la vista (con letra grande casi todo queda debajo del borde) y lo toca.
    private func tocar(_ id: String) {
        esperar(id)
        var n = 0
        while (!e(id).isHittable || e(id).frame.maxY > app.frame.maxY - 60) && n < 12 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            n += 1
        }
        e(id).tap()
    }
    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(letraGrande ? "grande" : oscuro ? "oscuro" : "claro")-\(nombre).png")) }
    }
    private func volver() { app.navigationBars.buttons.element(boundBy: 0).tap(); RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
    private func valor(_ id: String) -> String { e(id).value as? String ?? "" }
    private func esperarValor(_ id: String, _ v: String, _ t: TimeInterval = 15) {
        let limite = Date().addingTimeInterval(t)
        while valor(id) != v && Date() < limite { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertEqual(valor(id), v, id)
    }

    /// Las tres poses de corrido: cada «Usar esta foto» lleva a la que falta, y al terminar Mati ya las tiene.
    private func recorrido() {
        lanzar("vacio")
        esperar("fotos-inicio-tarjeta")
        foto("1-tarjeta")
        // Un toque en la tarjeta y ya está la pose que falta; el segundo es la foto. Atrás queda el resumen.
        tocar("fotos-inicio-tarjeta")
        esperar("fotos-inicio-instruccion")
        XCTAssertTrue(app.navigationBars["De frente"].exists)
        foto("3-pose-frente")
        volver()
        esperar("fotos-inicio-pose-frente")
        XCTAssertEqual(valor("fotos-inicio-pose-frente"), "Falta")
        XCTAssertTrue(e("fotos-inicio-privacidad").exists)
        foto("2-resumen")
        tocar("fotos-inicio-pose-frente")
        tocar("fotos-inicio-foto")
        esperar("fotos-inicio-bien")
        foto("4-revisar-bien")
        tocar("fotos-inicio-usar")
        // Sigue sola con la de perfil y la de espalda.
        esperar("fotos-inicio-instruccion")
        XCTAssertTrue(app.navigationBars["De perfil"].waitForExistence(timeout: 5))
        foto("5-pose-perfil")
        tocar("fotos-inicio-foto")
        tocar("fotos-inicio-usar")
        XCTAssertTrue(app.navigationBars["De espalda"].waitForExistence(timeout: 5))
        foto("6-pose-espalda")
        tocar("fotos-inicio-foto")
        tocar("fotos-inicio-usar")
        esperar("fotos-inicio-listas")
        esperarValor("fotos-inicio-pose-espalda", "Lista")
        foto("7-listas")
        // El físico que te motiva: una foto y la nota.
        tocar("fotos-inicio-motivacion-agregar")
        tocar("fotos-inicio-usar")
        esperar("fotos-inicio-motivacion-foto")
        tocar("fotos-inicio-nota")
        e("fotos-inicio-nota").typeText("Los hombros y la cintura")
        e("fotos-inicio-teclado-listo").tap()   // el botón grande con texto que baja el teclado
        tocar("fotos-inicio-nota-guardar")
        esperar("fotos-inicio-nota-resultado")
        XCTAssertEqual(e("fotos-inicio-nota-resultado").label, "Nota guardada")
        foto("8-motivacion")
        tocar("fotos-inicio-listo")
        esperar("fotos-inicio-tarjeta")
        XCTAssertTrue(e("fotos-inicio-tarjeta").label.contains("Mati ya las tiene"))
        foto("9-tarjeta-lista")
    }

    func testRecorridoCompleto() { recorrido() }
    func testRecorridoOscuro() { oscuro = true; recorrido() }
    func testRecorridoLetraGrande() { letraGrande = true; recorrido() }

    /// Una foto oscura avisa y deja elegir: sacar otra o usarla igual.
    private func oscura() {
        lanzar("vacio", foto: "oscura")
        tocar("fotos-inicio-tarjeta")
        tocar("fotos-inicio-foto")
        esperar("fotos-inicio-problema-oscura")
        XCTAssertFalse(e("fotos-inicio-usar").exists)
        XCTAssertTrue(e("fotos-inicio-otra").exists)
        foto("calidad-oscura")
        tocar("fotos-inicio-usar-igual")
        XCTAssertTrue(app.navigationBars["De perfil"].waitForExistence(timeout: 5))
    }
    func testFotoOscuraAvisaYDejaUsarIgual() { oscura() }
    func testFotoOscuraOscuro() { oscuro = true; oscura() }
    func testFotoOscuraLetraGrande() { letraGrande = true; oscura() }

    func testFotoMovidaAvisa() {
        lanzar("vacio", foto: "movida")
        tocar("fotos-inicio-tarjeta")
        volver()
        tocar("fotos-inicio-pose-perfil")
        tocar("fotos-inicio-foto")
        esperar("fotos-inicio-problema-movida")
        XCTAssertTrue(e("fotos-inicio-usar-igual").exists)
        foto("calidad-movida")
    }

    /// Con poca resolución no hay «Usar igual»: solo sacar otra.
    func testFotoChicaNoSePuedeUsar() {
        lanzar("vacio", foto: "chica")
        tocar("fotos-inicio-tarjeta")
        volver()
        tocar("fotos-inicio-pose-espalda")
        tocar("fotos-inicio-foto")
        esperar("fotos-inicio-problema-chica")
        XCTAssertFalse(e("fotos-inicio-usar").exists)
        XCTAssertFalse(e("fotos-inicio-usar-igual").exists)
        XCTAssertTrue(e("fotos-inicio-otra").exists)
        foto("calidad-chica")
    }

    /// Faltando una, la tarjeta dice «Seguir» y se puede repetir una que ya está.
    func testFaltaUnaYRepetir() {
        lanzar("dos")
        esperar("fotos-inicio-tarjeta")
        XCTAssertTrue(e("fotos-inicio-tarjeta").label.contains("2 de 3"))
        tocar("fotos-inicio-tarjeta")
        XCTAssertTrue(app.navigationBars["De espalda"].waitForExistence(timeout: 5), "abre en la que falta")
        volver()
        esperar("fotos-inicio-faltan")
        XCTAssertEqual(e("fotos-inicio-faltan").label, "Te falta 1 foto")
        XCTAssertEqual(valor("fotos-inicio-pose-frente"), "Lista")
        XCTAssertEqual(valor("fotos-inicio-pose-espalda"), "Falta")
        foto("falta-una")
        tocar("fotos-inicio-pose-frente")
        tocar("fotos-inicio-foto")
        tocar("fotos-inicio-usar")
        // Después de repetir el frente sigue con la que falta.
        XCTAssertTrue(app.navigationBars["De espalda"].waitForExistence(timeout: 5))
    }

    /// El servidor no recibe la foto (4xx): se avisa y la pose vuelve a faltar.
    func testFotoRechazadaAvisa() {
        lanzar("rechazo")
        tocar("fotos-inicio-tarjeta")
        volver()
        tocar("fotos-inicio-pose-espalda")
        tocar("fotos-inicio-foto")
        tocar("fotos-inicio-usar")
        volver()
        esperar("fotos-inicio-aviso")
        esperarValor("fotos-inicio-pose-espalda", "Falta")
        foto("rechazada")
    }

    func testTopeDeMotivacion() {
        lanzar("topeMotivacion")
        tocar("fotos-inicio-tarjeta")
        volver()
        esperar("fotos-inicio-motivacion-tope")
        XCTAssertFalse(e("fotos-inicio-motivacion-agregar").exists)
        foto("motivacion-tope")
    }

    /// Completo: la entrada de Mis datos sigue ahí para repetir, con la nota que había.
    func testEntradaEnMisDatos() {
        lanzar("completo")
        XCTAssertTrue(app.buttons["Mis datos"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Mis datos"].firstMatch.tap()
        tocar("mis-datos-fotos-inicio")
        esperar("fotos-inicio-listas")
        XCTAssertEqual(e("fotos-inicio-nota").value as? String, "Los hombros")
        foto("mis-datos-completo")
    }

    /// Lo primero que se ve al abrir la app (Entreno): la tarjeta, mientras falte alguna.
    func testTarjetaEnEntreno() {
        lanzar("vacio", pestana: "entreno")
        esperar("fotos-inicio-tarjeta")
        foto("entreno-tarjeta")
        tocar("fotos-inicio-tarjeta")
        esperar("fotos-inicio-foto")
        app.terminate()
        lanzar("completo", pestana: "entreno")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertFalse(e("fotos-inicio-tarjeta").exists, "con las tres, en Entreno ya no está")
    }

    /// Apagado, sin el servidor nuevo o sin pedido: la app es la de siempre.
    func testApagadoNoSeVeNada() {
        for escenario in ["apagado", "sinServidor", "noHabilitado"] {
            lanzar(escenario)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            XCTAssertFalse(e("fotos-inicio-tarjeta").exists, escenario)
            app.terminate()
        }
    }
}
