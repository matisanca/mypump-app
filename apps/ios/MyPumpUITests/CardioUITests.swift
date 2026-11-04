import XCTest

/// Reporte del 4-nov: la cinta (sin duración, `progresion: []`) pedía reps, kg y RIR y no ofrecía «Sustituir». La demo con
/// `-cardio prueba` la trae como cardio en el día 1 y como calentamiento en el día 2, y con `-historial muestra` hay
/// cargas de 60 kg × 10 en la clave de cada ejercicio (también la de la cinta). Las capturas van como adjuntos.
@MainActor
final class CardioUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno", "-captura", "YES",
                               "-cardio", "prueba", "-historial", "muestra"]
        app.launch()
        let demo = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ver demo'")).firstMatch
        if demo.waitForExistence(timeout: 3) {
            app.terminate()
            app.launch()
            if demo.waitForExistence(timeout: 3) { demo.tap() }
        }
    }

    private func captura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }

    private func abrirCinta(dia: String) {
        let d = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", dia)).firstMatch
        XCTAssertTrue(d.waitForExistence(timeout: 30), "No está el \(dia) de la demo")
        d.tap()
        let fila = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fila-ejercicio' AND label CONTAINS[c] 'Cinta'")).firstMatch
        XCTAssertTrue(fila.waitForExistence(timeout: 10), "No está la cinta en el \(dia)")
        captura("cardio-lista-\(dia)")
        fila.tap()
    }

    private func comprobarPorTiempo(_ nombre: String) {
        let termine = app.buttons["termine-ejercicio"]
        for _ in 0..<6 where !(termine.exists && termine.isHittable) { app.swipeUp() }
        XCTAssertTrue(termine.waitForExistence(timeout: 10), "\(nombre): sin «Terminé este ejercicio»")
        XCTAssertFalse(app.buttons["confirmar-serie-1"].exists, "\(nombre): pide series (reps y kg)")
        XCTAssertFalse(app.staticTexts["leyenda-rir"].exists, "\(nombre): muestra la leyenda del RIR")
        XCTAssertFalse(app.staticTexts["Este ejercicio no tiene series esta semana."].exists, "\(nombre): tabla vacía")
        // La fila de la cinta (lo que lee VoiceOver es lo que se ve): sin «última vez» ni récord de las cargas de muestra.
        let fila = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fila-ejercicio' AND label CONTAINS[c] 'Cinta'")).firstMatch
        let valor = (fila.value as? String) ?? ""
        XCTAssertFalse(valor.contains("última vez") || valor.contains("récord"), "\(nombre): \(valor)")
        XCTAssertTrue(valor.contains("cardio") || valor.contains("calentamiento"), "\(nombre): \(valor)")
        let sustituir = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sustituir'")).firstMatch
        XCTAssertTrue(sustituir.exists && sustituir.isEnabled, "\(nombre): «Sustituir» apagado")
        captura("cardio-tarjeta-\(nombre)")
    }

    func testLaCintaDeCardioVaPorTiempoYSeSustituye() {
        abrirCinta(dia: "Día 1")
        comprobarPorTiempo("cardio")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sustituir'")).firstMatch.tap()
        let bici = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Bicicleta fija'")).firstMatch
        XCTAssertTrue(bici.waitForExistence(timeout: 10), "La hoja no ofrece la bici")
        captura("cardio-sustituir")
    }

    func testLaCintaDeCalentamientoVaPorTiempo() {
        abrirCinta(dia: "Día 2")
        comprobarPorTiempo("calentamiento")
    }
}
