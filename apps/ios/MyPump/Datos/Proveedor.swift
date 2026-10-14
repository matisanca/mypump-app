import Foundation
import MyPumpDatos

/// El modelo de la app, uno solo para todas las pantallas. Mientras las demás pestañas sigan siendo bocetos con
/// `Muestras`, Dieta ya usa este (datos reales).
@MainActor
enum Proveedor {
    static let modelo: ModeloApp = {
        #if DEBUG
        let d = UserDefaults.standard
        // `-sinOnboarding YES`: las capturas y las pruebas de interfaz no esperan la hoja de permisos;
        // `-reiniciarOnboarding YES` la vuelve a mostrar. Van antes del atajo de `-token`, que vuelve enseguida.
        if d.bool(forKey: "sinOnboarding") { d.set("1", forKey: "mypump_onboarding_v1") }
        if d.bool(forKey: "reiniciarOnboarding") { d.removeObject(forKey: "mypump_onboarding_v1") }
        // Desarrollo: `simctl launch … -token <TOKEN>` entra con una cuenta de prueba sin pasar por el link.
        if let t = d.string(forKey: "token"), FormatoToken.valido(t) {
            return ModeloApp(almacen: TokenEnMemoria(t))
        }
        // `-reiniciar YES`: arranca como recién instalada (sin token guardado), para probar la bienvenida.
        if d.bool(forKey: "reiniciar") {
            TokenEnKeychain().guardar(nil)
            d.removeObject(forKey: "mypump_token_invalido")
        }
        #endif
        // La migración del almacenamiento viejo corre ANTES de crear el modelo (que lee token y cola al iniciar).
        return ArranqueMigracion.arrancar { ModeloApp() }
    }()
}
