import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// DIE-01: el formato B (`tipos_dia`, docs/SCHEMA_DIETA.md) con su selector de tipo de día, guardado en
/// `mypump_tipo_dia` y global como en la web. La normalización de los dos formatos ya la cubren los vectores de la web
/// (NormalizarDietaTests); acá, lo que hace el modelo con el tipo elegido.
@Suite("Dieta: el tipo de día (DIE-01)", .serialized)
@MainActor
struct DietaTipoDeDiaTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("tipo-dia-\(UUID().uuidString)")

    static func comida(_ id: String, _ nombre: String, _ kcal: Int) -> String {
        #"{"id":"\#(id)","name":"\#(nombre)","options":[{"name":"A","foods":[{"name":"Arroz","qty":100,"unit":"g","kcal":\#(kcal),"prot":10,"carb":20,"fat":5}]}]}"#
    }

    static let dietaB = #"[{"id":"11111111-1111-4111-8111-111111111111","version":1,"estructura":{"tipos_dia":["#
        + #"{"id":"entreno","nombre":"Día de entrenamiento","macros_target":{"kcal":3200,"prot":220,"carb":380,"fat":90},"comidas":["#
        + comida("e1", "Desayuno", 500) + "," + comida("e2", "Almuerzo", 800) + "]},"
        + #"{"id":"descanso","nombre":"Día de descanso","macros_target":{"kcal":2800,"prot":220,"carb":280,"fat":90},"comidas":["#
        + comida("d1", "Desayuno liviano", 300) + "]}]}}]"

    static let dietaA = #"[{"id":"22222222-2222-4222-8222-222222222222","version":1,"estructura":{"macros_target":{"kcal":2500,"prot":180,"carb":250,"fat":80},"comidas":["#
        + comida("a1", "Desayuno", 400) + "]}}]"

    func modelo(dieta: String) -> ModeloApp {
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, dieta)
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
    }

    @Test func elTipoElegidoCambiaComidasYObjetivo_yQuedaGuardado() async {
        let antes = UserDefaults.standard.string(forKey: "mypump_tipo_dia")
        UserDefaults.standard.removeObject(forKey: "mypump_tipo_dia")
        defer { UserDefaults.standard.set(antes, forKey: "mypump_tipo_dia") }
        let m = modelo(dieta: Self.dietaB)
        await m.cargar()
        #expect(m.comidasDelDia.map(\.id) == ["e1", "e2"], "sin elegir, el primero")
        #expect(m.objetivo.kcal == 3200)
        m.tipoDia = "descanso"
        #expect(m.comidasDelDia.map(\.id) == ["d1"])
        #expect(m.objetivo.kcal == 2800)
        #expect(UserDefaults.standard.string(forKey: "mypump_tipo_dia") == "descanso", "global, como la web")
        // Otro arranque lo recuerda.
        let otro = modelo(dieta: Self.dietaB)
        await otro.cargar()
        #expect(otro.comidasDelDia.map(\.id) == ["d1"])
        // Un tipo que este plan no tiene: el primero.
        otro.tipoDia = "refeed"
        #expect(otro.comidasDelDia.map(\.id) == ["e1", "e2"] && otro.objetivo.kcal == 3200)
    }

    @Test func enElFormatoA_elTipoNoCambiaNada() async {
        let antes = UserDefaults.standard.string(forKey: "mypump_tipo_dia")
        defer { UserDefaults.standard.set(antes, forKey: "mypump_tipo_dia") }
        let m = modelo(dieta: Self.dietaA)
        await m.cargar()
        m.tipoDia = "descanso"
        #expect(m.comidasDelDia.map(\.id) == ["a1"])
        #expect(m.objetivo.kcal == 2500)
    }
}
