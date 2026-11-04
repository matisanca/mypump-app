import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Las dudas en audio contra el servidor REAL (entregas_019), con el cliente de prueba `test-nativa-ios` (nunca un
/// cliente). El token llega por `MYPUMP_AUDIO_TOKEN` y el audio (un m4a AAC mono) por `MYPUMP_AUDIO_ARCHIVO`. Sube UN
/// audio por corrida (y lo vuelve a mandar con el mismo p_id, que no suma otro): avisar para la limpieza.
private let tokenAudio = ProcessInfo.processInfo.environment["MYPUMP_AUDIO_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }
private let archivoAudio = ProcessInfo.processInfo.environment["MYPUMP_AUDIO_ARCHIVO"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }

@Suite("Dudas en audio contra el servidor (cliente de prueba)", .enabled(if: tokenAudio != nil && archivoAudio != nil), .serialized)
@MainActor
struct AudioDudaIntegracionTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-audio-int-\(UUID().uuidString)")

    @Test func subirUnAudioYVerloEnLaLista() async throws {
        let t = tokenAudio ?? "", origen = try #require(archivoAudio)
        let cliente = ClienteRPC()
        let disco = Disco(raiz: raiz, token: t)
        let carpeta = disco.url("audios")
        let escrituras = Escrituras(cliente: cliente, token: t, carpetaAudios: carpeta)
        let cola = Outbox(archivo: disco.url("outbox.json"), reintentoAutomatico: false) { await escrituras.ejecutar($0) }
        let m = ModeloAudioDuda(cliente: cliente, token: t, outbox: cola, disco: disco)
        await cola.observar(estado: { _ in }, abandonadas: { ops in Task { @MainActor in m.alAbandonar(ops) } },
                            guardadas: { ops in Task { @MainActor in m.alGuardar(ops) } })

        // La 019 está: la lista responde y el botón aparece.
        await m.consultar()
        #expect(m.disponible)
        let antes = m.servidor.count

        // El audio de verdad, por la cola.
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        let nombre = "\(id).m4a"
        try FileManager.default.copyItem(at: origen, to: carpeta.appendingPathComponent(nombre))
        let bytes = try Data(contentsOf: origen).count
        let payload: JSONValue = .objeto(["id": .texto(id), "archivo": .texto(nombre), "mime": .texto("audio/mp4"),
                                          "bytes": .numero(Double(bytes)), "segundos": .numero(4)])
        await cola.encolar(ModeloAudioDuda.kind, payload, dedupeKey: "guia_audio_\(id)")
        await cola.drenar()
        #expect(await cola.pendientes == 0)
        #expect(await cola.fallidos.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        #expect(m.filas.first { $0.id == id }?.estado == .subido)

        // Mandarlo otra vez con el mismo p_id: la re-subida da 403 y `subido` confirma. No suma otro audio.
        try FileManager.default.copyItem(at: origen, to: carpeta.appendingPathComponent(nombre))
        let r = await escrituras.ejecutar(Operacion(id: "otra", kind: ModeloAudioDuda.kind, payload: payload, dedupeKey: nil, ts: 0))
        guard case .respuesta(.success(let j)) = r else { Issue.record("el reenvío no salió bien: \(r)"); return }
        #expect(j["ok"] == .bool(true))

        await m.consultar()
        let mios = m.servidor.filter { $0.id == id }
        #expect(mios.count == 1)
        #expect(mios.first?.estado == .subido || mios.first?.estado == .transcripto)
        #expect(m.servidor.count == antes + 1)
        print("audio subido a test-nativa-ios: id \(id), \(bytes) bytes, estado \(mios.first?.estado.rawValue ?? "?"), segundos \(mios.first?.segundos ?? -1)")
    }
}
