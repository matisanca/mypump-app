import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// Alimentos agregados a una comida del plan (2.0.3, D1) y la hoja de cantidad (D2): las medidas caseras, las macros por
/// la cantidad, cómo cuentan en el día (lo propio que se compensa en la siguiente, D3), en lo consumido y en los tildes.
/// Los casos también salen como vectores (`apps/shared/vectores/agregados_comida.json`) que Android tiene que dar igual.
/// Para regenerarlos: `GENERAR_VECTORES_AGREGADOS=1 swift test --filter AgregadosComida`.
@Suite("AgregadosComida")
struct AgregadosComidaTests {
    typealias Cand = AgregadosComida.Candidato
    typealias M = AgregadosComida.Medida

    static func cand(_ n: String, _ k: Double, _ p: Double, _ c: Double, _ g: Double, unidad: String? = nil, gu: Double? = nil,
                     origen: AlimentoAgregado.Origen = .base) -> Cand {
        Cand(nombre: n, por100: MacrosPor100(kcal: k, p: p, c: c, g: g), unidad: unidad, gramosPorUnidad: gu, origen: origen)
    }

    // Los del pedido (food-db) y algunos más para cada rama de la medida casera.
    static let zapallo = cand("Zapallo / Calabaza", 26, 1, 6.5, 0.1)
    static let huevo = cand("Huevo entero", 143, 12.6, 0.7, 9.5, unidad: "unidad", gu: 60)
    static let clara = cand("Clara de huevo", 52, 10.9, 0.7, 0.2, unidad: "unidad", gu: 33)
    static let brocoli = cand("Brócoli", 34, 2.8, 6.6, 0.4)
    static let polloCrudo = cand("Pechuga de pollo (cruda)", 120, 22.5, 0, 2.6)
    static let polloCocido = cand("Pechuga de pollo (cocida)", 165, 31, 0, 3.6)
    static let arrozCocido = cand("Arroz blanco cocido", 130, 2.7, 28.6, 0.3)
    static let arrozCrudo = cand("Arroz blanco crudo", 365, 7.1, 80, 0.7)
    static let aceite = cand("Aceite de oliva", 884, 0, 0, 100)
    static let pan = cand("Pan de molde integral", 247, 10.7, 41, 3.5, unidad: "rebanada", gu: 30)
    static let leche = cand("Leche de almendras (sin azúcar)", 17, 0.6, 0.6, 1.4)
    static let lechuga = cand("Lechuga", 15, 1.4, 2.9, 0.2)
    static let pure = cand("Puré de papa", 88, 2, 15, 2.5, origen: .propio)
    static let raro = cand("Kombucha de jengibre", 20, 0, 5, 0)
    static let candidatos = [zapallo, huevo, clara, brocoli, polloCrudo, polloCocido, arrozCocido, arrozCrudo, aceite, pan,
                             leche, lechuga, pure, raro]

    /// Un agregado con ts fijo (los vectores no dependen del reloj).
    static func ag(_ c: Cand, _ q: Double, _ m: M? = nil, ts: Int64 = 1_730_000_000_000) -> AlimentoAgregado {
        AgregadosComida.agregado(c, cantidad: q, medida: m ?? .gramo, ts: ts)
    }

    @Test func lasMedidasCaseras() {
        #expect(AgregadosComida.medidas(Self.huevo) == [.gramo, M(nombre: "unidad", gramos: 60)])
        #expect(AgregadosComida.medidas(Self.pan) == [.gramo, M(nombre: "rebanada", gramos: 30)])
        #expect(AgregadosComida.medidas(Self.zapallo) == [.gramo, M(nombre: "puño", gramos: 90)])
        #expect(AgregadosComida.medidas(Self.polloCocido) == [.gramo, M(nombre: "palma", gramos: 100)])
        #expect(AgregadosComida.medidas(Self.polloCrudo) == [.gramo, M(nombre: "palma", gramos: 133)])
        #expect(AgregadosComida.medidas(Self.arrozCocido)[1] == M(nombre: "taza", gramos: 175))
        #expect(AgregadosComida.medidas(Self.leche)[1] == M(nombre: "vaso", gramos: 200))
        #expect(AgregadosComida.medidas(Self.pure)[1] == M(nombre: "taza", gramos: 175))
        // Sin medida casera (o «libre»): solo gramos.
        #expect(AgregadosComida.medidas(Self.lechuga) == [.gramo] && AgregadosComida.medidas(Self.raro) == [.gramo])
        // Abre con 1 huevo (la medida de la base) o con 100 g.
        #expect(AgregadosComida.inicial(Self.huevo) == (1, M(nombre: "unidad", gramos: 60)))
        #expect(AgregadosComida.inicial(Self.zapallo).cantidad == 100 && AgregadosComida.inicial(Self.zapallo).medida == .gramo)
    }

    @Test func elPedido() {
        // 180 g de pollo, 150 g de brócoli y 80 g de zapallo; 5 claras y 1 huevo.
        let z = Self.ag(Self.zapallo, 80)
        #expect(z.gramos == 80 && z.kcal == 21 && z.p == 0.8 && z.c == 5.2 && z.g == 0.1)
        let h = Self.ag(Self.huevo, 1, M(nombre: "unidad", gramos: 60))
        #expect(h.gramos == 60 && h.kcal == 86 && h.unidad == "unidad" && h.gramosUnidad == 60)
        let cl = Self.ag(Self.clara, 5, M(nombre: "unidad", gramos: 33))
        #expect(cl.gramos == 165 && cl.kcal == 86 && cl.p == 18)
        // La cantidad se acota a porciones servibles.
        #expect(Self.ag(Self.zapallo, 0).cantidad == 1 && Self.ag(Self.zapallo, 99999).cantidad == 2000)
        #expect(Self.ag(Self.huevo, 1.3, M(nombre: "unidad", gramos: 60)).cantidad == 1.5)
    }

    @Test func losPasos() {
        let g = M.gramo, u = M(nombre: "unidad", gramos: 60)
        #expect(AgregadosComida.subir(37, g) == 40 && AgregadosComida.bajar(37, g) == 35)
        #expect(AgregadosComida.subir(95, g) == 100 && AgregadosComida.subir(100, g) == 110 && AgregadosComida.bajar(110, g) == 100)
        #expect(AgregadosComida.bajar(100, g) == 95 && AgregadosComida.bajar(5, g) == 1 && AgregadosComida.subir(2000, g) == 2000)
        #expect(AgregadosComida.subir(1, u) == 1.5 && AgregadosComida.bajar(0.5, u) == 0.5 && AgregadosComida.subir(50, u) == 50)
    }

    @Test func laBusquedaEnLaBase() throws {
        let base = try BaseAlimentos(json: Data(contentsOf: archivoBaseAlimentos))
            .conPropios([AlimentoPropio(nombre: "Puré de zapallo casero", kcal: 45, prot: 1, carb: 9, fat: 1, unidad: "g",
                                        gramosPorUnidad: nil, categoria: nil)])
        let zapallo = AgregadosComida.buscar(base, "Zapallo")
        #expect(zapallo.first?.nombre == "Zapallo / Calabaza" && zapallo.contains { $0.nombre == "Puré de zapallo casero" && $0.esPropio })
        #expect(AgregadosComida.buscar(base, "pure  ZAPALLO").map(\.nombre) == ["Puré de zapallo casero"])
        let huevo = AgregadosComida.buscar(base, "huevo").map(\.nombre)
        #expect(huevo.first == "Huevo entero" && huevo.contains("Clara de huevo"))
        #expect(AgregadosComida.buscar(base, "brocoli").first?.nombre == "Brócoli")
        #expect(AgregadosComida.buscar(base, "  ").isEmpty && AgregadosComida.buscar(base, "a", limite: 5).count == 5)
        // Un propio de la base, con su medida: el candidato lo marca como propio.
        #expect(AgregadosComida.Candidato(zapallo.first { $0.esPropio }!).origen == .propio)
    }

    // MARK: - El día

    static let pollo = Alimento(nombre: "Pollo", qty: 200, unidad: "g", kcal: 330, prot: 62, carb: 0, fat: 7)
    static let arroz = Alimento(nombre: "Arroz", qty: 150, unidad: "g", kcal: 195, prot: 4, carb: 42, fat: 0.5)
    static let claras = Alimento(nombre: "Claras", qty: 5, unidad: "unidad", kcal: 86, prot: 18, carb: 1.2, fat: 0.3)
    static let avena = Alimento(nombre: "Avena", qty: 60, unidad: "g", kcal: 233, prot: 10, carb: 40, fat: 4)
    static let yogur = Alimento(nombre: "Yogur", qty: 200, unidad: "g", kcal: 120, prot: 10, carb: 14, fat: 3)
    typealias C = AjustePorciones.ComidaDelDia
    static let desayuno = C(id: "desayuno", nombre: "Desayuno", opcion: 0, alimentos: [claras, avena])
    static let almuerzo = C(id: "almuerzo", nombre: "Almuerzo", opcion: 0, alimentos: [pollo, arroz])
    static let merienda = C(id: "merienda", nombre: "Merienda", opcion: 0, alimentos: [yogur])

    static var casosDia: [(String, [C], [String: AjusteComida])] { [
        ("un huevo en el desayuno: suma y se compensa en el almuerzo",
         [desayuno, almuerzo], ["desayuno": AjusteComida(agregados: [ag(huevo, 1, M(nombre: "unidad", gramos: 60))])]),
        ("un huevo sin compensar: el día sube",
         [desayuno, almuerzo], ["desayuno": AjusteComida(compensar: false, agregados: [ag(huevo, 1, M(nombre: "unidad", gramos: 60))])]),
        ("zapallo en el almuerzo, que es la última: queda sin compensar",
         [desayuno, almuerzo], ["almuerzo": AjusteComida(agregados: [ag(zapallo, 80)])]),
        ("agregados en una comida que hoy no se come: no cuentan",
         [desayuno, almuerzo, merienda], ["almuerzo": AjusteComida(omitida: true, agregados: [ag(zapallo, 80), ag(brocoli, 150)])]),
        ("agregado más gramos a mano y kcal sumadas",
         [desayuno, almuerzo, merienda],
         ["almuerzo": AjusteComida(deltaKcal: 100, cantidades: ["0": 180], agregados: [ag(brocoli, 150), ag(zapallo, 80, ts: 1_730_000_000_001)])]),
        ("la que recibe tiene un agregado: lo agregado no se achica",
         [desayuno, almuerzo, merienda],
         ["desayuno": AjusteComida(deltaKcal: 150), "almuerzo": AjusteComida(compensar: false, agregados: [ag(aceite, 10)])]),
        ("cambió de opción: los agregados siguen (no van por posición)",
         [C(id: "desayuno", nombre: "Desayuno", opcion: 1, alimentos: [yogur]), almuerzo],
         ["desayuno": AjusteComida(opcion: 1, agregados: [ag(huevo, 2, M(nombre: "unidad", gramos: 60))])]),
    ] }

    static func salidaDia(_ comidas: [C], _ ajustes: [String: AjusteComida]) -> [String: Any] {
        let d = AjustePorciones.dia(comidas, ajustes: ajustes)
        var r: [String: Any] = [:]
        for c in comidas {
            let x = d[c.id]!
            r[c.id] = ["qty": x.alimentos.map { $0.qty as Any? ?? NSNull() }, "kcal": x.alimentos.map { $0.kcal ?? 0 },
                       "agregados": x.agregados.map { ["kcal": $0.kcal ?? 0, "prot": $0.prot ?? 0, "carb": $0.carb ?? 0, "fat": $0.fat ?? 0] },
                       "kcalPlan": x.kcalPlan, "kcalDia": x.kcal, "compensacion": x.compensacion, "noAbsorbido": x.noAbsorbido,
                       "propio": x.propio, "ajustada": x.ajustada]
        }
        r["_sinCompensar"] = AjustePorciones.sinCompensar(comidas, d)
        return r
    }

    @Test func elDia() {
        let r = Self.casosDia.map { AjustePorciones.dia($0.1, ajustes: $0.2) }
        // +86 kcal del huevo en el desayuno; el almuerzo baja lo que puede.
        #expect(r[0]["desayuno"]!.kcal == 319 + 86 && r[0]["desayuno"]!.propio == 86 && r[0]["almuerzo"]!.kcal < 525)
        #expect(r[1]["almuerzo"]!.kcal == 525 && r[1]["desayuno"]!.kcal == 405)
        #expect(r[2]["almuerzo"]!.kcal == 525 + 21 && AjustePorciones.sinCompensar(Self.casosDia[2].1, r[2]) == 0)
        // No la come: ni los agregados; sus kcal (sin agregados) pasan a la merienda.
        #expect(r[3]["almuerzo"]!.kcal == 0 && r[3]["almuerzo"]!.agregados.isEmpty && r[3]["merienda"]!.kcal > 120)
        // Los agregados no se escalan con lo que llega.
        #expect(r[5]["almuerzo"]!.agregados.first?.kcal == 88 && r[5]["almuerzo"]!.ajustada)
        #expect(r[6]["desayuno"]!.kcal == 120 + 172)
    }

    @Test func efectoDeUnAgregadoEnLasSiguientes() {
        // D3: lo que explica la hoja al agregar (el mismo `efecto` de «Ajustar esta comida»).
        let (comidas, ajustes) = (Self.casosDia[0].1, Self.casosDia[0].2)
        let e = AjustePorciones.efecto(comidas, ajustes: ajustes, de: "desayuno")
        #expect(e.cambios.count == 1 && e.cambios[0].id == "almuerzo" && e.cambios[0].kcal < 0)
    }

    // MARK: - Lo consumido y los tildes

    static func f(_ n: String, _ kcal: Double, _ p: Double, _ c: Double, _ g: Double, _ qty: Double, _ u: String = "g") -> [String: Any] {
        ["name": n, "qty": qty, "unit": u, "kcal": kcal, "prot": p, "carb": c, "fat": g]
    }
    static var comidas: [[String: Any]] { [
        ["id": "c1", "name": "Desayuno", "options": [["name": "A", "foods": [f("Claras", 86, 18, 1.2, 0.3, 5, "unidad"), f("Avena", 233, 10, 40, 4, 60)]],
                                                       ["name": "B", "foods": [f("Yogur", 120, 10, 14, 3, 200)]]]],
        ["id": "c2", "name": "Almuerzo", "options": [["name": "A", "foods": [f("Pollo", 330, 62, 0, 7, 200), f("Arroz", 195, 4, 42, 0.5, 150)]]]],
    ] }
    static func marca(_ id: String, _ o: String, _ e: String, _ excl: [Int]? = nil) -> [String: Any] {
        ["comida_id": id, "opcion_elegida": o, "estado": e, "foods_excluidos": excl as Any? ?? NSNull()]
    }
    static func json(_ a: AjusteComida) -> Any { try! JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) }

    typealias CasoConsumo = (nombre: String, marcas: [[String: Any]], ajustes: [String: AjusteComida], vistas: [String: Int])
    static var casosConsumo: [CasoConsumo] { [
        ("«Comí» con un huevo agregado: cuenta",
         [marca("c1", "A", "comido")], ["c1": AjusteComida(compensar: false, agregados: [ag(huevo, 1, M(nombre: "unidad", gramos: 60))])], [:]),
        ("el agregado destildado (índice n + j) no cuenta; el de la avena sí",
         [marca("c1", "A", "comido", [2])],
         ["c1": AjusteComida(compensar: false, agregados: [ag(huevo, 1, M(nombre: "unidad", gramos: 60))])], [:]),
        ("dos agregados, el segundo destildado y la avena destildada",
         [marca("c1", "A", "comido", [1, 3])],
         ["c1": AjusteComida(compensar: false, agregados: [ag(huevo, 1, M(nombre: "unidad", gramos: 60)), ag(zapallo, 80, ts: 1_730_000_000_002)])], [:]),
        ("marcada con la B: los agregados van después de su único alimento",
         [marca("c1", "B", "comido", [1])],
         ["c1": AjusteComida(opcion: 0, agregados: [ag(huevo, 1, M(nombre: "unidad", gramos: 60)), ag(zapallo, 80, ts: 1_730_000_000_002)])], [:]),
        ("agregado compensado en el almuerzo y las dos comidas marcadas",
         [marca("c1", "A", "comido"), marca("c2", "A", "comido")],
         ["c1": AjusteComida(agregados: [ag(huevo, 1, M(nombre: "unidad", gramos: 60))])], [:]),
        ("salteada con agregados: no suma", [marca("c1", "A", "saltado")], ["c1": AjusteComida(agregados: [ag(zapallo, 80)])], [:]),
        ("no la come: los agregados no suman aunque esté marcada",
         [marca("c1", "A", "comido"), marca("c2", "A", "comido")],
         ["c1": AjusteComida(compensar: false, omitida: true, agregados: [ag(zapallo, 80)])], [:]),
    ] }

    static func correr(_ c: CasoConsumo) throws -> ConsumoDelDia.Consumo {
        func dec<T: Decodable>(_ x: Any, _ t: T.Type) throws -> T { try JSONDecoder().decode(t, from: JSONSerialization.data(withJSONObject: x)) }
        return ConsumoDelDia.calcular(try dec(Self.comidas, [Comida].self),
                                      marcas: ConsumoDelDia.marcas(try dec(c.marcas, [ComidaMarcada].self)), libres: [],
                                      ajustes: c.ajustes, vistas: c.vistas)
    }

    static func esperado(_ r: ConsumoDelDia.Consumo) -> [String: Any] {
        ["kcal": r.kcal, "prot": r.prot, "carb": r.carb, "fat": r.fat, "comidas": r.comidas, "hechas": r.hechas, "salteadas": r.salteadas]
    }

    @Test func loConsumido() throws {
        let r = try Self.casosConsumo.map(Self.correr)
        #expect(abs(r[0].kcal - (86 + 233 + 86)) < 1e-9)
        #expect(abs(r[1].kcal - (86 + 233)) < 1e-9)
        #expect(abs(r[2].kcal - (86 + 86)) < 1e-9)
        #expect(abs(r[3].kcal - (120 + 21)) < 1e-9)
        #expect(r[4].hechas == 2 && r[4].kcal < 319 + 86 + 525)
        #expect(r[5].kcal == 0 && r[5].salteadas == 1)
        #expect(abs(r[6].kcal - 525) < 1e-9 && r[6].comidas == 1)
    }

    @Test func losTildesAlBorrar() {
        // Plan de 2: tildes 0, 1 del plan; 2, 3, 4 de los agregados.
        #expect(AgregadosComida.excluidosTrasBorrar([1, 2, 4], alimentosPlan: 2, borrado: 0) == [1, 3])
        #expect(AgregadosComida.excluidosTrasBorrar([3], alimentosPlan: 2, borrado: 1) == [])
        #expect(AgregadosComida.excluidosTrasBorrar([0, 4], alimentosPlan: 2, borrado: 1) == [0, 3])
    }

    // MARK: - Lectura, escritura y topes

    @Test func laLecturaToleraYSinAgregadosElJSONQuedaComoAntes() throws {
        let sin = String(data: try JSONEncoder().encode(AjusteComida(deltaKcal: 50)), encoding: .utf8)!
        #expect(!sin.contains("agregados"))
        let con = AjusteComida(agregados: [Self.ag(Self.huevo, 1, M(nombre: "unidad", gramos: 60))])
        #expect(!con.neutro)
        let vuelta = try JSONDecoder().decode(AjusteComida.self, from: JSONEncoder().encode(con))
        #expect(vuelta == con)
        #expect(String(data: try JSONEncoder().encode(con), encoding: .utf8)!.contains("\"_ts\":1730000000000"))
        // Un agregado roto se descarta solo; el resto del ajuste queda.
        let rota = try JSONDecoder().decode(AjusteComida.self, from: Data("""
        {"deltaKcal":50,"agregados":[{"nombre":"","cantidad":1},{"nombre":"Huevo","cantidad":1,"unidad":"unidad","gramosUnidad":60,
        "gramos":60,"kcal":86,"p":7.6,"c":0.4,"g":5.7,"por100":{"kcal":143,"p":12.6,"c":0.7,"g":9.5},"origen":"base","_ts":5},
        {"nombre":"X","cantidad":-1,"gramos":1,"kcal":1,"p":0,"c":0,"g":0,"por100":{"kcal":1,"p":0,"c":0,"g":0},"_ts":6},
        {"nombre":"Y","cantidad":10,"gramos":10,"kcal":1,"p":0,"c":0,"g":0,"por100":{"kcal":1,"p":0,"c":0,"g":0},"origen":"otro","_ts":7}]}
        """.utf8))
        #expect(rota.deltaKcal == 50 && rota.agregados.map(\.nombre) == ["Huevo", "Y"])
        #expect(rota.agregados[1].unidad == "g" && rota.agregados[1].origen == .base)
        // Una lista que no es lista: sin agregados, el resto igual.
        let otra = try JSONDecoder().decode(AjusteComida.self, from: Data(#"{"deltaKcal":50,"agregados":"x"}"#.utf8))
        #expect(otra.deltaKcal == 50 && otra.agregados.isEmpty)
        // Dos con el mismo `_ts` (su identidad en las vistas y al borrar): queda el primero.
        var segundo = con.agregados[0]
        segundo = AlimentoAgregado(nombre: "Otro", cantidad: segundo.cantidad, unidad: segundo.unidad, gramosUnidad: segundo.gramosUnidad,
                                   gramos: segundo.gramos, kcal: segundo.kcal, p: segundo.p, c: segundo.c, g: segundo.g, por100: segundo.por100,
                                   origen: segundo.origen, ts: segundo.ts)
        let doble = AjusteComida(agregados: [con.agregados[0], segundo])
        #expect(try JSONDecoder().decode(AjusteComida.self, from: JSONEncoder().encode(doble)).agregados.map(\.nombre) == ["Huevo entero"])
    }

    @Test func losTopes() {
        var aj: [String: AjusteComida] = [:]
        let uno = Self.ag(Self.zapallo, 80)
        aj["c1"] = AjusteComida(agregados: Array(repeating: uno, count: 8))
        #expect(AgregadosComida.motivoNoEntra(aj, comidaId: "c1") == nil)
        aj["c1"]!.agregados.append(uno)
        #expect(AgregadosComida.motivoNoEntra(aj, comidaId: "c1") != nil)
        aj = ["c1": AjusteComida(agregados: Array(repeating: uno, count: 8)), "c2": AjusteComida(agregados: Array(repeating: uno, count: 8)),
              "c3": AjusteComida(agregados: Array(repeating: uno, count: 8))]
        #expect(AgregadosComida.motivoNoEntra(aj, comidaId: "c3") == nil)
        aj["c4"] = AjusteComida(agregados: [uno])
        #expect(AgregadosComida.motivoNoEntra(aj, comidaId: "c4") != nil)
        // El día lleno de agregados con nombres largos entra en la fila (16000 bytes) con margen.
        let largo = Self.ag(Self.cand(String(repeating: "Ñandú asado con salsa ", count: 6), 200, 20, 10, 10), 1999)
        #expect(largo.nombre.count == AgregadosComida.largoNombre)
        let lleno = Dictionary(uniqueKeysWithValues: (0..<3).map { ("comida-\($0)", AjusteComida(deltaKcal: -50, cantidades: ["0": 120, "1": 35],
            anclas: ["0": AnclaAlimento(nombre: "Pechuga de pollo cocida", unidad: "g"), "1": AnclaAlimento(nombre: "Arroz integral", unidad: "g")],
            agregados: Array(repeating: largo, count: 8))) })
        #expect(AgregadosComida.bytesJsonb(lleno) <= AgregadosComida.maximoBytesJsonb, "\(AgregadosComida.bytesJsonb(lleno))")
        // El tope deja 1000 bytes de margen con los 16000 de nativa_004.
        #expect(AgregadosComida.maximoBytesJsonb <= 15000)
        // Un día que pasa la cota no entra, aunque no llegue a los topes de cantidad (el compacto de antes lo dejaba pasar).
        let enorme = Self.ag(Self.cand(String(repeating: "Ñ", count: 80), 1.3, 0.1, 0.3, 0.1, unidad: "taza", gu: 245.5), 1.5,
                             M(nombre: "taza", gramos: 245.5))
        let gordo = Dictionary(uniqueKeysWithValues: (0..<3).map { i in
            ("comida-\(i)", AjusteComida(cantidades: Dictionary(uniqueKeysWithValues: (0..<30).map { ("\($0)", 12.345 + Double($0)) }),
                                       anclas: Dictionary(uniqueKeysWithValues: (0..<30).map { ("\($0)", AnclaAlimento(nombre: String(repeating: "x", count: 40), unidad: "g")) }),
                                       agregados: (0..<8).map { j in AgregadosComida.agregado(enorme.candidato, cantidad: 1.5, medida: M(nombre: "taza", gramos: 245.5), ts: Int64(i * 10 + j)) }))
        })
        #expect(AgregadosComida.bytesJsonb(gordo) > AgregadosComida.maximoBytesJsonb)
        #expect(AgregadosComida.motivoNoEntra(gordo, comidaId: "comida-0") == "No entran más alimentos agregados hoy.")
    }

    /// La cota del jsonb nunca da menos que lo que midió la base (y no se pasa de más del 15 %).
    @Test func laCotaDelJsonbCubreLoMedido() throws {
        let raiz = try JSONSerialization.jsonObject(with: Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/agregados_jsonb_medido.json"))) as! [String: Any]
        for caso in raiz["casos"] as! [[String: Any]] {
            let medido = caso["jsonb"] as! Int
            let datos = try JSONSerialization.data(withJSONObject: caso["ajustes"]!)
            let dia = try JSONDecoder().decode([String: AjusteComida].self, from: datos)
            let cota = AgregadosComida.bytesJsonb(dia)
            #expect(cota >= medido, "\(caso["caso"]!): \(cota) < \(medido)")
            #expect(Double(cota) <= Double(medido) * 1.15, "\(caso["caso"]!): \(cota) muy por encima de \(medido)")
        }
    }

    // MARK: - Vectores compartidos con Android

    static var archivo: URL { raizRepo.appendingPathComponent("apps/shared/vectores/agregados_comida.json") }

    static func jsonCand(_ c: Cand) -> [String: Any] {
        var d: [String: Any] = ["nombre": c.nombre, "por100": ["kcal": c.por100.kcal, "p": c.por100.p, "c": c.por100.c, "g": c.por100.g],
                                "origen": c.origen.rawValue]
        if let u = c.unidad { d["unidad"] = u }
        if let g = c.gramosPorUnidad { d["gramosPorUnidad"] = g }
        return d
    }
    static func jsonMedida(_ m: M) -> [String: Any] { ["nombre": m.nombre, "gramos": m.gramos] }
    static func jsonAlimento(_ a: Alimento) -> [String: Any] {
        var d: [String: Any] = ["name": a.nombre]
        if let q = a.qty { d["qty"] = q }
        if let u = a.unidad { d["unit"] = u }
        if let v = a.kcal { d["kcal"] = v }
        if let v = a.prot { d["prot"] = v }
        if let v = a.carb { d["carb"] = v }
        if let v = a.fat { d["fat"] = v }
        return d
    }

    /// Las cuentas sueltas: medidas, pasos y agregados, con lo que dan.
    static func sueltos() -> [String: Any] {
        let medidas: [[String: Any]] = Self.candidatos.map { c in
            let i = AgregadosComida.inicial(c)
            return ["candidato": jsonCand(c), "medidas": AgregadosComida.medidas(c).map(jsonMedida),
                    "inicial": ["cantidad": i.cantidad, "medida": jsonMedida(i.medida)]]
        }
        let ms = [M.gramo, M(nombre: "unidad", gramos: 60)]
        let pasos: [[String: Any]] = [0, 0.3, 1, 1.3, 4, 5, 19, 37, 95, 100, 105, 110, 1999, 2000, 2500, 50, 51].flatMap { q in
            ms.map { m in ["cantidad": q, "medida": jsonMedida(m), "subir": AgregadosComida.subir(q, m),
                           "bajar": AgregadosComida.bajar(q, m), "acotar": AgregadosComida.acotar(q, m)] }
        }
        let agregados: [[String: Any]] = Self.candidatos.flatMap { c in
            AgregadosComida.medidas(c).flatMap { m in
                [1.0, 80, 2.5].map { q in
                    ["candidato": jsonCand(c), "cantidad": q, "medida": jsonMedida(m),
                     "esperado": json(AjusteComida(agregados: [AgregadosComida.agregado(c, cantidad: q, medida: m, ts: 42)]))]
                }
            }
        }
        let tildes: [[String: Any]] = [([1, 2, 4], 2, 0), ([3], 2, 1), ([0, 4], 2, 1), ([0, 1, 2, 3], 1, 2), ([], 3, 0)].map {
            ["excluidos": $0.0, "n": $0.1, "j": $0.2, "esperado": AgregadosComida.excluidosTrasBorrar($0.0, alimentosPlan: $0.1, borrado: $0.2)]
        }
        return ["medidas": medidas, "pasos": pasos, "agregados": agregados, "tildes": tildes]
    }

    static func casosJSON() throws -> [String: Any] {
        let dia: [[String: Any]] = Self.casosDia.map { nombre, comidas, ajustes in
            ["nombre": nombre,
             "comidas": comidas.map { ["id": $0.id, "nombre": $0.nombre, "opcion": $0.opcion, "alimentos": $0.alimentos.map(jsonAlimento)] },
             "ajustes": ajustes.mapValues(json), "esperado": salidaDia(comidas, ajustes)]
        }
        let consumo: [[String: Any]] = try Self.casosConsumo.map { c in
            ["nombre": c.nombre, "comidas": Self.comidas, "marcas": c.marcas, "ajustes": c.ajustes.mapValues(json), "vistas": c.vistas,
             "esperado": esperado(try correr(c))]
        }
        return sueltos().merging(["dia": dia, "consumo": consumo]) { $1 }
    }

    @Test func generarVectores() throws {
        guard ProcessInfo.processInfo.environment["GENERAR_VECTORES_AGREGADOS"] == "1" else { return }
        var todo = try Self.casosJSON()
        todo["generado"] = "MyPumpKit AgregadosComidaTests (iOS). Android: AgregadosComidaTest.kt lo tiene que dar igual."
        try JSONSerialization.data(withJSONObject: todo, options: [.prettyPrinted, .sortedKeys]).write(to: Self.archivo)
    }

    /// Lo grabado tiene que seguir saliendo igual (si cambia la regla a propósito, se regeneran y se revisa el diff).
    @Test func losVectoresSiguenIguales() throws {
        let grabado = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.archivo)) as! NSDictionary
        var ahora = try Self.casosJSON()
        ahora["generado"] = grabado["generado"]
        let a = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: ahora, options: .sortedKeys)) as! NSDictionary
        for k in ["medidas", "pasos", "agregados", "tildes", "dia", "consumo"] {
            #expect(a[k] as? NSArray == grabado[k] as? NSArray, "\(k)")
        }
    }
}
