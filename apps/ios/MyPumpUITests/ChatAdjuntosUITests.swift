import XCTest

/// Fotos y audios en el chat (2.3.0) con el chat de mentira (`-chatAdjuntosDePrueba YES`): sin cuenta, sin red y sin
/// tocar la base. Deja las capturas en claro y oscuro en `CHAT_CAPTURAS` si está.
@MainActor
final class ChatAdjuntosUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CHAT_CAPTURAS"] }

    private func abrir(oscuro: Bool = false, letraGrande: Bool = false, extra: [String] = []) {
        continueAfterFailure = false
        app.launchArguments = ["-bocetos", "YES", "-sinOnboarding", "YES", "-pestana", "chat", "-chatAdjuntosDePrueba", "YES"] + extra
        if oscuro { app.launchArguments += ["-mypump-theme", "dark", "-AppleInterfaceStyle", "Dark"] }
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] }
        app.launch()
    }

    private func captura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(nombre).png")) }
    }

    private func esperarHilo() {
        XCTAssertTrue(app.descendants(matching: .any)["chat-audio"].firstMatch.waitForExistence(timeout: 20), "no apareció el audio")
        XCTAssertTrue(app.descendants(matching: .any)["chat-foto"].firstMatch.waitForExistence(timeout: 5), "no apareció la foto")
        // Que termine de bajar la foto (la miniatura reemplaza al cargando).
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
    }

    func testSeVenLaFotoElAudioYLoQueYaNoEsta() throws {
        abrir()
        esperarHilo()
        XCTAssertTrue(app.descendants(matching: .any)["chat-adjunto-no-disponible"].exists, "no dice que ya no está disponible")
        XCTAssertTrue(app.descendants(matching: .any)["chat-microfono"].exists, "no está el micrófono")
        XCTAssertTrue(app.descendants(matching: .any)["chat-foto-boton"].exists, "no está el botón de la foto")
        // Ningún texto de la pantalla habla de lo que pasa después con el archivo.
        for t in app.staticTexts.allElementsBoundByIndex.map(\.label) {
            let l = t.lowercased()
            XCTAssertFalse(l.contains("transcrib") || l.contains("inteligencia") || l.contains(" ia ") || l.contains("automátic"), "«\(t)»")
        }
        captura("chat-adjuntos-claro")
    }

    func testCapturaOscuro() throws {
        abrir(oscuro: true)
        esperarHilo()
        captura("chat-adjuntos-oscuro")
    }

    func testCapturaLetraGrande() throws {
        abrir(letraGrande: true)
        esperarHilo()
        captura("chat-adjuntos-letra-grande")
    }

    func testElAudioSeEscuchaYSePausa() throws {
        abrir()
        esperarHilo()
        let play = app.buttons["chat-audio-play"].firstMatch
        XCTAssertEqual(play.label, "Escuchar")
        play.tap()
        let pausar = app.buttons["Pausar"].firstMatch
        XCTAssertTrue(pausar.waitForExistence(timeout: 8), "no empezó a sonar")
        captura("chat-adjuntos-sonando")
        pausar.tap()
        XCTAssertTrue(app.buttons["Escuchar"].firstMatch.waitForExistence(timeout: 3))
    }

    func testLaFotoSeVeGrandeYSeCierra() throws {
        abrir()
        esperarHilo()
        app.descendants(matching: .any)["chat-foto"].firstMatch.tap()
        let cerrar = app.buttons["chat-visor-cerrar"]
        XCTAssertTrue(cerrar.waitForExistence(timeout: 5), "no se abrió la foto grande")
        captura("chat-adjuntos-visor")
        cerrar.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chat-microfono"].waitForExistence(timeout: 5))
    }

    /// Mantener apretado graba; al soltar sale con «enviando…» y después queda como un audio más.
    func testGrabarManteniendoApretadoYSoltar() throws {
        abrir()
        esperarHilo()
        let antes = app.descendants(matching: .any).matching(identifier: "chat-audio").count
        let mic = app.descendants(matching: .any)["chat-microfono"]
        mic.press(forDuration: 2.6)
        let ahora = app.descendants(matching: .any).matching(identifier: "chat-audio")
        let limite = Date().addingTimeInterval(8)
        while ahora.count <= antes && Date() < limite { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertEqual(ahora.count, antes + 1, "el audio no apareció en el hilo")
        captura("chat-adjuntos-audio-enviando")
    }

    /// Deslizando a la izquierda mientras graba, al soltar no sale nada.
    func testDeslizarCancela() throws {
        abrir()
        esperarHilo()
        let antes = app.descendants(matching: .any).matching(identifier: "chat-audio").count
        let mic = app.descendants(matching: .any)["chat-microfono"]
        let desde = mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        desde.press(forDuration: 1.5, thenDragTo: desde.withOffset(CGVector(dx: -200, dy: 0)))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat-audio").count, antes, "salió un audio cancelado")
    }

    /// Mientras se mantiene apretado se ve la barra con el tiempo y «Deslizá para cancelar».
    func testCapturaGrabando() throws {
        abrir()
        esperarHilo()
        let mic = app.descendants(matching: .any)["chat-microfono"]
        let desde = mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Mantiene y se mueve apenas (sin cancelar): la captura sale en el medio con la barra a la vista.
        let exp = expectation(description: "captura")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            MainActor.assumeIsolated { self?.captura("chat-adjuntos-grabando") }
            exp.fulfill()
        }
        desde.press(forDuration: 3.5, thenDragTo: desde.withOffset(CGVector(dx: -10, dy: 0)))
        wait(for: [exp], timeout: 10)
    }

    /// El tope del día: no se reintenta solo, la burbuja dice por qué y ofrece Reintentar y Borrar.
    func testElTopeDelDiaSeDiceEnLaBurbuja() throws {
        abrir(extra: ["-chatAdjuntosConFallo", "YES"])
        esperarHilo()
        let borrar = app.buttons["chat-adjunto-borrar"]
        XCTAssertTrue(borrar.waitForExistence(timeout: 15), "no apareció el «no salió»")
        XCTAssertTrue(app.buttons["chat-reintentar"].exists)
        XCTAssertTrue(app.staticTexts["Por hoy llegaste al máximo de fotos y audios. Probá mañana."].exists)
        captura("chat-adjuntos-no-salio")
        borrar.tap()
        XCTAssertTrue(borrar.waitForNonExistence(timeout: 5), "Borrar no lo sacó")
    }
}
