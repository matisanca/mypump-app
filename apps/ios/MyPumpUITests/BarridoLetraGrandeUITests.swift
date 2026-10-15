import XCTest

/// Barrido visual con la letra más grande de accesibilidad: cada pantalla desplazada de a una, con una captura por paso
/// (adjuntas al resultado). No afirma nada: es para mirar. Encontró el 15-oct el total de Dieta ilegible, «Check de la
/// semana» pisado por «Enviado» y el peso en «8… kg». Corre solo con `TEST_RUNNER_MYPUMP_BARRIDO=1`:
/// `TEST_RUNNER_MYPUMP_BARRIDO=1 scripts/nativa/probar-ui.sh <udid> real -only-testing:MyPumpUITests/BarridoLetraGrandeUITests`
/// y después `xcrun xcresulttool export attachments`.
@MainActor
final class BarridoLetraGrandeUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = true
        guard ProcessInfo.processInfo.environment["MYPUMP_BARRIDO"] == "1" else { throw XCTSkip("es un barrido para mirar: TEST_RUNNER_MYPUMP_BARRIDO=1") }
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    }

    private func captura(_ nombre: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
    }

    private func recorrer(_ nombre: String, pasos: Int) {
        sleep(5)
        captura("\(nombre)-00")
        for i in 1...pasos {
            app.swipeUp(velocity: .slow)
            sleep(1)
            captura(String(format: "%@-%02d", nombre, i))
        }
    }

    private func abrir(_ args: [String]) { app.launchArguments += args; app.launch() }

    func testEntreno() { abrir(["-pestana", "entreno"]); recorrer("entreno", pasos: 10) }
    func testEjercicio() { abrir(["-pestana", "entreno", "-abrir", "ejercicio"]); recorrer("ejercicio", pasos: 8) }
    func testDieta() { abrir(["-pestana", "dieta"]); recorrer("dieta", pasos: 12) }
    func testRevision() { abrir(["-pestana", "revision"]); recorrer("revision", pasos: 12) }
    func testMisDatos() { abrir(["-pestana", "revision", "-abrir", "misdatos"]); recorrer("misdatos", pasos: 8) }
    func testProgreso() { abrir(["-pestana", "progreso"]); recorrer("progreso", pasos: 8) }
    func testChat() { abrir(["-pestana", "chat"]); sleep(5); captura("chat-00") }
}
