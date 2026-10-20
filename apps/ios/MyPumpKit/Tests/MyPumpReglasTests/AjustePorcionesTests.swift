import Foundation
import Testing
@testable import MyPumpReglas
import MyPumpModelos

/// Ajustar porciones (feedback del 20-oct): sumar o restar kcal a una comida, gramos a mano, «Hoy no la como» y
/// compensar en la siguiente. Los casos de abajo también salen como vectores (`apps/shared/vectores/ajuste_porciones.json`)
/// que Android tiene que dar igual. Para regenerarlos: `GENERAR_VECTORES_AJUSTE=1 swift test --filter AjustePorciones`.
@Suite("AjustePorciones")
struct AjustePorcionesTests {
    static let avena = Alimento(nombre: "Avena", qty: 100, unidad: "g", kcal: 380, prot: 13, carb: 67, fat: 7)
    static let huevos = Alimento(nombre: "Huevos", qty: 3, unidad: "u", kcal: 234, prot: 18, carb: 0, fat: 18)
    static let banana = Alimento(nombre: "Banana", qty: 1, unidad: "u", kcal: 105, prot: 1, carb: 27, fat: 0)
    static let pollo = Alimento(nombre: "Pollo", qty: 200, unidad: "g", kcal: 330, prot: 62, carb: 0, fat: 7)
    static let arroz = Alimento(nombre: "Arroz", qty: 150, unidad: "g", kcal: 195, prot: 4, carb: 42, fat: 0.5)
    static let tostadas = Alimento(nombre: "Tostadas", qty: 2, unidad: "rebanada", kcal: 140, prot: 5, carb: 26, fat: 2)
    static let cafe = Alimento(nombre: "Café", qty: nil, unidad: nil, kcal: 0, prot: 0, carb: 0, fat: 0)
    static let aceite = Alimento(nombre: "Aceite de oliva", qty: 10, unidad: "g", kcal: 88, prot: 0, carb: 0, fat: 10)

    typealias C = AjustePorciones.ComidaDelDia
    static let desayuno = C(id: "desayuno", nombre: "Desayuno", opcion: 0, alimentos: [avena, huevos, banana])
    static let pre = C(id: "pre", nombre: "Pre-entreno", opcion: 0, alimentos: [banana, tostadas])
    static let almuerzo = C(id: "almuerzo", nombre: "Almuerzo", opcion: 0, alimentos: [pollo, arroz, aceite])
    static let merienda = C(id: "merienda", nombre: "Merienda", opcion: 0, alimentos: [cafe])

    /// Los casos de los vectores: nombre, comidas del día y ajustes.
    static let casos: [(String, [C], [String: AjusteComida])] = [
        ("sin ajustes", [desayuno, almuerzo], [:]),
        ("suma y compensa en la siguiente", [desayuno, almuerzo], ["desayuno": AjusteComida(deltaKcal: 200)]),
        ("suma sin compensar", [desayuno, almuerzo], ["desayuno": AjusteComida(deltaKcal: 200, compensar: false)]),
        ("resta y compensa", [desayuno, almuerzo], ["desayuno": AjusteComida(deltaKcal: -150)]),
        ("resta hasta el tope", [desayuno], ["desayuno": AjusteComida(deltaKcal: -5000)]),
        ("suma hasta el tope", [desayuno], ["desayuno": AjusteComida(deltaKcal: 9000)]),
        ("gramos a mano", [desayuno, almuerzo], ["desayuno": AjusteComida(cantidades: ["0": 60])]),
        ("gramos a mano y kcal", [desayuno, almuerzo], ["desayuno": AjusteComida(deltaKcal: 100, cantidades: ["0": 60])]),
        ("gramos de otra opción no valen", [desayuno], ["desayuno": AjusteComida(opcion: 1, cantidades: ["0": 50])]),
        ("no come el pre-entreno y lo pasa", [desayuno, pre, almuerzo], ["pre": AjusteComida(omitida: true)]),
        ("no come el pre-entreno y no lo pasa", [desayuno, pre, almuerzo], ["pre": AjusteComida(compensar: false, omitida: true)]),
        ("lo que llega a una omitida sigue de largo", [desayuno, pre, almuerzo],
         ["desayuno": AjusteComida(deltaKcal: 200), "pre": AjusteComida(compensar: false, omitida: true)]),
        ("lo que llega a una sin nada que escalar sigue de largo", [desayuno, merienda, almuerzo], ["desayuno": AjusteComida(deltaKcal: -100)]),
        ("la última no pasa nada", [almuerzo], ["almuerzo": AjusteComida(deltaKcal: 150)]),
        ("dos ajustes en cadena", [desayuno, pre, almuerzo],
         ["desayuno": AjusteComida(deltaKcal: 100), "pre": AjusteComida(deltaKcal: 50)]),
        ("recibe y suma lo suyo", [desayuno, almuerzo],
         ["desayuno": AjusteComida(deltaKcal: 200), "almuerzo": AjusteComida(deltaKcal: 100, compensar: false)]),
        ("lo que no entra en la siguiente pasa a la otra", [desayuno, almuerzo, pre], ["desayuno": AjusteComida(deltaKcal: 600)]),
        ("recibe al tope y suma lo suyo", [desayuno, almuerzo, pre],
         ["desayuno": AjusteComida(deltaKcal: 600), "almuerzo": AjusteComida(deltaKcal: 100, compensar: false)]),
        ("gramos a mano de otro alimento no valen", [almuerzo],
         ["almuerzo": AjusteComida(cantidades: ["0": 250], anclas: ["0": AnclaAlimento(nombre: "Arroz", unidad: "g")])]),
        ("gramos a mano del mismo alimento valen", [almuerzo],
         ["almuerzo": AjusteComida(cantidades: ["0": 250], anclas: ["0": AnclaAlimento(nombre: " pollo ", unidad: "gr")])]),
        ("gramos a mano en otra unidad no valen", [desayuno],
         ["desayuno": AjusteComida(cantidades: ["1": 5], anclas: ["1": AnclaAlimento(nombre: "Huevos", unidad: "g")])]),
    ]

    @Test func redondeaAPorcionesServibles() {
        #expect(AjustePorciones.redondear(113, unidad: "g") == 115)
        #expect(AjustePorciones.redondear(12.4, unidad: "g") == 12)
        #expect(AjustePorciones.redondear(3.3, unidad: "u") == 3.5)
        #expect(AjustePorciones.redondear(0.1, unidad: "u") == 0.5)
        #expect(AjustePorciones.redondear(2, unidad: "ml") == 2)
        #expect(AjustePorciones.redondear(.nan, unidad: "g") == 0)
    }

    @Test func pasoDeCadaAlimento() {
        #expect(AjustePorciones.pasoCantidad(Self.avena) == 10)
        #expect(AjustePorciones.pasoCantidad(Self.aceite) == 5)
        #expect(AjustePorciones.pasoCantidad(Self.huevos) == 0.5)
    }

    @Test func conCantidadEscalaLasMacros() {
        let a = AjustePorciones.conCantidad(Self.avena, 150)
        #expect(a.qty == 150 && a.kcal == 570 && a.prot == 19.5 && a.carb == 100.5 && a.fat == 10.5)
        #expect(AjustePorciones.conCantidad(Self.cafe, 10) == Self.cafe)   // sin cantidad no se toca
    }

    @Test func sumarKcalAgrandaTodoParejo() {
        let r = AjustePorciones.escalar([Self.avena, Self.huevos, Self.banana], deltaKcal: 200)
        // Factor 919/719 ≈ 1,28 y redondeo (130 g, 4 u, 1,5 u = 964 kcal); el afinado lo baja de a 5 g hasta ≈ 919.
        #expect(abs(AjustePorciones.kcal(r) - 919) < 10, "\(AjustePorciones.kcal(r))")
        // Pedido más: ningún alimento queda por debajo del plan.
        #expect(zip(r, [Self.avena, Self.huevos, Self.banana]).allSatisfy { ($0.qty ?? 0) >= ($1.qty ?? 0) })
    }

    @Test func restarNuncaAgrandaUnAlimento() {
        for delta in stride(from: -50.0, through: -500, by: -50) {
            let r = AjustePorciones.escalar([Self.avena, Self.huevos, Self.banana, Self.aceite], deltaKcal: delta)
            #expect(zip(r, [Self.avena, Self.huevos, Self.banana, Self.aceite]).allSatisfy { ($0.qty ?? 0) <= ($1.qty ?? 0) }, "\(delta)")
        }
        for delta in stride(from: 50.0, through: 600, by: 50) {
            let r = AjustePorciones.escalar([Self.avena, Self.huevos, Self.banana, Self.aceite], deltaKcal: delta)
            #expect(zip(r, [Self.avena, Self.huevos, Self.banana, Self.aceite]).allSatisfy { ($0.qty ?? 0) >= ($1.qty ?? 0) }, "\(delta)")
            let plan = AjustePorciones.kcal([Self.avena, Self.huevos, Self.banana, Self.aceite])
            #expect(abs(AjustePorciones.kcal(r) - plan - delta) <= 25, "\(delta): \(AjustePorciones.kcal(r) - plan)")
        }
    }

    @Test func lasCantidadesAManoSeRespetan() {
        let r = AjustePorciones.escalar([Self.avena, Self.huevos], deltaKcal: 0, cantidades: [0: 60])
        #expect(r[0].qty == 60 && r[0].kcal == 228 && r[1].qty == 3)
        let s = AjustePorciones.escalar([Self.avena, Self.huevos], deltaKcal: 100, cantidades: [0: 60])
        #expect(s[0].qty == 60)      // la puesta a mano no se mueve
        #expect(s[1].qty == 4.5)     // las +100 van a los huevos: 3 × 334/234 = 4,3 → 4,5 (no hay otro con qué afinar)
    }

    @Test func compensaEnLaSiguienteYElDiaQuedaCercaDelPlan() {
        let d = AjustePorciones.dia([Self.desayuno, Self.almuerzo], ajustes: ["desayuno": AjusteComida(deltaKcal: 200)])
        let des = d["desayuno"]!, alm = d["almuerzo"]!
        #expect(des.ajustada && des.deltaPropio == 200)
        #expect(alm.compensaDe == ["Desayuno"] && alm.compensacion == -(des.kcal - des.kcalPlan))
        #expect(alm.kcal < alm.kcalPlan && alm.ajustada)
        #expect(abs((des.kcal + alm.kcal) - (des.kcalPlan + alm.kcalPlan)) < 60)
    }

    @Test func sinCompensarElDiaSube() {
        let d = AjustePorciones.dia([Self.desayuno, Self.almuerzo], ajustes: ["desayuno": AjusteComida(deltaKcal: 100, compensar: false)])
        #expect(d["almuerzo"]!.compensacion == 0 && !d["almuerzo"]!.ajustada)
    }

    @Test func noComerElPreEntrenoLoPasaAlAlmuerzo() {
        let d = AjustePorciones.dia([Self.desayuno, Self.pre, Self.almuerzo], ajustes: ["pre": AjusteComida(omitida: true)])
        #expect(d["pre"]!.omitida && d["pre"]!.kcal == 0)
        #expect(d["almuerzo"]!.compensacion == d["pre"]!.kcalPlan && d["almuerzo"]!.compensaDe == ["Pre-entreno"])
        #expect(d["desayuno"]!.compensacion == 0)
    }

    @Test func loQueLlegaAUnaOmitidaSigueDeLargo() {
        let d = AjustePorciones.dia([Self.desayuno, Self.pre, Self.almuerzo],
                                    ajustes: ["desayuno": AjusteComida(deltaKcal: 200), "pre": AjusteComida(compensar: false, omitida: true)])
        let des = d["desayuno"]!
        #expect(d["pre"]!.noAbsorbido == -(des.kcal - des.kcalPlan))
        #expect(d["almuerzo"]!.compensacion == d["pre"]!.noAbsorbido && d["almuerzo"]!.compensaDe == ["Desayuno"])
    }

    @Test func loQueLlegaAUnaComidaSinNadaQueEscalarSigue() {
        let d = AjustePorciones.dia([Self.desayuno, Self.merienda, Self.almuerzo], ajustes: ["desayuno": AjusteComida(deltaKcal: -100)])
        #expect(d["merienda"]!.noAbsorbido != 0 && !d["merienda"]!.ajustada)
        #expect(d["almuerzo"]!.compensacion == d["merienda"]!.noAbsorbido)
    }

    @Test func soloRecibirNoPasaElRedondeo() {
        // El almuerzo recibe −X y lo absorbe con redondeo: no le pasa ese resto a nadie (no tiene ajuste propio).
        let d = AjustePorciones.dia([Self.desayuno, Self.almuerzo, Self.pre], ajustes: ["desayuno": AjusteComida(deltaKcal: 200)])
        #expect(d["pre"]!.compensacion == 0)
    }

    @Test func laUltimaComidaNoPasaNadaYAvisaLoQueQueda() {
        let comidas = [Self.desayuno, Self.merienda]
        let d = AjustePorciones.dia(comidas, ajustes: ["desayuno": AjusteComida(deltaKcal: 100)])
        #expect(AjustePorciones.sinCompensar(comidas, d) != 0)
        let e = AjustePorciones.dia([Self.almuerzo], ajustes: ["almuerzo": AjusteComida(deltaKcal: 150)])
        #expect(abs(e["almuerzo"]!.kcal - e["almuerzo"]!.kcalPlan - 150) < 5)
    }

    @Test func loQueNoEntraPorElTopeSigueALaOtra() {
        let d = AjustePorciones.dia([Self.desayuno, Self.almuerzo, Self.pre], ajustes: ["desayuno": AjusteComida(deltaKcal: 600)])
        let des = d["desayuno"]!, alm = d["almuerzo"]!, pre = d["pre"]!
        // El almuerzo baja hasta un cuarto (−460 de 613) y lo que falta va al pre-entreno, que lo puede absorber.
        #expect(alm.compensacion == -des.propio)
        #expect(alm.noAbsorbido == jsRound(alm.compensacion + 613 * 0.75) && alm.noAbsorbido < -100)
        #expect(pre.compensacion == alm.noAbsorbido && pre.compensaDe == ["Desayuno"] && pre.noAbsorbido == 0)
        let plan = des.kcalPlan + alm.kcalPlan + pre.kcalPlan, hoy = des.kcal + alm.kcal + pre.kcal
        #expect(abs(hoy - plan) < 40, "\(hoy - plan)")
        #expect(AjustePorciones.sinCompensar([Self.desayuno, Self.almuerzo, Self.pre], d) == 0)
    }

    @Test func loPropioVaPrimeroYLoQueLlegaEntraEnLoQueQueda() {
        let d = AjustePorciones.dia([Self.desayuno, Self.almuerzo, Self.pre],
                                    ajustes: ["desayuno": AjusteComida(deltaKcal: 600), "almuerzo": AjusteComida(deltaKcal: 100, compensar: false)])
        let alm = d["almuerzo"]!
        // Con sus +100 el almuerzo tiene más lugar para bajar: absorbe 613 × (1,163 − 0,25) ≈ 560 y pasan ≈ 40.
        #expect(abs(alm.absorbido + 560) <= 1 && d["pre"]!.compensacion == alm.noAbsorbido)
        #expect(abs(alm.propio - 100) <= 25, "\(alm.propio)")
    }

    @Test func propioEsLoQueHizoElCliente() {
        let d = AjustePorciones.dia([Self.desayuno, Self.pre, Self.almuerzo],
                                    ajustes: ["desayuno": AjusteComida(deltaKcal: 200), "pre": AjusteComida(omitida: true)])
        #expect(abs(d["desayuno"]!.propio - 200) <= 25)
        #expect(d["pre"]!.propio == -245)          // sin comerla: todo el plan
        #expect(d["almuerzo"]!.propio == 0)        // solo recibe
        #expect(d["pre"]!.absorbido == 0 && d["almuerzo"]!.absorbido == d["almuerzo"]!.compensacion)
    }

    @Test func lasCantidadesSeAnclanAlAlimento() {
        let a = AjustePorciones.anclar(AjusteComida(deltaKcal: 50, cantidades: ["0": 60, "7": 10]), en: Self.desayuno)
        #expect(a.cantidades == ["0": 60] && a.anclas == ["0": AnclaAlimento(nombre: "Avena", unidad: "g")])
        // Mati vuelve a publicar con otro alimento en esa posición: la cantidad no vale y al guardar se va.
        let otra = C(id: "desayuno", nombre: "Desayuno", opcion: 0, alimentos: [Self.aceite, Self.huevos, Self.banana])
        #expect(AjustePorciones.cantidadesValidas(otra, a).isEmpty)
        let b = AjustePorciones.anclar(a, en: otra)
        #expect(b.cantidades.isEmpty && b.anclas.isEmpty && b.deltaKcal == 50)
        // De otra opción tampoco.
        #expect(AjustePorciones.anclar(AjusteComida(opcion: 1, cantidades: ["0": 60]), en: Self.desayuno).neutro)
        #expect(AnclaAlimento(nombre: "Avena", unidad: "gramos").coincide(con: Self.avena))
        #expect(!AnclaAlimento(nombre: "Avena", unidad: "taza").coincide(con: Self.avena))
    }

    @Test func laBaseNoCuentaLoPuestoAMano() {
        #expect(AjustePorciones.baseEscalable(Self.desayuno, nil) == 719)
        #expect(AjustePorciones.baseEscalable(Self.desayuno, AjusteComida(cantidades: ["0": 60])) == 339)
        #expect(AjustePorciones.baseEscalable(Self.merienda, nil) == 0)
    }

    @Test func elDestinoSaltaLaQueNoSeComeYLaQueNoEscala() {
        let comidas = [Self.desayuno, Self.pre, Self.merienda, Self.almuerzo]
        let aj = ["pre": AjusteComida(omitida: true)]
        #expect(AjustePorciones.destino(comidas, ajustes: aj, despuesDe: "desayuno")?.id == "almuerzo")
        #expect(AjustePorciones.destino(comidas, ajustes: [:], despuesDe: "desayuno")?.id == "pre")
        #expect(AjustePorciones.destino(comidas, ajustes: [:], despuesDe: "almuerzo") == nil)
    }

    @Test func elEfectoEsLoQueCambiaEnElRestoDelDia() {
        let comidas = [Self.desayuno, Self.almuerzo, Self.pre]
        let e = AjustePorciones.efecto(comidas, ajustes: ["desayuno": AjusteComida(deltaKcal: 600)], de: "desayuno")
        #expect(e.cambios.map(\.id) == ["almuerzo", "pre"] && e.sinCompensar == 0)
        #expect(e.cambios.allSatisfy { $0.kcal < 0 })
        // Sin compensar no cambia nada más; en la última, lo que no entra queda sin compensar.
        #expect(AjustePorciones.efecto(comidas, ajustes: ["desayuno": AjusteComida(deltaKcal: 600, compensar: false)], de: "desayuno").cambios.isEmpty)
        let ultima = AjustePorciones.efecto([Self.desayuno, Self.pre], ajustes: ["desayuno": AjusteComida(deltaKcal: 600)], de: "desayuno")
        #expect(ultima.cambios.map(\.id) == ["pre"] && ultima.sinCompensar < -300)
    }

    @Test func neutroYLecturaTolerante() throws {
        #expect(AjusteComida().neutro)
        #expect(!AjusteComida(deltaKcal: 50).neutro && !AjusteComida(omitida: true).neutro && !AjusteComida(cantidades: ["0": 10]).neutro)
        let viejo = try JSONDecoder().decode(AjusteComida.self, from: Data(#"{"deltaKcal":100,"cantidades":{"0":-5,"1":30}}"#.utf8))
        #expect(viejo.deltaKcal == 100 && viejo.compensar && !viejo.omitida && viejo.cantidades == ["1": 30] && viejo.anclas.isEmpty)
        let conAnclas = try JSONDecoder().decode(AjusteComida.self, from: Data(#"{"cantidades":{"1":30},"anclas":{"1":{"nombre":"Huevos","unidad":"u"}}}"#.utf8))
        #expect(conAnclas.anclas == ["1": AnclaAlimento(nombre: "Huevos", unidad: "u")])
    }

    // MARK: - Vectores compartidos con Android

    static var archivo: URL { raizRepo.appendingPathComponent("apps/shared/vectores/ajuste_porciones.json") }

    static func json(_ a: Alimento) -> [String: Any] {
        var d: [String: Any] = ["name": a.nombre]
        if let q = a.qty { d["qty"] = q }
        if let u = a.unidad { d["unit"] = u }
        if let v = a.kcal { d["kcal"] = v }
        if let v = a.prot { d["prot"] = v }
        if let v = a.carb { d["carb"] = v }
        if let v = a.fat { d["fat"] = v }
        return d
    }

    static func salida(_ comidas: [C], _ ajustes: [String: AjusteComida]) -> [String: Any] {
        let d = AjustePorciones.dia(comidas, ajustes: ajustes)
        var r: [String: Any] = [:]
        for c in comidas {
            let x = d[c.id]!
            r[c.id] = ["qty": x.alimentos.map { $0.qty as Any? ?? NSNull() }, "kcal": x.alimentos.map { $0.kcal ?? 0 },
                       "prot": x.alimentos.map { $0.prot ?? 0 }, "carb": x.alimentos.map { $0.carb ?? 0 },
                       "fat": x.alimentos.map { $0.fat ?? 0 }, "kcalPlan": x.kcalPlan, "kcalDia": x.kcal,
                       "deltaPropio": x.deltaPropio, "omitida": x.omitida, "compensacion": x.compensacion,
                       "compensaDe": x.compensaDe, "noAbsorbido": x.noAbsorbido, "cambiados": x.cambiados.sorted(),
                       "propio": x.propio]
        }
        r["_sinCompensar"] = AjustePorciones.sinCompensar(comidas, d)
        return r
    }

    @Test func generarVectores() throws {
        guard ProcessInfo.processInfo.environment["GENERAR_VECTORES_AJUSTE"] == "1" else { return }
        let casos: [[String: Any]] = Self.casos.map { nombre, comidas, ajustes in
            ["nombre": nombre,
             "comidas": comidas.map { ["id": $0.id, "nombre": $0.nombre, "opcion": $0.opcion, "alimentos": $0.alimentos.map(Self.json)] },
             "ajustes": ajustes.mapValues { a in ["deltaKcal": a.deltaKcal, "compensar": a.compensar, "omitida": a.omitida,
                                                  "opcion": a.opcion, "cantidades": a.cantidades,
                                                  "anclas": a.anclas.mapValues { an in ["nombre": an.nombre, "unidad": an.unidad as Any? ?? NSNull()] }] },
             "esperado": Self.salida(comidas, ajustes)]
        }
        let todo: [String: Any] = ["generado": "MyPumpKit AjustePorcionesTests (iOS). Android: AjustePorcionesTest.kt lo tiene que dar igual.",
                                   "casos": casos]
        let datos = try JSONSerialization.data(withJSONObject: todo, options: [.prettyPrinted, .sortedKeys])
        try datos.write(to: Self.archivo)
    }

    /// Lo grabado tiene que seguir saliendo igual (si cambia la regla a propósito, se regeneran y se revisa el diff).
    @Test func losVectoresSiguenIguales() throws {
        let datos = try Data(contentsOf: Self.archivo)
        let todo = try JSONSerialization.jsonObject(with: datos) as! [String: Any]
        let casos = todo["casos"] as! [[String: Any]]
        #expect(casos.count == Self.casos.count)
        for (i, (nombre, comidas, ajustes)) in Self.casos.enumerated() {
            let grabado = casos[i]
            #expect(grabado["nombre"] as? String == nombre)
            let ahora = try JSONSerialization.data(withJSONObject: Self.salida(comidas, ajustes), options: .sortedKeys)
            let antes = try JSONSerialization.data(withJSONObject: grabado["esperado"]!, options: .sortedKeys)
            let a = try JSONSerialization.jsonObject(with: ahora) as! NSDictionary
            let b = try JSONSerialization.jsonObject(with: antes) as! NSDictionary
            #expect(a == b, "\(nombre)")
        }
    }
}
