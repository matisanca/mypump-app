import Foundation
import MyPumpModelos

/// La preparación de cada ejercicio (2.0.3, E1): calentamiento, aproximaciones y potenciación antes de las series
/// efectivas. Es solo una indicación (peso, reps y descanso): no se registra como carga. La arma la app con el criterio de
/// Mati (su video); si el plan trae `aproximaciones`, gana el plan (`[]` es sin preparación). Todos los números y las
/// listas viven acá (y en el gemelo de Android, Preparacion.kt); lo verifican los vectores de
/// `apps/shared/vectores/preparacion.json`.
///
/// - PRINCIPAL = tipo compuesto, menos los accesorios por nombre (`palabrasAccesorio`: remo al mentón, unilaterales,
///   búlgara/zancada/estocada, press o agarre cerrado, fondos en máquina, pull through, subida al cajón, step, goblet).
///   ACCESORIO = lo demás que cuenta (esos compuestos, aislamiento o aislado).
/// - No llevan nada ni cuentan: cardio, core, calentamiento, lo sin tipo, lo de peso corporal y lo de potencia o
///   isométrico (`palabrasSinPreparacion`: cajón, swing, get-up, cargada, granjero, monster walk, rollout, isométrico).
/// - Grupo = el músculo principal del catálogo del ejercicio que se hace (el del sustituto si el catálogo lo tiene; si no,
///   el del original, por `CatalogoEjercicios.resolver`: slug, slug de la foto, reglas y nombre).
/// - El primer principal del músculo en el día: calentamiento de 16-20 al 25 %, aproximaciones de 5 al 60 y al 85 % y la
///   potenciación opcional de 1-3 con +5 kg (+2,5 bajo 50 kg, nunca más de +10). Los principales siguientes del mismo
///   músculo: una sola de 5 al 75 %.
/// - El primer accesorio del músculo en el día: una de 5-6 al 60 %. Los siguientes accesorios del músculo, nada.
/// - Sin músculo (respaldo conservador): el principal lleva calentamiento solo si es el primer ejercicio de fuerza del
///   día y las dos aproximaciones, sin potenciación; el accesorio, nada.
/// - El kg sale del kg efectivo (el que el alumno escribió en la primera serie efectiva, en vivo; si no, el que sugiere la
///   app), redondeado a lo que se puede cargar: barra de 2,5 en 2,5 y nunca menos que la barra sola (20 kg, «Barra
///   sola»); mancuernas de 1 en 1 hasta 10 y de 2 en 2 desde ahí; máquina o polea de 5 en 5; lo demás de 2,5 en 2,5.
///   Sin kg efectivo, solo reps.
public enum Preparacion {
    public static let descansoSegundos = 30
    public static let pctCalentamiento = 25.0
    public static let pctAproximaciones = [60.0, 85.0]
    public static let pctSiguientePrincipal = 75.0
    public static let pctAccesorio = 60.0
    public static let repsCalentamiento = "16-20"
    public static let repsAproximacion = "5"
    public static let repsAccesorio = "5-6"
    public static let repsPotenciacion = "1-3"
    public static let potenciacionKg = 5.0
    public static let potenciacionKgLiviano = 2.5
    public static let potenciacionLimiteLiviano = 50.0
    public static let potenciacionTope = 10.0
    public static let kgBarra = 20.0
    public static let paso = 2.5
    public static let pasoMaquina = 5.0
    public static let pasoMancuernaLiviana = 1.0
    public static let pasoMancuernaPesada = 2.0
    public static let limiteMancuernaLiviana = 10.0
    /// El texto cuando no hay kg de referencia.
    public static let textoSinKg = "Usalas para encontrar tu peso de trabajo."

    static let barraRE = RegexWeb(#"\bbarra\b"#)
    static let noBarraLibreRE = RegexWeb(#"polea|cable|jalon|maquina|smith|multipower|dominada|mancuerna|barra\s*(z|ez)\b"#)
    static let mancuernaRE = RegexWeb(#"mancuerna"#)
    static let maquinaRE = RegexWeb(#"maquina|polea|cable|prensa|smith|multipower|jalon|hack|pec\s*deck|contractora"#)
    /// Compuestos que son ACCESORIO (expresiones sobre el nombre en minúsculas y sin tildes).
    public static let palabrasAccesorio = [#"remo al menton"#, #"unilateral"#, #"a una mano"#, #"a un brazo"#, #"a una pierna"#,
                                           #"bulgara"#, #"zancada"#, #"estocada"#, #"press cerrado"#, #"agarre cerrado"#,
                                           #"fondos en maquina"#, #"pull[\s-]*through"#, #"subida al cajon"#, #"\bstep\b"#, #"goblet"#]
    /// Potencia, sin kg de referencia o isométricos: no llevan preparación (ídem).
    public static let palabrasSinPreparacion = [#"salto al cajon"#, #"box jump"#, #"swing"#, #"turkish"#, #"get[\s-]*up"#,
                                                #"power clean"#, #"cargada"#, #"farmer"#, #"granjero"#, #"monster walk"#, #"rollout"#,
                                                #"isometric"#]
    static let accesorioRE = RegexWeb(palabrasAccesorio.joined(separator: "|"))
    static let sinPreparacionRE = RegexWeb(palabrasSinPreparacion.joined(separator: "|"))

    /// Con qué se carga: decide el redondeo.
    public enum Equipo: String, Equatable, Sendable { case barra, mancuerna, maquina, otro }

    public enum Tipo: String, Equatable, Sendable { case calentamiento, aproximacion, potenciacion }

    /// Un ejercicio del día, en orden, como lo hace el alumno (con los sustitutos).
    public struct Entrada: Equatable, Sendable {
        public var tipo: String?
        /// nil = el catálogo no lo tiene (respaldo conservador).
        public var musculo: String?
        public var nombre: String
        /// De peso corporal (`ReglasEjercicio.esSinPeso`, con el equipo del catálogo).
        public var sinPeso: Bool
        public init(tipo: String?, musculo: String?, nombre: String, sinPeso: Bool) {
            self.tipo = tipo; self.musculo = musculo; self.nombre = nombre; self.sinPeso = sinPeso
        }

        /// Lleva preparación y cuenta para «primero del músculo».
        var cuenta: Bool { (Preparacion.compuesto(tipo) || Preparacion.monoarticular(tipo)) && !sinPeso && !Preparacion.sinPreparacion(nombre) }
        var principal: Bool { Preparacion.esPrincipal(nombre: nombre, tipo: tipo) }
        var grupo: String? {
            guard let m = musculo?.trimmingCharacters(in: .whitespaces).lowercased(), !m.isEmpty else { return nil }
            return m
        }
    }

    /// Una serie de preparación.
    public struct Serie: Equatable, Sendable {
        public let tipo: Tipo
        /// «Aproximación 1/2»: el número entre las de su tipo (nil si es una sola).
        public let numero: Int?
        public let reps: String
        /// nil = sin kg (no hay referencia o el ejercicio no lleva).
        public let kg: Double?
        public let barraSola: Bool
        public let opcional: Bool
        public let nota: String?

        public init(tipo: Tipo, numero: Int? = nil, reps: String, kg: Double? = nil, barraSola: Bool = false, opcional: Bool = false, nota: String? = nil) {
            self.tipo = tipo; self.numero = numero; self.reps = reps; self.kg = kg; self.barraSola = barraSola
            self.opcional = opcional; self.nota = nota
        }

        /// «Calentamiento», «Aproximación 1», «Potenciación (opcional)».
        public var etiqueta: String {
            switch tipo {
            case .calentamiento: return "Calentamiento"
            case .aproximacion: return numero.map { "Aproximación \($0)" } ?? "Aproximación"
            case .potenciacion: return "Potenciación (opcional)"
            }
        }

        /// «Barra sola», «22,5» o nil (sin kg).
        public var textoKg: String? {
            if barraSola { return "Barra sola" }
            return kg.map { JS.texto($0).replacingOccurrences(of: ".", with: ",") }
        }
    }

    static func compuesto(_ tipo: String?) -> Bool { tipo == "compuesto" }
    static func monoarticular(_ tipo: String?) -> Bool { tipo == "aislamiento" || tipo == "aislado" }

    /// Minúsculas y sin tildes (para los nombres).
    static func normal(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased() }

    /// PRINCIPAL: compuesto y no accesorio por nombre.
    public static func esPrincipal(nombre: String, tipo: String?) -> Bool { compuesto(tipo) && !accesorioRE.prueba(normal(nombre)) }

    /// Potencia, sin kg de referencia o isométrico: sin preparación.
    public static func sinPreparacion(_ nombre: String) -> Bool { sinPreparacionRE.prueba(normal(nombre)) }

    /// Barra libre (olímpica): el equipo del catálogo o el nombre, sin polea, máquina ni barra Z.
    public static func esBarra(nombre: String, equipo: String?) -> Bool {
        if equipo?.trimmingCharacters(in: .whitespaces).lowercased() == "barbell" { return true }
        let n = normal(nombre)
        return barraRE.prueba(n) && !noBarraLibreRE.prueba(n)
    }

    /// El equipo: el del catálogo (el sustituto) y si no, el nombre. Mancuerna gana; después barra libre; después máquina.
    public static func equipo(nombre: String, equipo: String?) -> Equipo {
        let e = equipo?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let n = normal(nombre)
        if e == "dumbbell" || mancuernaRE.prueba(n) { return .mancuerna }
        if esBarra(nombre: nombre, equipo: equipo) { return .barra }
        if e == "machine" || e == "cable" || maquinaRE.prueba(n) { return .maquina }
        return .otro
    }

    /// Redondeo a lo que se puede cargar (la mitad, para arriba, como `Math.round`). 0 o menos es nil; con barra, nunca
    /// menos que la barra (lo dice `barraSola`).
    public static func redondear(_ kg: Double, equipo: Equipo) -> Double? {
        let p: Double
        switch equipo {
        case .mancuerna: p = kg < limiteMancuernaLiviana ? pasoMancuernaLiviana : pasoMancuernaPesada
        case .maquina: p = pasoMaquina
        case .barra, .otro: p = paso
        }
        let r = (kg / p + 0.5 + 1e-9).rounded(.down) * p
        if equipo == .barra { return max(kgBarra, r) }
        return r > 0 ? r : nil
    }

    /// ¿Es el primero de su clase (principal o accesorio) en su músculo? Sin músculo, un principal es «primero» si es el
    /// primer ejercicio de fuerza del día (respaldo conservador); un accesorio sin músculo nunca.
    public static func primero(_ dia: [Entrada], indice: Int) -> Bool {
        guard indice >= 0, indice < dia.count, dia[indice].cuenta else { return false }
        let e = dia[indice]
        guard let g = e.grupo else { return e.principal && dia.firstIndex(where: \.cuenta) == indice }
        return dia.firstIndex { $0.cuenta && $0.grupo == g && $0.principal == e.principal } == indice
    }

    /// La preparación del ejercicio `indice` del día. `plan` es el `aproximaciones` del plan (gana si no es nil; vacío es
    /// sin preparación). `kgEfectivo` nil (o 0) es sin referencia (solo reps); `sinKg` (peso corporal) no lleva preparación,
    /// salvo la del plan, que va sin kg.
    public static func series(dia: [Entrada], indice: Int, nombre: String, equipo: String?, sinKg: Bool, kgEfectivo: Double?,
                              plan: [Aproximacion]?) -> [Serie] {
        guard indice >= 0, indice < dia.count else { return [] }
        let ref: Double? = sinKg ? nil : kgEfectivo.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        let eq = self.equipo(nombre: nombre, equipo: equipo)
        func kg(_ pct: Double) -> (Double?, Bool) {
            guard let ref, let k = redondear(ref * pct / 100, equipo: eq) else { return (nil, false) }
            return (k, eq == .barra && k <= kgBarra)
        }
        if let plan {
            let n = plan.count
            return plan.enumerated().map { i, a in
                let (k, sola): (Double?, Bool) = sinKg ? (nil, false) : (a.kg.map { ($0, false) } ?? a.pct.map(kg) ?? (nil, false))
                return Serie(tipo: .aproximacion, numero: n > 1 ? i + 1 : nil, reps: a.reps ?? "–", kg: k, barraSola: sola, nota: a.nota)
            }
        }
        let e = dia[indice]
        guard e.cuenta, !sinKg else { return [] }
        let esPrimero = primero(dia, indice: indice)
        guard e.principal else {
            guard esPrimero else { return [] }
            let (k, sola) = kg(pctAccesorio)
            return [Serie(tipo: .aproximacion, reps: repsAccesorio, kg: k, barraSola: sola)]
        }
        // Principal sin músculo: el respaldo conservador (calentamiento solo si es el primero de fuerza, dos aproximaciones).
        guard e.grupo != nil else {
            var s: [Serie] = []
            if esPrimero {
                let (k, sola) = kg(pctCalentamiento)
                s.append(Serie(tipo: .calentamiento, reps: repsCalentamiento, kg: k, barraSola: sola))
            }
            for (i, p) in pctAproximaciones.enumerated() {
                let (k, sola) = kg(p)
                s.append(Serie(tipo: .aproximacion, numero: i + 1, reps: repsAproximacion, kg: k, barraSola: sola))
            }
            return s
        }
        guard esPrimero else {
            let (k, sola) = kg(pctSiguientePrincipal)
            return [Serie(tipo: .aproximacion, reps: repsAproximacion, kg: k, barraSola: sola)]
        }
        let (kc, solac) = kg(pctCalentamiento)
        var s = [Serie(tipo: .calentamiento, reps: repsCalentamiento, kg: kc, barraSola: solac)]
        for (i, p) in pctAproximaciones.enumerated() {
            let (k, sola) = kg(p)
            s.append(Serie(tipo: .aproximacion, numero: i + 1, reps: repsAproximacion, kg: k, barraSola: sola))
        }
        var kp: Double?
        if let ref {
            let suma = min(potenciacionTope, ref < potenciacionLimiteLiviano ? potenciacionKgLiviano : potenciacionKg)
            kp = redondear(ref + suma, equipo: eq)
        }
        s.append(Serie(tipo: .potenciacion, reps: repsPotenciacion, kg: kp, opcional: true))
        return s
    }

    /// El kg efectivo: el de la primera serie efectiva si ya lo escribió, si no el que sugiere la app para ella.
    public static func kgEfectivo(escrito: String, sugerido: String) -> Double? {
        let t = escrito.isEmpty ? sugerido : escrito
        guard let k = JS.parseFloat(Verosimilitud.primeraComaAPunto(t)), k > 0, k.isFinite else { return nil }
        return k
    }

    /// La clave de los tildes: fecha local + día + lugar (los ids son por posición, `slug-dN-idx`).
    public static func claveTildes(fecha: String, dia: String, lugar: String) -> String { "\(fecha)|\(dia)|\(lugar)" }
}
