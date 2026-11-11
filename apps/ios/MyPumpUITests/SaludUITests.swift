import XCTest

/// «Mi progreso» (antes Salud; 2.1, S1 y S2; desde la 2.1.0 una hoja sobre Revisión; desde el simplificar del 11/11 una sola
/// columna sin los botones de arriba): las tres secciones con la cuenta de prueba (el token llega por
/// `TEST_RUNNER_MYPUMP_TOKEN`, nunca escrito en el repo), en claro y oscuro, y las series por músculo del cierre del día
/// en la demo. Gemelo de `SaludPestanaUiTest.kt`.
@MainActor
final class SaludUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func abrir(segmento: String? = nil, oscuro: Bool = false) throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-pestana", "salud", "-sinOnboarding", "YES"]
        if let segmento { app.launchArguments += ["-segmento", segmento] }
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        app.launch()
    }

    private var barra: XCUIElement { app.navigationBars["Mi progreso"] }
    private func seccion(_ s: String) -> XCUIElement { app.descendants(matching: .any)["mi-progreso-\(s)"].firstMatch }
    /// La sección quedó arriba, a la vista (lo que antes era «el segmento seleccionado»).
    private func arriba(_ s: String) -> Bool {
        let x = seccion(s)
        guard x.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<10 where abs(x.frame.minY - barra.frame.maxY) > 160 { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
        return abs(x.frame.minY - barra.frame.maxY) <= 160
    }

    func testLosTresSegmentosEnClaro() throws { try tresSegmentos(oscuro: false) }

    func testLosTresSegmentosEnOscuro() throws { try tresSegmentos(oscuro: true) }

    private func tresSegmentos(oscuro: Bool) throws {
        let tema = oscuro ? "oscuro" : "claro"
        try abrir(oscuro: oscuro)
        XCTAssertTrue(barra.waitForExistence(timeout: 20), "No abrió Mi progreso")
        XCTAssertFalse(app.tabBars.buttons["Salud"].exists, "Salud ya no es una pestaña: se abre desde Revisión")
        XCTAssertFalse(app.pestana("Progreso").exists, "Quedó la pestaña Progreso")
        XCTAssertFalse(app.segmentedControls["segmento-salud"].exists, "Los botones de arriba se fueron (una sola columna)")
        for nombre in ["recuperacion", "fuerza", "cuerpo"] {
            XCTAssertTrue(seccion(nombre).waitForExistence(timeout: 10), "Falta la sección \(nombre)")
        }
        // Arriba de todo, Recuperación: la card de recuperación (o la de conectar salud, si la cuenta no tiene permiso).
        let recuperacion = app.otherElements["card-recuperacion"].firstMatch
        XCTAssertTrue(recuperacion.waitForExistence(timeout: 15), "Recuperación no muestra la card")
        XCTAssertTrue(arriba("recuperacion"), "No arrancó en Recuperación")
        sleep(1)
        captura("t2-salud-recuperacion-\(tema)")

        // Bajando, Fuerza y después Cuerpo, en la misma pantalla.
        let volumen = app.otherElements["volumen-musculo"].firstMatch
        for _ in 0..<8 where !(volumen.exists && volumen.isHittable) { app.swipeUp() }
        XCTAssertTrue(volumen.waitForExistence(timeout: 15), "Fuerza no muestra las series por músculo")
        XCTAssertTrue(app.staticTexts["Series por músculo"].exists)
        sleep(2)   // que llegue el historial
        captura("t2-salud-fuerza-\(tema)")

        let peso = app.textFields["peso-hoy"].firstMatch
        for _ in 0..<12 where !(peso.exists && peso.isHittable) { app.swipeUp() }
        XCTAssertTrue(peso.waitForExistence(timeout: 10), "Cuerpo no trae el peso")
        XCTAssertTrue(app.otherElements["cuerpo-fotos"].firstMatch.exists, "Cuerpo no trae las fotos por semana")
        sleep(1)
        captura("t2-salud-cuerpo-\(tema)")
        let check = app.otherElements["cuerpo-check"].firstMatch
        for _ in 0..<6 where !check.isHittable { app.swipeUp() }
        XCTAssertTrue(check.exists, "Cuerpo no trae el check de la semana")
        // La recuperación sigue en la misma hoja (no se fue a ningún lado).
        XCTAssertTrue(recuperacion.exists, "La recuperación desapareció de Mi progreso")
        captura("t2-salud-cuerpo-abajo-\(tema)")
    }

    /// Las filas del volumen se leen como una sola unidad con VoiceOver («Pecho, 12 series esta semana, 10 la semana pasada»).
    func testElVolumenSeLeeEnUnaFrase() throws {
        try abrir(segmento: "fuerza")
        let volumen = app.otherElements["volumen-musculo"].firstMatch
        XCTAssertTrue(volumen.waitForExistence(timeout: 20))
        let filas = volumen.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'volumen-' AND identifier != 'volumen-musculo'"))
        if filas.count == 0 {
            // Sin filas lo dice: sin series, o trayendo el historial, o sin red (revisión del 3-nov).
            let textos = ["Todavía no registraste series esta semana.", "Trayendo tus series de la semana…",
                          "Sin conexión: tus series de la semana se ven cuando vuelva la señal."]
            XCTAssertTrue(textos.contains { app.staticTexts[$0].exists }, "Sin filas tiene que decirlo")
        } else {
            let label = filas.element(boundBy: 0).label
            XCTAssertTrue(label.contains(" esta semana, ") && label.hasSuffix(" la semana pasada"), "Etiqueta: \(label)")
        }
    }

    /// Un aviso o un botón con el viejo «Progreso» abre Mi progreso en Fuerza (el argumento viejo sigue andando).
    func testElArgumentoViejoProgresoAbreSalud() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else { throw XCTSkip("Falta MYPUMP_TOKEN") }
        app.launchArguments = ["-token", token, "-pestana", "progreso", "-sinOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(barra.waitForExistence(timeout: 20))
        XCTAssertTrue(arriba("fuerza"), "El viejo «Progreso» tiene que abrir Fuerza")
    }

    /// 2.1.0: Salud no está en la barra. Desde «Mi salud» (11/11) la fila Recuperación vive ahí (arriba de todo en Revisión):
    /// la abre, y «Listo» vuelve a Mi salud. «Tu progreso» sigue en Revisión.
    func testLaTarjetaDeRevisionAbreSalud() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else { throw XCTSkip("Falta MYPUMP_TOKEN") }
        app.launchArguments = ["-token", token, "-pestana", "revision", "-sinOnboarding", "YES"]
        app.launch()
        let miSalud = app.buttons["tarjeta-mi-salud"]
        XCTAssertTrue(miSalud.waitForExistence(timeout: 20), "Falta la tarjeta Mi salud en Revisión")
        XCTAssertFalse(app.tabBars.buttons["Salud"].exists, "Salud quedó en la barra")
        XCTAssertTrue(app.pestana("Revisión").exists && app.pestana("Entreno").exists)
        XCTAssertFalse(app.buttons["tarjeta-recuperacion-revision"].exists, "Recuperación se mudó a Mi salud")
        captura("revision-con-mi-salud")
        miSalud.tap()
        let tarjeta = app.buttons["tarjeta-recuperacion-revision"]
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 20), "Falta la tarjeta Recuperación en Mi salud")
        tarjeta.tap()
        XCTAssertTrue(barra.waitForExistence(timeout: 5), "La tarjeta no abrió Mi progreso")
        XCTAssertTrue(arriba("recuperacion"), "No abrió en Recuperación")
        app.buttons["salud-cerrar"].tap()
        // La tarjeta existe detrás de la hoja: lo que prueba el cierre es que la barra de Salud se va.
        XCTAssertTrue(barra.waitForNonExistence(timeout: 5), "«Listo» no cerró Salud")

        // Volver a tocar Recuperación después de cerrar: la hoja vuelve a abrir (y en Recuperación).
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 5))
        tarjeta.tap()
        XCTAssertTrue(barra.waitForExistence(timeout: 5))
        XCTAssertTrue(arriba("recuperacion"))
        app.buttons["salud-cerrar"].tap()
        XCTAssertTrue(barra.waitForNonExistence(timeout: 5), "«Listo» no cerró Salud")
        // Atrás, a Revisión: «Tu progreso» abre Salud en Fuerza.
        app.navigationBars["Mi salud"].buttons.firstMatch.tap()
        let progreso = app.buttons["tarjeta-progreso-revision"]
        XCTAssertTrue(progreso.waitForExistence(timeout: 5), "Falta la tarjeta Tu progreso")
        progreso.tap()
        XCTAssertTrue(barra.waitForExistence(timeout: 5))
        XCTAssertTrue(arriba("fuerza"), "Tu progreso no abrió Fuerza")
        captura("salud-fuerza-desde-progreso")
        app.buttons["salud-cerrar"].tap()
        XCTAssertTrue(barra.waitForNonExistence(timeout: 5), "«Listo» no cerró Salud")
    }

    /// El cierre del día en la demo, con 3 series confirmadas: «Series por músculo hoy».
    func testElCierreDelDiaTraeLasSeriesPorMusculo() throws {
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno", "-captura", "YES",
                               "-abrir", "ejercicio", "-series", "3", "-descanso", "no"]
        app.launch()
        let demo = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ver demo'")).firstMatch
        if demo.waitForExistence(timeout: 3) { app.terminate(); app.launch(); if demo.waitForExistence(timeout: 3) { demo.tap() } }
        // Con las series confirmadas, se vuelve a la lista y se cierra.
        let atras = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(atras.waitForExistence(timeout: 30), "No abrió el ejercicio")
        sleep(2)
        app.volverALaLista()
        XCTAssertTrue(app.navigationBars["Remo con barra"].waitForNonExistence(timeout: 10), "No volvió a la lista")
        let cerrar = app.bajarHastaCerrarSesion()
        XCTAssertTrue(cerrar.isHittable, "No está «Terminar el entrenamiento de hoy»")
        cerrar.tap()
        let hoy = app.otherElements["volumen-hoy"].firstMatch
        XCTAssertTrue(hoy.waitForExistence(timeout: 10), "El cierre no trae las series por músculo")
        XCTAssertTrue(app.staticTexts["Series por músculo hoy"].exists)
        let fila = hoy.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ' hoy, '")).firstMatch
        XCTAssertTrue(fila.exists, "La fila no se lee como una frase")
        XCTAssertTrue(fila.label.contains("3 series hoy"), "Etiqueta: \(fila.label)")
        captura("t2-cierre-series-por-musculo-claro")
    }

    private func captura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
