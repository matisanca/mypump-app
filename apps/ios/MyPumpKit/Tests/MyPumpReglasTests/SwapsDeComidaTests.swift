import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// Los casos de scripts/test-swaps-anclados.mjs (no está en `npm test` y es el que cuida el BORRADO de swaps).
@Suite("Swaps de comida: anclaje e hidratación (casos de la web)")
struct SwapsDeComidaTests {
    func food(_ n: String, _ q: Double, _ u: String = "g") -> Alimento { Alimento(nombre: n, qty: q, unidad: u, kcal: 100) }
    func json(_ a: Alimento) -> JSONValue {
        .objeto(["name": .texto(a.nombre), "qty": .numero(a.qty ?? 0), "unit": .texto(a.unidad ?? ""), "kcal": .numero(a.kcal ?? 0)])
    }
    func dieta(_ comidas: [(String, [Alimento])]) -> EstructuraDieta {
        EstructuraDieta(comidas: comidas.map { Comida(id: $0.0, opciones: [Opcion(nombre: "A", alimentos: $0.1)]) })
    }
    var v1: EstructuraDieta { dieta([("c2", [food("Café", 200, "ml"), food("Pan lactal", 60), food("Huevos", 3, "unidad")])]) }
    var v2: EstructuraDieta { dieta([("c2", [food("Yogur", 200), food("Café", 200, "ml"), food("Pan lactal", 60), food("Huevos", 3, "unidad")])]) }
    var tipos: EstructuraDieta {
        EstructuraDieta(tiposDia: [
            TipoDia(id: "entreno", comidas: [Comida(id: "c2", opciones: [Opcion(nombre: "A", alimentos: [food("Café", 200, "ml"), food("Avena", 80), food("Huevos", 3, "unidad")])])]),
            TipoDia(id: "descanso", comidas: [Comida(id: "c2", opciones: [Opcion(nombre: "A", alimentos: [food("Café", 200, "ml"), food("Avena", 50), food("Huevos", 3, "unidad")])])]),
        ])
    }

    func efectivo(_ d: EstructuraDieta, _ original: Alimento, _ swap: SwapLocal?, comida: String = "c2", opt: Int = 0, idx: Int) -> String {
        SwapsDeComida.efectivo(original, swap: swap, comidaId: comida) {
            SwapsDeComida.enPosicion(d, tipoActivo: nil, comidaId: comida, optIdx: opt, foodIdx: idx)
        }.alimento.nombre
    }

    func fila(_ comida: String, _ opt: Int, _ idx: Int, _ data: JSONValue) throws -> FoodSwap {
        let j: JSONValue = .objeto(["comida_id": .texto(comida), "opt_idx": .numero(Double(opt)), "food_idx": .numero(Double(idx)), "food_data": data])
        return try JSONDecoder().decode(FoodSwap.self, from: JSONEncoder().encode(j))
    }

    func hidratar(_ d: EstructuraDieta, remotos: [FoodSwap]?, locales: [String: SwapLocal] = [:], pendientes: [String: String] = [:], yaMigrado: Bool = false) -> SwapsDeComida.Hidratacion? {
        SwapsDeComida.hidratar(remotos: remotos, locales: locales, dietaId: "d1", pendientes: pendientes, yaMigrado: yaMigrado) {
            SwapsDeComida.enPosicion(d, tipoActivo: nil, comidaId: $0, optIdx: $1, foodIdx: $2)
        }
    }

    // 1. el swap se ancla al alimento que reemplaza
    @Test func conAnclaGuardaNombreCantidadYUnidad() {
        let a = SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("Pan lactal", 60))
        #expect(a["_orig"] == .objeto(["name": .texto("Pan lactal"), "qty": .numero(60), "unit": .texto("g")]))
        #expect(a["name"]?.comoTexto == "Arroz")
    }

    @Test func conLaDietaIgualSeAplica() {
        let s = SwapLocal(current: SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("Pan lactal", 60)))
        #expect(efectivo(v1, food("Pan lactal", 60), s, idx: 1) == "Arroz")
    }

    @Test func matiAgregaUnYogurAntesYElSwapDelPanNoTapaAlCafe() {
        let s = SwapLocal(current: SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("Pan lactal", 60)))
        #expect(efectivo(v2, food("Café", 200, "ml"), s, idx: 1) == "Café")
    }

    @Test func matiCambia60a80YElSwapNoSeAplica() {
        let s = SwapLocal(current: SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("Pan lactal", 60)))
        let v3 = dieta([("c2", [food("Café", 200, "ml"), food("Pan lactal", 80)])])
        #expect(efectivo(v3, food("Pan lactal", 80), s, idx: 1) == "Pan lactal")
    }

    @Test func mayusculasYEspaciosNoRompenElAncla() {
        let s = SwapLocal(current: SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("  PAN LACTAL ", 60, " G ")))
        #expect(efectivo(v1, food("Pan lactal", 60), s, idx: 1) == "Arroz")
    }

    // 2. hidratar desde el backend
    @Test func legadoSinOrigSeAnclaYSeResube() throws {
        let r = try #require(hidratar(v1, remotos: [try fila("c2", 0, 1, json(food("Arroz", 80)))]))
        let k = "swap_d1_c2_0_1"
        #expect(r.swaps[k]?.current["_orig"]?["name"]?.comoTexto == "Pan lactal")
        #expect(r.operaciones.map(\.kind) == ["swap"])
        #expect(r.operaciones.first?.clave == k)
    }

    @Test func ancladoQueYaNoCoincideSeSacaYSeBorraEnElBackend() throws {
        let anclado = SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("Pan lactal", 60))
        let r = try #require(hidratar(v2, remotos: [try fila("c2", 0, 1, anclado)]))   // en v2 la posición 1 es Café
        #expect(r.swaps["swap_d1_c2_0_1"] == nil)
        #expect(r.operaciones.map(\.kind) == ["swap_del"])
    }

    @Test func ancladoQueSigueCoincidiendoQuedaSinTrafico() throws {
        let anclado = SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("Pan lactal", 60))
        let r = try #require(hidratar(v1, remotos: [try fila("c2", 0, 1, anclado)]))
        #expect(r.swaps["swap_d1_c2_0_1"] != nil)
        #expect(r.operaciones.isEmpty)
    }

    @Test func posicionQueYaNoExisteNoRompe() throws {
        let r = try #require(hidratar(v1, remotos: [try fila("c9", 0, 7, json(food("Arroz", 80)))]))
        #expect(r.operaciones.isEmpty)
    }

    // 2b. tipos de día y cola
    @Test func unSwapDeOtroAlimentoNoSeCruzaEntreTiposDeDia() {
        let cruzada = EstructuraDieta(tiposDia: [
            TipoDia(id: "a", comidas: [Comida(id: "c2", opciones: [Opcion(nombre: "A", alimentos: [food("Café", 200, "ml"), food("Avena", 80)])])]),
            TipoDia(id: "b", comidas: [Comida(id: "c2", opciones: [Opcion(nombre: "A", alimentos: [food("Café", 200, "ml"), food("Tostadas", 2, "unidad")])])]),
        ])
        let s = SwapLocal(current: SwapsDeComida.conAncla(json(food("Galletas", 30)), original: food("Tostadas", 2, "unidad")))
        #expect(efectivo(cruzada, food("Avena", 80), s, idx: 1) == "Avena")
    }

    @Test func unSwapDeEntrenoSigueValiendoEnDescanso() {
        let s = SwapLocal(current: SwapsDeComida.conAncla(json(food("Pan", 60)), original: food("Avena", 80)))
        #expect(efectivo(tipos, food("Avena", 50), s, idx: 1) == "Pan")
    }

    @Test func yElHydrateNoLoBorra() throws {
        let anclado = SwapsDeComida.conAncla(json(food("Pan", 60)), original: food("Avena", 80))
        let r = try #require(hidratar(tipos, remotos: [try fila("c2", 0, 1, anclado)]))
        #expect(r.swaps["swap_d1_c2_0_1"] != nil)
        #expect(!r.operaciones.contains { $0.kind == "swap_del" })
    }

    @Test func elAnclaValeContraCualquierTipoDeDia() throws {
        let anclado = SwapsDeComida.conAncla(json(food("Pan", 40)), original: food("Avena", 50))
        let r = try #require(hidratar(tipos, remotos: [try fila("c2", 0, 1, anclado)]))
        #expect(r.swaps["swap_d1_c2_0_1"] != nil)
        #expect(!r.operaciones.contains { $0.kind == "swap_del" })
        #expect(efectivo(tipos, food("Avena", 80), r.swaps["swap_d1_c2_0_1"], idx: 1) == "Pan")
    }

    @Test func conUnaOpPendienteElHydrateNoLaToca() throws {
        let k = "swap_d1_c2_0_1"
        let anclado = SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("Pan lactal", 60))
        let local = SwapLocal(current: SwapsDeComida.conAncla(json(food("Galletas", 30)), original: food("Café", 200, "ml")))
        let r = try #require(hidratar(v2, remotos: [try fila("c2", 0, 1, anclado)], locales: [k: local], pendientes: [k: "swap"]))
        #expect(r.swaps[k] == local)
        #expect(r.operaciones.isEmpty)
    }

    @Test func unLegadoTampocoSeResubeSiHayAlgoPendiente() throws {
        let k = "swap_d1_c2_0_1"
        let r = try #require(hidratar(v1, remotos: [try fila("c2", 0, 1, json(food("Arroz", 80)))], pendientes: [k: "swap"]))
        #expect(r.operaciones.isEmpty)
    }

    @Test func unaReversionPendienteNoLaResucitaElRemoto() throws {
        let k = "swap_d1_c2_0_1"
        let anclado = SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("Pan lactal", 60))
        let r = try #require(hidratar(v1, remotos: [try fila("c2", 0, 1, anclado)], pendientes: [k: "swap_del"]))
        #expect(r.swaps[k] == nil)
    }

    // 3. migración y red
    @Test func sinRedNoSeTocaNada() {
        #expect(hidratar(v1, remotos: nil, locales: ["x": SwapLocal(current: .null)]) == nil)
    }

    @Test func laMigracionVaPorLaColaYNoSeMarcaHastaDrenar() throws {
        let k = "swap_d1_c2_0_1"
        let local = SwapLocal(current: SwapsDeComida.conAncla(json(food("Arroz", 80)), original: food("Pan lactal", 60)))
        let r = try #require(hidratar(v1, remotos: [], locales: [k: local]))
        #expect(r.migrando)
        #expect(r.operaciones.map(\.clave) == [k])
        #expect(r.operaciones.first?.comidaId == "c2" && r.operaciones.first?.foodIdx == 1)
        #expect(!r.marcarMigrado)
    }

    @Test func yaMigradoYBackendVacioDescartaLoLocalSalvoLoPendiente() throws {
        let local = SwapLocal(current: .objeto(["name": .texto("X")]))
        let r = try #require(hidratar(v1, remotos: [], locales: ["a": local, "b": local], pendientes: ["b": "swap"], yaMigrado: true))
        #expect(Set(r.swaps.keys) == ["b"])
    }
}
