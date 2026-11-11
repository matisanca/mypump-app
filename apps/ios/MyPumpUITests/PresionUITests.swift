import XCTest

/// «Presión arterial» contra el doble del servidor (`-presionDePrueba`, sin red). Las reglas y la cola están probadas en el kit;
/// acá va lo que solo se ve con la pantalla de verdad. `-presionSegundos` acorta las esperas de 5 minutos.
@MainActor
final class PresionUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    private static let alarma = ["dolor_pecho", "falta_aire", "cefalea_fuerte_nueva", "cambios_vista", "debilidad_un_lado", "dificultad_hablar", "confusion", "desmayo"]
    private static let guardiaSintomas = "Con lo que marcaste tiene que verte un médico ahora. Andá a una guardia."
    private static let guardiaPresion = "Con estos valores tiene que verte un médico hoy. Andá a una guardia."

    override func setUp() async throws { continueAfterFailure = false }

    /// `reposo`: los segundos del reposo de antes de la toma, aparte de las demás esperas (`-presionReposo`). `enEntreno`: la app
    /// abre como siempre, en su primera pestaña; si no, en Mis datos. `destino`: como si se hubiera tocado un aviso con ese destino.
    private func lanzar(_ escenario: String, segundos: Int = 2, reposo: Int? = 240, enEntreno: Bool = false, destino: String? = nil) {
        app = XCUIApplication()
        let token = "tkpresion" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-presionDePrueba", escenario, "-presionSegundos", "\(segundos)"]
        if !enEntreno { app.launchArguments += ["-pestana", "revision", "-abrir", "misdatos"] }
        if let reposo { app.launchArguments += ["-presionReposo", "\(reposo)"] }
        if let destino { app.launchArguments += ["-destinoDePrueba", destino] }
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        // El tamaño de accesibilidad más grande.
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func esperar(_ id: String, _ t: TimeInterval = 60) {
        if e(id).waitForExistence(timeout: t) { return }
        foto("fallo-\(id)")
        XCTFail("No apareció \(id)")
    }
    private func tocar(_ id: String) {
        esperar(id)
        var n = 0
        while !e(id).isHittable && n < 12 { app.swipeUp(velocity: .slow); n += 1 }
        // Con la Mac cargada el scroll sigue un instante: se espera a que frene para que el toque caiga en el control.
        if n > 0 { RunLoop.current.run(until: Date().addingTimeInterval(1.5)) }
        e(id).tap()
    }
    private func haciaAbajo(_ id: String, veces: Int = 6) {
        var n = 0
        while !e(id).waitForExistence(timeout: 2.5) && n < veces { app.swipeUp(velocity: .slow); n += 1 }
    }
    /// Para lo que está en el contenido (no en la barra de abajo): si quedó debajo de los botones fijos de abajo da «hittable»
    /// pero el toque cae en la barra, así que se sube antes.
    private func tocarArriba(_ id: String) {
        esperar(id)
        var n = 0
        while e(id).frame.maxY > app.frame.height * 0.62 && n < 6 { app.swipeUp(velocity: .slow); n += 1 }
        if n > 0 { RunLoop.current.run(until: Date().addingTimeInterval(1.5)) }
        tocar(id)
    }
    private func escribir(_ id: String, _ texto: String) {
        tocarArriba(id)
        e(id).typeText(texto)
    }
    private func foto(_ nombre: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ios-\(letraGrande ? "grande" : oscuro ? "oscuro" : "claro")-\(nombre).png")) }
    }

    private func abrir(_ escenario: String, segundos: Int = 2, reposo: Int? = 240) {
        lanzar(escenario, segundos: segundos, reposo: reposo)
        haciaAbajo("mis-datos-presion")
        tocar("mis-datos-presion")
    }

    /// De Inicio hasta la pantalla de anotar. `esperando`: deja correr el reposo (la toma cuenta); si no, «Ya esperé».
    private func hastaAnotar(esperando: Bool = false) {
        tocar("presion-toma")
        desdeCuando(esperando: esperando)
    }

    /// De «Cuándo» hasta la pantalla de anotar: un paso por pantalla.
    private func desdeCuando(esperando: Bool = false) {
        esperar("presion-cuando")
        tocar("presion-cuando-seguir")
        esperar("presion-como")
        tocar("presion-empezar")
        for k in ["cafeina", "fumo", "comida", "ejercicio"] { tocarArriba("presion-previa-\(k)-no") }
        tocar("presion-previa-seguir")
        esperar("presion-reposo")
        if !esperando { tocar("presion-saltear") }
        esperar("presion-alta", 30)
    }

    private func anotar(_ sis: String, _ dia: String, _ pulso: String) {
        escribir("presion-alta", sis)
        escribir("presion-baja", dia)
        escribir("presion-pulso", pulso)
        // El botón queda siempre a la vista, por encima del teclado: se toca sin scrollear.
        esperar("presion-anotar")
        XCTAssertTrue(e("presion-anotar").isHittable, "«Anotar la toma» tiene que verse con el teclado abierto")
        e("presion-anotar").tap()
        // Con la Mac cargada el toque puede caer mientras baja el teclado: si la pantalla sigue ahí, se toca de nuevo.
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        if e("presion-pulso").exists, e("presion-anotar").exists, e("presion-anotar").isEnabled, e("presion-anotar").isHittable { e("presion-anotar").tap() }
    }

    private func texto(_ id: String) -> String { e(id).label }

    // MARK: Recorridos

    func testTomaComunCompleta() {
        abrir("serie2", reposo: nil)
        esperar("presion-avance")
        XCTAssertEqual(texto("presion-avance-texto"), "Te falta 1 toma")
        XCTAssertEqual(e("presion-avance").label, "Tres círculos, uno por toma. Completaste dos de tres.")
        hastaAnotar(esperando: true)
        anotar("124", "78", "62")
        esperar("presion-listo")
        XCTAssertEqual(texto("presion-listo"), "Listo, terminaste las 3 tomas. Gracias.")
        XCTAssertFalse(e("presion-no-cuenta").exists)
        XCTAssertFalse(e("presion-revisar").exists)
        tocar("presion-cerrar")
        esperar("presion-hoy-listo")
        XCTAssertEqual(texto("presion-avance-texto"), "Listo, terminaste las 3 tomas")
        XCTAssertFalse(e("presion-toma").exists, "con la de hoy hecha no se ofrece otra")
    }

    func testTomaSaltandoElReposoNoCuenta() {
        abrir("serie0", segundos: 30)
        hastaAnotar()
        anotar("124", "78", "62")
        esperar("presion-no-cuenta")
        XCTAssertEqual(texto("presion-no-cuenta"), "Esta no cuenta. Hacé otra otro día, antes del café y del preentreno.")
        tocar("presion-cerrar")
        esperar("presion-toma")
        XCTAssertEqual(texto("presion-avance-texto"), "Te faltan 3 tomas")
    }

    func testToma160PideConfirmarYRepetir() {
        // La espera de la repetición, corta; el reposo, largo: «Ya esperé» no corre contra un temporizador de 3 segundos.
        abrir("serie0", segundos: 3, reposo: 240)
        hastaAnotar()
        anotar("160", "100", "70")
        esperar("presion-revisar")
        XCTAssertFalse(e("presion-espera").exists, "sin confirmar el número no sigue")
        tocar("presion-confirmar")
        esperar("presion-espera")
        XCTAssertEqual(texto("presion-espera"), "Quedate sentado y tranquilo. En 5 minutos volvé a medirte.")
        XCTAssertFalse(e("presion-espera-sintomas").exists, "la lista es solo con 180/120")
        tocar("presion-repetir-toma")
        anotar("150", "90", "68")
        // Se salteó el reposo: la toma se cierra sin guardia, con el aviso de que no cuenta.
        esperar("presion-no-cuenta")
        XCTAssertFalse(e("presion-guardia-presion").exists)
        XCTAssertFalse(e("presion-guardia-sintomas").exists)
    }

    func testToma180ConUnSiVaAGuardiaPorSintomas() {
        abrir("serie0", segundos: 90)
        hastaAnotar()
        anotar("182", "121", "80")
        tocar("presion-confirmar")
        esperar("presion-espera-sintomas")
        // Ninguna fila viene marcada.
        for c in Self.alarma {
            haciaAbajo("presion-alarma-\(c)-si", veces: 3)
            XCTAssertFalse(e("presion-alarma-\(c)-si").isSelected, c)
            XCTAssertFalse(e("presion-alarma-\(c)-no").isSelected, c)
        }
        tocar("presion-alarma-confusion-si")
        esperar("presion-guardia-sintomas")
        XCTAssertTrue(app.staticTexts[Self.guardiaSintomas].exists)
        XCTAssertFalse(app.staticTexts[Self.guardiaPresion].exists)
        tocar("presion-guardia-cerrar")
        esperar("presion-inicio")
    }

    func testToma180TodosNoYRepeticionAltaVaAGuardiaPorPresion() {
        abrir("serie0", segundos: 20)
        hastaAnotar()
        anotar("182", "121", "80")
        tocar("presion-confirmar")
        esperar("presion-espera-sintomas")
        for c in Self.alarma { tocar("presion-alarma-\(c)-no") }
        XCTAssertTrue(e("presion-alarma-desmayo-no").isSelected)
        XCTAssertFalse(e("presion-guardia-sintomas").exists, "con todos en No sigue la espera")
        haciaArriba("presion-repetir-toma")
        tocar("presion-repetir-toma")
        anotar("181", "122", "82")
        tocar("presion-confirmar")
        esperar("presion-guardia-presion")
        XCTAssertTrue(app.staticTexts[Self.guardiaPresion].exists)
        XCTAssertFalse(app.staticTexts[Self.guardiaSintomas].exists)
    }

    private func haciaArriba(_ id: String) {
        // Hasta el tope: debajo de la barra translúcida un botón figura tocable y el toque no le llega.
        app.swipeDown(); app.swipeDown()
        _ = e(id).waitForExistence(timeout: 40)
    }

    func testValorImposibleNoPasa() {
        abrir("serie0", segundos: 30)
        hastaAnotar()
        anotar("300", "80", "60")
        esperar("presion-revisar")
        XCTAssertEqual(texto("presion-revisar"), "Revisá el número que anotaste.")
        XCTAssertFalse(e("presion-confirmar").exists, "un valor imposible no se puede confirmar")
        XCTAssertTrue(e("presion-alta").exists)
        XCTAssertFalse(e("presion-listo").exists)
        XCTAssertFalse(e("presion-espera").exists)
        tocar("presion-flujo-cerrar")
        esperar("presion-sin-tomas")
    }

    /// Con el pulso de 120 o más la toma se guarda y después se abre la hoja de síntomas; lo marcado decide el paso.
    func testPulsoAltoGuardaLaTomaYDespuesPreguntaSintomas() {
        abrir("serie0", segundos: 30)
        hastaAnotar()
        anotar("128", "80", "125")
        // El pulso de 125 pide confirmar el número.
        tocar("presion-confirmar")
        esperar("presion-sintomas-hoja")
        // «Marcar un síntoma» y «Cerrar» son botones con texto debajo del principal, no ítems de la barra.
        XCTAssertFalse(app.navigationBars.buttons["presion-flujo-cerrar"].exists)
        XCTAssertTrue(e("presion-flujo-cerrar").isHittable)
        // «Palpitaciones» está en la segunda lista: se sube para que no quede debajo de los botones de abajo.
        app.swipeUp(velocity: .slow)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        tocar("presion-sintoma-palpitaciones")
        tocar("presion-sintomas-seguir")
        esperar("presion-guardia-sintomas")
        XCTAssertTrue(app.staticTexts[Self.guardiaSintomas].exists)
    }

    func testMarcarSintomaDeAlarmaDesdeElBoton() {
        abrir("sinSerie")
        tocar("presion-marcar-sintoma")
        tocar("presion-sintoma-palpitaciones")
        tocar("presion-sintoma-enviar")
        esperar("presion-sintoma-recibido")
        XCTAssertFalse(e("presion-guardia-sintomas").exists)
        tocar("presion-sintoma-cerrar")
        tocar("presion-marcar-sintoma")
        tocar("presion-sintoma-falta_aire")
        tocar("presion-sintoma-enviar")
        esperar("presion-guardia-sintomas")
        XCTAssertTrue(app.staticTexts[Self.guardiaSintomas].exists)
    }

    func testSinAparatoPideLaMedidaYElAparato() {
        abrir("vacio")
        esperar("presion-antes")
        XCTAssertFalse(e("presion-toma").exists)
        // Un paso por pantalla: leer, medir el brazo, anotar el tensiómetro.
        tocar("presion-antes-seguir")
        esperar("presion-medida")
        XCTAssertFalse(e("presion-antes-seguir").isEnabled, "sin la medida no sigue")
        escribir("presion-medida", "35")
        tocar("presion-antes-seguir")
        esperar("presion-tipo-brazo")
        XCTAssertFalse(e("presion-guardar").isEnabled, "sin elegir el aparato no guarda")
        tocar("presion-tipo-brazo")
        tocar("presion-guardar")
        esperar("presion-toma")
        XCTAssertTrue(e("presion-sin-tomas").exists)
    }

    // MARK: Fácil de encontrar: la tarjeta de arriba y los avisos

    func testTarjetaLlevaDirectoALaTomaDeHoy() {
        lanzar("serie0", enEntreno: true)
        esperar("tarjeta-presion", 40)
        XCTAssertTrue(app.staticTexts["Tu presión"].exists)
        XCTAssertTrue(app.staticTexts["Te faltan 3 tomas"].exists)
        XCTAssertTrue(app.staticTexts["Son 3 tomas, una por día"].exists)
        XCTAssertEqual(e("tarjeta-presion-boton").label, "Hacer la toma de hoy")
        XCTAssertTrue(e("tarjeta-presion-boton").isHittable, "arriba de todo, sin scrollear")
        XCTAssertGreaterThanOrEqual(e("tarjeta-presion-boton").frame.height, 56)
        // Dos toques: la tarjeta y el botón de la pantalla.
        e("tarjeta-presion-boton").tap()
        desdeCuando()
        anotar("124", "78", "62")
        esperar("presion-no-cuenta")
        tocar("presion-cerrar")
        esperar("presion-inicio")
    }

    func testTarjetaRepetirAbreLaRepeticion() {
        lanzar("pendienteAlta", enEntreno: true)
        esperar("tarjeta-presion", 40)
        XCTAssertTrue(app.staticTexts["Te quedó pendiente repetir la toma. Hacela sentado y tranquilo cuando puedas."].exists)
        XCTAssertEqual(e("tarjeta-presion-boton").label, "Repetir la toma")
        e("tarjeta-presion-boton").tap()
        esperar("presion-alta", 30)
        anotar("150", "90", "68")
        // La repetición retomada no trae las previas ni el reposo: por eso nunca dice «Esta no cuenta».
        esperar("presion-listo")
        XCTAssertFalse(e("presion-no-cuenta").exists, "una repetición retomada no dice que no cuenta")
        tocar("presion-cerrar")
        esperar("presion-inicio")
        XCTAssertFalse(e("presion-pendiente").exists)
    }

    func testTarjetaPrepararYHoyListo() {
        lanzar("medirDeNuevo", enEntreno: true)
        esperar("tarjeta-presion", 40)
        XCTAssertTrue(app.staticTexts["Primero medí tu brazo y anotá tu tensiómetro"].exists)
        XCTAssertEqual(e("tarjeta-presion-boton").label, "Empezar")
        e("tarjeta-presion-boton").tap()
        esperar("presion-medir-de-nuevo", 30)
        app.terminate()

        lanzar("hoyListo", enEntreno: true)
        esperar("tarjeta-presion", 40)
        XCTAssertFalse(e("tarjeta-presion-boton").exists, "con la de hoy hecha no hay botón")
        XCTAssertTrue(e("tarjeta-presion").label.contains("La de hoy ya está. La próxima, otro día."))
        e("tarjeta-presion").tap()
        esperar("presion-hoy-listo", 30)
    }

    func testSinNadaParaHacerNoHayTarjetaYLaRutinaSigueIgual() {
        for escenario in ["sinSerie", "apagado", "sinServidor", "vacio"] {
            lanzar(escenario, enEntreno: true)
            XCTAssertTrue(app.tabBars.buttons["Entreno"].waitForExistence(timeout: 40), escenario)
            RunLoop.current.run(until: Date().addingTimeInterval(6))
            XCTAssertFalse(e("tarjeta-presion").exists, escenario)
            app.terminate()
        }
    }

    func testAvisoConDestinoPresionAbreLaRepeticion() {
        lanzar("pendienteAlta", enEntreno: true, destino: "presion")
        esperar("presion-alta", 60)
        XCTAssertFalse(e("presion-inicio").isHittable, "no pasa por la pantalla de inicio")
        app.terminate()
        // Apagada, el mismo aviso no abre nada.
        lanzar("apagado", enEntreno: true, destino: "presion")
        XCTAssertTrue(app.tabBars.buttons["Entreno"].waitForExistence(timeout: 40))
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        XCTAssertFalse(e("presion-alta").exists)
        XCTAssertFalse(e("presion-cerrar-seccion").exists)
    }

    func testComparacionDeBrazosVaAntesDeLaTomaDelDia() {
        abrir("brazos")
        tocar("presion-toma")
        esperar("presion-brazos")
        XCTAssertFalse(e("presion-cuando").exists)
    }

    func testComoSeNumeraDesdeUno() {
        abrir("serie0", segundos: 30)
        tocar("presion-toma")
        esperar("presion-cuando")
        tocar("presion-cuando-seguir")
        esperar("presion-como")
        haciaAbajo("presion-como-pasos")
        let primero = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "1. Sentate en una silla con respaldo")).firstMatch
        var n = 0
        while !primero.exists && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
        XCTAssertTrue(primero.exists, "los pasos de «Cómo» empiezan en 1")
    }

    func testPalancaApagadaLaFilaNoExiste() {
        for escenario in ["apagado", "sinServidor"] {
            lanzar(escenario)
            // La fila iría justo arriba de «Respaldo científico del plan»: con esa a la vista, si existiera se vería.
            let vecina = app.staticTexts["Respaldo científico del plan"]
            var n = 0
            while !(vecina.waitForExistence(timeout: 3) && vecina.isHittable) && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
            XCTAssertTrue(vecina.exists, escenario)
            XCTAssertFalse(e("mis-datos-presion").exists, escenario)
            app.terminate()
        }
    }

    // MARK: Capturas

    private func capturas() {
        abrir("serie2", segundos: 240)
        esperar("presion-avance")
        foto("inicio")
        app.swipeUp(velocity: .slow)
        foto("inicio-tomas")
        haciaArriba("presion-toma")
        tocar("presion-toma")
        esperar("presion-cuando")
        foto("cuando")
        tocar("presion-que-evitar")
        esperar("presion-evitar-1")
        foto("que-evitar")
        tocar("presion-evitar-cerrar")
        tocar("presion-cuando-seguir")
        esperar("presion-como")
        foto("como")
        app.swipeUp(velocity: .slow)
        foto("como-1")
        app.swipeUp(velocity: .slow)
        foto("como-2")
        app.swipeUp(velocity: .slow)
        foto("como-3")
        tocar("presion-empezar")
        esperar("presion-previa-cafeina")
        foto("previa")
        for k in ["cafeina", "fumo", "comida", "ejercicio"] { tocarArriba("presion-previa-\(k)-no") }
        tocar("presion-previa-seguir")
        esperar("presion-reposo")
        foto("reposo")
        tocar("presion-saltear")
        esperar("presion-alta")
        escribir("presion-alta", "182")
        escribir("presion-baja", "121")
        escribir("presion-pulso", "80")
        foto("anotar")
        // Con el teclado abierto: el botón sigue a la vista y el tilde de latido irregular se alcanza.
        tocar("presion-alta")
        foto("anotar-teclado")
        XCTAssertTrue(e("presion-anotar").isHittable)
        // En el pulso, con el teclado arriba, el tilde de latido irregular se trae a la vista.
        tocar("presion-pulso")
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        foto("anotar-teclado-pulso")
        XCTAssertTrue(e("presion-irregular").isHittable, "el tilde de latido irregular no puede quedar tapado por el teclado")
        XCTAssertTrue(e("presion-anotar").isHittable)
        tocar("presion-anotar")
        esperar("presion-revisar")
        foto("confirmar")
        tocar("presion-confirmar")
        esperar("presion-espera-sintomas")
        foto("espera-sintomas")
        tocar("presion-alarma-dolor_pecho-no")
        tocar("presion-alarma-falta_aire-no")
        app.swipeUp(velocity: .slow)
        foto("espera-sintomas-2")
        tocar("presion-alarma-confusion-si")
        esperar("presion-guardia-sintomas")
        foto("guardia")
        app.terminate()

        abrir("vacio")
        esperar("presion-antes")
        foto("antes")
        tocar("presion-antes-seguir")
        esperar("presion-medida")
        foto("antes-medir")
        escribir("presion-medida", "44")
        app.swipeUp(velocity: .slow)
        foto("antes-talles")
        tocar("presion-antes-seguir")
        esperar("presion-tipo-brazo")
        tocar("presion-tipo-brazo")
        foto("antes-aparato")
        app.terminate()
    }

    /// La tarjeta de arriba en Entreno, en sus cuatro estados.
    private func capturasTarjeta() {
        for (escenario, nombre) in [("serie0", "toma"), ("serie2", "seguir"), ("pendienteAlta", "repetir"), ("medirDeNuevo", "preparar"), ("hoyListo", "hoy-listo")] {
            lanzar(escenario, enEntreno: true)
            esperar("tarjeta-presion", 40)
            foto("tarjeta-\(nombre)")
            app.terminate()
        }
    }

    func testCapturasTarjetaClaro() { capturasTarjeta() }
    func testCapturasTarjetaOscuro() { oscuro = true; capturasTarjeta() }
    func testCapturasTarjetaLetraGrande() { letraGrande = true; capturasTarjeta() }

    func testCapturasClaro() { capturas() }
    func testCapturasOscuro() { oscuro = true; capturas() }
    func testCapturasLetraGrande() { letraGrande = true; capturas() }
}
