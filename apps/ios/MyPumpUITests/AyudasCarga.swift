import XCTest

/// Lo que todas las pruebas de Entreno hacen con la carga simple: escribir la carga y dar OK.
@MainActor
extension XCUIApplication {
    var okSerie: XCUIElement { buttons["ok-serie"] }

    /// Vuelve a la lista del día. En iOS 26 el botón se llama "BackButton" y el primero de la barra es otro; en 17 y 18
    /// es el primero.
    func volverALaLista() {
        let volver = navigationBars.buttons["BackButton"]
        (volver.exists ? volver : navigationBars.buttons.element(boundBy: 0)).tap()
    }

    /// Baja la lista del día hasta el fondo, donde queda «Terminar el entrenamiento de hoy». Con una serie pendiente el panel
    /// de carga tapa la mitad de abajo y el botón puede estar detrás aunque XCUI lo dé por tocable: recién al fondo de la
    /// lista (el contenido termina por encima del panel) queda a la vista. Arrastres cortos que se sostienen al final (sin
    /// inercia, para leer la posición quieta): un `swipeUp` desde el centro podía caer en una tarjeta y abrir el ejercicio.
    func bajarHastaCerrarSesion(intentos: Int = 16) -> XCUIElement {
        let cerrar = buttons["cerrar-sesion"].firstMatch
        var antes = CGRect.null
        for _ in 0..<intentos {
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                       withVelocity: .default, thenHoldForDuration: 0.2)
            let ahora = cerrar.exists ? cerrar.frame : .null
            if !ahora.isNull && ahora == antes { break }
            antes = ahora
        }
        return cerrar
    }
    var cargaValor: XCUIElement { textFields["carga-valor"] }

    /// Escribe la carga única y baja el teclado: con el teclado arriba el panel se esconde.
    func fijarCarga(_ texto: String) {
        XCTAssertTrue(cargaValor.waitForExistence(timeout: 15), "Sin el campo de la carga")
        traerArribaDelPanel(cargaValor)
        cargaValor.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))   // la selección llega 0,08 s después del foco
        cargaValor.typeText(texto)
        buttons["teclado-listo"].tap()
        XCTAssertTrue(okSerie.waitForExistence(timeout: 5), "El panel no volvió al bajar el teclado")
    }

    /// Deja el elemento entre la barra de arriba y el panel fijo, con arrastres cortos para no pasarse.
    func traerArribaDelPanel(_ e: XCUIElement) {
        let dial = descendants(matching: .any)["reps-dial"]
        let arriba: CGFloat = 170
        for _ in 0..<10 {
            let tope = dial.exists ? dial.frame.minY - 90 : frame.maxY - 120
            let f = e.frame
            if f.minY >= arriba, f.maxY <= tope, e.isHittable { return }
            // Proporcional al centro de la zona libre: en un SE la zona es más angosta que un paso fijo y rebotaba.
            var dy = (arriba + tope) / 2 - f.midY
            if abs(dy) < 40 { dy = -60 }
            dy = max(-170, min(170, dy))
            let inicio = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy < 0 ? 0.42 : 0.28))
            // Lento y sosteniendo al final: sin inercia, si no la lista se pasa y en un SE no converge.
            inicio.press(forDuration: 0.05, thenDragTo: inicio.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .slow, thenHoldForDuration: 0.15)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
    }

    /// Da OK; si es a menos de 10 s del anterior y sin cambiar reps, confirma también la guardia.
    func darOK() {
        XCTAssertTrue(okSerie.waitForExistence(timeout: 8), "Sin el botón OK")
        okSerie.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        if okSerie.exists, okSerie.label.hasPrefix("¿Ya hiciste") {
            okSerie.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }

    /// Lleva el dial a `n` con el − y el +. El VoiceOver lee «10, La vez pasada: 10»; la cuenta es lo primero.
    func fijarReps(_ n: Int) {
        let dial = descendants(matching: .any)["reps-dial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 8), "Sin el dial")
        for _ in 0..<40 {
            let actual = Int(((dial.value as? String) ?? "").split(separator: ",").first ?? "") ?? 0
            if actual == n { return }
            buttons[actual < n ? "reps-mas" : "reps-menos"].tap()
        }
        XCTFail("El dial no llegó a \(n)")
    }

    func filaSerie(_ n: Int) -> XCUIElement { descendants(matching: .any)["fila-serie-\(n)"] }
}
