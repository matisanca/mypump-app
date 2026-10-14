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

/// GEN-05: el aviso "a tu plan le falta información", como la web (`avisarPlanIncompleto`): lo de la rutina primero y,
/// de una dieta que no sirve, solo "está incompleta". A propósito, a quien tiene rutina y no dieta no se le avisa.
@Suite("El aviso de plan incompleto (GEN-05)", .serialized)
@MainActor
struct AvisoPlanIncompletoTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("aviso-plan-\(UUID().uuidString)")

    static let rutinaSinSemanas = #"[{"id":"rut-1","version":1,"semana_actual":1,"estructura":{"dias":[{"id":"d1","nombre":"Día 1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Sentadilla","progresion":[{"semana":1,"series":3,"reps":"8"}]}]}]},{"id":"d2","nombre":"Día 2","bloques":[]}]}}]"#
    static let dietaSinObjetivo = #"[{"id":"33333333-3333-4333-8333-333333333333","version":1,"estructura":{"comidas":["#
        + DietaTipoDeDiaTests.comida("c1", "Desayuno", 400) + "]}}]"
    static let rutinaCompleta = #"[{"id":"rut-2","version":1,"semana_actual":1,"estructura":{"semanas_total":12,"dias":[{"id":"d1","nombre":"Día 1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Sentadilla","progresion":[{"semana":1,"series":3,"reps":"8"}]}]}]}]}}]"#
    static let dietaInservible = #"[{"id":"44444444-4444-4444-8444-444444444444","version":1,"estructura":{"comidas":[{"id":"c1","name":"Desayuno","options":[]}]}}]"#

    func modelo(rutina: String, dieta: String) -> ModeloApp {
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, rutina)
            case "mypump_get_dieta_activa": return (200, dieta)
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
    }

    @Test func primeroLoDeLaRutina_yDespuesLoDeLaDieta() async throws {
        let m = modelo(rutina: Self.rutinaSinSemanas, dieta: Self.dietaSinObjetivo)
        await m.cargar()
        let aviso = try #require(m.avisoPlanIncompleto)
        #expect(aviso.texto == "A tu plan le falta información y algunas cosas pueden verse raras. Avisale a Mati y lo republica.")
        #expect(aviso.detalle == "Día 2: sin ejercicios. · El plan no dice cuántas semanas dura; se asume 12. · El plan no traía el objetivo de calorías; se calculó con la opción A.",
                "\(aviso.detalle)")
    }

    @Test func unaDietaQueNoSirve_diceQueEstaIncompleta() async throws {
        let m = modelo(rutina: "[]", dieta: Self.dietaInservible)
        await m.cargar()
        #expect(m.avisoPlanIncompleto?.detalle == "Tu dieta está publicada pero incompleta.")
    }

    @Test func conRutinaYSinDieta_noHayAviso() async {
        let m = modelo(rutina: Self.rutinaCompleta, dieta: "[]")
        await m.cargar()
        #expect(m.avisoPlanIncompleto == nil, "a quien solo tiene rutina no se le deja un aviso de error fijo")
    }
}
