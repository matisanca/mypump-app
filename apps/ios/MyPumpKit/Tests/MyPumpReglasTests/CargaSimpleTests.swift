import XCTest
import MyPumpModelos
@testable import MyPumpReglas

/// Prototipo de la carga simple: lo que no puede fallar (qué se registra) y dos conductas de hoy que motivan el cambio.
final class CargaSimpleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func ej(_ semanas: [(Int, String)], nombre: String = "Press banca con barra", tipo: String = "compuesto") -> Ejercicio {
        Ejercicio(id: "x", nombre: nombre, tipo: tipo, progresion: semanas.enumerated().map { Progresion(semana: $0.offset + 1, series: $0.element.0, reps: $0.element.1) })
    }
    private let refs: [CargaSimple.Referencia] = [.init(reps: 10, kg: 80), .init(reps: 10, kg: 80), .init(reps: 9, kg: 80), .init(reps: 8, kg: 80)]
    private func normal(_ g: Double = 0) -> CargaSimple {
        CargaSimple(ejercicio: ej([(4, "10"), (4, "10"), (4, "10")]), semana: 2, ultimaVez: refs, equipo: .barra, recordKg: 80, guardiaSegundos: g)
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
        XCTAssertEqual(s.confirmar(1, ahora: t0 + 3), .guardia)
        XCTAssertFalse(s.series[1].confirmada)
        XCTAssertEqual(s.confirmar(1, ahora: t0 + 4, insistio: true), .registrada)
        s.ajustarReps(2, -1)
        XCTAssertEqual(s.confirmar(2, ahora: t0 + 5), .registrada, "si tocó el dial, miró")
        XCTAssertEqual(s.confirmar(3, ahora: t0 + 120), .registrada)
    }

    func testVerosimilitudSigueMandando() {
        var s = normal()
        s.fijarCarga(700)
        guard case .preguntar = s.confirmar(0, ahora: t0) else { return XCTFail() }
        XCTAssertFalse(s.series[0].confirmada)
        XCTAssertEqual(s.confirmar(0, ahora: t0, registrarIgual: true), .registrada)
    }

    func testCorregirNoDesconfirma() {
        var s = normal()
        _ = s.confirmar(0, ahora: t0)
        s.corregir(0, reps: 12, kg: 77.5)
        XCTAssertTrue(s.series[0].confirmada)
        XCTAssertEqual(s.reps(0), 12)
        XCTAssertEqual(s.series[0].kg, 77.5)
    }

    func testVariasCargasEnUnaSesion_elPayloadEsElDeHoy() {
        var s = normal()
        _ = s.confirmar(0, ahora: t0)
        let p = EscriturasEntreno.carga(sesionId: nil, dia: "d", semana: 2, ejercicio: "x", indice: 0, serie: s.serieLocal(0, rir: "0"), nombre: "Press", varianteEjercicio: nil)
        guard case let .objeto(o) = p, case let .objeto(d)? = o["datos"] else { return XCTFail() }
        XCTAssertEqual(d["peso"], .numero(80))
        XCTAssertEqual(d["reps"], .numero(10))
        XCTAssertEqual(d["rir"], .numero(0))
        XCTAssertEqual(d["serie"], .numero(1))
    }

    func testGuardia_sumarYRestarLoMismoNoCuentaComoMirar() {
        var s = normal(10)
        _ = s.confirmar(0, ahora: t0)
        s.ajustarReps(1, 1); s.ajustarReps(1, -1)
        XCTAssertEqual(s.confirmar(1, ahora: t0 + 3), .guardia)
    }

    func testVariante_lasHechasNoSeMezclan() {
        var s = normal()
        s.varianteActual = "Prono"
        _ = s.confirmar(0, ahora: t0)
        s.varianteActual = "Supino"
        s.moverCarga(1)
        XCTAssertEqual(s.hechasConOtraCarga, 0)
        XCTAssertEqual(s.aplicarCargaALasHechas(), [])
        XCTAssertEqual(s.serieLocal(0, rir: "0").varianteRegistrada, "Prono")
    }

    func testCambiarlasTambienSeVaAlConfirmarLaSiguiente() {
        var s = normal()
        _ = s.confirmar(0, ahora: t0)
        s.moverCarga(-1)
        XCTAssertEqual(s.hechasConOtraCarga, 1)
        _ = s.confirmar(1, ahora: t0 + 100)
        XCTAssertEqual(s.hechasConOtraCarga, 0, "bajar por fatiga no ofrece reescribir lo anterior")
    }

    func testDeshacerVuelveALaCargaActual() {
        var s = normal()
        _ = s.confirmar(0, ahora: t0)
        s.moverCarga(1)
        s.deshacer(0)
        XCTAssertEqual(s.series[0].kg, 82.5)
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

    // MARK: Conductas de hoy que motivan el cambio

    /// Hoy: subiste en la serie 1 y tocás ✓ en la 2 sin escribir: se graba el kg de la semana pasada.
    func testHoy_tildeSinEscribirGrabaElKgViejoAunqueHayasSubido() {
        let (s, lista) = ConfirmacionSerie.completar(SerieLocal(), sinKg: false, repsPlan: "10", kgUltimaVez: "80", repsUltimaVez: "10", kgHeredable: "82.5")
        XCTAssertTrue(lista)
        XCTAssertEqual(s.kg, "80")
    }

    /// Hoy: escribir solo las reps en la serie 1 no alcanza: hay que escribir también el kilo.
    func testHoy_soloRepsEnLaPrimeraNoDejaConfirmar() {
        let f = FilaSerie.armar(SerieLocal(reps: "11"), activa: true, sinKg: false, repsPlan: "10", kgUltimaVez: "80", repsUltimaVez: "10", kgHeredable: "")
        XCTAssertFalse(f.puedeConfirmar)
    }
}
