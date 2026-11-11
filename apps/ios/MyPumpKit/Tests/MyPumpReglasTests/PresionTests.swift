import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

/// Los vectores que comparten la web, Android y el servidor (`apps/shared/vectores/presion.json`). Se recorre TODO el archivo y
/// se compara la salida completa.
final class PresionTests: XCTestCase {
    private func vectores() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/vectores/presion.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }
    private func n(_ i: Int) -> JSONValue { .numero(Double(i)) }
    private func n(_ i: Int?) -> JSONValue { i.map { .numero(Double($0)) } ?? .null }
    private func t(_ s: String?) -> JSONValue { s.map(JSONValue.texto) ?? .null }
    private func textos(_ xs: [String]) -> JSONValue { .lista(xs.map(JSONValue.texto)) }
    private func valor(_ v: Presion.Valor?) -> JSONValue {
        v.map { .objeto(["sis": n($0.sis), "dia": n($0.dia), "pulso": n($0.pulso)]) } ?? .null
    }

    private func json(_ e: Presion.Evaluacion) -> JSONValue {
        let o: JSONValue = e.ortostatica.map {
            .objeto(["caida_sis_max": n($0.caidaSisMax), "caida_dia_max": n($0.caidaDiaMax), "subida_pulso_max": n($0.subidaPulsoMax),
                     "hipotension": .bool($0.hipotension), "hipertension_posible": .bool($0.hipertensionPosible)])
        } ?? .null
        return .objeto(["paso": .texto(e.paso.rawValue), "texto": .texto(e.texto), "cuenta": .bool(e.cuenta), "motivo_exclusion": t(e.motivoExclusion),
                        "valor": valor(e.valor), "valida_bajo_efecto": .bool(e.validaBajoEfecto), "urgencia": .bool(e.urgencia), "ortostatica": o,
                        "reglas": textos(e.reglas)])
    }

    private func json(_ r: Presion.ResumenSerie) -> JSONValue {
        .objeto(["tomas_validas": n(r.tomasValidas), "dias": textos(r.dias), "serie_valida": .bool(r.serieValida), "faltan": n(r.faltan),
                 "promedio": valor(r.promedio), "maximos": r.maximos.map { .objeto(["sis": n($0.sis), "dia": n($0.dia)]) } ?? .null,
                 "categoria": t(r.categoria),
                 "bajo_efecto": .objeto(["n": n(r.bajoEfecto.n), "validas": n(r.bajoEfecto.validas), "promedio": valor(r.bajoEfecto.promedio),
                                         "tomas_pulso_100_o_mas": n(r.bajoEfecto.tomasPulso100OMas), "aviso": .bool(r.bajoEfecto.aviso), "alta": .bool(r.bajoEfecto.alta)]),
                 "reglas": textos(r.reglas)])
    }

    /// Ninguna clave del archivo queda sin recorrer: si los vectores suman una, esta prueba falla hasta que se cubra.
    func testSeRecorreTodoElArchivo() throws {
        guard case .objeto(let o) = try vectores() else { return XCTFail() }
        XCTAssertEqual(Set(o.keys), ["_", "limites", "espera_repeticion_s", "reposo_s", "recordatorio_min", "sin_repetir_min", "alarma", "otros", "sintomas",
                                     "validar", "nivel", "tramo", "calza", "metodo", "momento", "pasos", "sesion", "serie", "textos", "propios"])
    }

    func testConstantes() throws {
        let v = try vectores()
        XCTAssertEqual(v["limites"], .objeto(["sisMin": n(Presion.Lim.sisMin), "sisMax": n(Presion.Lim.sisMax), "diaMin": n(Presion.Lim.diaMin), "diaMax": n(Presion.Lim.diaMax),
                                              "pulMin": n(Presion.Lim.pulMin), "pulMax": n(Presion.Lim.pulMax), "difMin": n(Presion.Lim.difMin)]))
        XCTAssertEqual(v["espera_repeticion_s"], n(Presion.esperaRepeticionS))
        XCTAssertEqual(v["reposo_s"], n(Presion.reposoS))
        XCTAssertEqual(v["recordatorio_min"], n(Presion.recordatorioMin))
        XCTAssertEqual(v["sin_repetir_min"], n(Presion.sinRepetirMin))
        XCTAssertEqual(v["alarma"], textos(Presion.alarma))
        XCTAssertEqual(v["otros"], textos(Presion.otros))
        XCTAssertEqual(v["sintomas"], .objeto(TextosPresion.sintomas.mapValues(JSONValue.texto)))
    }

    func testTextos() throws {
        let v = try vectores()
        guard case .objeto(let esperados)? = v["textos"], case .objeto(let mios) = TextosPresion.T.todos else { return XCTFail() }
        XCTAssertEqual(Set(mios.keys), Set(esperados.keys))
        for (k, e) in esperados { XCTAssertEqual(mios[k], e, "textos.\(k)") }
        guard case .objeto(let propios)? = v["propios"], case .objeto(let misN) = TextosPresion.N.todos else { return XCTFail() }
        // Igualdad total con los vectores: ni un texto de más ni uno de menos.
        XCTAssertEqual(Set(misN.keys), Set(propios.keys))
        for (k, e) in propios { XCTAssertEqual(misN[k], e, "propios.\(k)") }
    }

    /// El alumno no lee ninguna de estas palabras, y los textos no llevan «:», «;» ni guiones.
    func testTextosSinPalabrasVedadas() {
        var todos: [String] = []
        func juntar(_ j: JSONValue) {
            switch j {
            case .texto(let s): todos.append(s)
            case .lista(let l): l.forEach(juntar)
            case .objeto(let o): o.values.forEach(juntar)
            default: break
            }
        }
        juntar(TextosPresion.T.todos); juntar(TextosPresion.N.todos)
        todos.append(contentsOf: TextosPresion.sintomas.values)
        XCTAssertGreaterThan(todos.count, 150)
        for s in todos {
            let m = s.lowercased()
            for vedada in ["hipertens", "normal", "riesgo", "promedio de", "tu coach", "tu entrenador", " ia ", "inteligencia artificial"] {
                XCTAssertFalse(m.contains(vedada), "«\(s)» dice \(vedada)")
            }
            XCTAssertFalse(s.contains(":") || s.contains(";") || s.contains(" - ") || s.contains("—") || s.contains("–"), "«\(s)»")
        }
    }

    func testValidarNivelTramoMomento() throws {
        let v = try vectores()
        XCTAssertEqual(lista(v["validar"]).count, 21)
        for c in lista(v["validar"]) {
            let toma = c["toma"]
            XCTAssertEqual(Presion.validarToma(sis: toma?["sis"]?.comoNumero, dia: toma?["dia"]?.comoNumero, pulso: toma?["pulso"]?.comoNumero).rawValue, c["sale"]?.comoTexto, "\(c)")
        }
        XCTAssertFalse(lista(v["nivel"]).isEmpty)
        for c in lista(v["nivel"]) {
            XCTAssertEqual(Presion.nivelToma(sis: Int(c["toma"]!["sis"]!.comoNumero!), dia: Int(c["toma"]!["dia"]!.comoNumero!)).rawValue, c["sale"]?.comoTexto, "\(c)")
        }
        XCTAssertFalse(lista(v["tramo"]).isEmpty)
        for c in lista(v["tramo"]) { XCTAssertEqual(t(Presion.tramoBrazo(c["cm"]?.comoNumero)), c["sale"], "\(c)") }
        XCTAssertFalse(lista(v["momento"]).isEmpty)
        for c in lista(v["momento"]) { XCTAssertEqual(Presion.momento(Int(c["hora"]!.comoNumero!)), c["sale"]?.comoTexto, "\(c)") }
    }

    func testCalzaYMetodo() throws {
        let v = try vectores()
        XCTAssertFalse(lista(v["calza"]).isEmpty)
        for c in lista(v["calza"]) {
            let sale: JSONValue = Presion.manguitoCalza(c["cm"]?.comoNumero, Presion.Aparato(c["aparato"])).map(JSONValue.bool) ?? .null
            XCTAssertEqual(sale, c["sale"], "\(c)")
        }
        XCTAssertFalse(lista(v["metodo"]).isEmpty)
        for c in lista(v["metodo"]) {
            let m = Presion.metodo(c["cm"]?.comoNumero, Presion.Aparato(c["aparato"]))
            let sale: JSONValue = .objeto(["metodo": .texto(m.metodo), "provisoria": .bool(m.provisoria), "pedir_brazo": .bool(m.pedirBrazo),
                                           "pedir_validado": .bool(m.pedirValidado), "admite_tomas": .bool(m.admiteTomas)])
            XCTAssertEqual(sale, c["sale"], "\(c)")
        }
        XCTAssertNil(Presion.manguitoCalza(35, nil))
        XCTAssertEqual(Presion.metodo(35, nil), Presion.Metodo())
    }

    func testPasos() throws {
        let v = try vectores()
        XCTAssertFalse(lista(v["pasos"]).isEmpty)
        for c in lista(v["pasos"]) {
            let sale: JSONValue = .lista(Presion.pasos(c["tipo"]!.comoTexto!, c["variante"]?.comoTexto).map {
                .objeto(["espera_s": n($0.esperaS), "posicion": .texto($0.posicion), "minutos_de_pie": n($0.minutosDePie), "brazo": t($0.brazo)])
            })
            XCTAssertEqual(sale, c["sale"], "\(c)")
        }
    }

    func testSesion() throws {
        let v = try vectores()
        XCTAssertEqual(lista(v["sesion"]).count, 50)
        for c in lista(v["sesion"]) {
            XCTAssertEqual(json(Presion.evaluarSesion(Presion.Sesion(c["entrada"]!))), c["sale"], c["nombre"]?.comoTexto ?? "")
        }
    }

    func testSerie() throws {
        let v = try vectores()
        XCTAssertEqual(lista(v["serie"]).count, 24)
        for c in lista(v["serie"]) {
            let e = c["entrada"]!
            let entrada = Presion.EntradaSerie(
                tipo: e["serie"]?["tipo"]?.comoTexto, tomasObjetivo: e["serie"]?["tomas_objetivo"]?.comoNumero.map { Int($0) }, fechaInicio: e["serie"]?["fecha_inicio"]?.comoTexto,
                sesiones: lista(e["sesiones"]).map(Presion.Sesion.init), soloUrgencias: e["solo_urgencias"] == .bool(true), basalPulso: e["basal_pulso"]?.comoNumero.map { Int($0) })
            XCTAssertEqual(json(Presion.resumenSerie(entrada)), c["sale"], c["nombre"]?.comoTexto ?? "")
        }
    }

    func testMediaConCuentasEnteras() {
        XCTAssertEqual(Presion.media([124]), 124)
        XCTAssertEqual(Presion.media([160, 165]), 163)   // 162,5 sube
        XCTAssertEqual(Presion.media([130, 134, 131]), 132)   // 131,67
        XCTAssertEqual(Presion.media([1, 2, 2]), 2)
        XCTAssertEqual(Presion.media([]), 0)
    }

    func testDeAlarma() {
        XCTAssertTrue(Presion.deAlarma(["palpitaciones", "confusion"]))
        XCTAssertTrue(Presion.deAlarma(["desmayo_en_esfuerzo"]))
        XCTAssertFalse(Presion.deAlarma(Presion.otros))
        XCTAssertFalse(Presion.deAlarma([]))
    }
}
