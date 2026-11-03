import Foundation
import MyPumpModelos

/// El aviso de récord apenas se confirma una serie efectiva (2.0.3, E3): «Récord: +2,5 kg» o «Récord: +1 rep». Es el
/// mismo criterio del «Récord a superar» de la card (la serie más pesada, `HistorialEntreno.record`), por serie y no por
/// sesión como el 🏆 PR de Progreso (`ProgresoEjercicio.resumen`, que compara el máximo de cada día). Lo verifican los
/// vectores de `apps/shared/vectores/entreno_203.json`.
///
/// - Lo mejor anterior es la serie más pesada del historial de días anteriores (misma clave) y, entre las de ese kg, la
///   de más reps. Las series de hoy ya confirmadas también cuentan como piso: el récord que ya se avisó no se repite en la
///   serie siguiente, y una serie de hoy por encima vuelve a avisar contra ella.
/// - Más kg con al menos 1 rep: «+N kg». El mismo kg que lo mejor con más reps: «+N rep(s)». Menos kg, nada.
/// - Sin historia de días anteriores no hay aviso (la primera vez no es récord). Los ejercicios sin kg (peso corporal,
///   calentamiento) y las series no verosímiles (las que hubo que preguntar) no avisan. Las filas con 0 kg no cuentan
///   (son de cuando el ejercicio se trataba como «sin peso»).
public enum RecordSerie {
    /// Una serie: kg y reps.
    public struct Marca: Equatable, Sendable {
        public let kg: Double
        public let reps: Int
        public init(kg: Double, reps: Int) { self.kg = kg; self.reps = reps }
    }

    public struct Aviso: Equatable, Sendable {
        public enum Tipo: String, Equatable, Sendable { case kg, reps }
        public let tipo: Tipo
        /// Lo que se superó: kg (2.5) o reps (1).
        public let delta: Double
        /// «Récord: +2,5 kg»
        public let texto: String
    }

    static let tolerancia = 1e-6

    public static func evaluar(_ serie: Marca, sinKg: Bool, verosimil: Bool, anteriores: [Marca], hoy: [Marca]) -> Aviso? {
        guard !sinKg, verosimil, serie.reps >= 1, serie.kg > 0, serie.kg.isFinite else { return nil }
        let sirve = { (m: Marca) in m.kg > 0 && m.kg.isFinite && m.reps >= 1 }
        let previas = anteriores.filter(sirve)
        guard !previas.isEmpty else { return nil }
        let piso = previas + hoy.filter(sirve)
        let mejorKg = piso.map(\.kg).max()!
        let mejorReps = piso.filter { abs($0.kg - mejorKg) < tolerancia }.map(\.reps).max() ?? 0
        if serie.kg > mejorKg + tolerancia {
            let delta = (serie.kg - mejorKg) * 100
            let d = delta.rounded() / 100
            return Aviso(tipo: .kg, delta: d, texto: "Récord: +\(JS.texto(d).replacingOccurrences(of: ".", with: ",")) kg")
        }
        if abs(serie.kg - mejorKg) < tolerancia && serie.reps > mejorReps {
            let n = serie.reps - mejorReps
            return Aviso(tipo: .reps, delta: Double(n), texto: "Récord: +\(n) rep\(n == 1 ? "" : "s")")
        }
        return nil
    }

    /// Las marcas del historial (del más nuevo al más viejo, como llega) que no son del día `hoy` (YYYY-MM-DD local).
    public static func anteriores(_ h: [RegistroHistorico], hoy: String?, zona: TimeZone) -> [Marca] {
        h.compactMap { r in
            guard let kg = r.pesoKg, let reps = r.reps else { return nil }
            if let hoy, HistorialEntreno.fechaLocal(r.registradoEn, zona: zona) == hoy { return nil }
            return Marca(kg: kg, reps: reps)
        }
    }

    /// Una serie del día como marca (los campos son texto, como los tipeó el cliente).
    public static func marca(_ s: SerieLocal) -> Marca? {
        guard let kg = JS.parseFloat(Verosimilitud.primeraComaAPunto(s.kg)), let reps = JS.parseInt(s.reps), reps.isFinite else { return nil }
        return Marca(kg: kg, reps: Int(reps))
    }
}
