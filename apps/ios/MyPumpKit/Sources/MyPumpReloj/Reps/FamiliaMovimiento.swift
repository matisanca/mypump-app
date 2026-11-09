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

/// La propuesta de reps: al terminar la serie, el reloj pone la corona en lo que contó y pregunta «¿10 reps?». Prendida
/// para todos y en todas las familias; es solo una propuesta: nunca registra la serie, y si no es clara no propone.
public enum ConfirmacionReps {
    /// La regularidad mínima para proponer.
    public static let calidadMinima: Double = 0.5

    /// Una serie terminada, pareja, en rango y hecha con carga (ver `ContadorReps.esfuerzoMinimo`).
    public static func serieClara(_ conteo: ContadorReps.Resultado) -> Bool {
        conteo.quieto && conteo.calidad >= calidadMinima && conteo.reps >= ContadorReps.repsMinimas && conteo.reps <= SesionReloj.repsMax
            && (conteo.esfuerzo ?? 0) >= ContadorReps.esfuerzoMinimo
            && (conteo.amplitud ?? 0) >= ContadorReps.relacionMinima * (conteo.esfuerzo ?? 0)
    }

    /// Las reps a proponer con la corona, o nil.
    public static func propuesta(_ conteo: ContadorReps.Resultado) -> Int? { serieClara(conteo) ? conteo.reps : nil }

    /// «¿10 reps?»
    public static func texto(_ reps: Int) -> String { "¿\(reps) \(reps == 1 ? "rep" : "reps")?" }
    /// Lo que dice VoiceOver cuando la corona se movió sola.
    public static func textoAccesible(_ reps: Int) -> String {
        "El reloj contó \(reps) \(reps == 1 ? "repetición" : "repeticiones"). Girá la corona si no es así."
    }
}

/// La propuesta de una serie y si el alumno tocó las reps. Se reinicia al confirmar o al cambiar de ejercicio.
/// - Si el alumno giró las reps, no se le pisa nunca lo que puso (antes o después de la propuesta).
/// - Mientras no las toque, la propuesta sigue a la última serie clara. En la grabación real el descanso generaba rachas
///   que parecían series: si la propuesta fuera de una sola vez, una de esas se gastaba la de la serie de verdad.
/// - `corregida` compara lo que se confirma con lo propuesto; girar y volver al mismo número cuenta como aceptada.
public struct PropuestaSerie: Equatable, Sendable {
    /// Lo que propuso el reloj en esta serie (nil = no propuso).
    public private(set) var reps: Int?
    /// El alumno giró las reps: no se le propone más nada en esta serie.
    public private(set) var tocada = false

    public init() {}

    /// El alumno giró las reps.
    public mutating func girar() { tocada = true }

    /// Las reps a poner en la corona si cambiaron, o nil.
    public mutating func proponer(_ conteo: ContadorReps.Resultado) -> Int? {
        guard !tocada, let n = ConfirmacionReps.propuesta(conteo), n != reps else { return nil }
        reps = n
        return n
    }

    /// Para el encabezado, con las reps que se confirman: nil sin propuesta; si no, si difieren de lo propuesto.
    public func corregida(confirmadas: Int) -> Bool? { reps.map { $0 != confirmadas } }
    /// La corona sigue en lo que propuso el reloj (para la pantalla).
    public func enLaCorona(_ enCorona: Int) -> Bool { reps == enCorona }

    public mutating func reiniciar() { self = PropuestaSerie() }
}

/// Lo que dice la pantalla del ejercicio sobre el conteo. Nunca queda muda: si no pudo contar, lo dice.
public enum AvisoConteo: Equatable, Sendable {
    /// No hay nada que decir (apagado por el servidor, o en el descanso, o con la propuesta a la vista).
    case ninguno
    /// Sin el entreno empezado, los sensores no corren.
    case falta_empezar
    /// Los sensores no entregan nada.
    case sinSensores
    /// La sesión de entreno se cortó (con la muñeca baja deja de ver).
    case sinSesion
    /// Va contando la serie.
    case contando(Int)
    /// No hay propuesta: si ya terminó, se carga a mano.
    case noPude(munecaQuieta: Bool)

    public var texto: String? {
        switch self {
        case .ninguno: nil
        case .falta_empezar: "Tocá Empezar para que el reloj cuente."
        case .sinSensores: "No pude leer el movimiento. Cargá las reps con la corona."
        case .sinSesion: "Se cortó el entreno: puede que no cuente. Cargá las reps con la corona."
        case .contando(let n): "Contando… \(n)"
        case .noPude(true): "Con la muñeca quieta casi no puedo contar. Usá la corona."
        case .noPude(false): "Si terminaste y no propuse nada, no la pude contar. Usá la corona."
        }
    }

    /// `sensores`: si entregan muestras (nil = no corren).
    public static func de(prendido: Bool, iniciada: Bool, enDescanso: Bool, conPropuesta: Bool, muestras: Bool, sesionViva: Bool,
                          conteo: ContadorReps.Resultado?, familia: FamiliaMovimiento) -> AvisoConteo {
        guard prendido, !enDescanso, !conPropuesta else { return .ninguno }
        guard iniciada else { return .falta_empezar }
        guard muestras else { return .sinSensores }
        guard sesionViva else { return .sinSesion }
        if let c = conteo, c.reps > 0, !c.quieto { return .contando(c.reps) }
        return .noPude(munecaQuieta: familia == .maquinaMunecaQuieta)
    }
}
