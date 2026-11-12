import XCTest

/// La videollamada (2.3.0): la tarjeta fija arriba de Entreno, «Entrar» apagado con la cuenta regresiva y activo desde 10
/// minutos antes, y con la palanca `elegir_horario` (`-elegirHorario YES`) la pantalla para elegir y cambiar el horario.
/// Servidor de mentira (`-agendaDemo`, `ServidorAgendaUI`): nunca toca la base ni crea un Meet. Con `AGENDA_CAPTURAS` en el
/// entorno del runner deja `ios-videollamada-<nombre>[-oscuro].png`.
@MainActor
final class VideollamadaUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws { continueAfterFailure = false }

    private func abrir(_ escenario: String, oscuro: Bool = false, palanca: Bool = true, _ extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-bocetos", "YES", "-agendaDemo", escenario, "-sinOnboarding", "YES", "-pestana", "entreno",
                               "-elegirHorario", palanca ? "YES" : "NO", "-mypump-theme", oscuro ? "dark" : "light"] + extra
        app.launch()
    }

    private func id(_ i: String) -> XCUIElement { app.descendants(matching: .any)[i].firstMatch }

    private func captura(_ nombre: String, oscuro: Bool) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let s = XCUIScreen.main.screenshot()
        let n = "videollamada-\(nombre)\(oscuro ? "-oscuro" : "")"
        let a = XCTAttachment(screenshot: s); a.name = n; a.lifetime = .keepAlways; add(a)
        guard let dir = ProcessInfo.processInfo.environment["AGENDA_CAPTURAS"], !dir.isEmpty else { return }
        let sufijo = ProcessInfo.processInfo.environment["AGENDA_SUFIJO"] ?? ""
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ios-\(n)\(sufijo).png"))
    }

    /// Elegir: la tarjeta «Agendá tu videollamada» arriba de Entreno, la pantalla con los días y 10/12, la confirmación y,
    /// de vuelta en Entreno, la tarjeta fija con «Entrar» apagado.
    func testElegirConfirmarYTarjeta() throws {
        for oscuro in [false, true] {
            abrir("elegir", oscuro: oscuro)
            let agendar = app.buttons["videollamada-elegir"]
            XCTAssertTrue(agendar.waitForExistence(timeout: 40), "No está «Elegir horario» en Entreno")
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'entrega'")).firstMatch.exists, "Nunca «entrega»")
            agendar.tap()
            XCTAssertTrue(id("horario-titulo").waitForExistence(timeout: 5))
            let confirmar = app.buttons["horario-confirmar"]
            XCTAssertFalse(confirmar.isEnabled, "Sin horario elegido no se confirma")
            app.buttons["horario-franja-f3"].tap()
            XCTAssertTrue(confirmar.isEnabled)
            XCTAssertTrue(confirmar.label.hasPrefix("Confirmar "), confirmar.label)
            captura("elegir", oscuro: oscuro)
            confirmar.tap()
            XCTAssertTrue(id("horario-listo").waitForExistence(timeout: 45), "No llegó a «Listo, quedó agendada»")
            captura("confirmacion", oscuro: oscuro)
            app.buttons["horario-listo-cerrar"].tap()
            XCTAssertTrue(id("videollamada").waitForExistence(timeout: 10), "No quedó la tarjeta fija")
            XCTAssertTrue(app.buttons["videollamada-entrar-apagado"].exists)
            XCTAssertFalse(app.buttons["videollamada-entrar-apagado"].isEnabled)
        }
    }

    /// Días antes: fecha, hora, «Vas a entrar a la videollamada desde acá», «Entrar» apagado con «Se habilita…», ayuda y
    /// el cambio de horario con tope.
    func testTarjetaDiasAntesYCambio() throws {
        for oscuro in [false, true] {
            abrir("diasAntes", oscuro: oscuro)
            XCTAssertTrue(id("videollamada").waitForExistence(timeout: 40))
            XCTAssertTrue(id("videollamada-desde-aca").exists)
            XCTAssertTrue(id("videollamada-cuenta").exists)
            XCTAssertFalse(app.buttons["agenda-entrar"].exists, "Días antes no se puede entrar")
            captura("dias-antes", oscuro: oscuro)
            app.buttons["videollamada-como-entro"].tap()
            XCTAssertTrue(id("videollamada-ayuda").waitForExistence(timeout: 5))
            captura("dias-antes-ayuda", oscuro: oscuro)
            if oscuro { continue }
            let cambiar = app.buttons["videollamada-cambiar"]
            if !cambiar.isHittable { app.swipeUp() }
            XCTAssertTrue(cambiar.waitForExistence(timeout: 5), "Con cambio disponible está «Cambiar horario»")
            cambiar.tap()
            XCTAssertTrue(id("horario-ahora-es").waitForExistence(timeout: 5))
            app.buttons["horario-franja-f6"].tap()
            captura("cambiar", oscuro: oscuro)
            app.buttons["horario-confirmar"].tap()
            XCTAssertTrue(id("horario-listo").waitForExistence(timeout: 45))
            app.buttons["horario-listo-cerrar"].tap()
            XCTAssertTrue(id("videollamada").waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["videollamada-cambiar"].exists, "Sin cambios restantes no se ofrece otro")
        }
    }

    /// 10 minutos antes: verde lleno, «Ya podés entrar», «Entrar a la videollamada» activo y la aclaración de la sala.
    func testEntrarActivoDiezMinutosAntes() throws {
        for oscuro in [false, true] {
            abrir("porEntrar", oscuro: oscuro)
            let entrar = app.buttons["agenda-entrar"]
            XCTAssertTrue(entrar.waitForExistence(timeout: 40), "A 6 minutos «Entrar» tiene que estar activo")
            XCTAssertTrue(entrar.isEnabled)
            XCTAssertTrue(id("videollamada-admite").exists)
            captura("entrar", oscuro: oscuro)
        }
    }

    /// 2.3.1: debajo de «Entrar» siempre está el código de la reunión con «Copiar código», y «Entrar» abre la reunión
    /// DENTRO de la app (SFSafariViewController), sin pasar por Gmail ni por Safari: MyPump sigue adelante.
    func testCodigoYEntrarDentroDeLaApp() throws {
        for oscuro in [false, true] {
            abrir("porEntrar", oscuro: oscuro)
            let entrar = app.buttons["agenda-entrar"]
            XCTAssertTrue(entrar.waitForExistence(timeout: 40))
            let codigo = id("videollamada-codigo")
            XCTAssertTrue(codigo.exists, "El código tiene que estar a la vista debajo de «Entrar»")
            XCTAssertTrue(codigo.label.contains("Código de la reunión"))
            XCTAssertTrue(app.staticTexts["abc-defg-hij"].exists || codigo.label.contains("a b c"))
            let conTexto = { (t: String) in self.app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch }
            XCTAssertTrue(conTexto("Si no se abre la reunión:").exists, "Los pasos para pegar el código")
            XCTAssertTrue(conTexto("Unirse con un código").exists)
            let copiar = app.buttons["videollamada-copiar-codigo"]
            XCTAssertTrue(copiar.label.contains("Copiar código"))
            copiar.tap()
            XCTAssertTrue(app.buttons["videollamada-copiar-codigo"].label.contains("Código copiado"))
            captura("codigo-copiado", oscuro: oscuro)
            entrar.tap()
            // El navegador de adentro de la app: su barra de abajo y la página; MyPump no pasa a segundo plano.
            RunLoop.current.run(until: Date().addingTimeInterval(4))
            XCTAssertEqual(app.state, .runningForeground, "«Entrar» no tiene que sacar al alumno de la app")
            XCTAssertFalse(entrar.isHittable, "La reunión se abre encima de la tarjeta")
            captura("reunion-adentro", oscuro: oscuro)
        }
    }

    /// Sin la palanca: no hay «Elegir horario» en Entreno (la agenda de la guía queda como en la 2.2.0), pero la tarjeta
    /// fija de una reserva confirmada sí está (no cambia datos).
    func testSinPalanca() throws {
        abrir("elegir", palanca: false)
        XCTAssertFalse(app.buttons["videollamada-elegir"].waitForExistence(timeout: 8))
        abrir("diasAntes", palanca: false)
        XCTAssertTrue(id("videollamada").waitForExistence(timeout: 40))
        XCTAssertFalse(app.buttons["videollamada-cambiar"].exists, "Sin la palanca no se cambia desde la app")
    }

    /// Letra grande: la tarjeta y la pantalla de elegir no se cortan.
    func testLetraGrande() throws {
        abrir("diasAntes", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(id("videollamada").waitForExistence(timeout: 40))
        captura("dias-antes-letra-grande", oscuro: false)
        abrir("porEntrar", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(app.buttons["agenda-entrar"].waitForExistence(timeout: 40))
        app.swipeUp()
        XCTAssertTrue(app.buttons["videollamada-copiar-codigo"].isHittable)
        captura("codigo-letra-grande", oscuro: false)
        abrir("elegir", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        let agendar = app.buttons["videollamada-elegir"]
        XCTAssertTrue(agendar.waitForExistence(timeout: 40))
        agendar.tap()
        XCTAssertTrue(app.buttons["horario-franja-f1"].waitForExistence(timeout: 5))
        app.buttons["horario-franja-f1"].tap()
        captura("elegir-letra-grande", oscuro: false)
    }
}
