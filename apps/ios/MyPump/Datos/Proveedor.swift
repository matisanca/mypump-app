import Foundation
import MyPumpDatos

/// El modelo de la app, uno solo para todas las pantallas. Mientras las demás pestañas sigan siendo bocetos con
/// `Muestras`, Dieta ya usa este (datos reales).
@MainActor
enum Proveedor {
    static let modelo: ModeloApp = {
        #if DEBUG
        // Desarrollo: `simctl launch … -token <TOKEN>` entra con una cuenta de prueba sin pasar por el link.
        if let t = UserDefaults.standard.string(forKey: "token"), FormatoToken.valido(t) {
            return ModeloApp(almacen: TokenEnMemoria(t))
        }
        #endif
        return ModeloApp()
    }()
}
