import XCTest

/// La pestaña Salud (2.1, S1 y S2): los tres segmentos con la cuenta de prueba (el token llega por
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

    private var control: XCUIElement { app.segmentedControls["segmento-salud"].firstMatch }

    func testLosTresSegmentosEnClaro() throws { try tresSegmentos(oscuro: false) }

    func testLosTresSegmentosEnOscuro() throws { try tresSegmentos(oscuro: true) }

    private func tresSegmentos(oscuro: Bool) throws {
        let tema = oscuro ? "oscuro" : "claro"
        try abrir(oscuro: oscuro)
        XCTAssertTrue(app.navigationBars["Salud"].waitForExistence(timeout: 20), "No abrió Salud")
        XCTAssertTrue(app.pestana("Salud").exists, "La pestaña no se llama Salud")
        XCTAssertFalse(app.pestana("Progreso").exists, "Quedó la pestaña Progreso")
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Falta el control de segmentos")
        for nombre in ["Recuperación", "Fuerza", "Cuerpo"] {
            XCTAssertTrue(control.buttons[nombre].exists, "Falta el segmento \(nombre)")
        }
        // Arranca en Recuperación: la card de recuperación (o la de conectar salud, si la cuenta no tiene permiso).
        XCTAssertTrue(control.buttons["Recuperación"].isSelected, "No arrancó en Recuperación")
        let recuperacion = app.otherElements["card-recuperacion"].firstMatch
        XCTAssertTrue(recuperacion.waitForExistence(timeout: 15), "Recuperación no muestra la card")
        sleep(1)
        captura("t2-salud-recuperacion-\(tema)")

        control.buttons["Fuerza"].tap()
        let volumen = app.otherElements["volumen-musculo"].firstMatch
        XCTAssertTrue(volumen.waitForExistence(timeout: 15), "Fuerza no muestra las series por músculo")
        XCTAssertTrue(app.staticTexts["Series por músculo"].exists)
        XCTAssertFalse(recuperacion.exists, "La card de recuperación quedó en Fuerza")
        sleep(2)   // que llegue el historial
        captura("t2-salud-fuerza-\(tema)")

        control.buttons["Cuerpo"].tap()
        XCTAssertTrue(app.textFields["peso-hoy"].firstMatch.waitForExistence(timeout: 10), "Cuerpo no trae el peso")
        XCTAssertTrue(app.otherElements["cuerpo-fotos"].firstMatch.exists, "Cuerpo no trae las fotos por semana")
        sleep(1)
        captura("t2-salud-cuerpo-\(tema)")
        let check = app.otherElements["cuerpo-check"].firstMatch
        for _ in 0..<6 where !check.isHittable { app.swipeUp() }
        XCTAssertTrue(check.exists, "Cuerpo no trae el check de la semana")
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

    /// Un aviso o un botón con el viejo «Progreso» abre Salud → Fuerza (el argumento viejo sigue andando).
    func testElArgumentoViejoProgresoAbreSalud() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else { throw XCTSkip("Falta MYPUMP_TOKEN") }
        app.launchArguments = ["-token", token, "-pestana", "progreso", "-sinOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Salud"].waitForExistence(timeout: 20))
    }

    /// El cierre del día en la demo, con 3 series confirmadas: «Series por músculo hoy».
    func testElCierreDelDiaTraeLasSeriesPorMusculo() throws {
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno", "-captura", "YES",
                               "-abrir", "ejercicio", "-series", "3", "-descanso", "no"]
        app.launch()
        let demo = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ver demo'")).firstMatch
        if demo.waitForExistence(timeout: 3) { app.terminate(); app.launch(); if demo.waitForExistence(timeout: 3) { demo.tap() } }
        // Con las series confirmadas, se vuelve a la lista y se cierra.
        let atras = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(atras.waitForExistence(timeout: 30), "No abrió el ejercicio")
        sleep(2)
        atras.tap()
        let cerrar = app.buttons.matching(NSPredicate(format: "label == 'Cerrar sesión de hoy'")).firstMatch
        for _ in 0..<12 where !(cerrar.exists && cerrar.isHittable) { app.swipeUp() }
        XCTAssertTrue(cerrar.isHittable, "No está «Cerrar sesión de hoy»")
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
