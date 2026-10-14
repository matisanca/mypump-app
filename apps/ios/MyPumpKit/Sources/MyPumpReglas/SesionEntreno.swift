import Foundation
import MyPumpModelos

// Entreno, lo que es de la sesión: el cronómetro con el tope de 6 h (SES-03), el descanso como fecha de fin persistida
// (SES-04), los comentarios por ejercicio (SES-08) y la poda de sustituciones (SER-12). Port de cliente.html; lo
// verifican los vectores de scripts/nativa/vectores-entreno.mjs. Los tiempos van en milisegundos desde 1970, como
// `Date.now()`.

public enum TiempoEntreno {
    /// `SESION_MAX_H`: más que esto no es un entrenamiento largo, es un día que quedó sin cerrar.
    public static let sesionMaxH = 6.0

    /// `fmtTime(s)`: "m:ss" (sin horas; 3600 s son "60:00").
    public static func fmtTiempo(_ s: Double) -> String {
        let t = max(0, s)
        let seg = JS.texto(t.truncatingRemainder(dividingBy: 60))
        return "\(JS.texto((t / 60).rounded(.down))):\(seg.count < 2 ? "0" + seg : seg)"
    }

    /// `fmtCrono(ms)`: "m:ss" o "h:mm:ss".
    public static func fmtCrono(_ ms: Double) -> String {
        let s = max(0, (ms / 1000).rounded(.down))
        let h = (s / 3600).rounded(.down), m = (s.truncatingRemainder(dividingBy: 3600) / 60).rounded(.down), ss = s.truncatingRemainder(dividingBy: 60)
        let p = { (n: Double) -> String in let t = JS.texto(n); return t.count < 2 ? "0" + t : t }
        return h > 0 ? "\(JS.texto(h)):\(p(m)):\(p(ss))" : "\(JS.texto(m)):\(p(ss))"
    }

    /// `minutosSesion` (SES-03): los minutos de la sesión, o nil si el número no es creíble (más de 6 h, o negativo).
    /// Lo que se GUARDA y lo que se MUESTRA salen de acá.
    public static func minutosSesion(inicio: Double?, ahora: Double) -> Int? {
        guard let inicio, inicio != 0 else { return nil }
        let seg = jsRound((ahora - inicio) / 1000)
        guard seg >= 0 && seg <= sesionMaxH * 3600 else { return nil }
        return Int(jsRound(seg / 60))
    }

    /// El cronómetro de arriba del día (`renderTrain`).
    public enum Cronometro: Equatable, Sendable {
        /// "▶ Empezar entrenamiento"
        case empezar
        /// "EN CURSO 12:34" (con "⏱ arrancó con tu primera serie" si no se tocó Empezar).
        case enCurso(String, porBoton: Bool)
        /// Más de 6 h: "SIN CERRAR · Empezar de nuevo" (la duración que se guarda va null).
        case sinCerrar
    }

    /// nil cuando el día está cerrado o todo hecho (ahí está la card de cierre).
    public static func cronometro(inicio: Double?, ahora: Double, porBoton: Bool, diaFinalizado: Bool, todoHecho: Bool) -> Cronometro? {
        guard !diaFinalizado && !todoHecho else { return nil }
        guard let inicio, inicio != 0 else { return .empezar }
        if ahora - inicio > sesionMaxH * 3_600_000 { return .sinCerrar }
        return .enCurso(fmtCrono(ahora - inicio), porBoton: porBoton)
    }
}

/// El descanso entre series (SES-04): anclado al reloj (fin y cierre), así una app en segundo plano no se atrasa. Se
/// guarda en disco igual que la web guardaba `mypump_rest_<TOKEN>`.
public struct Descanso: Equatable, Sendable {
    /// `endsAt` (ms)
    public var fin: Double
    /// `target` (s): lo que se pidió, más lo que se sumó con +15.
    public var objetivo: Double
    /// `autoCloseAt` (ms): 2 s después del fin se cierra la barra.
    public var cierre: Double
    /// `doneFired`: ya sonó.
    public var terminado: Bool

    /// Lo que va a disco: `{endsAt, target, autoCloseAt}`.
    public struct Guardado: Codable, Equatable, Sendable {
        public var endsAt: Double
        public var target: Double
        public var autoCloseAt: Double?
        public init(endsAt: Double, target: Double, autoCloseAt: Double?) { self.endsAt = endsAt; self.target = target; self.autoCloseAt = autoCloseAt }
    }

    /// `startRest(seconds)`. El 90 por defecto ya lo puso `normalizarRutina` en `descanso_segundos`.
    public static func iniciar(segundos: Double, ahora: Double) -> Descanso {
        Descanso(fin: ahora + segundos * 1000, objetivo: segundos, cierre: ahora + (segundos + 2) * 1000, terminado: false)
    }

    /// −15 / +15: corre el fin y el cierre; solo lo que se suma agranda el objetivo. Si el fin vuelve a quedar
    /// adelante, puede sonar de nuevo.
    public mutating func ajustar(segundos: Double, ahora: Double) {
        fin += segundos * 1000
        cierre += segundos * 1000
        if segundos > 0 { objetivo += segundos }
        if fin > ahora { terminado = false }
    }

    /// `restTick`: `termino` la primera vez que se cruza el fin (sonido y vibración); `cerrar` al pasar el cierre.
    public mutating func tick(ahora: Double) -> (termino: Bool, cerrar: Bool) {
        var termino = false
        if ahora >= fin && !terminado {
            terminado = true
            termino = true
        }
        return (termino, ahora >= cierre)
    }

    /// `restoreRest`: lo guardado, si todavía no se cerró. Si ya pasó el fin, no vuelve a sonar.
    public static func restaurar(_ g: Guardado?, ahora: Double) -> Descanso? {
        guard let g, let cierre = g.autoCloseAt, cierre != 0, ahora < cierre else { return nil }
        return Descanso(fin: g.endsAt, objetivo: g.target, cierre: cierre, terminado: ahora >= g.endsAt)
    }

    public var guardado: Guardado { Guardado(endsAt: fin, target: objetivo, autoCloseAt: cierre) }

    /// Segundos que faltan, redondeados hacia arriba.
    public func restante(ahora: Double) -> Double { max(0, ((fin - ahora) / 1000).rounded(.up)) }

    /// "1:29"
    public func texto(ahora: Double) -> String { TiempoEntreno.fmtTiempo(restante(ahora: ahora)) }

    /// "/ 1:30 objetivo"
    public var textoObjetivo: String { "/ \(TiempoEntreno.fmtTiempo(objetivo)) objetivo" }

    /// 0-100 de la barra.
    public func porcentaje(ahora: Double) -> Double {
        max(0, min(100, ((objetivo - restante(ahora: ahora)) / objetivo) * 100))
    }
}

/// La barra del descanso: lo que hacen `startRest`, `restTick`, `stopRest`, `restoreRest` y los botones −15 / +15 /
/// Saltar de la web, con lo que queda en disco (`guardado`). Sin sonido ni vibración: eso es de la app.
public struct BarraDescanso: Equatable, Sendable {
    public private(set) var descanso: Descanso?
    /// Lo que está en disco (`mypump_rest_<TOKEN>`); nil es "nada guardado".
    public private(set) var guardado: Descanso.Guardado?
    public private(set) var visible = false
    /// Terminó (la barra verde).
    public private(set) var listo = false
    /// "1:29"
    public private(set) var texto = ""
    /// "/ 1:30 objetivo"
    public private(set) var textoObjetivo = ""
    /// 0-100; nil hasta que se pinta por primera vez.
    public private(set) var porcentaje: Double?

    public init(guardado: Descanso.Guardado? = nil) { self.guardado = guardado }

    /// `startRest`
    public mutating func iniciar(segundos: Double, ahora: Double) {
        detener()
        let d = Descanso.iniciar(segundos: segundos, ahora: ahora)
        descanso = d
        visible = true
        listo = false
        pintar(ahora)
        guardado = d.guardado
    }

    /// `restTick`: devuelve true la vez que termina (la app suena y vibra). A los 2 s del fin se cierra.
    @discardableResult
    public mutating func tick(ahora: Double) -> Bool {
        guard var d = descanso else { return false }
        let (termino, cerrar) = d.tick(ahora: ahora)
        descanso = d
        if termino { listo = true }
        if cerrar { detener(); return termino }
        pintar(ahora)
        return termino
    }

    /// Los botones: "-15", "15" o "skip".
    public mutating func ajustar(_ v: String, ahora: Double) {
        guard var d = descanso else { return }
        if v == "skip" { detener(); return }
        d.ajustar(segundos: JS.parseInt(v, base10: false) ?? .nan, ahora: ahora)
        descanso = d
        if d.fin > ahora { listo = false }
        pintar(ahora)
        guardado = d.guardado
    }

    /// `stopRest`: se va la barra y lo guardado.
    public mutating func detener() {
        descanso = nil
        visible = false
        listo = false
        guardado = nil
    }

    /// `restoreRest`: lo guardado vuelve si todavía no se cerró. Como en la web, restaurar borra lo guardado (el
    /// `stopRest` de adentro lo limpia y no se vuelve a escribir).
    public mutating func restaurar(ahora: Double) {
        guard let g = guardado, let cierre = g.autoCloseAt, cierre != 0 else { return }
        if ahora >= cierre { guardado = nil; return }
        detener()
        guard let d = Descanso.restaurar(g, ahora: ahora) else { return }
        descanso = d
        visible = true
        listo = d.terminado
        pintar(ahora)
    }

    /// `updateRestUI`
    private mutating func pintar(_ ahora: Double) {
        guard let d = descanso else { return }
        texto = d.texto(ahora: ahora)
        textoObjetivo = d.textoObjetivo
        porcentaje = d.porcentaje(ahora: ahora)
    }
}

/// Los comentarios coach ↔ cliente indexados por `ambito|referencia_id` (los badges y la sección de cada card).
public struct IndiceComentarios: Equatable, Sendable {
    public private(set) var porReferencia: [String: [Comentario]] = [:]
    public private(set) var sinLeer: [String: Int] = [:]

    public init(_ filas: [Comentario] = []) {
        for c in filas {
            let k = Self.clave(c.ambito, c.referenciaId)
            porReferencia[k, default: []].append(c)
            if c.autor == "coach" && c.leidoPorCliente != true { sinLeer[k, default: 0] += 1 }
        }
    }

    /// `_comKey`: `${ambito}|${refId || ''}`
    public static func clave(_ ambito: String, _ referencia: String?) -> String { "\(ambito)|\(referencia ?? "")" }

    public func comentarios(ejercicio: String) -> [Comentario] { porReferencia[Self.clave("ejercicio", ejercicio)] ?? [] }
    public func sinLeer(ejercicio: String) -> Int { sinLeer[Self.clave("ejercicio", ejercicio)] ?? 0 }

    /// `totalUnreadComentarios`: el badge de Entreno, SIN el chat (`general|`), que tiene el suyo.
    public var totalEntreno: Int { sinLeer.filter { !$0.key.hasPrefix("general|") }.values.reduce(0, +) }

    /// "9+" desde 10.
    public static func badge(_ n: Int) -> String? { n > 0 ? (n > 9 ? "9+" : String(n)) : nil }

    /// `getUnreadDia`: el 💬 del selector de días.
    public func sinLeer(dia: Dia) -> Int { dia.bloques.flatMap(\.ejercicios).reduce(0) { $0 + sinLeer(ejercicio: $1.id) } }

    /// `marcarLeidosEjercicio`, optimista: el badge se va ya; la base se avisa aparte.
    public mutating func marcarLeidos(ejercicio: String) {
        let k = Self.clave("ejercicio", ejercicio)
        sinLeer[k] = 0
        porReferencia[k] = porReferencia[k]?.map { c in
            guard c.autor == "coach" else { return c }
            return c.leido()
        }
    }

    /// `fmtComentarioFecha`: "12-oct · 06:05 p. m."
    public static func fecha(_ iso: String, zona: TimeZone) -> String {
        guard let d = FechaJS.leer(iso) else { return "Invalid Date · Invalid Date" }
        return "\(FechaJS.diaMes(d, zona: zona)) · \(FechaJS.horaMinutos(d, zona: zona))"
    }
}

extension Comentario {
    /// El mismo comentario, leído por el cliente.
    func leido() -> Comentario {
        var o: [String: JSONValue] = [
            "id": .texto(id), "ambito": .texto(ambito), "autor": .texto(autor), "contenido": .texto(contenido),
            "leido_por_cliente": .bool(true), "created_at": .texto(createdAt),
        ]
        if let r = referenciaId { o["referencia_id"] = .texto(r) }
        if let n = referenciaNombre { o["referencia_nombre"] = .texto(n) }
        return (try? JSONDecoder().decode(Comentario.self, from: JSONEncoder().encode(JSONValue.objeto(o)))) ?? self
    }
}

/// Las sustituciones de ejercicio que eligió el cliente (`STATE.exerciseSwaps`), con el MISMO formato que la web
/// (`mypump_exercise_swaps_<RUTINA>`): `exId → {original:{slug,nombre,images}, current:{slug,nombre,equipment,images},
/// fijado, semana, diaId}`. Se guardan crudas (JSON) para devolverlas igual y para que la migración del almacenamiento
/// viejo las copie tal cual.
public enum SustitucionesEntreno {
    /// Al cargar: las guardadas antes del flag "fijado" se tratan como FIJADAS (se eligieron cuando el swap era
    /// permanente). Solo si la clave falta: un `null` explícito es "no fijada", como en la web.
    public static func compat(_ m: [String: JSONValue]) -> [String: JSONValue] {
        m.mapValues { v in
            guard case .objeto(var o) = v, o["fijado"] == nil else { return v }
            o["fijado"] = .bool(true)
            return .objeto(o)
        }
    }

    /// `pruneExerciseSwaps` (SER-12): las NO fijadas valen solo por la sesión de su día: se borran si son de otra
    /// semana o si su día ya se cerró. Al CERRAR el día se conservan las del día abierto (para reabrir y corregir).
    public static func podar(_ m: [String: JSONValue], semanaActual: Int, diasCompletados: Set<String>, diaActual: String?,
                             diaFinalizado: Bool, conservarDiaActual: Bool) -> (quedan: [String: JSONValue], borradas: [String]) {
        var quedan = m
        var borradas: [String] = []
        let conservar = conservarDiaActual ? JS.verdadero(diaActual) : nil
        for (exId, s) in m {
            guard case .objeto(let o) = s, !AnclajeSwaps.esVerdadero(o["fijado"] ?? .null) else { continue }
            let diaId = o["diaId"]
            if let conservar, case .texto(let d)? = diaId, JS.iguales(d, conservar) { continue }
            let semana = o["semana"] ?? .null
            let otraSemana = semana != .null && semana != .numero(Double(semanaActual))
            var diaCerrado = false
            if case .texto(let d)? = diaId, !d.isEmpty, diasCompletados.contains(d) { diaCerrado = true }
            if case .texto(let d)? = diaId, JS.iguales(d, diaActual), diaFinalizado { diaCerrado = true }
            if otraSemana || diaCerrado {
                quedan[exId] = nil
                borradas.append(exId)
            }
        }
        return (quedan, borradas)
    }

    /// Lo que guarda `confirmExSwap` al elegir un sustituto.
    public static func nueva(_ sub: SustitutoEjercicio, original ef: EjercicioEfectivo, fijado: Bool, semana: Int, diaId: String) -> JSONValue {
        func imagenes(_ i: Imagenes?) -> JSONValue {
            guard let i else { return .null }
            var o: [String: JSONValue] = ["eccentric": i.eccentric.map(JSONValue.texto) ?? .null, "concentric": i.concentric.map(JSONValue.texto) ?? .null]
            if let m = i.matchedSlug { o["_matched_slug"] = .texto(m) }
            return .objeto(o)
        }
        return .objeto([
            "original": .objeto([
                "slug": JS.verdadero(ef.slugOriginal).map(JSONValue.texto) ?? .null,
                "nombre": .texto(JS.verdadero(ef.nombreOriginal) ?? ef.ejercicio.nombre),
                "images": imagenes(ef.imagenesOriginales),
            ]),
            "current": .objeto([
                "slug": sub.slug.map(JSONValue.texto) ?? .null, "nombre": .texto(sub.nombre),
                "equipment": sub.equipoCrudo.map(JSONValue.texto) ?? .null, "images": imagenes(sub.imagenes),
            ]),
            "fijado": .bool(fijado),
            "semana": .numero(Double(semana)),
            "diaId": .texto(diaId),
        ])
    }

    /// El `current` de lo guardado, como lo usa `getEffectiveEx`.
    public static func aplicada(_ v: JSONValue?) -> SustitucionAplicada? {
        guard let v, case .objeto(let o) = v, case .objeto(let c)? = o["current"] else { return nil }
        let imagenes = c["images"].flatMap { try? JSONDecoder().decode(Imagenes.self, from: JSONEncoder().encode($0)) }
        return SustitucionAplicada(slug: c["slug"]?.comoTexto, nombre: c["nombre"]?.comoTexto ?? "", equipo: c["equipment"]?.comoTexto,
                                   imagenes: imagenes, fijado: AnclajeSwaps.esVerdadero(o["fijado"] ?? .null))
    }

    /// La búsqueda del modal: `name.toLowerCase().includes(query.toLowerCase().trim())`.
    public static func filtrar(_ subs: [SustitutoEjercicio], _ consulta: String) -> [SustitutoEjercicio] {
        guard !consulta.isEmpty else { return subs }
        let q = Array(JS.trim(JS.minusculas(consulta)).utf16)
        return subs.filter { s in
            let n = Array(JS.minusculas(s.nombre).utf16)
            guard !q.isEmpty else { return true }
            guard q.count <= n.count else { return false }
            return (0...(n.count - q.count)).contains { n[$0..<($0 + q.count)].elementsEqual(q) }
        }
    }
}
