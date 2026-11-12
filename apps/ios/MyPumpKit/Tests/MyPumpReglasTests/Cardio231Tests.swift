import XCTest
import MyPumpModelos
@testable import MyPumpReglas

/// 2.3.1 (auditoría de llamadas, falla 3): el slug de cinta gana sobre el tipo, y el cardio con una progresión por
/// tiempo no arma filas aunque el plan traiga `series`. Los mismos casos que test-cardio.mjs (web) y Cardio231Test.kt.
final class Cardio231Tests: XCTestCase {
    func testElSlugDeCardioGanaSobreElTipo() {
        XCTAssertTrue(ReglasEjercicio.esCardio(nombre: "Cinta", tipo: "compuesto", slugs: ["walking_treadmill"]))
        XCTAssertTrue(ReglasEjercicio.esCardio(nombre: "Lo que sea", tipo: "accesorio", slugs: [nil, "Elliptical_Trainer"]))
        XCTAssertFalse(ReglasEjercicio.esCardio(nombre: "Cinta", tipo: "compuesto", slugs: []), "el nombre solo respeta el tipo")
        XCTAssertTrue(ReglasEjercicio.esCardio(nombre: "Cinta", tipo: "calentamiento", slugs: []))
        XCTAssertFalse(ReglasEjercicio.esCardio(nombre: "Press banca", tipo: "compuesto", slugs: ["bench_press"]))
    }

    func testRepsQueSonTiempo() {
        for r in ["10 min", "10min", "20'", "30 s", "45 seg", "1 h", "15-20 min", "12 minutos", "8,5 min"] {
            XCTAssertTrue(ReglasEjercicio.repsEsTiempo(r), r)
        }
        for r in ["12", "8-10", "6 × 30 s / 30 s", "AMRAP", "", "10 reps"] { XCTAssertFalse(ReglasEjercicio.repsEsTiempo(r), r) }
        XCTAssertFalse(ReglasEjercicio.repsEsTiempo(nil))
    }

    func testLaCintaConProgresionPorTiempoNoArmaFilas() {
        let cinta = Ejercicio(id: "c", nombre: "Cinta", tipo: "cardio",
                              progresion: [Progresion(semana: 1, series: 1, reps: "10 min"), Progresion(semana: 2, series: 3, reps: "12 min", rir: "1")])
        XCTAssertEqual(Progresiones.pauta(cinta, semana: 2), Pauta(series: nil, reps: "12 min", rir: nil))
        var comoCompuesto = cinta; comoCompuesto.tipo = "compuesto"; comoCompuesto.catalogoSlug = "Walking_Treadmill"
        XCTAssertEqual(Progresiones.pauta(comoCompuesto, semana: 1).series, nil)
        let intervalos = Ejercicio(id: "b", nombre: "Bici", tipo: "cardio", progresion: [Progresion(semana: 1, series: 6, reps: "6 × 30 s / 30 s")])
        XCTAssertEqual(Progresiones.pauta(intervalos, semana: 1).series, 6, "los intervalos siguen con las series del plan")
        let plancha = Ejercicio(id: "p", nombre: "Plancha", tipo: "core", progresion: [Progresion(semana: 1, series: 3, reps: "30 s")])
        XCTAssertEqual(Progresiones.pauta(plancha, semana: 1).series, 3, "la plancha por tiempo sigue con series")
    }
}
