import Foundation
import MyPumpReglas

/// La familia de movimiento de un ejercicio para el conteo de reps (tanda 4): lo que importa es cómo se mueve la MUÑECA,
/// que es donde está el reloj. Sale del `patron_movimiento` del catálogo (el iPhone lo manda con la rutina) y del equipo;
/// sin patrón, del nombre. El error del contador se mide por familia y el conteo se prende familia por familia.
///
/// «máquina con muñeca quieta» junta lo que se hace en una máquina con las manos fijas o sin las manos (prensa,
/// extensión y curl femoral, aductores, gemelos sentado): ahí el reloj casi no se mueve y no se espera contar.
public enum FamiliaMovimiento: String, Codable, Sendable, CaseIterable {
    case empujeHorizontal = "empuje_horizontal"
    case empujeVertical = "empuje_vertical"
    case tironHorizontal = "tiron_horizontal"
    case tironVertical = "tiron_vertical"
    case curl
    case extensionCodo = "extension_codo"
    case sentadilla
    case bisagra
    case zancada
    case elevacionLateral = "elevacion_lateral"
    case aperturaPectoral = "apertura_pectoral"
    case encogimiento
    case gemelo
    case core
    case maquinaMunecaQuieta = "maquina_muneca_quieta"
    case otra

    public var nombre: String {
        switch self {
        case .empujeHorizontal: "Empuje horizontal"
        case .empujeVertical: "Empuje vertical"
        case .tironHorizontal: "Tirón horizontal"
        case .tironVertical: "Tirón vertical"
        case .curl: "Curl"
        case .extensionCodo: "Extensión de codo"
        case .sentadilla: "Sentadilla"
        case .bisagra: "Bisagra"
        case .zancada: "Zancada"
        case .elevacionLateral: "Elevación lateral"
        case .aperturaPectoral: "Apertura de pecho"
        case .encogimiento: "Encogimiento"
        case .gemelo: "Gemelo"
        case .core: "Core"
        case .maquinaMunecaQuieta: "Máquina con muñeca quieta"
        case .otra: "Otra"
        }
    }

    /// La familia de un ejercicio. `patron` es el `patron_movimiento` del catálogo; `equipo`, el crudo o la etiqueta.
    public static func de(patron: String?, equipo: String?, nombre: String?, tipo: String? = nil) -> FamiliaMovimiento {
        let n = ClaveEjercicio.de(nombre)
        let maquina = esMaquina(equipo: equipo, nombre: n)
        if let p = patron, !p.isEmpty, let f = dePatron(p, maquina: maquina, nombre: n) { return f }
        return deNombre(n, maquina: maquina, tipo: tipo)
    }

    static func esMaquina(equipo: String?, nombre n: String) -> Bool {
        let e = ClaveEjercicio.de(equipo)
        return e.contains("machine") || e.contains("maquina") || n.contains("maquina") || n.contains("prensa")
    }

    static func dePatron(_ p: String, maquina: Bool, nombre n: String) -> FamiliaMovimiento? {
        switch p {
        case "empuje_horizontal", "empuje_inclinado", "empuje_declinado", "press_cerrado", "fondos_paralelas": .empujeHorizontal
        case "empuje_vertical_hombro": .empujeVertical
        case "remo_horizontal", "deltoide_posterior": .tironHorizontal
        case "jalon_vertical", "pullover": .tironVertical
        case "curl_biceps", "curl_martillo_braquial", "flexion_muneca": .curl
        case "extension_triceps_overhead", "extension_triceps_pushdown", "extension_triceps_kickback": .extensionCodo
        // La prensa es del patrón de sentadilla, pero en la máquina las manos no se mueven.
        case "sentadilla_prensa": maquina || n.contains("prensa") || n.contains("hack") ? .maquinaMunecaQuieta : .sentadilla
        case "bisagra_cadera", "extension_cadera_gluteo", "extension_lumbar": .bisagra
        case "zancada_unilateral": .zancada
        case "elevacion_lateral", "elevacion_frontal", "remo_menton": .elevacionLateral
        case "apertura_pectoral": .aperturaPectoral
        case "encogimiento_trapecio": .encogimiento
        case "gemelo_de_pie": maquina ? .maquinaMunecaQuieta : .gemelo
        case "gemelo_sentado", "flexion_rodilla", "extension_rodilla", "aduccion_cadera", "abduccion_cadera": .maquinaMunecaQuieta
        case "core_flexion", "core_rotacion", "core_anti_extension": .core
        default: nil
        }
    }

    /// Sin patrón del catálogo: por palabras del nombre (en castellano y en inglés).
    static func deNombre(_ n: String, maquina: Bool, tipo: String?) -> FamiliaMovimiento {
        func tiene(_ ps: String...) -> Bool { ps.contains { n.contains($0) } }
        if tiene("prensa", "leg press", "extension de cuadriceps", "leg extension", "curl femoral", "leg curl", "aductor", "abductor", "gemelo sentado", "hack") {
            return .maquinaMunecaQuieta
        }
        if tiene("frances", "triceps", "skull", "pushdown", "patada", "kickback") { return .extensionCodo }
        if tiene("curl", "martillo", "hammer") { return .curl }
        if tiene("dominada", "jalon", "pull up", "pulldown", "chin up", "pullover") { return .tironVertical }
        if tiene("remo", "row", "face pull", "pajaro", "posterior") { return .tironHorizontal }
        if tiene("militar", "overhead press", "press de hombro", "arnold", "shoulder press") { return .empujeVertical }
        if tiene("press", "flexiones", "push up", "fondos", "dips") { return .empujeHorizontal }
        if tiene("apertura", "cruce", "fly", "pec deck", "contractora") { return .aperturaPectoral }
        if tiene("vuelo", "elevacion lateral", "elevaciones laterales", "lateral raise", "elevacion frontal", "front raise") { return .elevacionLateral }
        if tiene("zancada", "estocada", "bulgara", "lunge", "split squat", "step up") { return .zancada }
        if tiene("sentadilla", "squat", "goblet") { return maquina ? .maquinaMunecaQuieta : .sentadilla }
        if tiene("peso muerto", "deadlift", "hip thrust", "puente", "good morning", "buenos dias", "rumano", "swing") { return .bisagra }
        if tiene("encogimiento", "shrug") { return .encogimiento }
        if tiene("gemelo", "pantorrilla", "calf") { return maquina ? .maquinaMunecaQuieta : .gemelo }
        if tiene("abdominal", "crunch", "plancha", "plank", "rueda", "core", "russian") { return .core }
        return .otra
    }
}

/// El flujo final del conteo (tanda 4), preparado y APAGADO: al terminar la serie, el reloj propone «¿10 reps?» con la
/// corona ya en lo que contó, solo en las familias de `habilitadas` (vacía hasta que la evaluación diga en cuáles el
/// contador acierta ±1 rep en el 90 % de las series). En el modo calibración nunca propone: se compara, no se toca.
public enum ConfirmacionReps {
    /// Las familias donde el reloj propone las reps. VACÍA: nadie ve el flujo hasta que se decida con los datos.
    public static let habilitadas: Set<FamiliaMovimiento> = []
    /// La autocorrelación mínima para proponer.
    public static let calidadMinima: Double = 0.6

    /// Corre el contador en esta familia (para el flujo final).
    public static func cuenta(_ familia: FamiliaMovimiento, habilitadas: Set<FamiliaMovimiento> = habilitadas) -> Bool {
        habilitadas.contains(familia)
    }

    /// Las reps a proponer con la corona, o nil: solo en una familia habilitada, con la serie terminada (quieto después
    /// del tramo activo), una serie clara y fuera del modo calibración.
    public static func propuesta(_ familia: FamiliaMovimiento, conteo: ContadorReps.Resultado, calibrando: Bool,
                                 habilitadas: Set<FamiliaMovimiento> = habilitadas) -> Int? {
        guard !calibrando, habilitadas.contains(familia), conteo.quieto, conteo.calidad >= calidadMinima,
              conteo.reps >= SesionReloj.repsMin, conteo.reps <= SesionReloj.repsMax else { return nil }
        return conteo.reps
    }

    /// «¿10 reps?»
    public static func texto(_ reps: Int) -> String { "¿\(reps) \(reps == 1 ? "rep" : "reps")?" }
}
