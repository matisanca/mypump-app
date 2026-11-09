import XCTest

/// 2.0.3, Entreno en la demo con historial de muestra (`-historial muestra`: 60 kg × 10 hace 4 días en cada ejercicio):
/// la preparación (E1), el descanso elegido a mano (E2) y el aviso de récord (E3). Las capturas del boceto salen como
/// adjuntos (`v2-…`).
@MainActor
final class Entreno203UITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func lanzar(historial: Bool) {
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno", "-captura", "YES"]
            + (historial ? ["-historial", "muestra"] : [])
        app.launch()
        // A veces el primer arranque después de cambiar la apariencia queda en el acceso.
        let demo = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ver demo'")).firstMatch
        if demo.waitForExistence(timeout: 3) {
            // Quedó en el acceso: se relanza, para que valgan los argumentos (el historial de muestra).
            app.terminate()
            app.launch()
            if demo.waitForExistence(timeout: 3) { demo.tap() }
        }
    }

    /// Abre un ejercicio del día 1 de la demo por su nombre.
    private func abrir(_ nombre: String) {
        let dia1 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Día 1'")).firstMatch
        XCTAssertTrue(dia1.waitForExistence(timeout: 30), "No está el día 1 de la demo")
        dia1.tap()
        let fila = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fila-ejercicio' AND label CONTAINS[c] %@", nombre)).firstMatch
        for _ in 0..<8 where !(fila.exists && fila.isHittable) { app.swipeUp() }
        XCTAssertTrue(fila.exists, "No está «\(nombre)» en el día 1")
        fila.tap()
    }

    /// Deja el bloque de preparación arriba, debajo de la barra de título, antes de una captura (arrastres cortos).
    private func verBloque() {
        let bloque = app.otherElements["bloque-preparacion"]
        let alto = app.frame.height
        for _ in 0..<10 {
            let y = bloque.frame.minY
            let objetivo = alto * 0.2
            guard abs(y - objetivo) > alto * 0.06 else { break }
            let d = max(-0.3, min(0.3, (objetivo - y) / alto))   // en fracción de pantalla
            let desde = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            desde.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55 + d)))
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    }

    private func captura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }

    /// E1: el remo con barra (primer compuesto de su músculo y principal) lleva calentamiento en barra sola, dos
    /// aproximaciones y la potenciación opcional, con el kg de la última vez; el kg sigue en vivo al que se escribe en la
    /// primera efectiva; tocar una fila arranca el descanso de 30 s; «Ocultar» lo esconde. E3: confirmar más kg que la
    /// última vez avisa el récord.
    func testPreparacionDelCompuestoYRecord() throws {
        lanzar(historial: true)
        abrir("Remo con barra")
        let bloque = app.otherElements["bloque-preparacion"]
        XCTAssertTrue(bloque.waitForExistence(timeout: 10), "No está la preparación")
        let filas = (1...4).map { app.buttons["preparacion-\($0)"] }
        XCTAssertTrue(filas[0].label.hasPrefix("Calentamiento") && filas[0].label.contains("Barra sola"), filas[0].label)
        XCTAssertTrue(filas[1].label.hasPrefix("Aproximación 1") && filas[1].label.contains("35 kilos"), filas[1].label)
        XCTAssertTrue(filas[2].label.hasPrefix("Aproximación 2") && filas[2].label.contains("50 kilos"), filas[2].label)
        XCTAssertTrue(filas[3].label.hasPrefix("Potenciación (opcional)") && filas[3].label.contains("65 kilos"), filas[3].label)
        XCTAssertTrue(app.staticTexts["Series efectivas"].exists, "Sin el título de las efectivas")
        // Sin RIR: todo al fallo.
        XCTAssertFalse(app.staticTexts["RIR"].exists, "Quedó la columna de RIR")
        let leyenda = app.staticTexts["leyenda-rir"]
        XCTAssertTrue(leyenda.exists && (leyenda.label == "Al fallo"), leyenda.label)
        captura("v2-compuesto-con-kg")

        // Tocar una fila: queda hecha y arranca el descanso corto.
        filas[0].tap()
        // Que asiente (arranca el descanso abajo y la fila se atenúa) antes de tocar la otra.
        let hecha = NSPredicate(format: "label ENDSWITH 'hecha'")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: hecha, evaluatedWith: app.buttons["preparacion-1"])], timeout: 3), .completed)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        filas[1].tap()
        XCTAssertTrue(app.otherElements["descanso-en-tarjeta"].waitForExistence(timeout: 5), "No arrancó el descanso")
        XCTAssertTrue(app.staticTexts["Descanso / 0:30"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '0:30'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["preparacion-2"].label.hasSuffix("hecha"), app.buttons["preparacion-2"].label)
        XCTAssertTrue(app.buttons["preparacion-1"].label.hasSuffix("hecha"), app.buttons["preparacion-1"].label)
        app.otherElements["descanso-en-tarjeta"].buttons["Saltar descanso"].tap()
        verBloque()
        captura("v2-dos-tocadas")

        // El kg en vivo: 62,5 en la primera efectiva → la aproximación al 60 % pasa a 37,5.
        app.fijarCarga("62,5")
        XCTAssertTrue(app.buttons["preparacion-2"].label.contains("37,5 kilos"), app.buttons["preparacion-2"].label)

        // E3: confirmar 62,5 × 10 contra 60 × 10 de la última vez. Con otra carga la base es la del plan.
        app.fijarReps(10)
        app.darOK()
        let aviso = app.descendants(matching: .any)["aviso-record"]
        XCTAssertTrue(aviso.waitForExistence(timeout: 5), "No avisó el récord")
        XCTAssertTrue(aviso.label.contains("Récord: +2,5 kg"), aviso.label)
        captura("record-aviso")

        // «Ocultar» y «Mostrar».
        let ocultar = app.buttons["ocultar-preparacion"]
        for _ in 0..<4 where !(ocultar.exists && ocultar.isHittable) { app.swipeDown() }
        ocultar.tap()
        XCTAssertTrue(app.buttons["preparacion-1"].waitForNonExistence(timeout: 3), "«Ocultar» no la escondió")
        XCTAssertTrue(app.staticTexts["Calentamiento y aproximación · 4"].exists, "Sin la línea colapsada")
        verBloque()
        captura("v2-colapsado")
        ocultar.tap()
        XCTAssertTrue(app.buttons["preparacion-1"].waitForExistence(timeout: 3), "«Mostrar» no la volvió a poner")
    }

    /// E1, capturas del boceto: el monoarticular (una sola aproximación) y el compuesto sin historial (solo reps).
    func testBocetoMonoarticularYSinKg() throws {
        lanzar(historial: true)
        abrir("Curl con barra Z")
        XCTAssertTrue(app.otherElements["bloque-preparacion"].waitForExistence(timeout: 10), "No está la preparación del curl")
        XCTAssertTrue(app.buttons["preparacion-1"].label.hasPrefix("Aproximación"), app.buttons["preparacion-1"].label)
        XCTAssertFalse(app.buttons["preparacion-2"].exists, "El monoarticular lleva una sola")
        captura("v2-monoarticular")

        app.terminate()
        lanzar(historial: false)
        abrir("Remo con barra")
        XCTAssertTrue(app.otherElements["bloque-preparacion"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Usalas para encontrar tu peso de trabajo · 30 s entre cada una"].exists, "Sin el texto de la primera vez")
        captura("v2-sin-kg")
        app.buttons["ayuda-preparacion"].tap()
        XCTAssertTrue(app.navigationBars["Antes de las efectivas"].waitForExistence(timeout: 3))
        RunLoop.current.run(until: Date().addingTimeInterval(1))   // que termine de subir la hoja
        captura("v2-ayuda")
    }

    /// E2: tocar el descanso del ejercicio, elegir otro, y que sea el que arranca al confirmar; «Volver al del plan».
    func testDescansoElegidoPorEjercicio() throws {
        lanzar(historial: true)
        abrir("Remo con barra")
        let descanso = app.buttons["descanso-ejercicio"]
        XCTAssertTrue(descanso.waitForExistence(timeout: 10), "El descanso del ejercicio no se toca")
        descanso.tap()
        let rueda = app.pickerWheels.firstMatch
        XCTAssertTrue(rueda.waitForExistence(timeout: 3))
        rueda.adjust(toPickerWheelValue: "2:15")
        app.buttons["guardar-descanso"].tap()
        XCTAssertTrue(descanso.label.contains("2:15"), descanso.label)
        app.darOK()   // lo de la última vez, de un toque
        let tarjeta = app.otherElements["descanso-en-tarjeta"]
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 5))
        XCTAssertTrue(tarjeta.staticTexts.matching(NSPredicate(format: "label CONTAINS '2:15'")).firstMatch.exists, "No arrancó con 2:15")
        tarjeta.buttons["Saltar descanso"].tap()
        descanso.tap()
        app.buttons["descanso-del-plan"].tap()
        XCTAssertFalse(descanso.label.contains("2:15"), descanso.label)
    }
}
