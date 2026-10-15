import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Sospecha de la revisión del 15-oct, confirmada: `JSONEncoder` tira con NaN o infinito y `Outbox.guardar` se lo traga.
/// Con un solo número así en una op, la cola dejaba de guardarse para siempre, en silencio: lo que se encolaba después
/// vivía solo en memoria (y se perdía al cerrar la app), la op no se podía mandar (la RPC tampoco arma el JSON) y al
/// abandonarla pasaba a fallidos, que también se guardan. JSON.stringify de la web lo escribe como null: acá también.
@Suite("La cola con un número no finito")
struct OutboxNoFinitosTests {
    let archivo = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-nofinitos-\(UUID().uuidString)/outbox.json")

    /// Un reemplazo con números que salieron de una cuenta rota (una porción de 0 g por unidad da infinito).
    static let swapRoto: JSONValue = .objeto([
        "dietaId": .texto("d1"), "comidaId": .texto("c1"), "optIdx": .numero(0), "foodIdx": .numero(0),
        "food": .objeto(["name": .texto("Agua"), "qty": .numero(.infinity), "kcal": .numero(0), "_dev": .numero(.nan)]),
    ])

    @Test func loQueSeEncolaDespuesSigueGuardandoseEnDisco() async throws {
        let o = Outbox(archivo: archivo, reintentoAutomatico: false) { _ in .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin red"))) }
        await o.encolar("swap", Self.swapRoto, dedupeKey: "swap_d1_c1_0_0")
        await o.encolar("habito", .objeto(["fecha": .texto("2026-10-15"), "campo": .texto("vasos_agua"), "valor": .texto("3")]),
                        dedupeKey: "habito|2026-10-15|vasos_agua")
        // Otro arranque: lo que quedó en disco.
        let otra = Outbox(archivo: archivo, reintentoAutomatico: false) { _ in .respuesta(.success(.texto("ok"))) }
        #expect(await otra.pendientes == 2, "la cola dejó de guardarse")
        let food = await otra.operaciones.first?.payload["food"]
        #expect(food?["qty"] == .null && food?["_dev"] == .null && food?["name"]?.comoTexto == "Agua", "como JSON.stringify: null")
    }

    /// El mismo reemplazo desde Dieta: el archivo de reemplazos de la dieta también se sigue guardando.
    @MainActor @Test func unReemplazoConNumerosRotosQuedaGuardado() async throws {
        let raiz = archivo.deletingLastPathComponent()
        let dieta = #"[{"id":"dieta-1","version":1,"estructura":{"macros_target":{"kcal":2500,"prot":180,"carb":250,"fat":80},"comidas":["#
            + #"{"id":"c1","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":80,"unit":"g","kcal":300,"prot":10,"carb":50,"fat":6}]}]}]}}]"#
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, dieta)
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
        await m.cargar()
        let avena = try #require(m.comidasDelDia.first?.opciones.first?.alimentos.first)
        await m.sustituir(avena, por: Self.swapRoto["food"]!, comidaId: "c1", opt: 0, idx: 0)
        let enDisco = Disco(raiz: raiz, token: "AAAAAAAAAAAAAAAAAAAA").leer([String: SwapLocal].self, "swaps_dieta-1.json") ?? [:]
        #expect(enDisco.count == 1, "el archivo de reemplazos no se guardó")
        #expect(enDisco.values.first?.current["qty"] == .null)
    }

    @Test func laOpSeMandaConNullYNoTerminaEnFallidos() async throws {
        let t = TransporteProgramado { fn, cuerpo in
            fn == "mypump_save_food_swap" ? (200, #"[{"ok":true}]"#) : (200, "[]")
        }
        let esc = Escrituras(cliente: ClienteRPC(config: .produccion, transporte: t), token: "AAAAAAAAAAAAAAAAAAAA")
        let o = Outbox(archivo: archivo, reintentoAutomatico: false) { op in await esc.ejecutar(op) }
        await o.encolar("swap", Self.swapRoto, dedupeKey: "swap_d1_c1_0_0")
        for _ in 0..<3 { await o.drenar() }
        #expect(t.llamadas.contains("mypump_save_food_swap"), "la RPC no pudo armar el JSON")
        #expect(await o.pendientes == 0)
        #expect(await o.fallidos.count == 0)
    }
}
