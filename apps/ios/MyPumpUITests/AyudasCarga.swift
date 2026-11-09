import XCTest

/// Lo que todas las pruebas de Entreno hacen con la carga simple: escribir la carga y dar OK.
@MainActor
extension XCUIApplication {
    var okSerie: XCUIElement { buttons["ok-serie"] }
    var cargaValor: XCUIElement { textFields["carga-valor"] }

    /// Escribe la carga única y baja el teclado: con el teclado arriba el panel se esconde.
    func fijarCarga(_ texto: String) {
        XCTAssertTrue(cargaValor.waitForExistence(timeout: 15), "Sin el campo de la carga")
        cargaValor.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))   // la selección llega 0,08 s después del foco
        cargaValor.typeText(texto)
        buttons["teclado-listo"].tap()
        XCTAssertTrue(okSerie.waitForExistence(timeout: 5), "El panel no volvió al bajar el teclado")
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

    func filaSerie(_ n: Int) -> XCUIElement { descendants(matching: .any)["fila-serie-\(n)"] }
}
