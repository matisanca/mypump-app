import Foundation
import Testing
@testable import MyPumpModelos

/// Raíz del repo, a partir de este archivo (apps/ios/MyPumpKit/Tests/MyPumpModelosTests/…).
let raizRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

func fixture(_ cuenta: String, _ rpc: String) throws -> Data {
    try Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/fixtures/\(cuenta)/\(rpc).json"))
}

let cuentas = ["test-nativa-real", "test-nativa-ios"]

@Suite("Respuestas reales grabadas de la base")
struct FixturesTests {
    @Test(arguments: cuentas)
    func rutinaYDieta(cuenta: String) throws {
        let r = try JSONDecoder().decode([RutinaActiva].self, from: fixture(cuenta, "get_rutina_activa"))
        #expect(r.count == 1)
        #expect(!r[0].estructura.dias.isEmpty)
        #expect(r[0].estructura.dias.allSatisfy { $0.id != nil && !$0.bloques.isEmpty })
        let d = try JSONDecoder().decode([DietaActiva].self, from: fixture(cuenta, "get_dieta_activa"))
        #expect(d.count == 1)
        #expect(!d[0].estructura.comidas.isEmpty)
        #expect(d[0].estructura.comidas.allSatisfy { !$0.opciones.isEmpty })
    }

    @Test(arguments: cuentas)
    func todasLasLecturas(cuenta: String) throws {
        let dec = JSONDecoder()
        _ = try dec.decode([ClienteInfo].self, from: fixture(cuenta, "get_cliente_info"))
        let hist = try dec.decode([RegistroHistorico].self, from: fixture(cuenta, "get_historico_por_clave"))
        #expect(!hist.isEmpty)
        #expect(hist.allSatisfy { $0.clave != nil && !$0.registradoEn.isEmpty })
        _ = try dec.decode([Sesion].self, from: fixture(cuenta, "get_sesiones_semana"))
        _ = try dec.decode([Sesion].self, from: fixture(cuenta, "get_sesion_dia"))
        _ = try dec.decode([HabitosDia].self, from: fixture(cuenta, "get_habitos_dia"))
        _ = try dec.decode([Racha].self, from: fixture(cuenta, "get_streak"))
        let adh = try dec.decode([DiaAdherencia].self, from: fixture(cuenta, "get_adherencia_30d"))
        #expect(adh.count == 30)
        _ = try dec.decode([ComidaMarcada].self, from: fixture(cuenta, "get_comidas_marcadas"))
        _ = try dec.decode([ComidaLibre].self, from: fixture(cuenta, "get_comidas_libres"))
        _ = try dec.decode([FoodSwap].self, from: fixture(cuenta, "get_food_swaps"))
        _ = try dec.decode([AlimentoPropio].self, from: fixture(cuenta, "get_custom_foods"))
        _ = try dec.decode([PreferenciasCliente].self, from: fixture(cuenta, "get_cliente_prefs"))
        _ = try dec.decode([Comentario].self, from: fixture(cuenta, "get_comentarios"))
        _ = try dec.decode([MensajeChat].self, from: fixture(cuenta, "get_chat"))
        let salud = try dec.decode([FilaSalud].self, from: fixture(cuenta, "get_salud"))
        #expect(salud.allSatisfy { !$0.fecha.isEmpty && !$0.tipo.isEmpty })
        _ = try dec.decode([Recuperacion].self, from: fixture(cuenta, "get_recuperacion"))
        _ = try dec.decode([Conexion].self, from: fixture(cuenta, "get_conexiones"))
        _ = try dec.decode([CheckinSemana].self, from: fixture(cuenta, "get_checkin_semana"))
        _ = try dec.decode([FotoProgreso].self, from: fixture(cuenta, "get_fotos_progreso"))
        _ = try dec.decode(Bool?.self, from: fixture(cuenta, "get_mostrar_recuperacion"))
    }

    @Test func registrosDeUnaSesion() throws {
        let regs = try JSONDecoder().decode([RegistroSesion].self, from: fixture("test-nativa-real", "get_registros_sesion"))
        #expect(!regs.isEmpty)
        #expect(regs.allSatisfy { !$0.ejercicioId.isEmpty && $0.serie >= 1 })
        let estados = try JSONDecoder().decode([EstadoEjercicio].self, from: fixture("test-nativa-real", "get_ejercicios_estado"))
        #expect(estados.allSatisfy { !$0.ejercicioId.isEmpty })
    }

    @Test func formaRealDelCerebro() throws {
        let r = try JSONDecoder().decode([RutinaActiva].self, from: fixture("test-nativa-real", "get_rutina_activa"))[0]
        let ejercicios = r.estructura.dias.flatMap { $0.bloques.flatMap(\.ejercicios) }
        #expect(ejercicios.allSatisfy { !$0.progresion.isEmpty })
        #expect(ejercicios.contains { $0.imagenes?.eccentric != nil })
        #expect(ejercicios.contains { $0.catalogoSlug != nil })
        #expect(r.estructura.semanaOffset == 0)
        #expect(r.estructura.fase == 1)
        // series null y rir null en cardio: tienen que llegar como nil, no romper.
        #expect(ejercicios.contains { $0.tipo == "cardio" && $0.progresion.first?.series == nil })
    }
}

/// Las estructuras de TODOS los planes activos (leídas de la base, fuera del repo). Si no están, se saltea:
/// en CI o en otra Mac no existen. La decodificación tolerante no puede perder nada válido: se cuenta contra el JSON crudo.
@Suite("Planes reales activos (privado)")
struct PlanesRealesTests {
    static let carpeta = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Developer/nativa-evidencia/privado/estructuras")

    static func crudos(_ archivo: String) -> [Any] {
        guard let d = try? Data(contentsOf: carpeta.appendingPathComponent(archivo)),
              let a = try? JSONSerialization.jsonObject(with: d) as? [Any] else { return [] }
        return a
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: carpeta.path)))
    func rutinasNoPierdenNada() throws {
        for archivo in ["rutinas.json", "rutinas-en-cola.json"] {
            let data = try Data(contentsOf: Self.carpeta.appendingPathComponent(archivo))
            let decodificadas = try JSONDecoder().decode([EstructuraRutina].self, from: data)
            let crudas = Self.crudos(archivo)
            #expect(decodificadas.count == crudas.count)
            for (dec, cruda) in zip(decodificadas, crudas) {
                guard let c = cruda as? [String: Any], let dias = c["dias"] as? [[String: Any]] else { continue }
                #expect(dec.dias.count == dias.count)
                for (d, dc) in zip(dec.dias, dias) {
                    let bloquesObj = (dc["bloques"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
                    #expect(d.bloques.count == bloquesObj.count)
                    for (b, bc) in zip(d.bloques, bloquesObj) {
                        let ejObj = (bc["ejercicios"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
                        #expect(b.ejercicios.count == ejObj.count)
                        for (e, ec) in zip(b.ejercicios, ejObj) {
                            #expect(!e.id.isEmpty && !e.nombre.isEmpty)
                            #expect(e.progresion.count == (ec["progresion"] as? [Any])?.compactMap { $0 as? [String: Any] }.count ?? 0)
                        }
                    }
                }
            }
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: carpeta.path)))
    func dietasNoPierdenNada() throws {
        let data = try Data(contentsOf: Self.carpeta.appendingPathComponent("dietas.json"))
        let decodificadas = try JSONDecoder().decode([EstructuraDieta].self, from: data)
        let crudas = Self.crudos("dietas.json")
        #expect(decodificadas.count == crudas.count)
        for (dec, cruda) in zip(decodificadas, crudas) {
            guard let c = cruda as? [String: Any] else { continue }
            let comidas = (c["comidas"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
            #expect(dec.comidas.count == comidas.count)
            for (com, cc) in zip(dec.comidas, comidas) {
                let ops = (cc["options"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
                #expect(com.opciones.count == ops.count)
                for (op, oc) in zip(com.opciones, ops) {
                    #expect(op.alimentos.count == (oc["foods"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.count)
                    #expect(op.alimentos.allSatisfy { !$0.nombre.isEmpty && $0.kcal != nil })
                }
            }
        }
    }
}

@Suite("Tolerancia a la forma rota")
struct ToleranciaTests {
    @Test func bloqueNullYReemplazaTexto() throws {
        let json = """
        {"dias":[{"id":"d4","n":"4","nombre":"Pierna","reemplaza":"d2","bloques":[null,{"titulo":"B1","ejercicios":[
          {"id":"x-d4-0","nombre":"Sentadilla","series":"4","reps":8,"descanso_segundos":0,"progresion":[null,{"semana":1,"series":null,"reps":"6-8","rir":null,"titulo":"S1"}]},
          "basura"
        ]}]}],"semanas_total":"12"}
        """
        let e = try JSONDecoder().decode(EstructuraRutina.self, from: Data(json.utf8))
        #expect(e.semanasTotal == 12)
        #expect(e.dias[0].n == 4)
        #expect(e.dias[0].reemplaza == ["d2"])
        #expect(e.dias[0].bloques.count == 1)
        let x = e.dias[0].bloques[0].ejercicios
        #expect(x.count == 1)
        #expect(x[0].series == 4 && x[0].reps == "8" && x[0].descansoSegundos == 0)
        #expect(x[0].progresion.count == 1 && x[0].progresion[0].series == nil)
    }

    @Test func foodDataSeConservaEntero() throws {
        let json = #"[{"comida_id":"desayuno","opt_idx":1,"food_idx":2,"food_data":{"name":"Ricota","qty":150,"_orig":{"name":"Queso","qty":60,"unit":"g"},"_dev":0.03}}]"#
        let s = try JSONDecoder().decode([FoodSwap].self, from: Data(json.utf8))[0]
        #expect(s.foodData["_orig"]?["name"]?.comoTexto == "Queso")
        let vuelta = try JSONEncoder().encode(s.foodData)
        #expect(try JSONDecoder().decode(JSONValue.self, from: vuelta) == s.foodData)
    }
}
