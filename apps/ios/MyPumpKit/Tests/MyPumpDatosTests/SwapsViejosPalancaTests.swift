import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// sim-migracion.sh (15-oct): un teléfono de la v1.0.11, sin la marca de migrados, con un reemplazo de comida que solo
/// estaba en el teléfono (c3) y otro en la cola vieja (c1). Al leer la palanca la cola soltaba las ops de la migración, y
/// el `swap` de c1 llegaba al servidor antes de que la hidratación preguntara qué tenía. El servidor «ya tenía algo», ganaba
/// la mezcla y c3 se perdía. Ahora los `swap` y `swap_del` viejos esperan esa decisión; las demás ops viejas salen igual.
@Suite("Los reemplazos de comida viejos esperan la decisión de la migración", .serialized)
@MainActor
struct SwapsViejosPalancaTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("swaps-viejos-\(UUID().uuidString)")
    nonisolated static let token = "AAAAAAAAAAAAAAAAAAAA"
    nonisolated static let dietaId = "dieta-d"
    static let c1 = "swap_dieta-d_c1_0_0"
    static let c3 = "swap_dieta-d_c3_0_0"

    nonisolated static let dieta = #"[{"id":"dieta-d","version":1,"estructura":{"macros_target":{"kcal":2500,"prot":180,"carb":250,"fat":80},"comidas":["#
        + #"{"id":"c1","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Pollo","qty":200,"unit":"g","kcal":330,"prot":62,"carb":0,"fat":7}]}]},"#
        + #"{"id":"c3","name":"Cena","options":[{"name":"A","foods":[{"name":"Merluza","qty":250,"unit":"g","kcal":225,"prot":45,"carb":0,"fat":4}]}]}]}}]"#

    /// La cola vieja con un hábito y el reemplazo de c1; el mapa del teléfono con c1 y c3; sin la marca de migrados.
    func sembrar() throws {
        let disco = Disco(raiz: raiz, token: Self.token)
        let habito = Operacion(id: "cap-habito", kind: "habito", payload: .objeto(["fecha": .texto("2026-10-14"), "campo": .texto("agua"), "valor": .numero(3)]),
                               dedupeKey: "habito_2026-10-14_agua", ts: 1_000)
        let ricota: JSONValue = .objeto(["name": .texto("Ricota"), "_orig": .objeto(["name": .texto("Pollo"), "qty": .numero(200), "unit": .texto("g")])])
        let swapC1 = Operacion(id: "cap-swap", kind: "swap", payload: .objeto(["dietaId": .texto(Self.dietaId), "comidaId": .texto("c1"),
                               "optIdx": .numero(0), "foodIdx": .numero(0), "food": ricota]), dedupeKey: Self.c1, ts: 1_001)
        let quedaron = try Outbox.importarEnArchivo(disco.url("outbox.json"), [habito, swapC1])
        #expect(quedaron.allSatisfy { $0.legado == true })
        disco.guardar([
            Self.c1: SwapLocal(original: .objeto(["name": .texto("Pollo"), "qty": .numero(200), "unit": .texto("g")]), current: ricota),
            Self.c3: SwapLocal(original: .objeto(["name": .texto("Merluza")]),
                               current: .objeto(["name": .texto("Atún"), "_orig": .objeto(["name": .texto("Merluza"), "qty": .numero(250), "unit": .texto("g")])])),
        ], "swaps_\(Self.dietaId).json")
    }

    func modelo(_ s: ServidorDeSwaps) -> ModeloApp {
        let t = TransporteProgramado { fn, cuerpo in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, Self.dieta)
            case "mypump_get_app_config": return (200, #"{"migracion_ops_legadas":true}"#)
            case "mypump_get_cliente_prefs", "mypump_get_custom_foods":
                // Lo de antes de preguntar por los reemplazos tarda, como en un teléfono de verdad: la cola ya está mandando.
                try await Task.sleep(for: .milliseconds(150))
                return (200, "[]")
            case "mypump_get_food_swaps":
                if s.lecturaFalla { throw URLError(.notConnectedToInternet) }
                return (200, s.filas())
            case "mypump_save_food_swap":
                s.guardar(cuerpo["p_comida_id"]?.comoTexto ?? "?", cuerpo["p_food_data"] ?? .null)
                return (200, #"[{"id":"1"}]"#)
            case "mypump_set_habito":
                s.anotarHabito()
                return (200, "true")
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
    }

    @Test func elReemplazoQueSoloEstabaEnElTelefonoNoSePierde() async throws {
        try sembrar()
        let s = ServidorDeSwaps()
        let m = modelo(s)
        await m.cargar()
        await m.outbox?.drenar()
        #expect(s.comidas == ["c1", "c3"], "c3 se perdía: el swap viejo de c1 llegaba antes de la decisión")
        #expect(Set(m.swaps.keys) == [Self.c1, Self.c3])
        #expect(s.habitos == 1, "las demás ops viejas salen igual")
        #expect(await m.outbox?.pendientes == 0)
    }

    @Test func sinPoderPreguntarLosReemplazosViejosEsperanYLoDemasSale() async throws {
        try sembrar()
        let s = ServidorDeSwaps()
        s.lecturaFalla = true
        let m = modelo(s)
        await m.cargar()
        await m.outbox?.drenar()
        #expect(s.comidas.isEmpty, "salió un reemplazo viejo sin decidir")
        #expect(s.habitos == 1, "el hábito viejo no tiene por qué esperar")
        #expect(await m.outbox?.operaciones.map(\.kind) == ["swap"])
        #expect(Set(m.swaps.keys) == [Self.c1, Self.c3], "sin poder preguntar no se toca nada")

        // Con la próxima carga se decide y suben los dos.
        s.lecturaFalla = false
        await m.cargar()
        await m.outbox?.drenar()
        #expect(s.comidas == ["c1", "c3"])
        #expect(Set(m.swaps.keys) == [Self.c1, Self.c3])
    }
}

/// Los reemplazos guardados en el servidor de la prueba (la regla del transporte corre fuera del actor principal).
final class ServidorDeSwaps: @unchecked Sendable {
    private let lock = NSLock()
    private var _filas: [String: JSONValue] = [:]
    private var _habitos = 0
    private var _lecturaFalla = false
    var comidas: [String] { lock.withLock { _filas.keys.sorted() } }
    var habitos: Int { lock.withLock { _habitos } }
    var lecturaFalla: Bool { get { lock.withLock { _lecturaFalla } } set { lock.withLock { _lecturaFalla = newValue } } }
    func guardar(_ comida: String, _ food: JSONValue) { lock.withLock { _filas[comida] = food } }
    func anotarHabito() { lock.withLock { _habitos += 1 } }
    func filas() -> String {
        let filas = lock.withLock { _filas }.sorted { $0.key < $1.key }.map { comida, food in
            JSONValue.objeto(["comida_id": .texto(comida), "opt_idx": .numero(0), "food_idx": .numero(0), "food_data": food])
        }
        return String(decoding: (try? JSONEncoder().encode(JSONValue.lista(filas))) ?? Data("[]".utf8), as: UTF8.self)
    }
}
