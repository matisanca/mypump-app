import XCTest

/// «Tu guía» v2 (2.2.0): la novedad, los obligatorios y la agenda de la entrega, con la 021 de mentira
/// (`-agendaDemo <escenario>`, `ServidorAgendaUI`): nunca toca la base. Lo único que sale a la red es el video público de
/// la demo que hay que ver. Con `AGENDA_CAPTURAS=<carpeta>` en el entorno del runner (`TEST_RUNNER_AGENDA_CAPTURAS`), deja
/// las capturas `ios-<nombre><AGENDA_SUFIJO>.png` ahí.
@MainActor
final class AgendaUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws { continueAfterFailure = false }

    private func abrir(_ escenario: String, guia: Bool = true, _ extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-bocetos", "YES", "-agendaDemo", escenario, "-sinOnboarding", "YES", "-pestana", "entreno"]
            + (guia ? ["-abrir", "guia"] : []) + extra
        app.launch()
        if guia { XCTAssertTrue(app.descendants(matching: .any)["guia-avance"].waitForExistence(timeout: 20), "No abrió la guía") }
    }

    private func id(_ i: String) -> XCUIElement { app.descendants(matching: .any)[i].firstMatch }
    private func texto(_ t: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch
    }

    private func esperar(_ condicion: () -> Bool, segundos: Double) -> Bool {
        let limite = Date().addingTimeInterval(segundos)
        while Date() < limite {
            if condicion() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return condicion()
    }

    /// Baja (o sube) hasta que el elemento quede tocable en la mitad de la pantalla.
    private func llevarALaVista(_ e: XCUIElement, maximo: Int = 25) {
        for _ in 0..<maximo {
            if e.exists, e.isHittable, e.frame.minY > app.frame.height * 0.1, e.frame.maxY < app.frame.height * 0.82 { return }
            let origen = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            // Si ya se sabe dónde está, se arrastra lo justo para centrarlo (con letra grande y pantalla chica, un paso
            // fijo lo pasa de largo de un lado al otro).
            let h = app.frame.height
            let d: CGFloat
            if e.exists, !e.frame.isEmpty, e.frame.midY > -h, e.frame.midY < 2 * h {
                d = min(max(h * 0.45 - e.frame.midY, -h * 0.3), h * 0.3)
            } else {
                d = -h * 0.3
            }
            origen.press(forDuration: 0.05, thenDragTo: origen.withOffset(CGVector(dx: 0, dy: d)), withVelocity: .fast, thenHoldForDuration: 0.1)
        }
    }

    /// Deja la tarjeta de la agenda entera a la vista para la captura: su borde de arriba justo debajo de la barra de «Tu
    /// guía» (con letra grande, si no entra, al menos el comienzo). Se arrastra de a poco y se mide de nuevo.
    private func mostrarTarjeta() {
        let caja = id("agenda")
        XCTAssertTrue(caja.waitForExistence(timeout: 10), "No está la tarjeta de la agenda")
        let h = app.frame.height
        let objetivo = h * 0.15
        var anterior = CGFloat.nan
        for _ in 0..<15 {
            let y = caja.frame.minY
            let d = objetivo - y
            if abs(d) < 12 || abs(y - anterior) < 2 { break }
            anterior = y
            let origen = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let paso = min(max(d, -h * 0.35), h * 0.35)
            origen.press(forDuration: 0.05, thenDragTo: origen.withOffset(CGVector(dx: 0, dy: paso)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    private func captura(_ nombre: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = nombre; a.lifetime = .keepAlways; add(a)
        guard let dir = ProcessInfo.processInfo.environment["AGENDA_CAPTURAS"], !dir.isEmpty else { return }
        let sufijo = ProcessInfo.processInfo.environment["AGENDA_SUFIJO"] ?? ""
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ios-\(nombre)\(sufijo).png"))
    }

    // MARK: - Pruebas

    /// La spec §5: bloqueada → ver el último → habilitada → reservar → pendiente → confirmada (sin «Entrar»). De paso, la
    /// tarjeta NOVEDAD de Entreno y el bloque «Novedad» arriba de la guía.
    func testBloqueadaVerElUltimoReservarYEntrar() throws {
        abrir("flujo", guia: false)
        let ceja = id("guia-tarjeta-ceja")
        XCTAssertTrue(ceja.waitForExistence(timeout: 20), "No está la tarjeta destacada")
        XCTAssertEqual(ceja.label.lowercased(), "novedad en tu guía")
        XCTAssertEqual(id("guia-tarjeta-texto").label, "Novedad en tu guía, 1 de 2 videos nuevos, te queda 1 min")
        XCTAssertEqual(app.buttons["guia-tarjeta"].label, "Ver lo nuevo")
        captura("tarjeta-novedad")
        app.buttons["guia-tarjeta"].tap()
        XCTAssertTrue(id("guia-avance").waitForExistence(timeout: 15))
        // El bloque «Novedad» va primero, con el subtítulo, y abre con el video nuevo sin ver.
        let novedad = app.buttons["guia-bloque-_novedad"]
        llevarALaVista(novedad)
        XCTAssertTrue(novedad.exists && novedad.label.contains("2 videos nuevos para vos · 1 min"), novedad.label)
        if novedad.value as? String == "Cerrado" { novedad.tap() }
        let fila = app.buttons["guia-fila-N-1"]
        XCTAssertTrue(fila.waitForExistence(timeout: 5))
        XCTAssertTrue((fila.value as? String ?? "").contains("Para ver antes de la entrega"), "Falta la etiqueta: \(fila.value ?? "")")
        XCTAssertLessThan(novedad.frame.minY, app.buttons["guia-bloque-Tu app"].frame.minY, "«Novedad» va arriba de «Tu app»")
        captura("novedad-arriba")

        // Bloqueada: el contador y la gris con candado.
        let bloqueada = id("agenda-bloqueada")
        llevarALaVista(bloqueada)
        XCTAssertTrue(bloqueada.waitForExistence(timeout: 10), "No está la agenda bloqueada")
        XCTAssertTrue(bloqueada.label.contains("Cuando termines los videos de arriba se habilita la agenda. Te falta 1."), bloqueada.label)
        XCTAssertEqual(app.buttons["agenda-contador"].label, "Te falta 1 video para habilitar la agenda")
        mostrarTarjeta()
        captura("agenda-bloqueada")

        // «Ir al próximo video»: arranca el que falta. Se ve entero a 1,5x y queda visto.
        let ir = app.buttons["agenda-ir-al-video"]
        llevarALaVista(ir)
        ir.tap()
        let titulo = app.staticTexts["guia-titulo-actual"]
        XCTAssertTrue(esperar({ titulo.exists && titulo.label == "Lo que cambia en tu entrenamiento" }, segundos: 8), "No fue al video que falta")
        let velocidad = app.buttons["guia-velocidad"]
        if velocidad.waitForExistence(timeout: 5) { velocidad.tap(); velocidad.tap() }
        XCTAssertTrue(esperar({ (app.buttons["guia-fila-N-1"].value as? String ?? "").hasPrefix("Visto") }, segundos: 60),
                      "El video que faltaba no quedó visto")

        // Habilitada: las franjas por día.
        let franja = app.buttons["agenda-franja-f1"]
        XCTAssertTrue(esperar({ franja.exists }, segundos: 20), "La agenda no se habilitó")
        llevarALaVista(franja)
        XCTAssertFalse(id("agenda-bloqueada").exists)
        XCTAssertGreaterThanOrEqual(franja.frame.height, 44)
        mostrarTarjeta()
        captura("agenda-habilitada")
        franja.tap()
        let hoja = app.staticTexts["agenda-hoja-texto"]
        XCTAssertTrue(hoja.waitForExistence(timeout: 5), "No abrió la confirmación")
        XCTAssertTrue(hoja.label.hasPrefix("¿Confirmás la entrega el ") && hoja.label.hasSuffix("a las 10:00? Dura alrededor de 1 hora."), hoja.label)
        captura("agenda-hoja")
        // «Elegir otro» cierra sin reservar.
        app.buttons["agenda-elegir-otro"].tap()
        XCTAssertTrue(esperar({ !hoja.exists }, segundos: 5))
        XCTAssertTrue(franja.exists)
        franja.tap()
        XCTAssertTrue(app.buttons["agenda-confirmar"].waitForExistence(timeout: 5))
        app.buttons["agenda-confirmar"].tap()

        // Pendiente → confirmada (el doble confirma a la tercera consulta, cada 5 s).
        let reservando = id("agenda-reservando")
        XCTAssertTrue(reservando.waitForExistence(timeout: 8), "No se vio «Estamos reservando tu horario…»")
        llevarALaVista(reservando)
        mostrarTarjeta()
        captura("agenda-pendiente")
        let confirmada = id("agenda-confirmada")
        XCTAssertTrue(confirmada.waitForExistence(timeout: 30), "No se confirmó")
        XCTAssertTrue(confirmada.label.hasPrefix("Tu entrega: ") && confirmada.label.hasSuffix(", 10:00 a 11:00"), confirmada.label)
        XCTAssertTrue(texto("¿Necesitás cambiarla? Escribinos por WhatsApp").exists)
        XCTAssertTrue(app.buttons["agenda-calendario"].exists)
        // Confirmada para mañana: solo el día y la hora, sin botón ni aviso de la sala (el cliente nunca entra directo).
        llevarALaVista(app.buttons["agenda-calendario"])
        XCTAssertFalse(app.buttons["agenda-entrar"].exists, "Al confirmar no aparece «Entrar»")
        XCTAssertFalse(id("agenda-esperando-sala").exists, "Antes del día no hay aviso de la sala")
        mostrarTarjeta()
        captura("agenda-confirmada")
    }

    /// El día de la entrega, sin la sala abierta: el aviso y sin botón. Cuando Mati entra al Meet (la tercera consulta
    /// del doble, cada 2 s), «Mati ya está en la videollamada» y «Entrar», que abre el link.
    func testSalaSinAbrirYDespuesAbierta() throws {
        abrir("confirmada", ["-guiaAncla", "agenda"])
        let esperando = id("agenda-esperando-sala")
        XCTAssertTrue(esperando.waitForExistence(timeout: 15), "Sin la sala abierta tiene que estar el aviso")
        XCTAssertTrue(esperando.label.hasPrefix("Tu entrega es hoy a las ")
                      && esperando.label.hasSuffix("Cuando Mati abra la videollamada se habilita el botón para entrar."), esperando.label)
        XCTAssertFalse(app.buttons["agenda-entrar"].exists, "Sin la sala abierta no hay botón")
        llevarALaVista(esperando)
        mostrarTarjeta()
        captura("agenda-confirmada-sin-sala")

        abrir("salaSeAbre", ["-guiaAncla", "agenda", "-agendaSalaCada", "2"])
        let entrar = app.buttons["agenda-entrar"]
        XCTAssertTrue(entrar.waitForExistence(timeout: 40), "No apareció «Entrar» al abrirse la sala")
        XCTAssertFalse(id("agenda-esperando-sala").exists)
        XCTAssertEqual(id("agenda-sala").label, "Mati ya está en la videollamada")
        llevarALaVista(entrar)
        mostrarTarjeta()
        captura("agenda-confirmada-sala-abierta")
        entrar.tap()
        // Abre el link de Meet afuera (el navegador del simulador): la app pasa a segundo plano.
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10), "«Entrar a la videollamada» no abrió el link")
    }

    /// La franja se ocupó al reservar: el aviso y las franjas de nuevo, sin la tomada.
    func testTomadaVuelveALasFranjas() throws {
        abrir("tomada", ["-guiaAncla", "agenda"])
        let franja = app.buttons["agenda-franja-f1"]
        XCTAssertTrue(franja.waitForExistence(timeout: 15))
        llevarALaVista(franja)
        franja.tap()
        XCTAssertTrue(app.buttons["agenda-confirmar"].waitForExistence(timeout: 5))
        app.buttons["agenda-confirmar"].tap()
        let aviso = id("agenda-aviso")
        XCTAssertTrue(aviso.waitForExistence(timeout: 15), "No apareció el aviso")
        XCTAssertEqual(aviso.label, "Ese horario se ocupó recién, elegí otro.")
        XCTAssertTrue(esperar({ !app.buttons["agenda-franja-f1"].exists }, segundos: 10), "La tomada sigue")
        XCTAssertTrue(app.buttons["agenda-franja-f2"].exists)
        llevarALaVista(aviso)
        mostrarTarjeta()
        captura("agenda-fallo-tomada")
    }

    /// El daemon la pasó a `fallo` con `vencida` (más de 30 min pendiente): «No pudimos reservar…» y las franjas.
    func testVencidaVuelveALasFranjas() throws {
        abrir("vencida", ["-guiaAncla", "agenda"])
        let aviso = id("agenda-aviso")
        XCTAssertTrue(aviso.waitForExistence(timeout: 15))
        XCTAssertEqual(aviso.label, "No pudimos reservar ese horario, elegí otro.")
        XCTAssertTrue(app.buttons["agenda-franja-f2"].exists)
    }

    /// Sin el OK de horarios (el punto de control): el texto y el contador, sin candado de «Ir al próximo video».
    func testSinAutorizar() throws {
        abrir("noAutorizada", ["-guiaAncla", "agenda"])
        let b = id("agenda-bloqueada")
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        llevarALaVista(b)
        XCTAssertEqual(b.label, "Cuando termines de ver todo te habilitamos la agenda.")
        XCTAssertEqual(app.buttons["agenda-contador"].label, "Te falta 1 video para habilitar la agenda")
        XCTAssertFalse(app.buttons["agenda-ir-al-video"].exists)
        mostrarTarjeta()
        captura("agenda-no-autorizada")
        // El contador salta al video que falta.
        llevarALaVista(app.buttons["agenda-contador"])
        app.buttons["agenda-contador"].tap()
        let titulo = app.staticTexts["guia-titulo-actual"]
        XCTAssertTrue(esperar({ titulo.exists && titulo.isHittable && titulo.label == "Lo que cambia en tu entrenamiento" }, segundos: 8))
    }

    func testSinFranjasYPendiente() throws {
        abrir("sinFranjas", ["-guiaAncla", "agenda"])
        let sin = id("agenda-sin-franjas")
        XCTAssertTrue(sin.waitForExistence(timeout: 15))
        XCTAssertEqual(sin.label, "Ahora no hay horarios libres. Te escribimos por WhatsApp para coordinar.")
        llevarALaVista(sin)
        mostrarTarjeta()
        captura("agenda-sin-franjas")
        abrir("pendiente", ["-guiaAncla", "agenda"])
        XCTAssertTrue(id("agenda-reservando").waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["agenda-franja-f2"].exists, "Con la reserva pendiente no van franjas")
    }

    /// En Entreno, desde 30 min antes: el aviso sin botón hasta que Mati abre la sala; después, «Mati ya está en la
    /// videollamada · Entrar». Confirmada y sin red: lo último guardado, con «Sin conexión», y el link sigue a mano.
    func testSinRedConLaConfirmadaGuardada() throws {
        abrir("confirmada", guia: false)
        let esperando = id("agenda-esperando-tarjeta")
        XCTAssertTrue(esperando.waitForExistence(timeout: 20), "No está el aviso de la entrega en Entreno")
        XCTAssertTrue(esperando.label.hasPrefix("Tu entrega es hoy a las "), esperando.label)
        XCTAssertFalse(app.buttons["agenda-entrar-tarjeta"].exists, "Sin la sala abierta no hay botón en Entreno")
        captura("entreno-sin-sala")
        abrir("salaAbierta", guia: false)
        let tarjeta = app.buttons["agenda-entrar-tarjeta"]
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 20), "No está «Entrar» en Entreno")
        XCTAssertTrue(tarjeta.label.hasPrefix("Mati ya está en la videollamada"), tarjeta.label)
        captura("entreno-entrar")
        // Se abre la guía con red (queda guardada) y se vuelve a abrir sin red.
        abrir("salaAbierta", ["-guiaAncla", "agenda"])
        XCTAssertTrue(id("agenda-confirmada").waitForExistence(timeout: 15))
        abrir("salaAbierta", ["-agendaSinRed", "YES", "-agendaConservar", "YES", "-guiaAncla", "agenda"])
        let sinRed = id("agenda-sin-red")
        XCTAssertTrue(sinRed.waitForExistence(timeout: 15), "No dice «Sin conexión»")
        XCTAssertTrue(id("agenda-confirmada").exists)
        let entrar = app.buttons["agenda-entrar"]
        llevarALaVista(entrar)
        XCTAssertTrue(entrar.isHittable, "Sin red, el link tiene que seguir a mano")
        mostrarTarjeta()
        captura("agenda-sin-red")
    }

    /// Letra de accesibilidad: la confirmada y la hoja se leen enteras y los botones se tocan.
    func testLetraGrande() throws {
        let grande = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        abrir("salaAbierta", ["-guiaAncla", "agenda"] + grande)
        let entrar = app.buttons["agenda-entrar"]
        XCTAssertTrue(entrar.waitForExistence(timeout: 15))
        llevarALaVista(entrar)
        XCTAssertTrue(entrar.isHittable)
        XCTAssertLessThanOrEqual(entrar.frame.width, app.frame.width)
        captura("agenda-confirmada-letra-grande")
        abrir("tomada", ["-guiaAncla", "agenda"] + grande)
        let franja = app.buttons["agenda-franja-f2"]
        XCTAssertTrue(franja.waitForExistence(timeout: 15))
        llevarALaVista(franja)
        XCTAssertTrue(franja.isHittable)
        captura("agenda-habilitada-letra-grande")
        franja.tap()
        let confirmar = app.buttons["agenda-confirmar"]
        XCTAssertTrue(confirmar.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmar.isHittable || { app.swipeUp(); return confirmar.isHittable }())
        captura("agenda-hoja-letra-grande")
    }

    /// «Ver demo» (la revisión de Apple): la agenda está, bloqueada hasta ver los dos nuevos.
    func testDemoTieneLaAgenda() throws {
        app.terminate()
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno", "-abrir", "guia", "-guiaAncla", "agenda"]
        app.launch()
        let b = id("agenda-bloqueada")
        XCTAssertTrue(b.waitForExistence(timeout: 20), "La demo no tiene la agenda")
        XCTAssertTrue(b.label.hasSuffix("Te faltan 2."), b.label)
        XCTAssertEqual(app.buttons["agenda-contador"].label, "Te faltan 2 videos para habilitar la agenda")
        // Se ven los dos nuevos (videos públicos de la demo, 18 s cada uno) y la agenda se habilita sola.
        for id in ["FT-2a", "FT-2d"] {
            let ir = app.buttons["agenda-ir-al-video"]
            llevarALaVista(ir)
            XCTAssertTrue(ir.exists, "Falta «Ir al próximo video» antes de \(id)")
            ir.tap()
            let velocidad = app.buttons["guia-velocidad"]
            if velocidad.waitForExistence(timeout: 5), velocidad.label == "Velocidad 1x" { velocidad.tap(); velocidad.tap() }
            XCTAssertTrue(esperar({ (app.buttons["guia-fila-\(id)"].value as? String ?? "").hasPrefix("Visto") }, segundos: 60), "\(id) no quedó visto")
        }
        let franja = app.buttons["agenda-franja-demo-franja-1"]
        llevarALaVista(franja)
        XCTAssertTrue(esperar({ franja.exists }, segundos: 10), "La agenda de la demo no se habilitó")
        franja.tap()
        XCTAssertTrue(app.buttons["agenda-confirmar"].waitForExistence(timeout: 5))
        app.buttons["agenda-confirmar"].tap()
        let demo = id("agenda-demo")
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        XCTAssertEqual(demo.label, "En la demo no se crea ninguna videollamada.")
        XCTAssertFalse(app.buttons["agenda-entrar"].exists, "En la demo no hay videollamada")
        llevarALaVista(demo)
        mostrarTarjeta()
        captura("demo-confirmada")
    }
}
