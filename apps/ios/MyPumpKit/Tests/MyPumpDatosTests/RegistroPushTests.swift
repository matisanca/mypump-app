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

    /// Hallazgo 9 (15-oct): si `push.py` da de baja la fila (APNs dijo que el token no sirve, o un envío falló), el
    /// teléfono no volvía a registrarse mientras no cambiara su token. Ahora se registra de nuevo aunque no haya cambiado,
    /// como mucho una vez cada 7 días.
    @Test func seVuelveARegistrarAunqueNoCambieUnaVezPorSemana() async throws {
        let suite = "registro-push-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let t = TransporteProgramado { fn, _ in fn == "mypump_registrar_push" ? (200, "true") : (200, "[]") }
        let a = modelo(Self.cuentaA, t)
        let dia0 = Date(timeIntervalSince1970: 1_792_000_000)
        func dia(_ n: Double) -> Date { dia0.addingTimeInterval(n * 86_400) }

        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults, ahora: dia0))
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults, ahora: dia(1)))
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults, ahora: dia(6.9)))
        #expect(registros(t) == 1, "dentro de la semana, una sola vez")
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults, ahora: dia(7)))
        #expect(registros(t) == 2, "a los 7 días se registra de nuevo aunque el token sea el mismo")
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults, ahora: dia(8)))
        #expect(registros(t) == 2)
        // Un reloj que vuelve para atrás (el cliente cambió la fecha) tampoco lo deja sin registrar.
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults, ahora: dia(-30)))
        #expect(registros(t) == 3)
    }

    /// Lo que dejó una versión anterior (token y cuenta, sin fecha): se registra una vez más y queda con fecha.
    @Test func sinFechaAnotadaSeRegistra() async throws {
        let suite = "registro-push-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ABC123", forKey: "mypump_push_token")
        defaults.set(ModeloApp.huellaPush(Self.cuentaA), forKey: "mypump_push_cuenta")
        let t = TransporteProgramado { fn, _ in fn == "mypump_registrar_push" ? (200, "true") : (200, "[]") }
        let a = modelo(Self.cuentaA, t)
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults))
        #expect(await a.registrarPush(dispositivo: "ABC123", version: "2.0.0", defaults: defaults))
        #expect(registros(t) == 1)
    }

    /// Hallazgo 9: un permiso de notificaciones dado desde Ajustes no se registraba hasta el próximo arranque (lo de los
    /// avisos corría solo al cambiar la fase). Ahora corre también cada vez que la app vuelve al frente con la cuenta.
    @Test func alVolverAlFrenteConLaCuentaSeRegistranLosAvisos() async throws {
        let t = TransporteProgramado { fn, _ in
            fn == "mypump_get_cliente_info" ? (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#) : (200, "[]")
        }
        let a = modelo(Self.cuentaA, t)
        let veces = ContadorAvisos()
        a.conAvisos = { veces.n += 1 }
        await a.cargar()
        await a.alVolverAPrimerPlano()
        #expect(veces.n == 1, "al volver al frente no se registró")
        await a.alVolverAPrimerPlano()
        #expect(veces.n == 2)
        // Sin cuenta no hay nada que registrar.
        a.salir()
        await a.alVolverAPrimerPlano()
        #expect(veces.n == 2)
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

@MainActor
final class ContadorAvisos {
    var n = 0
}
