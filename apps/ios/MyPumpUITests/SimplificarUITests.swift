import XCTest

/// Simplificar (OK de Mati del 11/11, `nativa-evidencia/privado/simplificar/SPEC.md`): los 7 puntos en el iPhone, contra los
/// dobles (sin red, datos inventados), y cada destino de aviso tocando el aviso de verdad. Con `TEST_RUNNER_SIMPLIFICAR_DIR`
/// deja las capturas `simplificar-ios-<modo>-<n>.png` (claro, oscuro y letra grande).
@MainActor
final class SimplificarUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["SIMPLIFICAR_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ args: [String], pestana: String = "entreno") {
        app = XCUIApplication()
        let token = "tksimplificar" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana] + args
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
    }
    /// La demo (devoluciones, novedades y progreso de ejemplo), sin cuenta.
    private func lanzarDemo(_ args: [String], pestana: String) {
        app = XCUIApplication()
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", pestana] + args
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
    }
    /// Mi salud con algo para hacer, la guía de muestra a mitad de camino (o como se pida) y la lista previa.
    private func lanzarInicio(_ extra: [String] = []) {
        lanzar(["-miSaludDePrueba", "completo/serie0", "-guiaMuestra", "YES", "-guiaBienvenida", "no", "-guiaVolverAEntreno", "YES",
                "-listaPreviaDePrueba", "demo"] + extra)
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func pausa(_ s: TimeInterval = 0.5) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    private func esperar(_ id: String, _ t: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        if e(id).waitForExistence(timeout: t) { return }
        foto("fallo-\(id)")
        XCTFail("No apareció \(id)", file: file, line: line)
    }
    private func foto(_ nombre: String) {
        pausa(0.8)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir {
            let modo = letraGrande ? "letra-grande" : oscuro ? "oscuro" : "claro"
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/simplificar-ios-\(modo)-\(nombre).png"))
        }
    }
    private func bajarHasta(_ x: XCUIElement, max: Int = 25) {
        var n = 0
        while !(x.exists && x.isHittable) && n < max { app.swipeUp(); n += 1 }
    }

    // MARK: 1 y 3: arriba de Entreno, «Tu inicio con Mati» y una sola «Mi salud»

    func testEntrenoArribaUnaTarjetaDeInicioYUnaDeSalud() {
        lanzarInicio()
        esperar("inicio-con-mati")
        esperar("tarjeta-mi-salud-inicio")
        // La guía grande, con su avance, es lo primero; arriba de Mi salud.
        let guia = e("guia-destacada")
        XCTAssertTrue(guia.waitForExistence(timeout: 10), "La guía grande no está dentro de «Tu inicio con Mati»")
        XCTAssertTrue(app.staticTexts["Tu inicio con Mati"].exists)
        XCTAssertLessThan(e("inicio-con-mati").frame.minY, e("tarjeta-mi-salud-inicio").frame.minY, "Tu inicio va primero")
        XCTAssertLessThan(guia.frame.minY, e("lista-previa").exists ? e("lista-previa").frame.minY : .greatestFiniteMagnitude)
        // Ni sueltas ni repetidas: las viejas no están afuera.
        for viejo in ["lista-previa-tarjeta", "estudios-tarjeta-inicio", "control-tarjeta-inicio", "tarjeta-presion"] {
            XCTAssertFalse(e(viejo).exists, "\(viejo) quedó suelta en Entreno")
        }
        XCTAssertGreaterThanOrEqual(e("guia-tarjeta").frame.height, 44)
        foto("1-entreno-arriba")
        bajarHasta(e("tarjeta-mi-salud-inicio-boton"), max: 6)
        foto("1-entreno-mi-salud")
    }

    /// Con todo visto: una fila discreta dentro de «Tu inicio con Mati» (sin la tarjeta verde) y la fila de Mis datos todavía no.
    func testGuiaVistaQuedaComoFilaDiscreta() {
        lanzarInicio(["-guiaVistos", "todos"])
        esperar("inicio-con-mati")
        XCTAssertFalse(e("guia-destacada").exists, "con todo visto ya no va grande")
        let fila = app.buttons["guia-tarjeta"]
        XCTAssertTrue(fila.waitForExistence(timeout: 10))
        XCTAssertTrue(fila.label.contains("Viste los"), fila.label)
        foto("2-entreno-guia-vista")
        fila.tap()
        XCTAssertTrue(app.navigationBars["Tu guía"].waitForExistence(timeout: 15))
    }

    // MARK: 2 y 7: «Mis datos» con texto y corto

    func testMisDatosConTextoYCorto() {
        lanzar(["-miSaludDePrueba", "completo/serie0", "-guiaMuestra", "YES", "-guiaBienvenida", "no"], pestana: "revision")
        let boton = app.buttons["revision-mis-datos"]
        XCTAssertTrue(boton.waitForExistence(timeout: 20))
        XCTAssertEqual(boton.label, "Mis datos")
        XCTAssertTrue(app.staticTexts["Mis datos"].exists || boton.frame.width > 60, "el botón dice «Mis datos», no es solo un ícono")
        foto("3-revision")
        boton.tap()
        XCTAssertTrue(app.navigationBars["Mis datos"].waitForExistence(timeout: 10))
        for fuera in ["mis-datos-novedades", "mis-datos-tecnica", "mis-datos-gimnasio", "mis-datos-fotos-inicio"] {
            XCTAssertFalse(e(fuera).exists, "\(fuera) tenía que salir de Mis datos")
        }
        XCTAssertTrue(e("mis-datos-mi-salud").exists, "Mi salud se queda como atajo")
        for grupo in ["MI PLAN", "AJUSTES", "PRIVACIDAD"] {
            let g = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", grupo)).firstMatch
            bajarHasta(g, max: 6)
            XCTAssertTrue(g.exists, "Falta el grupo \(grupo)")
        }
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        foto("4-mis-datos")
        let filas = app.cells.count
        XCTAssertLessThanOrEqual(filas, 12, "Mis datos tiene \(filas) renglones")
    }

    // MARK: 4: «Mi gimnasio y mi técnica»

    func testGimnasioYTecnicaUnaPantallaConLaRespuestaAUnToque() {
        lanzar(["-tecnicaDePrueba", "publicado"])
        let respuesta = e("donde-entreno-respuesta")
        XCTAssertTrue(respuesta.waitForExistence(timeout: 30), "Falta «Ver lo que te respondió Mati» en Entreno")
        bajarHasta(respuesta)
        foto("5-entreno-renglon")
        // Un toque: la respuesta de Mati.
        respuesta.tap()
        esperar("tecnica-credito", 15)
        foto("6-respuesta-tecnica")
        app.navigationBars.buttons.firstMatch.tap()
        esperar("donde-entreno-bloque-tecnica", 10)
        XCTAssertTrue(e("tecnica-fila-publicado").exists)
        foto("7-mi-tecnica")
    }

    func testGimnasioConCasaEnLaMismaPantalla() {
        lanzar(["-colaBDePrueba", "gimnasioListo"])
        XCTAssertTrue(app.pestana("Entreno").waitForExistence(timeout: 20))
        XCTAssertFalse(e("casa-tarjeta").exists, "el botón suelto de casa pasó adentro")
        app.abrirDondeEntreno()
        esperar("donde-entreno-bloque-gimnasio")
        esperar("casa-interruptor")
        esperar("donde-entreno-gimnasio")
        foto("8-mi-gimnasio")
        e("donde-entreno-gimnasio").tap()
        XCTAssertTrue(app.navigationBars["Tu gimnasio"].waitForExistence(timeout: 15))
    }

    // MARK: 5: «Mi progreso», una columna con la recuperación

    func testMiProgresoUnaColumnaConRecuperacion() {
        lanzarDemo([], pestana: "revision")
        let progreso = app.buttons["tarjeta-progreso-revision"]
        bajarHasta(progreso, max: 10)
        progreso.tap()
        XCTAssertTrue(app.navigationBars["Mi progreso"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "sin los tres botones de arriba")
        for s in ["recuperacion", "fuerza", "cuerpo"] { esperar("mi-progreso-\(s)", 10) }
        app.swipeDown(); app.swipeDown()
        foto("9-mi-progreso-arriba")
        bajarHasta(e("cuerpo-fotos"))
        foto("9-mi-progreso-cuerpo")
    }

    // MARK: 6: la devolución y las novedades juntas en Revisión

    func testNovedadesEnRevisionDebajoDeLaDevolucion() {
        lanzarDemo(["-novedadDeMuestra", "rutina"], pestana: "revision")
        // La hoja de la novedad sale sola la primera vez: se cierra.
        let listo = app.buttons["Listo"]
        if listo.waitForExistence(timeout: 8) { listo.tap() }
        let bloque = e("revision-novedades")
        bajarHasta(bloque, max: 8)
        XCTAssertTrue(bloque.exists, "Falta «Lo último que cambió en tu plan» en Revisión")
        XCTAssertTrue(app.staticTexts["Lo último que cambió en tu plan"].exists)
        if e("devolucion-seccion").exists {
            XCTAssertLessThan(e("devolucion-seccion").frame.minY, bloque.frame.minY, "va debajo de la devolución")
        }
        foto("10-revision-novedades")
        e("revision-novedades-ver-todo").tap()
        XCTAssertTrue(app.navigationBars["Novedades de tu plan"].waitForExistence(timeout: 10))
        XCTAssertTrue(e("novedad-fila").waitForExistence(timeout: 5))
    }

    // MARK: Capturas en oscuro y con letra grande

    func testCapturasOscuro() {
        oscuro = true
        testEntrenoArribaUnaTarjetaDeInicioYUnaDeSalud(); app.terminate()
        testMisDatosConTextoYCorto(); app.terminate()
        testGimnasioYTecnicaUnaPantallaConLaRespuestaAUnToque(); app.terminate()
        testMiProgresoUnaColumnaConRecuperacion(); app.terminate()
        testNovedadesEnRevisionDebajoDeLaDevolucion()
    }
    func testCapturasLetraGrande() {
        letraGrande = true
        testEntrenoArribaUnaTarjetaDeInicioYUnaDeSalud(); app.terminate()
        testGuiaVistaQuedaComoFilaDiscreta(); app.terminate()
        testGimnasioYTecnicaUnaPantallaConLaRespuestaAUnToque(); app.terminate()
        testMiProgresoUnaColumnaConRecuperacion()
    }

    // MARK: Cada destino de aviso, tocando el aviso (app en el fondo, como un push)

    /// El aviso local (`-avisoDePrueba`, solo Debug) entra por el mismo `didReceive` que el push, con el mismo `destino`.
    private func tocarAviso(_ destino: String) {
        lanzar(["-miSaludDePrueba", "completo/serie0", "-avisoDePrueba", destino])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permitir = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Permitir"])).firstMatch
        if permitir.waitForExistence(timeout: 5) { permitir.tap() }
        XCTAssertTrue(app.pestana("Entreno").waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        let aviso = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Mati te dejó un mensaje")).firstMatch
        // El cartel dura unos segundos: si se fue antes de buscarlo (simulador cargado), queda en el centro de avisos.
        if !aviso.waitForExistence(timeout: 25) {
            let arriba = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.005))
            arriba.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)))
        }
        XCTAssertTrue(aviso.waitForExistence(timeout: 10), "No llegó el aviso \(destino)")
        aviso.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    private func destino(_ d: String, _ comprobar: () -> Void) {
        tocarAviso(d)
        comprobar()
        foto("aviso-\(d)")
        app.terminate()
    }

    func testCadaDestinoDeAvisoAbreSuLugar() {
        destino("train") { XCTAssertTrue(app.pestana("Entreno").waitForExistence(timeout: 10)); XCTAssertTrue(app.pestana("Entreno").isSelected) }
        destino("diet") { XCTAssertTrue(app.pestana("Dieta").waitForExistence(timeout: 10)); pausa(1.5); XCTAssertTrue(app.pestana("Dieta").isSelected) }
        destino("chat") { esperar("chat-campo", 15) }
        destino("revision") { pausa(1.5); XCTAssertTrue(app.pestana("Revisión").isSelected) }
        destino("progress") {
            XCTAssertTrue(app.navigationBars["Mi progreso"].waitForExistence(timeout: 15), "progress → Mi progreso")
            esperar("mi-progreso-fuerza", 10)
        }
        destino("myday") {
            XCTAssertTrue(app.navigationBars["Mi salud"].waitForExistence(timeout: 15), "myday → Mi salud")
            esperar("mi-salud-bloque-recuperacion", 10)
        }
        destino("salud") {
            XCTAssertTrue(app.navigationBars["Mi salud"].waitForExistence(timeout: 15), "salud → Mi salud")
            esperar("mi-salud-bloque-recuperacion", 10)
        }
        destino("estudios") {
            XCTAssertTrue(app.navigationBars["Mi salud"].waitForExistence(timeout: 15), "estudios → Mi salud")
            esperar("mi-salud-bloque-estudios", 10)
        }
        destino("presion") {
            esperar("presion-cuando", 20)   // Presión directo en la toma de hoy
            XCTAssertTrue(e("mi-salud-bloque-presion").exists, "con Mi salud debajo")
        }
        // Sin fotos de inicio pedidas (este doble), queda en Revisión, sin pantalla en blanco.
        destino("fotos_inicio") { pausa(1.5); XCTAssertTrue(app.pestana("Revisión").isSelected) }
        // Un destino que no existe cae en el Chat.
        destino("no_existe") { esperar("chat-campo", 15) }
    }
}
