import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La carga simple contra la cola y el disco de verdad: lo que no puede perderse ni falsearse.
@Suite("Carga simple: OK, Deshacer y persistencia", .serialized)
@MainActor
struct CargaSimpleModeloTests {
    let lugar = "pre-d1-0"
    let hoy = "2026-10-14"

    func rutina(rir: String = "2", semana: Int = 2, reps2: String = "8") -> RutinaActiva {
        let est = #"{"semanas_total":12,"dias":[{"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"B1","ejercicios":[{"id":"pre-d1-0","nombre":"Press banca con barra","tipo":"compuesto","descanso_segundos":120,"progresion":[{"semana":1,"series":4,"reps":"10","rir":"\#(rir)"},{"semana":2,"series":4,"reps":"\#(reps2)","rir":"\#(rir)"}]}]}]}]}"#
        return try! JSONDecoder().decode(RutinaActiva.self, from: Data(#"{"id":"r1","version":1,"semana_actual":\#(semana),"tiene_siguiente":false,"estructura":\#(est)}"#.utf8))
    }

    /// 80 kg × 10 hace una semana; opcionalmente una fila de HOY (la que el historial trae al recargar).
    func historial(_ b: Banco, hoyKg: Double? = nil) {
        var f = (1...4).map { #"{"clave":"\#(ClaveEjercicio.de("Press banca con barra"))","registrado_en":"2026-10-07T18:00:00Z","peso_kg":80,"reps_realizadas":10,"rir_real":0,"serie_numero":\#($0),"notas":null,"ejercicio_nombre":"Press banca con barra"}"# }
        if let hoyKg { f.insert(#"{"clave":"\#(ClaveEjercicio.de("Press banca con barra"))","registrado_en":"2026-10-14T17:00:00Z","peso_kg":\#(hoyKg),"reps_realizadas":8,"rir_real":0,"serie_numero":1,"notas":null,"ejercicio_nombre":"Press banca con barra"}"#, at: 0) }
        b.servidor.cuando("get_historico_por_clave", "[\(f.joined(separator: ","))]")
    }

    func modelo(_ b: Banco, rutina r: RutinaActiva? = nil) async -> ModeloEntreno {
        let m = b.modelo(r ?? rutina())
        await m.cargar()
        return m
    }

    func cargasEnCola(_ b: Banco) async -> [JSONValue] {
        await b.cola.operaciones.filter { $0.kind == "carga" }.map { $0.payload }
    }

    func ok(_ m: ModeloEntreno, _ i: Int) async -> ModeloEntreno.ResultadoOK { await m.okSerie(lugar, i, venceEn: nil) { _ in true } }

    @Test func okDentroDeLaVentanaNoSaleHastaQueVence() async {
        let b = Banco(); historial(b)
        let m = await modelo(b)
        #expect(await ok(m, 0) == .registrada)
        #expect(m.dia.ejercicios[lugar]?.series[0].confirmada == true)
        #expect(m.dia.ejercicios[lugar]?.series[0].kg == "80")
        #expect(await cargasEnCola(b).isEmpty, "todavía se puede deshacer")
        await m.vaciarDeshacer()
        #expect(await cargasEnCola(b).count == 1)
    }

    @Test func deshacerEsDeVerdad_noEscribeYAlRecargarNoVuelve() async {
        let b = Banco(); historial(b)
        let m = await modelo(b)
        _ = await ok(m, 0)
        m.deshacerOK()
        #expect(m.dia.ejercicios[lugar]?.series[0].confirmada == false)
        #expect(m.dia.ejercicios[lugar]?.series[0].reps == "")
        #expect(m.descanso.visible == false)
        await m.vaciarDeshacer()
        #expect(await cargasEnCola(b).isEmpty, "deshecha no se registra")
        b.servidor.cuando("get_sesion_dia", sesionJSON("s1", semana: 2))
        await m.restaurarSesion()
        #expect(m.dia.ejercicios[lugar]?.series[0].confirmada == false, "no vuelve como fantasma")
    }

    @Test func deshacerLaUltimaSerieNoDejaElEjercicioCompleto() async {
        let b = Banco(); historial(b)
        let m = await modelo(b, rutina: rutina())
        for i in 0..<3 { _ = await ok(m, i); await m.vaciarDeshacer(); b.reloj.ms += 120_000 }
        _ = await ok(m, 3)
        #expect(m.dia.estado(lugar) == "completo")
        m.deshacerOK()
        #expect(m.dia.estado(lugar) == "pendiente" && m.dia.ejercicios[lugar]?.completo == false)
        let estados = await b.cola.operaciones.filter { $0.kind == "estado" }
        #expect(estados.isEmpty, "el «completo» no llegó a salir")
    }

    @Test func siLaAppMuereEnLaVentanaLaSerieNoSePierde() async {
        let b = Banco(); historial(b)
        let m = await modelo(b)
        _ = await ok(m, 0)
        // Relanzar: otro modelo con el mismo disco; el OK estaba demorado.
        let m2 = await modelo(b)
        #expect(await cargasEnCola(b).count == 1, "se recupera del disco")
        #expect(m2.dia.ejercicios[lugar]?.series[0].confirmada == true)
        // Y al abrir de nuevo no se manda dos veces.
        let m3 = await modelo(b)
        #expect(await cargasEnCola(b).count == 1)
        _ = m3
    }

    @Test func relanzarTrasAceptarNoVuelveASugerir() async {
        let b = Banco(); historial(b)
        let m = await modelo(b)
        #expect(m.cargaSimple(lugar)?.aumento == .sugerido(desde: 80, hasta: 82.5))
        m.cambiarCarga(lugar) { $0.aceptarAumento() }
        #expect(m.cargaSimple(lugar)?.carga == 82.5)
        // Al recargar, el historial trae también lo de hoy: no puede sugerir 85.
        historial(b, hoyKg: 82.5)
        let m2 = await modelo(b)
        #expect(m2.cargaSimple(lugar)?.aumento == .aceptado(desde: 80, hasta: 82.5))
        #expect(m2.cargaSimple(lugar)?.carga == 82.5)
    }

    @Test func dejarLaSugerenciaTampocoVuelveAlRelanzar() async {
        let b = Banco(); historial(b)
        let m = await modelo(b)
        m.cambiarCarga(lugar) { $0.descartarAumento() }
        let m2 = await modelo(b)
        #expect(m2.cargaSimple(lugar)?.aumento == .descartado)
        #expect(m2.cargaSimple(lugar)?.carga == 80)
    }

    @Test func aMedioEjercicioNoSePierdeNada() async {
        let b = Banco(); historial(b)
        let m = await modelo(b, rutina: rutina(reps2: "10"))
        m.cambiarCarga(lugar) { $0.moverCarga(1); $0.ajustarReps(1, 2); $0.usarMismoPeso(false); $0.fijarKg(2, 75) }
        let m2 = await modelo(b, rutina: rutina(reps2: "10"))
        let c = m2.cargaSimple(lugar)
        #expect(c?.carga == 82.5 && c?.mismoPeso == false)
        #expect(c?.reps(1) == 12)
        #expect(c?.series[2].kg == 75)
    }

    @Test func laSemanaQueVieneNoHeredaLoDeEsta() async {
        let b = Banco(); historial(b)
        let m = await modelo(b)
        m.cambiarCarga(lugar) { $0.aceptarAumento() }
        let m2 = await modelo(b, rutina: rutina(semana: 3))
        #expect(m2.dia.cargas[lugar] == nil)
    }

    @Test func elMismoEjercicioNoSubeDosVecesEnLaSemana() async {
        let b = Banco(); historial(b)
        let m = await modelo(b)
        m.cambiarCarga(lugar) { $0.aceptarAumento() }
        // Otro lugar con el mismo ejercicio en la misma semana: ya subió.
        m.dia.cargas[lugar] = nil
        #expect(m.dia.aumentosSemana.contains(m.dia.claveAumento(lugar)))
        #expect(m.cargaSimple(lugar)?.aumento == .noCorresponde)
    }

    @Test func subirNoReescribeLoHechoYLaSiguienteVaConLaNueva() async {
        let b = Banco(); historial(b)
        let m = await modelo(b, rutina: rutina(reps2: "10"))
        _ = await ok(m, 0)
        b.reloj.ms += 120_000
        m.cambiarCarga(lugar) { $0.moverCarga(1) }
        _ = await ok(m, 1)
        await m.vaciarDeshacer()
        let pesos = await cargasEnCola(b).compactMap { $0["datos"]?["peso"]?.comoNumero }
        #expect(pesos == [80, 82.5])
    }

    @Test func guardia_elOKApuradoPideOtroToqueSinFrenarElDescanso() async {
        let b = Banco(); historial(b)
        let m = await modelo(b, rutina: rutina(reps2: "10"))
        _ = await ok(m, 0)
        b.reloj.ms += 3_000
        #expect(await ok(m, 1) == .guardia)
        #expect(m.dia.ejercicios[lugar]?.series[1].confirmada == false)
        #expect(m.descanso.visible, "el descanso sigue corriendo")
        b.reloj.ms += 300
        #expect(await ok(m, 1) == .guardia, "un doble toque no la vence")
        b.reloj.ms += 900
        #expect(await ok(m, 1) == .registrada)
        // A los 10 s o después, sin guardia.
        await m.vaciarDeshacer()
        b.reloj.ms += 10_000
        #expect(await ok(m, 2) == .registrada)
    }

    @Test func noRegistradaNoQuedaComoSiLaHubieraTipeado() async {
        let b = Banco(); historial(b)
        let m = await modelo(b, rutina: rutina(reps2: "10"))
        m.cambiarCarga(lugar) { $0.fijarCarga(9000) }
        #expect(await ok(m, 0) == .noRegistrada)
        let s = m.dia.ejercicios[lugar]?.series[0]
        #expect(s?.confirmada == false && s?.reps == "" && s?.kg == "" && s?.aviso?.isEmpty == false)
    }

    @Test func elRIRDelPlanNuncaSeCopia() async {
        let b = Banco(); historial(b)
        let m = await modelo(b, rutina: rutina(rir: "2-3"))
        _ = await ok(m, 0)
        await m.vaciarDeshacer()
        #expect(await cargasEnCola(b).first?["datos"]?["rir"] == .numero(0))
    }

    @Test func corregirReescribeEsaSerieSinDesmarcarla() async {
        let b = Banco(); historial(b)
        let m = await modelo(b, rutina: rutina(reps2: "10"))
        _ = await ok(m, 0)
        await m.vaciarDeshacer()
        let antes = await cargasEnCola(b).count
        await m.editarSerie(lugar, 0)
        #expect(m.corrigiendo == .init(lugar: lugar, indice: 0))
        #expect(m.dia.ejercicios[lugar]?.series[0].confirmada == true)
        #expect(await m.guardarCorreccion(reps: 10, kg: 80) { _ in true } == .sinCambios, "sin cambios no escribe")
        #expect(await cargasEnCola(b).count == antes)
        await m.editarSerie(lugar, 0)
        #expect(await m.guardarCorreccion(reps: 12, kg: 77.5) { _ in true } == .guardada)
        let filas = await cargasEnCola(b)
        #expect(filas.count == antes, "misma clave de cola: la reemplaza")
        #expect(filas.last?["datos"]?["reps"] == .numero(12) && filas.last?["datos"]?["peso"] == .numero(77.5))
        #expect(m.dia.ejercicios[lugar]?.series[0].confirmada == true && m.corrigiendo == nil)
    }

    @Test func cerrarElDiaManda_loDemoradoAntes() async {
        let b = Banco(ejecutar: true); historial(b)
        b.servidor.cuando("registrar_carga", "null")
        b.servidor.cuando("get_sesion_dia", sesionJSON("s1", semana: 2))
        let m = await modelo(b)
        _ = await ok(m, 0)
        _ = await m.cerrarDia(notas: "")
        #expect(b.servidor.llamadas("registrar_carga").count == 1)
    }

    @Test func laPreparacionUsaLaCargaYNoEsUnaSerie() async {
        let b = Banco(); historial(b)
        let m = await modelo(b, rutina: rutina(reps2: "10"))
        m.cambiarCarga(lugar) { $0.moverCarga(1) }
        let series = m.preparacion(lugar)
        #expect(!series.isEmpty)
        #expect(series.allSatisfy { ($0.kg ?? 0) < 82.5 }, "la preparación no hereda la carga como serie")
        #expect(m.dia.ejercicios[lugar]?.series.count == 4, "no suma series efectivas")
    }

    @Test func sinHistorialTodaviaLaCargaNoQuedaVacia() async {
        let b = Banco()
        let m = await modelo(b, rutina: rutina(reps2: "10"))
        m.cambiarCarga(lugar) { $0.ajustarReps(0, 1) }   // tocó el dial antes de que llegara el historial
        historial(b)
        m.dia.historial[lugar] = nil
        await m.pedirHistorial(lugar)
        #expect(m.cargaSimple(lugar)?.carga == 80)
    }

    @Test func enMedioDelRelojLaCargaEsLaDelPanel() async {
        let b = Banco(); historial(b)
        let m = await modelo(b, rutina: rutina(reps2: "10"))
        m.cambiarCarga(lugar) { $0.moverCarga(1) }
        let r = m.rutinaReloj()
        #expect(r.ejercicios.first?.series.map(\.kgSugerido) == [82.5, 82.5, 82.5, 82.5])
    }
}
