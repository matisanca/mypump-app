import XCTest

extension XCUIApplication {
    /// La pestaña por su nombre, esté donde esté: abajo en el iPhone (un TabBar) o arriba en el iPad con iPadOS 18+, donde
    /// la barra flotante no es un TabBar para XCUITest. Buscar solo en `tabBars` hacía fallar en el iPad las pruebas de
    /// acceso, avisos y la hoja de la primera vez (15-oct).
    func pestana(_ nombre: String) -> XCUIElement {
        descendants(matching: .button).matching(NSPredicate(format: "label == %@", nombre)).firstMatch
    }
}

extension XCUIApplication {
    /// Simplificar (11/11): «Mi gimnasio y mi técnica» se abre con el renglón del final de Entreno (antes, renglones de Mis
    /// datos y el botón de casa de arriba). Baja hasta él y lo toca.
    func abrirDondeEntreno(file: StaticString = #filePath, line: UInt = #line) {
        let entreno = pestana("Entreno")
        if entreno.waitForExistence(timeout: 20), !entreno.isSelected { entreno.tap() }
        let fila = descendants(matching: .any)["donde-entreno-entrada"].firstMatch
        XCTAssertTrue(fila.waitForExistence(timeout: 20), "Falta el renglón «Mi gimnasio y mi técnica»", file: file, line: line)
        var n = 0
        while !fila.isHittable && n < 25 { swipeUp(); n += 1 }
        fila.tap()
    }
}
