import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

@Suite("Dieta: días que se pueden cargar y copiar a hoy")
struct DiasDietaTests {
    @Test func seleccionablesHoyYSieteAtras() {
        let f = DiasDieta.seleccionables(hoy: "2026-11-09", hoyServidor: "2026-11-09")
        #expect(f.count == 8 && f.first == "2026-11-09" && f.last == "2026-11-02")
    }

    @Test func unTelefonoAtrasadoNoOfreceUnDiaQueLaBaseRechaza() {
        // En Argentina ya es el 10: el 2 quedó afuera de −7.
        let f = DiasDieta.seleccionables(hoy: "2026-11-09", hoyServidor: "2026-11-10")
        #expect(f.first == "2026-11-09" && f.last == "2026-11-03")
    }

    @Test func cruzaElMesYElAnio() {
        #expect(DiasDieta.sumar("2026-01-02", dias: -3) == "2025-12-30")
        #expect(DiasDieta.sumar("2026-03-01", dias: -1) == "2026-02-28")
    }

    @Test func ventanaDeMarcar() {
        #expect(DiasDieta.permiteMarcar("2026-11-07", hoyServidor: "2026-11-09", dias: 2))
        #expect(!DiasDieta.permiteMarcar("2026-11-06", hoyServidor: "2026-11-09", dias: 2))
        #expect(DiasDieta.permiteMarcar("2026-11-02", hoyServidor: "2026-11-09", dias: 7))
        #expect(!DiasDieta.permiteMarcar("2026-11-10", hoyServidor: "2026-11-09", dias: 7))
    }

    @Test func rotulos() {
        #expect(DiasDieta.rotuloCorto("2026-11-09", hoy: "2026-11-09") == "Hoy")
        #expect(DiasDieta.rotuloCorto("2026-11-08", hoy: "2026-11-09") == "Ayer")
        #expect(DiasDieta.rotuloCorto("2026-11-07", hoy: "2026-11-09") == "Sáb 7")
        #expect(DiasDieta.rotuloLargo("2026-11-07") == "sábado 7 de noviembre")
    }

    // MARK: - Copia

    private func comida(_ id: String, opciones: [String] = ["A", "B"], alimentos: Int = 2) -> Comida {
        let ops = opciones.map { o -> [String: Any] in
            ["name": o, "foods": (0..<alimentos).map { ["name": "x\($0)", "qty": 100, "unit": "g", "kcal": 100, "prot": 10, "carb": 10, "fat": 1] as [String: Any] }]
        }
        let data = try! JSONSerialization.data(withJSONObject: ["id": id, "name": id, "options": ops] as [String: Any])
        return try! JSONDecoder().decode(Comida.self, from: data)
    }

    private func libre(_ id: String, _ desc: String, _ kcal: Double) -> ComidaLibre {
        let data = try! JSONSerialization.data(withJSONObject: ["id": id, "descripcion": desc, "kcal": kcal] as [String: Any])
        return try! JSONDecoder().decode(ComidaLibre.self, from: data)
    }

    private func plan(_ c: [Comida], om: [String: MarcaComida] = [:], oa: [String: AjusteComida] = [:], ol: [ComidaLibre] = [],
                      hm: [String: MarcaComida] = [:], ha: [String: AjusteComida] = [:], hl: [ComidaLibre] = [], otro: Bool = false) -> CopiaDeComidas.Plan {
        CopiaDeComidas.plan(comidas: c, origenMarcas: om, origenAjustes: oa, origenLibres: ol, hoyMarcas: hm, hoyAjustes: ha, hoyLibres: hl, otroPlan: otro) { _, _, _, _ in 500 }
    }

    @Test func seCopiaLoComidoNoLoSalteadoNiLoOmitido() {
        let c = [comida("d"), comida("a"), comida("m")]
        let p = plan(c, om: ["d": MarcaComida(opcion: "B", estado: .comido, excluidos: [1]), "a": MarcaComida(opcion: "A", estado: .saltado)],
                     oa: ["m": AjusteComida(omitida: true)])
        #expect(p.comidas.map(\.comidaId) == ["d"])
        #expect(p.comidas[0].opcion == 1 && p.comidas[0].marca?.excluidos == [1] && p.comidas[0].estado == .nueva)
    }

    @Test func soloAjusteSinMarcaTambienSeOfrece() {
        let a = AjusteComida(deltaKcal: 50, opcion: 1, agregados: [])
        let p = plan([comida("d")], oa: ["d": a])
        #expect(p.comidas.count == 1 && p.comidas[0].marca == nil && p.comidas[0].ajuste == a && p.comidas[0].opcion == 1)
    }

    @Test func loQueHoyTieneAlgoEsConflictoYLoIgualNoSeRepite() {
        let m = MarcaComida(opcion: "A", estado: .comido)
        let c = [comida("d"), comida("a")]
        let p = plan(c, om: ["d": m, "a": m], hm: ["d": m, "a": MarcaComida(opcion: "B", estado: .comido)])
        #expect(p.comidas.first { $0.comidaId == "d" }?.estado == .igual)
        #expect(p.comidas.first { $0.comidaId == "a" }?.estado == .conflicto)
    }

    @Test func unaOpcionQueYaNoExisteNoSeCopia() {
        let p = plan([comida("d", opciones: ["A"])], om: ["d": MarcaComida(opcion: "Vieja", estado: .comido)])
        #expect(p.comidas.isEmpty)
    }

    @Test func tildesFueraDeRangoSeCaen() {
        let p = plan([comida("d", alimentos: 2)], om: ["d": MarcaComida(opcion: "A", estado: .comido, excluidos: [1, 7])])
        #expect(p.comidas[0].marca?.excluidos == [1])
    }

    @Test func libresRepetidasNoSeDuplican() {
        let p = plan([], ol: [libre("1", "Pizza ", 800), libre("2", "Helado", 300)], hl: [libre("9", "pizza", 800.2)])
        #expect(p.libres.map(\.estado) == [.igual, .nueva])
    }

    @Test func conOtroPlanSoloLibres() {
        let p = plan([comida("d")], om: ["d": MarcaComida(opcion: "A", estado: .comido)], ol: [libre("1", "Pizza", 800)], otro: true)
        #expect(p.comidas.isEmpty && p.libres.count == 1 && p.otroPlan)
    }
}
