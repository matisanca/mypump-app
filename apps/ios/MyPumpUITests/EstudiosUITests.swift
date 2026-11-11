import XCTest

/// Estudios y órdenes contra el doble del servidor (`-estudiosDePrueba`, sin red y con datos inventados). Lo fino de la cola
/// está en el kit; acá va lo que solo se ve con la pantalla de verdad, y las capturas.
@MainActor
final class EstudiosUITests: XCTestCase {
    private var app = XCUIApplication()
    private var dir: String? { ProcessInfo.processInfo.environment["CARGA_DIR"] }
    private var oscuro = false
    private var letraGrande = false

    private func id(_ n: Int) -> String { String(format: "%08d-0000-4000-8000-000000000000", n) }

    override func setUp() async throws { continueAfterFailure = false }

    private func lanzar(_ escenario: String, pestana: String = "revision", extra: [String] = []) {
        app = XCUIApplication()
        // Un token distinto por prueba: la cola queda en disco y no se mezcla.
        let token = "tkestudios" + UUID().uuidString.prefix(8).lowercased()
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES", "-pestana", pestana, "-estudiosDePrueba", escenario] + extra
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        if letraGrande { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
    }

    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func esperar(_ id: String, _ t: TimeInterval = 40) {
        if e(id).waitForExistence(timeout: t) { return }
        foto("fallo-\(id)")
        XCTFail("No apareció \(id)")
    }
    private func pausa(_ s: TimeInterval = 0.5) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    /// Sube la pantalla de a poco hasta que el elemento se pueda tocar y no quede pegado al borde de abajo.
    private func traer(_ id: String) {
        // Mis datos es una lista perezosa: con letra grande la fila no existe hasta que se llega a ella.
        var b = 0
        while !e(id).waitForExistence(timeout: b == 0 ? 6 : 1) && b < 12 { subir(); b += 1 }
        esperar(id)
        var n = 0
        while (!e(id).isHittable || e(id).frame.maxY > app.frame.maxY - 60) && n < 25 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            n += 1
        }
        pausa(0.8)   // que la lista termine de frenar: un toque en pleno desplazamiento no entra
    }
    private func tocar(_ id: String) { traer(id); e(id).tap() }
    private func texto(_ s: String) -> XCUIElement { app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch }
    private func foto(_ nombre: String) {
        pausa(0.7)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = nombre; a.lifetime = .keepAlways; add(a)
        if let dir { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(letraGrande ? "letra-grande" : oscuro ? "oscuro" : "claro")-\(nombre).png")) }
    }
    private func subir(_ veces: Int = 1) {
        for _ in 0..<veces { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))); pausa(0.3) }
    }

    private func abrirMisDatos() {
        let datos = app.buttons["Mis datos"].firstMatch
        XCTAssertTrue(datos.waitForExistence(timeout: 20))
        datos.tap()
        XCTAssertTrue(app.navigationBars["Mis datos"].waitForExistence(timeout: 10))
    }

    private func abrirEstudios() {
        abrirMisDatos()
        tocar("mis-datos-estudios")
        esperar("estudios-subir")
    }

    /// La pantalla entera, la hoja de subida con tres archivos, el envío, el detalle de una orden y el PDF dentro de la app.
    private func recorrido() {
        lanzar("completo", extra: ["-estudiosLento", "YES"])
        abrirMisDatos()
        traer("mis-datos-estudios")
        XCTAssertTrue(texto("Te faltan 3 estudios").exists)
        foto("0-mis-datos")
        e("mis-datos-estudios").tap()
        esperar("estudios-proximo-control")
        XCTAssertTrue(texto("Semana del 23/11").exists)
        XCTAssertTrue(texto("Era para el jueves 5/11").exists)
        foto("1-pantalla-a")
        traer("estudios-subir")
        XCTAssertTrue(texto("Entre el lunes 16/11 y el jueves 19/11").exists || letraGrande)
        foto("1-pantalla-b")
        traer("estudios-orden-\(id(12))")
        foto("1-pantalla-c")
        traer("estudios-nota")
        subir()
        XCTAssertTrue(texto("Mati lo vio").exists)
        XCTAssertTrue(texto("Recibido quiere decir que llegó").exists)
        foto("1-pantalla-d")

        // Hoja de subida: dos fotos y un PDF.
        tocar("estudios-subir")
        esperar("estudios-guia")
        foto("2-subida-vacia")
        tocar("estudios-sacar-fotos")
        tocar("estudios-elegir-fotos")
        tocar("estudios-elegir-pdf")
        esperar("estudios-enviar")
        XCTAssertTrue(app.buttons["Enviar 3 archivos"].waitForExistence(timeout: 40))
        XCTAssertTrue(texto("PDF 1").exists)
        foto("2-subida")
        e("estudios-quitar").tap()
        XCTAssertTrue(app.buttons["Enviar 2 archivos"].waitForExistence(timeout: 5))
        tocar("estudios-elegir-pdf")
        XCTAssertTrue(app.buttons["Enviar 3 archivos"].waitForExistence(timeout: 40))
        e("estudios-enviar").tap()
        esperar("estudios-subiendo")
        traer("estudios-subiendo")
        XCTAssertTrue(texto("Subiendo").exists)
        foto("2-subiendo")
        esperar("estudios-aviso", 30)
        XCTAssertTrue(texto("Recibido. Mati lo revisa y te escribe.").exists)
        traer("estudios-aviso")
        foto("2-recibido")

        // Detalle de una orden y el PDF dentro de la app.
        tocar("estudios-orden-\(id(11))")
        esperar("estudios-ver-orden")
        XCTAssertTrue(texto("Emitida el 3/11 · Vale hasta el 2/1").exists)
        XCTAssertTrue(texto("Ayuno de 8 a 12 horas").exists)
        foto("3-orden-a")
        traer("estudios-donde")
        subir()
        XCTAssertTrue(texto("No dejes ninguna medicación sin que Mati te lo diga.").exists)
        XCTAssertTrue(texto("En cualquier laboratorio de análisis clínicos").exists)
        foto("3-orden-b")
        for _ in 0..<6 { app.swipeDown() }
        tocar("estudios-ver-orden")
        esperar("estudios-visor")
        foto("4-orden-pdf")
        e("estudios-visor-cerrar").tap()
        esperar("estudios-ver-orden")
    }

    func testRecorridoYCapturasClaro() { recorrido() }
    func testCapturasOscuro() { oscuro = true; recorrido() }
    func testCapturasLetraGrande() { letraGrande = true; recorrido() }

    func testYaMeLoHiceYDeshacer() {
        lanzar("completo")
        abrirEstudios()
        tocar("estudios-hecho-boton-\(id(2))")
        esperar("estudios-fecha-guardar")
        XCTAssertTrue(texto("¿Cuándo te lo hiciste?").exists)
        foto("5-fecha")
        tocar("estudios-fecha-guardar")
        // El doble vive el 10/11/2026: la fecha de hoy del simulador queda fuera de su ventana o dentro, según el día.
        if e("estudios-fecha-error").waitForExistence(timeout: 4) {
            XCTAssertTrue(texto("Revisá la fecha.").exists)
            app.buttons["Cancelar"].firstMatch.tap()
        } else {
            esperar("estudios-hecho-\(id(2))")
            XCTAssertTrue(texto("Falta subir el resultado.").exists)
        }
        // El que ya venía hecho se puede deshacer.
        tocar("estudios-deshacer-\(id(3))")
        esperar("estudios-hecho-boton-\(id(3))")
        XCTAssertTrue(texto("Antes del viernes 27/11").exists)
    }

    func testVerOrdenDesdeElPendienteYVerUnEstudioPropio() {
        lanzar("completo")
        abrirEstudios()
        tocar("estudios-ver-orden-\(id(2))")
        esperar("estudios-visor")
        e("estudios-visor-cerrar").tap()
        // Solo el que el servidor deja abrir tiene «Ver».
        tocar("estudios-ver-\(id(22))")
        esperar("estudios-visor")
        e("estudios-visor-cerrar").tap()
        XCTAssertFalse(e("estudios-ver-\(id(21))").exists)
        XCTAssertFalse(e("estudios-orden-\(id(13))").exists, "La vencida no se abre")
        XCTAssertTrue(e("estudios-orden-vencida-\(id(13))").exists)
        XCTAssertTrue(texto("Vencida. Si la necesitás, pedísela a Mati por el chat.").exists)
    }

    func testSubirResultadoDesdeElPendiente() {
        lanzar("completo")
        abrirEstudios()
        tocar("estudios-subir-\(id(2))")
        XCTAssertTrue(app.navigationBars["Subir resultado"].waitForExistence(timeout: 40))
        tocar("estudios-elegir-pdf")
        XCTAssertTrue(app.buttons["Enviar 1 archivo"].waitForExistence(timeout: 40))
        e("estudios-enviar").tap()
        esperar("estudios-aviso", 30)
        XCTAssertTrue(texto("Recibido. Mati lo revisa y te escribe.").exists)
    }

    func testArchivoRechazado() {
        lanzar("rechazo")
        abrirEstudios()
        tocar("estudios-subir")
        tocar("estudios-sacar-fotos")
        esperar("estudios-enviar")
        e("estudios-enviar").tap()
        esperar("estudios-aviso", 30)
        XCTAssertTrue(texto("No pudimos leer ese archivo. Probá con una foto o un PDF.").exists)
        XCTAssertFalse(texto("Recibido. Mati lo revisa").exists)
    }

    func testTopeDelDia() {
        lanzar("topeDia")
        abrirEstudios()
        tocar("estudios-subir")
        tocar("estudios-elegir-pdf")
        esperar("estudios-enviar")
        e("estudios-enviar").tap()
        esperar("estudios-aviso", 30)
        XCTAssertTrue(texto("Ya mandaste varios envíos hoy. Probá mañana o escribile a Mati.").exists)
    }

    func testSinSenalAlSubirQuedaEnCola() {
        lanzar("sinSenalAlSubir")
        abrirEstudios()
        tocar("estudios-subir")
        tocar("estudios-elegir-pdf")
        esperar("estudios-enviar")
        e("estudios-enviar").tap()
        esperar("estudios-sin-senal", 30)
        XCTAssertTrue(texto("Sin señal. Se envía solo cuando vuelva.").exists)
        foto("6-sin-senal")
    }

    func testCancelarLaHojaNoEnviaNada() {
        lanzar("completo")
        abrirEstudios()
        tocar("estudios-subir")
        tocar("estudios-elegir-pdf")
        esperar("estudios-enviar")
        e("estudios-cancelar").tap()
        esperar("estudios-subir")
        pausa(1)
        XCTAssertFalse(e("estudios-subiendo").exists)
        XCTAssertFalse(e("estudios-aviso").exists)
    }

    func testVacio() {
        lanzar("vacio")
        abrirMisDatos()
        traer("mis-datos-estudios")
        XCTAssertTrue(texto("Todo al día").exists)
        e("mis-datos-estudios").tap()
        esperar("estudios-vacio")
        XCTAssertTrue(texto("Acá vas a ver los estudios que te pida Mati, tus órdenes y lo que nos mandes.").exists)
        XCTAssertTrue(e("estudios-subir").exists)
        foto("7-vacio")
    }

    /// Apagada, sin el servidor nuevo o sin habilitar para la cuenta: Mis datos queda como hoy.
    func testApagadoNoMuestraNada() {
        for caso in ["apagado", "sinServidor", "noHabilitado"] {
            lanzar(caso)
            abrirMisDatos()
            XCTAssertTrue(app.staticTexts["Política de privacidad"].waitForExistence(timeout: 10) || app.buttons["Política de privacidad"].waitForExistence(timeout: 2))
            pausa(2)
            XCTAssertFalse(e("mis-datos-estudios").exists, caso)
            XCTAssertFalse(texto("Estudios y órdenes").exists, caso)
            app.terminate()
        }
    }

    // MARK: Novedades: la tarjeta de arriba, el punto, «Nuevo» y el aviso

    /// Cualquier elemento cuya etiqueta contenga ese texto (un botón o una tarjeta leen sus textos juntos).
    private func conEtiqueta(_ s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    /// Arriba de Entreno la tarjeta verde con «Ver»; un toque lleva a Estudios con la tarjeta nueva a la vista y su «Nuevo».
    private func novedad() {
        lanzar("novedad", pestana: "entreno")
        esperar("estudios-tarjeta-inicio-boton")
        XCTAssertTrue(conEtiqueta("Tenés un estudio nuevo para hacer").exists)
        XCTAssertTrue(e("estudios-tarjeta-inicio-boton").label.hasPrefix("Ver"))
        XCTAssertTrue(e("estudios-tarjeta-inicio-boton").isHittable, "se ve sin desplazar")
        XCTAssertGreaterThanOrEqual(e("estudios-tarjeta-inicio-boton").frame.height, 44)
        foto("8-novedad-inicio")
        e("estudios-tarjeta-inicio-boton").tap()
        esperar("estudios-pendiente-\(id(2))")
        XCTAssertTrue(e("estudios-pendiente-\(id(2))").isHittable, "la tarjeta nueva queda a la vista")
        XCTAssertTrue(conEtiqueta("Nuevo").waitForExistence(timeout: 5))
        foto("8-novedad-estudios")
        // Estuvo a la vista: sigue pendiente y conserva «Nuevo» mientras se la mira.
        pausa(3)
        XCTAssertTrue(conEtiqueta("Nuevo").exists)
        XCTAssertTrue(e("estudios-subir-\(id(2))").exists)
    }

    func testNovedadLaTarjetaDeArribaLlevaALaTarjetaNueva() { novedad() }
    func testNovedadOscuro() { oscuro = true; novedad() }
    func testNovedadLetraGrande() { letraGrande = true; novedad() }

    /// Sin nada sin ver y con algo por hacer: «Tenés un estudio para hacer» y «Subir resultado». Un toque a Estudios, dos al selector.
    func testSinNovedadLaTarjetaLlevaASubirEnDosToques() {
        lanzar("completo", pestana: "entreno")
        esperar("estudios-tarjeta-inicio-boton")
        XCTAssertTrue(conEtiqueta("Tenés un estudio para hacer").exists)
        XCTAssertTrue(e("estudios-tarjeta-inicio-boton").label.hasPrefix("Subir resultado"))
        foto("9-para-hacer-inicio")
        e("estudios-tarjeta-inicio-boton").tap()
        esperar("estudios-subir-\(id(1))")
        XCTAssertFalse(conEtiqueta("Nuevo").exists)
        e("estudios-subir-\(id(1))").tap()
        esperar("estudios-sacar-fotos")
        for opcion in ["estudios-sacar-fotos", "estudios-elegir-fotos", "estudios-elegir-pdf"] {
            XCTAssertTrue(e(opcion).isHittable, opcion)
            XCTAssertGreaterThanOrEqual(e(opcion).frame.height, 44, opcion)
            XCTAssertGreaterThan(e(opcion).frame.width, app.frame.width * 0.7, "\(opcion) va de ancho completo")
        }
        foto("9-hoja-opciones")
    }

    func testSinPedidosNiNovedadNoHayTarjetaArriba() {
        lanzar("vacio", pestana: "entreno")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        pausa(3)
        XCTAssertFalse(e("estudios-tarjeta-inicio").exists)
        XCTAssertFalse(e("estudios-tarjeta-inicio-boton").exists)
    }

    /// El punto en la fila de Mis datos (leído «Novedad») se apaga cuando la orden nueva estuvo a la vista.
    func testElPuntoDeLaFilaSeApagaAlVerLaOrden() {
        lanzar("ordenNueva")
        abrirMisDatos()
        traer("mis-datos-estudios")
        XCTAssertTrue(e("mis-datos-estudios-novedad").exists || e("mis-datos-estudios").label.contains("Novedad"))
        foto("10-novedad-mis-datos")
        e("mis-datos-estudios").tap()
        // La orden nueva está más abajo que los pedidos: la pantalla se desplaza sola hasta ella.
        esperar("estudios-orden-\(id(12))")
        pausa(1.5)
        XCTAssertTrue(e("estudios-orden-\(id(12))").isHittable, "la orden nueva queda a la vista")
        XCTAssertTrue(conEtiqueta("Nuevo").exists)
        pausa(3)
        app.navigationBars.buttons.firstMatch.tap()
        traer("mis-datos-estudios")
        pausa(1)
        XCTAssertFalse(e("mis-datos-estudios-novedad").exists)
        XCTAssertFalse(e("mis-datos-estudios").label.contains("Novedad"))
    }

    /// Tocar el aviso con la app cerrada (`destino = estudios`): Mis datos → Estudios, con la tarjeta nueva a la vista.
    func testElAvisoAbreEstudios() {
        lanzar("novedad", pestana: "entreno", extra: ["-destinoDePrueba", "estudios"])
        esperar("estudios-pendiente-\(id(2))")
        XCTAssertTrue(e("estudios-pendiente-\(id(2))").isHittable)
        XCTAssertTrue(conEtiqueta("Nuevo").waitForExistence(timeout: 5))
        // Atrás vuelve a Mis datos, de donde cuelga.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Mis datos"].waitForExistence(timeout: 10))
    }

    /// Sin la sección (palanca apagada, sin el servidor nuevo, cuenta sin la función) el aviso deja en Mis datos: nunca en
    /// blanco ni en el Chat.
    func testElAvisoSinLaSeccionCaeEnMisDatos() {
        for caso in ["apagado", "sinServidor", "noHabilitado"] {
            lanzar(caso, pestana: "entreno", extra: ["-destinoDePrueba", "estudios"])
            XCTAssertTrue(app.navigationBars["Mis datos"].waitForExistence(timeout: 30), caso)
            pausa(7)   // más que el tope de la espera
            XCTAssertTrue(app.navigationBars["Mis datos"].exists, caso)
            XCTAssertFalse(e("estudios-subir").exists, caso)
            XCTAssertFalse(e("mis-datos-estudios").exists, caso)
            app.terminate()
        }
    }
}
