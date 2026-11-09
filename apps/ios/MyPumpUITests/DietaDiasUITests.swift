import XCTest

/// Cargar días anteriores y copiar a hoy, tocado en el simulador contra el backend con una cuenta de prueba
/// (`TEST_RUNNER_MYPUMP_TOKEN`, nunca escrito en el repo). Deja la cuenta como la encontró: lo que marca, lo desmarca.
@MainActor
final class DietaDiasUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-pestana", "dieta", "-sinOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(botones("comi-").firstMatch.waitForExistence(timeout: 25), "No cargó Dieta")
    }

    private func botones(_ prefijo: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefijo))
    }

    private var chips: XCUIElementQuery { botones("dia-20") }
    private var banner: XCUIElement { app.descendants(matching: .any)["banner-dia-pasado"] }
    private var volver: XCUIElement { app.buttons["volver-a-hoy"] }

    private func irAAyer() {
        let ayer = chips.element(boundBy: 1)
        XCTAssertTrue(ayer.waitForExistence(timeout: 5), "No está la tira de días")
        ayer.tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "No apareció el aviso de otro día")
        XCTAssertTrue(botones("comi-").firstMatch.waitForExistence(timeout: 15), "No cargó el día anterior")
    }

    private func dejar(_ b: XCUIElement, activo: Bool) {
        scrollHasta(b)
        if b.isSelected != activo { b.tap() }
        let p = NSPredicate(format: "selected == %@", NSNumber(value: activo))
        expectation(for: p, evaluatedWith: b)
        waitForExpectations(timeout: 8)
    }

    private func scrollHasta(_ b: XCUIElement) {
        // La lista es perezosa: lo que no se llegó a dibujar todavía no existe.
        for _ in 0..<8 where !(b.exists && b.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(b.exists && b.isHittable, "\(b.identifier) no se pudo tocar")
    }

    private func arriba() {
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
    }

    /// Los ids de las dos primeras comidas del plan.
    private func comidas() -> [String] {
        (0..<2).map { String(botones("comi-").element(boundBy: $0).identifier.dropFirst("comi-".count)) }
    }

    func testAbreEnHoyMuestraElAvisoYVuelve() {
        XCTAssertTrue(chips.element(boundBy: 0).isSelected, "No abrió en hoy")
        XCTAssertFalse(banner.exists)
        irAAyer()
        XCTAssertTrue(chips.element(boundBy: 1).isSelected)
        XCTAssertTrue(app.staticTexts["dia-rotulo"].exists)
        volver.tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5), "No volvió a hoy")
        XCTAssertTrue(chips.element(boundBy: 0).isSelected)
    }

    func testAyerSeMarcaSinTocarHoyYSobrevive() {
        let id = comidas()[0]
        dejar(app.buttons["comi-\(id)"], activo: false)
        arriba()
        irAAyer()
        let comi = app.buttons["comi-\(id)"]
        dejar(comi, activo: true)
        arriba()
        volver.tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["comi-\(id)"].isSelected, "Marcar ayer tocó hoy")
        // Al volver a ayer sigue marcada (viene del servidor o de la cola).
        irAAyer()
        XCTAssertTrue(app.buttons["comi-\(id)"].isSelected, "No quedó la marca de ayer")
        dejar(app.buttons["comi-\(id)"], activo: false)
    }

    func testCopiarDeAyerPreguntaAntesDePisarYCapturas() throws {
        let ids = comidas()
        // Ayer: comió las dos. Hoy: en la primera marcó «Salté» (no se puede pisar sin preguntar), la segunda libre.
        dejar(app.buttons["salte-\(ids[0])"], activo: true)
        dejar(app.buttons["comi-\(ids[1])"], activo: false)
        arriba()
        guardar("selector")
        irAAyer()
        dejar(app.buttons["comi-\(ids[0])"], activo: true)
        dejar(app.buttons["comi-\(ids[1])"], activo: true)
        arriba()
        guardar("dia-anterior")
        volver.tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        arriba()

        let abrir = app.buttons["copiar-de-otro-dia"]
        scrollHasta(abrir)
        abrir.tap()
        let conflicto = app.buttons["copiar-item-\(ids[0])"]
        let nueva = app.buttons["copiar-item-\(ids[1])"]
        XCTAssertTrue(conflicto.waitForExistence(timeout: 10), "La hoja no mostró las comidas")
        XCTAssertFalse(conflicto.isSelected, "Lo que pisa algo de hoy no viene tildado")
        XCTAssertTrue(nueva.isSelected, "Lo nuevo viene tildado")
        sleep(1)
        guardar("copiar")
        conflicto.tap()
        app.buttons["copiar-confirmar"].tap()
        XCTAssertTrue(app.buttons["Reemplazar y copiar"].waitForExistence(timeout: 3), "No preguntó antes de reemplazar")
        // No se reemplaza: se cancela y se copia solo lo nuevo.
        app.buttons["Cancelar"].firstMatch.tap()
        conflicto.tap()
        app.buttons["copiar-confirmar"].tap()
        XCTAssertTrue(nueva.waitForNonExistence(timeout: 8), "La hoja no se cerró")
        XCTAssertTrue(app.buttons["salte-\(ids[0])"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["salte-\(ids[0])"].isSelected, "Se pisó lo que había hoy")
        scrollHasta(app.buttons["comi-\(ids[1])"])
        XCTAssertTrue(app.buttons["comi-\(ids[1])"].isSelected, "No se copió la segunda comida")

        // Deja la cuenta como estaba.
        dejar(app.buttons["comi-\(ids[1])"], activo: false)
        arriba()   // la lista es perezosa: la primera comida ya no existe si se bajó
        dejar(app.buttons["salte-\(ids[0])"], activo: false)
        arriba()
        irAAyer()
        dejar(app.buttons["comi-\(ids[0])"], activo: false)
        dejar(app.buttons["comi-\(ids[1])"], activo: false)
    }

    private func guardar(_ nombre: String) {
        let e = ProcessInfo.processInfo.environment
        guard let dir = e["CAPTURAS_DIA"], let tema = e["CAPTURAS_TEMA"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/iphone-17-pro-\(nombre)-\(tema).png"))
    }
}
