import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// «Pump del día» con el modelo: la palanca `metas_pasos`, la meta de la dieta, los pasos de Salud y la celebración
/// guardada por cuenta (una vez por día aunque se cierre la app).
@MainActor @Suite(.serialized)
struct MetasModeloTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("metas-\(UUID().uuidString)")
    static let token = "MMMMMMMMMMMMMMMMMMMM"

    private func modelo(palanca: String, dieta: String, pasosHoy: Int) -> ModeloApp {
        let hoy = FechaLocal.hoy()
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, #"[{"id":"d1","version":1,"estructura":\#(dieta)}]"#)
            case "mypump_get_app_config": return (200, palanca)
            case "mypump_get_salud":
                return (200, #"[{"fecha":"\#(hoy)","tipo":"pasos","valor":\#(pasosHoy),"fuente":"apple_health"}]"#)
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
    }

    private static let dietaConMetas = #"{"macros_target":{"kcal":2000},"comidas":[{"id":"d","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7}]}]}],"meta_pasos_dia":10000,"ritmo_peso_kg_semana":-0.5}"#

    private func cargar(_ m: ModeloApp) async {
        await m.cargar()
        await m.salud?.cargar()
    }

    @Test func conLaPalancaApagadaNoHayNada() async {
        defer { PalancaRemota.deFabrica.recordar() }
        let m = modelo(palanca: #"{"metas_pasos":false}"#, dieta: Self.dietaConMetas, pasosHoy: 12000)
        await cargar(m)
        #expect(m.metas == nil)
        #expect(m.pumpDelDia() == nil)
        let sinClave = modelo(palanca: #"{}"#, dieta: Self.dietaConMetas, pasosHoy: 12000)
        await cargar(sinClave)
        #expect(sinClave.metas == nil, "sin la clave, apagada")
    }

    @Test func sinMetaEnElPlanNoSeInventa() async {
        defer { PalancaRemota.deFabrica.recordar() }
        let m = modelo(palanca: #"{"metas_pasos":true}"#, dieta: #"{"macros_target":{"kcal":2000},"comidas":[{"id":"d","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7}]}]}]}"#, pasosHoy: 12000)
        await cargar(m)
        #expect(m.palanca.metasPasos)
        #expect(m.dieta != nil)
        #expect(m.metas == nil)
        #expect(m.pumpDelDia() == nil)
    }

    @Test func celebraUnaVezYSeAcuerdaAlReabrir() async {
        defer { PalancaRemota.deFabrica.recordar() }
        let m = modelo(palanca: #"{"metas_pasos":true}"#, dieta: Self.dietaConMetas, pasosHoy: 10400)
        await cargar(m)
        #expect(m.metas?.metaPasos == 10000)
        #expect(m.metas?.ritmoKgSemana == -0.5)
        guard let e = m.pumpDelDia() else { Issue.record("sin Pump del día"); return }
        #expect(e.vista.cumplido)
        #expect(e.vista.pasosHoy == 10400)
        #expect(m.debeCelebrarPump(e.vista))
        m.marcarPumpCelebrado()
        #expect(!m.debeCelebrarPump(e.vista))
        // La app se cierra y se vuelve a abrir con la misma cuenta: lo celebrado sigue en su disco.
        let otra = modelo(palanca: #"{"metas_pasos":true}"#, dieta: Self.dietaConMetas, pasosHoy: 10400)
        await cargar(otra)
        guard let e2 = otra.pumpDelDia() else { Issue.record("sin Pump del día"); return }
        #expect(!otra.debeCelebrarPump(e2.vista))
        // Salir borra lo de la cuenta en memoria.
        otra.salir()
        #expect(otra.registroMetas.celebrados.isEmpty)
    }
}
