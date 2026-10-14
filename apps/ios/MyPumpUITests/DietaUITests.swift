import XCTest

/// Dieta tocada de verdad en el simulador: la mano y el reemplazo de alimentos, de punta a punta contra el backend.
/// Corre SOLO con una cuenta de prueba: el token llega por `TEST_RUNNER_MYPUMP_TOKEN` (xcodebuild le saca el prefijo),
/// nunca escrito en el repo. Ej.: `scripts/nativa/probar-ui.sh <udid> real`.
@MainActor
final class DietaUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-pestana", "dieta"]
        app.launch()
    }

    func testLaManoMuestraYOcultaLaPorcionCasera() throws {
        let mano = app.buttons["Ver porción casera"].firstMatch
        XCTAssertTrue(mano.waitForExistence(timeout: 20), "No apareció ningún botón de porción casera")
        mano.tap()
        let porcion = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Porción casera:")).firstMatch
        XCTAssertTrue(porcion.waitForExistence(timeout: 3), "La mano no mostró la porción casera")
        adjuntarCaptura("mano-abierta")
        let ocultar = app.buttons["Ocultar porción casera"].firstMatch
        XCTAssertTrue(ocultar.exists)
        ocultar.tap()
        XCTAssertTrue(porcion.waitForNonExistence(timeout: 3), "La mano no ocultó la porción casera")
    }

    func testReemplazarUnAlimentoYVolverAlDelPlan() throws {
        let reemplazar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reemplazar ")).firstMatch
        XCTAssertTrue(reemplazar.waitForExistence(timeout: 20), "No apareció ningún botón de reemplazo")
        let original = String(reemplazar.label.dropFirst("Reemplazar ".count))
        reemplazar.tap()

        let primero = app.buttons.matching(identifier: "sustituto").firstMatch
        XCTAssertTrue(primero.waitForExistence(timeout: 5), "La hoja de reemplazo no mostró opciones para \(original)")
        adjuntarCaptura("hoja-reemplazo")
        primero.tap()
        let confirmar = app.buttons["confirmar-reemplazo"]
        XCTAssertTrue(confirmar.isEnabled, "Elegir una opción no habilitó el botón de reemplazar")
        let nuevo = confirmar.label.replacingOccurrences(of: "Reemplazar por ", with: "")
        confirmar.tap()

        let distintivo = app.buttons["Reemplazado. Tocá para volver a \(original)"].firstMatch
        XCTAssertTrue(distintivo.waitForExistence(timeout: 5), "No quedó marcado el reemplazo de \(original) por \(nuevo)")
        XCTAssertTrue(app.staticTexts[nuevo].firstMatch.exists, "La fila no muestra \(nuevo)")
        adjuntarCaptura("reemplazado")

        // Sobrevive a cerrar y abrir la app (quedó en disco y en la cola).
        app.terminate()
        app.launch()
        XCTAssertTrue(distintivo.waitForExistence(timeout: 20), "El reemplazo no sobrevivió a reabrir la app")

        distintivo.tap()
        let volver = app.buttons["Volver a \(original)"].firstMatch
        XCTAssertTrue(volver.waitForExistence(timeout: 3))
        volver.tap()
        XCTAssertTrue(distintivo.waitForNonExistence(timeout: 5), "No volvió a \(original)")
        adjuntarCaptura("revertido")
    }

    func testComidaLibreAManoSeRegistraYSeBorra() throws {
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reemplazar ")).firstMatch.waitForExistence(timeout: 20))
        // Está al pie de una lista perezosa: no existe hasta que se llega con el scroll.
        let aMano = app.buttons["A mano"].firstMatch
        for _ in 0..<12 where !aMano.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(aMano.isHittable, "No apareció la sección de comidas libres")
        aMano.tap()
        let descripcion = app.textFields["Ej: Milanesa con puré"]
        XCTAssertTrue(descripcion.waitForExistence(timeout: 5))
        descripcion.tap()
        descripcion.typeText("Prueba UI alfajor")
        let kcal = app.textFields.matching(identifier: "kcal-comida-libre").firstMatch
        XCTAssertTrue(kcal.exists)
        kcal.tap()
        kcal.typeText("250")
        adjuntarCaptura("comida-libre-form")
        app.buttons["Registrar"].tap()
        let fila = app.staticTexts["Prueba UI alfajor"]
        XCTAssertTrue(fila.waitForExistence(timeout: 10), "La comida libre no apareció en la lista")
        for _ in 0..<6 where !app.buttons["Borrar Prueba UI alfajor"].isHittable { app.swipeUp() }
        adjuntarCaptura("comida-libre-lista")
        app.buttons["Borrar Prueba UI alfajor"].tap()
        XCTAssertTrue(fila.waitForNonExistence(timeout: 10), "La comida libre no se borró")
    }

    private func adjuntarCaptura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
