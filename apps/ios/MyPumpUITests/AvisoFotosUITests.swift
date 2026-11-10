import XCTest

/// El aviso de las fotos en la pestaña Revisión: sin las fotos de la semana aparece con la guía; con las tres, no.
@MainActor
final class AvisoFotosUITests: XCTestCase {
    private var app = XCUIApplication()
    private var aviso: XCUIElement { app.descendants(matching: .any)["aviso-fotos"] }

    override func setUp() async throws { continueAfterFailure = false }

    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
    }

    private func sinFotos(oscuro: Bool) {
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "revision"] + (oscuro ? ["-mypump-theme", "dark"] : [])
        app.launch()
        XCTAssertTrue(aviso.waitForExistence(timeout: 20), "Sin fotos tiene que aparecer el aviso")
        XCTAssertTrue(aviso.label.contains("Tus fotos de la semana"), aviso.label)
        XCTAssertTrue(aviso.label.contains("el celu vertical a la altura del ombligo"), aviso.label)
    }

    func testSinFotosApareceConLaGuia() { sinFotos(oscuro: false); foto("aviso-fotos-claro") }

    func testSinFotosEnModoOscuro() { sinFotos(oscuro: true); foto("aviso-fotos-oscuro") }

    func testConLasTresFotosNoAparece() throws {
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-pestana", "revision", "-sinOnboarding", "YES", "-fotosDePrueba", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Completas"].waitForExistence(timeout: 25), "No cargaron las tres fotos de la semana")
        XCTAssertFalse(aviso.exists, "Con las tres fotos el aviso no va")
        foto("aviso-fotos-con-las-tres")
    }
}
