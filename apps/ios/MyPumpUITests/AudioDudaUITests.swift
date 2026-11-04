import XCTest

/// Las dudas en audio de «Tu guía», con la guía de muestra, el micrófono de mentira (`-audioDoble YES`) y, cuando hace
/// falta, la 019 simulada (`-audioServidor YES`): nunca toca la base. Con `AUDIO_CAPTURAS=<carpeta>` en el entorno del
/// runner (`TEST_RUNNER_AUDIO_CAPTURAS`), deja las capturas `ios-audio-*.png` ahí.
@MainActor
final class AudioDudaUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws { continueAfterFailure = false }

    private func abrir(_ extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-bocetos", "YES", "-guiaMuestra", "YES", "-sinOnboarding", "YES", "-pestana", "entreno", "-abrir", "guia",
                               "-guiaAncla", "dudas-llamada", "-audioDoble", "YES"] + extra
        app.launch()
        XCTAssertTrue(boton("audio-grabar").waitForExistence(timeout: 20), "No apareció «Grabar un audio»")
        llevarALaVista(boton("audio-grabar"))
    }

    private func boton(_ id: String) -> XCUIElement { app.buttons[id] }
    private func texto(_ t: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch }

    /// Lo deja en la mitad de arriba de la pantalla, con lugar para lo que aparece debajo.
    private func llevarALaVista(_ e: XCUIElement) {
        for _ in 0..<8 {
            guard e.exists else { return }
            if e.isHittable && e.frame.midY < app.frame.height * 0.55 && e.frame.minY > app.frame.height * 0.12 { return }
            let origen = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let d: CGFloat = e.frame.midY > app.frame.height * 0.55 ? -app.frame.height * 0.25 : app.frame.height * 0.2
            origen.press(forDuration: 0.05, thenDragTo: origen.withOffset(CGVector(dx: 0, dy: d)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    private func captura(_ nombre: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = nombre; a.lifetime = .keepAlways; add(a)
        guard let dir = ProcessInfo.processInfo.environment["AUDIO_CAPTURAS"], !dir.isEmpty else { return }
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ios-audio-\(nombre).png"))
    }

    private var sufijo: String { ProcessInfo.processInfo.environment["AUDIO_SUFIJO"] ?? "" }

    /// Grabar, revisar, escuchar y mandar con la cola y la 019 simuladas: «Mandando tu audio…», «Listo, me llegó tu
    /// audio…» y la transcripción.
    func testGrabarRevisarYMandar() throws {
        abrir(["-audioServidor", "YES"])
        captura("reposo\(sufijo)")
        boton("audio-grabar").tap()
        XCTAssertTrue(boton("audio-terminar").waitForExistence(timeout: 5), "No arrancó a grabar")
        XCTAssertEqual(boton("audio-terminar").label, "Terminar de grabar")
        sleep(3)
        captura("grabando\(sufijo)")
        boton("audio-terminar").tap()
        XCTAssertTrue(boton("audio-mandar").waitForExistence(timeout: 5), "No pasó a revisar")
        XCTAssertTrue(boton("audio-de-nuevo").exists && boton("audio-borrar").exists && boton("audio-escuchar").exists)
        boton("audio-escuchar").tap()
        XCTAssertTrue(app.buttons["Pausar tu audio"].waitForExistence(timeout: 3), "No reproduce lo grabado")
        captura("revisar\(sufijo)")
        boton("audio-mandar").tap()
        XCTAssertTrue(texto("Mandando tu audio").waitForExistence(timeout: 5), "No se vio «Mandando tu audio…»")
        XCTAssertTrue(boton("audio-grabar").exists, "El grabador no volvió a reposo")
        captura("mandando\(sufijo)")
        XCTAssertTrue(texto("Listo, me llegó tu audio").waitForExistence(timeout: 15), "No se confirmó la subida")
        captura("subido\(sufijo)")
        XCTAssertTrue(texto("Esto es lo que entendí").waitForExistence(timeout: 15), "No llegó la transcripción")
        XCTAssertTrue(texto("¿Puedo tomar café antes de entrenar?").exists)
        captura("transcripto\(sufijo)")
    }

    /// Menos de 2 segundos no se manda.
    func testMuyCortoNoSeManda() throws {
        abrir()
        boton("audio-grabar").tap()
        XCTAssertTrue(boton("audio-terminar").waitForExistence(timeout: 5))
        boton("audio-terminar").tap()
        // Con la máquina cargada el toque puede llegar pasados los 2 s y entonces sí se revisa (la regla la cubren las
        // pruebas del kit): no es una falla.
        if boton("audio-mandar").waitForExistence(timeout: 1) { throw XCTSkip("El toque en «Terminar» llegó después de 2 s") }
        XCTAssertTrue(texto("No se escuchó nada, probá de nuevo.").waitForExistence(timeout: 3))
        XCTAssertFalse(boton("audio-mandar").exists)
    }

    /// En la demo (sin cola): se graba y se escucha, pero «Mandar» dice «Vista previa». Borrar y grabar de nuevo.
    func testVistaPreviaBorrarYGrabarDeNuevo() throws {
        abrir()
        boton("audio-grabar").tap()
        XCTAssertTrue(boton("audio-terminar").waitForExistence(timeout: 5))
        sleep(3)
        boton("audio-terminar").tap()
        XCTAssertTrue(boton("audio-mandar").waitForExistence(timeout: 5))
        boton("audio-mandar").tap()
        XCTAssertTrue(texto("Vista previa: el audio no se manda.").waitForExistence(timeout: 3))
        XCTAssertTrue(boton("audio-mandar").exists, "Tiene que seguir revisando")
        boton("audio-de-nuevo").tap()
        XCTAssertTrue(boton("audio-terminar").waitForExistence(timeout: 5), "Grabar de nuevo no arrancó")
        sleep(3)
        boton("audio-terminar").tap()
        XCTAssertTrue(boton("audio-borrar").waitForExistence(timeout: 5))
        boton("audio-borrar").tap()
        XCTAssertTrue(boton("audio-grabar").waitForExistence(timeout: 3))
        XCTAssertFalse(boton("audio-mandar").exists)
    }

    /// Segundo plano mientras graba: frena y pasa a revisar.
    func testSegundoPlanoPasaARevisar() throws {
        abrir()
        boton("audio-grabar").tap()
        XCTAssertTrue(boton("audio-terminar").waitForExistence(timeout: 5))
        sleep(3)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(boton("audio-mandar").waitForExistence(timeout: 8), "No quedó revisando al volver")
    }

    /// Permiso negado: el texto con Ajustes y el botón «Abrir ajustes».
    func testPermisoNegado() throws {
        abrir(["-audioPermiso", "negado"])
        boton("audio-grabar").tap()
        XCTAssertTrue(texto("no me dio permiso para el micrófono").waitForExistence(timeout: 3))
        XCTAssertTrue(boton("audio-ajustes").exists)
        captura("permiso-negado\(sufijo)")
    }

    /// Antes del primer permiso, el renglón chico.
    func testAntesDelPermisoAvisa() throws {
        abrir(["-audioPermiso", "sinPreguntar"])
        XCTAssertTrue(texto("Te va a pedir permiso para usar el micrófono").exists)
    }

    /// La transcripción no se repite en «Ya me dejaste esta» (la muestra trae la misma duda escrita).
    func testTranscriptoSeVeUnaSolaVez() throws {
        abrir(["-audioEstado", "transcripto"])
        XCTAssertTrue(texto("Esto es lo que entendí").waitForExistence(timeout: 5))
        XCTAssertTrue(texto("¿Puedo entrenar a la noche?").exists)
        // La única duda escrita de la muestra es la misma que la transcripción: no queda «Ya me dejaste esta».
        XCTAssertFalse(texto("Ya me dejaste").exists)
    }
}
