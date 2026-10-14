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
        #expect(DiaCalendario.numero("2026-10-14").map(DiaCalendario.texto) == "2026-10-14")
        #expect(DiaCalendario.numero("2026-03-01")! - DiaCalendario.numero("2026-02-28")! == 1)
        #expect(DiaCalendario.numero("x") == nil)
    }
}

private func foto(_ semana: String, _ pose: String) -> FotoProgreso {
    try! JSONDecoder().decode(FotoProgreso.self, from: JSONEncoder().encode(JSONValue.objeto(["semana_lunes": .texto(semana), "pose": .texto(pose)])))
}

@Suite("Fotos de progreso: semanas, racha y comparador como la web")
struct FotosProgresoTests {
    @Test func lunesISO() {
        #expect(FotosProgreso.lunes("2026-10-14") == "2026-10-12")   // miércoles
        #expect(FotosProgreso.lunes("2026-10-12") == "2026-10-12")   // lunes
        #expect(FotosProgreso.lunes("2026-10-18") == "2026-10-12")   // domingo
        #expect(FotosProgreso.lunes("2026-03-01") == "2026-02-23")
    }

    @Test func rachaDeSemanasCompletasHaciaAtras() {
        var f: [FotoProgreso] = []
        for s in ["2026-09-14", "2026-09-28", "2026-10-05"] { for p in ["frente", "perfil", "espalda"] { f.append(foto(s, p)) } }
        f.append(foto("2026-10-12", "frente"))   // la actual, incompleta, no corta la racha
        #expect(FotosProgreso.racha(f) == 2)      // 28/9 y 5/10; el 21/9 falta
        #expect(FotosProgreso.semanas(f) == ["2026-09-14", "2026-09-28", "2026-10-05", "2026-10-12"])
        #expect(FotosProgreso.racha([]) == 0)
    }

    @Test func posesDeLaSemanaConPendientes() {
        let f = [foto("2026-10-12", "frente")]
        let s = FotosProgreso.posesDeLaSemana(f, pendientes: [("perfil", "2026-10-14"), ("espalda", "2026-10-05")], semana: "2026-10-12")
        #expect(s == ["frente", "perfil"])
        let p = FotosProgreso.pendientes(checkinEnviado: true, posesDeLaSemana: s)
        #expect(p.total == 1 && p.faltanFotos && !p.faltaCheck)
        #expect(FotosProgreso.textoRecordatorio(faltaCheck: true, faltanFotos: true) == "Te faltan tu check y tus fotos de la semana")
    }

    @Test func resumenDelComparador() {
        let peso = [PesoCorporal.Punto(fecha: "2026-09-15", kg: 84.0), PesoCorporal.Punto(fecha: "2026-10-13", kg: 81.6)]
        #expect(FotosProgreso.resumenComparador(primera: "2026-09-14", ultima: "2026-10-12", peso: peso) == "4 semanas · -2,4 kg")
        #expect(FotosProgreso.resumenComparador(primera: "2026-10-05", ultima: "2026-10-12", peso: []) == "1 semana")
    }
}

@Suite("toFixed como JavaScript")
struct ToFixedTests {
    @Test func casosDeLaRevisionYBordes() {
        #expect(NumeroJS.toFixed((60.0 + 60.1) / 2, 1) == "60.0")   // la nativa daba 60.1
        #expect(NumeroJS.toFixed(1150.0 / 1000, 1) == "1.1")        // "+1,1 kg", la nativa daba 1,2
        #expect(NumeroJS.toFixed(-9950.0 / 1000, 1) == "-9.9")      // la nativa daba -10,0
        #expect(NumeroJS.toFixed(1.25, 1) == "1.3")                 // empate exacto: el mayor
        #expect(NumeroJS.toFixed(0.15, 1) == "0.1")                 // 0,1499…
        #expect(NumeroJS.toFixed(-0.04, 1) == "-0.0")
        #expect(NumeroJS.toFixed(9.96, 1) == "10.0")
        #expect(NumeroJS.toFixed(99.95, 1) == "100.0")              // 99,9500000000000028…
        #expect(NumeroJS.toFixed(0, 1) == "0.0")
        #expect(NumeroJS.toFixed(13.207547169811321, 1) == "13.2")
        #expect(PesoCorporal.textoDelta(1150) == "+1,1 kg")
    }
}
