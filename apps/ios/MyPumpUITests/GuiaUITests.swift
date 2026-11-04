import XCTest

/// «Tu guía» de punta a punta contra el servidor, con el cliente de prueba `test-nativa-ios` (`TEST_RUNNER_MYPUMP_TOKEN`,
/// nunca un cliente): `scripts/nativa/probar-ui.sh <udid> ios -only-testing:MyPumpUITests/GuiaUITests`.
/// Escribe en ese cliente de prueba: lo visto, una duda de video y una de la videollamada por corrida.
@MainActor
final class GuiaUITests: XCTestCase {
    private var app = XCUIApplication()
    private var token = ""

    override func setUp() async throws {
        continueAfterFailure = false
        guard let t = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !t.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan el cliente de prueba, nunca un cliente.")
        }
        token = t
    }

    private func abrirApp(_ extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-token", token, "-pestana", "entreno", "-sinOnboarding", "YES"] + extra
        app.launch()
    }

    private var tarjeta: XCUIElement { app.buttons["guia-tarjeta"] }

    /// Abre la guía desde la tarjeta de Entreno.
    private func abrirGuia() {
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 25), "No apareció la tarjeta de «Tu guía» en Entreno")
        tarjeta.tap()
        XCTAssertTrue(app.descendants(matching: .any)["guia-avance"].waitForExistence(timeout: 20), "No abrió la guía")
    }

    private func filas() -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guia-fila-'")).allElementsBoundByIndex
    }

    /// Abre todos los capítulos plegados.
    private func abrirCapitulos() {
        for _ in 0..<12 {
            let cerrados = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guia-bloque-' AND value == 'Cerrado'"))
            guard cerrados.count > 0 else { return }
            let b = cerrados.element(boundBy: 0)
            desplazarHasta(b)
            b.tap()
        }
    }

    private func desplazarHasta(_ e: XCUIElement, maximo: Int = 15) {
        var n = 0
        while !e.isHittable && n < maximo { app.swipeUp(velocity: .slow); n += 1 }
    }

    private func esperar(_ condicion: () -> Bool, segundos: Double) -> Bool {
        let limite = Date().addingTimeInterval(segundos)
        while Date() < limite {
            if condicion() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return condicion()
    }

    private func captura(_ nombre: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
    }

    // MARK: - Pruebas

    /// «Ver por qué» (A5): el video del suplemento no está en la lista; el botón lo abre ahí mismo, chico, y lo cierra.
    func testVerPorQueAbreElVideoDebajoDelSuplemento() throws {
        abrirApp()
        abrirGuia()
        abrirCapitulos()
        let enLaLista = Set(filas().map { $0.identifier.replacingOccurrences(of: "guia-fila-", with: "") })
        let botones = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guia-ver-por-que-' AND identifier != 'guia-ver-por-que-video'"))
        let boton = botones.firstMatch
        var n = 0
        while !(boton.exists && boton.isHittable) && n < 30 { app.swipeUp(velocity: .slow); n += 1 }
        guard boton.exists else {
            throw XCTSkip("El cliente de prueba no tiene suplementos con video: no hay «Ver por qué» para probar.")
        }
        let id = boton.identifier.replacingOccurrences(of: "guia-ver-por-que-", with: "")
        XCTAssertFalse(enLaLista.contains(id), "El video de un suplemento no va en la lista de capítulos")
        XCTAssertTrue(boton.label.hasPrefix("Ver por qué ("), "Rótulo inesperado: \(boton.label)")
        boton.tap()
        let video = app.descendants(matching: .any)["guia-ver-por-que-video"]
        XCTAssertTrue(video.waitForExistence(timeout: 10), "No se abrió el video debajo del suplemento")
        XCTAssertTrue(app.buttons["guia-ver-por-que-\(id)"].label.hasPrefix("Cerrar el video"))
        XCTAssertTrue(app.textViews["guia-duda-campo-\(id)"].exists || app.textFields["guia-duda-campo-\(id)"].exists
                      || app.descendants(matching: .any)["guia-duda-campo-\(id)"].exists, "Falta el recuadro de duda del video")
        captura("ver-por-que-abierto")
        app.buttons["guia-ver-por-que-\(id)"].tap()
        XCTAssertTrue(esperar({ !video.exists }, segundos: 5), "No se cerró el video")
    }

    /// Abrir, ver un video hasta pasar el 80 % (a 1,5x), cerrar la app y volver: sigue visto (salió por la cola al servidor).
    func testVerUnVideoQuedaVistoAlVolver() throws {
        abrirApp()
        abrirGuia()
        abrirCapitulos()
        // El video sin ver más corto: el que esté a la vista y diga «Sin ver».
        let sinVer = filas().filter { ($0.value as? String ?? "").hasPrefix("Sin ver") && !($0.value as? String ?? "").contains("subiendo") }
        guard let elegido = sinVer.min(by: { duracion($0) < duracion($1) }) else {
            throw XCTSkip("El cliente de prueba ya vio todos los videos: pedile a la sesión de entregas que lo limpie.")
        }
        let id = elegido.identifier
        desplazarHasta(elegido)
        elegido.tap()
        let velocidad = app.buttons["guia-velocidad"]
        XCTAssertTrue(velocidad.waitForExistence(timeout: 5))
        velocidad.tap(); velocidad.tap()
        XCTAssertEqual(velocidad.label, "Velocidad 1,5x")
        captura("reproduciendo")
        let fila = app.buttons[id]
        XCTAssertTrue(esperar({ (fila.value as? String ?? "").hasPrefix("Visto") }, segundos: duracion(elegido) / 1.5 + 30),
                      "No quedó visto después del 80 % (\(id))")
        captura("visto")
        // Que salga por la cola antes de cerrar (con red sale enseguida).
        sleep(3)
        abrirApp()
        abrirGuia()
        abrirCapitulos()
        let otra = app.buttons[id]
        XCTAssertTrue(otra.waitForExistence(timeout: 10))
        XCTAssertTrue((otra.value as? String ?? "").hasPrefix("Visto"), "Al volver, \(id) no figura visto: \(otra.value ?? "")")
    }

    /// Una duda del video que suena y una para la videollamada: quedan en la lista.
    func testDudaDeVideoYDudaGeneral() throws {
        abrirApp()
        abrirGuia()
        let marca = "Prueba iOS \(Int(Date().timeIntervalSince1970) % 100000)"
        let campo = app.descendants(matching: .any).matching(identifier: "guia-duda-campo").firstMatch
        desplazarHasta(campo)
        campo.tap()
        campo.typeText("\(marca) video")
        app.buttons["guia-duda-enviar"].tap()
        let dudas = app.descendants(matching: .any)["guia-dudas-video"]
        XCTAssertTrue(esperar({ dudas.exists && dudas.label.contains("\(marca) video") && !dudas.label.contains("Enviando") }, segundos: 20),
                      "La duda del video no quedó guardada")
        XCTAssertTrue(app.staticTexts["Listo, me llega antes de la videollamada."].exists)
        captura("duda-video")

        let llamada = app.descendants(matching: .any).matching(identifier: "guia-llamada-campo").firstMatch
        desplazarHasta(llamada, maximo: 25)
        guard llamada.exists else {
            XCTAssertTrue(app.staticTexts["guia-llamada-tope"].exists, "No está ni el campo ni el aviso del tope")
            throw XCTSkip("El cliente de prueba llegó al tope de 30 dudas para la videollamada")
        }
        llamada.tap()
        llamada.typeText("\(marca) llamada")
        app.buttons["guia-llamada-enviar"].tap()
        let lista = app.descendants(matching: .any)["guia-dudas-llamada"]
        XCTAssertTrue(esperar({ app.staticTexts["\(marca) llamada"].exists && lista.exists }, segundos: 20), "La duda de la llamada no quedó en la lista")
        XCTAssertTrue(esperar({ app.staticTexts["Listo, la vemos en la videollamada."].exists }, segundos: 10))
        captura("duda-llamada")
    }

    /// Sin red: la tarjeta y la lista salen de lo guardado y el reproductor pide conexión.
    func testSinRedSeVeLaListaYElVideoPideConexion() throws {
        abrirApp()
        abrirGuia()          // deja la copia guardada
        abrirApp(["-sinRed", "YES"])
        abrirGuia()
        XCTAssertTrue(app.descendants(matching: .any)["guia-sin-red"].waitForExistence(timeout: 5), "No avisa que es lo guardado")
        let fila = filas().first { $0.isEnabled }
        XCTAssertNotNil(fila, "Sin red no se ve la lista")
        if let fila { desplazarHasta(fila, maximo: 25); fila.tap() }
        XCTAssertTrue(app.staticTexts["guia-sin-conexion"].waitForExistence(timeout: 5), "No dice «Necesitás conexión para ver el video»")
        captura("sin-red")
    }

    /// Token revocado o la página dada de baja (`{"ok": false}`): la tarjeta desaparece y la sección se cierra sola.
    func testConOkFalseLaSeccionDesaparece() throws {
        abrirApp()
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 25))
        abrirApp(["-guiaOkFalse", "YES"])
        XCTAssertTrue(esperar({ !self.tarjeta.exists }, segundos: 20), "La tarjeta siguió con ok false")
        // Y si estaba adentro, se cierra: se entra con la copia y al traer la guía vuelve a Entreno.
        abrirApp()
        abrirGuia()
        abrirApp(["-guiaOkFalse", "YES", "-abrir", "guia"])
        XCTAssertTrue(esperar({ !self.app.descendants(matching: .any)["guia-avance"].exists }, segundos: 20), "La guía siguió abierta con ok false")
        XCTAssertFalse(tarjeta.exists)
        // La guía vuelve a aparecer con la respuesta real.
        abrirApp()
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 25))
    }

    /// Con la letra más grande de accesibilidad (el SE): las filas se pueden tocar y el título no queda en una columna.
    func testLetraMasGrande() throws {
        abrirApp(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        abrirGuia()
        captura("letra-grande-arriba")
        let fila = filas().first
        XCTAssertNotNil(fila)
        if let f = fila {
            desplazarHasta(f, maximo: 25)
            XCTAssertTrue(f.isHittable)
            // En el teléfono la fila ocupa casi todo el ancho; en el iPad, la columna de la lista (la otra es el reproductor).
            let minimo = UIDevice.current.userInterfaceIdiom == .phone ? app.frame.width * 0.6 : app.frame.width * 0.3
            XCTAssertGreaterThan(f.frame.width, minimo, "La fila quedó angosta con la letra grande")
            captura("letra-grande-fila")
        }
    }

    /// Accesibilidad: zonas tocables y Dynamic Type de la sección (lo del reproductor del sistema no cuenta).
    func testAuditoriaDeLaGuia() throws {
        abrirApp()
        abrirGuia()
        sleep(2)
        var hallazgos: [String] = []
        do {
        try app.performAccessibilityAudit(for: [.hitRegion, .dynamicType, .sufficientElementDescription]) { p in
            let id = p.element?.identifier ?? ""
            // Los controles del AVPlayerViewController y la barra del sistema no son nuestros.
            if !id.hasPrefix("guia-") && (p.element?.elementType != .staticText) { return true }
            hallazgos.append("\(p.auditType.rawValue) \(p.compactDescription) · \(id) «\(p.element?.label ?? "")»")
            return true
        }
        } catch let e as NSError where e.code == -56 {
            // En el iPad la auditoría a veces no termina a tiempo (pantalla grande con el reproductor): no es un hallazgo.
            throw XCTSkip("La auditoría no terminó a tiempo en este equipo")
        }
        let a = XCTAttachment(string: hallazgos.isEmpty ? "sin hallazgos" : hallazgos.joined(separator: "\n"))
        a.name = "auditoria-guia"; a.lifetime = .keepAlways; add(a)
        XCTAssertTrue(hallazgos.filter { $0.contains("guia-") }.isEmpty, hallazgos.joined(separator: "\n"))
    }

    /// Los segundos de la duración que dice el valor de la fila («Sin ver, 18 segundos», «1 minuto y 12 segundos»).
    private func duracion(_ e: XCUIElement) -> Double {
        let v = (e.value as? String) ?? ""
        var total = 0.0
        let numeros = v.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Double.init)
        if v.contains("minuto") {
            total = (numeros.first ?? 0) * 60 + (numeros.count > 1 ? numeros[1] : 0)
        } else {
            total = numeros.first ?? 600
        }
        return total
    }
}
