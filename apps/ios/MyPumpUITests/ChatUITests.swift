import XCTest

/// Chat con la cuenta de prueba (`TEST_RUNNER_MYPUMP_TOKEN`, nunca un cliente). No manda nada: solo escribe.
@MainActor
final class ChatUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-pestana", "chat", "-sinOnboarding", "YES"]
        app.launch()
    }

    /// CHA-02: nunca sale un mensaje de más de 1000 caracteres (la web corta con `maxlength`). Acá no se recorta mientras
    /// se escribe, porque SwiftUI dejaba un carácter de más a la vista que se perdía al mandar: se ve el contador en rojo
    /// y Enviar se apaga hasta que vuelva a entrar.
    func testUnMensajeDeMasDeMilNoSale() throws {
        // Por el identificador, sea campo o vista de texto: elegir el tipo antes de que cargue la pantalla fallaba en iOS 17
        // (todavía no existía ninguno y quedaba esperando el que no era).
        let campo = app.descendants(matching: .any).matching(identifier: "chat-campo").firstMatch
        XCTAssertTrue(campo.waitForExistence(timeout: 20), "No apareció el campo del chat")
        // Un solo toque y a escribir: si el toque no le diera el foco, typeText falla ("no keyboard focus"), que es lo que le
        // pasaría al cliente.
        campo.tap()
        esperarFoco(campo)
        campo.typeText(String(repeating: "a", count: 1001))
        let enviar = app.buttons["chat-enviar"]
        let contador = app.staticTexts["chat-contador"]
        XCTAssertTrue(contador.waitForExistence(timeout: 3), "no se ve el contador")
        XCTAssertEqual(contador.label, "Te pasaste: 1.001 de 1.000 caracteres")
        XCTAssertFalse(enviar.isEnabled, "con 1001 se podía mandar")
        campo.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(enviar.isEnabled, "con 1000 no se podía mandar")
        XCTAssertEqual(contador.label, "1.000 de 1.000 caracteres")
    }

    /// El campo de varias líneas toma el toque solo cerca del texto. En el iPad, tocar el medio del campo vacío no hacía
    /// nada, y en cualquier equipo tampoco el borde de la cápsula, que es la mitad de su alto (15-oct). Ahora todo el
    /// vidrio lleva al campo, sin quitarle sus propios toques: mover el cursor sigue andando.
    func testTodoElVidrioLlevaAlCampo() throws {
        let campo = app.descendants(matching: .any).matching(identifier: "chat-campo").firstMatch
        XCTAssertTrue(campo.waitForExistence(timeout: 20), "No apareció el campo del chat")
        // El borde de arriba de la cápsula, fuera del campo.
        campo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.4)).tap()
        esperarFoco(campo)
        campo.typeText("hola mundo")
        // Un toque al principio del texto deja el cursor ahí.
        campo.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 2, dy: 0)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        campo.typeText("X")
        XCTAssertEqual(campo.value as? String, "Xhola mundo")
    }

    /// Antes de escribir, hasta 3 s para que el foco se asiente (en 17.5 escribía antes y fallaba). En el iPad
    /// `hasKeyboardFocus` puede no informarse aunque el campo tenga el foco: la prueba de verdad es que typeText escriba.
    private func esperarFoco(_ campo: XCUIElement) {
        let limite = Date().addingTimeInterval(3)
        while !(campo.value(forKey: "hasKeyboardFocus") as? Bool ?? false) && Date() < limite {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }
}
