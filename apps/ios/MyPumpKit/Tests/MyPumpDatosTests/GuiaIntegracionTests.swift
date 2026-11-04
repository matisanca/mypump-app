import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// «Tu guía» contra el servidor REAL, con el cliente de prueba `test-nativa-ios` (nunca un cliente). El token llega por
/// la variable de entorno `MYPUMP_GUIA_TOKEN` (no está en el repo ni en el log). Escribe en ese cliente de prueba: un
/// avance de 12 s sin visto y, con `MYPUMP_GUIA_ESCRIBIR_DUDAS=1`, una duda de video y una de la videollamada.
private let tokenGuia = ProcessInfo.processInfo.environment["MYPUMP_GUIA_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }
private let escribirDudas = ProcessInfo.processInfo.environment["MYPUMP_GUIA_ESCRIBIR_DUDAS"] == "1"

@Suite("Tu guía contra el servidor (cliente de prueba)", .enabled(if: tokenGuia != nil), .serialized)
@MainActor
struct GuiaIntegracionTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-guia-int-\(UUID().uuidString)")

    private func armar() -> (ModeloGuia, Outbox) {
        let t = tokenGuia ?? ""
        let cliente = ClienteRPC()
        let disco = Disco(raiz: raiz, token: t)
        let escrituras = Escrituras(cliente: cliente, token: t)
        let cola = Outbox(archivo: disco.url("outbox.json"), reintentoAutomatico: false) { await escrituras.ejecutar($0) }
        let m = ModeloGuia(cliente: cliente, token: t, outbox: cola, disco: disco)
        Task { await cola.observar(estado: { _ in }, abandonadas: { ops in Task { @MainActor in m.alAbandonar(ops) } },
                                   guardadas: { ops in Task { @MainActor in m.alGuardar(ops) } }) }
        return (m, cola)
    }

    @Test func resumenGetYAvance() async throws {
        let (m, cola) = armar()
        await m.actualizarResumen()
        let r = try #require(m.resumen)
        #expect(r.ok && r.total >= 1, "test-nativa-ios tiene la guía aprobada")
        await m.abrir()
        #expect(m.estado == .lista)
        let g = try #require(m.guia)
        #expect(g.clips.count == r.total)
        #expect(g.clips.allSatisfy { !$0.id.isEmpty && !$0.titulo.isEmpty })
        #expect(g.clips.contains { $0.url != nil })
        #expect(!ReglasGuiaBloques.titulos(g.clips).isEmpty)
        // Un avance chico, sin visto (la base toma el mayor: no le baja nada a lo que ya haya).
        let clip = try #require(m.clips.first { $0.url != nil })
        await m.avance(video: clip.id, segundos: 12, visto: false)
        await cola.drenar()
        let fallidos = await cola.fallidos
        let quedan = await cola.pendientes
        #expect(quedan == 0 && fallidos.isEmpty)
        let (otro, _) = armar()
        await otro.abrir()
        #expect((otro.guia?.clips.first { $0.id == clip.id }?.segundos ?? 0) >= 12)
    }

    @Test(.enabled(if: escribirDudas)) func dudasDeVideoYDeLaLlamada() async throws {
        let (m, cola) = armar()
        await m.abrir()
        let clip = try #require(m.clips.first)
        let marca = "Prueba nativa iOS \(Int(Date().timeIntervalSince1970))"
        m.borradores[clip.id] = marca
        #expect(await m.enviarDuda(video: clip.id))
        m.borradores[""] = marca
        #expect(await m.enviarDudaLlamada())
        await cola.drenar()
        let (otro, _) = armar()
        await otro.abrir()
        #expect(otro.guia?.clips.first { $0.id == clip.id }?.duda?.contains(marca) == true)
        #expect(otro.guia?.dudasLlamada.contains { $0.texto == marca } == true)
    }

    @Test func unTokenQueNoExisteNoTieneGuia() async {
        let falso = "token_que_no_existe_\(UUID().uuidString.prefix(8))"
        let m = ModeloGuia(cliente: ClienteRPC(), token: falso, outbox: nil, disco: Disco(raiz: raiz, token: falso))
        await m.actualizarResumen()
        #expect(m.resumen?.ok == false && !m.mostrarTarjeta)
        await m.abrir()
        #expect(m.estado == .oculta)
    }
}

enum ReglasGuiaBloques {
    static func titulos(_ c: [ClipGuia]) -> [String] { Array(Set(c.compactMap(\.bloque))) }
}
