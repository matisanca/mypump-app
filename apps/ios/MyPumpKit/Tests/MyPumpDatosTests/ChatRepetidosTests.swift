import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 7, con el modelo entero (la cola, las escrituras y el hilo):
/// - un mensaje igual a uno mandado en los últimos 2 minutos quedaba "enviando…" hasta reiniciar: el servidor deduplica
///   (mig 075) y devuelve la fila vieja, así que nunca llega una fila nueva que saque la burbuja;
/// - con el reloj del teléfono atrasado, `yaLlego` tomaba un mensaje igual de hasta una hora antes como este y el nuevo
///   no salía nunca.
@Suite("Chat: mensajes repetidos", .serialized)
@MainActor
struct ChatRepetidosTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("chat-repetidos-\(UUID().uuidString)")

    func esperar(_ condicion: () async -> Bool) async -> Bool {
        for _ in 0..<150 {
            if await condicion() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condicion()
    }

    func modelo(_ t: TransporteProgramado) -> ModeloApp {
        ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
    }

    nonisolated static func fila(_ id: String, _ texto: String, _ fecha: Date) -> String {
        #"{"id":"\#(id)","autor":"cliente","contenido":"\#(texto)","leido_por_cliente":true,"created_at":"\#(FechaISO.texto(fecha))"}"#
    }

    @Test func unRepetidoQueElServidorDeduplicaNoQuedaEnviando() async throws {
        let hace90Segundos = Date().addingTimeInterval(-90)
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_chat": return (200, "[" + Self.fila("m5", "dale", hace90Segundos) + "]")
            case "mypump_agregar_comentario": return (200, #""m5""#)   // 075: el mismo texto en 2 minutos es la fila que ya estaba
            default: return (200, "[]")
            }
        }
        let m = modelo(t)
        await m.cargar()
        let chat = try #require(m.chat)
        #expect(chat.hilo.mensajes.map(\.id) == ["m5"])
        await chat.enviar("dale")
        #expect(await esperar { t.llamadas.contains("mypump_agregar_comentario") && t.llamadas.contains("mypump_chat_nuevos") })
        #expect(await esperar { !chat.hilo.mensajes.contains(where: \.pendiente) }, "quedó \"enviando…\" para siempre")
        #expect(chat.hilo.mensajes.map(\.id) == ["m5"])
    }

    @Test func conElRelojAtrasadoUnRepetidoDeHaceMediaHoraSale() async throws {
        // El teléfono atrasa una hora: para el servidor el "dale" anterior fue hace media hora, que en el reloj del
        // teléfono es media hora en el futuro.
        let anterior = Date().addingTimeInterval(30 * 60)
        let nuevo = Date().addingTimeInterval(60 * 60)
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_chat": return (200, "[" + Self.fila("m5", "dale", anterior) + "]")
            case "mypump_agregar_comentario": return (200, #""m6""#)
            case "mypump_chat_nuevos": return (200, "[" + Self.fila("m6", "dale", nuevo) + "]")
            default: return (200, "[]")
            }
        }
        let m = modelo(t)
        await m.cargar()
        let chat = try #require(m.chat)
        await chat.enviar("dale")
        #expect(await esperar { t.llamadas.contains("mypump_chat_nuevos") })
        #expect(await esperar { await m.outbox?.pendientes == 0 })
        #expect(t.llamadas.filter { $0 == "mypump_agregar_comentario" }.count == 1, "el mensaje nuevo no salió: se tomó el de hace media hora")
        #expect(await esperar { chat.hilo.mensajes.map(\.id) == ["m5", "m6"] })
    }

    @Test func unReintentoDeAlgoQueYaHabiaLlegadoNoSeMandaDosVeces() async throws {
        // La primera vez el mensaje llega pero la respuesta se pierde; el reintento lo encuentra en el hilo (con el reloj
        // del teléfono atrasado una hora, como en la de arriba).
        let anterior = Date().addingTimeInterval(30 * 60)
        let llego = Date().addingTimeInterval(60 * 60)
        let estado = EstadoChatServidor()
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_chat":
                return (200, "[" + (estado.llego ? Self.fila("m6", "dale", llego) + "," : "") + Self.fila("m5", "dale", anterior) + "]")
            case "mypump_agregar_comentario":
                estado.llego = true
                throw URLError(.networkConnectionLost)
            default: return (200, "[]")
            }
        }
        let m = modelo(t)
        await m.cargar()
        let chat = try #require(m.chat)
        await chat.enviar("dale")
        #expect(await esperar { estado.llego })
        // El reintento (la cola lo programa sola; acá se fuerza).
        for _ in 0..<3 { await m.outbox?.drenar() }
        #expect(await esperar { await m.outbox?.pendientes == 0 })
        #expect(t.llamadas.filter { $0 == "mypump_agregar_comentario" }.count == 1, "se mandó de nuevo algo que ya estaba")
    }
}

final class EstadoChatServidor: @unchecked Sendable {
    private let lock = NSLock()
    private var _llego = false
    var llego: Bool { get { lock.withLock { _llego } } set { lock.withLock { _llego = newValue } } }
}
