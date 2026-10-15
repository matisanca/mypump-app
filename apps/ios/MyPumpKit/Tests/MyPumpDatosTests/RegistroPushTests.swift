import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// NOT-01: el push se registra una vez por teléfono y por cuenta. Con el link de otra cuenta en el mismo teléfono se
/// vuelve a registrar: si no, los avisos seguían yendo a la anterior (lo encontró el agente de Android, 14-oct; Android
/// tiene el gemelo en AgendaAvisosTest).
@Suite("Push: una vez por teléfono y por cuenta (NOT-01)", .serialized)
@MainActor
struct RegistroPushTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("registro-push-\(UUID().uuidString)")
    static let cuentaA = "AAAAAAAAAAAAAAAAAAAA"
    static let cuentaB = "BBBBBBBBBBBBBBBBBBBB"

    func modelo(_ token: String, _ t: TransporteProgramado) -> ModeloApp {
        ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(token), raizDisco: raiz)
    }

    func registros(_ t: TransporteProgramado) -> Int { t.llamadas.filter { $0 == "mypump_registrar_push" }.count }

    @Test func otraCuentaEnElMismoTelefonoVuelveARegistrar() async throws {
        let suite = "registro-push-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let t = TransporteProgramado { fn, _ in fn == "mypump_registrar_push" ? (200, "true") : (200, "[]") }

        let a = modelo(Self.cuentaA, t)
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults))
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults))
        #expect(registros(t) == 1, "la misma cuenta con el mismo token: una sola vez")

        let b = modelo(Self.cuentaB, t)
        #expect(await b.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults))
        #expect(registros(t) == 2, "otra cuenta en el mismo teléfono: se vuelve a registrar")
        #expect(defaults.string(forKey: "mypump_push_cuenta") == ModeloApp.huellaPush(Self.cuentaB))
        #expect(defaults.string(forKey: "mypump_push_cuenta")?.contains(Self.cuentaB) == false, "la huella, nunca el token")

        // Un token nuevo de APNs en la misma cuenta también se registra.
        #expect(await b.registrarPush(dispositivo: "DEF456", version: "2.0.0", defaults: defaults))
        #expect(registros(t) == 3)
    }

    @Test func unRechazoNoQuedaAnotado() async throws {
        let suite = "registro-push-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let t = TransporteProgramado { fn, _ in fn == "mypump_registrar_push" ? (200, "false") : (200, "[]") }
        let a = modelo(Self.cuentaA, t)
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults) == false)
        #expect(defaults.string(forKey: "mypump_push_token") == nil && defaults.string(forKey: "mypump_push_cuenta") == nil)
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults) == false)
        #expect(registros(t) == 2, "lo que el servidor no aceptó se vuelve a intentar")
    }
}
