import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Abrir el Chat mientras carga la cuenta (por ejemplo, al tocar un aviso de Mati) pedía dos veces la última página: la
/// pantalla la traía al abrirse y la carga de la cuenta la volvía a pedir al llegar al chat (lo encontró el agente de
/// Android el 15-oct; Android tiene la misma prueba, ChatAlAbrirTest).
@Suite("Abrir el chat mientras carga la cuenta no lo pide dos veces", .serialized)
@MainActor
struct ChatAlAbrirTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("chat-al-abrir-\(UUID().uuidString)")

    final class Pedidos: @unchecked Sendable {
        private let lock = NSLock()
        private var _chats = 0
        var chats: Int { lock.withLock { _chats } }
        func sumar() { lock.withLock { _chats += 1 } }
    }

    func modelo(_ p: Pedidos) -> ModeloApp {
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, SwapsViejosPalancaTests.dieta)
            case "mypump_get_cliente_prefs", "mypump_get_custom_foods":
                // La ventana: la cuenta ya está a la vista y la carga todavía no llegó al chat.
                try await Task.sleep(for: .milliseconds(300))
                return (200, "[]")
            case "mypump_get_chat":
                p.sumar()
                return (200, "[]")
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"),
                         raizDisco: raiz)
    }

    @Test func abrirloDuranteLaCargaLoPideUnaSolaVez() async throws {
        let p = Pedidos()
        let m = modelo(p)
        async let carga: Void = m.cargar()
        while m.fase != .listo || m.chat == nil { try await Task.sleep(for: .milliseconds(10)) }
        await m.chat?.alAbrir()
        await carga
        #expect(p.chats == 1, "la última página se pidió \(p.chats) veces")
    }

    /// Una carga nueva de la cuenta (volver de la copia sin red, tirar para actualizar) sí lo trae de nuevo.
    @Test func otraCargaDeLaCuentaLoVuelveATraer() async {
        let p = Pedidos()
        let m = modelo(p)
        await m.cargar()
        await m.chat?.alAbrir()
        #expect(p.chats == 1, "abrirlo ya traído no lo pide")
        await m.cargar()
        #expect(p.chats == 2)
    }
}
