import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// PRO-02: Progreso agrupa por el ejercicio que se hace de verdad, con el sustituto si hay (`getEffectiveEx` en el
/// `loadProgressAndRender` de la web, cliente.html:6085-6101). La pantalla pasaba solo la rutina y agrupaba por el
/// nombre del plan: un press sustituido salía con el nombre y el historial del original (lo encontró la auditoría de
/// Android del 14-oct).
@Suite("Progreso: por el ejercicio efectivo (PRO-02)", .serialized)
@MainActor
struct ProgresoEfectivoTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("progreso-efectivo-\(UUID().uuidString)")

    @Test func unEjercicioSustituidoSeAgrupaPorElSustituto() async throws {
        let inclinado = ClaveEjercicio.de("Press inclinado con mancuernas")
        let banca = ClaveEjercicio.de("Press banca")
        let sentadilla = ClaveEjercicio.de("Sentadilla")
        let pedidas = Pedidas()
        let t = TransporteProgramado { fn, cuerpo in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, Datos.rutina)
            case "mypump_get_exercise_swaps": return (200, Datos.swaps)
            case "mypump_get_historico_por_clave":
                pedidas.guardar(cuerpo["p_claves"])
                return (200, "[" + [Datos.fila(inclinado, "Press inclinado con mancuernas", kg: 30),
                                    Datos.fila(banca, "Press banca", kg: 80),
                                    Datos.fila(sentadilla, "Sentadilla", kg: 100)].joined(separator: ",") + "]")
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"),
                          raizDisco: raiz)
        await m.cargar()
        let entreno = try #require(m.entreno)
        await entreno.cargar()
        #expect(entreno.efectivo(try #require(m.rutina?.estructura.dias.first?.bloques.first?.ejercicios.first)).ejercicio.nombre
                == "Press inclinado con mancuernas", "la sustitución del servidor tiene que estar aplicada")

        await m.cargarProgreso()
        let tarjetas = try #require(m.progreso?.tarjetas)
        #expect(tarjetas.map(\.nombre) == ["Press inclinado con mancuernas", "Sentadilla"],
                "el sustituto y el original del día 2 son una sola tarjeta; el press banca no aparece")
        #expect(tarjetas.first?.dias == "EMPUJE · TORSO")
        #expect(pedidas.claves == [inclinado, sentadilla], "pide la clave del sustituto, no la del plan")
    }

    @Test func sinSustitucionesQuedaComoElPlan() async throws {
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, Datos.rutina)
            case "mypump_get_exercise_swaps": return (200, #"{"vivas":{},"borradas":{},"ahora":2000}"#)
            case "mypump_get_historico_por_clave":
                return (200, "[" + Datos.fila(ClaveEjercicio.de("Press banca"), "Press banca", kg: 80) + "]")
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"),
                          raizDisco: raiz)
        await m.cargar()
        await m.entreno?.cargar()
        await m.cargarProgreso()
        #expect(m.progreso?.tarjetas.map(\.nombre) == ["Press banca"])
    }
}

/// Las claves que pidió Progreso (la regla del transporte corre fuera del actor principal).
private final class Pedidas: @unchecked Sendable {
    private let lock = NSLock()
    private var _claves: [String] = []
    var claves: [String] { lock.withLock { _claves } }
    func guardar(_ v: JSONValue?) {
        guard case .lista(let l)? = v else { return }
        lock.withLock { _claves = l.compactMap(\.comoTexto) }
    }
}

/// La rutina, las sustituciones y el historial de las pruebas (fuera del actor principal: los usa el transporte).
private enum Datos {
    static func ejercicio(_ id: String, _ nombre: String) -> String {
        #"{"id":"\#(id)","tipo":"principal","nombre":"\#(nombre)","progresion":[{"semana":1,"series":3,"reps":"8","rir":2}]}"#
    }

    /// Dos días: el press banca del día 1 está sustituido (fijado) por el mismo press inclinado que tiene el día 2.
    static let rutina = #"[{"id":"rut-progreso","version":1,"semana_actual":1,"estructura":{"dias":["#
        + #"{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":["#
        + ejercicio("press-d1-0", "Press banca") + "," + ejercicio("sentadilla-d1-1", "Sentadilla") + "]}]},"
        + #"{"n":2,"id":"d2","nombre":"TORSO","bloques":[{"titulo":"A","ejercicios":["#
        + ejercicio("inclinado-d2-0", "Press inclinado con mancuernas") + "]}]}]}}]"

    static let swaps = #"{"vivas":{"press-d1-0":{"current":{"slug":null,"nombre":"Press inclinado con mancuernas","#
        + #""equipment":null,"images":null},"fijado":true,"semana":1,"_ts":1000}},"borradas":{},"ahora":2000}"#

    static func fila(_ clave: String, _ nombre: String, kg: Double) -> String {
        #"{"clave":"\#(clave)","registrado_en":"2026-10-10T12:00:00+00:00","peso_kg":\#(kg),"reps_realizadas":8,"#
            + #""rir_real":2,"serie_numero":1,"notas":null,"ejercicio_nombre":"\#(nombre)"}"#
    }
}
