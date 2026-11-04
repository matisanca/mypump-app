import Foundation
import MyPumpModelos

/// La línea de la tarjeta «Tu progreso» de Revisión (2.1.0, aprobada por Mati el 4-nov): lo más útil de la semana en una
/// frase. Mira los últimos 7 días (hoy incluido) y, por ejercicio, su última sesión contra las anteriores (el máximo de
/// kg por día, como Progreso). En orden: récords, ejercicios que subieron, sesiones entrenadas; sin nada, nil y la
/// tarjeta dice lo genérico. Los vectores, en `apps/shared/vectores/progreso_semana.json`.
public enum ProgresoSemana {
    public struct Ejercicio: Sendable, Equatable {
        public let nombre: String
        /// Fecha local ("YYYY-MM-DD") → máximo de kg de ese día.
        public let sesiones: [String: Double]
        public init(nombre: String, sesiones: [String: Double]) {
            self.nombre = nombre
            self.sesiones = sesiones
        }
    }

    /// Las sesiones de un ejercicio desde su historial (un peso nulo cuenta como 0, como `ProgresoEjercicio`).
    public static func ejercicio(nombre: String, filas: [RegistroHistorico], zona: TimeZone = .current) -> Ejercicio {
        var porFecha: [String: Double] = [:]
        for f in filas {
            let fecha = FechaLocal.de(f.registradoEn, zona: zona)
            guard !fecha.isEmpty else { continue }
            porFecha[fecha] = max(porFecha[fecha] ?? 0, f.pesoKg ?? 0)
        }
        return Ejercicio(nombre: nombre, sesiones: porFecha)
    }

    public static func linea(_ ejercicios: [Ejercicio], hoy: String) -> String? {
        guard let n = DiaCalendario.numero(hoy) else { return nil }
        let semana = Set((0..<7).map { DiaCalendario.texto(n - $0) })
        var records: [(nombre: String, kg: Double)] = []
        var subieron: [String] = []
        var dias = Set<String>()

        for e in ejercicios {
            let fechas = e.sesiones.keys.filter { DiaCalendario.numero($0) != nil }.sorted()
            dias.formUnion(fechas.filter(semana.contains))
            guard let ultima = fechas.last, semana.contains(ultima), let kg = e.sesiones[ultima], kg.isFinite, kg > 0 else { continue }
            let anteriores = fechas.dropLast().compactMap { e.sesiones[$0] }.filter(\.isFinite)
            guard let previa = anteriores.last else { continue }
            if kg > (anteriores.max() ?? 0) { records.append((e.nombre, kg)) }
            else if kg > previa { subieron.append(e.nombre) }
        }

        switch records.count {
        case 1: return "🏆 Récord en \(records[0].nombre): \(kilos(records[0].kg)) kg"
        case 2: return "🏆 2 récords esta semana: \(records[0].nombre) y \(records[1].nombre)"
        case 3...: return "🏆 \(records.count) récords esta semana: \(records[0].nombre), \(records[1].nombre) y \(records.count - 2) más"
        default: break
        }
        switch subieron.count {
        case 1: return "Subiste en \(subieron[0]) esta semana"
        case 2...: return "Subiste en \(subieron.count) ejercicios esta semana"
        default: break
        }
        switch dias.count {
        case 0: return nil
        case 1: return "1 sesión entrenada esta semana"
        default: return "\(dias.count) sesiones entrenadas esta semana"
        }
    }

    /// 82.5 → "82,5"; 80 → "80"; hasta dos decimales.
    public static func kilos(_ kg: Double) -> String {
        let centesimos = Int((kg * 100).rounded())
        let entero = centesimos / 100, resto = centesimos % 100
        if resto == 0 { return "\(entero)" }
        return resto % 10 == 0 ? "\(entero),\(resto / 10)" : "\(entero),\(String(format: "%02d", resto))"
    }
}
