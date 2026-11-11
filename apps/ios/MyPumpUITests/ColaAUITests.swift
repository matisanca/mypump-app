import XCTest

/// La «cola A» de la 2.3.0: récords y logros, la lista previa a la videollamada y la demo con historial. Las cuentas van contra
/// el doble del servidor (`-colaADePrueba`, sin red). Lo fino (reglas, cola, palancas) está en el kit; acá va lo que solo se
/// ve con la pantalla de verdad, en claro, oscuro y letra grande. Capturas: `TEST_RUNNER_COLAA_DIR=<carpeta>`.
@MainActor
final class ColaAUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["COLAA_DIR"] }

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ args: [String], oscuro: Bool = false, letraGrande: Bool = false) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-sinOnboarding", "YES", "-mypump-theme", oscuro ? "dark" : "light"] + args
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] }
        app.launch()
    }

    /// Una cuenta de mentira contra el doble: `sinPermiso`, `conPermiso`, `sinRedPermiso`, `apagado`, `listaLista`…
    private func cuenta(_ escenario: String, _ extra: [String] = [], oscuro: Bool = false, letraGrande: Bool = false, token dado: String? = nil) {
        let token = dado ?? Self.tokenNuevo()
        lanzar(["-token", token, "-colaADePrueba", escenario] + extra, oscuro: oscuro, letraGrande: letraGrande)
    }

    private static func tokenNuevo() -> String { "tkcolaadeprueba" + UUID().uuidString.prefix(8).lowercased() }

    private func demo(_ extra: [String] = [], oscuro: Bool = false, letraGrande: Bool = false) {
        lanzar(["-entrar", "demo"] + extra, oscuro: oscuro, letraGrande: letraGrande)
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func esperar(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    /// Revisión con la cuenta de muestra ocupa el hilo principal un rato largo al abrir (peor con la máquina cargada): si se
    /// le pregunta antes, XCTest corta a los 30 s con «main thread busy».
    private func esperarQuieta() { esperar(100) }
    private func foto(_ nombre: String) {
        esperar(0.8)
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir, !dir.isEmpty { try? s.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(nombre).png")) }
    }
    /// Deja el elemento (con lo que tiene debajo, su pie) bien arriba de la barra de pestañas.
    private func subir(_ x: XCUIElement) {
        for _ in 0..<6 where x.frame.maxY > app.frame.height * 0.55 {
            let medio = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            medio.press(forDuration: 0.05, thenDragTo: medio.withOffset(CGVector(dx: 0, dy: -220)), withVelocity: .slow, thenHoldForDuration: 0.2)
            esperar(0.5)
        }
    }
    private func noAparece(_ id: String, _ s: TimeInterval = 4, _ mensaje: String) {
        XCTAssertFalse(e(id).waitForExistence(timeout: s), mensaje)
    }

    // MARK: - Récords y logros

    /// Sin permiso: el festejo ofrece «Contarle a Mati», que abre el permiso. Con el sí, el festejo dice que Mati se entera.
    func testFestejoSinPermisoYHojaDePermiso() {
        cuenta("sinPermiso", ["-pestana", "entreno", "-festejoDePrueba", "3"])
        XCTAssertTrue(e("festejo-titulo").waitForExistence(timeout: 150), "No se abrió el festejo")
        XCTAssertEqual(e("festejo-titulo").label, "3 récords hoy")
        XCTAssertEqual(e("festejo-subtitulo").label, "Superaste 3 de tus mejores marcas.")
        XCTAssertTrue(e("festejo-record-remo con barra").exists)
        XCTAssertTrue(e("festejo-record-remo con barra").label.contains("57,5 kg"), e("festejo-record-remo con barra").label)
        XCTAssertFalse(e("festejo-con-permiso").exists, "Sin permiso no dice que Mati se entera")
        XCTAssertTrue(app.buttons["festejo-seguir"].isHittable)
        foto("festejo-sin-permiso")
        app.buttons["festejo-contarle"].tap()
        XCTAssertTrue(e("permiso-logros-titulo").waitForExistence(timeout: 25))
        XCTAssertEqual(e("permiso-logros-titulo").label, "¿Compartir tus logros con Mati?")
        XCTAssertTrue(app.buttons["permiso-logros-no"].isHittable)
        foto("permiso")
        app.buttons["permiso-logros-si"].tap()
        XCTAssertTrue(e("festejo-con-permiso").waitForExistence(timeout: 15), "Con el sí, el festejo lo dice")
        XCTAssertEqual(e("festejo-con-permiso").label, "Mati se va a enterar de estos logros.")
        XCTAssertFalse(app.buttons["festejo-contarle"].exists)
        foto("festejo-recien-compartido")
        app.buttons["festejo-seguir"].tap()
        noAparece("festejo-titulo", 3, "«Seguir» cierra el festejo")
    }

    /// Con el permiso ya dado: sin botón de compartir, con la línea. En oscuro y con letra grande.
    func testFestejoConPermiso() {
        for (oscuro, grande) in [(false, false), (true, false), (false, true)] {
            cuenta("conPermiso", ["-pestana", "entreno", "-festejoDePrueba", "1"], oscuro: oscuro, letraGrande: grande)
            XCTAssertTrue(e("festejo-titulo").waitForExistence(timeout: 150), "No se abrió el festejo")
            XCTAssertEqual(e("festejo-titulo").label, "Récord nuevo")
            XCTAssertTrue(e("festejo-con-permiso").waitForExistence(timeout: 5))
            XCTAssertEqual(e("festejo-con-permiso").label, "Mati se va a enterar de este logro.")
            XCTAssertFalse(app.buttons["festejo-contarle"].exists)
            XCTAssertTrue(app.buttons["festejo-seguir"].isHittable, "«Seguir» siempre a la vista")
            foto("festejo-con-permiso\(oscuro ? "-oscuro" : "")\(grande ? "-letra-grande" : "")")
        }
    }

    /// Letra grande y tres récords sin permiso: los dos botones quedan a la vista y lo de arriba se puede recorrer.
    func testFestejoLetraGrande() {
        cuenta("sinPermiso", ["-pestana", "entreno", "-festejoDePrueba", "3"], oscuro: true, letraGrande: true)
        XCTAssertTrue(e("festejo-titulo").waitForExistence(timeout: 150))
        XCTAssertTrue(app.buttons["festejo-contarle"].isHittable)
        XCTAssertTrue(app.buttons["festejo-seguir"].isHittable)
        foto("festejo-sin-permiso-oscuro-letra-grande")
        app.buttons["festejo-contarle"].tap()
        XCTAssertTrue(e("permiso-logros-titulo").waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["permiso-logros-si"].isHittable)
        XCTAssertTrue(app.buttons["permiso-logros-no"].isHittable)
        foto("permiso-oscuro-letra-grande")
    }

    /// Sin red, el permiso no queda dado: lo dice y la hoja sigue ahí. «Ahora no» la cierra.
    func testPermisoSinRed() {
        cuenta("sinRedPermiso", ["-pestana", "entreno", "-festejoDePrueba", "1"])
        XCTAssertTrue(e("festejo-titulo").waitForExistence(timeout: 150))
        app.buttons["festejo-contarle"].tap()
        XCTAssertTrue(app.buttons["permiso-logros-si"].waitForExistence(timeout: 25))
        app.buttons["permiso-logros-si"].tap()
        XCTAssertTrue(e("permiso-logros-aviso").waitForExistence(timeout: 15), "Sin red tiene que avisar")
        foto("permiso-sin-red")
        app.buttons["permiso-logros-no"].tap()
        XCTAssertTrue(app.buttons["festejo-contarle"].waitForExistence(timeout: 5), "Sin permiso, el festejo sigue ofreciéndolo")
        XCTAssertFalse(e("festejo-con-permiso").exists)
    }

    /// Mis datos → Logros: apagar saca el permiso y lo dice; prender abre la hoja de permiso.
    func testMisDatosInterruptor() {
        cuenta("conPermiso", ["-pestana", "revision", "-abrir", "misdatos"])
        esperarQuieta()
        let interruptor = app.switches["logros-interruptor"]
        XCTAssertTrue(interruptor.waitForExistence(timeout: 150), "Falta la sección Logros")
        XCTAssertEqual(interruptor.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Compartir mis logros con Mati"].exists)
        subir(interruptor)
        foto("misdatos-logros")
        interruptor.switches.firstMatch.tap()
        XCTAssertTrue(e("logros-aviso").waitForExistence(timeout: 10))
        XCTAssertEqual(interruptor.value as? String, "0")
        foto("misdatos-logros-apagado")
        interruptor.switches.firstMatch.tap()
        XCTAssertTrue(e("permiso-logros-titulo").waitForExistence(timeout: 25), "Prenderlo pide el permiso")
        app.buttons["permiso-logros-si"].tap()
        esperar(2)
        XCTAssertEqual(app.switches["logros-interruptor"].value as? String, "1")
    }

    /// Con la palanca apagada y el permiso dado de antes, el interruptor sigue para poder sacarlo; al apagarlo, la sección
    /// no desaparece: queda el «Listo, no se comparte nada más.».
    func testMisDatosApagarConLaPalancaApagada() {
        // El permiso «de antes» queda en el teléfono en una primera apertura, con la palanca todavía prendida; con la palanca
        // apagada la app ya no le pregunta el estado al servidor.
        let token = Self.tokenNuevo()
        cuenta("conPermiso", ["-pestana", "revision", "-abrir", "misdatos"], token: token)
        esperarQuieta()
        XCTAssertTrue(app.switches["logros-interruptor"].waitForExistence(timeout: 150), "Falta la sección Logros")
        XCTAssertEqual(app.switches["logros-interruptor"].value as? String, "1")
        cuenta("apagadoConPermiso", ["-pestana", "revision", "-abrir", "misdatos"], token: token)
        esperarQuieta()
        let interruptor = app.switches["logros-interruptor"]
        XCTAssertTrue(interruptor.waitForExistence(timeout: 150), "Con el permiso dado, la sección sigue aunque la palanca esté apagada")
        XCTAssertEqual(interruptor.value as? String, "1")
        interruptor.switches.firstMatch.tap()
        XCTAssertTrue(e("logros-aviso").waitForExistence(timeout: 15))
        XCTAssertEqual(e("logros-aviso").label, "Listo, no se comparte nada más.")
        XCTAssertTrue(app.switches["logros-interruptor"].exists, "La sección no desaparece con el aviso a la vista")
        XCTAssertEqual(app.switches["logros-interruptor"].value as? String, "0")
    }

    func testMisDatosOscuroLetraGrande() {
        cuenta("sinPermiso", ["-pestana", "revision", "-abrir", "misdatos"], oscuro: true, letraGrande: true)
        esperarQuieta()
        let interruptor = app.switches["logros-interruptor"]
        XCTAssertTrue(interruptor.waitForExistence(timeout: 150), "Falta la sección Logros")
        XCTAssertEqual(interruptor.value as? String, "0")
        subir(interruptor)
        XCTAssertTrue(interruptor.isHittable, "Con letra grande el interruptor no queda tapado")
        foto("misdatos-logros-oscuro-letra-grande")
        // Al final del scroll tampoco queda nada tapado por la barra de pestañas.
        let barra = app.tabBars.firstMatch
        XCTAssertTrue(interruptor.frame.maxY <= barra.frame.minY, "El interruptor queda arriba de la barra: \(interruptor.frame) y \(barra.frame)")
    }

    /// Con las palancas apagadas no hay nada nuevo: ni festejo, ni lista, ni la sección de Mis datos.
    func testConLasPalancasApagadasNoHayNada() {
        cuenta("apagado", ["-pestana", "entreno", "-festejoDePrueba", "2"])
        XCTAssertTrue(app.buttons["fila-ejercicio-1"].waitForExistence(timeout: 150), "No cargó Entreno")
        noAparece("festejo-titulo", 6, "Apagada no se festeja")
        XCTAssertFalse(e("lista-previa").exists, "Apagada no hay lista previa")
        cuenta("apagado", ["-pestana", "revision", "-abrir", "misdatos"])
        esperarQuieta()
        XCTAssertTrue(app.switches["tema-oscuro"].waitForExistence(timeout: 150), "No abrió Mis datos")
        XCTAssertFalse(app.switches["logros-interruptor"].exists, "Apagada y sin permiso no hay sección Logros")
    }

    /// La racha de pasos que es un hito, con permiso: la celebración del Pump del día lo dice.
    func testRachaDePasosConPermiso() {
        cuenta("conPermiso", ["-pestana", "entreno", "-metas", "racha7", "-pasos", "10240"])
        XCTAssertTrue(e("pump-racha-compartida").waitForExistence(timeout: 150), "La celebración no dice que Mati se entera")
        XCTAssertEqual(e("pump-racha-compartida").label, "Mati se va a enterar de esta racha.")
        esperar(3)   // los textos de la celebración entran con la animación
        foto("pump-racha-compartida")
        app.buttons["pump-seguir"].tap()
    }

    func testRachaDePasosSinPermiso() {
        cuenta("sinPermiso", ["-pestana", "entreno", "-metas", "racha7", "-pasos", "10240"])
        XCTAssertTrue(app.buttons["pump-seguir"].waitForExistence(timeout: 150), "No salió la celebración")
        XCTAssertFalse(e("pump-racha-compartida").exists, "Sin permiso no se comparte nada")
    }

    // MARK: - Lista previa

    /// Sin reserva: la lista como tarjeta propia, arriba de todo y desplegada. La fila de las fotos lleva a Revisión.
    func testListaPreviaSola() {
        for (oscuro, grande) in [(false, false), (true, false), (false, true)] {
            cuenta("sinPermiso", ["-pestana", "entreno"], oscuro: oscuro, letraGrande: grande)
            XCTAssertTrue(e("lista-previa-tarjeta").waitForExistence(timeout: 150), "Falta la lista previa")
            XCTAssertEqual(e("lista-previa-titulo").label, "Antes de la videollamada")
            XCTAssertTrue(e("lista-previa-resumen").exists)
            XCTAssertTrue(e("lista-previa-consejo").exists)
            XCTAssertTrue(app.buttons["lista-previa-fotos"].exists, "Las fotos que faltan son un botón")
            foto("lista-previa-sola\(oscuro ? "-oscuro" : "")\(grande ? "-letra-grande" : "")")
        }
        let fotos = app.buttons["lista-previa-fotos"]
        for _ in 0..<4 where !fotos.isHittable { app.swipeUp(velocity: .slow) }
        fotos.tap()
        XCTAssertTrue(app.tabBars.buttons["Revisión"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Revisión"].isSelected, "Las fotos llevan a Revisión")
    }

    func testListaPreviaTodoListo() {
        cuenta("listaLista", ["-pestana", "entreno"])
        XCTAssertTrue(e("lista-previa-tarjeta").waitForExistence(timeout: 150))
        XCTAssertEqual(e("lista-previa-resumen").label, "Ya tenés todo listo")
        XCTAssertFalse(app.buttons["lista-previa-fotos"].exists, "Lo hecho no es un botón")
        foto("lista-previa-todo-listo")
    }

    func testListaPreviaInactiva() {
        cuenta("listaInactiva", ["-pestana", "entreno"])
        XCTAssertTrue(app.buttons["fila-ejercicio-1"].waitForExistence(timeout: 150), "No cargó Entreno")
        esperar(2)
        XCTAssertFalse(e("lista-previa").exists, "Inactiva no se muestra")
    }

    /// Con la reserva de comienzo: la lista va DENTRO de la tarjeta de la videollamada (y no hay tarjeta propia). La fila de la
    /// guía abre la guía.
    func testListaPreviaDentroDeLaTarjeta() {
        for (escenario, oscuro, grande) in [("diasAntes", false, false), ("diasAntes", true, false), ("porEntrar", false, false), ("diasAntes", false, true)] {
            lanzar(["-bocetos", "YES", "-agendaDemo", escenario, "-pestana", "entreno", "-elegirHorario", "YES", "-listaPreviaDePrueba", "demo"],
                   oscuro: oscuro, letraGrande: grande)
            XCTAssertTrue(e("videollamada").waitForExistence(timeout: 150))
            let lista = e("lista-previa")
            for _ in 0..<5 where !(lista.exists && lista.isHittable) { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(lista.exists, "La lista va dentro de la tarjeta")
            XCTAssertFalse(e("lista-previa-tarjeta").exists, "Con la tarjeta de la videollamada no hay tarjeta propia")
            let tarjeta = e("videollamada").frame, l = lista.frame
            XCTAssertTrue(tarjeta.minY <= l.minY && l.maxY <= tarjeta.maxY + 1, "La lista queda dentro de la tarjeta: \(l) en \(tarjeta)")
            let guia = app.buttons["lista-previa-guia"]
            for _ in 0..<5 where !guia.isHittable { app.swipeUp(velocity: .slow) }
            foto("lista-previa-en-tarjeta\(escenario == "porEntrar" ? "-por-entrar" : "")\(oscuro ? "-oscuro" : "")\(grande ? "-letra-grande" : "")")
        }
        let guia = app.buttons["lista-previa-guia"]
        XCTAssertTrue(guia.isHittable)
        guia.tap()
        XCTAssertTrue(app.navigationBars["Tu guía"].waitForExistence(timeout: 8), "La fila de la guía abre la guía")
    }

    // MARK: - La demo con historial

    /// Entreno en la demo: la lista previa de ejemplo como tarjeta propia y el Pump del día con sus pasos.
    func testDemoEntreno() {
        for oscuro in [false, true] {
            demo(["-pestana", "entreno"], oscuro: oscuro)
            XCTAssertTrue(e("lista-previa-tarjeta").waitForExistence(timeout: 150), "La demo trae su lista previa")
            foto("demo-entreno\(oscuro ? "-oscuro" : "")")
            let pump = e("pump-del-dia")
            for _ in 0..<8 where !(pump.exists && pump.isHittable) { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(pump.exists, "La demo trae el Pump del día")
            foto("demo-pump-del-dia\(oscuro ? "-oscuro" : "")")
        }
    }

    /// Revisión en la demo: la devolución de Mati arriba de todo.
    func testDemoDevolucion() {
        for (oscuro, grande) in [(false, false), (true, false), (false, true)] {
            demo(["-pestana", "revision"], oscuro: oscuro, letraGrande: grande)
            XCTAssertTrue(e("devolucion-tarjeta").waitForExistence(timeout: 150), "La demo trae la devolución de Mati")
            XCTAssertTrue(e("devolucion-texto").exists)
            foto("demo-devolucion\(oscuro ? "-oscuro" : "")\(grande ? "-letra-grande" : "")")
        }
    }

    /// Salud en la demo: Fuerza con el historial por ejercicio y Cuerpo con el peso y el ritmo.
    func testDemoProgresoYPeso() {
        for oscuro in [false, true] {
            demo(["-pestana", "salud", "-segmento", "fuerza"], oscuro: oscuro)
            XCTAssertTrue(app.staticTexts["Remo con barra"].waitForExistence(timeout: 150), "Fuerza no muestra el historial de la demo")
            foto("demo-progreso\(oscuro ? "-oscuro" : "")")
            if !oscuro {
                app.staticTexts["Remo con barra"].firstMatch.tap()
                esperar(1.5)
                foto("demo-progreso-detalle")
            }
            demo(["-pestana", "salud", "-segmento", "cuerpo"], oscuro: oscuro)
            XCTAssertTrue(e("ritmo-peso").waitForExistence(timeout: 150), "Cuerpo no muestra el peso con su ritmo")
            foto("demo-peso\(oscuro ? "-oscuro" : "")")
        }
        demo(["-pestana", "salud", "-segmento", "recuperacion"])
        XCTAssertTrue(e("pump-del-dia").waitForExistence(timeout: 150), "Recuperación muestra los pasos de la demo")
        foto("demo-salud-pasos")
    }

    /// El chat de la demo: la charla de ejemplo con Mati.
    func testDemoChat() {
        for oscuro in [false, true] {
            demo(["-pestana", "chat"], oscuro: oscuro)
            XCTAssertTrue(e("chat-campo").waitForExistence(timeout: 150))
            XCTAssertTrue(app.staticTexts.count > 3, "El chat de la demo no trae la charla")
            foto("demo-chat\(oscuro ? "-oscuro" : "")")
        }
    }

    /// La demo, de punta a punta: más kilos que la última vez, cerrar la sesión y el festejo. «Contarle a Mati» no manda nada.
    func testDemoFestejoAlCerrarLaSesion() {
        demo(["-pestana", "entreno", "-abrir", "ejercicio", "-descanso", "no"])
        app.fijarCarga("95")
        app.darOK()
        let atras = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(atras.waitForExistence(timeout: 10))
        app.volverALaLista()
        XCTAssertTrue(app.navigationBars["Remo con barra"].waitForNonExistence(timeout: 10), "No volvió a la lista")
        let cerrar = app.bajarHastaCerrarSesion()
        XCTAssertTrue(cerrar.isHittable, "No está «Terminar el entrenamiento de hoy»")
        cerrar.tap()
        XCTAssertTrue(app.buttons["confirmar-cierre"].waitForExistence(timeout: 30))
        app.buttons["confirmar-cierre"].tap()
        XCTAssertTrue(e("festejo-titulo").waitForExistence(timeout: 40), "Después de cerrar con un récord, el festejo")
        XCTAssertEqual(e("festejo-titulo").label, "Récord nuevo")
        foto("demo-festejo")
        app.buttons["festejo-contarle"].tap()
        XCTAssertTrue(e("festejo-demo").waitForExistence(timeout: 5), "En la demo no se envía nada, y lo dice")
        XCTAssertFalse(e("permiso-logros-titulo").exists)
        foto("demo-festejo-no-envia")
        app.buttons["festejo-seguir"].tap()
        noAparece("festejo-titulo", 3, "«Seguir» cierra el festejo")
    }
}
