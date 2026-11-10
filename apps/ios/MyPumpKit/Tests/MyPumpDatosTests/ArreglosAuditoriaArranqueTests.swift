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

/// Auditoría del 10/11, F7 y F11: al volver a la app el iPhone no pedía de nuevo la rutina ni la dieta (un plan publicado
/// hoy no se veía hasta cerrar la app del todo), y todo lo demás se releía en cada vuelta.
@Suite("Auditoría F7 y F11: el plan al volver, sin releer todo", .serialized)
@MainActor
struct ArreglosAuditoriaVolverTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("volver-\(UUID().uuidString)")

    final class Plan: @unchecked Sendable {
        private let lock = NSLock()
        private var _version = 1
        var version: Int { get { lock.withLock { _version } } set { lock.withLock { _version = newValue } } }
    }

    nonisolated static func rutina(_ v: Int) -> String {
        #"{"id":"rut-1","version":\#(v),"semana_actual":3,"tiene_siguiente":false,"estructura":{"semanas_total":12,"dias":[{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":[{"id":"press-d1-0","tipo":"principal","nombre":"Press banca \#(v)","progresion":[{"semana":1,"series":3,"reps":"8"}]}]}]}]}}"#
    }

    @Test func elPlanNuevoLlegaAlVolverPasadosUnosMinutos() async throws {
        let plan = Plan()
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, "[" + Self.rutina(plan.version) + "]")
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
        var ahora = Date(timeIntervalSince1970: 1_792_000_000)
        m.relojRelecturas = { ahora }
        await m.cargar()
        #expect(m.rutina?.version == 1)
        plan.version = 2   // Mati publicó
        let antes = t.llamadas.filter { $0 == "mypump_get_rutina_activa" }.count
        ahora += 60
        await m.alVolverAPrimerPlano()
        #expect(t.llamadas.filter { $0 == "mypump_get_rutina_activa" }.count == antes, "al minuto no se relee")
        ahora += 6 * 60
        await m.alVolverAPrimerPlano()
        #expect(m.rutina?.version == 2, "pasados unos minutos llega el plan nuevo")
    }

    @Test func conLaCopiaViejaElMotorSeRestauraConLaRutinaNueva() async throws {
        let plan = Plan()
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, "[" + Self.rutina(plan.version) + "]")
            default: return (200, "[]")
            }
        }
        await ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz).cargar()
        plan.version = 2
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
        let antes = t.llamadas.filter { $0 == "mypump_get_sesion_dia" }.count
        await m.cargar()
        try await Task.sleep(for: .milliseconds(300))
        #expect(m.entreno?.rutina.version == 2)
        #expect(t.llamadas.filter { $0 == "mypump_get_sesion_dia" }.count - antes >= 2, "el día se restauró después de reemplazar la rutina")
    }
}
