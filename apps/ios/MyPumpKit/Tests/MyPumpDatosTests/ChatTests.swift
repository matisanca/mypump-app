import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

private func fila(_ id: String, _ autor: String, _ texto: String, _ fecha: String, leido: Bool? = nil) -> MensajeChat {
    var o: [String: JSONValue] = ["id": .texto(id), "autor": .texto(autor), "contenido": .texto(texto), "created_at": .texto(fecha)]
    if let leido { o["leido_por_cliente"] = .bool(leido) }
    return try! JSONDecoder().decode(MensajeChat.self, from: JSONEncoder().encode(JSONValue.objeto(o)))
}

@Suite("Chat: chatMerge de la web")
struct HiloChatTests {
    @Test func noRepiteYOrdenaPorFecha() {
        var h = HiloChat()
        // get_chat devuelve de la más nueva a la más vieja.
        let entraron = h.mezclar([fila("3", "coach", "dale", "2026-10-13T10:02:00.123456+00:00"),
                                  fila("2", "cliente", "hola", "2026-10-13T10:01:00+00:00"),
                                  fila("1", "coach", "buenas", "2026-10-13T10:00:00.5+00:00")])
        #expect(entraron == 3)
        #expect(h.mensajes.map(\.id) == ["1", "2", "3"])
        #expect(h.cursor == "2026-10-13T10:02:00.123456+00:00")
        // El sondeo y la paginación se solapan: la misma fila no entra dos veces.
        let repetidas = h.mezclar([fila("3", "coach", "dale", "2026-10-13T10:02:00.123456+00:00")])
        #expect(repetidas == 0)
        #expect(h.mensajes.count == 3)
    }

    @Test func laFilaRealSeLlevaTodasLasOptimistasDelMismoTexto() {
        var h = HiloChat()
        h.agregarPendiente(BurbujaChat(id: "tmp_1", autor: "cliente", contenido: "ya entrené", leidoPorCliente: nil,
                                       createdAt: "2026-10-13T12:00:00.000Z", pendiente: true))
        h.agregarPendiente(BurbujaChat(id: "tmp_2", autor: "cliente", contenido: "ya entrené", leidoPorCliente: nil,
                                       createdAt: "2026-10-13T12:00:01.000Z", pendiente: true))
        h.mezclar([fila("9", "cliente", "ya entrené", "2026-10-13T12:00:02+00:00")])
        #expect(h.mensajes.map(\.id) == ["9"])
        #expect(h.cursor == "2026-10-13T12:00:02+00:00")
    }

    @Test func elCursorIgnoraLasPendientes() {
        var h = HiloChat()
        h.mezclar([fila("1", "coach", "hola", "2026-10-13T10:00:00+00:00")])
        h.agregarPendiente(BurbujaChat(id: "tmp", autor: "cliente", contenido: "x", leidoPorCliente: nil, createdAt: "2026-10-13T11:00:00.000Z", pendiente: true))
        h.mezclar([])
        #expect(h.cursor == "2026-10-13T10:00:00+00:00")
    }

    @Test func fallidoYReintento() {
        var h = HiloChat()
        h.agregarPendiente(BurbujaChat(id: "tmp", autor: "cliente", contenido: "x", leidoPorCliente: nil, createdAt: "2026-10-13T11:00:00.000Z", pendiente: true))
        h.marcarFallido(contenido: "x")
        #expect(h.mensajes[0].fallo)
        let reintento = h.desmarcarFallido(id: "tmp")
        #expect(reintento?.contenido == "x")
        #expect(!h.mensajes[0].fallo)
    }

    @Test func sinLeerYMarcarLeidos() {
        var h = HiloChat()
        h.mezclar([fila("1", "coach", "a", "2026-10-13T10:00:00+00:00", leido: false),
                   fila("2", "coach", "b", "2026-10-13T10:01:00+00:00", leido: true),
                   fila("3", "cliente", "c", "2026-10-13T10:02:00+00:00")])
        #expect(h.sinLeer == 1)
        let habia = h.marcarLeidos()
        #expect(habia)
        #expect(h.sinLeer == 0)
        let otraVez = h.marcarLeidos()
        #expect(!otraVez)
    }

    @Test func fechasComoJS() {
        #expect(FechaISO.ms("2026-10-13T10:00:00.123456+00:00") == 1_791_885_600_123)
        #expect(FechaISO.ms("2026-10-13T07:00:00-03:00") == 1_791_885_600_000)
        #expect(FechaISO.ms("2026-10-13 10:00:00+00") == 1_791_885_600_000)
        #expect(FechaISO.ms("") == 0)
    }
}

/// Revisión del 14-oct, hallazgo 7: lo que manda Mati con el chat abierto llega por `mypump_chat_nuevos`, que no trae
/// `leido_por_cliente`. Antes `marcarLeido` no veía nada sin leer y no avisaba al servidor: Mati lo veía sin leer y el
/// badge volvía a prenderse en el próximo arranque.
@Suite("Chat: lo que llega con el chat abierto queda leído en el servidor", .serialized)
@MainActor
struct ChatLeidoAlLlegarTests {
    @Test func loNuevoDeMatiConElChatAbiertoSeMarcaEnElServidor() async {
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_chat":
                return (200, #"[{"id":"1","autor":"cliente","contenido":"hola","leido_por_cliente":true,"created_at":"2026-10-14T10:00:00+00:00"}]"#)
            case "mypump_chat_nuevos":
                return (200, #"[{"id":"2","autor":"coach","contenido":"¿cómo venís?","created_at":"2026-10-14T10:05:00+00:00"}]"#)
            default: return (200, "true")
            }
        }
        let chat = ModeloChat(cliente: ClienteRPC(config: .produccion, transporte: t), token: "tok", outbox: nil)
        await chat.cargar()
        chat.abierto = true
        await chat.sondear()
        #expect(t.llamadas.contains("mypump_marcar_leidos_cliente"))
        #expect(chat.noLeidos == 0)
    }

    @Test func conElChatCerradoSumaAlBadgeYNoMarca() async {
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_chat":
                return (200, #"[{"id":"1","autor":"cliente","contenido":"hola","leido_por_cliente":true,"created_at":"2026-10-14T10:00:00+00:00"}]"#)
            case "mypump_chat_nuevos":
                return (200, #"[{"id":"2","autor":"coach","contenido":"¿cómo venís?","created_at":"2026-10-14T10:05:00+00:00"}]"#)
            default: return (200, "true")
            }
        }
        let chat = ModeloChat(cliente: ClienteRPC(config: .produccion, transporte: t), token: "tok", outbox: nil)
        await chat.cargar()
        await chat.sondear()
        #expect(!t.llamadas.contains("mypump_marcar_leidos_cliente"))
        #expect(chat.noLeidos == 1)
    }
}

/// CHA-04: el sondeo va cada 45 s con el chat cerrado y cada 15 s abierto (al abrirlo arranca de nuevo), y parado no
/// consulta más (la app en segundo plano lo para). Las esperas se registran en vez de dormirlas.
@Suite("Chat: los intervalos del sondeo")
@MainActor
struct SondeoChatTests {
    actor Esperas {
        var pedidas: [Double] = []
        func anotar(_ s: Double) { pedidas.append(s) }
    }

    func esperar(_ condicion: @escaping () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condicion() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condicion()
    }

    @Test func cuarentaYCincoCerradoQuinceAbiertoYNadaParado() async {
        struct Vacio: Transporte {
            func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) {
                (Data("[]".utf8), HTTPURLResponse(url: p.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        let esperas = Esperas()
        let m = ModeloChat(cliente: ClienteRPC(transporte: Vacio()), token: "tokenDePrueba_0000000000", outbox: nil)
        m.dormir = { s in await esperas.anotar(s); try? await Task.sleep(for: .milliseconds(5)) }
        m.empezarSondeo()
        #expect(await esperar { await esperas.pedidas.count >= 2 })
        #expect(await esperas.pedidas.allSatisfy { $0 == 45 })
        m.abierto = true
        let antes = await esperas.pedidas.count
        #expect(await esperar { await esperas.pedidas.count >= antes + 2 })
        #expect(await esperas.pedidas.last == 15)
        m.pararSondeo()
        try? await Task.sleep(for: .milliseconds(30))
        let parado = await esperas.pedidas.count
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await esperas.pedidas.count == parado, "siguió consultando parado")
    }
}
