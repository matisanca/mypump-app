import XCTest

/// Revisión tocada de verdad contra el backend. Corre SOLO con una cuenta de prueba: el token llega por
/// `TEST_RUNNER_MYPUMP_TOKEN` (ej.: `scripts/nativa/probar-ui.sh <udid> real`), nunca escrito en el repo.
@MainActor
final class RevisionUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-pestana", "revision", "-sinOnboarding", "YES"]
        app.launch()
    }

    /// Pedido de Mati (14-oct): ni la IA ni el aviso del domingo son algo que el cliente configure. La IA trabaja bajo
    /// su aprobación y el recordatorio llega como un mensaje suyo: en Mis datos no hay interruptores de ninguno de los dos.
    func testMisDatosNoTieneInterruptorDeIANiDeRecordatorios() throws {
        let misDatos = app.buttons["Mis datos"].firstMatch
        XCTAssertTrue(misDatos.waitForExistence(timeout: 20), "No apareció el acceso a Mis datos")
        misDatos.tap()
        let respaldo = app.buttons["Respaldo científico del plan"].firstMatch
        XCTAssertTrue(app.navigationBars["Mis datos"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !respaldo.isHittable { app.swipeUp() }
        XCTAssertTrue(respaldo.exists, "No se recorrió Mis datos")
        XCTAssertFalse(app.switches["asistente-ia"].exists, "Volvió el interruptor de la IA")
        XCTAssertFalse(app.switches["recordatorio-domingo"].exists, "Volvió el interruptor del recordatorio")
        XCTAssertFalse(app.staticTexts["Inteligencia artificial"].exists)
        adjuntarCaptura("mis-datos-sin-interruptores")
    }

    /// Pedidos de Mati (15-oct): Revisión sin Mi día (sin el agua, los hábitos ni los últimos 30 días) y el peso como
    /// parte del check («Tu peso de hoy»), con la tarjeta de peso para los demás días.
    func testRevisionSinMiDiaYConElPesoEnElCheck() throws {
        let enviar = app.buttons["enviar-check"].firstMatch
        XCTAssertTrue(enviar.waitForExistence(timeout: 20), "No apareció el check")
        for _ in 0..<6 where !app.textFields["peso-check"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.textFields["peso-check"].exists, "El check no trae el peso")
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(app.otherElements["control-agua"].exists, "Volvió el agua de Mi día")
        XCTAssertFalse(app.staticTexts["Mi día"].exists, "Volvió Mi día")
        XCTAssertFalse(app.staticTexts["Mis últimos 30 días"].exists, "Volvieron los últimos 30 días")
        adjuntarCaptura("revision-sin-mi-dia")
    }

    /// 5.1.1(i) y 1.4.1: desde Mis datos se abren el respaldo científico y la política de privacidad. Las dos hojas
    /// cuelgan de la misma vista, así que vale correrlo también en iOS 17.
    func testMisDatosAbreElRespaldoYLaPolitica() throws {
        let misDatos = app.buttons["Mis datos"].firstMatch
        XCTAssertTrue(misDatos.waitForExistence(timeout: 20), "No apareció el acceso a Mis datos")
        misDatos.tap()
        let respaldo = app.buttons["Respaldo científico del plan"].firstMatch
        for _ in 0..<6 where !respaldo.isHittable { app.swipeUp() }
        XCTAssertTrue(respaldo.isHittable, "No está el respaldo en Mis datos")
        respaldo.tap()
        XCTAssertTrue(app.navigationBars["Respaldo científico"].waitForExistence(timeout: 5), "El respaldo no se abrió")
        app.buttons["Listo"].tap()
        XCTAssertTrue(app.navigationBars["Respaldo científico"].waitForNonExistence(timeout: 5))
        let politica = app.buttons["Política de privacidad"].firstMatch
        XCTAssertTrue(politica.waitForExistence(timeout: 3))
        politica.tap()
        // SFSafariViewController con el botón de cerrar (el contenido corre en otro proceso).
        let cerrar = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cerrar", "Close", "OK", "Listo"])).firstMatch
        XCTAssertTrue(cerrar.waitForExistence(timeout: 10), "La política de privacidad no se abrió")
        adjuntarCaptura("politica-de-privacidad")
        cerrar.tap()
    }

    /// REV-04: con 4 semanas o más de fotos, «Ver mis fotos» abre la galería por semana con el comparador «Antes y ahora»
    /// arriba. Las fotos son de prueba (`-fotosDePrueba`, solo Debug): la ventana del servidor no deja sembrar semanas viejas.
    func testLaGaleriaConCincoSemanasTraeElComparador() throws {
        app.terminate()
        app.launchArguments += ["-fotosDePrueba", "YES"]
        app.launch()
        let ver = app.buttons["Ver mis fotos · 5 semanas"].firstMatch
        XCTAssertTrue(ver.waitForExistence(timeout: 20), "No apareció «Ver mis fotos» con las 5 semanas")
        let alto = app.windows.firstMatch.frame.maxY
        for _ in 0..<10 where !(ver.isHittable && ver.frame.maxY < alto - 180) { app.swipeUp() }
        ver.tap()
        XCTAssertTrue(app.staticTexts["Antes y ahora"].waitForExistence(timeout: 10), "El comparador no está arriba de la galería")
        sleep(2)   // que bajen las imágenes
        adjuntarCaptura("comparador-5-semanas")
    }

    /// El botón dice "marcado" en su valor de accesibilidad (`isSelected` no llega desde un botón de SwiftUI).
    private func marcado(_ e: XCUIElement) -> Bool { (e.value as? String) == "marcado" }

    private func esperar(_ e: XCUIElement, seleccionado: Bool, timeout: TimeInterval = 4) -> Bool {
        let fin = Date().addingTimeInterval(timeout)
        while Date() < fin {
            if marcado(e) == seleccionado { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return marcado(e) == seleccionado
    }

    private func adjuntarCaptura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
