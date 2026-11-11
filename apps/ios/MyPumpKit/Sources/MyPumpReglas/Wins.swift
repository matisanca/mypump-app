import Foundation
import MyPumpModelos

/// «Récords y logros» (2.3.0, palanca `wins_app`): los récords del día que se festejan al cerrar la sesión, los hitos de la
/// racha de pasos y los textos. La referencia es `scripts/nativa/generar-vectores-cola-a.py` y los vectores de
/// `apps/shared/vectores/wins.json`: esto tiene que dar exactamente lo mismo que Android y la web.
///
/// Por ejercicio del día: `anteriores` son las marcas de días anteriores (misma clave) y `hoy` las series de hoy
/// confirmadas y verosímiles. Una marca sirve si kg > 0, finito, y reps >= 1. Sin kg, sin historia suficiente, sin marcas
/// anteriores que sirvan o sin series de hoy que sirvan: no hay récord. Lo mejor es la marca de más kg y, entre las de ese
/// kg, la de más reps. A lo sumo un récord por ejercicio, en el orden del día, y como mucho `tope`.
public enum ReglasWins {
    public typealias Marca = RecordSerie.Marca

    /// Un ejercicio del día, como entra a la regla.
    public struct Ejercicio: Equatable, Sendable {
        public let clave: String
        /// El del ejercicio que se hace (el sustituto, si está sustituido).
        public let nombre: String
        public let anteriores: [Marca]
        public let hoy: [Marca]
        /// Peso corporal, por tiempo, calentamiento o cardio: nunca hay récord.
        public let sinKg: Bool
        /// `RecordSerie.historiaSuficiente`: con la historia cortada no se habla de récord.
        public let suficiente: Bool

        public init(clave: String, nombre: String, anteriores: [Marca], hoy: [Marca], sinKg: Bool = false, suficiente: Bool = true) {
            self.clave = clave; self.nombre = nombre; self.anteriores = anteriores; self.hoy = hoy
            self.sinKg = sinKg; self.suficiente = suficiente
        }
    }

    public enum Tipo: String, Codable, Equatable, Sendable {
        case recordKg = "record_kg"
        case recordReps = "record_reps"
        case rachaPasos = "racha_pasos"
    }

    public struct Record: Equatable, Sendable, Identifiable {
        public let tipo: Tipo
        public let clave: String
        public let ejercicio: String
        public let kg: Double
        public let reps: Int
        public let antesKg: Double
        public let antesReps: Int
        /// Lo que se superó: kg (2,5) o reps (1).
        public let delta: Double
        /// «57,5 kg × 8»
        public let marca: String
        /// «+2,5 kg» o «+1 rep»
        public let chip: String
        /// «Antes: 55 kg × 8»
        public let antes: String

        public var id: String { clave }

        /// Lo que viaja a `mypump_wins_registrar` en `p_datos`.
        public var datos: JSONValue {
            .objeto(["ejercicio": .texto(ejercicio), "kg": .numero(kg), "reps": .numero(Double(reps)),
                     "antes_kg": .numero(antesKg), "antes_reps": .numero(Double(antesReps))])
        }
    }

    public static let tope = 12
    static let tolerancia = 1e-6

    static func sirve(_ m: Marca) -> Bool { m.kg > 0 && m.kg.isFinite && m.reps >= 1 }

    static func mejor(_ marcas: [Marca]) -> Marca {
        let kg = marcas.map(\.kg).max() ?? 0
        let reps = marcas.filter { abs($0.kg - kg) < tolerancia }.map(\.reps).max() ?? 0
        return Marca(kg: kg, reps: reps)
    }

    /// 60 → «60», 62.5 → «62,5» (el número como lo escribe JS, con coma).
    static func kilos(_ x: Double) -> String { JS.texto(x).replacingOccurrences(of: ".", with: ",") }

    public static func records(_ ejercicios: [Ejercicio]) -> [Record] {
        var salida: [Record] = []
        for e in ejercicios {
            if e.sinKg || !e.suficiente { continue }
            let antes = e.anteriores.filter(sirve), hoy = e.hoy.filter(sirve)
            if antes.isEmpty || hoy.isEmpty { continue }
            let a = mejor(antes), h = mejor(hoy)
            let tipo: Tipo, delta: Double, chip: String
            if h.kg > a.kg + tolerancia {
                tipo = .recordKg
                delta = ((h.kg - a.kg) * 100).rounded() / 100
                chip = "+\(kilos(delta)) kg"
            } else if abs(h.kg - a.kg) < tolerancia && h.reps > a.reps {
                tipo = .recordReps
                let n = h.reps - a.reps
                delta = Double(n)
                chip = "+\(n) rep\(n == 1 ? "" : "s")"
            } else {
                continue
            }
            salida.append(Record(tipo: tipo, clave: e.clave, ejercicio: e.nombre, kg: h.kg, reps: h.reps, antesKg: a.kg, antesReps: a.reps,
                                 delta: delta, marca: "\(kilos(h.kg)) kg × \(h.reps)", chip: chip,
                                 antes: "Antes: \(kilos(a.kg)) kg × \(a.reps)"))
            if salida.count == tope { break }
        }
        return salida
    }

    // MARK: - Textos (los de `wins.json`)

    public static func titulo(_ n: Int) -> String { n == 1 ? "Récord nuevo" : "\(n) récords hoy" }
    public static func subtitulo(_ n: Int) -> String { n == 1 ? "Superaste tu mejor marca." : "Superaste \(n) de tus mejores marcas." }
    public static func conPermiso(_ n: Int) -> String { n == 1 ? "Mati se va a enterar de este logro." : "Mati se va a enterar de estos logros." }

    public static let contarle = "Contarle a Mati"
    public static let seguir = "Seguir"
    public static let permisoTitulo = "¿Compartir tus logros con Mati?"
    public static let permisoCuerpo = [
        "Cuando logres un récord o una racha de pasos, Mati lo va a ver y lo puede compartir con el equipo de Pump Team.",
        "Se comparte tu nombre y el logro: el ejercicio y la marca, o los días de tu racha. Nunca tus fotos, tu peso ni otros datos de salud.",
        "Lo podés desactivar cuando quieras en Mis datos. Lo ya compartido no se puede borrar.",
    ]
    public static let permisoSi = "Sí, compartir"
    public static let permisoNo = "Ahora no"
    public static let ajusteSeccion = "Logros"
    public static let ajusteInterruptor = "Compartir mis logros con Mati"
    public static let ajustePie = "Mati ve tus récords y tus rachas de pasos, y los puede compartir con el equipo de Pump Team. Nunca tus fotos, tu peso ni otros datos de salud."
    public static let desactivado = "Listo, no se comparte nada más."
    public static let sinRed = "No se pudo guardar. Probá de nuevo cuando tengas conexión."
    public static let demo = "En la demo no se envía nada."
    public static let rachaConPermiso = "Mati se va a enterar de esta racha."

    /// La versión del texto del permiso que acepta el alumno (`p_version`).
    public static let permisoVersion = 1

    // MARK: - Racha de pasos

    public static let hitosRacha = [7, 14, 21, 30, 60, 90, 120, 180, 365]
    public static func esHito(_ dias: Int) -> Bool { hitosRacha.contains(dias) }

    /// `p_datos` de un `racha_pasos`.
    public static func datosRacha(dias: Int, meta: Int) -> JSONValue {
        .objeto(["dias": .numero(Double(dias)), "meta": .numero(Double(meta))])
    }
}
