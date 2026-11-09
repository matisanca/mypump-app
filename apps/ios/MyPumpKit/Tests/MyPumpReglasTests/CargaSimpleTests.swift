import XCTest
import MyPumpModelos
@testable import MyPumpReglas

/// La carga simple: lo que no puede fallar (qué se registra). Las series se confirman acá con el mismo efecto que el día en
/// curso: lo del OK de verdad (cola, deshacer, persistencia) lo prueban `CargaSimpleModeloTests`.
final class CargaSimpleTests: XCTestCase {
    private let t0 = 1_800_000_000_000.0

    private func ej(_ semanas: [(Int, String)], nombre: String = "Press banca con barra", tipo: String = "compuesto") -> Ejercicio {
        Ejercicio(id: "x", nombre: nombre, tipo: tipo, progresion: semanas.enumerated().map { Progresion(semana: $0.offset + 1, series: $0.element.0, reps: $0.element.1) })
    }
    private let refs: [CargaSimple.Referencia] = [.init(reps: 10, kg: 80), .init(reps: 10, kg: 80), .init(reps: 9, kg: 80), .init(reps: 8, kg: 80)]
    private func normal(_ g: Double = 0) -> CargaSimple {
        CargaSimple(ejercicio: ej([(4, "10"), (4, "10"), (4, "10")]), semana: 2, ultimaVez: refs, equipo: .barra, recordKg: 80, guardiaMs: g * 1000)
    }

    func testBase_laVezPasadaPorSerie() {
        let s = normal()
        XCTAssertEqual(s.carga, 80)
        XCTAssertEqual((0..<4).map { s.reps($0) }, [10, 10, 9, 8])
        XCTAssertEqual(s.base(2).origen, .ultimaVez)
    }

    func testCargaUnica_sinVolverACargarla() {
        var s = normal()
        s.moverCarga(1)
        for i in 0..<4 { XCTAssertEqual(s.confirmar(i, ahora: t0), .registrada) }
        XCTAssertEqual(s.series.map(\.kg), [82.5, 82.5, 82.5, 82.5])
    }

    func testConOtraCarga_lasRepsVuelvenAlPlan() {
        var s = normal()
        s.moverCarga(1)
        XCTAssertEqual((0..<4).map { s.reps($0) }, [10, 10, 10, 10])
        XCTAssertEqual(s.base(3).origen, .plan)
    }

    func testSubirNoReescribeLasHechas() {
        var s = normal()
        _ = s.confirmar(0, ahora: t0)
        s.moverCarga(1)
        XCTAssertEqual(s.series[0].kg, 80)
        XCTAssertEqual(s.series[1].kg, 82.5)
        XCTAssertEqual(s.hechasConOtraCarga, 1)
        XCTAssertEqual(s.aplicarCargaALasHechas(), [0])
        XCTAssertEqual(s.series[0].kg, 82.5)
    }

    func testLoMarcadoNoSePisaAlCambiarCarga() {
        var s = normal()
        s.ajustarReps(0, 2)
        s.moverCarga(1)
        XCTAssertEqual(s.reps(0), 12)
    }

    func testMasRepsQueElPlanSiempreVale() {
        var s = normal()
        s.ajustarReps(0, 6)
        XCTAssertEqual(s.confirmar(0, ahora: t0), .registrada)
        XCTAssertEqual(s.reps(0), 16)
    }

    func testAumentoSoloSiElPlanBajaLasRepsYNuncaEnCalibracion() {
        let baja = CargaSimple(ejercicio: ej([(4, "10"), (4, "8")]), semana: 2, ultimaVez: refs, equipo: .barra)
        XCTAssertEqual(baja.aumento, .sugerido(desde: 80, hasta: 82.5))
        XCTAssertEqual(baja.carga, 80, "sugerido: no sube solo")
        XCTAssertEqual(CargaSimple(ejercicio: ej([(4, "10"), (4, "10")]), semana: 2, ultimaVez: refs, equipo: .barra).aumento, .noCorresponde)
        XCTAssertEqual(CargaSimple(ejercicio: ej([(4, "10"), (4, "8")]), semana: 1, ultimaVez: refs, equipo: .barra).aumento, .noCorresponde)
        XCTAssertEqual(CargaSimple(ejercicio: ej([(3, "10"), (4, "8")]), semana: 2, ultimaVez: refs, equipo: .barra).aumento, .noCorresponde)
    }

    func testPasoSegunEquipo() {
        XCTAssertEqual(AumentoCarga.mover(80, pasos: 1, equipo: .barra), 82.5)
        XCTAssertEqual(AumentoCarga.mover(60, pasos: 1, equipo: .maquina), 65)
        XCTAssertEqual(AumentoCarga.mover(21, pasos: 1, equipo: .mancuerna), 22)
        XCTAssertEqual(AumentoCarga.mover(8, pasos: -1, equipo: .mancuerna), 7)
    }

    func testModa_unaSerieConMenosNoCorreLaBase() {
        XCTAssertEqual(AumentoCarga.moda([80, 80, 80, 75]), 80)
        XCTAssertEqual(AumentoCarga.moda([80, 75]), 80)
        var s = CargaSimple(ejercicio: ej([(4, "10"), (4, "10")]), semana: 2,
                            ultimaVez: [.init(reps: 10, kg: 60), .init(reps: 10, kg: 60), .init(reps: 9, kg: 60), .init(reps: 10, kg: 55)], equipo: .maquina)
        XCTAssertEqual(s.series.map(\.kg), [60, 60, 60, 60])
        s.usarMismoPeso(false)
        XCTAssertEqual(s.series.map(\.kg), [60, 60, 60, 55])
    }

    func testPrimeraVez_sinCargaNoHayOK() {
        var s = CargaSimple(ejercicio: ej([(3, "10-12")]), semana: 1, ultimaVez: [], equipo: .barra)
        XCTAssertFalse(s.puedeConfirmar(0))
        s.fijarCarga(60)
        XCTAssertEqual(s.reps(0), 12)
        XCTAssertTrue(s.puedeConfirmar(0))
    }

    func testAMRAP_hayQueMarcar() {
        var s = CargaSimple(ejercicio: ej([(3, "máx"), (3, "máx")], nombre: "Lagartijas"), semana: 2,
                            ultimaVez: [.init(reps: 20, kg: nil)], equipo: .otro)
        XCTAssertTrue(s.sinKg)
        XCTAssertFalse(s.puedeConfirmar(0))
        s.ajustarReps(0, 1)
        XCTAssertEqual(s.reps(0), 21)
        XCTAssertTrue(s.puedeConfirmar(0))
    }

    func testGuardia_rafagaSinTocarPideOtroToque() {
        var s = normal(10)
        XCTAssertEqual(s.confirmar(0, ahora: t0), .registrada)
        XCTAssertEqual(s.confirmar(1, ahora: t0 + 3000), .guardia)
        XCTAssertFalse(s.series[1].confirmada)
        XCTAssertEqual(s.confirmar(1, ahora: t0 + 4000, insistio: true), .registrada)
        s.ajustarReps(2, -1)
        XCTAssertEqual(s.confirmar(2, ahora: t0 + 5000), .registrada, "si tocó el dial, miró")
        XCTAssertEqual(s.confirmar(3, ahora: t0 + 120000), .registrada)
    }

    func testGuardia_sumarYRestarLoMismoNoCuentaComoMirar() {
        var s = normal(10)
        _ = s.confirmar(0, ahora: t0)
        s.ajustarReps(1, 1); s.ajustarReps(1, -1)
        XCTAssertEqual(s.confirmar(1, ahora: t0 + 3000), .guardia)
    }

    func testVariante_lasHechasNoSeMezclan() {
        var s = normal()
        s.varianteActual = "Prono"
        _ = s.confirmar(0, ahora: t0)
        s.varianteActual = "Supino"
        s.moverCarga(1)
        XCTAssertEqual(s.hechasConOtraCarga, 0)
        XCTAssertEqual(s.aplicarCargaALasHechas(), [])
        XCTAssertEqual(s.series[0].variante, "Prono")
    }

    func testCambiarlasTambienSeVaAlConfirmarLaSiguiente() {
        var s = normal()
        _ = s.confirmar(0, ahora: t0)
        s.moverCarga(-1)
        XCTAssertEqual(s.hechasConOtraCarga, 1)
        _ = s.confirmar(1, ahora: t0 + 100000)
        XCTAssertEqual(s.hechasConOtraCarga, 0, "bajar por fatiga no ofrece reescribir lo anterior")
    }

    func testAumentoSeInvalidaSiLaCargaCambioAMano() {
        var s = CargaSimple(ejercicio: ej([(4, "10"), (4, "8")]), semana: 2, ultimaVez: refs, equipo: .barra)
        s.moverCarga(2)
        XCTAssertEqual(s.aumento, .descartado)
        XCTAssertEqual(s.carga, 85)
    }

    func testAumentoConPesoPorSerieSubeLasQueFaltan() {
        var s = CargaSimple(ejercicio: ej([(4, "10"), (4, "8")]), semana: 2, ultimaVez: refs, equipo: .barra)
        s.usarMismoPeso(false)
        s.aceptarAumento()
        XCTAssertEqual(s.series.map(\.kg), [82.5, 82.5, 82.5, 82.5])
    }

    func testRetildarSinCargaTomaLaPrimeraConPeso() {
        var s = CargaSimple(ejercicio: ej([(2, "10")]), semana: 1, ultimaVez: [], equipo: .barra)
        s.usarMismoPeso(false)
        s.fijarKg(0, 50)
        s.usarMismoPeso(true)
        XCTAssertEqual(s.carga, 50)
        XCTAssertEqual(s.series.map(\.kg), [50, 50])
    }

    func testModaIgnoraCeros() { XCTAssertEqual(AumentoCarga.moda([0, 0, 40]), 40) }

}

private enum R: Equatable { case registrada, guardia, faltanDatos }

private extension CargaSimple {
    /// El OK de la serie: lo que evalúa y lo que el día en curso deja en la serie al registrarla.
    mutating func confirmar(_ i: Int, ahora: Double, insistio: Bool = false) -> R {
        switch evaluarOK(i, ahora: ahora, insistio: insistio) {
        case .faltanDatos: return .faltanDatos
        case .guardia: return .guardia
        case let .lista(reps, kg):
            series[i].reps = reps
            series[i].kg = kg
            series[i].confirmada = true
            series[i].variante = varianteActual
            anotarOK(ahora: ahora)
            return .registrada
        }
    }
}
