import XCTest

extension XCUIApplication {
    /// La pestaña por su nombre, esté donde esté: abajo en el iPhone (un TabBar) o arriba en el iPad con iPadOS 18+, donde
    /// la barra flotante no es un TabBar para XCUITest. Buscar solo en `tabBars` hacía fallar en el iPad las pruebas de
    /// acceso, avisos y la hoja de la primera vez (15-oct).
    func pestana(_ nombre: String) -> XCUIElement {
        descendants(matching: .button).matching(NSPredicate(format: "label == %@", nombre)).firstMatch
    }
}
