import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

@Suite("Comida libre: el mismo re-escalado y validación que la web")
struct ComidaLibreNuevaTests {
    let estimacion = EstimacionPlato(
        descripcion: "Milanesa con puré", escala: "plato de 26 cm",
        alimentos: [.init(nombre: "Milanesa de carne", gramos: 205, kcal: 451, prot: 36.9, carb: 22.6, fat: 23.4),
                    .init(nombre: "Puré de papa", gramos: 180.4, kcal: 158, prot: 3.4, carb: 27.2, fat: 4.1)],
        kcal: 609, prot: 40.3, carb: 49.8, fat: 27.5, confianza: "media")

    @Test func lasBasesSonPorGramoYLosGramosInicialesRedondeados() {
        let b = ComidaLibreNueva.bases(estimacion)
        #expect(b.count == 2)
        #expect(b[1].gramosIniciales == 180)
        #expect(b[0].kcal == 451.0 / 205)
    }

    @Test func corregirGramosReEscalaLosTotales() {
        let b = ComidaLibreNueva.bases(estimacion)
        // Sin tocar: los mismos totales (con los gramos sin redondear de la IA se escala por 180, el redondeado).
        let g = ComidaLibreNueva.gramos(b, escritos: [nil, nil])
        #expect(g == [205, 180])
        // 205 → 260 g de milanesa.
        let t = ComidaLibreNueva.totales(b, gramos: ComidaLibreNueva.gramos(b, escritos: [260, nil]))
        #expect(t.kcal == 730)                 // 451/205·260 + 158/180.4·180 = 572,0 + 157,6
        #expect(t.prot == 50.2)                // 46,8 + 3,39
        #expect(t.fat == 33.8)
    }

    @Test func unGramajeIlegibleVuelveAlInicial() {
        let b = ComidaLibreNueva.bases(estimacion)
        #expect(ComidaLibreNueva.gramos(b, escritos: [-3, .nan]) == [205, 180])
    }

    @Test func elDetalleGuardaLosGramosCorregidos() throws {
        let b = ComidaLibreNueva.bases(estimacion)
        let d = try #require(ComidaLibreNueva.detalle(b, gramos: [260, 180], confianza: "media", escala: nil))
        guard case .lista(let alimentos)? = d["alimentos"] else { Issue.record("sin alimentos"); return }
        #expect(alimentos[0]["gramos"] == .numero(260))
        #expect(alimentos[0]["kcal"] == .numero(572))
        #expect(d["confianza"] == .texto("media"))
        #expect(d["escala"] == .null)
        #expect(ComidaLibreNueva.detalle([], gramos: [], confianza: nil, escala: nil) == nil)
    }

    @Test func validacion() {
        #expect(ComidaLibreNueva.preparar(descripcion: "  ", hora: nil, kcal: 300, prot: nil, carb: nil, fat: nil, detalle: nil)
                == .failure(ErrorFormulario("Contá qué comiste.")))
        #expect(ComidaLibreNueva.preparar(descripcion: "Alfajor", hora: "", kcal: 0, prot: -2, carb: nil, fat: nil, detalle: nil)
                == .failure(ErrorFormulario("Cargá al menos las calorías o algún macro.")))
        let ok = try? ComidaLibreNueva.preparar(descripcion: " Alfajor ", hora: "", kcal: 250, prot: nil, carb: 35, fat: 11, detalle: nil).get()
        #expect(ok?.descripcion == "Alfajor" && ok?.hora == nil && ok?.prot == 0 && ok?.carb == 35)
    }

    @Test func fechaYHoraLocales() {
        let d = Date(timeIntervalSince1970: 1_791_950_000) // 2026-10-14 03:53 UTC
        let ar = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        #expect(FechaLocal.hoy(d, zona: ar) == "2026-10-14")
        #expect(FechaLocal.hoy(d, zona: TimeZone(identifier: "America/Los_Angeles")!) == "2026-10-13")
        #expect(ComidaLibreNueva.hora(d, zona: ar) == "00:53")
    }
}
