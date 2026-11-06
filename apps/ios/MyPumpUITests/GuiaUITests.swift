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
        // La demo («Ver demo») no usa cuenta: corre sin el token.
        if name.contains("Demo") || name.contains("Muestra") { return }
        guard let t = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !t.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan el cliente de prueba, nunca un cliente.")
        }
        token = t
    }

    private func abrirApp(_ extra: [String] = []) {
        app.terminate()
        // `-audioSinServidor`: estas pruebas no consultan las RPC de audio (las de audio van con dobles, AudioDudaUITests).
        // La bienvenida de la primera vez tiene sus propias pruebas (con la muestra): acá no tapa la tarjeta.
        app.launchArguments = ["-token", token, "-pestana", "entreno", "-sinOnboarding", "YES", "-audioSinServidor", "YES",
                               "-guiaBienvenida", "no"] + extra
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

    /// Desplaza hasta que el elemento quede entero en la zona visible: debajo de la barra de navegación y encima del
    /// teclado o de la barra de pestañas. `isHittable` solo no alcanza: un campo detrás de la barra translúcida de arriba
    /// da `true` y el toque se lo lleva la barra.
    private func desplazarHasta(_ e: XCUIElement, maximo: Int = 15) {
        for _ in 0..<maximo {
            guard e.exists else { app.swipeUp(velocity: .slow); continue }
            let z = zonaVisible(), f = e.frame
            let arribaBien = f.minY >= z.minY
            let abajoBien = f.maxY <= z.maxY || f.height > z.height
            if e.isHittable && arribaBien && abajoBien { return }
            // Arrastres medidos y con pausa al final, sin inercia, para no pasarse de largo.
            let tope = z.height * 0.6
            let d: CGFloat
            if !arribaBien { d = min(z.minY - f.minY + 24, tope) }        // está arriba: el dedo baja
            else if !abajoBien { d = -min(f.maxY - z.maxY + 24, tope) }   // está abajo: el dedo sube
            else { d = -tope }
            let origen = app.coordinate(withNormalizedOffset: .zero)
            let desde = origen.withOffset(CGVector(dx: z.midX, dy: z.midY - d / 2))
            let hasta = origen.withOffset(CGVector(dx: z.midX, dy: z.midY + d / 2))
            desde.press(forDuration: 0.05, thenDragTo: hasta, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    /// Lo que se ve de la pantalla entre la barra de navegación y el teclado (o la barra de pestañas).
    private func zonaVisible() -> CGRect {
        let ventana = app.frame
        let arriba = app.navigationBars.allElementsBoundByIndex
            .map(\.frame).filter { !$0.isEmpty && $0.minY < ventana.midY }.map(\.maxY).max() ?? ventana.minY
        var abajo = ventana.maxY
        let teclado = app.keyboards.firstMatch
        if teclado.exists, !teclado.frame.isEmpty { abajo = min(abajo, teclado.frame.minY) }
        let pestanas = app.tabBars.firstMatch
        if pestanas.exists, !pestanas.frame.isEmpty, pestanas.frame.minY > ventana.midY { abajo = min(abajo, pestanas.frame.minY) }
        return CGRect(x: ventana.minX, y: arriba, width: ventana.width, height: max(abajo - arriba, 1))
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

    // MARK: - Después de la entrega y demo

    private var evidencia: String? { ProcessInfo.processInfo.environment["GUIA_CAPTURAS"] }

    /// Captura adjunta y, si se pidió (`GUIA_CAPTURAS`, la carpeta de la maqueta), también en disco.
    private func capturaMaqueta(_ nombre: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = nombre; a.lifetime = .keepAlways; add(a)
        guard let dir = evidencia else { return }
        let equipo = app.frame.width < 380 ? "SE" : (UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "17Pro")
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ios-pe-\(nombre)-\(equipo).png"))
    }

    /// Mis datos, desde la pestaña Revisión.
    private func abrirMisDatos() {
        let pestana = app.pestana("Revisión")
        XCTAssertTrue(pestana.waitForExistence(timeout: 10))
        pestana.tap()
        let boton = app.buttons["Mis datos"].firstMatch
        XCTAssertTrue(boton.waitForExistence(timeout: 10))
        boton.tap()
        XCTAssertTrue(app.navigationBars["Mis datos"].waitForExistence(timeout: 10))
    }

    private var filaGuia: XCUIElement { app.buttons["mis-datos-guia"] }

    /// Hasta el pie de la guía, donde está «Quitar de Entreno» o «Volver a mostrar en Entreno».
    private func accionAlPie(_ id: String) -> XCUIElement {
        let b = app.buttons[id]
        var n = 0
        while !(b.exists && b.isHittable) && n < 40 { app.swipeUp(velocity: .fast); n += 1 }
        return b
    }

    /// 48 h después de la entrega (`mostrar_tarjeta` false, el resumen de verdad con ese campo cambiado): la tarjeta no
    /// está en Entreno; la fila «Ver mi guía» de Mis datos sí, y abre la guía.
    func testDespuesDeLaEntregaLaGuiaQuedaEnMisDatos() throws {
        abrirApp(["-guiaVolverAEntreno", "YES"])
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 25))
        abrirApp(["-guiaTarjeta", "no"])
        XCTAssertTrue(esperar({ !self.tarjeta.exists }, segundos: 20), "La tarjeta siguió en Entreno con mostrar_tarjeta false")
        XCTAssertTrue(app.pestana("Entreno").exists, "Tiene que seguir en Entreno")
        capturaMaqueta("entreno-sin-tarjeta")
        abrirMisDatos()
        desplazarHasta(filaGuia)
        XCTAssertTrue(filaGuia.waitForExistence(timeout: 10), "No está la fila «Ver mi guía»")
        XCTAssertEqual(filaGuia.label, "Ver mi guía")
        capturaMaqueta("fila")
        filaGuia.tap()
        XCTAssertTrue(app.descendants(matching: .any)["guia-avance"].waitForExistence(timeout: 20), "La fila no abrió la guía")
        // Con mostrar_tarjeta false no hay «Quitar de Entreno» ni «Volver a mostrar».
        _ = accionAlPie("guia-quitar-entreno")
        XCTAssertFalse(app.buttons["guia-quitar-entreno"].exists)
        XCTAssertFalse(app.buttons["guia-volver-entreno"].exists)
        // Con mostrar_tarjeta true la fila no está.
        abrirApp()
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 25))
        abrirMisDatos()
        let respaldo = app.buttons["Respaldo científico del plan"]
        desplazarHasta(respaldo)
        XCTAssertTrue(respaldo.exists)
        XCTAssertFalse(filaGuia.exists, "Con la tarjeta en Entreno la fila sobra")
    }

    /// «Quitar de Entreno»: la tarjeta sale (también al volver a abrir la app), la guía queda en Mis datos y desde ahí
    /// «Volver a mostrar en Entreno» la devuelve.
    func testQuitarDeEntrenoYVolverAMostrar() throws {
        addTeardownBlock { @MainActor in
            // Que una falla a mitad de camino no deje la tarjeta quitada para las demás pruebas.
            self.app.terminate()
            self.app.launchArguments = ["-token", self.token, "-pestana", "entreno", "-sinOnboarding", "YES", "-guiaVolverAEntreno", "YES",
                                        "-guiaBienvenida", "no"]
            self.app.launch()
            _ = self.tarjeta.waitForExistence(timeout: 25)
        }
        abrirApp(["-guiaVolverAEntreno", "YES"])
        abrirGuia()
        let quitar = accionAlPie("guia-quitar-entreno")
        XCTAssertTrue(quitar.exists, "No está «Quitar de Entreno» al pie de la guía")
        XCTAssertEqual(quitar.label, "Quitar de Entreno")
        capturaMaqueta("accion")
        quitar.tap()
        XCTAssertTrue(app.buttons["guia-volver-entreno"].waitForExistence(timeout: 5), "No ofrece volver a mostrarla")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(esperar({ !self.tarjeta.exists }, segundos: 5), "La tarjeta siguió en Entreno")
        // Queda guardado en el teléfono.
        abrirApp()
        sleep(3)
        XCTAssertFalse(tarjeta.exists, "Al volver a abrir la app la tarjeta volvió")
        abrirMisDatos()
        desplazarHasta(filaGuia)
        XCTAssertTrue(filaGuia.waitForExistence(timeout: 10))
        filaGuia.tap()
        XCTAssertTrue(app.descendants(matching: .any)["guia-avance"].waitForExistence(timeout: 20))
        let volver = accionAlPie("guia-volver-entreno")
        XCTAssertTrue(volver.exists, "No está «Volver a mostrar en Entreno»")
        capturaMaqueta("volver")
        volver.tap()
        XCTAssertTrue(app.buttons["guia-quitar-entreno"].waitForExistence(timeout: 5))
        app.pestana("Entreno").tap()
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 10), "La tarjeta no volvió a Entreno")
    }

    /// «Ver demo» (la revisión de Apple, sin cuenta): la tarjeta de la guía está en Entreno y abre los clips de «Tu app».
    func testDemoTieneLaGuia() throws {
        app.terminate()
        app.launchArguments = ["-entrar", "demo", "-sinOnboarding", "YES", "-pestana", "entreno"]
        app.launch()
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 15), "La demo no muestra la tarjeta de «Tu guía»")
        // Sin ningún video visto, la destacada; en la demo de Apple, sin la bienvenida.
        let texto = app.descendants(matching: .any)["guia-tarjeta-texto"]
        // 2.2.0: la demo trae dos videos nuevos (FT-2a y FT-2d): la tarjeta es la de la novedad.
        XCTAssertTrue(texto.waitForExistence(timeout: 5) && texto.label == "Novedad en tu guía, 2 videos nuevos, 1 min",
                      "La tarjeta de la demo dice otra cosa: \(texto.label)")
        XCTAssertFalse(app.buttons["guia-bienvenida-ver"].exists, "La demo de Apple no lleva la bienvenida")
        capturaMaqueta("demo-tarjeta")
        tarjeta.tap()
        XCTAssertTrue(app.descendants(matching: .any)["guia-avance"].waitForExistence(timeout: 10), "No abrió la guía de la demo")
        // 2.2.0: abre con el bloque de la novedad desplegado (los dos nuevos); los otros 6 de «Tu app» quedan plegados.
        XCTAssertEqual(filas().map(\.identifier).sorted(), ["guia-fila-FT-2a", "guia-fila-FT-2d"], "La novedad tiene que traer los 2 nuevos")
        let titulo = app.staticTexts["guia-titulo-actual"]
        XCTAssertTrue(titulo.waitForExistence(timeout: 5))
        // Abre con lo nuevo, que va arriba de todo.
        XCTAssertEqual(titulo.label, "¿Qué subo en la revisión semanal?")
        capturaMaqueta("demo-guia")
        // Reproduce de verdad la URL pública: el primer nuevo queda visto al terminar.
        let primera = app.buttons["guia-fila-FT-2a"]
        desplazarHasta(primera)
        primera.tap()
        XCTAssertTrue(esperar({ (primera.value as? String ?? "").hasPrefix("Visto") }, segundos: 60),
                      "El video de la demo no se reprodujo hasta el final")
        capturaMaqueta("demo-reproduciendo")
        // Nada sale: no hay «Quitar de Entreno» que falle; si está, oculta la tarjeta solo en memoria.
        XCTAssertTrue(accionAlPie("guia-quitar-entreno").exists)
    }

    // MARK: - Guía destacada (con la muestra: sin token ni red)

    private func abrirMuestra(_ extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-bocetos", "YES", "-guiaMuestra", "YES", "-sinOnboarding", "YES", "-pestana", "entreno"] + extra
        app.launch()
    }

    private var destacada: XCUIElement { app.descendants(matching: .any)["guia-destacada"] }

    /// La primera vez, con 0 vistos: la bienvenida con el nombre; «Más tarde» deja la tarjeta verde y no vuelve a salir;
    /// «Ver mi guía» (otro arranque) abre la guía.
    func testMuestraBienvenidaConCeroVistosAbreLaGuia() throws {
        abrirMuestra(["-guiaVistos", "ninguno"])
        let titulo = app.staticTexts["guia-bienvenida-titulo"]
        XCTAssertTrue(titulo.waitForExistence(timeout: 15), "No apareció la bienvenida con 0 vistos")
        XCTAssertEqual(titulo.label, "Hola Tomás")
        let texto = app.staticTexts["guia-bienvenida-texto"]
        XCTAssertTrue(texto.label.hasPrefix("Antes de empezar, mirá tu guía. Son 11 videos cortos"), texto.label)
        XCTAssertTrue(app.buttons["guia-bienvenida-ver"].isHittable)
        capturaMaqueta("destacada-bienvenida")
        app.buttons["guia-bienvenida-despues"].tap()
        XCTAssertTrue(esperar({ !titulo.exists }, segundos: 5), "«Más tarde» no cerró la bienvenida")
        XCTAssertTrue(destacada.waitForExistence(timeout: 5), "Sin ningún video visto va la tarjeta destacada")
        XCTAssertEqual(tarjeta.label, "Ver mi guía")
        XCTAssertTrue(app.buttons["guia-ocultar"].exists)
        // Una sola vez: no vuelve a salir en esta sesión.
        sleep(3)
        XCTAssertFalse(titulo.exists, "La bienvenida volvió a salir")
        // «Ver mi guía» desde la bienvenida abre la guía en Entreno.
        abrirMuestra(["-guiaVistos", "ninguno"])
        XCTAssertTrue(app.buttons["guia-bienvenida-ver"].waitForExistence(timeout: 15))
        app.buttons["guia-bienvenida-ver"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["guia-avance"].waitForExistence(timeout: 10), "«Ver mi guía» no abrió la guía")
        XCTAssertTrue(app.pestana("Entreno").isSelected)
    }

    /// A mitad de camino: la destacada con «Seguir viendo»; «Ocultar» la pasa a Mis datos con el aviso y «Deshacer» la
    /// devuelve. Sin deshacer, queda la fila de Mis datos.
    func testMuestraTarjetaDestacadaOcultarYDeshacer() throws {
        abrirMuestra()
        XCTAssertTrue(destacada.waitForExistence(timeout: 15), "No está la tarjeta destacada")
        XCTAssertFalse(app.staticTexts["guia-bienvenida-titulo"].exists, "Con videos vistos no va la bienvenida")
        XCTAssertEqual(tarjeta.label, "Seguir viendo")
        let texto = app.descendants(matching: .any)["guia-tarjeta-texto"]
        XCTAssertEqual(texto.label, "Tu guía, 4 de 11 videos, te quedan 6 min")
        // Va primera, arriba del título del día.
        // (el título del día de la lista, no el de la barra, que está más arriba y oculto)
        if let dia = app.staticTexts.matching(identifier: "Tirón A — Ancho").allElementsBoundByIndex.max(by: { $0.frame.minY < $1.frame.minY }) {
            XCTAssertLessThan(destacada.frame.minY, dia.frame.minY, "La tarjeta tiene que ir arriba de todo")
        }
        let ocultar = app.buttons["guia-ocultar"]
        XCTAssertGreaterThanOrEqual(ocultar.frame.height, 44)
        XCTAssertGreaterThanOrEqual(ocultar.frame.width, 44)
        ocultar.tap()
        let aviso = app.descendants(matching: .any)["guia-aviso-oculta"]
        XCTAssertTrue(aviso.waitForExistence(timeout: 3), "No apareció el aviso")
        XCTAssertTrue(app.staticTexts["La encontrás en Mis datos"].exists)
        XCTAssertFalse(destacada.exists, "La tarjeta siguió en Entreno")
        capturaMaqueta("destacada-aviso")
        app.buttons["guia-deshacer"].tap()
        XCTAssertTrue(destacada.waitForExistence(timeout: 3), "«Deshacer» no la devolvió")
        XCTAssertTrue(esperar({ !aviso.exists }, segundos: 3))
        // Sin deshacer: el aviso se va solo y la guía queda en Mis datos.
        app.buttons["guia-ocultar"].tap()
        XCTAssertTrue(aviso.waitForExistence(timeout: 3))
        XCTAssertTrue(esperar({ !aviso.exists }, segundos: 15), "El aviso no se fue solo")
        abrirMisDatos()
        desplazarHasta(filaGuia)
        XCTAssertTrue(filaGuia.waitForExistence(timeout: 10), "No está la fila «Ver mi guía» en Mis datos")
    }

    /// Con todo visto, la compacta de siempre (sin «Ocultar» ni bienvenida), y abre la guía.
    func testMuestraTarjetaCompactaConTodoVisto() throws {
        abrirMuestra(["-guiaVistos", "todos"])
        XCTAssertTrue(tarjeta.waitForExistence(timeout: 15))
        XCTAssertFalse(destacada.exists, "Con todo visto no va la destacada")
        XCTAssertFalse(app.buttons["guia-ocultar"].exists)
        XCTAssertFalse(app.staticTexts["guia-bienvenida-titulo"].exists)
        XCTAssertTrue(tarjeta.label.contains("Viste los 11 videos"), tarjeta.label)
        capturaMaqueta("destacada-compacta")
        tarjeta.tap()
        XCTAssertTrue(app.descendants(matching: .any)["guia-avance"].waitForExistence(timeout: 10))
    }

    /// Letra más grande: la destacada entra sin cortar palabras y sus botones se tocan.
    func testMuestraDestacadaConLetraGrande() throws {
        abrirMuestra(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(destacada.waitForExistence(timeout: 15))
        XCTAssertLessThanOrEqual(destacada.frame.width, app.frame.width)
        let ocultar = app.buttons["guia-ocultar"]
        desplazarHasta(ocultar)
        XCTAssertTrue(ocultar.isHittable, "«Ocultar» no se puede tocar con la letra grande")
        desplazarHasta(tarjeta)
        XCTAssertTrue(tarjeta.isHittable)
        capturaMaqueta("destacada-letra-grande")
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
