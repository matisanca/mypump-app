import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

// MARK: Lo que devuelve `mypump_presion_get` (todo opcional: un campo que falta o que no se entiende vale lo de fábrica)

public struct SeriePresion: Equatable, Sendable {
    public let id: String?
    public let motivo: String?
    /// "estandar" o "bajo_efecto".
    public let tipo: String
    public let estado: String?
    public let tomasObjetivo: Int
    public let fechaInicio: String?
    public let fechaLimite: String?
    public let brazo: String?
    /// nil, "acostado_parado" o "sentado_parado": falta hacerla.
    public internal(set) var ortostatica: String?
    public internal(set) var compararBrazos: Bool
    public let medidaPedida: Bool
    public internal(set) var dias: [String]
    public internal(set) var faltan: Int

    init?(_ j: JSONValue?) {
        guard let j, case .objeto = j else { return nil }
        id = j["id"]?.comoTexto
        motivo = j["motivo"]?.comoTexto
        tipo = j["tipo"]?.comoTexto == "bajo_efecto" ? "bajo_efecto" : "estandar"
        estado = j["estado"]?.comoTexto
        if let n = j["tomas_objetivo"]?.comoNumero, n >= 1, n <= 30 { tomasObjetivo = Int(n) } else { tomasObjetivo = 3 }
        fechaInicio = j["fecha_inicio"]?.comoTexto
        fechaLimite = j["fecha_limite"]?.comoTexto
        brazo = j["brazo"]?.comoTexto
        let o = j["ortostatica"]?.comoTexto
        ortostatica = o == "acostado_parado" || o == "sentado_parado" ? o : nil
        compararBrazos = j["comparar_brazos"] == .bool(true)
        medidaPedida = j["medida_pedida"] == .bool(true)
        if case .lista(let l)? = j["dias"] { dias = l.compactMap(\.comoTexto) } else { dias = [] }
        if let n = j["faltan"]?.comoNumero, n >= 0, n <= 30 { faltan = Int(n) } else { faltan = max(0, tomasObjetivo - dias.count) }
    }
}

/// Una sesión ya guardada, tal como la anotó el alumno.
public struct SesionPresion: Equatable, Sendable, Identifiable {
    public let id: String
    public let serieId: String?
    public let fecha: String
    public let tipo: String
    public let cuenta: Bool?
    public let tomas: [Presion.Toma]

    init?(_ j: JSONValue) {
        guard let i = j["id"]?.comoTexto, !i.isEmpty else { return nil }
        id = i
        serieId = j["serie_id"]?.comoTexto
        fecha = j["fecha"]?.comoTexto ?? ""
        tipo = j["tipo"]?.comoTexto ?? "estandar"
        if case .bool(let b)? = j["cuenta"] { cuenta = b } else { cuenta = nil }
        if case .lista(let l)? = j["tomas"] { tomas = l.compactMap(Presion.Toma.init).sorted { $0.orden < $1.orden } } else { tomas = [] }
    }
}

public struct PendientePresion: Equatable, Sendable {
    public let sesionId: String
    /// "alta" o "urgencia".
    public let nivel: String
    public let desde: String?

    public init(sesionId: String, nivel: String, desde: String?) { self.sesionId = sesionId; self.nivel = nivel; self.desde = desde }

    init?(_ j: JSONValue?) {
        guard let j, let s = j["sesion_id"]?.comoTexto, !s.isEmpty else { return nil }
        sesionId = s
        nivel = j["nivel"]?.comoTexto == "urgencia" ? "urgencia" : "alta"
        desde = j["desde"]?.comoTexto
    }
}

public struct TensiometroPresion: Equatable, Sendable, Identifiable {
    public var id: String { "\(nombre)-\(codigo ?? "")-\(pais ?? "")" }
    public let nombre: String
    public let codigo: String?
    public let pais: String?
    public let nota: String?
}

/// La lista de aparatos que sirven, por tramo. nil hasta que el equipo la verifique: sin ella no se muestra «Ver cuáles sirven».
public struct TensiometrosPresion: Equatable, Sendable {
    public let version: String?
    public let tramos: [String: [TensiometroPresion]]

    init?(_ j: JSONValue?) {
        guard let j, case .objeto(let t)? = j["tramos"] else { return nil }
        version = j["version"]?.comoTexto ?? j["version"]?.comoNumero.map { String(Int($0)) }
        tramos = t.mapValues { v in
            guard case .lista(let l) = v else { return [] }
            return l.compactMap { a in
                guard let n = a["nombre"]?.comoTexto, !n.isEmpty else { return nil }
                return TensiometroPresion(nombre: n, codigo: a["codigo"]?.comoTexto, pais: a["pais"]?.comoTexto, nota: a["nota"]?.comoTexto)
            }
        }
    }
}

/// `mypump_presion_get` con la sección habilitada. Si no vino `habilitado: true`, nil: no se muestra nada.
public struct EstadoPresion: Equatable, Sendable {
    public let fotos: Bool
    public let hoy: String?
    public let aparato: Presion.Aparato?
    public let circunferenciaBrazoCm: Double?
    public let serie: SeriePresion?
    /// Las últimas, la más nueva primero.
    public let sesiones: [SesionPresion]
    public let pendiente: PendientePresion?
    public let tensiometros: TensiometrosPresion?

    public init?(_ j: JSONValue) {
        guard j["habilitado"] == .bool(true) else { return nil }
        fotos = j["fotos"] == .bool(true)
        hoy = j["hoy"]?.comoTexto
        aparato = Presion.Aparato(j["aparato"])
        if let c = j["circunferencia_brazo_cm"]?.comoNumero, c > 0, c.isFinite { circunferenciaBrazoCm = c } else { circunferenciaBrazoCm = nil }
        serie = SeriePresion(j["serie"])
        if case .lista(let l)? = j["sesiones"] { sesiones = l.compactMap(SesionPresion.init) } else { sesiones = [] }
        pendiente = PendientePresion(j["pendiente"])
        tensiometros = TensiometrosPresion(j["tensiometros"])
    }
}

// MARK: Lo que vive en el teléfono

/// El botón «Marcar un síntoma» y la lista del recordatorio (`mypump_presion_sintoma`).
public struct SintomaPresion: Codable, Equatable, Sendable {
    public var id: String
    public var marcadoEn: String
    public var zonaHoraria: String
    /// "boton" o "recordatorio_180_120".
    public var contexto: String
    public var sesionId: String?
    public var codigos: [String]
    public var sinSintomasEnLista: Bool?
    public var nota: String?
}

/// Un envío de la cola: una sesión entera (la última versión) o un síntoma.
struct EnvioPresion: Codable, Equatable {
    var sesion: Presion.Sesion?
    var textoAlumno: String?
    var sintoma: SintomaPresion?
    /// Cuándo entró a la cola: pasados 30 días sin poder salir, se descarta. nil en lo guardado por una versión anterior.
    var creado: Date?
    /// Una repetición retomada de lo que avisa el servidor: las preguntas previas y el reposo no se saben, viajan en null.
    var retomada: Bool?
    var id: String { sesion?.id ?? sintoma?.id ?? "" }
}

/// La sesión que se está haciendo, con su temporizador: sobrevive a cerrar la app para poder retomar la repetición.
public struct EnCursoPresion: Codable, Equatable, Sendable {
    public var sesion: Presion.Sesion
    /// En qué pantalla quedó. La app pone los nombres.
    public var etapa: String
    /// Índice en `Presion.pasos` (ortostática y comparación de brazos).
    public var paso: Int
    /// La hora en que termina el temporizador que corre. Se guarda la hora, no los segundos que faltan.
    public var finTemporizador: Date?
    public var ultimaTomaEn: Date?
    /// Las respuestas de la lista de alarma de la espera, por código. Lo que no está, no se contestó.
    public var lista: [String: Bool]
    /// Día local en que empezó: al otro día ya no se retoma.
    public var dia: String
    /// Retomada de lo que avisa el servidor (`pendiente`): no se sabe qué contestó antes ni si esperó.
    public var retomada: Bool?
    /// La variante de la ortostática ("acostado_parado" o "sentado_parado"): la serie deja de traerla cuando se guarda la primera toma.
    public var variante: String?

    public init(sesion: Presion.Sesion, etapa: String, paso: Int = 0, finTemporizador: Date? = nil, ultimaTomaEn: Date? = nil, lista: [String: Bool] = [:], dia: String) {
        self.sesion = sesion; self.etapa = etapa; self.paso = paso; self.finTemporizador = finTemporizador
        self.ultimaTomaEn = ultimaTomaEn; self.lista = lista; self.dia = dia
    }
}

struct ColaPresion: Codable, Equatable {
    var envios: [EnvioPresion] = []
    var enCurso: EnCursoPresion?
    static let archivo = "presion-cola.json"
}

/// Presión arterial. Las sesiones y los síntomas se guardan primero en el teléfono y se mandan en orden: sin red, con un 5xx o un
/// 429 quedan y se reintentan (al volver al frente y al abrir la pantalla); un 4xx que no sea 429, o `ok: false`, se descarta y se
/// refresca el estado. El texto de guardia lo decide `Presion.evaluarSesion` acá, sin esperar al servidor. Con la palanca
/// `presion_app` apagada `ModeloApp` no llama a nada de esto: `estado` queda en nil y no se ve ni se pide nada.
///
/// Nada de esta clase toca Entreno ni la rutina: la presión nunca frena el entrenamiento.
@MainActor @Observable
public final class ModeloPresion {
    public enum Resultado: Equatable, Sendable { case ok, sinSenal, error }

    /// nil: apagado, sin el servidor nuevo, o sin red y sin nada guardado. No se muestra nada.
    public private(set) var estado: EstadoPresion?
    private var local = ColaPresion()

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored private let ahora: @Sendable () -> Date
    @ObservationIgnored private var drenando = false
    @ObservationIgnored private var apagado = false

    static let archivoEstado = "presion-estado.json"
    /// Un envío se conserva 30 días (también sin el servidor nuevo: un 404 o PGRST202 no borra la cola).
    static let venceS: TimeInterval = 30 * 24 * 3600

    public init(cliente: ClienteRPC, token: String, disco: Disco?, ahora: @escaping @Sendable () -> Date = { Date() }) {
        self.cliente = cliente; self.token = token; self.disco = disco; self.ahora = ahora
        local = disco?.leer(ColaPresion.self, ColaPresion.archivo) ?? ColaPresion()
        // Lo que lleva más de 30 días sin poder salir ya no se manda.
        let limite = ahora().addingTimeInterval(-Self.venceS)
        let vivos = local.envios.filter { ($0.creado ?? ahora()) >= limite }
        if vivos.count != local.envios.count { local.envios = vivos; guardar() }
        // La repetición se retoma el mismo día: al otro día el servidor ya no la pide.
        if let e = local.enCurso, e.dia != FechaLocal.hoy(ahora()) { local.enCurso = nil; guardar() }
    }

    // MARK: Lo que lee la pantalla

    public var habilitado: Bool { estado != nil }
    public var enCurso: EnCursoPresion? { local.enCurso }
    /// Cuántos envíos esperan señal.
    public var enCola: Int { local.envios.count }
    public var hoy: String { estado?.hoy ?? FechaLocal.hoy(ahora()) }
    /// Esa sesión tiene una versión que todavía no salió: lo que diga el servidor de ella puede estar viejo.
    public func esperaSalir(_ sesionId: String) -> Bool { local.envios.contains { $0.sesion?.id == sesionId } }

    /// La serie con lo que todavía no confirmó el servidor: una toma en la cola que cuenta ya suma su día, y la comparación
    /// de brazos o la ortostática en la cola ya no se vuelven a pedir.
    public var serieVista: SeriePresion? {
        guard var s = estado?.serie else { return nil }
        let base = s.dias.count
        for envio in local.envios {
            guard let c = envio.sesion, c.serieId != nil, c.serieId == s.id else { continue }
            if c.tipo == "comparacion_brazos", c.tomas.count >= 4 { s.compararBrazos = false }
            if c.tipo == "ortostatica", c.tomas.count >= 3 { s.ortostatica = nil }
            guard c.tipo == "estandar" || c.tipo == "bajo_efecto", envio.retomada != true,
                  let dia = c.inicio.flatMap({ Self.iso.date(from: $0) }).map({ FechaLocal.hoy($0) }),
                  !s.dias.contains(dia), s.dias.count < s.tomasObjetivo else { continue }
            let ev = Presion.evaluarSesion(c)
            if s.tipo == "bajo_efecto" ? ev.validaBajoEfecto : ev.cuenta { s.dias.append(dia) }
        }
        s.faltan = max(0, s.faltan - (s.dias.count - base))
        return s
    }
    /// La de hoy ya está hecha (con lo que espera en la cola).
    public var hoyListo: Bool { serieVista?.dias.contains(hoy) == true }

    /// La repetición que falta: la del teléfono si quedó a medias, o la que pide el servidor (salvo que ya esté saliendo de la cola).
    public var pendiente: PendientePresion? {
        if let e = local.enCurso, let id = e.sesion.id, !e.sesion.tomas.isEmpty, e.sesion.tipo != "ortostatica", e.sesion.tipo != "comparacion_brazos",
           let ev = evaluar(), ev.paso == .repetir || ev.paso == .repetirConLista {
            return PendientePresion(sesionId: id, nivel: ev.paso == .repetirConLista ? "urgencia" : "alta", desde: e.sesion.inicio)
        }
        if let p = estado?.pendiente, !esperaSalir(p.sesionId) { return p }
        return nil
    }

    /// La tarjeta de arriba en la primera pestaña (CONTRATO_APP.md, «Fácil de encontrar y súper visible»). nil: no hay tarjeta.
    /// Es una tarjeta más: no frena ni condiciona la rutina.
    public enum Tarjeta: Equatable, Sendable {
        /// Quedó una repetición sin hacer.
        case repetir
        /// Serie abierta y falta el aparato, o medir el brazo para esta serie.
        case preparar
        /// Serie abierta y sin toma válida hoy.
        case toma(hechas: Int, total: Int, faltan: Int)
        /// Serie abierta y la de hoy hecha.
        case hoyListo(hechas: Int, total: Int)
    }
    public var tarjeta: Tarjeta? {
        guard let e = estado else { return nil }
        if pendiente != nil { return .repetir }
        guard let s = serieVista else { return nil }
        let hechas = min(s.tomasObjetivo, max(0, s.tomasObjetivo - s.faltan))
        if e.aparato == nil || !Presion.metodo(e.circunferenciaBrazoCm, e.aparato).admiteTomas || s.medidaPedida { return .preparar }
        if s.dias.contains(hoy) { return .hoyListo(hechas: hechas, total: s.tomasObjetivo) }
        if s.faltan <= 0 { return nil }
        return .toma(hechas: hechas, total: s.tomasObjetivo, faltan: s.faltan)
    }

    /// Las tomas de una sesión guardada, para retomar una repetición que pide el servidor.
    public func sesionGuardada(_ id: String) -> SesionPresion? { estado?.sesiones.first { $0.id == id } }

    // MARK: Servidor

    private var zona: String { TimeZone.current.identifier }

    public func refrescar() async {
        switch await cliente.llamar("mypump_presion_get", ["p_token": .texto(token), "p_zona": .texto(zona)]) {
        case .success(.null):
            estado = nil
        case .success(let j):
            aplicar(j)
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            // Se apaga y no se muestra nada, pero la cola no se toca: lo anotado se conserva 30 días y sale cuando vuelva.
            apagar()
            disco?.borrar(Self.archivoEstado)
        case .failure:
            // Sin red, lo último que se supo: los pasos y la cola siguen vivos.
            if estado == nil, !apagado, let j = disco?.leer(JSONValue.self, Self.archivoEstado), let e = EstadoPresion(j) { estado = e }
        }
    }

    /// El estado que devuelve el servidor (en `get` y en cada escritura).
    private func aplicar(_ j: JSONValue) {
        guard let e = EstadoPresion(j) else { apagar(); disco?.borrar(Self.archivoEstado); return }
        apagado = false
        estado = e
        disco?.guardar(j, Self.archivoEstado)
    }

    public func apagar() { estado = nil; apagado = true }

    private func escribir(_ funcion: String, _ parametros: [String: JSONValue]) async -> Resultado {
        guard estado != nil else { return .error }
        var p = parametros
        p["p_token"] = .texto(token)
        switch await cliente.llamar(funcion, p) {
        case .success(let j):
            guard j["ok"] == .bool(true) else { return .error }
            if let e = j["estado"], e != .null { aplicar(e) } else { await refrescar() }
            return .ok
        case .failure(let e):
            if e.funcionInexistente || e.status == 404 { apagar(); return .error }
            return e.clase == .permanente ? .error : .sinSenal
        }
    }

    /// Cambiar aparato o manguito crea uno nuevo en el servidor (el anterior queda inactivo).
    public func guardarAparato(_ a: Presion.Aparato) async -> Resultado {
        func n(_ x: Double?) -> JSONValue { x.map(JSONValue.numero) ?? .null }
        func t(_ s: String?) -> JSONValue {
            let v = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? .null : .texto(String(v.prefix(120)))
        }
        return await escribir("mypump_presion_aparato", ["p_aparato": .objeto([
            "tipo": t(a.tipo), "marca": t(a.marca), "modelo": t(a.modelo), "modelo_codigo": t(a.modeloCodigo),
            "manguito_min_cm": n(a.manguitoMinCm), "manguito_max_cm": n(a.manguitoMaxCm),
        ])])
    }

    /// La medida del brazo, de 20 a 70 cm con un decimal.
    public func guardarMedida(_ cm: Double) async -> Resultado {
        guard cm >= 20, cm <= 70 else { return .error }
        return await escribir("mypump_presion_medida", ["p_cm": .numero((cm * 10).rounded() / 10), "p_zona": .texto(zona)])
    }

    // MARK: La sesión en curso

    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private func sello(_ d: Date) -> String { Self.iso.string(from: d) }

    /// Empieza una sesión nueva con su id. No manda nada hasta la primera toma.
    @discardableResult
    public func empezar(tipo: String, serieId: String?, brazo: String?, etapa: String, variante: String? = nil) -> EnCursoPresion {
        let s = Presion.Sesion(id: UUID().uuidString.lowercased(), serieId: serieId, tipo: tipo, inicio: sello(ahora()), zonaHoraria: zona, brazo: brazo ?? "izq")
        var e = EnCursoPresion(sesion: s, etapa: etapa, dia: FechaLocal.hoy(ahora()))
        e.variante = variante
        local.enCurso = e
        guardar()
        return e
    }

    /// Retoma la repetición que pide el servidor (`pendiente`) cuando el teléfono no tiene la sesión: con las tomas que ya están
    /// guardadas, para que la regla vea las dos. Lo que no viene en `sesiones` (las preguntas previas, el reposo) queda sin dato.
    @discardableResult
    public func retomar(_ p: PendientePresion, etapa: String) -> EnCursoPresion {
        if let e = local.enCurso, e.sesion.id == p.sesionId { return e }
        let g = sesionGuardada(p.sesionId)
        var s = Presion.Sesion(id: p.sesionId, serieId: g?.serieId, tipo: g?.tipo ?? "suelta", inicio: p.desde, zonaHoraria: zona, brazo: g?.tomas.first?.brazo ?? estado?.serie?.brazo ?? "izq")
        s.tomas = g?.tomas ?? []
        var e = EnCursoPresion(sesion: s, etapa: etapa, dia: FechaLocal.hoy(ahora()))
        e.retomada = true
        local.enCurso = e
        guardar()
        return e
    }

    /// Cambia lo que haga falta de la sesión en curso (la etapa, el temporizador, las respuestas) y lo deja en disco.
    public func cambiar(_ f: (inout EnCursoPresion) -> Void) {
        guard var e = local.enCurso else { return }
        f(&e)
        local.enCurso = e
        guardar()
    }

    /// Minutos desde la última toma: lo que mira la regla para el recordatorio.
    private func conMinutos(_ e: EnCursoPresion) -> Presion.Sesion {
        var s = e.sesion
        s.minutosDesdeUltima = e.ultimaTomaEn.map { max(0, ahora().timeIntervalSince($0) / 60).rounded(.down) } ?? 0
        return s
    }

    /// Qué toca ahora, con lo anotado hasta acá. nil sin sesión en curso.
    public func evaluar() -> Presion.Evaluacion? { local.enCurso.map { Presion.evaluarSesion(conMinutos($0)) } }

    /// Anota una toma ya validada, la deja en la cola con la sesión entera y devuelve qué toca. Se decide acá, sin esperar al servidor.
    @discardableResult
    public func anotarToma(sis: Int, dia: Int, pulso: Int, latidoIrregular: Bool, posicion: String = "sentado", minutosDePie: Int? = nil, brazo: String? = nil,
                           confirmada: Bool = false, sintomas: [String] = []) -> Presion.Evaluacion? {
        guard var e = local.enCurso, Presion.validarToma(sis: sis, dia: dia, pulso: pulso) != .imposible else { return nil }
        let orden = (e.sesion.tomas.map(\.orden).max() ?? 0) + 1
        let t = ahora()
        e.sesion.tomas.append(Presion.Toma(orden: orden, posicion: posicion, minutosDePie: minutosDePie, brazo: brazo ?? e.sesion.brazo, sis: sis, dia: dia, pulso: pulso,
                                           latidoIrregular: latidoIrregular, medidoEn: sello(t), confirmadaPorAlumno: confirmada))
        for c in sintomas where !e.sesion.sintomas.contains(c) { e.sesion.sintomas.append(c) }
        e.ultimaTomaEn = t
        e.lista = [:]
        e.sesion.listaEspera = nil
        local.enCurso = e
        return encolarSesion()
    }

    /// Una respuesta de la lista de alarma de la espera. Con un Sí, guardia por síntomas en el acto; con todas en No queda «no»;
    /// si falta alguna, la lista queda sin contestar (no cuenta como «no»).
    @discardableResult
    public func responderLista(_ codigo: String, _ si: Bool) -> Presion.Evaluacion? {
        guard var e = local.enCurso else { return nil }
        e.lista[codigo] = si
        e.sesion.sintomas.removeAll { $0 == codigo }
        if si { e.sesion.sintomas.append(codigo) }
        let contestadas = Presion.alarma.filter { e.lista[$0] != nil }
        let antes = e.sesion.listaEspera
        if e.lista.values.contains(true) { e.sesion.listaEspera = "si" }
        else if contestadas.count == Presion.alarma.count { e.sesion.listaEspera = "no" }
        else { e.sesion.listaEspera = nil }
        local.enCurso = e
        // Se manda cuando la lista dice algo nuevo: un Sí o todas en No.
        if e.sesion.listaEspera != antes || si { return encolarSesion() }
        guardar()
        return evaluar()
    }

    /// Síntomas marcados dentro de la sesión (la hoja que se abre con el pulso o la alta fuera de lo esperado, o «Me mareé»).
    @discardableResult
    public func sumarSintomas(_ codigos: [String]) -> Presion.Evaluacion? {
        guard var e = local.enCurso else { return nil }
        for c in codigos where !e.sesion.sintomas.contains(c) { e.sesion.sintomas.append(c) }
        local.enCurso = e
        // Sin ninguna toma todavía no hay nada que mandar: viaja con la primera.
        if e.sesion.tomas.isEmpty { guardar(); return evaluar() }
        return encolarSesion()
    }

    private func encolarSesion() -> Presion.Evaluacion? {
        guard let e = local.enCurso else { return nil }
        let ev = Presion.evaluarSesion(conMinutos(e))
        var envio = EnvioPresion(sesion: e.sesion, textoAlumno: ev.texto, sintoma: nil, creado: ahora(), retomada: e.retomada)
        if let i = local.envios.firstIndex(where: { $0.sesion != nil && $0.id == envio.id }) {
            envio.creado = local.envios[i].creado ?? envio.creado
            local.envios[i] = envio
        } else {
            local.envios.append(envio)
        }
        guardar()
        drenarEnFondo()
        return ev
    }

    /// Cierra la sesión en curso. Lo anotado ya está en la cola.
    public func terminar() {
        guard local.enCurso != nil else { return }
        local.enCurso = nil
        guardar()
    }

    /// «Marcar un síntoma» o la lista del recordatorio. Devuelve si hay alguno de alarma: ahí va el texto de guardia, sin esperar.
    @discardableResult
    public func marcarSintoma(codigos: [String], nota: String?, contexto: String = "boton", sesionId: String? = nil, sinSintomasEnLista: Bool? = nil) -> Bool {
        let n = (nota ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let s = SintomaPresion(id: UUID().uuidString.lowercased(), marcadoEn: sello(ahora()), zonaHoraria: zona, contexto: contexto, sesionId: sesionId,
                               codigos: codigos, sinSintomasEnLista: sinSintomasEnLista, nota: n.isEmpty ? nil : String(n.prefix(500)))
        local.envios.append(EnvioPresion(sesion: nil, textoAlumno: nil, sintoma: s, creado: ahora()))
        guardar()
        drenarEnFondo()
        return Presion.deAlarma(codigos)
    }

    // MARK: Cola

    public func drenarEnFondo() { Task { await drenar() } }

    /// En orden y de a uno. Sin red, 5xx o 429: corta y queda para después. 4xx u `ok: false`: se descarta y se refresca el estado.
    public func drenar() async {
        guard !drenando, estado != nil else { return }
        drenando = true
        defer { drenando = false }
        var refrescarAlFinal = false
        while let envio = local.envios.first, estado != nil {
            let r: Result<JSONValue, ErrorRPC>
            if let s = envio.sesion {
                r = await cliente.llamar("mypump_presion_sesion", ["p_token": .texto(token), "p_sesion": Self.json(s, texto: envio.textoAlumno ?? "ninguno", retomada: envio.retomada == true)])
            } else if let s = envio.sintoma {
                r = await cliente.llamar("mypump_presion_sintoma", ["p_token": .texto(token), "p_sintoma": Self.json(s)])
            } else {
                quitar(envio); continue
            }
            switch r {
            case .success(.null):
                return   // token caído: queda guardado para el link nuevo
            case .success(let j):
                // Mientras viajaba pudo entrar otra toma de la misma sesión: esa versión nueva sigue en la cola.
                quitar(envio)
                if j["ok"] == .bool(true) {
                    if let e = j["estado"], e != .null { aplicar(e); refrescarAlFinal = false } else { refrescarAlFinal = true }
                } else {
                    refrescarAlFinal = true
                }
            case .failure(let e):
                // Sin el servidor nuevo (404 o PGRST202): se apaga y la cola queda guardada (30 días) para cuando vuelva.
                if e.funcionInexistente || e.status == 404 { apagar(); return }
                if e.clase != .permanente { return }   // red, 5xx, 429: queda
                quitar(envio)
                refrescarAlFinal = true
            }
        }
        if refrescarAlFinal { await refrescar() }
    }

    /// Saca el envío que se mandó, salvo que mientras tanto lo haya reemplazado una versión más nueva de la misma sesión.
    private func quitar(_ envio: EnvioPresion) {
        if let i = local.envios.firstIndex(of: envio) { local.envios.remove(at: i) }
        guardar()
    }

    @discardableResult private func guardar() -> Bool {
        guard let disco else { return false }
        return disco.guardar(local, ColaPresion.archivo)
    }

    // MARK: Lo que viaja

    static var versionApp: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    static func json(_ s: Presion.Sesion, texto: String, retomada: Bool = false) -> JSONValue {
        func t(_ x: String?) -> JSONValue { x.map(JSONValue.texto) ?? .null }
        func b(_ x: Bool?) -> JSONValue { x.map(JSONValue.bool) ?? .null }
        func n(_ x: Int?) -> JSONValue { x.map { .numero(Double($0)) } ?? .null }
        return .objeto([
            "id": t(s.id), "serie_id": t(s.serieId), "tipo": .texto(s.tipo), "inicio": t(s.inicio), "zona_horaria": t(s.zonaHoraria), "brazo": t(s.brazo),
            // En una repetición retomada no se sabe: va en null y el servidor conserva lo que ya tenía.
            "previo": retomada ? .null : .objeto(["cafeina": .bool(s.previo.cafeina), "fumo": .bool(s.previo.fumo), "comida": .bool(s.previo.comida), "ejercicio": .bool(s.previo.ejercicio)]),
            "reposo_cumplido": b(s.reposoCumplido), "temporizador_salteado": b(s.temporizadorSalteado),
            "dosis_estimulante_hora": t(s.dosisEstimulanteHora), "entreno_entre_dosis_y_toma": b(s.entrenoEntreDosisYToma),
            "sintomas": .lista(s.sintomas.map(JSONValue.texto)), "lista_espera": t(s.listaEspera), "nota": t(s.nota), "texto_alumno": .texto(texto),
            "app_version": .texto(versionApp), "plataforma": .texto("ios"),
            "tomas": .lista(s.tomas.map { m in
                .objeto(["orden": n(m.orden), "posicion": .texto(m.posicion ?? "sentado"), "minutos_de_pie": n(m.minutosDePie), "brazo": t(m.brazo ?? s.brazo),
                         "sis": n(m.sis), "dia": n(m.dia), "pulso": n(m.pulso), "latido_irregular": .bool(m.latidoIrregular), "medido_en": t(m.medidoEn),
                         "confirmada_por_alumno": .bool(m.confirmadaPorAlumno)])
            }),
        ])
    }

    static func json(_ s: SintomaPresion) -> JSONValue {
        .objeto(["id": .texto(s.id), "marcado_en": .texto(s.marcadoEn), "zona_horaria": .texto(s.zonaHoraria), "contexto": .texto(s.contexto),
                 "sesion_id": s.sesionId.map(JSONValue.texto) ?? .null, "codigos": .lista(s.codigos.map(JSONValue.texto)),
                 "sin_sintomas_en_lista": s.sinSintomasEnLista.map(JSONValue.bool) ?? .null, "nota": s.nota.map(JSONValue.texto) ?? .null])
    }
}
