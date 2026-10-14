import XCTest

/// La bienvenida: demo sin red ni cuenta, un link que no es de MyPump y entrar pegando el link de la cuenta de prueba.
@MainActor
final class AccesoUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-reiniciar", "YES"]
        app.launch()
    }

    func testLaDemoEntraYSaleSinCuenta() throws {
        let demo = app.buttons["ver-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10), "No apareció la bienvenida")
        adjuntarCaptura("bienvenida")
        demo.tap()
        XCTAssertTrue(app.staticTexts["Estás viendo la demo"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Dieta"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reemplazar ")).firstMatch.waitForExistence(timeout: 5),
                      "La dieta de ejemplo no se ve en la demo")
        adjuntarCaptura("demo-dieta")
        app.buttons["salir-demo"].tap()
        XCTAssertTrue(demo.waitForExistence(timeout: 5), "Salir de la demo no volvió a la bienvenida")
    }

    func testUnLinkQueNoEsDeMyPumpAvisa() throws {
        let campo = app.textFields["campo-link"]
        XCTAssertTrue(campo.waitForExistence(timeout: 10))
        campo.tap()
        campo.typeText("hola")
        app.buttons["entrar"].tap()
        XCTAssertTrue(app.staticTexts["Eso no parece un link de MyPump. Copiá el link entero que te pasó Mati."].waitForExistence(timeout: 3))
    }

    func testEntrarPegandoElLinkDeLaCuentaDePrueba() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        let campo = app.textFields["campo-link"]
        XCTAssertTrue(campo.waitForExistence(timeout: 10))
        campo.tap()
        campo.typeText("https://app.mypumpteam.com/?t=\(token)")
        app.buttons["entrar"].tap()
        XCTAssertTrue(app.tabBars.buttons["Dieta"].waitForExistence(timeout: 20), "No entró a la cuenta")
        // Quedó guardado: al reabrir (sin reiniciar) entra solo.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dieta"].waitForExistence(timeout: 20), "El token no quedó guardado")
        // Limpieza: la próxima corrida arranca sin cuenta.
        app.terminate()
        app.launchArguments = ["-reiniciar", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["ver-demo"].waitForExistence(timeout: 10))
    }

    private func adjuntarCaptura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
