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
        let campo = app.textViews["chat-campo"].exists ? app.textViews["chat-campo"] : app.textFields["chat-campo"]
        XCTAssertTrue(campo.waitForExistence(timeout: 20), "No apareció el campo del chat")
        campo.tap()
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
}
