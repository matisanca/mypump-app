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

    /// El peso del comparador (2.3.3): el de la semana de cada foto, o el más cercano en ±7 días; sin kg si no se puede decir.
    @Test func pesoDelComparador() {
        func p(_ l: [(String, Double)]) -> [PesoCorporal.Punto] { l.map { PesoCorporal.Punto(fecha: $0.0, kg: $0.1) } }
        func r(_ a: String, _ b: String, _ l: [(String, Double)]) -> String { FotosProgreso.resumenComparador(primera: a, ultima: b, peso: p(l)) }
        // Emmanuel: con la regla vieja (el primero desde el lunes, sobre 60 días) veía +0,7.
        #expect(r("2026-08-31", "2026-11-16", [("2026-09-02", 73.0), ("2026-09-20", 72.1), ("2026-11-16", 68.4), ("2026-11-18", 68.9)])
                == "11 semanas · -4,6 kg")
        // La semana sin peso toma el más cercano: 3 días antes del lunes le gana a 5 después del domingo.
        #expect(r("2026-09-14", "2026-11-09", [("2026-09-11", 82.0), ("2026-09-25", 81.0), ("2026-11-10", 79.6)]) == "8 semanas · -2,4 kg")
        // Empate (4 y 4): el de después.
        #expect(r("2026-09-14", "2026-11-09", [("2026-09-10", 82.0), ("2026-09-24", 81.0), ("2026-11-10", 79.6)]) == "8 semanas · -1,4 kg")
        // A 7 días justos entra; a 8, no.
        #expect(r("2026-09-14", "2026-11-09", [("2026-09-07", 82.0), ("2026-11-10", 79.6)]) == "8 semanas · -2,4 kg")
        #expect(r("2026-09-14", "2026-11-09", [("2026-09-06", 82.0), ("2026-09-28", 81.0), ("2026-11-10", 79.6)]) == "8 semanas")
        // Libras contra kilos: pasa el 25 %. El 25 % justo se muestra.
        #expect(r("2026-08-17", "2026-11-09", [("2026-08-17", 219.0), ("2026-11-10", 101.4)]) == "12 semanas")
        #expect(r("2026-09-14", "2026-11-09", [("2026-09-14", 80.0), ("2026-11-09", 60.0)]) == "8 semanas · -20,0 kg")
        // El mismo pesaje en las dos fotos (la regla vieja decía «1 semana · 0,0 kg»).
        #expect(r("2026-11-02", "2026-11-09", [("2026-11-09", 80.0)]) == "1 semana")
        // La última toma un pesaje de la semana de la primera (es el cambio dentro de la semana 1).
        #expect(r("2026-11-02", "2026-11-09", [("2026-11-02", 80.0), ("2026-11-08", 79.4)]) == "1 semana")
        // Un 0,0 real (dos pesajes, cada uno en su semana) se muestra, sin signo.
        #expect(r("2026-11-02", "2026-11-09", [("2026-11-02", 80.0), ("2026-11-10", 80.0)]) == "1 semana · 0,0 kg")
        #expect(r("2026-11-02", "2026-11-09", [("2026-11-02", 80.0), ("2026-11-10", 80.04)]) == "1 semana · 0,0 kg")
        #expect(r("2026-11-02", "2026-11-09", [("2026-11-02", 80.0), ("2026-11-10", 79.96)]) == "1 semana · 0,0 kg")
        #expect(r("2026-11-02", "2026-11-09", [("2026-11-02", 80.0), ("2026-11-10", 80.5)]) == "1 semana · +0,5 kg")
        #expect(FotosProgreso.pesoDeSemana("2026-09-14", p([("2026-09-16", 81.0), ("2026-09-15", 82.0)])) == 82.0)
        #expect(FotosProgreso.pesoDeSemana("mal", p([("2026-09-15", 82.0)])) == nil)
    }

    /// Desde cuándo se pide el peso del comparador: el lunes de la foto más vieja menos 7 días; solo si Salud no llega.
    @Test func desdeDelPesoDelComparador() {
        #expect(FotosProgreso.desdePesoComparador(["2026-11-16", "2026-09-02", "2026-10-05", "mal", ""]) == "2026-08-24")
        #expect(FotosProgreso.desdePesoComparador(["2026-08-31"]) == "2026-08-24")
        #expect(FotosProgreso.desdePesoComparador([]) == nil)
        // Hoy 19/11: Salud trae desde el 21/09.
        #expect(FotosProgreso.necesitaPesoComparador(desde: "2026-09-20", hoy: "2026-11-19"))
        #expect(!FotosProgreso.necesitaPesoComparador(desde: "2026-09-21", hoy: "2026-11-19"))
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

@Suite("Revisión: el aviso de las fotos de la semana")
struct AvisoFotosTests {
    @Test func apareceSoloSiFaltanYElServidorYaContesto() {
        #expect(FotosProgreso.mostrarAviso(cargadas: true, posesDeLaSemana: []))
        #expect(FotosProgreso.mostrarAviso(cargadas: true, posesDeLaSemana: ["frente", "perfil"]))
        #expect(!FotosProgreso.mostrarAviso(cargadas: true, posesDeLaSemana: ["frente", "perfil", "espalda"]))
        #expect(!FotosProgreso.mostrarAviso(cargadas: false, posesDeLaSemana: []), "sin saber qué hay no se dice nada")
    }

    @Test func elTextoEsElAprobado() {
        #expect(FotosProgreso.avisoTitulo == "Tus fotos de la semana")
        #expect(FotosProgreso.avisoCuerpo == "Esta semana todavía no subiste tus fotos. Sacalas en el mismo lugar y con la misma luz que siempre, con la misma ropa, el celu vertical a la altura del ombligo y a 2 o 3 metros. Frente, perfil y espalda. Así vemos bien cómo venís")
    }
}
