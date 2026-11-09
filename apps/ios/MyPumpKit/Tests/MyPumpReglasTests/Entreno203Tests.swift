import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

// 2.0.3, Entreno: el descanso elegido a mano (E2), el aviso de récord (E3), el RIR que arranca en el objetivo (E4) y la
// preparación (E1). Los casos están a mano en `apps/shared/vectores/entreno_203.json` y `preparacion.json` (la web no
// tiene estas reglas); Android (Entreno203Test, PreparacionTest) lee los mismos archivos.

private func leer(_ nombre: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/\(nombre)")))
}

private extension JSONValue {
    subscript(_ k: String) -> JSONValue? { if case .objeto(let o) = self { return o[k] }; return nil }
    var lista: [JSONValue] { if case .lista(let l) = self { return l }; return [] }
    var numero: Double? { if case .numero(let n) = self { return n }; return nil }
    var texto: String? { if case .texto(let t) = self { return t }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
}

@Suite("2.0.3: descanso, récord y RIR")
struct Entreno203Tests {
    @Test func descansoPropio() throws {
        let v = try leer("entreno_203.json")["descanso"]!
        #expect(DescansoPropio.opciones == v["opciones"]!.lista.compactMap { $0.numero.map(Int.init) })
        let casos = v["casos"]!.lista
        #expect(casos.count >= 8)
        for c in casos {
            let s = DescansoPropio.segundos(propio: c["propio"]?.numero.map(Int.init), plan: c["plan"]?.numero.map(Int.init))
            #expect(s == Int(c["sale"]!.numero!), "\(c)")
        }
    }

    /// E2: «Usar» no borra el propio aunque elija el del plan, y sin mover la rueda con un del plan que no es opción no
    /// guarda nada.
    @Test func usarDelSelector() throws {
        let casos = try leer("entreno_203.json")["descanso"]!["usar"]!["casos"]!.lista
        #expect(casos.count >= 6)
        for c in casos {
            let g = DescansoPropio.alUsar(Int(c["seleccion"]!.numero!), inicial: Int(c["inicial"]!.numero!), plan: Int(c["plan"]!.numero!),
                                          propio: c["propio"]!.bool!)
            #expect(g == c["guarda"]?.numero.map(Int.init), "\(c["nombre"]!.texto!)")
        }
    }

    @Test func rirDelPlan() throws {
        let casos = try leer("entreno_203.json")["rir"]!["casos"]!.lista
        #expect(casos.count >= 12)
        for c in casos {
            #expect(RIRDelPlan.guardar(c["objetivo"]?.texto) == c["guarda"]!.texto!, "\(c)")
            #expect(RIRDelPlan.leyenda(c["objetivo"]?.texto) == c["leyenda"]!.texto!, "\(c)")
        }
    }

    @Test func record() throws {
        let casos = try leer("entreno_203.json")["record"]!["casos"]!.lista
        #expect(casos.count >= 12)
        func marca(_ j: JSONValue) -> RecordSerie.Marca { RecordSerie.Marca(kg: j["kg"]!.numero!, reps: Int(j["reps"]!.numero!)) }
        for c in casos {
            let a = RecordSerie.evaluar(marca(c["serie"]!), sinKg: c["sinKg"]?.bool ?? false, verosimil: c["verosimil"]?.bool ?? true,
                                        anteriores: c["anteriores"]!.lista.map(marca), hoy: c["hoy"]!.lista.map(marca))
            #expect(a?.texto == c["sale"]?.texto, "\(c["nombre"]!.texto!)")
        }
    }

    /// El día real: el récord sale al confirmar contra el historial de días anteriores, no contra el de hoy, y no se
    /// repite en la serie siguiente con el mismo peso.
    @Test func recordAlConfirmar() throws {
        let j = #"{"id":"d1","nombre":"Día 1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Press banca","tipo":"compuesto","series":3,"reps":"8-10","rir_objetivo":"1-2"}]}]}"#
        let plan = try JSONDecoder().decode(Dia.self, from: Data(j.utf8))
        var d = DiaEnCurso(dia: plan, semana: 1, sesionId: "s1", zona: TimeZone(identifier: "America/Argentina/Buenos_Aires")!)
        let fila = { (fecha: String, kg: Double, reps: Int) -> RegistroHistorico in
            try! JSONDecoder().decode(RegistroHistorico.self, from: Data(#"{"registrado_en":"\#(fecha)T15:00:00+00:00","peso_kg":\#(kg),"reps_realizadas":\#(reps),"serie_numero":1}"#.utf8))
        }
        d.historial["e1"] = [fila("2026-11-03", 90, 10), fila("2026-10-30", 80, 10)]
        d.escribir("e1", 0, campo: "reps", valor: "8")
        d.escribir("e1", 0, campo: "kg", valor: "82,5")
        let p1 = d.confirmarSerie("e1", 0, hoy: "2026-11-03")
        #expect(p1.record?.texto == "Récord: +2,5 kg", "los 90 kg de hoy no cuentan como historia")
        d.escribir("e1", 1, campo: "reps", valor: "8")
        d.escribir("e1", 1, campo: "kg", valor: "82.5")
        #expect(d.confirmarSerie("e1", 1, hoy: "2026-11-03").record == nil, "ya avisado")
        d.escribir("e1", 2, campo: "reps", valor: "9")
        d.escribir("e1", 2, campo: "kg", valor: "82.5")
        #expect(d.confirmarSerie("e1", 2, hoy: "2026-11-03").record?.texto == "Récord: +1 rep")
    }

    private static let zonaAR = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
    private static func fila(_ fecha: String, _ kg: Double, _ reps: Int) -> RegistroHistorico {
        try! JSONDecoder().decode(RegistroHistorico.self, from: Data(#"{"registrado_en":"\#(fecha)T15:00:00+00:00","peso_kg":\#(kg),"reps_realizadas":\#(reps),"serie_numero":1}"#.utf8))
    }

    /// El historial llega cortado en `topeHistorial` filas: lleno y más corto que medio año, la mejor marca puede ser más
    /// vieja y no se avisa; lleno y de más de medio año, sí; con menos filas que el tope (completo), sí.
    @Test func recordConHistoriaCorta() throws {
        let j = #"{"id":"d1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Press banca","tipo":"compuesto","series":1,"reps":"8"}]}]}"#
        let plan = try JSONDecoder().decode(Dia.self, from: Data(j.utf8))
        func confirmar(_ h: [RegistroHistorico]) -> String? {
            var d = DiaEnCurso(dia: plan, semana: 1, sesionId: "s1", zona: Self.zonaAR)
            d.historial["e1"] = h
            d.escribir("e1", 0, campo: "reps", valor: "8")
            d.escribir("e1", 0, campo: "kg", valor: "82,5")
            return d.confirmarSerie("e1", 0, hoy: "2026-11-03").record?.texto
        }
        let corto = (0..<RecordSerie.topeHistorial).map { _ in Self.fila("2026-10-01", 80, 8) }
        #expect(confirmar(corto) == nil, "48 filas de un mes: la mejor puede ser más vieja")
        #expect(confirmar(Array(corto.dropLast())) == "Récord: +2,5 kg", "47 filas: el historial está completo")
        let largo = Array(corto.dropLast()) + [Self.fila("2026-04-01", 80, 8)]
        #expect(confirmar(largo) == "Récord: +2,5 kg", "48 filas que abarcan más de medio año")
        #expect(RecordSerie.historiaSuficiente([], hoy: "2026-11-03", zona: Self.zonaAR))
    }

    /// El récord no se repite: el lápiz sobre la serie que lo dio, ni el mismo ejercicio en otro lugar del día.
    @Test func recordNoSeRepite() throws {
        let j = #"{"id":"d1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Press banca","tipo":"compuesto","series":2,"reps":"8"},{"id":"e2","nombre":"Curl con barra","tipo":"aislamiento","series":1,"reps":"8"},{"id":"e3","nombre":"Press banca","tipo":"compuesto","series":1,"reps":"8"}]}]}"#
        var d = DiaEnCurso(dia: try JSONDecoder().decode(Dia.self, from: Data(j.utf8)), semana: 1, sesionId: "s1", zona: Self.zonaAR)
        d.historial["e1"] = [Self.fila("2026-10-30", 80, 8)]
        d.historial["e3"] = [Self.fila("2026-10-30", 80, 8)]
        d.escribir("e1", 0, campo: "reps", valor: "8")
        d.escribir("e1", 0, campo: "kg", valor: "85")
        #expect(d.confirmarSerie("e1", 0, hoy: "2026-11-03").record?.texto == "Récord: +5 kg")
        // El lápiz: se corrige la misma serie con lo mismo; no vuelve a avisar.
        _ = d.editarSerie("e1", 0)
        #expect(d.confirmarSerie("e1", 0, hoy: "2026-11-03").record == nil, "el lápiz no repite el récord")
        // El mismo ejercicio más tarde en el día: lo de hoy es piso.
        d.escribir("e3", 0, campo: "reps", valor: "8")
        d.escribir("e3", 0, campo: "kg", valor: "85")
        #expect(d.confirmarSerie("e3", 0, hoy: "2026-11-03").record == nil, "mismo ejercicio en otro lugar")
        d.escribir("e3", 0, campo: "kg", valor: "87,5")
        _ = d.editarSerie("e3", 0)
        d.escribir("e3", 0, campo: "kg", valor: "87,5")
        #expect(d.confirmarSerie("e3", 0, hoy: "2026-11-03").record?.texto == "Récord: +2,5 kg", "por encima de lo de hoy sí")
    }

    /// El RIR del ejercicio que se hace: el core y lo que va sin peso quedan en null, aunque el plan diga otra cosa; un
    /// objetivo en RPE es al fallo. El aviso de primera vez dice lo mismo que la leyenda (en el modelo: EntrenoModelo203Tests).
    @Test func rirDelQueSeHaceYCalibracion() throws {
        let j = #"{"id":"d1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Plancha","tipo":"core","series":1,"reps":"30","progresion":[{"semana":1,"series":1,"reps":"30","rir":"1-2"}]},{"id":"e2","nombre":"Flexiones de brazos","tipo":"compuesto","series":1,"reps":"8","progresion":[{"semana":1,"series":1,"reps":"8","rir":"1"}]},{"id":"e3","nombre":"Press banca","tipo":"compuesto","series":1,"reps":"8","progresion":[{"semana":1,"series":1,"reps":"8","rir":"RPE 8"}]},{"id":"e4","nombre":"Remo con barra","tipo":"compuesto","series":1,"reps":"10","progresion":[{"semana":1,"series":1,"reps":"10","rir":"0"}]}]}]}"#
        var d = DiaEnCurso(dia: try JSONDecoder().decode(Dia.self, from: Data(j.utf8)), semana: 1, sesionId: "s1")
        #expect(d.leyendaRIR("e1") == nil && d.leyendaRIR("e2") == nil, "sin leyenda en el core ni en lo de peso corporal")
        #expect(d.leyendaRIR("e3") == "Al fallo")
        d.fijarRIRDelPlan("e1", 0)
        d.fijarRIRDelPlan("e2", 0)
        d.fijarRIRDelPlan("e3", 0)
        #expect(d.ejercicios["e1"]!.series[0].rir == "" && d.ejercicios["e2"]!.series[0].rir == "")
        #expect(d.ejercicios["e3"]!.series[0].rir == "0")
        // El sustituto manda: un press (con peso) en lugar de las flexiones lleva el RIR de la pauta.
        var press = d.ejercicio("e2")!
        press.nombre = "Press banca con barra"; press.equipo = "barbell"
        d.fijarRIRDelPlan("e2", 0, efectivo: press)
        #expect(d.ejercicios["e2"]!.series[0].rir == "0", "2.3.0: todo al fallo, nunca el RIR del plan")
        #expect(RIRDelPlan.calibracion("… a 8 reps dejando 1–2 en reserva.", leyenda: "Dejando 0–1 en reserva") == "… a 8 reps dejando 0–1 en reserva.")
    }

    /// E2: el descanso del ejercicio (por su clave) le gana al del plan y es el que arranca al confirmar.
    @Test func descansoElegidoArrancaAlConfirmar() throws {
        let j = #"{"id":"d1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Remo con barra","tipo":"compuesto","series":2,"reps":"10","descanso_segundos":120}]}]}"#
        var d = DiaEnCurso(dia: try JSONDecoder().decode(Dia.self, from: Data(j.utf8)), semana: 1, sesionId: "s1")
        #expect(d.descanso("e1") == 120 && !d.tieneDescansoPropio("e1"))
        d.descansosPropios[ClaveEjercicio.de("Remo con barra")] = 75
        #expect(d.descanso("e1") == 75 && d.tieneDescansoPropio("e1"))
        d.escribir("e1", 0, campo: "reps", valor: "10")
        d.escribir("e1", 0, campo: "kg", valor: "60")
        #expect(d.confirmarSerie("e1", 0).efectos.contains(.iniciarDescanso(segundos: 75)))
    }

    /// 2.3.0: al confirmar va 0 (al fallo), aunque el plan traiga RIR; el calentamiento queda null y una
    /// serie ya registrada (con nombre) conserva el suyo.
    @Test func rirDelPlanAlConfirmar() throws {
        let j = #"{"id":"d1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Press banca","series":2,"reps":"8","progresion":[{"semana":1,"series":2,"reps":"8","rir":"1-2"}]},{"id":"e2","nombre":"Curl","series":1,"reps":"12"},{"id":"e3","nombre":"Movilidad","tipo":"calentamiento","series":1,"reps":"10"}]}]}"#
        var d = DiaEnCurso(dia: try JSONDecoder().decode(Dia.self, from: Data(j.utf8)), semana: 1, sesionId: "s1")
        #expect(d.leyendaRIR("e1") == "Al fallo" && d.leyendaRIR("e2") == "Al fallo")
        func cargaRIR(_ id: String, _ idx: Int) -> JSONValue? {
            d.escribir(id, idx, campo: "reps", valor: "8")
            d.escribir(id, idx, campo: "kg", valor: "10")
            d.fijarRIRDelPlan(id, idx)
            let p = d.confirmarSerie(id, idx)
            guard case .encolar(_, let payload, _)? = p.efectos.first(where: { if case .encolar(let k, _, _) = $0 { return k == "carga" }; return false }) else { return nil }
            return payload["datos"]?["rir"]
        }
        #expect(cargaRIR("e1", 0) == .numero(0), "el RIR del plan (1-2) no se copia")
        #expect(cargaRIR("e2", 0) == .numero(0))
        #expect(cargaRIR("e3", 0) == .null, "el calentamiento no es serie dura")
        // Una serie que vino del servidor sin RIR y se corrige con el lápiz no se toca.
        d.ejercicios["e1"]!.series[1].nombreRegistrado = "Press banca"
        #expect(cargaRIR("e1", 1) == .null)
    }
}

@Suite("2.0.3: preparación (E1)")
struct PreparacionTests {
    @Test func losCasosCompartidos() throws {
        let v = try leer("preparacion.json")
        let dias = v["dias"]!
        let casos = v["casos"]!.lista
        #expect(casos.count >= 15)
        for c in casos {
            let nombre = c["nombre"]!.texto!
            let dia = dias[c["dia"]!.texto!]!.lista.map {
                Preparacion.Entrada(tipo: $0["tipo"]?.texto, musculo: $0["musculo"]?.texto, nombre: $0["nombre"]!.texto!, sinPeso: $0["sinPeso"]!.bool!)
            }
            let plan: [Aproximacion]? = c["plan"].flatMap { Aproximacion.lista($0) }
            let s = Preparacion.series(dia: dia, indice: Int(c["indice"]!.numero!), nombre: c["ejercicio"]!.texto!, equipo: c["equipo"]?.texto,
                                       sinKg: c["sinKg"]!.bool!, kgEfectivo: c["kg"]?.numero, plan: plan)
            let sale = c["sale"]!.lista
            #expect(s.count == sale.count, "\(nombre): \(s)")
            for (a, b) in zip(s, sale) {
                #expect(a.tipo.rawValue == b["tipo"]!.texto!, "\(nombre)")
                #expect(a.numero == b["numero"]?.numero.map(Int.init), "\(nombre)")
                #expect(a.reps == b["reps"]!.texto!, "\(nombre)")
                #expect(a.kg == b["kg"]?.numero, "\(nombre): \(a)")
                #expect(a.barraSola == b["barraSola"]!.bool!, "\(nombre)")
                #expect(a.opcional == b["opcional"]!.bool!, "\(nombre)")
                #expect(a.nota == b["nota"]?.texto, "\(nombre)")
            }
        }
    }

    @Test func clasificacion() throws {
        let casos = try leer("preparacion.json")["clasificacion"]!["casos"]!.lista
        #expect(casos.count >= 30)
        for c in casos {
            let n = c["nombre"]!.texto!
            #expect(Preparacion.esPrincipal(nombre: n, tipo: c["tipo"]?.texto) == c["principal"]!.bool!, "\(n): principal")
            #expect(Preparacion.sinPreparacion(n) == c["sinPreparacion"]!.bool!, "\(n): sin preparación")
        }
    }

    /// El campo en la rutina: el decodificado nunca tira abajo el ejercicio ni la rutina.
    @Test func elCampoEnLaRutina() throws {
        let j = #"{"dias":[{"id":"d1","bloques":[{"ejercicios":[{"id":"a","nombre":"A","aproximaciones":[{"reps":10,"pct":50}]},{"id":"b","nombre":"B","aproximaciones":{"x":1}},{"id":"c","nombre":"C","aproximaciones":[]},{"id":"d","nombre":"D"}]}]}]}"#
        let est = try JSONDecoder().decode(EstructuraRutina.self, from: Data(j.utf8))
        let ej = est.dias[0].bloques[0].ejercicios
        #expect(ej.map(\.id) == ["a", "b", "c", "d"])
        #expect(ej[0].aproximaciones == [Aproximacion(reps: "10", pct: 50)])
        #expect(ej[1].aproximaciones == nil && ej[3].aproximaciones == nil)
        #expect(ej[2].aproximaciones == [])
    }

    @Test func textos() {
        #expect(Preparacion.Serie(tipo: .aproximacion, numero: 2, reps: "5", kg: 22.5).etiqueta == "Aproximación 2")
        #expect(Preparacion.Serie(tipo: .aproximacion, numero: 2, reps: "5", kg: 22.5).textoKg == "22,5")
        #expect(Preparacion.Serie(tipo: .potenciacion, reps: "1-3", opcional: true).etiqueta == "Potenciación (opcional)")
        #expect(Preparacion.Serie(tipo: .calentamiento, reps: "16-20", kg: 20, barraSola: true).textoKg == "Barra sola")
        #expect(Preparacion.kgEfectivo(escrito: "", sugerido: "57.5") == 57.5)
        #expect(Preparacion.kgEfectivo(escrito: "60,5", sugerido: "57.5") == 60.5)
        #expect(Preparacion.kgEfectivo(escrito: "", sugerido: "–") == nil)
    }
}
