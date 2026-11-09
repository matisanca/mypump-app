import XCTest

/// Lo que todas las pruebas de Entreno hacen con la carga simple: escribir la carga y dar OK.
@MainActor
extension XCUIApplication {
    var okSerie: XCUIElement { buttons["ok-serie"] }
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
        let centro = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        for _ in 0..<10 {
            let tope = dial.exists ? dial.frame.minY - 90 : frame.maxY - 120
            let dy: CGFloat
            if e.frame.minY < 170 { dy = 130 } else if e.frame.maxY > tope { dy = -130 } else if e.isHittable { return } else { dy = -60 }
            centro.press(forDuration: 0.05, thenDragTo: centro.withOffset(CGVector(dx: 0, dy: dy)))
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
