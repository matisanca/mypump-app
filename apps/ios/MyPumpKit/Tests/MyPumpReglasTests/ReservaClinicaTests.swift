import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

/// Reserva clínica (19/11, OK de Mati): el plan que deja reps en reserva a propósito nunca ve «Al fallo», «llevá al
/// fallo» ni «Subí la carga»; ve la pauta del plan. Mismos vectores que la web y Android (`reserva_clinica.json`).
final class ReservaClinicaTests: XCTestCase {
    private var v: [String: Any] {
        get throws {
            let url = raizRepo.appendingPathComponent("apps/shared/vectores/reserva_clinica.json")
            return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        }
    }
    private func texto(_ x: Any?) -> String? { x == nil || x is NSNull ? nil : (x as? String) ?? (x as? NSNumber).map { "\($0)" } }
    private func decodificar<T: Decodable>(_ t: T.Type, _ x: Any) throws -> T {
        try JSONDecoder().decode(t, from: JSONSerialization.data(withJSONObject: x))
    }
    private func dia(_ ejercicios: Any) throws -> Dia { try decodificar(Dia.self, ["id": "d1", "bloques": [["ejercicios": ejercicios]]]) }
    private func prohibido() throws -> NSRegularExpression {
        try NSRegularExpression(pattern: try v["prohibido"] as! String, options: .caseInsensitive)
    }
    private func nota(_ n: NotaProgresion?) -> [String: AnyHashable]? {
        n.map { ["texto": $0.texto, "cambia": $0.cambia, "calibracion": $0.calibracion] }
    }
    private func esperada(_ x: Any?) -> [String: AnyHashable]? {
        (x as? [String: Any]).map { ["texto": $0["texto"] as! String, "cambia": $0["cambia"] as! Bool, "calibracion": $0["calibracion"] as! Bool] }
    }

    func testCuandoElRirPideReserva() throws {
        let i = try v["indicada"] as! [String: [Any]]
        for x in i["si"]! { XCTAssertTrue(ReservaClinica.indicada(texto(x)), "\(x)") }
        for x in i["no"]! { XCTAssertFalse(ReservaClinica.indicada(texto(x)), "\(x)") }
    }

    func testLeyendaConReserva() throws {
        for c in try v["leyenda"] as! [[String: Any]] {
            XCTAssertEqual(ReservaClinica.leyenda(texto(c["rir"])), texto(c["sale"]), "\(c)")
        }
        XCTAssertEqual(ReservaClinica.frase("Dejando 2–3 en reserva"), " dejando 2–3 en reserva")
        XCTAssertEqual(ReservaClinica.frase(nil), "")
    }

    func testQuePlanesTienenReserva() throws {
        let planes = try v["planes"] as! [[String: Any]]
        XCTAssertEqual(planes.count, 10)
        for c in planes {
            XCTAssertEqual(ReservaClinica.delPlan([try dia(c["ejercicios"]!)], semana: c["semana"] as? Int), c["sale"] as! Bool, c["nombre"] as! String)
        }
        XCTAssertFalse(ReservaClinica.delPlan([], semana: 1))
    }

    func testLaNotaEsLaPautaDelPlan() throws {
        let re = try prohibido()
        for c in try v["notas"] as! [[String: Any]] {
            let e = try decodificar(Ejercicio.self, c["ejercicio"]!)
            let semana = c["semana"] as? Int
            let con = Progresiones.nota(e, semanaActual: semana, reservaClinica: true)
            XCTAssertEqual(nota(con), esperada(c["sale"]), "con reserva: \(c["nombre"]!)")
            XCTAssertEqual(nota(Progresiones.nota(e, semanaActual: semana)), esperada(c["sinReserva"]), "sin reserva: \(c["nombre"]!)")
            let t = con!.texto
            XCTAssertNil(re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), t)
        }
    }

    func testSinCartelConReserva() throws {
        for c in try v["banner"] as! [[String: Any]] {
            let d = try dia(c["ejercicios"]!)
            let semana = c["semana"] as! Int, offset = c["offset"] as! Int
            let sin = SemanaEntreno.banner(d, semana: semana, offset: offset)
            let con = SemanaEntreno.banner(d, semana: semana, offset: offset, reservaClinica: true)
            let es = c["sinReserva"] as! [String: Any], ec = c["conReserva"] as! [String: Any]
            XCTAssertEqual([sin.cambian, sin.calibracion ? 1 : 0], [es["cambian"] as! Int, (es["calibracion"] as! Bool) ? 1 : 0], c["nombre"] as! String)
            XCTAssertEqual([con.cambian, con.calibracion ? 1 : 0], [ec["cambian"] as! Int, (ec["calibracion"] as! Bool) ? 1 : 0], c["nombre"] as! String)
            XCTAssertNil(con.texto)
        }
    }

    func testLaCargaNuncaSugiereSubirConReserva() throws {
        for c in try v["aumento"] as! [[String: Any]] {
            let e = try decodificar(Ejercicio.self, c["ejercicio"]!)
            let semana = c["semana"] as! Int
            let refs = (c["ultimaVez"] as! [[String: Any]]).map { CargaSimple.Referencia(reps: $0["reps"] as! Int, kg: ($0["kg"] as? NSNumber)?.doubleValue) }
            let equipo = Preparacion.Equipo(rawValue: c["equipo"] as! String)!
            func armar(_ reserva: Bool, _ estado: CargaSimple.Estado? = nil) -> CargaSimple {
                CargaSimple(ejercicio: e, semana: semana, ultimaVez: refs, equipo: equipo, estado: estado, reservaClinica: reserva)
            }
            let es = c["sinReserva"] as! [String: Any]
            var sin = armar(false)
            XCTAssertEqual(sin.aumento, .sugerido(desde: es["desde"] as! Double, hasta: es["hasta"] as! Double), c["nombre"] as! String)
            XCTAssertEqual(armar(true).aumento, .noCorresponde, c["nombre"] as! String)
            XCTAssertTrue(AumentoCarga.corresponde(e, semana: semana))
            XCTAssertFalse(AumentoCarga.corresponde(e, semana: semana, reservaClinica: true))
            // Guardado antes de este arreglo con la sugerencia: con reserva se cae y la carga sigue en la de la última vez.
            let guardado = sin.estado
            XCTAssertEqual(armar(true, guardado).aumento, .noCorresponde)
            XCTAssertEqual(armar(true, guardado).carga, es["desde"] as? Double)
            XCTAssertEqual(armar(false, guardado).aumento, sin.aumento)
            // Lo que el alumno ya aceptó, queda.
            sin.aceptarAumento()
            guard case .aceptado = armar(true, sin.estado).aumento else { return XCTFail("lo aceptado se perdió") }
        }
    }

    func testLaLeyendaDelDia() throws {
        let c = (try v["planes"] as! [[String: Any]])[0]   // 2-3 en todas las semanas
        let d = DiaEnCurso(dia: try dia(c["ejercicios"]!), semana: 2)
        let id = d.lista[0].id
        XCTAssertEqual(d.leyendaRIR(id), "Al fallo", "sin reserva clínica, como siempre (2.3.0)")
        XCTAssertEqual(d.leyendaRIR(id, reservaClinica: true), "Dejando 2–3 en reserva")
        XCTAssertNil(d.leyendaRIR(d.lista[1].id, reservaClinica: true), "la plancha no lleva RIR")
        // Una semana sin rir en un plan con reserva (el taper): ninguna leyenda, nunca «Al fallo».
        let taper: [[String: Any]] = [["id": "a", "nombre": "Sentadilla con barra", "tipo": "compuesto", "progresion": [
            ["semana": 1, "series": 3, "reps": "3", "rir": "3"], ["semana": 2, "series": 3, "reps": "2", "rir": NSNull()],
            ["semana": 3, "series": 3, "reps": "8", "rir": "1-2"]]]]
        let dt = DiaEnCurso(dia: try dia(taper), semana: 2)
        XCTAssertTrue(ReservaClinica.delPlan([dt.dia], semana: 2))
        XCTAssertNil(dt.leyendaRIR(dt.lista[0].id, reservaClinica: true))
        XCTAssertEqual(dt.leyendaRIR(dt.lista[0].id), "Al fallo")
        // El aviso de primera vez sigue a la leyenda.
        XCTAssertEqual(RIRDelPlan.calibracion("llegues a 10 reps dejando 1–2 en reserva.", leyenda: "Dejando 2–3 en reserva"), "llegues a 10 reps dejando 2–3 en reserva.")
        XCTAssertEqual(RIRDelPlan.calibracion("llegues a 10 reps dejando 1–2 en reserva.", leyenda: nil), "llegues a 10 reps.")
    }

    func testLaNotaTecnicaVaEnteraConReserva() {
        let n = "Dejá 2 repeticiones en reserva y bajá controlado."
        XCTAssertEqual(TextoAlumno.notaParaAlumno(n, rir: nil, clinica: true), n)
        XCTAssertEqual(TextoAlumno.notaParaAlumno(n, rir: "0"), TextoAlumno.sinRIR(n))
        XCTAssertEqual(TextoAlumno.notaParaAlumno("Cerca del fallo, sin trampa.", rir: nil, clinica: true), "Cerca del fallo, sin trampa.")
    }
}
