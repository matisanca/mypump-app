import Foundation
import Testing
import MyPumpReglas
@testable import MyPumpReloj

// El entreno en el reloj con la rutina de muestra: la corona, la preparación, el récord, el descanso, la cola y lo que
// pasa cuando llega una rutina nueva del iPhone.

func sesionDemo() -> SesionReloj {
    var s = SesionReloj()
    s.recibir(.demo(fecha: HOY, generada: T0))
    return s
}

@Suite struct SesionTests {
    @Test func arrancaEnElPrimerEjercicioConLoSugerido() {
        let s = sesionDemo()
        #expect(s.lugar == "press-banca-d1-0")
        #expect(s.reps == 8)
        #expect(s.kg == 80)
        #expect(!s.iniciada)
    }

    @Test func laCoronaVaDePasoDelEquipo() {
        var s = sesionDemo()
        s.girarKg(1)
        #expect(s.kg == 82.5, "barra: de 2,5 en 2,5")
        s.girarKg(-3)
        #expect(s.kg == 75)
        s.elegir("press-inclinado-mancuernas-d1-1")
        #expect(s.kg == 26)
        s.girarKg(1)
        #expect(s.kg == 28, "mancuerna pesada: de 2 en 2")
        s.elegir("elevaciones-laterales-d1-3")
        s.girarKg(-1)
        #expect(s.kg == 9, "mancuerna liviana: de 1 en 1 debajo de 10")
        s.girarKg(2)
        #expect(s.kg == 12, "9 → 10 → 12")
        s.girarKg(-100)
        #expect(s.kg == 0, "no baja de 0")
        s.girarReps(-100)
        #expect(s.reps == SesionReloj.repsMin)
        s.girarReps(1_000)
        #expect(s.reps == SesionReloj.repsMax)
    }

    @Test func unValorFueraDeLaGrillaSeAlinea() {
        var s = sesionDemo()
        s.elegir("press-inclinado-mancuernas-d1-1")
        s.girarKg(-2) // 26 → 24 → 22
        s.girarKg(-1) // 22 → 20
        s.girarKg(-1) // 20 → 18
        #expect(s.kg == 18)
    }

    @Test func sinKgLaCoronaNoTocaElPeso() {
        var s = sesionDemo()
        s.elegir("fondos-d1-4")
        #expect(s.kg == nil)
        s.girarKg(3)
        #expect(s.kg == nil)
        #expect(s.preparacion("fondos-d1-4").isEmpty, "peso corporal: sin preparación")
    }

    @Test func laPreparacionEsLaDelKitYSigueALaCorona() {
        var s = sesionDemo()
        let p = s.preparacion("press-banca-d1-0")
        #expect(p.map(\.tipo) == [.calentamiento, .aproximacion, .aproximacion, .potenciacion])
        #expect(p.map(\.kg) == [20, 47.5, 67.5, 85])
        #expect(p[0].barraSola)
        #expect(TextoReloj.preparacion(p[0]) == "16-20 × Barra sola")
        #expect(TextoReloj.preparacion(p[1]) == "5 × 47,5 kg")
        // Mismo resultado que llamar al kit con las entradas del día.
        let r = s.rutina!
        #expect(p == Preparacion.series(dia: r.entradasPreparacion, indice: 0, nombre: "Press banca", equipo: "barbell",
                                        sinKg: false, kgEfectivo: 80, plan: nil))
        // Con la corona en 100 antes de la primera serie, la preparación sigue a 100.
        s.girarKg(8)
        #expect(s.kg == 100)
        #expect(s.preparacion("press-banca-d1-0").map(\.kg) == [25, 60, 85, 105])
        // Confirmada la primera, manda lo hecho (no la corona de la segunda).
        s.confirmar(ahora: T0)
        s.girarKg(-10)
        #expect(s.preparacion("press-banca-d1-0").map(\.kg) == [25, 60, 85, 105])
        // El segundo de pecho es un principal siguiente: una sola al 75 %.
        #expect(s.preparacion("press-inclinado-mancuernas-d1-1").map(\.reps) == ["5"])
    }

    @Test func laPreparacionDelPlanGana() {
        var r = RutinaReloj.demo(fecha: HOY, generada: T0)
        r.ejercicios[0].aproximacionesPlan = [AproximacionReloj(reps: "10", pct: 50)]
        var s = SesionReloj()
        s.recibir(r)
        let p = s.preparacion("press-banca-d1-0")
        #expect(p.count == 1)
        #expect(p[0].kg == 40)
        r.ejercicios[0].aproximacionesPlan = []
        s.recibir(RutinaReloj(rutinaId: r.rutinaId, diaId: "d9", semana: 1, nombreDia: "X", fecha: HOY, generada: T0 + 1, ejercicios: r.ejercicios))
        #expect(s.preparacion("press-banca-d1-0").isEmpty, "[] del plan es sin preparación")
    }

    @Test func confirmarEncolaIniciarYLaSerieYArrancaElDescanso() throws {
        var s = sesionDemo()
        let r10 = s.confirmar(ahora: T0)
        let c = try #require(r10)
        #expect(s.iniciada)
        #expect(s.cola.pendientes.map(\.evento) == [
            .iniciar(diaId: "d1", semana: 1),
            .serie(diaId: "d1", semana: 1, lugar: "press-banca-d1-0", indice: 0, reps: 8, kg: 80),
        ])
        #expect(c.descanso)
        #expect(!c.diaCompleto)
        #expect(c.record == nil, "igualar no es récord")
        let d = try #require(s.descansoEnCurso(ahora: T0 + 1_000))
        #expect(d.objetivo == 150)
        #expect(s.actual?.series[0].confirmada == true)
        #expect(s.actual?.estado == "en_curso")
        #expect(s.reps == 8 && s.kg == 80, "la corona pasa a la serie 2")
    }

    @Test func elRecordEsElDelKit() throws {
        var s = sesionDemo()
        s.girarKg(1) // 82,5 > 80
        let r11 = s.confirmar(ahora: T0)
        let c = try #require(r11)
        #expect(c.record == "Récord: +2,5 kg")
        #expect(s.records == ["Press banca · Récord: +2,5 kg"])
        // La serie de hoy es el piso: 82,5 otra vez no vuelve a avisar; con una rep más, sí.
        #expect(s.kg == 80, "la serie 2 arranca en lo sugerido, como en el teléfono")
        s.girarKg(1)
        let r12 = s.confirmar(ahora: T0 + 1)
        #expect(r12?.record == nil)
        s.girarKg(1)
        s.girarReps(1)
        let r13 = s.confirmar(ahora: T0 + 2)
        #expect(r13?.record == "Récord: +1 rep")
    }

    @Test func sinHistoriaSuficienteNoHayRecord() {
        var r = RutinaReloj.demo(fecha: HOY, generada: T0)
        r.ejercicios[0].historiaSuficiente = false
        var s = SesionReloj()
        s.recibir(r)
        s.girarKg(10)
        let r14 = s.confirmar(ahora: T0)
        #expect(r14?.record == nil)
    }

    @Test func alTerminarUnEjercicioPasaAlSiguiente() throws {
        var s = sesionDemo()
        s.confirmar(ahora: T0); s.confirmar(ahora: T0 + 1)
        let r15 = s.confirmar(ahora: T0 + 2)
        let c = try #require(r15)
        #expect(c.siguiente == "press-inclinado-mancuernas-d1-1")
        #expect(s.lugar == "press-inclinado-mancuernas-d1-1")
        #expect(s.kg == 26)
        #expect(s.ejercicio("press-banca-d1-0")?.estado == "completo")
    }

    @Test func conTodoHechoNoHayDescansoYElResumenCuenta() throws {
        var s = sesionDemo()
        var ultima: SesionReloj.Confirmacion?
        var t = T0
        while true {
            guard let c = s.confirmar(ahora: t) else { break }
            ultima = c
            t += 60_000
        }
        #expect(ultima?.diaCompleto == true)
        #expect(ultima?.descanso == false)
        #expect(s.descanso == nil)
        #expect(s.todoHecho)
        let r16 = s.terminar(ahora: t, salud: SaludEntreno(fcMedia: 121, fcMaxima: 160, kcal: 310))
        let r = try #require(r16)
        #expect(r.series == 14)
        #expect(r.ejercicios == 5)
        let esperado: Double = 1920 + 780 + 1080 + 450 // 3×8×80 + 3×10×26 + 3×8×45 + 3×15×10
        #expect(r.volumenKg == esperado)
        #expect(r.textoVolumen == "4.230 kg")
        #expect(r.minutos == 14)
        #expect(r.kcal == 310)
        #expect(r.sinEnviar == 16, "iniciar + 14 series + terminar, nada acusado")
        #expect(r.textoSinEnviar == "16 cambios sin pasar al iPhone")
        #expect(s.cola.pendientes.last?.evento == .terminar(diaId: "d1", semana: 1))
        // Terminar dos veces no encola dos cierres.
        _ = s.terminar(ahora: t + 1)
        #expect(s.cola.pendientes.count == 16)
    }

    @Test func elDescansoVibraUnaVezYSeCierraSolo() {
        var s = sesionDemo()
        s.elegir("elevaciones-laterales-d1-3") // 60 s
        s.confirmar(ahora: T0)
        let r17 = s.tickDescanso(ahora: T0 + 30_000)
        #expect(!r17)
        s.ajustarDescanso(15, ahora: T0 + 30_000)
        #expect(s.descansoEnCurso(ahora: T0 + 30_000)?.objetivo == 75)
        let r18 = s.tickDescanso(ahora: T0 + 61_000)
        #expect(!r18, "el +15 lo corrió")
        let r19 = s.tickDescanso(ahora: T0 + 75_000)
        #expect(r19)
        let r20 = s.tickDescanso(ahora: T0 + 75_500)
        #expect(!r20, "no vuelve a vibrar")
        _ = s.tickDescanso(ahora: T0 + 78_000)
        #expect(s.descanso == nil, "2 s después del fin se va")
    }

    @Test func unDescansoVistoTardeNoVibra() {
        var s = sesionDemo()
        s.confirmar(ahora: T0) // 150 s
        let r21 = s.tickDescanso(ahora: T0 + 151_000 + SesionReloj.vibrarHasta)
        #expect(!r21)
    }

    @Test func unaRutinaNuevaDelMismoDiaConservaLoQueElTelefonoNoTiene() {
        var s = sesionDemo()
        s.girarReps(2)
        s.confirmar(ahora: T0)
        // El iPhone manda la rutina sin esa serie (todavía no le llegó).
        s.recibir(.demo(fecha: HOY, generada: T0 + 5_000))
        #expect(s.ejercicio("press-banca-d1-0")?.series[0].confirmada == true)
        #expect(s.ejercicio("press-banca-d1-0")?.series[0].reps == 10)
        #expect(s.iniciada)
        // Acusada, la rutina del teléfono ya la trae.
        let ids = s.cola.pendientes.map { AcuseEvento(id: $0.id, resultado: .aplicado) }
        s.acusar(ids)
        var r = RutinaReloj.demo(fecha: HOY, generada: T0 + 9_000)
        r.ejercicios[0].series[0] = SerieReloj(numero: 1, confirmada: true, reps: 10, kg: 80)
        r.ejercicios[0].estado = "en_curso"
        s.recibir(r)
        #expect(s.cola.vacia)
        #expect(s.ejercicio("press-banca-d1-0")?.confirmadas == 1)
    }

    @Test func unaRutinaMasViejaSeIgnoraYOtroDiaReemplaza() {
        var s = sesionDemo()
        s.confirmar(ahora: T0)
        var vieja = RutinaReloj.demo(fecha: HOY, generada: T0 - 1)
        vieja.nombreDia = "VIEJA"
        s.recibir(vieja)
        #expect(s.rutina?.nombreDia == "EMPUJE")
        var otro = RutinaReloj.demo(fecha: HOY, generada: T0 + 1)
        otro.diaId = "d2"
        otro.nombreDia = "TIRÓN"
        s.recibir(otro)
        #expect(s.rutina?.nombreDia == "TIRÓN")
        #expect(s.ejercicio("press-banca-d1-0")?.confirmadas == 0, "las series del d1 no se pegan al d2")
        #expect(s.cola.pendientes.count == 2, "pero se siguen mandando")
        #expect(!s.iniciada)
    }

    @Test func elDescansoDelTelefonoSeSigueEnElReloj() {
        var s = sesionDemo()
        var r = RutinaReloj.demo(fecha: HOY, generada: T0 + 1)
        r.descanso = Descanso.iniciar(segundos: 90, ahora: T0).guardado
        s.recibir(r)
        #expect(s.descansoEnCurso(ahora: T0 + 10_000)?.restante(ahora: T0 + 10_000) == 80)
    }

    @Test func sobreviveAlDisco() throws {
        var s = sesionDemo()
        s.girarKg(1)
        s.confirmar(ahora: T0)
        let vuelta = try JSONDecoder().decode(SesionReloj.self, from: JSONEncoder().encode(s))
        #expect(vuelta == s)
    }

    @Test func laComplicacionMuestraElDiaYElDescansoYDespuesElProximo() {
        var s = sesionDemo()
        var c = EstadoComplicacion.de(s, ahora: T0)
        #expect(c.titulo == "Empuje")
        #expect(c.detalle == "0 de 5 ejercicios")
        #expect(c.finDescanso == nil)
        s.confirmar(ahora: T0)
        c = EstadoComplicacion.de(s, ahora: T0 + 1)
        #expect(c.finDescanso == T0 + 150_000)
        var t = T0
        while true {
            guard s.confirmar(ahora: t) != nil else { break }
            t += 1
        }
        c = EstadoComplicacion.de(s, ahora: t)
        #expect(c.titulo == "Tirón")
        #expect(c.detalle == "Próximo")
        #expect(EstadoComplicacion.de(SesionReloj(), ahora: 0).detalle == "Abrí Pump Team")
    }

    // MARK: - Revisión del 3-nov: nada se pierde en silencio

    @Test func losEventosLlevanLaCuentaYLaRutina() throws {
        var s = sesionDemo()
        s.confirmar(ahora: T0)
        let e = try #require(s.cola.pendientes.last)
        #expect(e.cuenta == "demo" && e.rutinaId == "demo")
    }

    @Test func pendienteQuedaEnLaColaConElMotivoYRechazadoSeMuestra() throws {
        var s = sesionDemo()
        s.iniciar(ahora: T0)
        s.confirmar(ahora: T0 + 1)
        s.confirmar(ahora: T0 + 2)
        let p = s.cola.pendientes
        try #require(p.count == 3)
        s.acusar([AcuseEvento(id: p[0].id, resultado: .rechazado, motivo: "el iPhone ya pasó a la semana 2."),
                  AcuseEvento(id: p[1].id, resultado: .rechazado, motivo: "tu rutina cambió desde que la hiciste."),
                  AcuseEvento(id: p[2].id, resultado: .pendiente, motivo: "En el iPhone hay otro día abierto. Cerralo para pasar esto.")], ahora: T0 + 3)
        #expect(s.rechazos == ["No se pudo empezar en el iPhone: el iPhone ya pasó a la semana 2.",
                               "Esta serie no se pudo guardar: tu rutina cambió desde que la hiciste."])
        #expect(s.esperando == "En el iPhone hay otro día abierto. Cerralo para pasar esto.")
        #expect(s.cola.pendientes.map(\.id) == [p[2].id], "el pendiente se guarda para reintentar")
        s.acusar([AcuseEvento(id: p[2].id, resultado: .aplicado)])
        #expect(s.esperando == nil && s.cola.vacia)
        s.leerRechazos()
        #expect(s.rechazos.isEmpty)
    }

    @Test func losRechazosSonLosUltimosCinco() {
        var s = sesionDemo()
        for i in 0..<8 {
            s.confirmar(ahora: T0 + Double(i))
            let id = s.cola.pendientes.last!.id
            s.acusar([AcuseEvento(id: id, resultado: .rechazado, motivo: "m\(i).")])
        }
        #expect(s.rechazos.count == SesionReloj.topeRechazos)
        #expect(s.rechazos.last == "Esta serie no se pudo guardar: m7.")
    }

    @Test func unPendienteDeOtraRutinaNoSePintaEnLaNueva() {
        var s = sesionDemo()
        s.confirmar(ahora: T0)
        var r = RutinaReloj.demo(fecha: HOY, generada: T0 + 5_000)
        r.rutinaId = "otra"
        s.recibir(r)
        #expect(s.ejercicio("press-banca-d1-0")?.series[0].confirmada == false)
        #expect(s.cola.pendientes.count == 2, "pero sigue en la cola (iniciar y la serie)")
    }

    @Test func siElIPhoneCierraElDiaElRelojLoDaPorTerminado() {
        var s = sesionDemo()
        s.iniciar(ahora: T0)
        s.confirmar(ahora: T0 + 1)
        #expect(s.descanso != nil && !s.terminada)
        var r = RutinaReloj.demo(fecha: HOY, generada: T0 + 5_000)
        r.diaFinalizado = true
        s.recibir(r)
        #expect(s.terminada)
        #expect(s.descanso == nil)
    }

    // MARK: - Elegir el día

    @Test func elDiaQueYaEstaSeAbreYOtroSePideAlIPhone() {
        var s = sesionDemo()
        let e1 = s.elegirDia("d1", conIPhone: false, ahora: T0)

        #expect(e1 == .entrar)
        let e2 = s.elegirDia("d2", conIPhone: true, ahora: T0)

        #expect(e2 == .pedir)
        #expect(s.diaPedido == "d2")
        #expect(s.esperandoDia(ahora: T0 + 1_000))
        // Llega la rutina del día pedido: se entra y se deja de esperar.
        let e3 = s.recibir(.demo(fecha: HOY, generada: T0 + 1, dia: "d2"))

        #expect(e3)
        #expect(s.rutina?.diaId == "d2")
        #expect(s.rutina?.nombreDia == "TIRÓN")
        #expect(s.diaPedido == nil)
        #expect(s.lugar == "dominadas-lastre-d2-0")
        #expect(s.avisoDia == nil)
    }

    @Test func sinElIPhoneSeSigueConElDiaQueHay() {
        var s = sesionDemo()
        let e4 = s.elegirDia("d3", conIPhone: false, ahora: T0)

        #expect(e4 == .no(SesionReloj.textoSinIPhone))
        #expect(s.avisoDia == SesionReloj.textoSinIPhone)
        #expect(s.diaPedido == nil)
        // Nunca se inventa una rutina: sigue el día que mandó el iPhone, y se conocen los días para mostrarlos.
        #expect(s.rutina?.diaId == "d1")
        #expect(s.rutina?.diasParaElegir.count == 4)
        s.leerAvisoDia()
        #expect(s.avisoDia == nil)
        let e5 = s.elegirDia("d9", conIPhone: true, ahora: T0)

        #expect(e5 == .no("Ese día ya no está en tu rutina."))
    }

    @Test func conElEntrenoEmpezadoNoSeCambiaDeDia() throws {
        var s = sesionDemo()
        s.iniciar(ahora: T0)
        #expect(!s.puedeCambiarDia)
        let e6 = s.elegirDia("d2", conIPhone: true, ahora: T0)

        #expect(e6 == .no(SesionReloj.textoEmpezado))
        let e7 = s.elegirDia("d1", conIPhone: true, ahora: T0)

        #expect(e7 == .entrar)
        _ = s.terminar(ahora: T0 + 60_000)
        // Terminado sí: es lo normal después de entrenar.
        #expect(s.puedeCambiarDia)
        let e8 = s.elegirDia("d2", conIPhone: true, ahora: T0)

        #expect(e8 == .pedir)
    }

    @Test func sinRespuestaDelIPhoneSeDejaDeEsperarYSeAvisa() {
        var s = sesionDemo()
        _ = s.elegirDia("d2", conIPhone: true, ahora: T0)
        let e9 = s.vencerPedido(ahora: T0 + SesionReloj.esperaDia - 1)

        #expect(!e9)
        let e10 = s.vencerPedido(ahora: T0 + SesionReloj.esperaDia)

        #expect(e10)
        #expect(s.diaPedido == nil)
        #expect(s.avisoDia == SesionReloj.textoSinRespuesta)
        #expect(s.rutina?.diaId == "d1")
        // Una rutina de otro día que llega tarde (la empujó el iPhone) igual se muestra, pero no «entra» sola.
        let e11 = s.recibir(.demo(fecha: HOY, generada: T0 + 1, dia: "d2"))

        #expect(!e11)
    }

    @Test func siElIPhoneNoPuedeAbrirElDiaQuedaElSuyoConElMotivo() {
        var s = sesionDemo()
        _ = s.elegirDia("d3", conIPhone: true, ahora: T0)
        var r = RutinaReloj.demo(fecha: HOY, generada: T0 + 1)
        r.avisoDia = "En el iPhone hay otro día en curso. Terminalo ahí para cambiar."
        let e12 = s.recibir(r)

        #expect(!e12)
        #expect(s.rutina?.diaId == "d1")
        #expect(s.avisoDia == r.avisoDia)
        // El aviso no se guarda con la rutina.
        #expect(s.rutina?.avisoDia == nil)
        #expect(s.diaPedido == nil)
    }

    @Test func cambiarDeDiaNoMezclaNiPierdeLosEventosDeOtroDia() throws {
        var s = sesionDemo()
        s.confirmar(ahora: T0)                         // iniciar + serie 1 de press banca (d1)
        s.confirmar(ahora: T0 + 1_000)                 // serie 2
        _ = s.terminar(ahora: T0 + 2_000)
        let deD1 = s.cola.pendientes
        #expect(deD1.count == 4)
        #expect(deD1.allSatisfy { $0.evento.diaId == "d1" })
        // Sin acuse del iPhone, se pasa a TIRÓN.
        let e13 = s.elegirDia("d2", conIPhone: true, ahora: T0 + 3_000)

        #expect(e13 == .pedir)
        s.recibir(.demo(fecha: HOY, generada: T0 + 3_001, dia: "d2"))
        // La cola sigue entera y en orden, con su día; nada de d1 se pinta en d2.
        #expect(s.cola.pendientes == deD1)
        #expect(s.rutina?.ejercicios.allSatisfy { $0.confirmadas == 0 } == true)
        #expect(!s.iniciada && !s.terminada)
        // Lo de d2 va con d2.
        s.confirmar(ahora: T0 + 4_000)
        let ultimo = try #require(s.cola.pendientes.last)
        #expect(ultimo.evento == .serie(diaId: "d2", semana: 1, lugar: "dominadas-lastre-d2-0", indice: 0, reps: 6, kg: 10))
        #expect(s.cola.pendientes.filter { $0.evento.diaId == "d1" }.count == 4)
        // Lo que el iPhone todavía no tiene vuelve a aparecer si llega d1 de nuevo (y lo de d2 no se le pega).
        s.recibir(.demo(fecha: HOY, generada: T0 + 5_000))
        #expect(s.rutina?.ejercicios.first?.confirmadas == 2)
        #expect(s.rutina?.ejercicios.allSatisfy { !$0.lugar.contains("-d2-") } == true)
        // Los acuses de d1 sacan solo lo de d1.
        s.acusar(deD1.map { AcuseEvento(id: $0.id, resultado: .aplicado) }, ahora: T0 + 6_000)
        #expect(s.cola.pendientes.map(\.evento.diaId) == ["d2", "d2"])
    }

    @Test func elPedidoSobreviveAlDisco() throws {
        var s = sesionDemo()
        _ = s.elegirDia("d2", conIPhone: true, ahora: T0)
        let leida = try JSONDecoder().decode(SesionReloj.self, from: JSONEncoder().encode(s))
        #expect(leida == s)
        #expect(leida.diaPedido == "d2")
        // Al reabrir la app pasada la espera (el temporizador murió con ella), el pedido vence y la lista se destraba.
        var reabierta = leida
        let vencio = reabierta.vencerPedido(ahora: T0 + SesionReloj.esperaDia)
        #expect(vencio)
        #expect(reabierta.diaPedido == nil)
        #expect(reabierta.avisoDia == SesionReloj.textoSinRespuesta)
    }

    @Test func elErrorTardioDeUnPedidoViejoNoCortaElNuevo() {
        var s = sesionDemo()
        _ = s.elegirDia("d2", conIPhone: true, ahora: T0)
        _ = s.vencerPedido(ahora: T0 + SesionReloj.esperaDia)
        _ = s.elegirDia("d3", conIPhone: true, ahora: T0 + SesionReloj.esperaDia + 1)
        // Llega el error de WatchConnectivity del pedido de d2: el de d3 sigue esperando.
        s.pedidoFallido(SesionReloj.textoSinIPhone, dia: "d2")
        #expect(s.diaPedido == "d3")
        #expect(s.avisoDia == nil)
        s.pedidoFallido(SesionReloj.textoSinIPhone, dia: "d3")
        #expect(s.diaPedido == nil)
        #expect(s.avisoDia == SesionReloj.textoSinIPhone)
    }
}
