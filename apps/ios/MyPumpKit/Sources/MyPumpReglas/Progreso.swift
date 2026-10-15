import Foundation
import MyPumpModelos

/// Progreso (cliente.html:6036-6249): una tarjeta por ejercicio con el máximo por sesión de las últimas 8, el tope, la
/// variación entre la primera y la última de esas 8, y el 🏆 PR si la última sesión superó a TODAS las anteriores.
public enum ProgresoEjercicio {
    public struct Resumen: Equatable, Sendable {
        /// Máximo por sesión, de la más vieja a la más nueva (las 8 más recientes).
        public let serie: [Double]
        public let tope: Double
        /// Variación en % (un decimal, como `toFixed(1)`), o nil con una sola sesión o arrancando en 0.
        public let variacion: Double?
        public let esPR: Bool
    }

    /// nil si no hay ninguna sesión. Las filas llegan de la más nueva a la más vieja; un peso nulo cuenta como 0.
    public static func resumen(_ filas: [RegistroHistorico], zona: TimeZone = .current) -> Resumen? {
        var porFecha: [String: Double] = [:]
        for f in filas {
            let fecha = FechaLocal.de(f.registradoEn, zona: zona)
            guard !fecha.isEmpty else { continue }
            let kg = f.pesoKg ?? 0
            if porFecha[fecha] == nil || kg > porFecha[fecha]! { porFecha[fecha] = kg }
        }
        let fechas = porFecha.keys.sorted()
        let todos = fechas.map { porFecha[$0]! }
        let serie = Array(todos.suffix(8))
        guard let primero = serie.first, let ultimo = serie.last else { return nil }
        let variacion: Double? = serie.count > 1 && primero > 0 ? redondear1((ultimo - primero) / primero * 100) : nil
        let esPR = todos.count > 1 && ultimo > (todos.dropLast().max() ?? 0)
        return Resumen(serie: serie, tope: serie.max() ?? 0, variacion: variacion, esPR: esPR)
    }

    /// Las sesiones entrenadas: fechas locales distintas con algún registro.
    public static func sesiones(_ filas: [RegistroHistorico], zona: TimeZone = .current) -> Set<String> {
        Set(filas.map { FechaLocal.de($0.registradoEn, zona: zona) }.filter { !$0.isEmpty })
    }

    /// `toFixed(1)` (exacto como JS) como número.
    static func redondear1(_ x: Double) -> Double {
        Double(NumeroJS.toFixed(x, 1)) ?? 0
    }
}

extension FechaLocal {
    /// `fechaLocalDe(iso)`: la fecha local de un instante del servidor; si no se puede leer, lo que viene antes de la T.
    public static func de(_ iso: String, zona: TimeZone = .current) -> String {
        guard !iso.isEmpty else { return "" }
        if let d = FechaISOReglas.fecha(iso) { return hoy(d, zona: zona) }
        return String(iso.split(separator: "T").first ?? "")
    }
}

/// Lectura de instantes ISO del servidor (microsegundos y zona) para las reglas, sin depender de MyPumpDatos.
enum FechaISOReglas {
    static func fecha(_ iso: String) -> Date? { Formateadores.instante(iso) }
}
