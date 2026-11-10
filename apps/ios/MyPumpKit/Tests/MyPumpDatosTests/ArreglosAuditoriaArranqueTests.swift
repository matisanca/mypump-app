import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Auditoría del 10/11, F2: con mala señal la app miraba el logo 20 a 40 segundos aunque tuviera el plan guardado. Ahora
/// la copia se muestra al toque y se actualiza por detrás.
@Suite("Auditoría F2: arranque con la copia primero", .serialized)
@MainActor
struct ArreglosAuditoriaArranqueTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("arranque-copia-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"
    nonisolated static let rutina = #"{"id":"rut-1","version":1,"semana_actual":3,"tiene_siguiente":false,"estructura":{"semanas_total":12,"dias":[{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":[{"id":"press-d1-0","tipo":"principal","nombre":"Press banca","progresion":[{"semana":1,"series":3,"reps":"8"}]}]}]}]}}"#

    final class Lento: @unchecked Sendable {
        private let lock = NSLock()
        private var _ms = 0
        var ms: Int { get { lock.withLock { _ms } } set { lock.withLock { _ms = newValue } } }
    }

    func modelo(_ lento: Lento) -> ModeloApp {
        let t = TransporteProgramado { fn, _ in
            if lento.ms > 0 { try await Task.sleep(for: .milliseconds(lento.ms)) }
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, "[" + Self.rutina + "]")
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
    }

    @Test func conCopiaGuardadaSeMuestraSinEsperarAlServidor() async throws {
        let lento = Lento()
        // Primera apertura con señal: queda la copia.
        await modelo(lento).cargar()
        // Segunda apertura con la señal colgada: el servidor tarda 1,5 s en cada pedido.
        lento.ms = 1500
        let m = modelo(lento)
        let carga = Task { await m.cargar() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(m.fase == .listo, "con la copia no se espera al servidor")
        #expect(m.rutina?.id == "rut-1")
        #expect(!m.desdeCache, "mientras se actualiza no se avisa «sin conexión»")
        await carga.value
        #expect(m.fase == .listo && m.rutina?.id == "rut-1" && !m.desdeCache)
    }

    @Test func sinCopiaSigueEsperando() async throws {
        let lento = Lento()
        lento.ms = 600
        let m = modelo(lento)
        let carga = Task { await m.cargar() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(m.fase == .cargando)
        await carga.value
        #expect(m.fase == .listo)
    }
}
