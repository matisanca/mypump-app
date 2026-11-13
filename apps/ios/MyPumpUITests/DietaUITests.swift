import XCTest

/// Dieta tocada de verdad en el simulador: la mano y el reemplazo de alimentos, de punta a punta contra el backend.
/// Corre SOLO con una cuenta de prueba: el token llega por `TEST_RUNNER_MYPUMP_TOKEN` (xcodebuild le saca el prefijo),
/// nunca escrito en el repo. Ej.: `scripts/nativa/probar-ui.sh <udid> real`.
@MainActor
final class DietaUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: estas pruebas usan una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-pestana", "dieta", "-sinOnboarding", "YES"]
        app.launch()
    }

    func testLaManoMuestraYOcultaLaPorcionCasera() throws {
        let mano = app.buttons["Ver porción casera"].firstMatch
        XCTAssertTrue(mano.waitForExistence(timeout: 20), "No apareció ningún botón de porción casera")
        mano.tap()
        let porcion = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Porción casera:")).firstMatch
        XCTAssertTrue(porcion.waitForExistence(timeout: 3), "La mano no mostró la porción casera")
        adjuntarCaptura("mano-abierta")
        let ocultar = app.buttons["Ocultar porción casera"].firstMatch
        XCTAssertTrue(ocultar.exists)
        ocultar.tap()
        XCTAssertTrue(porcion.waitForNonExistence(timeout: 3), "La mano no ocultó la porción casera")
    }

    func testReemplazarUnAlimentoYVolverAlDelPlan() throws {
        let reemplazar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reemplazar ")).firstMatch
        XCTAssertTrue(reemplazar.waitForExistence(timeout: 20), "No apareció ningún botón de reemplazo")
        let original = String(reemplazar.label.dropFirst("Reemplazar ".count))
        reemplazar.tap()

        let primero = app.buttons.matching(identifier: "sustituto").firstMatch
        XCTAssertTrue(primero.waitForExistence(timeout: 5), "La hoja de reemplazo no mostró opciones para \(original)")
        adjuntarCaptura("hoja-reemplazo")
        primero.tap()
        let confirmar = app.buttons["confirmar-reemplazo"]
        XCTAssertTrue(confirmar.isEnabled, "Elegir una opción no habilitó el botón de reemplazar")
        let nuevo = confirmar.label.replacingOccurrences(of: "Reemplazar por ", with: "")
        confirmar.tap()

        let distintivo = app.buttons["Reemplazado. Tocá para volver a \(original)"].firstMatch
        XCTAssertTrue(distintivo.waitForExistence(timeout: 5), "No quedó marcado el reemplazo de \(original) por \(nuevo)")
        XCTAssertTrue(app.staticTexts[nuevo].firstMatch.exists, "La fila no muestra \(nuevo)")
        adjuntarCaptura("reemplazado")

        // Sobrevive a cerrar y abrir la app (quedó en disco y en la cola).
        app.terminate()
        app.launch()
        XCTAssertTrue(distintivo.waitForExistence(timeout: 20), "El reemplazo no sobrevivió a reabrir la app")

        distintivo.tap()
        let volver = app.buttons["Volver a \(original)"].firstMatch
        XCTAssertTrue(volver.waitForExistence(timeout: 3))
        volver.tap()
        XCTAssertTrue(distintivo.waitForNonExistence(timeout: 5), "No volvió a \(original)")
        adjuntarCaptura("revertido")
    }

    func testComidaLibreAManoSeRegistraYSeBorra() throws {
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reemplazar ")).firstMatch.waitForExistence(timeout: 20))
        // Está al pie de una lista perezosa: no existe hasta que se llega con el scroll.
        let aMano = app.buttons["A mano"].firstMatch
        for _ in 0..<12 where !aMano.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(aMano.isHittable, "No apareció la sección de comidas libres")
        // Después de los swipes rápidos la lista sigue frenando, y un toque ahí solo la detiene (en iOS 17.5 pasaba).
        esperarQuieto(aMano)
        aMano.tap()
        let descripcion = app.textFields["Ej: Milanesa con puré"]
        XCTAssertTrue(descripcion.waitForExistence(timeout: 5))
        descripcion.tap()
        descripcion.typeText("Prueba UI alfajor")
        let kcal = app.textFields.matching(identifier: "kcal-comida-libre").firstMatch
        XCTAssertTrue(kcal.exists)
        kcal.tap()
        kcal.typeText("250")
        adjuntarCaptura("comida-libre-form")
        app.buttons["Registrar"].tap()
        let fila = app.staticTexts["Prueba UI alfajor"]
        XCTAssertTrue(fila.waitForExistence(timeout: 10), "La comida libre no apareció en la lista")
        for _ in 0..<6 where !app.buttons["Borrar Prueba UI alfajor"].isHittable { app.swipeUp() }
        adjuntarCaptura("comida-libre-lista")
        app.buttons["Borrar Prueba UI alfajor"].tap()
        XCTAssertTrue(fila.waitForNonExistence(timeout: 10), "La comida libre no se borró")
    }

    /// Apple 1.4.1: el respaldo pegado a los números abre las 14 fuentes con el aviso legal.
    func testElRespaldoCientificoAbreLasFuentes() throws {
        let renglon = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ver fuentes")).firstMatch
        XCTAssertTrue(renglon.waitForExistence(timeout: 20), "No está el renglón de respaldo en la cabecera")
        renglon.tap()
        XCTAssertTrue(app.navigationBars["Respaldo científico"].waitForExistence(timeout: 5))
        adjuntarCaptura("fuentes")
        let abrir = app.buttons.matching(NSPredicate(format: "label == %@", "Abrir fuente"))
        XCTAssertGreaterThanOrEqual(abrir.count, 3)
        app.buttons["Listo"].tap()
        XCTAssertTrue(app.navigationBars["Respaldo científico"].waitForNonExistence(timeout: 5))
    }

    /// Hasta que el elemento deja de moverse (dos lecturas iguales seguidas), como mucho 3 s.
    // MARK: - Ajustes de porciones (feedback del 20-oct)

    private var botonesAjustar: XCUIElementQuery { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ajustar-")) }

    /// El id de la primera comida. La lista es perezosa: con la letra grande el botón queda abajo y no existe hasta llegar.
    private func primeraComida() -> String {
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ver fuentes")).firstMatch.waitForExistence(timeout: 20),
                      "No cargó Dieta")
        for _ in 0..<15 where !botonesAjustar.firstMatch.exists { app.swipeUp() }
        XCTAssertTrue(botonesAjustar.firstMatch.waitForExistence(timeout: 3), "No está el botón de ajustar en las comidas")
        return String(botonesAjustar.firstMatch.identifier.dropFirst("ajustar-".count))
    }

    private func aviso(_ comidaId: String) -> XCUIElement { app.descendants(matching: .any)["ajuste-aviso-\(comidaId)"] }

    /// Abre la hoja de una comida (la primera, si no se dice) y devuelve su id.
    @discardableResult private func abrirAjuste(_ id: String? = nil) -> String {
        let boton = id.map { app.buttons["ajustar-\($0)"] } ?? botonesAjustar.firstMatch
        for _ in 0..<15 where !boton.exists { app.swipeUp() }
        XCTAssertTrue(boton.waitForExistence(timeout: 20), "No está el botón de ajustar en las comidas")
        aLaVista(boton)
        let comidaId = String(boton.identifier.dropFirst("ajustar-".count))
        boton.tap()
        XCTAssertTrue(kcalDeLaHoja.waitForExistence(timeout: 5), "No se abrió la hoja de ajuste")
        return comidaId
    }

    /// A la vista y lejos de la barra de pestañas, que flota encima de la lista (con la letra grande tapa más).
    private func aLaVista(_ e: XCUIElement) {
        let barra = app.tabBars.firstMatch
        for _ in 0..<12 {
            let tope = barra.exists ? barra.frame.minY - 8 : app.frame.maxY
            if e.exists, e.isHittable, e.frame.maxY < tope { break }
            if e.exists, e.frame.minY > tope || e.frame.maxY > tope { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
        }
        esperarQuieto(e)
    }

    /// Lo que haya dejado otra corrida en la cuenta de prueba, afuera.
    private func sinAjusteEn(_ comidaId: String) {
        let boton = app.buttons["ajustar-\(comidaId)"]
        for _ in 0..<15 where !boton.exists { app.swipeUp() }
        guard boton.waitForExistence(timeout: 2), boton.label == "Cambiar el ajuste" else { return }
        abrirAjuste(comidaId)
        volverAlPlanEnLaHoja()
        XCTAssertTrue(aviso(comidaId).waitForNonExistence(timeout: 5))
    }

    /// «Volver al plan» está al pie de la hoja: se baja hasta verlo.
    private func volverAlPlanEnLaHoja() {
        let volver = app.buttons["ajuste-volver-plan"]
        for _ in 0..<8 where !volver.isHittable { app.swipeUp() }
        esperarQuieto(volver)
        volver.tap()
    }

    private func prender(_ id: String) {
        let t = app.switches[id]
        // La hoja es una lista: con la letra grande el interruptor queda más abajo.
        for _ in 0..<6 where !t.exists || !t.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(t.waitForExistence(timeout: 3), "No está \(id)")
        (t.switches.firstMatch.exists ? t.switches.firstMatch : t).tap()
    }

    private var kcalDeLaHoja: XCUIElement { app.descendants(matching: .any)["ajuste-kcal"].firstMatch }

    /// Las kcal de la hoja: el valor empieza con el número («1323 kcal, +604 contra el plan…»).
    private var kcalHoy: Int { Int(((kcalDeLaHoja.value as? String) ?? "").prefix { $0 != " " }.filter(\.isNumber)) ?? -1 }

    /// +100 kcal a una comida: las porciones suben, la siguiente compensa, sobrevive a reabrir y «Volver al plan» lo saca.
    func testAjustarUnaComidaCompensaEnLaSiguienteYVuelveAlPlan() throws {
        let comidaId = primeraComida()
        sinAjusteEn(comidaId)
        abrirAjuste(comidaId)
        let antes = kcalHoy
        let mas = app.buttons["ajuste-mas"]
        XCTAssertTrue(mas.isEnabled, "No se puede sumar")
        mas.tap()
        mas.tap()
        let despues = kcalHoy
        XCTAssertLessThanOrEqual(abs(despues - antes - 100), 25, "+100 kcal dio \(antes) → \(despues)")
        XCTAssertTrue(app.descendants(matching: .any)["ajuste-macros"].firstMatch.exists, "Sin las macros de la comida")
        XCTAssertTrue(app.staticTexts["ajuste-dia"].label.hasPrefix("Tu día:"))
        let compensa = app.switches["ajuste-compensar"].exists
        if compensa {
            let texto = app.staticTexts["ajuste-efecto"].firstMatch
            let efecto = app.switches["ajuste-compensar"].label + " " + (texto.exists ? texto.label : "")
            XCTAssertTrue(efecto.contains("baja"), "La hoja no dice cuánto baja la siguiente: \(efecto)")
        }
        adjuntarCaptura("ajuste-hoja")
        app.buttons["ajuste-listo"].tap()

        XCTAssertTrue(aviso(comidaId).waitForExistence(timeout: 5), "La tarjeta no muestra el ajuste")
        XCTAssertTrue(aviso(comidaId).label.contains("Ajustada: +"), aviso(comidaId).label)
        XCTAssertEqual(app.buttons["ajustar-\(comidaId)"].label, "Cambiar el ajuste")
        let compensada = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                                             "ajuste-aviso-", "kcal por"))
        if compensa {
            // La siguiente tarjeta puede estar más abajo (la lista es perezosa).
            for _ in 0..<8 where !compensada.firstMatch.exists { app.swipeUp() }
            XCTAssertTrue(compensada.firstMatch.exists, "La siguiente no muestra la compensación")
        }
        adjuntarCaptura("ajuste-tarjetas")

        // Sobrevive a cerrar y abrir la app.
        app.terminate()
        app.launch()
        _ = primeraComida()
        for _ in 0..<15 where !aviso(comidaId).exists { app.swipeDown() }
        XCTAssertTrue(aviso(comidaId).waitForExistence(timeout: 5), "El ajuste no sobrevivió a reabrir la app")

        abrirAjuste(comidaId)
        volverAlPlanEnLaHoja()
        XCTAssertTrue(aviso(comidaId).waitForNonExistence(timeout: 5), "«Volver al plan» no sacó el ajuste")
        XCTAssertFalse(compensada.firstMatch.exists, "Quedó la compensación en la siguiente")
    }

    /// «Hoy no la como» (Emilio, el pre-entreno en un día sin entreno): la tarjeta lo dice, sin los alimentos, y sus kcal
    /// van a la siguiente. «Cancelar» no guarda nada.
    func testHoyNoLaComoPasaSusKcalALaSiguiente() throws {
        let comidaId = primeraComida()
        sinAjusteEn(comidaId)
        abrirAjuste(comidaId)
        app.buttons["ajuste-mas"].tap()
        app.buttons["Cancelar"].tap()
        XCTAssertFalse(aviso(comidaId).waitForExistence(timeout: 2), "Cancelar guardó el ajuste")

        abrirAjuste(comidaId)
        prender("ajuste-omitir")
        XCTAssertFalse(app.buttons["ajuste-mas"].isEnabled, "Sin comerla no se suman kcal")
        let omitir = app.switches["ajuste-omitir"].label
        XCTAssertTrue(omitir.contains(" kcal pasan al ") || omitir.contains(" kcal pasan a la "), omitir)
        adjuntarCaptura("ajuste-omitir")
        app.buttons["ajuste-listo"].tap()
        XCTAssertTrue(aviso(comidaId).waitForExistence(timeout: 5))
        XCTAssertTrue(aviso(comidaId).label.contains("Hoy no la comés"), aviso(comidaId).label)
        // La que no come no se marca (D25).
        XCTAssertFalse(app.buttons["comi-\(comidaId)"].exists, "Una comida que hoy no come muestra «Comí»")
        if botonesAjustar.count > 1 {
            let recibe = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                                               "ajuste-aviso-", "kcal por"))
            for _ in 0..<8 where !recibe.firstMatch.exists { app.swipeUp() }
            XCTAssertTrue(recibe.firstMatch.waitForExistence(timeout: 3), "La siguiente no recibió sus kcal")
            XCTAssertTrue(recibe.firstMatch.label.hasPrefix("+"), recibe.firstMatch.label)
        }
        adjuntarCaptura("ajuste-omitida")
        abrirAjuste(comidaId)
        volverAlPlanEnLaHoja()
        XCTAssertTrue(aviso(comidaId).waitForNonExistence(timeout: 5))
    }

    // MARK: - Comí / Salté y lo consumido (D25)

    /// Lo consumido del anillo de arriba: el valor empieza con el número («1234 de 2373 kcal»). La lista es perezosa: se
    /// sube hasta verlo.
    private func consumidoAhora() -> Int {
        let anillo = app.descendants(matching: .any)["consumido-kcal"].firstMatch
        for _ in 0..<15 where !anillo.exists || !anillo.isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(anillo.waitForExistence(timeout: 5), "No está lo consumido en la cabecera")
        esperarQuieto(anillo)
        return Int(((anillo.value as? String) ?? "").prefix { $0 != " " }.filter(\.isNumber)) ?? -1
    }

    private func esperar(_ e: XCUIElement, seleccionado: Bool, _ mensaje: String) {
        let p = NSPredicate(format: "isSelected == %@", NSNumber(value: seleccionado))
        let r = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: 5)
        XCTAssertEqual(r, .completed, mensaje)
    }

    private func esperar(_ e: XCUIElement, valor: String) {
        let p = NSPredicate(format: "value == %@", valor)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: 5), .completed,
                       "\(e.identifier): \(String(describing: e.value)) en vez de \(valor)")
    }

    /// Lo que haya dejado otra corrida en la cuenta de prueba: sin marca en esa comida.
    private func sinMarcaEn(_ comidaId: String) {
        for id in ["comi-\(comidaId)", "salte-\(comidaId)"] {
            let b = app.buttons[id]
            for _ in 0..<15 where !b.exists { app.swipeUp() }
            XCTAssertTrue(b.waitForExistence(timeout: 5), "No está \(id)")
            if b.isSelected {
                aLaVista(b)
                b.tap()
                esperar(b, seleccionado: false, "No se desmarcó \(id)")
            }
        }
    }

    /// Los tildes por alimento son interruptores para VoiceOver (`isToggle`); el resto, botones.
    private func tocar(_ id: String) -> XCUIElement {
        let b = id.hasPrefix("comido-") ? app.switches[id] : app.buttons[id]
        for _ in 0..<15 where !b.exists { app.swipeUp() }
        aLaVista(b)
        b.tap()
        return b
    }

    /// «Comí» suma la comida a lo consumido de arriba (capturas en claro y oscuro), sobrevive a reabrir la app, «Salté»
    /// la saca y tocar el marcado lo desmarca.
    func testComiYSalteSumanAlConsumidoYTocarDeNuevoDesmarca() throws {
        let comidaId = primeraComida()
        sinAjusteEn(comidaId)
        sinMarcaEn(comidaId)
        let antes = consumidoAhora()
        XCTAssertGreaterThanOrEqual(antes, 0)
        esperar(tocar("comi-\(comidaId)"), seleccionado: true, "«Comí» no quedó marcado")
        let conLaComida = consumidoAhora()
        XCTAssertGreaterThan(conLaComida, antes, "«Comí» no sumó a lo consumido")
        adjuntarCaptura("consumido-claro")

        // Quedó en el teléfono y en el servidor. Se reabre con el tema oscuro de la app (el de Mis datos): cambiar el
        // del sistema es una animación que la captura agarra a mitad de camino.
        app.terminate()
        app.launchArguments += ["-mypump-theme", "dark"]
        app.launch()
        _ = primeraComida()
        // U4: la comida marcada se ve plegada («La comiste»); tocando el título se abre con «Comí» marcado.
        let encabezado = app.descendants(matching: .any)["encabezado-\(comidaId)"].firstMatch
        // `primeraComida` pudo bajar hasta la próxima comida abierta: se busca para arriba y, si no, para abajo.
        for _ in 0..<8 where !encabezado.exists { app.swipeDown() }
        for _ in 0..<15 where !encabezado.exists { app.swipeUp() }
        XCTAssertTrue(encabezado.waitForExistence(timeout: 10), "Sin el título de la comida")
        XCTAssertEqual(encabezado.value as? String, "La comiste", "«Comí» no sobrevivió a reabrir la app")
        // Bug del 13-nov: plegada, se abre con un botón a la vista que dice que adentro se destilda y se desmarca.
        let abrir = app.buttons["abrir-\(comidaId)"]
        XCTAssertTrue(abrir.waitForExistence(timeout: 5), "Plegada, sin el botón para abrirla")
        XCTAssertEqual(abrir.label, "Destildar lo que no comiste o desmarcar")
        abrir.tap()
        let comi = app.buttons["comi-\(comidaId)"]
        for _ in 0..<15 where !comi.exists { app.swipeUp() }
        esperar(comi, seleccionado: true, "«Comí» no sobrevivió a reabrir la app")
        XCTAssertEqual(consumidoAhora(), conLaComida)
        adjuntarCaptura("consumido-oscuro")

        let salte = tocar("salte-\(comidaId)")
        esperar(salte, seleccionado: true, "«Salté» no quedó marcado")
        esperar(comi, seleccionado: false, "«Salté» no sacó «Comí»")
        XCTAssertEqual(consumidoAhora(), antes, "«Salté» no sacó la comida de lo consumido")
        adjuntarCaptura("salteada")
        esperar(tocar("salte-\(comidaId)"), seleccionado: false, "Tocar «Salté» marcado no lo desmarcó")
        XCTAssertEqual(consumidoAhora(), antes)
    }

    /// Consumo parcial: con «Comí», destildar un alimento descuenta sus kcal de lo consumido y tildarlo las vuelve a sumar.
    func testDestildarUnAlimentoDescuentaSusKcal() throws {
        let comidaId = primeraComida()
        sinAjusteEn(comidaId)
        sinMarcaEn(comidaId)
        let tilde = app.switches["comido-\(comidaId)-0"]
        XCTAssertFalse(tilde.exists, "Sin «Comí» no hay tildes")
        esperar(tocar("comi-\(comidaId)"), seleccionado: true, "«Comí» no quedó marcado")
        XCTAssertTrue(tilde.waitForExistence(timeout: 5), "Con «Comí» no aparecieron los tildes")
        esperar(tilde, valor: "Lo comiste")
        let todo = consumidoAhora()
        _ = tocar("comido-\(comidaId)-0")
        esperar(tilde, valor: "No lo comiste")
        let sinEse = consumidoAhora()
        XCTAssertLessThan(sinEse, todo, "Destildar no descontó")
        let pista = app.descendants(matching: .any)["tildes-\(comidaId)"].firstMatch
        for _ in 0..<15 where !pista.exists { app.swipeUp() }
        XCTAssertTrue(pista.label.hasPrefix("Cuenta lo tildado:"), pista.label)
        aLaVista(tilde)
        adjuntarCaptura("comi-parcial")

        // Mirar otra opción no cambia lo comido: se sigue contando la de la marca, sin tildes, y se puede volver a ella.
        let opciones = app.segmentedControls["opciones-\(comidaId)"]
        if opciones.exists, opciones.buttons.count > 1 {
            let marcada = opciones.buttons.element(boundBy: 0).label
            aLaVista(opciones)
            opciones.buttons.element(boundBy: 1).tap()
            XCTAssertTrue(tilde.waitForNonExistence(timeout: 3), "Mirando otra opción quedaron los tildes")
            XCTAssertTrue(pista.label.hasPrefix("Comiste la opción \(marcada)"), pista.label)
            XCTAssertEqual(consumidoAhora(), sinEse, "Mirar otra opción cambió lo consumido")
            esperar(app.buttons["comi-\(comidaId)"], seleccionado: true, "Mirar otra opción sacó «Comí»")
            _ = tocar("ver-opcion-\(comidaId)")
            XCTAssertTrue(tilde.waitForExistence(timeout: 3), "«Ver la opción» no volvió a la que comió")
            esperar(tilde, valor: "No lo comiste")
        }
        _ = tocar("comido-\(comidaId)-0")
        esperar(tilde, valor: "Lo comiste")
        XCTAssertEqual(consumidoAhora(), todo)
        esperar(tocar("comi-\(comidaId)"), seleccionado: false, "No se desmarcó")
        XCTAssertFalse(tilde.waitForExistence(timeout: 2), "Sin «Comí» quedaron los tildes")
    }

    // MARK: - Agregar alimentos y cantidades a la vista (2.0.3, D1 y D2)

    /// Las kcal de la hoja de cantidad: el valor empieza con el número («21 kcal»).
    private var kcalDeCantidad: Int {
        let e = app.descendants(matching: .any)["cantidad-kcal"].firstMatch
        return Int(((e.value as? String) ?? "").prefix { $0 != " " }.filter(\.isNumber)) ?? -1
    }

    private func abrirAgregar(_ comidaId: String) {
        let boton = app.buttons["agregar-\(comidaId)"]
        for _ in 0..<15 where !boton.exists { app.swipeUp() }
        XCTAssertTrue(boton.waitForExistence(timeout: 5), "No está «Agregar alimento» en la comida")
        aLaVista(boton)
        boton.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "No se abrió la hoja de agregar")
    }

    /// D1 (el pedido: «comí 80 g de puré de zapallo y no lo pude cargar»): se busca en la base, se eligen los gramos con
    /// las kcal en vivo y queda en la misma comida, que sube y lo dice; el «+» de los recientes lo suma de un toque; sobrevive
    /// a reabrir la app; con «Comí» tiene su tilde; se saca desde su hoja y «Volver al plan» saca todo.
    func testAgregarUnAlimentoALaComidaConSusGramos() throws {
        let comidaId = primeraComida()
        sinAjusteEn(comidaId)
        sinMarcaEn(comidaId)
        abrirAgregar(comidaId)
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("zapallo")
        let resultado = app.buttons.matching(identifier: "agregar-alimento").firstMatch
        XCTAssertTrue(resultado.waitForExistence(timeout: 5), "La búsqueda no encontró el zapallo")
        XCTAssertTrue(resultado.label.contains("Zapallo"), resultado.label)
        adjuntarCaptura("agregar-busqueda")
        resultado.tap()

        let campo = app.textFields["cantidad-campo"]
        XCTAssertTrue(campo.waitForExistence(timeout: 5), "No se abrió la hoja de cantidad")
        XCTAssertEqual(campo.value as? String, "100")
        XCTAssertEqual(kcalDeCantidad, 26)
        for _ in 0..<4 { app.buttons["cantidad-menos"].tap() }
        XCTAssertEqual(campo.value as? String, "80")
        XCTAssertEqual(kcalDeCantidad, 21, "Las kcal no se recalcularon en vivo")
        let medidas = app.segmentedControls["cantidad-medida"]
        XCTAssertTrue(medidas.exists && medidas.buttons.count == 2, "Sin la medida casera (puño)")
        adjuntarCaptura("agregar-cantidad")
        app.buttons["cantidad-confirmar"].tap()

        let fila = app.buttons["agregado-\(comidaId)-0"]
        XCTAssertTrue(fila.waitForExistence(timeout: 5), "El zapallo no quedó en la comida")
        XCTAssertTrue(fila.label.contains("80 g"), fila.label)
        XCTAssertTrue(aviso(comidaId).waitForExistence(timeout: 5))
        XCTAssertTrue(aviso(comidaId).label.contains("+21 kcal"), aviso(comidaId).label)
        aLaVista(fila)
        adjuntarCaptura("agregado-en-la-comida")

        // El «+» de los recientes: el mismo, de un toque.
        abrirAgregar(comidaId)
        let mas = app.buttons["reciente-agregar-0"]
        XCTAssertTrue(mas.waitForExistence(timeout: 3), "No está el zapallo en los recientes")
        mas.tap()
        XCTAssertTrue(app.buttons["agregado-\(comidaId)-1"].waitForExistence(timeout: 5), "El «+» de un toque no lo agregó")
        XCTAssertTrue(aviso(comidaId).label.contains("+42 kcal"), aviso(comidaId).label)

        // Sobrevive a cerrar y abrir la app (quedó en disco y en la cola).
        app.terminate()
        app.launch()
        _ = primeraComida()
        let segundo = app.buttons["agregado-\(comidaId)-1"]
        for _ in 0..<15 where !segundo.exists { app.swipeUp() }
        XCTAssertTrue(segundo.waitForExistence(timeout: 5), "Los agregados no sobrevivieron a reabrir la app")

        // «Comí» los cuenta y tienen su tilde (después de los del plan).
        esperar(tocar("comi-\(comidaId)"), seleccionado: true, "«Comí» no quedó marcado")
        let tildes = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "comido-\(comidaId)-"))
        XCTAssertTrue(tildes.firstMatch.waitForExistence(timeout: 5))
        let n = tildes.count
        XCTAssertTrue(app.switches["comido-\(comidaId)-\(n - 1)"].exists, "El agregado no tiene tilde")
        let conTodo = consumidoAhora()
        _ = tocar("comido-\(comidaId)-\(n - 1)")
        XCTAssertEqual(consumidoAhora(), conTodo - 21, "Destildar el agregado no descontó sus kcal")
        esperar(tocar("comi-\(comidaId)"), seleccionado: false, "No se desmarcó")

        // Se saca desde su hoja.
        aLaVista(segundo)
        segundo.tap()
        let borrar = app.buttons["cantidad-borrar"]
        for _ in 0..<6 where !borrar.isHittable { app.swipeUp(velocity: .slow) }
        borrar.tap()
        XCTAssertTrue(segundo.waitForNonExistence(timeout: 5), "No se sacó el agregado")
        XCTAssertTrue(app.buttons["agregado-\(comidaId)-0"].exists)

        // «Volver al plan» también los saca.
        sinAjusteEn(comidaId)
        XCTAssertFalse(app.buttons["agregado-\(comidaId)-0"].exists, "«Volver al plan» dejó el agregado")
    }

    /// D2: la cantidad de un alimento del plan se toca en la misma fila, se cambia con las kcal en vivo, queda a mano (la
    /// comida lo dice) y «Como el plan» la devuelve.
    func testTocarLaCantidadDeUnAlimentoDelPlan() throws {
        let comidaId = primeraComida()
        sinAjusteEn(comidaId)
        let pildora = app.buttons["cantidad-\(comidaId)-0"]
        for _ in 0..<15 where !pildora.exists { app.swipeUp() }
        XCTAssertTrue(pildora.waitForExistence(timeout: 5), "La cantidad no se puede tocar en la fila")
        let antes = pildora.label
        aLaVista(pildora)
        pildora.tap()
        let campo = app.textFields["cantidad-campo"]
        XCTAssertTrue(campo.waitForExistence(timeout: 5), "No se abrió la hoja de cantidad")
        let kcal0 = kcalDeCantidad
        app.buttons["cantidad-mas"].tap()
        app.buttons["cantidad-mas"].tap()
        XCTAssertGreaterThan(kcalDeCantidad, kcal0, "Las kcal no subieron en vivo")
        adjuntarCaptura("cantidad-del-plan")
        app.buttons["cantidad-confirmar"].tap()
        XCTAssertTrue(aviso(comidaId).waitForExistence(timeout: 5), "La comida no muestra el ajuste")
        XCTAssertNotEqual(pildora.label, antes, "La fila no muestra la cantidad nueva")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "En el plan:")).firstMatch.exists)
        aLaVista(pildora)
        adjuntarCaptura("cantidad-en-la-fila")

        pildora.tap()
        let comoPlan = app.buttons["cantidad-como-plan"]
        for _ in 0..<6 where !comoPlan.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(comoPlan.exists, "Sin «Como el plan» con la cantidad a mano")
        comoPlan.tap()
        XCTAssertTrue(aviso(comidaId).waitForNonExistence(timeout: 5), "«Como el plan» no sacó la cantidad a mano")
        XCTAssertEqual(pildora.label, antes)
    }

    /// Las pantallas nuevas en oscuro (el tema de la app, como «consumido-oscuro») y «Salté» sin «Agregar alimento»
    /// (revisión del 3-nov: en una comida salteada no tiene sentido sumarle algo).
    func testAgregarEnOscuroYSalteOcultaAgregar() throws {
        app.terminate()
        app.launchArguments += ["-mypump-theme", "dark"]
        app.launch()
        let comidaId = primeraComida()
        sinAjusteEn(comidaId)
        sinMarcaEn(comidaId)
        abrirAgregar(comidaId)
        adjuntarCaptura("agregar-oscuro")
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("zapallo")
        let resultado = app.buttons.matching(identifier: "agregar-alimento").firstMatch
        XCTAssertTrue(resultado.waitForExistence(timeout: 5))
        resultado.tap()
        XCTAssertTrue(app.textFields["cantidad-campo"].waitForExistence(timeout: 5))
        adjuntarCaptura("cantidad-oscuro")
        app.buttons["cantidad-confirmar"].tap()
        let fila = app.buttons["agregado-\(comidaId)-0"]
        XCTAssertTrue(fila.waitForExistence(timeout: 5))
        aLaVista(fila)
        adjuntarCaptura("agregado-oscuro")

        esperar(tocar("salte-\(comidaId)"), seleccionado: true, "«Salté» no quedó marcado")
        XCTAssertTrue(app.buttons["agregar-\(comidaId)"].waitForNonExistence(timeout: 5), "«Agregar alimento» sigue en una comida salteada")
        esperar(tocar("salte-\(comidaId)"), seleccionado: false, "No se desmarcó «Salté»")
        XCTAssertTrue(app.buttons["agregar-\(comidaId)"].waitForExistence(timeout: 5))
        sinAjusteEn(comidaId)
    }

    // MARK: - Código de barras (2.1, S3)

    /// Relanza con el código que «lee» el escáner (`-codigoDePrueba`, el simulador no tiene cámara) y Open Food Facts de
    /// mentira (`-offDePrueba`, con la respuesta real del yogur de los vectores). Cada caso usa su propio código: lo buscado
    /// queda en la caché del teléfono.
    private func relanzarConCodigo(_ codigo: String, off: String, oscuro: Bool = false) {
        app.terminate()
        app.launchArguments += ["-codigoDePrueba", codigo, "-offDePrueba", off]
        if oscuro { app.launchArguments += ["-mypump-theme", "dark"] }
        app.launch()
    }

    /// Encontrado: el acceso bien visible arriba de la hoja, la misma hoja de cantidad con la porción de la etiqueta
    /// (1 porción de 200 g = 164 kcal) y de dónde salen los valores; queda en la comida con su nombre y marca.
    func testEscanearUnCodigoQueEstaAbreLaCantidadYLoAgrega() throws {
        relanzarConCodigo("7791337006355", off: "encontrado")
        let comidaId = primeraComida()
        sinAjusteEn(comidaId)
        sinMarcaEn(comidaId)
        abrirAgregar(comidaId)
        let escanear = app.buttons["agregar-escanear"]
        XCTAssertTrue(escanear.waitForExistence(timeout: 3), "No está «Escanear código de barras» en la hoja")
        XCTAssertTrue(app.buttons["agregar-escanear-barra"].exists, "No está el botón del código en la barra")
        adjuntarCaptura("barras-hoja")
        escanear.tap()
        // «Buscando…» dura lo que tarda Open Food Facts; con el código ya en la caché del simulador ni aparece.

        let campo = app.textFields["cantidad-campo"]
        XCTAssertTrue(campo.waitForExistence(timeout: 8), "No abrió la hoja de cantidad")
        XCTAssertEqual(kcalDeCantidad, 164, "1 porción de 200 g del yogur (82 kcal cada 100 g)")
        let medidas = app.segmentedControls["cantidad-medida"]
        XCTAssertTrue(medidas.buttons["porción (200 g)"].exists, "Sin la porción de la etiqueta")
        XCTAssertTrue(medidas.buttons["porción (200 g)"].isSelected, "No abrió en la porción")
        XCTAssertTrue(app.descendants(matching: .any)["cantidad-origen-barras"].exists, "No dice de dónde salen los valores")
        XCTAssertTrue(app.staticTexts["Yogurisimo sabor Natural (La serenisima)"].exists)
        adjuntarCaptura("barras-cantidad")
        app.buttons["cantidad-confirmar"].tap()

        let fila = app.buttons["agregado-\(comidaId)-0"]
        XCTAssertTrue(fila.waitForExistence(timeout: 5), "El escaneado no quedó en la comida")
        XCTAssertTrue(fila.label.contains("Yogurisimo"), fila.label)
        XCTAssertTrue(aviso(comidaId).label.contains("+164 kcal"), aviso(comidaId).label)
        aLaVista(fila)
        adjuntarCaptura("barras-agregado")
        sinAjusteEn(comidaId)
    }

    /// No está: el mensaje con las dos salidas; «Cargarlo a mano» abre el alimento propio con el código, sin guardar nada.
    func testEscanearUnCodigoQueNoEstaOfreceCargarloAManoOConLaEtiqueta() throws {
        relanzarConCodigo("7790742000101", off: "noEncontrado")
        let comidaId = primeraComida()
        abrirAgregar(comidaId)
        app.buttons["agregar-escanear"].tap()
        let aviso = app.descendants(matching: .any)["codigo-sin-producto"]
        XCTAssertTrue(aviso.waitForExistence(timeout: 8), "No avisó que no lo encontró")
        XCTAssertTrue(aviso.label.contains("No encontramos este producto"), aviso.label)
        XCTAssertTrue(app.buttons["codigo-etiqueta"].exists, "Sin «Escanear la etiqueta»")
        XCTAssertTrue(app.buttons["codigo-a-mano"].exists, "Sin «Cargarlo a mano»")
        adjuntarCaptura("barras-no-encontrado")
        app.buttons["codigo-a-mano"].tap()
        let codigo = app.descendants(matching: .any)["crear-codigo"]
        XCTAssertTrue(codigo.waitForExistence(timeout: 5), "El alimento propio no muestra el código")
        XCTAssertTrue(app.staticTexts["7790742000101"].exists)
        adjuntarCaptura("barras-a-mano")
    }

    /// Incompleto, en oscuro: el aviso de que le faltan datos y el alimento propio precargado con lo que se pudo leer.
    func testEscanearUnCodigoIncompletoPrecargaElAlimentoEnOscuro() throws {
        relanzarConCodigo("7793913013993", off: "incompleto", oscuro: true)
        let comidaId = primeraComida()
        abrirAgregar(comidaId)
        XCTAssertTrue(app.buttons["agregar-escanear"].waitForExistence(timeout: 3))
        adjuntarCaptura("barras-hoja-oscuro")
        app.buttons["agregar-escanear"].tap()
        let aviso = app.descendants(matching: .any)["codigo-sin-producto"]
        XCTAssertTrue(aviso.waitForExistence(timeout: 8))
        XCTAssertTrue(aviso.label.contains("Le faltan datos"), aviso.label)
        adjuntarCaptura("barras-incompleto-oscuro")
        app.buttons["codigo-a-mano"].tap()
        let nombre = app.textFields["Ej: Pan integral marca X"]
        XCTAssertTrue(nombre.waitForExistence(timeout: 5))
        XCTAssertEqual(nombre.value as? String, "Yogurisimo sabor Natural (La serenisima)", "No precargó el nombre")
        XCTAssertEqual(app.textFields["Calorías en kcal"].value as? String, "82", "No precargó las kcal")
        adjuntarCaptura("barras-precargado-oscuro")
    }

    private func esperarQuieto(_ e: XCUIElement) {
        var antes = e.frame
        var iguales = 0
        let fin = Date().addingTimeInterval(3)
        while iguales < 2 && Date() < fin {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let ahora = e.frame
            iguales = ahora == antes ? iguales + 1 : 0
            antes = ahora
        }
    }

    private func adjuntarCaptura(_ nombre: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
}
