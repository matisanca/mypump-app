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

    /// La hoja «Sustituir» de la extensión de tríceps en polea del día 2 de la demo (la barra de la hoja).
    private func abrirSustituirDeLaExtension() -> XCUIElement {
        app.terminate()
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno"]
        app.launch()
        let dia2 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Día 2'")).firstMatch
        XCTAssertTrue(dia2.waitForExistence(timeout: 15), "No está el día 2 de la demo")
        dia2.tap()
        let fila = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fila-ejercicio' AND label CONTAINS[c] 'tríceps'")).firstMatch
        for _ in 0..<8 where !(fila.exists && fila.isHittable) { app.swipeUp() }
        XCTAssertTrue(fila.exists, "No está la extensión de tríceps del día 2")
        fila.tap()
        let sustituir = app.buttons["Sustituir"].firstMatch
        for _ in 0..<6 where !(sustituir.exists && sustituir.isHittable) { app.swipeUp() }
        sustituir.tap()
        let hoja = app.navigationBars["Sustituir ejercicio"]
        XCTAssertTrue(hoja.waitForExistence(timeout: 5), "No abrió la hoja de sustituir")
        return hoja
    }

    /// Mati, 20-oct (Eric, con la polea ocupada): a la extensión de tríceps en polea, debajo de las variantes del mismo
    /// movimiento, le aparecen los otros ejercicios de tríceps (fondos incluidos), y uno de ellos sustituye igual.
    func testLosOtrosDelMismoMusculoTambienSustituyen() throws {
        let hoja = abrirSustituirDeLaExtension()
        XCTAssertTrue(app.staticTexts["Otra variante u otro ejercicio de tríceps"].waitForExistence(timeout: 5), "El subtítulo no avisa de los otros ejercicios")
        // Primero el título (la lista es perezosa: al bajar hasta los fondos, el encabezado ya salió de la pantalla).
        let titulo = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Otros ejercicios de tríceps'")).firstMatch
        for _ in 0..<10 where !titulo.exists { app.swipeUp() }
        XCTAssertTrue(titulo.exists, "Sin el título de la sección")
        let t = XCTAttachment(screenshot: app.screenshot()); t.name = "otros-del-mismo-musculo-titulo"; t.lifetime = .keepAlways; add(t)
        let fondos = app.buttons.matching(NSPredicate(format: "identifier == 'otro-ejercicio' AND label BEGINSWITH 'Fondos'")).firstMatch
        for _ in 0..<10 where !(fondos.exists && fondos.isHittable) { app.swipeUp() }
        XCTAssertTrue(fondos.exists && fondos.isHittable, "Sin fondos entre los otros ejercicios de tríceps")
        fondos.tap()
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "otros-del-mismo-musculo"; a.lifetime = .keepAlways; add(a)
        hoja.buttons["Sustituir"].tap()
        XCTAssertTrue(hoja.waitForNonExistence(timeout: 5), "La hoja no se cerró")
        let sustituida = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fila-ejercicio' AND label CONTAINS 'Fondos'")).firstMatch
        XCTAssertTrue(sustituida.waitForExistence(timeout: 5), "El ejercicio no quedó sustituido por los fondos")
    }

    /// Revisión del 21-oct (D24, hallazgo 5): buscar «fondos» en la extensión en polea decía «Sin resultados para
    /// “fondos”» arriba de los fondos que sí había entre los otros ejercicios. Solo se dice si no hay en ninguna lista.
    func testBuscarUnOtroEjercicioNoDiceSinResultados() throws {
        _ = abrirSustituirDeLaExtension()
        let buscar = app.searchFields.firstMatch
        XCTAssertTrue(buscar.waitForExistence(timeout: 5), "Sin la búsqueda")
        buscar.tap()
        buscar.typeText("fondos")
        let fondos = app.buttons.matching(NSPredicate(format: "identifier == 'otro-ejercicio' AND label BEGINSWITH 'Fondos'")).firstMatch
        XCTAssertTrue(fondos.waitForExistence(timeout: 5), "La búsqueda no encontró los fondos")
        let sinResultados = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sin resultados'")).firstMatch
        XCTAssertFalse(sinResultados.exists, "Dice «Sin resultados» con los fondos abajo")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "buscar-fondos"; a.lifetime = .keepAlways; add(a)
        // Sin nada en ninguna de las dos, sí.
        buscar.typeText("zzz")
        XCTAssertTrue(app.staticTexts["Sin resultados para “fondoszzz”."].waitForExistence(timeout: 5), "Sin resultados en las dos y no lo dice")
        XCTAssertFalse(fondos.exists)
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
