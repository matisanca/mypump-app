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
