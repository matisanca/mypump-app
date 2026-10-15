import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 10: `hidratarDieta` no volvía a mirar si la cuenta seguía siendo la misma después de
/// esperar al servidor. Si en ese momento entraba otro link (Mati abriendo la cuenta de un cliente), las preferencias, los
/// alimentos propios y los reemplazos de A quedaban en B: en memoria, en su carpeta y en su cola.
@Suite("Hidratar la dieta con otra cuenta en el medio", .serialized)
@MainActor
struct HidratarOtraCuentaTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("hidratar-cuenta-\(UUID().uuidString)")
    nonisolated static let tokA = "AAAAAAAAAAAAAAAAAAAA"
    nonisolated static let tokB = "BBBBBBBBBBBBBBBBBBBB"

    nonisolated static func dieta(_ id: String, comida: String) -> String {
        #"[{"id":"\#(id)","version":1,"estructura":{"macros_target":{"kcal":2500,"prot":180,"carb":250,"fat":80},"comidas":["#
            + #"{"id":"\#(comida)","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":80,"unit":"g","kcal":300,"prot":10,"carb":50,"fat":6}]}]}]}}]"#
    }

    @Test func loDeAQueLlegaTardeNoQuedaEnB() async throws {
        let señal = BanderaRegresion()
        let t = TransporteProgramado { fn, cuerpo in
            let deA = cuerpo["p_token"]?.comoTexto == Self.tokA
            switch fn {
            case "mypump_get_cliente_info":
                return (200, #"[{"cliente_id":"\#(deA ? "c-a" : "c-b")","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, deA ? Self.dieta("dieta-a", comida: "a1") : Self.dieta("dieta-b", comida: "b1"))
            case "mypump_get_cliente_prefs":
                guard deA else { return (200, #"[{"excluir":[],"idioma":"es"}]"#) }
                // Las de A tardan: mientras tanto se abre el link de B.
                await señal.prender()
                try await Task.sleep(for: .milliseconds(300))
                return (200, #"[{"excluir":["cerdo"],"idioma":"es"}]"#)
            case "mypump_get_custom_foods":
                return (200, deA ? #"[{"name":"Pan de A","kcal":250,"prot":8,"carb":48,"fat":3,"unit":"g"}]"# : "[]")
            case "mypump_get_food_swaps":
                return (200, deA ? #"[{"comida_id":"a1","opt_idx":0,"food_idx":0,"food_data":{"name":"Ricota","qty":100,"unit":"g","kcal":138}}]"# : "[]")
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.tokA), raizDisco: raiz)
        async let cargaA: Void = m.cargar()
        for _ in 0..<100 where !(await señal.valor) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await señal.valor)
        #expect(await m.entrar(con: "https://app.mypumpteam.com/?t=\(Self.tokB)"))
        await cargaA

        #expect(m.token == Self.tokB && m.dieta?.id == "dieta-b")
        #expect(m.excluir.isEmpty, "quedaron las preferencias de A")
        #expect(m.alimentosPropios.isEmpty, "quedaron los alimentos propios de A")
        #expect(!m.swaps.keys.contains { $0.contains("dieta-a") }, "quedaron los reemplazos de A")
        let discoB = Disco(raiz: raiz, token: Self.tokB)
        let enDiscoB = discoB.leer([String: SwapLocal].self, "swaps_dieta-b.json") ?? [:]
        #expect(!enDiscoB.keys.contains { $0.contains("dieta-a") }, "los reemplazos de A se escribieron en la carpeta de B")
        let colaB = await m.outbox?.operaciones ?? []
        #expect(!colaB.contains { $0.payload["dietaId"]?.comoTexto == "dieta-a" }, "la cola de B tiene escrituras de A")
    }
}
