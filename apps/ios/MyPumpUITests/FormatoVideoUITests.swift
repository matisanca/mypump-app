import XCTest

/// El cuadro del video toma la forma del clip (pedido de Mati del 6/11: nunca franjas negras). Con la muestra y
/// `-guiaFormatos YES`, tres MP4 chicos armados en el momento (nada de clips de clientes, nada de red): vertical
/// (570×720, con la pista girada), horizontal (1280×720) y cuadrado. Con `AGENDA_CAPTURAS=<carpeta>` en el entorno del
/// runner deja `ios-video-<formato><AGENDA_SUFIJO>.png`.
@MainActor
final class FormatoVideoUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws { continueAfterFailure = false }

    private func abrir(_ extra: [String]) {
        app.terminate()
        app.launchArguments = ["-bocetos", "YES", "-guiaMuestra", "YES", "-guiaFormatos", "YES", "-guiaBienvenida", "no",
                               "-sinOnboarding", "YES", "-pestana", "entreno", "-abrir", "guia"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["guia-avance"].waitForExistence(timeout: 20), "No abrió la guía")
    }

    private func esperar(_ condicion: () -> Bool, segundos: Double) -> Bool {
        let limite = Date().addingTimeInterval(segundos)
        while Date() < limite {
            if condicion() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return condicion()
    }

    private func captura(_ nombre: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = nombre; a.lifetime = .keepAlways; add(a)
        guard let dir = ProcessInfo.processInfo.environment["AGENDA_CAPTURAS"], !dir.isEmpty else { return }
        let sufijo = ProcessInfo.processInfo.environment["AGENDA_SUFIJO"] ?? ""
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ios-\(nombre)\(sufijo).png"))
    }

    /// Desplaza para que el cuadro entero quede entre la barra de arriba y la de pestañas (para la captura).
    private func mostrarEntero(_ cuadro: XCUIElement) {
        let abajo = app.frame.height - 100, arriba: CGFloat = 110
        for _ in 0..<4 {
            let f = cuadro.frame
            if f.minY >= arriba && f.maxY <= abajo { return }
            let d = f.maxY > abajo ? -(min(f.maxY - abajo, f.minY - arriba)) : arriba - f.minY
            let origen = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            origen.press(forDuration: 0.05, thenDragTo: origen.withOffset(CGVector(dx: 0, dy: d)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    /// El cuadro llega a la forma del clip, centrado, sin pasarse del ancho ni (los verticales) del 60 % del alto.
    private func comprobar(_ cuadro: XCUIElement, proporcion: Double, _ nombre: String) {
        XCTAssertTrue(cuadro.waitForExistence(timeout: 15), "No está el cuadro de \(nombre)")
        let llego = esperar({
            let f = cuadro.frame
            return f.height > 0 && abs(f.width / f.height - proporcion) < 0.03
        }, segundos: 15)
        let f = cuadro.frame
        XCTAssertTrue(llego, "\(nombre): el cuadro quedó en \(f.width)×\(f.height), se esperaba \(proporcion)")
        XCTAssertLessThanOrEqual(f.width, app.frame.width)
        XCTAssertLessThanOrEqual(f.height, app.frame.height * 0.6 + 1, "\(nombre): pasa del 60 % del alto")
        XCTAssertEqual(f.midX, app.frame.midX, accuracy: 2, "\(nombre): no está centrado")
    }

    /// Los sintéticos no traen negro: se ven enteros (la detección no recorta un video sin franjas).
    func testCadaFormatoConSuForma() throws {
        for (id, proporcion, nombre) in [("MC-7a", 570.0 / 720.0, "vertical"), ("MC-13c", 1280.0 / 720.0, "horizontal"),
                                         ("FT-26a", 1.0, "cuadrado")] {
            abrir(["-guiaVideo", id])
            let cuadro = app.descendants(matching: .any)["guia-cuadro-video"].firstMatch
            comprobar(cuadro, proporcion: proporcion, nombre)
            // Ya corriendo: la forma sigue (no vuelve al 16:9 cuando llega el presentationSize).
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            XCTAssertEqual(cuadro.frame.width / cuadro.frame.height, proporcion, accuracy: 0.03)
            mostrarEntero(cuadro)
            captura("video-\(nombre)")
        }
    }

    /// Al volver a abrir un clip ya visto, arranca con su forma guardada (sin pasar por 16:9).
    func testLaFormaGuardadaEstaDesdeElPrincipio() throws {
        abrir(["-guiaVideo", "MC-7a"])
        let cuadro = app.descendants(matching: .any)["guia-cuadro-video"].firstMatch
        comprobar(cuadro, proporcion: 570.0 / 720.0, "vertical")
        abrir(["-guiaVideo", "MC-7a", "-sinRed", "YES"])
        // Sin red no se puede leer el video: la forma sale de lo guardado.
        XCTAssertTrue(cuadro.waitForExistence(timeout: 15))
        XCTAssertEqual(cuadro.frame.width / cuadro.frame.height, 570.0 / 720.0, accuracy: 0.03)
    }

    /// El clip de la demo que vio Mati («Lo que cambia en tu entrenamiento», FT-2b público): el archivo es 1280×720 con la
    /// grabación vertical en el medio y el negro metido en el video (columnas 422 a 855, 434 px). La app detecta la zona
    /// útil y el cuadro queda vertical (unos 0,63), sin el negro a los costados.
    func testClipDeLaDemoSeRecortaASuZonaUtil() throws {
        app.terminate()
        app.launchArguments = ["-bocetos", "YES", "-agendaDemo", "flujo", "-sinOnboarding", "YES", "-pestana", "entreno",
                               "-abrir", "guia", "-guiaVideo", "N-1", "-guiaOlvidarFormas", "YES"]
        app.launch()
        let cuadro = app.descendants(matching: .any)["guia-cuadro-video"].firstMatch
        XCTAssertTrue(cuadro.waitForExistence(timeout: 20))
        let llego = esperar({
            let f = cuadro.frame
            return f.height > 0 && (0.55...0.66).contains(f.width / f.height)
        }, segundos: 15)
        XCTAssertTrue(llego, "El clip con el negro en el archivo quedó en \(cuadro.frame.width)×\(cuadro.frame.height)")
        XCTAssertEqual(cuadro.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertLessThanOrEqual(cuadro.frame.height, app.frame.height * 0.6 + 1)
        // Pasada la placa del título (los primeros 3 s), la grabación vertical.
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        mostrarEntero(cuadro)
        XCTAssertGreaterThanOrEqual(cuadro.frame.minY, 100)
        XCTAssertLessThanOrEqual(cuadro.frame.maxY, app.frame.height - 90, "El cuadro tiene que entrar entero arriba de las pestañas")
        captura("video-demo-recortado")
        // Con lo medido guardado, al volver a abrirlo arranca recortado (sin red no se mide nada).
        app.terminate()
        app.launchArguments = ["-bocetos", "YES", "-agendaDemo", "flujo", "-sinOnboarding", "YES", "-pestana", "entreno",
                               "-abrir", "guia", "-guiaVideo", "N-1"]
        app.launch()
        XCTAssertTrue(cuadro.waitForExistence(timeout: 20))
        XCTAssertTrue((0.55...0.66).contains(cuadro.frame.width / cuadro.frame.height), "\(cuadro.frame)")
    }

    /// El «Ver por qué» de la citrulina (vertical) también toma su forma.
    func testVerPorQueVertical() throws {
        abrir(["-guiaVerPorQue", "FT-1b"])
        let cuadro = app.descendants(matching: .any)["guia-ver-por-que-video"].firstMatch
        XCTAssertTrue(cuadro.waitForExistence(timeout: 15))
        for _ in 0..<12 where !(cuadro.isHittable && cuadro.frame.maxY < app.frame.height * 0.9) { app.swipeUp() }
        comprobar(cuadro, proporcion: 570.0 / 720.0, "ver por qué")
        captura("video-ver-por-que")
    }
}
