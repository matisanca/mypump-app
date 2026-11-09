import Foundation
import MyPumpModelos

// PROTOTIPO (rama nativa-carga-simple): las reglas de la carga única por ejercicio. No las usa ninguna pantalla real.
// Vive en el kit para probarla con `swift test` y para que el gemelo de Android y el reloj salgan de la misma tabla. Ver
// la propuesta en nativa-evidencia/carga-simple/spec.md. Sale a `registrar_carga` serie por serie, como hoy.

/// Cuándo toca subir por planificación y de cuánto es el paso. El plan NO trae kilos (solo series, reps y RIR por semana):
/// lo único que dice es «bajan las reps, subí la carga», y eso es lo que se detecta acá.
public enum AumentoCarga {
    /// Esta semana bajan las reps con las mismas series (el mismo caso en que `Progresiones.nota` dice «Subí la carga»).
    /// Nunca en calibración, sin progresión ni en la primera semana.
    public static func corresponde(_ e: Ejercicio, semana: Int) -> Bool {
        guard let nota = Progresiones.nota(e, semanaActual: semana), !nota.calibracion else { return false }
        let cur = Progresiones.pauta(e, semana: semana), prev = Progresiones.pauta(e, semana: semana - 1)
        guard let a = Progresiones.tope(cur.reps), let b = Progresiones.tope(prev.reps), a < b else { return false }
        return cur.series != nil && cur.series == prev.series
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
        /// La variante con la que se hizo: la del ejercicio cambia, la de la serie no (`varianteRegistrada` de hoy).
        public var variante: String?
    }

    public enum Aumento: Equatable, Sendable {
        case noCorresponde
        case sugerido(desde: Double, hasta: Double)
        case aceptado(desde: Double, hasta: Double)
        case descartado
    }

    public enum OrigenBase: Equatable, Sendable { case ultimaVez, plan, ninguno }

    public enum Resultado: Equatable, Sendable {
        case registrada
        case faltanDatos
        /// OK sin tocar nada a pocos segundos del anterior: se pide un segundo toque.
        case guardia
        case rechazada(String)
        case preguntar(Pregunta)
    }

    public let sinKg: Bool
    public let equipo: Preparacion.Equipo
    public let repsPlan: String?
    public let calibracion: Bool
    public let repsDelPlanCambian: Bool
    public let ultimaVez: [Referencia]
    public let recordKg: Double
    /// Segundos en los que un OK sin tocar nada se toma como sospechoso.
    public var guardiaSegundos: Double

    public private(set) var carga: Double?
    public private(set) var cargaUltimaVez: Double?
    public private(set) var mismoPeso = true
    public private(set) var series: [Serie]
    public private(set) var aumento: Aumento = .noCorresponde
    public private(set) var ultimoOK: Date?
    public var varianteActual: String?
    /// Cambió la carga después del último OK: recién ahí tiene sentido ofrecer corregir las hechas.
    public private(set) var cargaCambioDesdeOK = false

    public init(ejercicio e: Ejercicio, semana: Int, ultimaVez: [Referencia], equipo: Preparacion.Equipo,
                sinKg: Bool? = nil, recordKg: Double = 0, guardiaSegundos: Double = 10) {
        self.sinKg = sinKg ?? ReglasEjercicio.sinKg(e)
        self.equipo = equipo
        let pauta = Progresiones.pauta(e, semana: semana)
        repsPlan = pauta.reps
        let nota = Progresiones.nota(e, semanaActual: semana)
        calibracion = nota?.calibracion ?? false
        let previa = semana > 1 ? Progresiones.pauta(e, semana: semana - 1).reps : nil
        repsDelPlanCambian = previa != nil && Progresiones.tope(previa) != Progresiones.tope(pauta.reps)
        self.ultimaVez = ultimaVez
        self.recordKg = recordKg
        self.guardiaSegundos = guardiaSegundos
        let base = self.sinKg ? nil : AumentoCarga.moda(ultimaVez.compactMap(\.kg))
        carga = base
        cargaUltimaVez = base
        series = Array(repeating: Serie(reps: nil, kg: base), count: max(pauta.series ?? 1, 1))
        if let b = base, !self.sinKg, AumentoCarga.corresponde(e, semana: semana) {
            aumento = .sugerido(desde: b, hasta: AumentoCarga.mover(b, pasos: 1, equipo: equipo))
        }
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
    /// vez pasada ya no describe esta serie y manda el plan.
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

    /// La corrección de «me olvidé de cambiarla antes de empezar»: pasa las hechas a la carga actual.
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

    /// El OK de la serie. Graba las reps que muestra el dial. `insistio` es el segundo toque después de la guardia, y
    /// `registrarIgual` la respuesta a «¿Está bien cargado?».
    public mutating func confirmar(_ i: Int, ahora: Date, insistio: Bool = false, registrarIgual: Bool? = nil) -> Resultado {
        guard puedeConfirmar(i), let r = reps(i) else { return .faltanDatos }
        let miro = series[i].tocada && r != base(i).reps   // sumar y restar lo mismo no es mirar
        if !miro, !insistio, let u = ultimoOK, ahora.timeIntervalSince(u) < guardiaSegundos { return .guardia }
        let kg = sinKg ? nil : series[i].kg
        let textoKg = kg.map(JS.texto) ?? ""
        switch Verosimilitud.evaluar(reps: String(r), kg: textoKg, sinKg: sinKg, recordKg: recordKg,
                                     repsUltimaVez: referencia(i).map { String($0.reps) } ?? "", repsPlan: repsPlan) {
        case .ok: break
        case .rechazada(let aviso): return .rechazada(aviso)
        case .preguntar(let p):
            guard registrarIgual == true else { return .preguntar(p) }
        }
        series[i].reps = r
        series[i].confirmada = true
        series[i].variante = varianteActual
        ultimoOK = ahora
        cargaCambioDesdeOK = false
        return .registrada
    }

    /// Volver atrás el último OK (error de dedo).
    public mutating func deshacer(_ i: Int) {
        guard series.indices.contains(i), series[i].confirmada else { return }
        series[i].confirmada = false
        if !series[i].tocada { series[i].reps = nil }
        if mismoPeso { series[i].kg = carga }
        series[i].variante = nil
        ultimoOK = nil
    }

    /// Corregir una serie ya hecha sin desconfirmarla: nunca queda en un limbo sin registrar.
    public mutating func corregir(_ i: Int, reps r: Int, kg: Double?) {
        guard series.indices.contains(i), series[i].confirmada, r >= 1, Double(r) <= Verosimilitud.repsMax else { return }
        series[i].reps = r
        if !sinKg, let kg { series[i].kg = kg }
    }

    /// La serie como la entiende la cola de hoy (`EscriturasEntreno.carga`). El RIR, el del plan, sin elegirlo.
    public func serieLocal(_ i: Int, rir: String) -> SerieLocal {
        SerieLocal(reps: reps(i).map(String.init) ?? "", kg: series[i].kg.map(JS.texto) ?? "", rir: rir, confirmada: series[i].confirmada,
                   varianteRegistrada: series[i].variante)
    }
}

extension CargaSimple {
    /// Al cambiar de agarre: las series ya hechas se quedan como se hicieron.
    public mutating func reemplazarHechas(_ viejas: [Serie]) {
        for i in series.indices where i < viejas.count && viejas[i].confirmada { series[i] = viejas[i] }
    }
}
