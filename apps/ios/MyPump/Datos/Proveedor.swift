import Foundation
import MyPumpDatos

/// El modelo de la app, uno solo para todas las pantallas. Mientras las demás pestañas sigan siendo bocetos con
/// `Muestras`, Dieta ya usa este (datos reales).
@MainActor
enum Proveedor {
    static let modelo: ModeloApp = {
        let m = crear()
        // Al volver al frente con la cuenta: el domingo al día y el token de push (un permiso dado desde Ajustes se
        // registra ahí, no en el próximo arranque; hallazgo 9).
        m.conAvisos = { await CentroAvisos.shared.alEntrar() }
        return m
    }()

    private static func crear() -> ModeloApp {
        #if DEBUG
        let d = UserDefaults.standard
        // `-sinOnboarding YES`: las capturas y las pruebas de interfaz no esperan la hoja de permisos;
        // `-reiniciarOnboarding YES` la vuelve a mostrar. Van antes del atajo de `-token`, que vuelve enseguida.
        if d.bool(forKey: "sinOnboarding") { d.set("1", forKey: "mypump_onboarding_v1") }
        if d.bool(forKey: "reiniciarOnboarding") { d.removeObject(forKey: "mypump_onboarding_v1") }
        // Desarrollo: `simctl launch … -token <TOKEN>` entra con una cuenta de prueba sin pasar por el link.
        if let t = d.string(forKey: "token"), FormatoToken.valido(t) {
            // `-sinRed YES`: como sin señal (el gimnasio). La app arranca de su copia guardada y lo que se carga queda
            // en la cola hasta el próximo arranque sin el argumento.
            return ModeloApp(cliente: d.bool(forKey: "sinRed") ? ClienteRPC(transporte: SinRed()) : ClienteRPC(), almacen: TokenEnMemoria(t))
        }
        // `-reiniciar YES`: arranca como recién instalada (sin token guardado), para probar la bienvenida.
        if d.bool(forKey: "reiniciar") {
            TokenEnKeychain().guardar(nil)
            d.removeObject(forKey: "mypump_token_invalido")
        }
        #endif
        // La migración del almacenamiento viejo corre ANTES de crear el modelo (que lee token y cola al iniciar).
        return ArranqueMigracion.arrancar { ModeloApp() }
    }
}

#if DEBUG
/// Todo pedido falla como sin señal (`-sinRed YES`).
private struct SinRed: Transporte {
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) }
}
#endif
