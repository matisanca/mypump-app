import Foundation
import MyPumpModelos

/// Reglas y decodificación de «Técnica por video» (`tecnica/CONTRATO_APP.md`). Decodifica con tolerancia: lo que no se entiende se
/// descarta y un campo roto vale lo de fábrica. Gemelo de Tecnica.kt; `apps/shared/vectores/tecnica.json` hace fallar si difieren.
public enum Tecnica {
    public static let consentimientoVigente = "terceros-tecnica-v1"
    public static let maxNota = 300
    public static let maxNombre = 120

    public enum Rechazo: String, Equatable, Sendable { case corto, largo, pesado, ilegible, otro
        public var texto: String {
            switch self {
            case .corto: TextosTecnica.rechazoCorto
            case .largo: TextosTecnica.rechazoLargo
            case .pesado: TextosTecnica.rechazoPesado
            case .ilegible: TextosTecnica.rechazoIlegible
            case .otro: TextosTecnica.errorGenerico
            }
        }
    }

    public enum Accion: String, Equatable, Sendable { case ok, reintentar, descartar, guardar }
    public struct Subida: Equatable, Sendable {
        public let accion: Accion
        public let rechazo: Rechazo?
    }

    /// 429, 5xx y un 200 raro no gastan el video. Un 403 (link caído o cuenta sin habilitar) tampoco: queda para el link nuevo.
    /// El resto de los 4xx es definitivo (contrato, «Enviar», paso 4).
    public static func clasificarSubida(status: Int, ok: Bool, error: String?) -> Subida {
        if (200..<300).contains(status) { return Subida(accion: ok ? .ok : .reintentar, rechazo: nil) }
        if status == 429 || status >= 500 || status == 0 { return Subida(accion: .reintentar, rechazo: nil) }
        if status == 403 { return Subida(accion: .guardar, rechazo: nil) }
        switch status {
        case 413: return Subida(accion: .descartar, rechazo: .pesado)
        case 400:
            let e = (error ?? "").lowercased()
            return Subida(accion: .descartar, rechazo: e.contains("corto") ? .corto : e.contains("largo") ? .largo : .ilegible)
        default: return Subida(accion: .descartar, rechazo: .otro)
        }
    }

    /// Lo que el teléfono puede frenar antes de subir.
    public static func validar(duracion: Double, bytes: Int64, topes: TopesTecnica) -> Rechazo? {
        if duracion <= 0 || bytes <= 0 { return .ilegible }
        if duracion < topes.duracionMinS { return .corto }
        // El servidor mide con ffprobe: medio segundo de margen por las diferencias de redondeo del contenedor.
        if duracion > topes.duracionMaxS + 0.5 { return .largo }
        if bytes > topes.bytesMax { return .pesado }
        return nil
    }

    /// El ejercicio tal como lo espera el contrato: el slug que tenga, y los nombres dentro de lo que acepta `nuevo`.
    public static func slug(_ e: Ejercicio) -> String {
        String((e.catalogoSlug ?? e.matchedSlug ?? e.imagenes?.matchedSlug ?? "").prefix(maxNombre))
    }

    /// Por puntos de código, como cuenta el SQL: `prefix` cuenta grafemas y una nota con emojis compuestos se pasaba del tope.
    public static func nota(_ s: String) -> String { var v = String.UnicodeScalarView(); v.append(contentsOf: s.unicodeScalars.prefix(maxNota)); return String(v) }

    /// Los ejercicios de la rutina para elegir: una vez cada uno, en orden, sin calentamientos ni cardio.
    public static func ejerciciosParaElegir(_ dias: [Dia], efectivo: (Ejercicio) -> Ejercicio = { $0 }) -> [Ejercicio] {
        var vistos = Set<String>()
        var salen: [Ejercicio] = []
        for d in dias {
            for b in d.bloques {
                for e in b.ejercicios.map(efectivo) where e.tipo != "calentamiento" && e.tipo != "cardio" && !e.nombre.isEmpty {
                    if vistos.insert(e.nombre.lowercased()).inserted { salen.append(e) }
                }
            }
        }
        return salen
    }
}

public struct TopesTecnica: Equatable, Sendable {
    public var duracionMinS: Double = 4
    public var duracionMaxS: Double = 75
    public var bytesMax: Int64 = 62_914_560
    public var porSemana: Int = 3
    public init() {}

    public init(_ j: JSONValue?) {
        if case .numero(let n)? = j?["duracion_min_s"], n > 0 { duracionMinS = n }
        if case .numero(let n)? = j?["duracion_max_s"], n > 0 { duracionMaxS = n }
        if case .numero(let n)? = j?["bytes_max"], n > 0 { bytesMax = Int64(n) }
        if case .numero(let n)? = j?["por_semana"], n > 0 { porSemana = Int(min(n, 1_000)) }
    }
}

public struct CorreccionTecnica: Equatable, Sendable, Identifiable {
    public var id: String { "\(prioridad)-\(titulo)" }
    public let prioridad: Int
    public let titulo: String
    public let queSeVe: String
    public let porQue: String
    public let comoCorregir: String
    public let momentoS: Double?

    init?(_ j: JSONValue) {
        guard let t = j["titulo"]?.comoTexto, !t.isEmpty else { return nil }
        titulo = t
        if case .numero(let n)? = j["prioridad"], n.isFinite { prioridad = Int(max(-1_000, min(n, 1_000))) } else { prioridad = 99 }
        queSeVe = j["que_se_ve"]?.comoTexto ?? ""
        porQue = j["por_que"]?.comoTexto ?? ""
        comoCorregir = j["como_corregir"]?.comoTexto ?? ""
        if case .numero(let n)? = j["momento_s"], n >= 0 { momentoS = n } else { momentoS = nil }
    }
}

public struct NoEvaluableTecnica: Equatable, Sendable, Identifiable {
    public var id: String { que }
    public let que: String
    public let motivo: String
}

public struct DevolucionTecnica: Equatable, Sendable {
    public let credito: String
    public let ejercicio: String?
    public let bien: [String]
    public let correcciones: [CorreccionTecnica]
    public let noEvaluable: [NoEvaluableTecnica]
    /// El cómo, si hace falta otro video. nil: no hace falta.
    public let otroVideo: String?

    init?(_ j: JSONValue?) {
        guard let j, case .objeto = j else { return nil }
        credito = j["credito"]?.comoTexto ?? ""
        ejercicio = j["ejercicio"]?.comoTexto
        bien = Self.lista(j["bien"]).compactMap { $0.comoTexto }.filter { !$0.isEmpty }
        correcciones = Self.lista(j["correcciones"]).compactMap(CorreccionTecnica.init).sorted { $0.prioridad < $1.prioridad }
        noEvaluable = Self.lista(j["no_evaluable"]).compactMap { n in
            guard let q = n["que"]?.comoTexto, !q.isEmpty else { return nil }
            return NoEvaluableTecnica(que: q, motivo: n["motivo"]?.comoTexto ?? "")
        }
        if j["pedir_otro_video"]?["necesario"] == .bool(true) { otroVideo = j["pedir_otro_video"]?["como"]?.comoTexto ?? "" } else { otroVideo = nil }
    }

    private static func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }
}

public struct EnvioTecnica: Equatable, Sendable, Identifiable {
    public enum Estado: String, Equatable, Sendable { case borrador, enviado, publicado, rechazado }
    public let id: String
    public var estado: Estado
    public let slug: String
    public let nombre: String
    public let nota: String?
    public let enviadoEn: String?
    public var tieneVideo: Bool
    public let rechazoTexto: String?
    public let publicadoEn: String?
    public let devolucion: DevolucionTecnica?

    public init(id: String, estado: Estado, slug: String, nombre: String, nota: String?, tieneVideo: Bool) {
        self.id = id; self.estado = estado; self.slug = slug; self.nombre = nombre; self.nota = nota; self.tieneVideo = tieneVideo
        enviadoEn = nil; rechazoTexto = nil; publicadoEn = nil; devolucion = nil
    }

    init?(_ j: JSONValue) {
        guard let i = j["id"]?.comoTexto, !i.isEmpty, let e = j["estado"]?.comoTexto.flatMap(Estado.init(rawValue:)) else { return nil }
        id = i; estado = e
        slug = j["ejercicio_slug"]?.comoTexto ?? ""
        nombre = j["ejercicio_nombre"]?.comoTexto ?? ""
        nota = j["nota_alumno"]?.comoTexto
        enviadoEn = j["enviado_en"]?.comoTexto
        tieneVideo = j["tiene_video"] == .bool(true)
        rechazoTexto = j["rechazo_texto"]?.comoTexto
        publicadoEn = j["publicado_en"]?.comoTexto
        devolucion = DevolucionTecnica(j["devolucion"])
        if e == .publicado && devolucion == nil { return nil }
    }
}

/// `mypump_tecnica_get` con la sección habilitada. Si no vino `habilitado: true`, nil: no se muestra nada.
public struct EstadoTecnica: Equatable, Sendable {
    public let consentimientoVersion: String
    public let consentimientoAceptado: Bool
    public let topes: TopesTecnica
    public var envios: [EnvioTecnica]

    public init?(_ j: JSONValue) {
        guard j["habilitado"] == .bool(true) else { return nil }
        consentimientoVersion = j["consentimiento_version"]?.comoTexto ?? Tecnica.consentimientoVigente
        consentimientoAceptado = j["consentimiento_aceptado"] == .bool(true)
        topes = TopesTecnica(j["topes"])
        if case .lista(let l)? = j["envios"] { envios = l.compactMap(EnvioTecnica.init) } else { envios = [] }
    }

    /// El borrador es del teléfono: el alumno nunca lo ve en la lista.
    public var visibles: [EnvioTecnica] { envios.filter { $0.estado != .borrador } }
    public var enRevision: EnvioTecnica? { envios.first { $0.estado == .enviado } }
}
