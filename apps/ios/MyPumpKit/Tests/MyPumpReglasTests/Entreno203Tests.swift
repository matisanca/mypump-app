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

    @Test func rirInicial() throws {
        let casos = try leer("entreno_203.json")["rirInicial"]!["casos"]!.lista
        #expect(casos.count >= 10)
        for c in casos {
            #expect(RIRInicial.de(c["objetivo"]?.texto) == c["sale"]!.texto!, "\(c)")
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

    /// E4: arranca en el objetivo de la semana; sin objetivo queda vacío y se guarda null; lo confirmado no se toca.
    @Test func rirPreseleccionado() throws {
        let j = #"{"id":"d1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Press banca","series":2,"reps":"8","progresion":[{"semana":1,"series":2,"reps":"8","rir":"1-2"}]},{"id":"e2","nombre":"Curl","series":1,"reps":"12"}]}]}"#
        var d = DiaEnCurso(dia: try JSONDecoder().decode(Dia.self, from: Data(j.utf8)), semana: 1, sesionId: "s1")
        d.ejercicios["e1"]!.series[1].rir = "3"
        d.preseleccionarRIR()
        #expect(d.ejercicios["e1"]?.series.map(\.rir) == ["1", "3"])
        #expect(d.ejercicios["e2"]?.series.map(\.rir) == [""])
        d.escribir("e2", 0, campo: "reps", valor: "12")
        d.escribir("e2", 0, campo: "kg", valor: "10")
        let p = d.confirmarSerie("e2", 0)
        guard case .encolar(_, let payload, _)? = p.efectos.first(where: { if case .encolar(let k, _, _) = $0 { return k == "carga" }; return false }) else {
            Issue.record("sin carga"); return
        }
        #expect(payload["datos"]?["rir"] == .null, "RIR sin cargar va null")
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
                Preparacion.Entrada(tipo: $0["tipo"]?.texto, musculo: $0["musculo"]?.texto, clave: $0["clave"]!.texto!)
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
