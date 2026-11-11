import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Auditoría del 10/11, F10: el alumno quedaba afuera sin explicación. Al volver a abrir la app después de que se dio de
/// baja el link se veía la bienvenida vacía; un link cortado tocado desde WhatsApp no decía nada; y si el link caía con la
/// app abierta, decía «sin conexión».
@Suite("Auditoría F10: el link que ya no anda se explica", .serialized)
@MainActor
struct ArreglosAuditoriaLinkTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("link-\(UUID().uuidString)")
    static let token = "BBBBBBBBBBBBBBBBBBBB"

    final class Base: @unchecked Sendable {
        private let lock = NSLock()
        private var _baja = false
        var baja: Bool { get { lock.withLock { _baja } } set { lock.withLock { _baja = newValue } } }
    }

    func transporte(_ base: Base) -> TransporteProgramado {
        TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info":
                return (200, base.baja ? "[]" : #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, "[" + ArreglosAuditoriaVolverTests.rutina(1) + "]")
            case "mypump_set_habito": return (200, base.baja ? "null" : "true")
            default: return (200, "[]")
            }
        }
    }

    @Test func alVolverAAbrirSeSigueExplicando() async {
        UserDefaults.standard.removeObject(forKey: "mypump_token_invalido")
        defer { UserDefaults.standard.removeObject(forKey: "mypump_token_invalido") }
        let base = Base()
        base.baja = true
        let almacen = TokenEnMemoria(Self.token)
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: transporte(base)), almacen: almacen, raizDisco: raiz)
        await m.cargar()
        #expect(m.fase == .tokenInvalido)
        // Se cierra la app y se vuelve a abrir: ya no hay cuenta guardada.
        let otra = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: transporte(base)), almacen: almacen, raizDisco: raiz)
        #expect(otra.fase == .tokenInvalido, "antes: la bienvenida vacía, sin decir qué pasó")
        // Si sale él (o nunca tuvo cuenta), la bienvenida de siempre.
        otra.salir()
        #expect(ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: transporte(base)), almacen: almacen, raizDisco: raiz).fase == .sinToken)
    }

    @Test func unLinkCortadoDesdeAfueraAvisa() async {
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: transporte(Base())), almacen: TokenEnMemoria(nil), raizDisco: raiz)
        #expect(await m.entrar(con: "https://app.ejemplo.com/?t=AAAA") == false)
        #expect(m.avisoLink == .malFormado)
        m.avisoLink = nil
        // Los links de los avisos (`?scene=…`) no son un link de entrada: nada.
        _ = await m.entrar(con: "mypump://abrir?scene=diet")
        #expect(m.avisoLink == nil)
    }

    @Test func siCaeConLaAppAbiertaNoDiceSinConexion() async throws {
        UserDefaults.standard.removeObject(forKey: "mypump_token_invalido")
        defer { UserDefaults.standard.removeObject(forKey: "mypump_token_invalido") }
        let base = Base()
        let t = transporte(base)
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
        await m.cargar()
        #expect(m.fase == .listo)
        base.baja = true   // Mati da de baja el link mientras el alumno usa la app
        _ = await m.outbox?.encolar("habito", .objeto(["fecha": .texto("2026-11-10"), "campo": .texto("agua"), "valor": .numero(3)]), dedupeKey: "h1")
        await m.outbox?.drenar()
        for _ in 0..<100 where m.fase != .tokenInvalido { try await Task.sleep(for: .milliseconds(20)) }
        #expect(m.fase == .tokenInvalido)
    }
}
