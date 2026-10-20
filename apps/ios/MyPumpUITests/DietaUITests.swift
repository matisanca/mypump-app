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

    private func aviso(_ comidaId: String) -> XCUIElement { app.descendants(matching: .any)["ajuste-aviso-\(comidaId)"] }

    /// Abre la hoja de una comida (la primera, si no se dice) y devuelve su id.
    @discardableResult private func abrirAjuste(_ id: String? = nil) -> String {
        let boton = id.map { app.buttons["ajustar-\($0)"] } ?? botonesAjustar.firstMatch
        XCTAssertTrue(boton.waitForExistence(timeout: 20), "No está el botón de ajustar en las comidas")
        for _ in 0..<10 where !boton.isHittable { app.swipeUp() }
        esperarQuieto(boton)
        let comidaId = String(boton.identifier.dropFirst("ajustar-".count))
        boton.tap()
        XCTAssertTrue(kcalDeLaHoja.waitForExistence(timeout: 5), "No se abrió la hoja de ajuste")
        return comidaId
    }

    /// Lo que haya dejado otra corrida en la cuenta de prueba, afuera.
    private func sinAjusteEn(_ comidaId: String) {
        guard aviso(comidaId).waitForExistence(timeout: 2), app.buttons["ajustar-\(comidaId)"].label == "Cambiar el ajuste" else { return }
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
        XCTAssertTrue(t.waitForExistence(timeout: 3), "No está \(id)")
        (t.switches.firstMatch.exists ? t.switches.firstMatch : t).tap()
    }

    private var kcalDeLaHoja: XCUIElement { app.descendants(matching: .any)["ajuste-kcal"].firstMatch }

    /// Las kcal de la hoja: el valor empieza con el número («1323 kcal, +604 contra el plan…»).
    private var kcalHoy: Int { Int(((kcalDeLaHoja.value as? String) ?? "").prefix { $0 != " " }.filter(\.isNumber)) ?? -1 }

    /// +100 kcal a una comida: las porciones suben, la siguiente compensa, sobrevive a reabrir y «Volver al plan» lo saca.
    func testAjustarUnaComidaCompensaEnLaSiguienteYVuelveAlPlan() throws {
        XCTAssertTrue(botonesAjustar.firstMatch.waitForExistence(timeout: 20))
        let comidaId = String(botonesAjustar.firstMatch.identifier.dropFirst("ajustar-".count))
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
        if compensa { XCTAssertTrue(compensada.firstMatch.exists, "La siguiente no muestra la compensación") }
        adjuntarCaptura("ajuste-tarjetas")

        // Sobrevive a cerrar y abrir la app.
        app.terminate()
        app.launch()
        XCTAssertTrue(aviso(comidaId).waitForExistence(timeout: 20), "El ajuste no sobrevivió a reabrir la app")

        abrirAjuste(comidaId)
        volverAlPlanEnLaHoja()
        XCTAssertTrue(aviso(comidaId).waitForNonExistence(timeout: 5), "«Volver al plan» no sacó el ajuste")
        XCTAssertFalse(compensada.firstMatch.exists, "Quedó la compensación en la siguiente")
    }

    /// «Hoy no la como» (Emilio, el pre-entreno en un día sin entreno): la tarjeta lo dice, sin los alimentos, y sus kcal
    /// van a la siguiente. «Cancelar» no guarda nada.
    func testHoyNoLaComoPasaSusKcalALaSiguiente() throws {
        XCTAssertTrue(botonesAjustar.firstMatch.waitForExistence(timeout: 20))
        let comidaId = String(botonesAjustar.firstMatch.identifier.dropFirst("ajustar-".count))
        sinAjusteEn(comidaId)
        abrirAjuste(comidaId)
        app.buttons["ajuste-mas"].tap()
        app.buttons["Cancelar"].tap()
        XCTAssertFalse(aviso(comidaId).waitForExistence(timeout: 2), "Cancelar guardó el ajuste")

        abrirAjuste(comidaId)
        prender("ajuste-omitir")
        XCTAssertFalse(app.buttons["ajuste-mas"].isEnabled, "Sin comerla no se suman kcal")
        adjuntarCaptura("ajuste-omitir")
        app.buttons["ajuste-listo"].tap()
        XCTAssertTrue(aviso(comidaId).waitForExistence(timeout: 5))
        XCTAssertTrue(aviso(comidaId).label.contains("Hoy no la comés"), aviso(comidaId).label)
        if botonesAjustar.count > 1 {
            let recibe = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                                               "ajuste-aviso-", "kcal por"))
            XCTAssertTrue(recibe.firstMatch.waitForExistence(timeout: 3), "La siguiente no recibió sus kcal")
            XCTAssertTrue(recibe.firstMatch.label.hasPrefix("+"), recibe.firstMatch.label)
        }
        adjuntarCaptura("ajuste-omitida")
        abrirAjuste(comidaId)
        volverAlPlanEnLaHoja()
        XCTAssertTrue(aviso(comidaId).waitForNonExistence(timeout: 5))
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
