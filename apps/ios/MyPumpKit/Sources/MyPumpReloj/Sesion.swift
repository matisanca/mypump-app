import Foundation
import MyPumpModelos
import MyPumpReglas

/// El entreno en el reloj: la rutina del día, la serie que se está cargando con la corona, el descanso y la cola. Es
/// puro (sin WatchConnectivity ni HealthKit): la app del reloj lo guarda en disco tal cual y le pasa la hora.
///
/// Las reglas son las del kit, las mismas del teléfono: la preparación (`Preparacion.series`, con el kg en vivo de la
/// primera serie efectiva), el récord (`RecordSerie.evaluar` contra las marcas de días anteriores y las de hoy), el
/// descanso (`Descanso`, anclado al reloj) y los topes de una serie (`Verosimilitud`).
public struct SesionReloj: Codable, Equatable, Sendable {
    public private(set) var rutina: RutinaReloj?
    public private(set) var cola = ColaReloj()
    /// El lugar que se mira.
    public private(set) var lugar: String?
    /// Lo que marca la corona para la próxima serie del lugar.
    public private(set) var reps: Int = 10
    public private(set) var kg: Double?
    public private(set) var descanso: Descanso.Guardado?
    /// El descanso actual ya vibró.
    private var descansoSono = false
    /// ms: cuándo se empezó en el reloj (o en el teléfono, si vino con la rutina).
    public private(set) var inicio: Double?
    public private(set) var terminada = false
    /// Los récords de hoy, en orden («Press banca · Récord: +2,5 kg»).
    public private(set) var records: [String] = []
    /// Lo que el iPhone rechazó, para mostrárselo al alumno («Esta serie no se pudo guardar: …»), del más viejo al más
    /// nuevo (los últimos `topeRechazos`).
    public private(set) var rechazos: [String] = []
    /// Por qué el iPhone todavía no aplicó lo que hay en la cola (`pendiente`); nil si no se sabe o no hay nada.
    public private(set) var esperando: String?
    public static let topeRechazos = 5
    /// ms: la última vez que se tocó algo (para no perder lo hecho si llega una rutina vieja).
    public private(set) var actualizada: Double = 0

    public init() {}

    // MARK: - La rutina

    /// Llegó una rutina del iPhone. Si es de otro día o de otra semana, reemplaza todo menos la cola (lo que el teléfono
    /// todavía no acusó se sigue mandando); si es la misma, se le vuelven a poner encima las series que el teléfono
    /// todavía no tiene. Una rutina más vieja que la que ya hay se ignora.
    public mutating func recibir(_ nueva: RutinaReloj) {
        if let r = rutina, r.diaId == nueva.diaId, r.semana == nueva.semana, r.fecha == nueva.fecha, nueva.generada < r.generada { return }
        let mismoDia = rutina.map { $0.diaId == nueva.diaId && $0.semana == nueva.semana && $0.fecha == nueva.fecha } ?? false
        var r = nueva
        aplicarPendientes(&r)
        rutina = r
        if !mismoDia {
            terminada = r.diaFinalizado
            records = []
            inicio = r.inicioSesion
        } else {
            if inicio == nil { inicio = r.inicioSesion }
            // Cerrado en el iPhone: se termina también acá (la app del reloj cierra su sesión de entreno).
            if r.diaFinalizado && !terminada {
                terminada = true
                descanso = nil
                descansoSono = false
            }
        }
        // El descanso del teléfono, si es más nuevo que el del reloj (lo empezó allá).
        if let d = r.descanso, (descanso?.endsAt ?? 0) < d.endsAt { descanso = d; descansoSono = false }
        if lugar.flatMap(ejercicio) == nil || !mismoDia { lugar = r.ejercicios.first { !$0.terminado }?.lugar ?? r.ejercicios.first?.lugar }
        cargarCorona()
    }

    /// Las series de la cola sobre la rutina (el teléfono todavía no las tiene).
    private func aplicarPendientes(_ r: inout RutinaReloj) {
        for p in cola.pendientes {
            guard p.evento.diaId == r.diaId, p.evento.semana == r.semana, p.cuenta == nil || p.cuenta == r.cuenta,
                  p.rutinaId == nil || p.rutinaId == r.rutinaId else { continue }
            if case .serie(_, _, let l, let i, let reps, let kg) = p.evento,
               let e = r.ejercicios.firstIndex(where: { $0.lugar == l }), i < r.ejercicios[e].series.count {
                r.ejercicios[e].series[i].confirmada = true
                r.ejercicios[e].series[i].reps = reps
                r.ejercicios[e].series[i].kg = kg
                Self.actualizarEstado(&r.ejercicios[e])
            }
        }
    }

    static func actualizarEstado(_ e: inout EjercicioReloj) {
        guard !EstadosEjercicio.terminales.contains(e.estado) else { return }
        let n = e.confirmadas
        e.estado = n == 0 ? "pendiente" : (n == e.series.count ? "completo" : "en_curso")
    }

    public func ejercicio(_ lugar: String) -> EjercicioReloj? { rutina?.ejercicios.first { $0.lugar == lugar } }
    public var actual: EjercicioReloj? { lugar.flatMap(ejercicio) }
    public var todoHecho: Bool { (rutina?.ejercicios.isEmpty == false && rutina!.ejercicios.allSatisfy(\.terminado)) || terminada }
    public var iniciada: Bool { inicio != nil }

    /// Elegir un ejercicio de la lista.
    public mutating func elegir(_ lugar: String) {
        guard ejercicio(lugar) != nil else { return }
        self.lugar = lugar
        cargarCorona()
    }

    /// La corona arranca en lo sugerido de la próxima serie (lo de la última vez, o lo del plan); sin sugerido, lo que
    /// se hizo en la serie de arriba.
    mutating func cargarCorona() {
        guard let e = actual else { return }
        let i = e.proximaSerie ?? max(0, e.series.count - 1)
        let s = e.series.indices.contains(i) ? e.series[i] : nil
        let arriba = i > 0 && e.series.indices.contains(i - 1) ? e.series[i - 1] : nil
        let plan = ReglasEjercicio.repsDelPlan(e.repsPlan).map { Int($0) }
        reps = s?.reps ?? s?.repsSugeridas ?? arriba?.reps ?? plan ?? 10
        kg = e.sinKg ? nil : (s?.kg ?? s?.kgSugerido ?? arriba?.kg)
        reps = Self.acotarReps(reps)
    }

    // MARK: - La corona

    public static let repsMin = 1
    public static var repsMax: Int { Int(Verosimilitud.repsMax) }
    /// El tope de la corona: lo que el teléfono ya preguntaría («¿Está bien cargado?»).
    public static var kgMax: Double { Verosimilitud.kgRaro }

    static func acotarReps(_ r: Int) -> Int { min(repsMax, max(repsMin, r)) }

    /// El paso del kg según con qué se carga (el mismo criterio que el redondeo de la preparación).
    public static func pasoKg(_ equipo: Preparacion.Equipo, kg: Double) -> Double {
        switch equipo {
        case .maquina: Preparacion.pasoMaquina
        case .mancuerna: kg < Preparacion.limiteMancuernaLiviana ? Preparacion.pasoMancuernaLiviana : Preparacion.pasoMancuernaPesada
        case .barra, .otro: Preparacion.paso
        }
    }

    /// Un clic de la corona en reps (±1).
    public mutating func girarReps(_ pasos: Int) { reps = Self.acotarReps(reps + pasos) }

    /// Un clic de la corona en kg: un paso del equipo (alineado a su grilla: un 21 de mancuerna sube a 22 y baja a 20),
    /// sin bajar de 0 ni pasar el tope.
    public mutating func girarKg(_ pasos: Int) {
        guard let e = actual, !e.sinKg, pasos != 0 else { return }
        var k = kg ?? 0
        for _ in 0..<abs(pasos) {
            if pasos > 0 {
                let p = Self.pasoKg(e.equipoCarga, kg: k)
                k = (k / p + 1e-9).rounded(.down) * p + p
            } else {
                let p = Self.pasoKg(e.equipoCarga, kg: max(0, k - 1e-6))
                k = (k / p - 1e-9).rounded(.up) * p - p
            }
            k = min(Self.kgMax, max(0, (k * 100).rounded() / 100))
        }
        kg = k
    }

    // MARK: - La preparación (E1)

    /// La preparación del lugar como en el teléfono: la del plan si la trae; si no, la que arma el kit. El kg sigue a la
    /// primera serie efectiva (lo hecho; si no, lo que marca la corona cuando es la primera; si no, lo sugerido). Es
    /// solo una indicación: no se registra.
    public func preparacion(_ lugar: String) -> [Preparacion.Serie] {
        guard let r = rutina, let i = r.ejercicios.firstIndex(where: { $0.lugar == lugar }) else { return [] }
        let e = r.ejercicios[i]
        let primera = e.series.first
        let enVivo: Double? = (self.lugar == lugar && e.proximaSerie == 0) ? kg : nil
        let ref = primera?.kg ?? enVivo ?? primera?.kgSugerido
        return Preparacion.series(dia: r.entradasPreparacion, indice: i, nombre: e.nombre, equipo: e.equipo, sinKg: e.sinKg,
                                  kgEfectivo: ref, plan: e.aproximacionesPlan?.map(\.aproximacion))
    }

    // MARK: - Confirmar

    public struct Confirmacion: Equatable, Sendable {
        /// «Récord: +2,5 kg»
        public var record: String?
        /// Arrancó un descanso (no en la última serie del día).
        public var descanso: Bool
        /// Con esta serie quedó todo hecho.
        public var diaCompleto: Bool
        /// Pasó al siguiente ejercicio.
        public var siguiente: String?
    }

    /// Confirma la próxima serie del lugar con lo que marca la corona: la marca hecha, la pone en la cola (con
    /// «iniciar» antes si la sesión no había empezado, como el teléfono con la primera serie), avisa el récord y arranca
    /// el descanso. nil si no hay nada para confirmar.
    @discardableResult
    public mutating func confirmar(ahora: Double) -> Confirmacion? {
        guard var r = rutina, let l = lugar, let ei = r.ejercicios.firstIndex(where: { $0.lugar == l }),
              let si = r.ejercicios[ei].proximaSerie, reps >= Self.repsMin else { return nil }
        if !iniciada { iniciar(ahora: ahora) }
        var e = r.ejercicios[ei]
        let kgSerie: Double? = e.sinKg ? nil : (kg ?? 0)
        // El récord: contra los días anteriores y las otras series de hoy de este ejercicio.
        var record: String?
        if e.historiaSuficiente, let k = kgSerie {
            let hoy = e.series.filter(\.confirmada).compactMap { s in s.reps.map { RecordSerie.Marca(kg: s.kg ?? 0, reps: $0) } }
            record = RecordSerie.evaluar(RecordSerie.Marca(kg: k, reps: reps), sinKg: e.sinKg, verosimil: true,
                                         anteriores: e.anteriores.map(\.marca), hoy: hoy)?.texto
        }
        e.series[si].confirmada = true
        e.series[si].reps = reps
        e.series[si].kg = kgSerie
        Self.actualizarEstado(&e)
        r.ejercicios[ei] = e
        rutina = r
        cola.encolar(EventoEnCola(.serie(diaId: r.diaId, semana: r.semana, lugar: l, indice: si, reps: reps, kg: kgSerie), creado: ahora, cuenta: r.cuenta, rutinaId: r.rutinaId))
        if let record { records.append("\(e.nombre) · \(record)") }
        actualizada = ahora
        let completo = todoHecho
        var siguiente: String?
        if completo {
            descanso = nil
            descansoSono = false
        } else {
            descanso = Descanso.iniciar(segundos: Double(e.descansoSegundos), ahora: ahora).guardado
            descansoSono = false
            if e.terminado, let sig = r.ejercicios[(ei + 1)...].first(where: { !$0.terminado }) ?? r.ejercicios.first(where: { !$0.terminado }) {
                lugar = sig.lugar
                siguiente = sig.lugar
            }
        }
        cargarCorona()
        return Confirmacion(record: record, descanso: !completo, diaCompleto: completo, siguiente: siguiente)
    }

    // MARK: - Sesión

    /// «Empezar» en el reloj.
    public mutating func iniciar(ahora: Double) {
        guard let r = rutina, !iniciada else { return }
        inicio = ahora
        terminada = false
        cola.encolar(EventoEnCola(.iniciar(diaId: r.diaId, semana: r.semana), creado: ahora, cuenta: r.cuenta, rutinaId: r.rutinaId))
        actualizada = ahora
    }

    /// «Terminar» en el reloj: cierra la sesión (en el teléfono, al llegar) y devuelve el resumen.
    public mutating func terminar(ahora: Double, salud: SaludEntreno = SaludEntreno()) -> ResumenReloj? {
        guard let r = rutina else { return nil }
        if !terminada { cola.encolar(EventoEnCola(.terminar(diaId: r.diaId, semana: r.semana), creado: ahora, cuenta: r.cuenta, rutinaId: r.rutinaId)) }
        let resumen = self.resumen(ahora: ahora, salud: salud)
        terminada = true
        descanso = nil
        descansoSono = false
        actualizada = ahora
        return resumen
    }

    // MARK: - Descanso

    public func descansoEnCurso(ahora: Double) -> Descanso? { Descanso.restaurar(descanso, ahora: ahora) }

    /// El tick del descanso: true la vez que termina (la háptica), salvo que haya terminado hace rato (la app estuvo
    /// cerrada: no vibra tarde). Al pasar el cierre se va.
    public mutating func tickDescanso(ahora: Double) -> Bool {
        guard let g = descanso else { return false }
        var termino = false
        if ahora >= g.endsAt && !descansoSono {
            descansoSono = true
            termino = ahora - g.endsAt < Self.vibrarHasta
        }
        if ahora >= (g.autoCloseAt ?? g.endsAt) {
            descanso = nil
            descansoSono = false
        }
        return termino
    }

    /// Un fin de descanso visto más tarde que esto (ms) ya no vibra.
    public static let vibrarHasta: Double = 5_000

    /// −15 / +15 con la corona o los botones.
    public mutating func ajustarDescanso(_ segundos: Double, ahora: Double) {
        guard var d = Descanso.restaurar(descanso, ahora: ahora) else { return }
        d.ajustar(segundos: segundos, ahora: ahora)
        descanso = d.guardado
        if d.fin > ahora { descansoSono = false }
    }

    public mutating func saltarDescanso() { descanso = nil; descansoSono = false }

    // MARK: - La cola

    /// El iPhone habla otra versión del protocolo: no se le reenvía nada (los eventos quedan guardados en la cola) hasta
    /// que una de las dos apps se actualice. El texto es para el alumno.
    public private(set) var incompatible: String?
    /// La versión del iPhone cuando dijo que no nos entiende.
    private var versionIncompatible: Int?
    public mutating func marcarIncompatible(version v: Int) {
        incompatible = ProtocoloReloj.textoIncompatible(v, enElReloj: true)
        versionIncompatible = v
    }
    /// Llegó un sobre del iPhone con la versión `v`: si es otra que la de cuando no nos entendía, se actualizó una de las
    /// dos apps y se vuelve a mandar (si sigue sin entender, contesta `incompatible` otra vez).
    public mutating func revisarVersion(_ v: Int) {
        guard let vi = versionIncompatible, v != vi else { return }
        incompatible = nil
        versionIncompatible = nil
    }

    public mutating func paraEnviar(ahora: Double, forzar: Bool = false) -> [EventoEnCola] {
        incompatible == nil ? cola.paraEnviar(ahora: ahora, forzar: forzar) : []
    }
    public mutating func fallo(_ ids: [UUID]) { cola.fallo(ids) }
    /// Los acuses del iPhone: salen de la cola los aplicados y los rechazados (estos, con su motivo a la vista); los
    /// pendientes se quedan con el motivo en `esperando`.
    public mutating func acusar(_ a: [AcuseEvento], ahora: Double = 0) {
        let salen = cola.acusar(a, ahora: ahora)
        for e in salen {
            guard let acuse = a.first(where: { $0.id == e.id }), acuse.resultado == .rechazado else { continue }
            let motivo = acuse.motivo ?? "el iPhone no lo aceptó"
            let texto: String
            switch e.evento {
            case .serie: texto = "Esta serie no se pudo guardar: \(motivo)"
            case .iniciar: texto = "No se pudo empezar en el iPhone: \(motivo)"
            case .terminar: texto = "No se pudo cerrar en el iPhone: \(motivo)"
            }
            rechazos.append(texto)
        }
        if rechazos.count > Self.topeRechazos { rechazos.removeFirst(rechazos.count - Self.topeRechazos) }
        if let p = a.last(where: { $0.resultado == .pendiente }) { esperando = p.motivo ?? "Esperando al iPhone" }
        if cola.vacia { esperando = nil }
    }

    /// El alumno ya leyó los rechazos.
    public mutating func leerRechazos() { rechazos = [] }

    // MARK: - Resumen

    public func resumen(ahora: Double, salud: SaludEntreno = SaludEntreno()) -> ResumenReloj {
        let ejercicios = rutina?.ejercicios ?? []
        let hechas = ejercicios.flatMap { $0.series.filter(\.confirmada) }
        let volumen = hechas.reduce(0.0) { $0 + ($1.kg ?? 0) * Double($1.reps ?? 0) }
        return ResumenReloj(minutos: TiempoEntreno.minutosSesion(inicio: inicio, ahora: ahora), series: hechas.count,
                            ejercicios: ejercicios.filter { $0.confirmadas > 0 || $0.terminado }.count, total: ejercicios.count,
                            volumenKg: volumen, records: records, fcMedia: salud.fcMedia, fcMaxima: salud.fcMaxima,
                            kcal: salud.kcal, sinEnviar: cola.pendientes.count)
    }
}

/// Lo que mide la sesión de entreno del reloj (HealthKit, en vivo; no se guarda en Salud).
public struct SaludEntreno: Codable, Equatable, Sendable {
    public var fcActual: Double?
    public var fcMedia: Double?
    public var fcMaxima: Double?
    public var kcal: Double?
    public init(fcActual: Double? = nil, fcMedia: Double? = nil, fcMaxima: Double? = nil, kcal: Double? = nil) {
        self.fcActual = fcActual; self.fcMedia = fcMedia; self.fcMaxima = fcMaxima; self.kcal = kcal
    }
}

/// El resumen al terminar.
public struct ResumenReloj: Codable, Equatable, Sendable {
    public var minutos: Int?
    public var series: Int
    public var ejercicios: Int
    public var total: Int
    public var volumenKg: Double
    public var records: [String]
    public var fcMedia: Double?
    public var fcMaxima: Double?
    public var kcal: Double?
    /// Lo que todavía no llegó al iPhone.
    public var sinEnviar: Int

    /// «12.450 kg»
    public var textoVolumen: String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "\(f.string(from: NSNumber(value: volumenKg.rounded())) ?? "0") kg"
    }

    public var textoMinutos: String { minutos.map { "\($0) min" } ?? "—" }
    public var textoSinEnviar: String? {
        sinEnviar == 0 ? nil : "\(sinEnviar) \(sinEnviar == 1 ? "cambio" : "cambios") sin pasar al iPhone"
    }
}
