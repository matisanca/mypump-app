import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// Los vectores de la web: `calcularConsumido` de cliente.html con su estado (scripts/nativa/vectores-consumo.mjs).
private struct ArchivoConsumo: Decodable {
    struct Entrada: Decodable {
        let comidas: [Comida]
        let marcas: [ComidaMarcada]
        let swaps: [String: Alimento]?
        let libres: [ComidaLibre]
    }
    struct Salida: Decodable {
        let kcal, prot, carb, fat: Double
        let nComidas, nComidasMarcadas: Int
    }
    struct Caso: Decodable { let nombre: String; let entrada: Entrada; let salida: Salida }
    let fuente: String
    let casos: [Caso]
}

private func fallasWeb(_ url: URL) throws -> (Int, [String]) {
    let a = try JSONDecoder().decode(ArchivoConsumo.self, from: Data(contentsOf: url))
    var fallas: [String] = []
    for c in a.casos {
        let e = c.entrada
        let r = ConsumoDelDia.calcular(e.comidas, marcas: ConsumoDelDia.marcas(e.marcas), libres: e.libres) { cid, o, i, a in
            e.swaps?["\(cid)|\(o)|\(i)"] ?? a
        }
        let s = c.salida
        let iguales = abs(r.kcal - s.kcal) < 1e-9 && abs(r.prot - s.prot) < 1e-9 && abs(r.carb - s.carb) < 1e-9
            && abs(r.fat - s.fat) < 1e-9 && r.comidas == s.nComidas && r.hechas == s.nComidasMarcadas
        if !iguales { fallas.append("\(c.nombre): \(r) ≠ \(s)") }
    }
    return (a.casos.count, fallas)
}

@Suite("Consumido hoy (DIE-05..07): lo mismo que calcularConsumido de la web, más los ajustes del día")
struct ConsumoDelDiaTests {
    static let publicos = raizRepo.appendingPathComponent("apps/shared/vectores/consumo_dia.json")
    static let privado = carpetaPrivada.appendingPathComponent("consumo_dia.json")
    static let archivoAjustes = raizRepo.appendingPathComponent("apps/shared/vectores/consumo_dia_ajustes.json")

    @Test func vectoresDeLaWeb() throws {
        let (n, f) = try fallasWeb(Self.publicos)
        #expect(n >= 20)
        #expect(f.isEmpty, "\(f.prefix(3))")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: privado.path)))
    func dietasReales() throws {
        let (n, f) = try fallasWeb(Self.privado)
        #expect(n >= 270)
        #expect(f.isEmpty, "\(f.count) de \(n): \(f.prefix(2))")
    }

    // MARK: - La opción de la marca

    static func comida(_ nombres: [String?]) -> Comida {
        Comida(id: "c1", nombre: "Desayuno", opciones: nombres.map { Opcion(nombre: $0, alimentos: []) })
    }

    @Test func laOpcionSeGuardaPorNombreOLetra() {
        let c = Self.comida(["A", "B", "C"])
        #expect(ConsumoDelDia.nombreOpcion(c, 1) == "B")
        #expect(ConsumoDelDia.indiceOpcion(c, nombre: "C") == 2)
        // Una opción que ya no existe (Mati volvió a publicar) o sin nombre guardado: la A, como la web.
        #expect(ConsumoDelDia.indiceOpcion(c, nombre: "D") == 0 && ConsumoDelDia.indiceOpcion(c, nombre: nil) == 0)
        #expect(ConsumoDelDia.indiceOpcion(c, nombre: "") == 0)
        // Sin nombres (15 comidas de 100 dietas): la letra de la que se ve; la «A» que guarda la web es la primera.
        let sin = Self.comida([nil, nil, ""])
        #expect(ConsumoDelDia.nombreOpcion(sin, 0) == "A" && ConsumoDelDia.nombreOpcion(sin, 2) == "C")
        #expect(ConsumoDelDia.indiceOpcion(sin, nombre: "B") == 1 && ConsumoDelDia.indiceOpcion(sin, nombre: "C") == 2)
        #expect(ConsumoDelDia.indiceOpcion(sin, nombre: "A") == 0)
        // Nombres repetidos (A, A, B, C en 4 comidas): la primera con ese nombre, como la web.
        let rep = Self.comida(["A", "A", "B", "C"])
        #expect(ConsumoDelDia.nombreOpcion(rep, 1) == "A" && ConsumoDelDia.indiceOpcion(rep, nombre: "A") == 0)
        #expect(ConsumoDelDia.indiceOpcion(rep, nombre: "B") == 2)
    }

    @Test func laMarcaDesdeLaFila() throws {
        let filas = try JSONDecoder().decode([ComidaMarcada].self, from: Data("""
        [{"comida_id":"c1","opcion_elegida":"B","estado":"comido","foods_excluidos":[3,1,3]},
         {"comida_id":"c2","opcion_elegida":"A","estado":"saltado","foods_excluidos":null},
         {"comida_id":"c3","opcion_elegida":"A","estado":"otro"},
         {"comida_id":"c4","opcion_elegida":"A","estado":"comido"},
         {"comida_id":"c4","opcion_elegida":"C","estado":"saltado"}]
        """.utf8))
        let m = ConsumoDelDia.marcas(filas)
        #expect(m["c1"] == MarcaComida(opcion: "B", estado: .comido, excluidos: [1, 3]))
        #expect(m["c2"] == MarcaComida(opcion: "A", estado: .saltado))
        #expect(m["c3"] == nil)
        #expect(m["c4"] == MarcaComida(opcion: "C", estado: .saltado))
        // La opción a la vista: la de «Comí»; con «Salté», la que se elija.
        let c = Self.comida(["A", "B"])
        #expect(ConsumoDelDia.opcionDeLaMarca(c, m["c1"]) == 1 && ConsumoDelDia.opcionDeLaMarca(c, m["c2"]) == nil)
        // En disco va igual que se lee (y una lista rota no tira la marca).
        let vuelta = try JSONDecoder().decode(MarcaComida.self, from: JSONEncoder().encode(m["c1"]!))
        #expect(vuelta == m["c1"])
        let rota = try JSONDecoder().decode(MarcaComida.self, from: Data(#"{"opcion":"A","estado":"comido","excluidos":"x"}"#.utf8))
        #expect(rota == MarcaComida(opcion: "A", estado: .comido))
    }

    // MARK: - Con los ajustes del día (D22): vectores propios, Android los tiene que dar igual

    static func f(_ n: String, _ kcal: Double, _ p: Double, _ c: Double, _ g: Double, _ qty: Double, _ u: String = "g") -> [String: Any] {
        ["name": n, "qty": qty, "unit": u, "kcal": kcal, "prot": p, "carb": c, "fat": g]
    }
    static var huevo: [String: Any] { f("Huevo entero", 172, 15.1, 0.8, 11.4, 2, "unidad") }
    static var pan: [String: Any] { f("Pan integral", 200, 8, 38, 2, 80) }
    static var palta: [String: Any] { f("Palta", 80, 1, 4, 7.3, 50) }
    static var pollo: [String: Any] { f("Pechuga de pollo", 330, 62, 0, 7, 200) }
    static var arroz: [String: Any] { f("Arroz", 195, 4, 42, 0.5, 150) }
    static var yogur: [String: Any] { f("Yogur", 120, 10, 14, 3, 200) }
    static var comidas: [[String: Any]] { [
        ["id": "c1", "name": "Desayuno", "options": [["name": "A", "foods": [huevo, pan, palta]], ["name": "B", "foods": [yogur, pan]]]],
        ["id": "c2", "name": "Almuerzo", "options": [["name": "A", "foods": [pollo, arroz]], ["name": "B", "foods": [arroz, palta]]]],
        ["id": "c3", "name": "Merienda", "options": [["name": "A", "foods": [yogur, ["name": "Café"]]]]],
        ["id": "c4", "name": "Cena", "options": [["name": "A", "foods": [pollo, arroz, palta]]]],
    ] }
    static func marca(_ id: String, _ o: String, _ e: String, _ excl: [Int]? = nil) -> [String: Any] {
        ["comida_id": id, "opcion_elegida": o, "estado": e, "foods_excluidos": excl as Any? ?? NSNull()]
    }

    typealias Caso = (nombre: String, marcas: [[String: Any]], ajustes: [String: [String: Any]], vistas: [String: Int], libres: [[String: Any]])
    static var casos: [Caso] { [
        ("una que hoy no come no suma ni cuenta, aunque tenga marca; la siguiente se come con lo que le pasa",
         [marca("c1", "A", "comido"), marca("c2", "A", "comido"), marca("c3", "A", "comido")],
         ["c2": ["omitida": true, "compensar": true]], [:], []),
        ("«Comí» en una comida con +150 kcal: cuentan las porciones de hoy",
         [marca("c1", "A", "comido")], ["c1": ["deltaKcal": 150, "compensar": false]], [:], []),
        ("gramos a mano y un alimento destildado",
         [marca("c1", "A", "comido", [2])], ["c1": ["opcion": 0, "cantidades": ["1": 120]]], [:], []),
        ("marcada con la B y ajustada a mano en la A: cuenta la B (los gramos eran de la A)",
         [marca("c1", "B", "comido")], ["c1": ["opcion": 0, "cantidades": ["0": 3], "compensar": true]], ["c1": 0], []),
        ("el almuerzo +200 se compensa en la merienda; las dos comidas y la cena salteada",
         [marca("c2", "A", "comido"), marca("c3", "A", "comido"), marca("c4", "A", "saltado")],
         ["c2": ["deltaKcal": 200, "compensar": true]], [:], []),
        ("salteada con ajuste: no suma", [marca("c1", "A", "saltado")], ["c1": ["deltaKcal": -100]], [:], []),
        ("sin marcas: cero, y las que no come no cuentan entre las comidas", [],
         ["c1": ["omitida": true], "c4": ["omitida": true, "compensar": false]], [:], []),
        ("la opción a la vista de una no marcada cambia lo que le llega a la siguiente",
         [marca("c2", "A", "comido")], ["c1": ["deltaKcal": 100, "compensar": true, "opcion": 1]], ["c1": 1], []),
        ("con comidas libres y un día ajustado",
         [marca("c1", "A", "comido", [0]), marca("c2", "B", "comido"), marca("c4", "A", "comido", [1, 2])],
         ["c3": ["omitida": true, "compensar": true]], ["c2": 0],
         [["id": "l1", "kcal": 350, "prot": 20, "carb": 40.5, "fat": 10], ["id": "l2", "kcal": "125", "prot": NSNull(), "carb": 3, "fat": 1.25]]),
        ("todas comidas sin ajustes que muevan nada: igual que la web",
         [marca("c1", "B", "comido"), marca("c2", "A", "comido"), marca("c3", "A", "comido"), marca("c4", "A", "comido")],
         ["c1": ["opcion": 1, "cantidades": [String: Double]()]], [:], []),
    ] }

    static func decodificar<T: Decodable>(_ x: Any, _ t: T.Type) throws -> T {
        try JSONDecoder().decode(t, from: JSONSerialization.data(withJSONObject: x))
    }

    static func correr(_ c: Caso) throws -> ConsumoDelDia.Consumo {
        ConsumoDelDia.calcular(try decodificar(Self.comidas, [Comida].self),
                               marcas: ConsumoDelDia.marcas(try decodificar(c.marcas, [ComidaMarcada].self)),
                               libres: try decodificar(c.libres, [ComidaLibre].self),
                               ajustes: try decodificar(c.ajustes, [String: AjusteComida].self), vistas: c.vistas)
    }

    static func esperado(_ r: ConsumoDelDia.Consumo) -> [String: Any] {
        ["kcal": r.kcal, "prot": r.prot, "carb": r.carb, "fat": r.fat, "comidas": r.comidas, "hechas": r.hechas, "salteadas": r.salteadas]
    }

    @Test func conAjustes() throws {
        let r = try Self.casos.map(Self.correr)
        // No la come: el almuerzo no cuenta; la merienda (con lo que le pasa) y el desayuno, sí.
        #expect(r[0].comidas == 3 && r[0].hechas == 2)
        #expect(r[0].kcal > 452 + 120)
        // +150: más que el plan (452), dentro de lo que se puede servir.
        #expect(r[1].kcal > 452 && r[1].kcal < 452 + 200)
        // 120 g de pan (300 kcal) + el huevo; la palta destildada.
        #expect(abs(r[2].kcal - (172 + 300)) < 1e-9)
        #expect(abs(r[3].kcal - 320) < 1e-9)
        // El almuerzo con +200 y la merienda con −200 (dentro de su tope).
        #expect(r[4].hechas == 2 && r[4].salteadas == 1)
        #expect(r[5].kcal == 0 && r[5].salteadas == 1)
        #expect(r[6].kcal == 0 && r[6].comidas == 2 && r[6].pendientes == 2)
        // El desayuno con la B (+100, compensa): el almuerzo come 100 menos.
        #expect(r[7].kcal < 525 && r[7].hechas == 1)
        #expect(r[8].comidas == 3 && r[8].hechas == 3)
        #expect(abs(r[9].kcal - (320 + 525 + 120 + 605)) < 1e-9)
    }

    @Test func generarVectores() throws {
        guard ProcessInfo.processInfo.environment["GENERAR_VECTORES_CONSUMO"] == "1" else { return }
        let casos: [[String: Any]] = try Self.casos.map { c in
            ["nombre": c.nombre, "comidas": Self.comidas, "marcas": c.marcas, "ajustes": c.ajustes, "vistas": c.vistas,
             "libres": c.libres, "esperado": Self.esperado(try Self.correr(c))]
        }
        let todo: [String: Any] = ["generado": "MyPumpKit ConsumoDelDiaTests (iOS). Android: ConsumoDelDiaTest.kt lo tiene que dar igual.",
                                   "casos": casos]
        try JSONSerialization.data(withJSONObject: todo, options: [.prettyPrinted, .sortedKeys]).write(to: Self.archivoAjustes)
    }

    /// Lo grabado tiene que seguir saliendo igual (si cambia la regla a propósito, se regeneran y se revisa el diff).
    @Test func losVectoresDeAjustesSiguenIguales() throws {
        let todo = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.archivoAjustes)) as! [String: Any]
        let casos = todo["casos"] as! [[String: Any]]
        #expect(casos.count == Self.casos.count)
        for (i, c) in Self.casos.enumerated() {
            #expect(casos[i]["nombre"] as? String == c.nombre)
            let ahora = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: Self.esperado(try Self.correr(c)))) as! NSDictionary
            let antes = casos[i]["esperado"] as! NSDictionary
            #expect(ahora == antes, "\(c.nombre)")
        }
    }
}
