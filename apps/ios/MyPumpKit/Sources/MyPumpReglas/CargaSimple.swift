import Foundation
import MyPumpModelos

// La carga única por ejercicio (2.3.0, aprobada por Mati el 9-nov). La carga se elige una vez y vale para todas las series
// que faltan; abajo queda fija la serie que toca. Las reglas son puras y salen de `apps/shared/vectores/carga_simple.json`
// (Android usa los mismos vectores). Sale a `registrar_carga` serie por serie, como siempre: la carga única no existe en la
// base y por eso la web, el Cerebro y el brief siguen leyendo lo mismo.

/// Cuándo se sugiere subir y hasta cuánto.
///
/// El plan NO trae kilos: `progresion` solo tiene series, reps, RIR y título. Lo único que dice es «bajan las reps». El
/// análisis de los planes activos (9-nov) confirma el 2,5 en los mensajes de la semana y no el 5: el 5 sale del paso de las
/// máquinas. Lo que no entra en la regla no se inventa: sin sugerencia.
public enum AumentoCarga {
    static let tituloFueraRE = RegexWeb(#"descarga|deload|re-?entrada|calibr|mantener|t[ée]cnica"#, i: true)
    static let tituloAnteriorFueraRE = RegexWeb(#"descarga|deload|re-?entrada"#, i: true)
    static let tituloCargaRE = RegexWeb(#"carga|fuerza|pico|potencia"#, i: true)
    /// «30 m», «50 s», «10 min»: va por tiempo o distancia, no por repeticiones.
    static let repsNoContablesRE = RegexWeb(#"\d\s*(s|seg|segundos?|m|mts?|metros?|min|minutos?|km)\b"#, i: true)
    /// La semana manda explícitamente la misma carga: la app no puede decir otra cosa ([[recomendaciones = app]]).
    static let mismaCargaRE = RegexWeb(#"misma\s+carga|mismo\s+peso|manten[eé]\w*\s+(el\s+|la\s+)?(peso|carga)"#, i: true)

    /// El título sin el «Semana 3 — » de adelante; vacío si no dice otra cosa.
    static func nombreDelTitulo(_ titulo: String?) -> String {
        guard let t = titulo else { return "" }
        let sinSemana = RegexWeb(#"^\s*semana\s+\d+\s*"#, i: true).reemplazarTodo(t, por: "")
        return sinSemana.trimmingCharacters(in: CharacterSet(charactersIn: " —–-·:\n\t"))
    }

    /// Esta semana bajan las reps con las mismas series, y nada del plan dice lo contrario. Nunca en calibración.
    public static func corresponde(_ e: Ejercicio, semana: Int, mensajeSemana: String? = nil) -> Bool {
        guard !e.progresion.isEmpty, !ReglasEjercicio.esCardio(e), e.tipo != "calentamiento",
              let nota = Progresiones.nota(e, semanaActual: semana), !nota.calibracion else { return false }
        let (cur, ant) = Progresiones.pasoDePlan(e.progresion, semana: Progresiones.semanaJS(semana))
        guard let prev = ant,
              let a = Progresiones.tope(cur.reps), let b = Progresiones.tope(prev.reps), a < b,
              let s = cur.series, s == prev.series,
              ReglasEjercicio.repsDelPlan(cur.reps) != nil, ReglasEjercicio.repsDelPlan(prev.reps) != nil,
              !repsNoContablesRE.prueba(cur.reps ?? ""), !repsNoContablesRE.prueba(prev.reps ?? "") else { return false }
        let titulo = nombreDelTitulo(cur.titulo)
        if tituloFueraRE.prueba(titulo) || tituloAnteriorFueraRE.prueba(nombreDelTitulo(prev.titulo)) { return false }
        if !titulo.isEmpty && !tituloCargaRE.prueba(titulo) { return false }
        if let m = mensajeSemana, mismaCargaRE.prueba(m) { return false }
        return true
    }

    /// El paso según con qué se carga (mismo criterio y constantes que `SesionReloj.pasoKg`).
    public static func paso(_ equipo: Preparacion.Equipo, kg: Double) -> Double {
        switch equipo {
        case .maquina: Preparacion.pasoMaquina
        case .mancuerna: kg < Preparacion.limiteMancuernaLiviana ? Preparacion.pasoMancuernaLiviana : Preparacion.pasoMancuernaPesada
        case .barra, .otro: Preparacion.paso
        }
    }

    /// Un paso arriba o abajo, alineado a la grilla del equipo (como la corona del reloj).
    public static func mover(_ kg: Double, pasos: Int, equipo: Preparacion.Equipo) -> Double {
        var k = kg
        for _ in 0..<abs(pasos) {
            if pasos > 0 {
                let p = paso(equipo, kg: k)
                k = (k / p + 1e-9).rounded(.down) * p + p
            } else {
                let p = paso(equipo, kg: max(0, k - 1e-6))
                k = (k / p - 1e-9).rounded(.up) * p - p
            }
            k = min(Verosimilitud.kgMax, max(0, (k * 100).rounded() / 100))
        }
        return k
    }

    public static let subidaMinima = 2.5
    public static let subidaMaxima = 5.0

    /// A cuánto se sugiere subir: la primera marca del equipo a 2,5 kg o más, si no pasa de 5 (barra 2,5; máquina 5; mancuerna
    /// 3 o 4, porque su grilla es de 1 o 2). Nil si en esa grilla no hay un salto entre 2,5 y 5 (43 en máquina): sin sugerencia.
    public static func hasta(desde: Double, equipo: Preparacion.Equipo) -> Double? {
        guard desde > 0 else { return nil }
        var k = desde
        for _ in 0..<10 {
            k = mover(k, pasos: 1, equipo: equipo)
            let subida = k - desde
            if subida >= subidaMinima - 1e-9 { return subida <= subidaMaxima + 1e-9 ? k : nil }
        }
        return nil
    }

    /// La carga base de la vez pasada: la moda de sus kilos y, en empate, la más alta. Una serie que salió con menos no
    /// corre la base de todas.
    public static func moda(_ kilos: [Double]) -> Double? {
        let kilos = kilos.filter { $0 > 0 }   // un 0 viejo no es una carga (`kgSugerido`)
        guard !kilos.isEmpty else { return nil }
        var cuenta: [Double: Int] = [:]
        for k in kilos { cuenta[k, default: 0] += 1 }
        return cuenta.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }
}

/// La guardia del OK apurado: el primer OK a menos de 10 s del anterior, sin cambiar reps, no registra y pide otro toque. El
/// segundo toque vale entre medio segundo y 3 segundos después: un doble toque no la vence y un toque tardío vuelve a pedir.
public struct GuardiaOK: Equatable, Sendable, Codable {
    public static let esperaSegundoToque: Double = 500
    public static let venceEn: Double = 3_000
    public private(set) var desde: Double?
    public private(set) var serie: Int?
    public init() {}

    public func activa(serie i: Int, ahora: Double) -> Bool {
        guard let d = desde, serie == i else { return false }
        return ahora - d < Self.venceEn
    }

    public mutating func levantar(serie i: Int, ahora: Double) { desde = ahora; serie = i }
    public mutating func limpiar() { desde = nil; serie = nil }

    /// ¿Este toque cuenta como el segundo? Si fue un doble toque, no cuenta ni levanta nada; si vencía, arranca de nuevo.
    public func esSegundoToque(serie i: Int, ahora: Double) -> Bool {
        guard let d = desde, serie == i else { return false }
        let t = ahora - d
        return t >= Self.esperaSegundoToque && t < Self.venceEn
    }

    public func esDobleToque(serie i: Int, ahora: Double) -> Bool {
        guard let d = desde, serie == i else { return false }
        return ahora - d < Self.esperaSegundoToque
    }
}

public struct CargaSimple: Equatable, Sendable {
    public struct Referencia: Equatable, Sendable {
        public var reps: Int
        public var kg: Double?
        public init(reps: Int, kg: Double?) { self.reps = reps; self.kg = kg }
    }

    public struct Serie: Equatable, Sendable {
        public var reps: Int?
        public var kg: Double?
        public var confirmada = false
        /// El cliente movió las reps: lo que marcó no se pisa con la base (lo mismo que «lo girado no se pisa» del reloj).
        public var tocada = false
        public var variante: String?
    }

    public enum Aumento: Equatable, Sendable, Codable {
        case noCorresponde
        case sugerido(desde: Double, hasta: Double)
        case aceptado(desde: Double, hasta: Double)
        case descartado
    }

    public enum OrigenBase: Equatable, Sendable { case ultimaVez, plan, ninguno }

    public enum Evaluacion: Equatable, Sendable {
        case faltanDatos
        /// OK sin tocar nada a pocos segundos del anterior: se pide un segundo toque.
        case guardia
        case lista(reps: Int, kg: Double?)
    }

    /// Lo que se guarda en el teléfono por ejercicio y semana: sobrevive a relanzar la app. Solo local.
    public struct Estado: Codable, Equatable, Sendable {
        public var carga: Double?
        /// La base congelada: el historial trae también las filas de hoy y, sin esto, relanzar sugeriría sobre lo ya aceptado.
        public var cargaUltimaVez: Double?
        public var mismoPeso = true
        public var aumento: Aumento = .noCorresponde
        /// Las reps que el cliente marcó en series que faltan (índice → reps).
        public var repsMarcadas: [Int: Int] = [:]
        /// El peso por serie con «mismo peso» destildado (índice → kg).
        public var kilos: [Int: Double] = [:]
        public var cargaCambioDesdeOK = false
        /// ms del último OK (para la guardia).
        public var ultimoOK: Double?
        public init() {}
    }

    public let sinKg: Bool
    public let equipo: Preparacion.Equipo
    public let repsPlan: String?
    public let calibracion: Bool
    public let repsDelPlanCambian: Bool
    public let ultimaVez: [Referencia]
    public let recordKg: Double
    /// Milisegundos en los que un OK sin cambiar reps se toma como sospechoso.
    public var guardiaMs: Double

    public private(set) var carga: Double?
    public private(set) var cargaUltimaVez: Double?
    public private(set) var mismoPeso = true
    public internal(set) var series: [Serie]
    public private(set) var aumento: Aumento = .noCorresponde
    public internal(set) var ultimoOK: Double?
    public var varianteActual: String?
    /// Cambió la carga después del último OK: recién ahí tiene sentido ofrecer corregir las hechas.
    public private(set) var cargaCambioDesdeOK = false

    /// `seriesLocales`: las del día (hechas y por hacer), que mandan sobre la cantidad; `estado`: lo guardado. Sin estado, la
    /// base sale de `ultimaVez` y `yaAumentadoEstaSemana` (el mismo ejercicio en otro día de la semana ya aceptó o rechazó)
    /// apaga la sugerencia.
    public init(ejercicio e: Ejercicio, semana: Int, ultimaVez: [Referencia], equipo: Preparacion.Equipo,
                sinKg: Bool? = nil, recordKg: Double = 0, guardiaMs: Double = 10_000, mensajeSemana: String? = nil,
                seriesLocales: [SerieLocal]? = nil, estado: Estado? = nil, yaAumentadoEstaSemana: Bool = false) {
        let sk = sinKg ?? ReglasEjercicio.sinKg(e)
        self.sinKg = sk
        self.equipo = equipo
        let pauta = Progresiones.pauta(e, semana: semana)
        repsPlan = pauta.reps
        let nota = Progresiones.nota(e, semanaActual: semana)
        calibracion = nota?.calibracion ?? false
        var previaReps: String?
        if !e.progresion.isEmpty, let p = Progresiones.pasoDePlan(e.progresion, semana: Progresiones.semanaJS(semana)).anterior { previaReps = p.reps }
        repsDelPlanCambian = previaReps != nil && Progresiones.tope(previaReps) != Progresiones.tope(pauta.reps)
        self.ultimaVez = ultimaVez
        self.recordKg = recordKg
        self.guardiaMs = guardiaMs

        let base = sk ? nil : AumentoCarga.moda(ultimaVez.compactMap(\.kg))
        carga = estado == nil ? base : estado!.carga
        cargaUltimaVez = estado == nil ? base : estado!.cargaUltimaVez
        mismoPeso = estado?.mismoPeso ?? true
        cargaCambioDesdeOK = estado?.cargaCambioDesdeOK ?? false
        ultimoOK = estado?.ultimoOK
        if let a = estado?.aumento {
            aumento = a
        } else if !yaAumentadoEstaSemana, let b = base, !sk, AumentoCarga.corresponde(e, semana: semana, mensajeSemana: mensajeSemana),
                  let h = AumentoCarga.hasta(desde: b, equipo: equipo) {
            aumento = .sugerido(desde: b, hasta: h)
        }

        let cuantas = seriesLocales?.count ?? max(pauta.series ?? 1, 1)
        var filas: [Serie] = []
        let cargaInicial = carga
        for i in 0..<cuantas {
            let l = seriesLocales.flatMap { i < $0.count ? $0[i] : nil }
            if let l, l.confirmada {
                filas.append(Serie(reps: Int(l.reps), kg: Double(l.kg), confirmada: true, tocada: false, variante: l.varianteRegistrada))
            } else {
                let marcada = estado?.repsMarcadas[i] ?? l.flatMap { Int($0.reps) }
                let kg = (estado?.mismoPeso ?? true) ? cargaInicial : (estado?.kilos[i] ?? cargaInicial)
                filas.append(Serie(reps: marcada, kg: kg, confirmada: false, tocada: marcada != nil, variante: nil))
            }
        }
        series = filas
    }

    /// Lo que se guarda en disco.
    public var estado: Estado {
        var e = Estado()
        e.carga = carga; e.cargaUltimaVez = cargaUltimaVez; e.mismoPeso = mismoPeso; e.aumento = aumento
        e.cargaCambioDesdeOK = cargaCambioDesdeOK; e.ultimoOK = ultimoOK
        for (i, s) in series.enumerated() where !s.confirmada {
            if s.tocada, let r = s.reps { e.repsMarcadas[i] = r }
            if !mismoPeso, let k = s.kg { e.kilos[i] = k }
        }
        return e
    }

    // MARK: Lo que se ve

    /// La primera sin confirmar: la del dial.
    public var activa: Int? { series.firstIndex { !$0.confirmada } }
    public var confirmadas: Int { series.filter(\.confirmada).count }
    public var completo: Bool { activa == nil }

    /// La vez pasada, en esta misma serie; si hoy hay más series que entonces, la última que hizo.
    public func referencia(_ i: Int) -> Referencia? {
        ultimaVez.indices.contains(i) ? ultimaVez[i] : ultimaVez.last
    }

    /// Sin número de reps en el plan (AMRAP, máx.) y el cliente no marcó nada: el OK no significa nada todavía.
    public var pideElegirReps: Bool { ReglasEjercicio.repsDelPlan(repsPlan) == nil }

    /// Las reps base y de dónde salen. Con otra carga que la vez pasada o con otras reps del plan esta semana, lo de la
    /// vez pasada ya no describe esta serie y manda el plan. Son referencia, no tope.
    public func base(_ i: Int) -> (reps: Int?, origen: OrigenBase) {
        let plan = ReglasEjercicio.repsDelPlan(repsPlan).map { Int($0) }
        guard series.indices.contains(i) else { return (nil, .ninguno) }
        if let r = referencia(i), plan == nil || (!repsDelPlanCambian && (sinKg || series[i].kg == r.kg)) {
            return (r.reps, .ultimaVez)
        }
        if let plan { return (plan, .plan) }
        return (nil, .ninguno)
    }

    public func reps(_ i: Int) -> Int? {
        guard series.indices.contains(i) else { return nil }
        return series[i].reps ?? base(i).reps
    }

    /// Lo marcado respecto de la base (+1, −2); nil si coincide o no hay base.
    public func diferencia(_ i: Int) -> Int? {
        guard let r = reps(i), let b = base(i).reps, r != b else { return nil }
        return r - b
    }

    public func puedeConfirmar(_ i: Int) -> Bool {
        guard series.indices.contains(i), !series[i].confirmada, let r = reps(i), r >= 1 else { return false }
        if pideElegirReps && !series[i].tocada { return false }
        return sinKg || series[i].kg != nil
    }

    /// Las ya hechas con otro peso que la carga actual.
    public var hechasConOtraCarga: Int {
        guard mismoPeso, cargaCambioDesdeOK, let c = carga else { return 0 }
        return series.filter { $0.confirmada && $0.kg != c && $0.variante == varianteActual }.count
    }

    /// La vez pasada no fueron todas con el mismo peso.
    public var ultimaVezMixta: Bool { Set(ultimaVez.compactMap(\.kg)).count > 1 }

    // MARK: Carga

    /// Toca solo las series que faltan: lo ya hecho se hizo con el peso que se hizo. Las reps sin tocar se recalculan.
    public mutating func fijarCarga(_ kg: Double?) {
        guard !sinKg else { return }
        if kg != carga { cargaCambioDesdeOK = true }
        carga = kg
        // Tocó la carga a mano: la sugerencia o el «subiste a…» ya no describen lo que hay.
        switch aumento {
        case let .sugerido(desde, _) where kg != desde: aumento = .descartado
        case let .aceptado(_, hasta) where kg != hasta: aumento = .descartado
        default: break
        }
        guard mismoPeso else { return }
        for i in series.indices where !series[i].confirmada { series[i].kg = kg }
    }

    public mutating func moverCarga(_ pasos: Int) {
        guard let c = carga else { return }
        fijarCarga(AumentoCarga.mover(c, pasos: pasos, equipo: equipo))
    }

    /// La corrección de «me olvidé de cambiarla antes de empezar»: pasa las hechas a la carga actual. Devuelve cuáles.
    public mutating func aplicarCargaALasHechas() -> [Int] {
        guard mismoPeso, cargaCambioDesdeOK, let c = carga else { return [] }
        var tocadas: [Int] = []
        cargaCambioDesdeOK = false
        for i in series.indices where series[i].confirmada && series[i].kg != c && series[i].variante == varianteActual {
            series[i].kg = c
            tocadas.append(i)
        }
        return tocadas
    }

    public mutating func aceptarAumento() {
        guard case let .sugerido(desde, hasta) = aumento else { return }
        aumento = .aceptado(desde: desde, hasta: hasta)
        fijarCarga(hasta)
        if !mismoPeso { for i in series.indices where !series[i].confirmada { series[i].kg = hasta } }
    }

    public mutating func descartarAumento() {
        if case .sugerido = aumento { aumento = .descartado }
    }

    /// Volver a la carga anterior desde el aviso de aumento aceptado.
    public mutating func deshacerAumento() {
        guard case let .aceptado(desde, hasta) = aumento else { return }
        aumento = .sugerido(desde: desde, hasta: hasta)
        fijarCarga(desde)
    }

    // MARK: Peso por serie

    /// Destildar «mismo peso»: cada serie que falta arranca con el suyo de la vez pasada si fue una mezcla; si no, con la
    /// carga. Volver a tildarlo iguala las que faltan a la carga; las hechas no se tocan.
    public mutating func usarMismoPeso(_ si: Bool) {
        guard si != mismoPeso else { return }
        mismoPeso = si
        for i in series.indices where !series[i].confirmada {
            if si {
                // En primera vez con pesos por fila la carga puede estar vacía: toma la de la primera que tenga peso.
                if carga == nil { carga = series.compactMap(\.kg).first }
                series[i].kg = carga
            } else if ultimaVezMixta, carga == cargaUltimaVez, let k = referencia(i)?.kg { series[i].kg = k }
        }
    }

    public mutating func fijarKg(_ i: Int, _ kg: Double?) {
        guard series.indices.contains(i), !series[i].confirmada, !mismoPeso else { return }
        series[i].kg = kg
    }

    public mutating func moverKg(_ i: Int, pasos: Int) {
        guard series.indices.contains(i), let k = series[i].kg else { return }
        fijarKg(i, AumentoCarga.mover(k, pasos: pasos, equipo: equipo))
    }

    // MARK: Reps

    /// Sumar o restar. Solo el piso de 1 y el tope de Verosimilitud: hacer más de lo que dice el plan siempre vale.
    public mutating func ajustarReps(_ i: Int, _ d: Int) {
        guard series.indices.contains(i), !series[i].confirmada, d != 0 else { return }
        let actual = reps(i) ?? ReglasEjercicio.repsDelPlan(repsPlan).map { Int($0) } ?? 10
        series[i].reps = min(Int(Verosimilitud.repsMax), max(1, actual + d))
        series[i].tocada = true
    }

    // MARK: Confirmar

    /// El OK de la serie: qué se registraría o por qué todavía no. `insistio` es el segundo toque después de la guardia.
    public func evaluarOK(_ i: Int, ahora: Double, insistio: Bool = false) -> Evaluacion {
        guard puedeConfirmar(i), let r = reps(i) else { return .faltanDatos }
        let miro = series[i].tocada && r != base(i).reps   // sumar y restar lo mismo no es mirar
        if !miro, !insistio, let u = ultimoOK, ahora - u < guardiaMs { return .guardia }
        return .lista(reps: r, kg: sinKg ? nil : series[i].kg)
    }

    /// El OK ya quedó registrado: anota cuándo, para la guardia de la próxima.
    public mutating func anotarOK(ahora: Double) {
        ultimoOK = ahora
        cargaCambioDesdeOK = false
    }
}
