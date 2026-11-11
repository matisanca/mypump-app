import XCTest

/// El check guiado contra un servidor de mentira (`-checkGuiadoDePrueba`, sin red). Lo fino de lo que se escribe está en
/// el kit (`CheckGuiadoModeloTests`); acá va lo que solo se ve con la pantalla de verdad: que se encuentra solo, que se
/// entiende paso por paso y que se retoma.
@MainActor
final class CheckGuiadoUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CG_DIR"] }
    private var variante = "claro"
    private var token = ""

    override func setUp() async throws {
        continueAfterFailure = false
        token = "tkcheck" + UUID().uuidString.prefix(10).lowercased()
    }

    private func lanzar(_ escenario: String, pestana: String = "revision", extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana, "-checkGuiadoDePrueba", escenario] + extra
        if variante == "oscuro" { app.launchArguments += ["-mypump-theme", "dark"] }
        if variante == "grande" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] }
        app.launch()
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func esperar(_ id: String, _ t: TimeInterval = 25, file: StaticString = #filePath, line: UInt = #line) {
        if e(id).waitForExistence(timeout: t) { return }
        foto("fallo-\(id)")
        XCTFail("No apareció \(id)", file: file, line: line)
    }
    private func tocar(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        esperar(id, file: file, line: line)
        var n = 0
        while !e(id).isHittable && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
        e(id).tap()
    }
    private func titulo(_ texto: String, file: StaticString = #filePath, line: UInt = #line) {
        let t = app.staticTexts[texto].firstMatch
        if !t.waitForExistence(timeout: 10) { foto("fallo-titulo"); XCTFail("No está el paso «\(texto)»", file: file, line: line) }
    }
    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(variante)-\(nombre).png")) }
    }
    private func escribir(_ id: String, _ texto: String) {
        tocar(id)
        e(id).typeText(texto)
    }
    private func elegirEscalas() {
        for (clave, n) in [("energia", 4), ("descanso", 3), ("hambre", 2), ("adherencia", 5)] { tocar("cg-escala-\(clave)-\(n)") }
    }

    /// De la tarjeta a «Listo», paso por paso. `fotos`: saca las capturas de cada pantalla.
    private func recorrido(_ escenario: String, fotos: Bool) {
        lanzar(escenario)
        esperar("check-guiado-tarjeta")
        XCTAssertTrue(app.staticTexts["Un minuto: tu peso, cómo venís y tus fotos. Mati lo ve antes de tu devolución."].exists)
        if fotos { foto("00-tarjeta") }
        tocar("check-guiado-abrir")

        titulo("¿Cuánto pesaste hoy?")
        XCTAssertEqual(e("cg-avance").label, "Paso 1 de 6")
        XCTAssertFalse(e("cg-seguir").isEnabled, "Sin peso no se sigue: para eso está «Hoy no me pesé»")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Media de 7 días'")).firstMatch.exists)
        if fotos { foto("01-peso") }
        escribir("cg-peso", "12")
        tocar("cg-seguir")
        XCTAssertTrue(app.staticTexts["Revisá el peso: tiene que estar entre 30 y 300 kg."].waitForExistence(timeout: 5))
        e("cg-peso").typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "78,4")
        if fotos { foto("02-peso-cargado") }
        tocar("cg-seguir")

        titulo("¿Cómo venís esta semana?")
        XCTAssertFalse(e("cg-seguir").isEnabled)
        tocar("cg-escala-energia-4")
        XCTAssertTrue(app.staticTexts["Faltan: Descanso, Hambre, Adherencia"].waitForExistence(timeout: 5))
        for (clave, n) in [("descanso", 3), ("hambre", 2), ("adherencia", 5)] { tocar("cg-escala-\(clave)-\(n)") }
        if fotos { foto("03-escalas") }
        tocar("cg-seguir")

        titulo("Tus fotos de la semana")
        XCTAssertFalse(e("cg-seguir").isEnabled, "Sin las tres fotos, la salida es «Las subo después»")
        if fotos { foto("04-fotos") }
        tocar("cg-omitir")

        let efectos = escenario.hasPrefix("ciclo")
        titulo(efectos ? "¿Notaste algo de esto?" : "¿Algo de esto esta semana?")
        XCTAssertFalse(e("cg-seguir").isEnabled)
        let primera = efectos ? "acne" : "dolor"
        tocar("cg-senal-\(primera)")
        tocar("cg-senal-animo")
        XCTAssertTrue(e("cg-senal-\(primera)").isSelected && e("cg-senal-animo").isSelected)
        tocar("cg-senal-ninguno")
        XCTAssertTrue(e("cg-senal-ninguno").isSelected)
        XCTAssertFalse(e("cg-senal-\(primera)").isSelected, "«Nada de esto» no convive con otra")
        tocar("cg-senal-\(primera)")
        XCTAssertFalse(e("cg-senal-ninguno").isSelected)
        if efectos {
            // Cada efecto marcado pide cuánto molesta: sin eso «Seguir» no avanza y lo dice.
            esperar("cg-intensidad-\(primera)-leve")
            tocar("cg-seguir")
            XCTAssertTrue(app.staticTexts["Elegí cuánto te molesta"].waitForExistence(timeout: 5))
            titulo("¿Notaste algo de esto?")
            if fotos { foto("05-senales-falta-intensidad") }
            tocar("cg-intensidad-\(primera)-moderado")
            XCTAssertTrue(e("cg-intensidad-\(primera)-moderado").isSelected)
            XCTAssertFalse(app.staticTexts["Elegí cuánto te molesta"].exists)
            if escenario == "cicloGlp1" {
                tocar("cg-senal-nauseas")
                tocar("cg-intensidad-nauseas-fuerte")
            }
        } else {
            XCTAssertFalse(e("cg-intensidad-\(primera)-leve").exists, "La lista general no pide intensidad")
        }
        if fotos { foto("05-senales") }
        tocar("cg-seguir")

        titulo("¿Algo que quieras contarme?")
        escribir("cg-nota", "Semana tranquila")
        if fotos { foto("06-nota") }
        tocar("cg-seguir")

        titulo("Así va tu check")
        XCTAssertTrue(e("cg-fila-peso").label.contains("78,4 kg"))
        XCTAssertTrue(e("cg-fila-escalas").label.contains("4 de 5"))
        XCTAssertTrue(e("cg-fila-escalas-hambre").label.contains("2 de 5"))
        XCTAssertTrue(e("cg-fila-fotos").label.contains("0 de 3"))
        XCTAssertTrue(e("cg-fila-nota").label.contains("Semana tranquila"))
        if efectos { XCTAssertTrue(e("cg-fila-senales").label.contains("Acné o piel grasa · Moderado"), e("cg-fila-senales").label) }
        if escenario == "cicloGlp1" { XCTAssertTrue(e("cg-fila-senales").label.contains("Náuseas · Fuerte"), e("cg-fila-senales").label) }
        XCTAssertEqual(e("cg-enviar").label, "Enviar mi check")
        if fotos { foto("07-resumen") }
        tocar("cg-enviar")

        esperar("cg-listo")
        if fotos { foto("08-listo") }
        tocar("cg-cerrar-listo")
        esperar("check-guiado-tarjeta")
        XCTAssertTrue(app.staticTexts["Enviado. Te faltan las fotos de la semana."].waitForExistence(timeout: 10))
        XCTAssertEqual(e("check-guiado-abrir").label, "Subir fotos")
        if fotos { foto("09-tarjeta-enviado") }
    }

    func testRecorridoCompleto() { recorrido("general", fotos: false) }

    func testEnCicloPreguntaLaListaDeCiclo() {
        lanzar("ciclo")
        tocar("check-guiado-abrir")
        tocar("cg-omitir")
        elegirEscalas()
        tocar("cg-seguir")
        tocar("cg-omitir")
        titulo("¿Notaste algo de esto?")
        esperar("cg-senal-acne")
        XCTAssertFalse(e("cg-senal-dolor").exists, "La lista general no va para quien está en ciclo")
        XCTAssertFalse(e("cg-senal-nauseas").exists, "Los digestivos son solo para quien usa un GLP-1")
    }

    /// Con GLP-1 la lista de efectos suma los digestivos, y cada efecto va con su intensidad hasta el resumen.
    func testConGlp1SumaLosDigestivosConIntensidad() { recorrido("cicloGlp1", fotos: false) }

    func testFueraDeCicloVaLaListaGeneral() {
        lanzar("general")
        tocar("check-guiado-abrir")
        tocar("cg-omitir")
        elegirEscalas()
        tocar("cg-seguir")
        tocar("cg-omitir")
        titulo("¿Algo de esto esta semana?")
        esperar("cg-senal-dolor")
        XCTAssertFalse(e("cg-senal-acne").exists)
        XCTAssertFalse(e("cg-senal-aplicacion").exists)
    }

    /// Guardado parcial: sale a medias, cierra la app y al volver sigue donde estaba, con lo contestado.
    func testSaleAMediasYRetomaDondeQuedo() {
        lanzar("general")
        tocar("check-guiado-abrir")
        escribir("cg-peso", "80")
        tocar("cg-seguir")
        elegirEscalas()
        tocar("cg-seguir")
        titulo("Tus fotos de la semana")
        tocar("cg-cerrar")
        esperar("check-guiado-tarjeta")
        XCTAssertTrue(app.staticTexts["Lo dejaste por la mitad. Seguís donde quedaste."].waitForExistence(timeout: 5))
        XCTAssertEqual(e("check-guiado-abrir").label, "Seguir")

        app.terminate()
        lanzar("general")
        esperar("check-guiado-tarjeta")
        XCTAssertEqual(e("check-guiado-abrir").label, "Seguir")
        tocar("check-guiado-abrir")
        titulo("Tus fotos de la semana")
        XCTAssertEqual(e("cg-avance").label, "Paso 3 de 6")
        tocar("cg-atras")
        titulo("¿Cómo venís esta semana?")
        XCTAssertTrue(e("cg-escala-energia-4").isSelected && e("cg-escala-adherencia-5").isSelected, "Lo contestado sigue ahí")
    }

    func testAbrirYSalirSinTocarNoDejaNadaAMedias() {
        lanzar("general")
        tocar("check-guiado-abrir")
        titulo("¿Cuánto pesaste hoy?")
        tocar("cg-cerrar")
        esperar("check-guiado-tarjeta")
        XCTAssertEqual(e("check-guiado-abrir").label, "Empezar")
    }

    /// Fácil de encontrar: la tarjeta es lo primero de Revisión, arriba de Recuperación, sin deslizar.
    func testLaTarjetaEsLoPrimeroDeRevision() {
        lanzar("general")
        esperar("check-guiado-tarjeta")
        XCTAssertTrue(e("check-guiado-abrir").isHittable, "El botón del check tiene que verse sin deslizar")
        let recuperacion = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Recuperación'")).firstMatch
        if recuperacion.exists { XCTAssertLessThan(e("check-guiado-tarjeta").frame.minY, recuperacion.frame.minY) }
        XCTAssertGreaterThanOrEqual(e("check-guiado-abrir").frame.height, 56)
        XCTAssertFalse(e("enviar-check").exists, "El check de antes no convive con el guiado")
    }

    /// Los avisos llevan directo: llegar a Revisión pidiendo el check abre el paso a paso.
    func testElAvisoAbreElCheckDirecto() {
        lanzar("general", extra: ["-ir", "check"])
        titulo("¿Cuánto pesaste hoy?")
        esperar("cg-seguir")
    }

    func testConElCheckEnviadoElAvisoNoAbreNada() {
        lanzar("enviado", extra: ["-ir", "check"])
        esperar("check-guiado-tarjeta")
        XCTAssertTrue(app.staticTexts["Enviado. Mati lo ve antes de tu devolución."].waitForExistence(timeout: 10))
        XCTAssertFalse(e("cg-seguir").exists)
        // «Cambiar algo» abre en el resumen con lo enviado.
        tocar("check-guiado-abrir")
        titulo("Así va tu check")
        XCTAssertEqual(e("cg-enviar").label, "Actualizar mi check")
        XCTAssertTrue(e("cg-fila-escalas").label.contains("4 de 5"))
        XCTAssertEqual(e("cg-avance").label, "Paso 5 de 5", "Con las tres fotos subidas no hay paso de fotos")
    }

    /// Palanca apagada: la Revisión de siempre, sin nada del check guiado.
    func testPalancaApagadaEsLaRevisionDeSiempre() {
        lanzar("apagado")
        esperar("enviar-check")
        XCTAssertFalse(e("check-guiado-tarjeta").exists)
        lanzar("apagado", extra: ["-ir", "check"])
        esperar("enviar-check")
        XCTAssertFalse(e("cg-seguir").exists)
    }

    /// Palanca prendida y la propuesta sin aplicar en la base: el check se manda igual (lo marcado no tiene dónde guardarse).
    func testSinLasFuncionesNuevasElCheckSeMandaIgual() {
        lanzar("sinServidor")
        tocar("check-guiado-abrir")
        tocar("cg-omitir")
        elegirEscalas()
        tocar("cg-seguir")
        tocar("cg-omitir")
        tocar("cg-senal-ninguno")
        tocar("cg-seguir")
        tocar("cg-seguir")
        tocar("cg-enviar")
        esperar("cg-listo")
    }

    /// Capturas para Mati (solo con CG_DIR): cada paso en claro, oscuro y letra grande.
    func testGaleria() throws {
        guard dir != nil else { throw XCTSkip("Sin CG_DIR no se sacan capturas") }
        for v in ["claro", "oscuro", "grande"] {
            variante = v
            token = "tkcheck" + UUID().uuidString.prefix(10).lowercased()
            recorrido("cicloGlp1", fotos: true)
            app.terminate()
        }
        variante = "claro"
        token = "tkcheck" + UUID().uuidString.prefix(10).lowercased()
        lanzar("general")
        tocar("check-guiado-abrir"); tocar("cg-omitir"); elegirEscalas(); tocar("cg-seguir"); tocar("cg-omitir")
        esperar("cg-senal-dolor")
        foto("05-senales-general")
        tocar("cg-cerrar")
        esperar("check-guiado-tarjeta")
        foto("00-tarjeta-a-medias")
    }
}
