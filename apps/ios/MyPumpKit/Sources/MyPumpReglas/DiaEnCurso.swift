import Foundation
import MyPumpModelos

/// El día que se está entrenando: lo que en la web es `STATE.session`, `STATE.exerciseStates`, `STATE.exerciseMeta`,
/// `STATE.expandedId`, `DATA.historico_por_ejercicio` y `STATE.exerciseSwaps`, con las acciones de la card (confirmar una
/// serie, marcar completo, "Terminé este ejercicio", reabrir, el lápiz, el RIR, la variante, abrir la card, sustituir y
/// volver). Es puro: lo que necesita de afuera (la cola, el descanso, el historial, la sesión del servidor) lo devuelve
/// como `Efecto`s, en el orden en que la web los hace, y `ModeloEntreno` los ejecuta. Así los vectores de
/// `confirmarSerie` y de los handlers de `bindTrainEvents` se prueban sin red.
public struct DiaEnCurso: Sendable, Equatable {
    public var dia: Dia
    /// `DATA.rutina.semana_actual || 1`
    public var semana: Int
    /// Sin rutina real (demo): no se escribe nada.
    public var demo: Bool
    public var sesionId: String?
    /// La sesión del día está cerrada (`finalizada_en`): el día cuenta como hecho.
    public var diaFinalizado: Bool
    /// Por id del LUGAR (`slug-d<n>-<i>`).
    public var ejercicios: [String: EjercicioEnSesion]
    public var estados: [String: String] = [:]
    public var meta: [String: MetaEstado] = [:]
    /// La card abierta.
    public var expandido: String?
    /// El historial por clave del ejercicio efectivo, guardado por lugar. Sin entrada = sin pedir (o falló la red).
    public var historial: [String: [RegistroHistorico]] = [:]
    /// Las sustituciones, en el formato de la web (ver `SustitucionesEntreno`).
    public var sustituciones: [String: JSONValue] = [:]
    public var zona: TimeZone

    public struct MetaEstado: Equatable, Sendable {
        public var seriesCompletadas: Int
        public var manual: Bool
        public init(seriesCompletadas: Int, manual: Bool) { self.seriesCompletadas = seriesCompletadas; self.manual = manual }
    }

    /// Lo que la app tiene que hacer después de una acción.
    public enum Efecto: Equatable, Sendable {
        /// Una escritura a la cola (`carga` o `estado`).
        case encolar(kind: String, payload: JSONValue, clave: String)
        /// `startRest(segundos)`
        case iniciarDescanso(segundos: Double)
        /// `stopRest()`
        case detenerDescanso
        /// `ensureSesionIniciada()` sin esperar (la serie entra a la cola ya; la cola resuelve la sesión al mandar).
        case asegurarSesion
        /// `loadHistorico(exId)`
        case pedirHistorial(String)
        /// `marcarLeidosEjercicio(exId)`
        case marcarLeidos(String)
        /// Guardar las sustituciones en disco.
        case guardarSustituciones
        /// Se reabrió el día cerrado: se borra la marca local de "cerrado".
        case reabrioDia
        /// Todos los ejercicios en un estado terminal: "🎉 ¡Día completado!" (medio segundo después, una sola vez).
        case diaCompleto
    }

    public init(dia: Dia, semana: Int, demo: Bool = false, sesionId: String? = nil, diaFinalizado: Bool = false,
                estados: [String: String] = [:], zona: TimeZone = .current) {
        self.dia = dia; self.semana = semana; self.demo = demo; self.sesionId = sesionId; self.diaFinalizado = diaFinalizado
        self.estados = estados; self.zona = zona
        ejercicios = Self.armar(dia, semana: semana, estados: estados)
    }

    /// `buildSession`: tantas series vacías como pide la semana, el estado que se conozca y la primera variante.
    public static func armar(_ dia: Dia, semana: Int, estados: [String: String]) -> [String: EjercicioEnSesion] {
        var s: [String: EjercicioEnSesion] = [:]
        for ex in dia.bloques.flatMap(\.ejercicios) {
            let n = max(0, Progresiones.pauta(ex, semana: semana).series ?? 0)
            s[ex.id] = EjercicioEnSesion(series: Array(repeating: SerieLocal(), count: n), completo: false,
                                         estado: JS.verdadero(estados[ex.id]) ?? "pendiente",
                                         variante: ReglasEjercicio.variantes(ex.nombre)?.opciones.first)
        }
        return s
    }

    // MARK: - Lecturas

    /// Los ejercicios del día, en orden (`DATA.dia.bloques.flatMap(b => b.ejercicios)`).
    public var lista: [Ejercicio] { dia.bloques.flatMap(\.ejercicios) }

    /// El ejercicio del PLAN en ese lugar (el primero con ese id).
    public func ejercicio(_ id: String) -> Ejercicio? { lista.first { $0.id == id } }

    /// `getExStatus`
    public func estado(_ id: String) -> String {
        JS.verdadero(ejercicios[id]?.estado) ?? JS.verdadero(estados[id]) ?? "pendiente"
    }

    /// El ejercicio que se hace en el lugar: el sustituto, si hay; si no, el del plan. Es el nombre que se registra.
    public func nombreEfectivo(_ id: String) -> String? {
        SustitucionesEntreno.aplicada(sustituciones[id])?.nombre ?? ejercicio(id)?.nombre
    }

    /// El selector de agarre o nivel que muestra la tarjeta: el del ejercicio que se hace, no el del plan. Desvío a
    /// propósito de la web (revisión del 21-oct): ahí el agarre del plan se grababa en las notas y filtraba el historial
    /// también con un sustituto sin ese selector (la extensión en polea con Soga → fondos: «Fondos» con notas «Soga»).
    public func variantesVisibles(_ id: String) -> VariantesEjercicio? { ReglasEjercicio.variantes(nombreEfectivo(id)) }

    /// `_varianteActiva`: la elegida y si es la default (las filas viejas sin nota cuentan solo para esa). Con el lugar
    /// sustituido por un ejercicio sin ese selector, el agarre del plan no filtra su historial (ver `variantesVisibles`).
    public func varianteActiva(_ id: String) -> (variante: String?, esDefault: Bool) {
        guard let v = JS.verdadero(ejercicios[id]?.variante) else { return (nil, false) }
        let ops = variantesVisibles(id)?.opciones
        if ops == nil, SustitucionesEntreno.aplicada(sustituciones[id]) != nil { return (nil, false) }
        return (v, ops != nil && JS.iguales(ops?.first, v))
    }

    public func pauta(_ id: String) -> Pauta? { ejercicio(id).map { Progresiones.pauta($0, semana: semana) } }

    /// `suggestedKg`
    public func kgUltimaVez(_ id: String, _ idx: Int) -> String {
        let (v, d) = varianteActiva(id)
        // `if (ex && !exNoKg(ex)) return ''`: sin el ejercicio, el 0 se devuelve.
        let sinKgPlan = ejercicio(id).map(ReglasEjercicio.sinKg) ?? true
        return HistorialEntreno.kgSugerido(historial[id] ?? [], indice: idx, variante: v, esDefault: d, sinKgPlan: sinKgPlan, zona: zona)
    }

    /// `suggestedReps`
    public func repsUltimaVez(_ id: String, _ idx: Int) -> String {
        let (v, d) = varianteActiva(id)
        return HistorialEntreno.repsSugeridas(historial[id] ?? [], indice: idx, variante: v, esDefault: d, zona: zona)
    }

    /// `kgHeredable`, pero solo de las series registradas con el mismo ejercicio que esta: el que se hace ahora o, si se
    /// corrige con el lápiz una serie registrada con otro, ese. Desvío a propósito de la web (revisión del 21-oct): al
    /// cambiar de movimiento a mitad del ejercicio (2 series de extensión en polea a 30 kg y después fondos), la serie 3
    /// heredaba los 30 kg de la polea y se grababa como fondos. Sin nombre registrado (una serie de antes de esto) cuenta
    /// como del que se hace ahora.
    public func kgHeredable(_ id: String, _ idx: Int) -> String {
        let series = ejercicios[id]?.series ?? []
        let actual = nombreEfectivo(id)
        func clave(_ s: SerieLocal) -> String { ClaveEjercicio.de(JS.verdadero(s.nombreRegistrado) ?? actual) }
        let esta = idx >= 0 && idx < series.count ? clave(series[idx]) : ClaveEjercicio.de(actual)
        return HistorialEntreno.kgHeredable(series.map { clave($0) == esta ? $0 : SerieLocal() }, indice: idx)
    }

    /// La serie es del ejercicio que se hace ahora: sin nombre registrado (no se sabe con cuál se hizo) o con el mismo.
    func esDelEjercicioActual(_ id: String, _ s: SerieLocal) -> Bool {
        JS.verdadero(s.nombreRegistrado).map { ClaveEjercicio.de($0) == ClaveEjercicio.de(nombreEfectivo(id)) } ?? true
    }

    /// "🏆 Récord a superar" (`lastSessionStr`); nil es "Primera vez con este ejercicio".
    public func record(_ id: String) -> String? { HistorialEntreno.record(historial[id] ?? []) }

    /// "📅 Última vez (…)" (`prevSessionStr`).
    public func ultimaVez(_ id: String, ahora: Date) -> UltimaVez? { HistorialEntreno.ultimaVez(historial[id] ?? [], ahora: ahora, zona: zona) }

    /// La fila de una serie (`renderSetRow`). `efectivo` es lo que se muestra (el sustituto, si hay): decide la columna
    /// de kg y las reps del plan; la variante y la regla del 0 salen del ejercicio del plan, como en la web.
    public func fila(_ id: String, _ idx: Int, efectivo: Ejercicio? = nil) -> FilaSerie? {
        guard let e = ejercicios[id], idx >= 0, idx < e.series.count, let plan = ejercicio(id) else { return nil }
        let ef = efectivo ?? plan
        return FilaSerie.armar(e.series[idx], activa: e.series.firstIndex { !$0.confirmada } == idx, sinKg: ReglasEjercicio.sinKg(ef),
                               repsPlan: Progresiones.pauta(ef, semana: semana).reps, kgUltimaVez: kgUltimaVez(id, idx),
                               repsUltimaVez: repsUltimaVez(id, idx), kgHeredable: kgHeredable(id, idx))
    }

    /// `checkIfDayCompleted`
    public var diaCompleto: Bool { EstadosEjercicio.diaCompleto(lista.map(\.id), estado: estado) }

    /// Hechos (en un estado terminal) y total, como el pie y la barra de progreso.
    public var hechos: Int { lista.filter { EstadosEjercicio.terminales.contains(estado($0.id)) }.count }

    /// Series, reps y volumen de lo confirmado hoy.
    public var resumen: ResumenDia {
        var vistos = Set<String>()
        return ResumenDia(lista.compactMap { vistos.insert($0.id).inserted ? ejercicios[$0.id] : nil })
    }

    /// Los ejercicios sin un estado terminal.
    public var cantidadPendientes: Int { lista.filter { !EstadosEjercicio.terminales.contains(estado($0.id)) }.count }

    /// Para el modal de cierre anticipado: hasta 3 pendientes (con el nombre del plan) y "y N más…".
    public var pendientes: [String] {
        let p = lista.filter { !EstadosEjercicio.terminales.contains(estado($0.id)) }.map(\.nombre)
        return p.count > 3 ? Array(p.prefix(3)) + ["y \(p.count - 3) más…"] : p
    }

    /// "Quedan 5 ejercicios sin completar:" (nil sin pendientes).
    public var avisoPendientes: String? {
        let n = cantidadPendientes
        return n > 0 ? "Quedan \(n) ejercicio\(n > 1 ? "s" : "") sin completar:" : nil
    }

    // MARK: - Acciones

    /// Lo que el cliente ya contestó en esta confirmación (nil = todavía no se le preguntó).
    public struct Respuestas: Equatable, Sendable {
        /// "Este día ya lo cerraste": "Reabrir día".
        public var reabrir: Bool?
        /// "¿Está bien cargado?": "Sí, registrar".
        public var registrarIgual: Bool?
        public init(reabrir: Bool? = nil, registrarIgual: Bool? = nil) { self.reabrir = reabrir; self.registrarIgual = registrarIgual }
    }

    /// Un paso de una acción que puede tener que preguntar: los efectos hasta acá y, si hace falta, la pregunta. Se
    /// vuelve a llamar con la respuesta (así nada queda esperando al cliente con el día "abierto" para escribir).
    public struct Paso: Equatable, Sendable {
        public enum Motivo: Equatable, Sendable { case reabrir, registrarIgual }
        public var efectos: [Efecto] = []
        public var pregunta: Pregunta?
        public var motivo: Motivo?
        public init(efectos: [Efecto] = [], pregunta: Pregunta? = nil, motivo: Motivo? = nil) {
            self.efectos = efectos; self.pregunta = pregunta; self.motivo = motivo
        }
    }

    /// `confirmarSerie` (SER-01/03/05): con el día cerrado pregunta si se reabre; sin editar es "lo de la última vez";
    /// lo imposible se rechaza y lo raro se pregunta; confirmada, entra a la cola YA y arranca el descanso (salvo el
    /// calentamiento). Con la última serie el ejercicio pasa a completo y se abre el siguiente pendiente (ENT-17).
    /// Si devuelve una pregunta, se vuelve a llamar con la respuesta en `respuestas`.
    /// `efectivo` es lo que se muestra (el sustituto, si hay): de ahí sale si la serie lleva kg, como en la fila. La web
    /// usa el del plan y con un sustituto de otra clase (Crunch → Crunch en polea) borraba el kg o no dejaba registrar.
    public mutating func confirmarSerie(_ id: String, _ idx: Int, efectivo: Ejercicio? = nil, respuestas r: Respuestas = Respuestas()) -> Paso {
        guard let e = ejercicios[id], idx >= 0, idx < e.series.count, !e.series[idx].confirmada, let ex = ejercicio(id) else { return Paso() }
        var efectos: [Efecto] = []
        if diaFinalizado {
            guard let reabrir = r.reabrir else { return Paso(pregunta: Self.preguntaReabrir, motivo: .reabrir) }
            guard reabrir else { return Paso() }
            diaFinalizado = false
            efectos.append(.reabrioDia)
        }
        let sinKg = ReglasEjercicio.sinKg(efectivo ?? ex)
        let prog = Progresiones.pauta(efectivo ?? ex, semana: semana)
        let repsUlt = repsUltimaVez(id, idx)
        let (serie, lista) = ConfirmacionSerie.completar(e.series[idx], sinKg: sinKg, repsPlan: prog.reps, kgUltimaVez: kgUltimaVez(id, idx),
                                                         repsUltimaVez: repsUlt, kgHeredable: kgHeredable(id, idx))
        ejercicios[id]!.series[idx] = serie
        guard lista else { return Paso(efectos: efectos) }
        switch Verosimilitud.evaluar(reps: serie.reps, kg: serie.kg, sinKg: sinKg, recordKg: HistorialEntreno.recordKg(historial[id] ?? []),
                                     repsUltimaVez: repsUlt, repsPlan: prog.reps) {
        case .ok:
            break
        case .rechazada(let aviso):
            ejercicios[id]!.series[idx].aviso = aviso
            return Paso(efectos: efectos)
        case .preguntar(let p):
            guard let registrar = r.registrarIgual else { return Paso(efectos: efectos, pregunta: p, motivo: .registrarIgual) }
            guard registrar else {
                ejercicios[id]!.series[idx].aviso = ""   // la fila queda marcada, sin texto
                return Paso(efectos: efectos)
            }
        }
        ejercicios[id]!.series[idx].aviso = nil
        ejercicios[id]!.series[idx].confirmada = true
        // La variante va solo si el ejercicio que se hace muestra ese selector, y la serie anota con qué ejercicio se
        // registró (el `ejercicioNombre` de la carga) para que el kg heredado no cruce de un ejercicio a otro. Una serie ya
        // registrada con OTRO ejercicio (el lápiz después de sustituir) conserva el suyo y su variante: se corrige lo que
        // se hizo. Desvíos a propósito de la web (revisión del 21-oct; ver `variantesVisibles`, `kgHeredable` y
        // `EscriturasEntreno.nombre`).
        if esDelEjercicioActual(id, ejercicios[id]!.series[idx]) {
            ejercicios[id]!.series[idx].varianteRegistrada = variantesVisibles(id) == nil ? nil : JS.verdadero(ejercicios[id]!.variante)
        }
        ejercicios[id]!.series[idx].nombreRegistrado = EscriturasEntreno.nombre(
            sustituto: SustitucionesEntreno.aplicada(sustituciones[id])?.nombre, serie: ejercicios[id]!.series[idx], plan: ex.nombre)
        efectos.append(.asegurarSesion)
        efectos += escribirSerie(id, idx)
        if ex.tipo != "calentamiento" {
            efectos.append(.iniciarDescanso(segundos: Double(ex.descansoSegundos ?? NormalizacionRutina.descansoPorDefecto)))
        }
        if ejercicios[id]!.series.allSatisfy(\.confirmada) && estado(id) == "pendiente" {
            efectos += cambiarEstado(id, "completo", manual: false)
            ejercicios[id]!.completo = true
            if let sig = siguientePendiente(id) {
                expandido = sig
                // El historial se pide ya, para que "Siguiente" abra con el sugerido, el récord y la última vez. Los
                // comentarios NO se marcan leídos: con D13 la card no se abre sola, y el 💬 se iba sin que el cliente
                // lo viera (la web sí los marca porque la abre; lo encontró el agente de Entreno de Android). Se
                // marcan al abrirla (`tocarCard`).
                if historial[sig] == nil { efectos.append(.pedirHistorial(sig)) }
            }
        }
        if !demo && diaCompleto { efectos.append(.diaCompleto) }
        return Paso(efectos: efectos)
    }

    /// "Marcar ejercicio completo": solo con todas las series confirmadas.
    public mutating func marcarCompleto(_ id: String) -> [Efecto] {
        guard let e = ejercicios[id], e.series.allSatisfy(\.confirmada) else { return [] }
        var efectos = cambiarEstado(id, "completo", manual: false)
        ejercicios[id]!.completo = true
        if let sig = siguientePendiente(id) { expandido = sig }
        efectos.append(.detenerDescanso)
        if !demo && diaCompleto { efectos.append(.diaCompleto) }
        return efectos
    }

    /// "Terminé este ejercicio" (SER-15), primera parte: sin series confirmadas hay que preguntar.
    public func preguntaTerminar(_ id: String) -> Pregunta? {
        guard let e = ejercicios[id], !e.series.contains(where: \.confirmada) else { return nil }
        return Self.preguntaTerminarSinDatos
    }

    /// "Terminé este ejercicio", ya contestada la pregunta y con la sesión asegurada (la web la espera antes): queda
    /// `completo` (o `completo_sin_datos` sin series), marcado a mano.
    public mutating func terminar(_ id: String) -> [Efecto] {
        guard let e = ejercicios[id] else { return [] }
        let confirmadas = e.series.filter(\.confirmada).count
        var efectos = cambiarEstado(id, confirmadas > 0 ? "completo" : "completo_sin_datos", manual: true)
        ejercicios[id]!.completo = true
        if let sig = siguientePendiente(id) { expandido = sig }
        efectos.append(.detenerDescanso)
        if !demo && diaCompleto { efectos.append(.diaCompleto) }
        return efectos
    }

    /// "Reabrir ejercicio"
    public mutating func reabrir(_ id: String) -> [Efecto] {
        guard ejercicios[id] != nil else { return [] }
        let efectos = cambiarEstado(id, "pendiente", manual: false)
        ejercicios[id]!.completo = false
        return efectos
    }

    /// El lápiz (SER-06): desconfirma la serie; si el ejercicio estaba completo, vuelve a pendiente.
    public mutating func editarSerie(_ id: String, _ idx: Int) -> [Efecto] {
        guard let e = ejercicios[id], idx >= 0, idx < e.series.count else { return [] }
        ejercicios[id]!.series[idx].confirmada = false
        ejercicios[id]!.completo = false
        return estado(id) == "completo" ? cambiarEstado(id, "pendiente", manual: false) : []
    }

    /// Lo que se tipea en un campo (SER-04): normalizado; borra el aviso de la fila.
    public mutating func escribir(_ id: String, _ idx: Int, campo: String, valor: String) {
        guard let e = ejercicios[id], idx >= 0, idx < e.series.count else { return }
        let v = CamposSerie.normalizar(campo, valor)
        switch campo {
        case "reps": ejercicios[id]!.series[idx].reps = v
        case "kg": ejercicios[id]!.series[idx].kg = v
        default: ejercicios[id]!.series[idx].rir = v
        }
        ejercicios[id]!.series[idx].aviso = nil
    }

    /// La variante (SER-07): vale para las series que se confirmen DESPUÉS.
    public mutating func elegirVariante(_ id: String, _ v: String) {
        guard ejercicios[id] != nil else { return }
        ejercicios[id]!.variante = v
    }

    /// El RIR 0-5 (SER-02): si la serie ya estaba confirmada, se vuelve a mandar (la RPC es upsert).
    public mutating func elegirRIR(_ id: String, _ idx: Int, _ v: String) -> [Efecto] {
        guard let e = ejercicios[id], idx >= 0, idx < e.series.count else { return [] }
        ejercicios[id]!.series[idx].rir = v
        return e.series[idx].confirmada ? escribirSerie(id, idx) : []
    }

    /// Abrir o cerrar la card: al abrir se pide el historial (si no está) y se marcan leídos los comentarios (SES-08).
    public mutating func tocarCard(_ id: String) -> [Efecto] {
        let estaba = expandido == id
        expandido = estaba ? nil : id
        guard !estaba else { return [] }
        var efectos: [Efecto] = []
        if historial[id] == nil { efectos.append(.pedirHistorial(id)) }
        efectos.append(.marcarLeidos(id))
        return efectos
    }

    /// Sustituir (SER-11/13): el lugar pasa a ser OTRO ejercicio, con su historial.
    public mutating func sustituir(_ id: String, por sub: SustitutoEjercicio, efectivo: EjercicioEfectivo, fijado: Bool) -> [Efecto] {
        sustituciones[id] = SustitucionesEntreno.nueva(sub, original: efectivo, fijado: fijado, semana: semana, diaId: dia.id ?? "")
        historial[id] = nil
        return [.guardarSustituciones, .pedirHistorial(id)]
    }

    /// "Volver a …": el lugar vuelve al original, y su historial también.
    public mutating func revertir(_ id: String) -> [Efecto] {
        sustituciones[id] = nil
        historial[id] = nil
        return [.guardarSustituciones, .pedirHistorial(id)]
    }

    // MARK: - Restaurar (lo que trae el servidor)

    /// `loadExerciseStates`
    public mutating func aplicarEstados(_ filas: [EstadoEjercicio]) {
        for f in filas {
            estados[f.ejercicioId] = f.status
            meta[f.ejercicioId] = MetaEstado(seriesCompletadas: f.seriesCompletadas ?? 0, manual: f.marcadoManualmente)
            guard ejercicios[f.ejercicioId] != nil else { continue }
            ejercicios[f.ejercicioId]!.estado = f.status
            if f.status == "completo" || f.status == "completo_sin_datos" { ejercicios[f.ejercicioId]!.completo = true }
        }
    }

    /// `loadRegistrosCarga`: las series guardadas, sin pisar las que ya se confirmaron en el teléfono. La variante
    /// vuelve de `notas` (SER-07) y la serie recuerda con qué nombre y variante se registró.
    public mutating func aplicarRegistros(_ filas: [RegistroSesion]) {
        for r in filas {
            guard var e = ejercicios[r.ejercicioId] else { continue }
            let i = r.serie - 1
            guard i >= 0, i < e.series.count, !e.series[i].confirmada else { continue }
            e.series[i].kg = r.pesoKg.map(JS.texto) ?? ""
            e.series[i].reps = r.reps.map(String.init) ?? ""
            e.series[i].rir = r.rir.map(String.init) ?? ""
            e.series[i].confirmada = true
            e.series[i].nombreRegistrado = JS.verdadero(r.ejercicioNombre)
            if let n = JS.verdadero(r.notas), let ex = ejercicio(r.ejercicioId), ReglasEjercicio.variantes(ex.nombre) != nil { e.variante = n }
            e.series[i].varianteRegistrada = JS.verdadero(r.notas)
            ejercicios[r.ejercicioId] = e
        }
    }

    // MARK: - Internas

    /// `setExStatus` + `writeExerciseStatus`.
    mutating func cambiarEstado(_ id: String, _ status: String, manual: Bool) -> [Efecto] {
        estados[id] = status
        if ejercicios[id] != nil { ejercicios[id]!.estado = status }
        guard !demo else { return [] }
        let objetivo = ejercicio(id).flatMap { Progresiones.pauta($0, semana: semana).series } ?? 0
        let d = dia.id ?? ""
        return [.encolar(kind: "estado",
                         payload: EscriturasEntreno.estado(sesionId: sesionId, semana: semana, dia: d, ejercicio: id, seriesObjetivo: objetivo,
                                                           status: status, manual: manual),
                         clave: EscriturasEntreno.claveEstado(dia: d, ejercicio: id, semana: semana))]
    }

    /// `writeSet`
    func escribirSerie(_ id: String, _ idx: Int) -> [Efecto] {
        guard !demo, let ex = ejercicio(id), let e = ejercicios[id], idx < e.series.count else { return [] }
        let s = e.series[idx]
        let nombre = EscriturasEntreno.nombre(sustituto: SustitucionesEntreno.aplicada(sustituciones[id])?.nombre, serie: s, plan: ex.nombre)
        // La variante del ejercicio solo completa una serie de ESTE ejercicio y con el selector a la vista: una de otro
        // (registrada antes de sustituir o de volver) va con la suya o sin ninguna.
        let variante = esDelEjercicioActual(id, s) && variantesVisibles(id) != nil ? e.variante : nil
        let d = dia.id ?? ""
        return [.encolar(kind: "carga",
                         payload: EscriturasEntreno.carga(sesionId: sesionId, dia: d, semana: semana, ejercicio: id, indice: idx, serie: s,
                                                          nombre: nombre, varianteEjercicio: variante),
                         clave: EscriturasEntreno.claveCarga(dia: d, ejercicio: id, indice: idx, semana: semana))]
    }

    func siguientePendiente(_ id: String) -> String? {
        EstadosEjercicio.siguientePendiente(lista.map(\.id), despuesDe: id, estado: estado)
    }

    public static let preguntaReabrir = Pregunta(titulo: "Este día ya lo cerraste",
                                                 cuerpo: "Lo marcaste como terminado. ¿Querés reabrirlo para seguir cargando series?",
                                                 confirmar: "Reabrir día", cancelar: "Dejarlo cerrado")
    public static let preguntaTerminarSinDatos = Pregunta(titulo: "Terminaste sin cargar datos",
                                                          cuerpo: "No confirmaste ninguna serie. ¿Querés marcar este ejercicio como terminado de todas formas?",
                                                          confirmar: "Sí, terminé", cancelar: "Volver")
}
