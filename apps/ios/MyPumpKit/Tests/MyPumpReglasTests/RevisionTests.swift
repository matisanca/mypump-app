import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

private func salud(_ filas: [(String, Double?, String)]) -> [FilaSalud] {
    let json: JSONValue = .lista(filas.map { f in
        .objeto(["fecha": .texto(f.0), "tipo": .texto("peso_kg"), "valor": f.1.map(JSONValue.numero) ?? .null, "fuente": .texto(f.2)])
    })
    return try! JSONDecoder().decode([FilaSalud].self, from: JSONEncoder().encode(json))
}

@Suite("Revisión: peso y check, como la web")
struct RevisionTests {
    @Test func laSerieDaPrioridadALoManualYDescartaCeros() {
        let s = PesoCorporal.serie(salud([("2026-10-12", 82.4, "apple_health"), ("2026-10-12", 82.0, "manual"),
                                          ("2026-10-10", 82.1, "manual"), ("2026-10-11", 0, "manual"), ("2026-10-09", nil, "manual")]))
        #expect(s == [.init(fecha: "2026-10-10", kg: 82.1), .init(fecha: "2026-10-12", kg: 82.0)])
    }

    @Test func mediaDeSieteDiasYDeltaSemanal() {
        // Semana anterior (01-07): 80 kg; esta (08-14): 80,5 kg → +500 g.
        var filas: [(String, Double?, String)] = []
        for d in 1...7 { filas.append((String(format: "2026-10-%02d", d), 80, "manual")) }
        for d in 8...14 { filas.append((String(format: "2026-10-%02d", d), 80.5, "manual")) }
        let s = PesoCorporal.serie(salud(filas))
        #expect(PesoCorporal.media(s, hasta: "2026-10-14", dias: 7) == 80.5)
        #expect(PesoCorporal.media(s, hasta: "2026-10-07", dias: 7) == 80)
        // (fin − 7, fin]: el 7 no entra en la semana que termina el 14.
        #expect(PesoCorporal.media(s, hasta: "2026-10-08", dias: 1) == 80.5)
        #expect(PesoCorporal.deltaSemanal(s, hoy: "2026-10-14") == 500)
        #expect(PesoCorporal.textoDelta(500) == "+500 g")
        #expect(PesoCorporal.textoDelta(-1250) == "-1,3 kg")
        #expect(PesoCorporal.textoDelta(1000) == "+1,0 kg")
        #expect(PesoCorporal.deltaSemanal(Array(s.suffix(3)), hoy: "2026-10-14") == nil)
    }

    @Test func leerElPeso() {
        #expect(PesoCorporal.leer("82,35") == 82.4)
        #expect(PesoCorporal.leer(" 30 ") == 30)
        #expect(PesoCorporal.leer("29,9") == nil)
        #expect(PesoCorporal.leer("300,1") == nil)
        #expect(PesoCorporal.leer("abc") == nil)
        #expect(PesoCorporal.kg(81.95) == "82,0")
    }

    @Test func checkFaltan() {
        #expect(CheckinSemanal.faltan(["energia": 3, "descanso": 4, "hambre": 2, "adherencia": 5]) == nil)
        #expect(CheckinSemanal.faltan(["energia": 3, "hambre": 0]) == "Faltan: Descanso, Hambre, Adherencia")
    }

    @Test func racha() {
        #expect([0, 1, 2, 3, 6, 7, 30].map(RachaTexto.icono) == ["💤", "✨", "✨", "⚡", "⚡", "🔥", "🔥"])
    }

    @Test func dias() {
        #expect(Dia.numero("2026-10-14").map(Dia.texto) == "2026-10-14")
        #expect(Dia.numero("2026-03-01")! - Dia.numero("2026-02-28")! == 1)
        #expect(Dia.numero("x") == nil)
    }
}
