import Foundation
import MyPumpModelos

/// Lo que pide el plan para un ejercicio en una semana. La progresión YA viene calculada por el Cerebro.
public struct Pauta: Equatable, Sendable {
    public let series: Int?
    public let reps: String?
    public let rir: String?

    public init(series: Int?, reps: String?, rir: String?) {
        self.series = series; self.reps = reps; self.rir = rir
    }
}

public struct NotaProgresion: Equatable, Sendable {
    public let texto: String
    public let cambia: Bool
    public let calibracion: Bool
}

public enum Progresiones {
    /// Port de `getProgresionActual` (cliente.html:1679). La semana se acota al largo del array: pasada la última,
    /// queda la última. Sin progresión, valen los campos viejos (`series`, `reps`, `rir_objetivo ?? rir`).
    public static func pauta(_ e: Ejercicio, semana: Int?) -> Pauta {
        if !e.progresion.isEmpty {
            let idx = max(0, min(semanaJS(semana) - 1, e.progresion.count - 1))
            let p = e.progresion[idx]
            return Pauta(series: p.series, reps: p.reps, rir: p.rir)
        }
        return Pauta(series: e.series, reps: e.reps, rir: e.rirObjetivo ?? e.rirSuelto)
    }

    static let textoCalibracion = "Semana de calibración: buscá el fallo muscular, no te guardes reps. Las reps son una guía (±2-3): si apuntás a 12 y te salen 9 o 14, perfecto. La idea es encontrar tu peso real llegando cerca del fallo."

    /// Port de `computeProgresionNota` (cliente.html:1701): explica el cambio de esta semana contra la anterior.
    /// Devuelve nil si el ejercicio no tiene progresión.
    public static func nota(_ e: Ejercicio, semanaActual: Int?) -> NotaProgresion? {
        let prog = e.progresion
        guard !prog.isEmpty else { return nil }
        let sem = semanaJS(semanaActual)

        func porSemana(_ s: Int) -> Progresion {
            prog.first { $0.semana == s } ?? prog[max(0, min(s - 1, prog.count - 1))]
        }
        let cur = porSemana(sem)

        // JS: ej.progresion.find(p => p.semana === sem - 1) || ej.progresion[sem - 2]. Sin acotar: fuera de rango
        // es undefined, y eso también es "calibración".
        var prev: Progresion?
        if sem > 1 {
            prev = prog.first { $0.semana == sem - 1 } ?? (sem - 2 < prog.count ? prog[sem - 2] : nil)
        }
        guard let prev else { return NotaProgresion(texto: textoCalibracion, cambia: false, calibracion: true) }

        let curReps = tope(cur.reps), prevReps = tope(prev.reps)
        let curSeries = tope(cur.series.map(String.init)), prevSeries = tope(prev.series.map(String.init))
        let curRir = tope(cur.rir), prevRir = tope(prev.rir)

        func ambos(_ a: Int?, _ b: Int?, _ op: (Int, Int) -> Bool) -> Bool {
            guard let a, let b else { return false }
            return op(a, b)
        }
        let repsBaja = ambos(curReps, prevReps, <)
        let repsSube = ambos(curReps, prevReps, >)
        let repsIgual = ambos(curReps, prevReps, ==)
        let seriesSube = ambos(curSeries, prevSeries, >)
        let seriesIgual = ambos(curSeries, prevSeries, ==)
        let rirBaja = ambos(curRir, prevRir, <)

        var partes: [String] = []
        if repsBaja && seriesIgual {
            partes.append("Esta semana bajan las reps (de \(js(prev.reps)) a \(js(cur.reps))). Subí la carga: apuntá a más kilos que la semana pasada, manteniendo buena técnica.")
        } else if repsBaja && seriesSube {
            partes.append("Más series y menos reps: subí un poco la carga y sumá volumen.")
        } else if seriesSube && repsIgual {
            partes.append("Sumamos una serie: mismo peso, más volumen total esta semana.")
        } else if repsSube && seriesIgual {
            partes.append("Suben las reps con el mismo peso. Si las completás sobrado, subí la carga la próxima.")
        }
        if rirBaja { partes.append("Bajamos el RIR: acercate más al fallo en cada serie.") }

        let cambia = !partes.isEmpty
        if !cambia {
            if repsIgual && seriesIgual {
                partes.append("Mantené el peso de la semana pasada e intentá superar tus reps, siempre cerca del fallo. Si te sobra, subí la carga.")
            } else {
                partes.append("Seguí la pauta de esta semana (\(cur.series.map(String.init) ?? "—")×\(cur.reps ?? "—")) y trabajá cerca del fallo; si te sobra, subí la carga.")
            }
        }
        return NotaProgresion(texto: partes.joined(separator: " "), cambia: cambia, calibracion: false)
    }

    /// `semana || 1` de JS: null, undefined y 0 valen 1.
    static func semanaJS(_ s: Int?) -> Int { (s ?? 0) == 0 ? 1 : s! }

    /// `upper` de JS: el mayor de los números que aparezcan en el texto ("8-10" → 10, "10 min" → 10).
    static func tope(_ v: String?) -> Int? {
        guard let v else { return nil }
        var mayor: Int?
        var actual = ""
        for ch in v + " " {
            if ch.isASCII, ch.isNumber { actual.append(ch) } else if !actual.isEmpty {
                if let n = Int(actual) { mayor = max(mayor ?? n, n) }
                actual = ""
            }
        }
        return mayor
    }

    /// Cómo imprime JS un valor en un template literal: null → "null".
    static func js(_ v: String?) -> String { v ?? "null" }
}
