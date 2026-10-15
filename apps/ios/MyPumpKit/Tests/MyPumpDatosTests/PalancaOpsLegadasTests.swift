import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 2: con la palanca remota `migracion_ops_legadas` apagada (el freno de emergencia de la
/// migración, `nativa_001`), las ops que la Fase L deja directo en la cola (hábitos, chat, peso, check, comidas, swaps
/// y series con sesión) salían igual en la primera carga: la palanca solo frenaba la Fase R.
@Suite("La palanca frena las ops de la migración", .serialized)
@MainActor
struct PalancaOpsLegadasTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("palanca-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"

    /// Una op de hábito de la cola vieja, como la deja la Fase L (`importarEnArchivo`) en la cola de la cuenta.
    func sembrarOpVieja() throws {
        let vieja = Operacion(id: "cap-1", kind: "habito", payload: .objeto(["fecha": .texto("2026-10-14"), "campo": .texto("agua"), "valor": .numero(3)]),
                              dedupeKey: "habito_2026-10-14_agua", ts: 1_000)
        let quedaron = try Outbox.importarEnArchivo(Disco(raiz: raiz, token: Self.token).url("outbox.json"), [vieja])
        #expect(quedaron.first?.legado == true, "la Fase L la marca como de la Capacitor")
    }

    func modelo(_ palanca: Palanca) -> (ModeloApp, TransporteProgramado) {
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_app_config": return (200, #"{"migracion_ops_legadas":\#(palanca.prendida)}"#)
            case "mypump_set_habito": return (200, "true")
            default: return (200, "[]")
            }
        }
        return (ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz), t)
    }

    @Test func conLaPalancaApagadaLaOpViejaNoSaleYAlPrenderlaSale() async throws {
        try sembrarOpVieja()
        let palanca = Palanca(prendida: false)
        let (m, t) = modelo(palanca)
        await m.cargar()
        #expect(!t.llamadas.contains("mypump_set_habito"), "salió con la palanca apagada")
        #expect(await m.outbox?.pendientes == 1, "quedó guardada en la cola")

        // Una escritura nativa sale igual, y la vieja sigue retenida.
        await m.outbox?.encolar("habito", .objeto(["fecha": .texto("2026-10-15"), "campo": .texto("entreno"), "valor": .texto("entrene")]), dedupeKey: "habito_2026-10-15_entreno")
        await m.outbox?.drenar()
        #expect(t.llamadas.filter { $0 == "mypump_set_habito" }.count == 1)
        #expect(await m.outbox?.operaciones.map(\.id) == ["cap-1"])

        // Se vuelve a prender: en la próxima carga sale.
        palanca.prendida = true
        await m.cargar()
        await m.outbox?.drenar()
        #expect(t.llamadas.filter { $0 == "mypump_set_habito" }.count == 2)
        #expect(await m.outbox?.pendientes == 0)
    }

    @Test func conLaPalancaPrendidaSaleEnLaPrimeraCarga() async throws {
        try sembrarOpVieja()
        let (m, t) = modelo(Palanca(prendida: true))
        await m.cargar()
        #expect(t.llamadas.contains("mypump_set_habito"))
        #expect(await m.outbox?.pendientes == 0)
    }
}

final class Palanca: @unchecked Sendable {
    private let lock = NSLock()
    private var _prendida: Bool
    init(prendida: Bool) { _prendida = prendida }
    var prendida: Bool { get { lock.withLock { _prendida } } set { lock.withLock { _prendida = newValue } } }
}
