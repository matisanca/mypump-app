import XCTest

/// Entreno en la demo (sin cuenta ni token): lo que se toca en la tabla de series.
@MainActor
final class EntrenoUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno", "-abrir", "ejercicio"]
        app.launch()
    }

    /// SER-04: al tocar un campo se selecciona todo y lo que se escribe reemplaza lo anterior (como `select()` en la
    /// web). Sin eso, 80 kg corregido a 7 quedaba "807" (revisión del 14-oct, hallazgo 2).
    func testTocarUnCampoLoSeleccionaEntero() throws {
        let campos = app.textFields
        XCTAssertTrue(campos.firstMatch.waitForExistence(timeout: 15), "No abrió el ejercicio")
        XCTAssertGreaterThanOrEqual(campos.count, 2, "El ejercicio no tiene columna de kg")
        let reps = campos.element(boundBy: 0), kg = campos.element(boundBy: 1)
        kg.tap()
        kg.typeText("80")
        reps.tap()   // el foco se va
        kg.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))   // la selección llega 0,08 s después del foco
        kg.typeText("7")
        XCTAssertEqual(kg.value as? String, "7", "lo nuevo no reemplazó a lo anterior")
    }

    /// D23 (Ian Actis, 20-oct): al confirmar una serie el descanso aparece grande, pegado a la tabla y traído a la vista
    /// sin tocar nada; −15 y +15 lo mueven y «Saltar descanso» lo saca.
    func testElDescansoApareceALaVistaYSeAjusta() throws {
        let campos = app.textFields
        XCTAssertTrue(campos.firstMatch.waitForExistence(timeout: 15), "No abrió el ejercicio")
        let reps = campos.element(boundBy: 0), kg = campos.element(boundBy: 1)
        reps.tap()
        reps.typeText("10")
        kg.tap()
        kg.typeText("60")
        let confirmar = app.buttons["confirmar-serie-1"]
        XCTAssertTrue(confirmar.waitForExistence(timeout: 3))
        confirmar.tap()
        let tarjeta = app.otherElements["descanso-en-tarjeta"]
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 5), "No apareció el descanso en la tarjeta")
        let saltar = tarjeta.buttons["Saltar descanso"]
        let aLaVista = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: saltar)
        wait(for: [aLaVista], timeout: 4)
        let tiempo = tarjeta.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Descanso, quedan'")).firstMatch
        XCTAssertTrue(tiempo.exists, "Sin la cuenta regresiva")
        let antes = Self.segundos(tiempo.label)
        XCTAssertGreaterThan(antes, 0, tiempo.label)
        tarjeta.buttons["Sumar 15 segundos"].tap()
        XCTAssertGreaterThanOrEqual(Self.segundos(tiempo.label), antes + 13, tiempo.label)
        tarjeta.buttons["Restar 15 segundos"].tap()
        tarjeta.buttons["Restar 15 segundos"].tap()
        XCTAssertLessThanOrEqual(Self.segundos(tiempo.label), antes - 14, tiempo.label)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "descanso-en-tarjeta"; a.lifetime = .keepAlways; add(a)
        saltar.tap()
        XCTAssertTrue(tarjeta.waitForNonExistence(timeout: 4), "«Saltar descanso» no lo sacó")
    }

    /// «Descanso, quedan 1:30» → 90.
    private static func segundos(_ etiqueta: String) -> Int {
        let partes = etiqueta.components(separatedBy: " ").last?.split(separator: ":").compactMap { Int($0) } ?? []
        return partes.count == 2 ? partes[0] * 60 + partes[1] : -1
    }

    /// ENT-10 y VoiceOver: después de sustituir y fijar, la card de la lista lo dice (antes la etiqueta fija tapaba la
    /// sustitución, los mensajes, la pauta y el récord), con la pauta y el descanso.
    func testLaCardDiceQueEstaSustituidaYFijada() throws {
        let sustituir = app.buttons["Sustituir"]
        XCTAssertTrue(sustituir.waitForExistence(timeout: 15), "No abrió el ejercicio")
        sustituir.tap()
        let hoja = app.navigationBars["Sustituir ejercicio"]
        XCTAssertTrue(hoja.waitForExistence(timeout: 5), "No abrió la hoja de sustituir")
        let variante = app.buttons.matching(identifier: "variante").firstMatch
        XCTAssertTrue(variante.waitForExistence(timeout: 5), "No hay variantes")
        variante.tap()
        // El interruptor está al pie de la lista (hasta 30 variantes). Se baja hasta poder tocarlo, no hasta que exista: en
        // iOS 18 la lista crea las filas antes de mostrarlas y el toque caía fuera de la pantalla.
        let fijar = app.switches.firstMatch
        for _ in 0..<10 where !(fijar.exists && fijar.isHittable) { app.swipeUp() }
        XCTAssertTrue(fijar.waitForExistence(timeout: 3) && fijar.isHittable, "No se llega a Fijar")
        if (fijar.value as? String) != "1" { fijar.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        XCTAssertEqual(fijar.value as? String, "1", "no se fijó")
        hoja.buttons["Sustituir"].tap()
        XCTAssertTrue(hoja.waitForNonExistence(timeout: 5), "La hoja no se cerró")
        // Vuelve a la lista del día. En iOS 26 el botón se llama "BackButton"; en 17 y 18 es el primero de la barra.
        let volver = app.navigationBars.buttons["BackButton"]
        (volver.exists ? volver : app.navigationBars.buttons.element(boundBy: 0)).tap()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS 'sustitución fijada'")).firstMatch
        for _ in 0..<6 where !card.waitForExistence(timeout: 1) { app.swipeUp() }   // la lista dibuja solo lo visible
        XCTAssertTrue(card.exists, "Ninguna card dice que está sustituida")
        let valor = card.value as? String ?? ""
        XCTAssertTrue(valor.contains("series de") && valor.contains("descanso"), "falta la pauta: \(valor)")
    }
}
