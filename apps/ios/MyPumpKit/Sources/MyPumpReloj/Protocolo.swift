import Foundation

/// El protocolo entre el iPhone y el Apple Watch (tanda 3, 2.2). Viaja por WatchConnectivity como un diccionario de
/// propiedades (`sendMessage`, `transferUserInfo`, `updateApplicationContext`): `["v": <versión>, "mp": <JSON>]`. El JSON es
/// un `SobreReloj` (versión, id, cuándo se mandó y el mensaje).
///
/// Reglas de versión:
/// - `version` sube cuando cambia algo que el otro lado no puede leer (un campo obligatorio nuevo, un caso que cambia
///   de forma). Un campo OPCIONAL nuevo no la sube: Codable ignora las claves que no conoce y deja nil las que faltan.
/// - Se lee todo lo que esté entre `minimoCompatible` y `version`. Algo más nuevo es `versionNueva` (el otro lado se
///   actualizó: el reloj muestra «Actualizá Pump Team en el iPhone» o al revés); algo más viejo, `versionVieja`.
/// - Un mensaje de un tipo que no se conoce es `desconocido` y se descarta sin romper nada (no se acusa: el otro lado
///   lo vuelve a mandar cuando se actualice).
///
/// El iPhone es el único que habla con el servidor: el reloj le manda eventos (iniciar, confirmar serie, terminar) y el
/// iPhone los pasa a su cola (Outbox) por el mismo camino que un toque en la pantalla. Cada evento lleva un id: el
/// iPhone recuerda los ya aplicados (`AplicadosReloj`), así un reenvío no duplica una serie, y le acusa recibo al reloj
/// (`acuse`), que recién ahí lo saca de su cola (`ColaReloj`).
public enum ProtocoloReloj {
    public static let version = 1
    public static let minimoCompatible = 1
    /// La clave del JSON en el diccionario de WatchConnectivity.
    public static let claveMensaje = "mp"
    /// La clave de la versión (también afuera del JSON, para rechazar sin decodificar).
    public static let claveVersion = "v"

    public enum Fallo: Error, Equatable, Sendable {
        case sinMensaje
        case versionNueva(Int)
        case versionVieja(Int)
        case desconocido(String)
        case ilegible
    }

    static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    /// El sobre como JSON.
    public static func datos(_ sobre: SobreReloj) throws -> Data { try codificador.encode(sobre) }

    /// El sobre como diccionario para WatchConnectivity (solo tipos de propiedades: Int y Data).
    public static func diccionario(_ sobre: SobreReloj) throws -> [String: Any] {
        [claveVersion: sobre.v, claveMensaje: try datos(sobre)]
    }

    /// Lee un diccionario que llegó por WatchConnectivity.
    public static func leer(_ d: [String: Any]) throws(Fallo) -> SobreReloj {
        guard let datos = d[claveMensaje] as? Data else { throw .sinMensaje }
        if let v = d[claveVersion] as? Int { try revisar(v) }
        return try leer(datos)
    }

    /// Lee el JSON de un sobre.
    public static func leer(_ datos: Data) throws(Fallo) -> SobreReloj {
        // Primero solo la versión y el tipo: un sobre de una versión que no se conoce no se intenta leer entero.
        let cabecera: Cabecera
        do { cabecera = try JSONDecoder().decode(Cabecera.self, from: datos) } catch { throw .ilegible }
        try revisar(cabecera.v)
        if let t = cabecera.mensaje?.tipo, MensajeReloj.Tipo(rawValue: t) == nil { throw .desconocido(t) }
        do { return try JSONDecoder().decode(SobreReloj.self, from: datos) } catch { throw .ilegible }
    }

    static func revisar(_ v: Int) throws(Fallo) {
        if v > version { throw .versionNueva(v) }
        if v < minimoCompatible { throw .versionVieja(v) }
    }

    private struct Cabecera: Decodable {
        struct Tipo: Decodable { let tipo: String }
        let v: Int
        let mensaje: Tipo?
    }
}

/// Un mensaje con su versión, su id y cuándo se armó (ms desde 1970).
public struct SobreReloj: Codable, Equatable, Sendable {
    public var v: Int
    public var id: UUID
    public var enviado: Double
    public var mensaje: MensajeReloj

    public init(_ mensaje: MensajeReloj, id: UUID = UUID(), enviado: Double, v: Int = ProtocoloReloj.version) {
        self.v = v; self.id = id; self.enviado = enviado; self.mensaje = mensaje
    }
}

/// Lo que se dicen el iPhone y el reloj.
public enum MensajeReloj: Equatable, Sendable {
    /// Reloj → iPhone: «mandame la rutina de hoy» (al abrir la app del reloj y al volver la conexión).
    case pedirRutina
    /// iPhone → reloj: la rutina del día tal como está en el teléfono (la última gana).
    case rutina(RutinaReloj)
    /// Reloj → iPhone: eventos de la cola del reloj, en orden.
    case eventos([EventoEnCola])
    /// iPhone → reloj: estos eventos ya están aplicados en el teléfono (o se descartaron a propósito: ver `motivo`).
    case acuse([AcuseEvento])
    /// iPhone → reloj: no hay rutina para mostrar (sin cuenta, sin rutina activa).
    case sinRutina(motivo: String)

    public enum Tipo: String, Codable, Sendable { case pedirRutina, rutina, eventos, acuse, sinRutina }

    public var tipo: Tipo {
        switch self {
        case .pedirRutina: .pedirRutina
        case .rutina: .rutina
        case .eventos: .eventos
        case .acuse: .acuse
        case .sinRutina: .sinRutina
        }
    }
}

extension MensajeReloj: Codable {
    private enum Claves: String, CodingKey { case tipo, rutina, eventos, acuse, motivo }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        switch try c.decode(Tipo.self, forKey: .tipo) {
        case .pedirRutina: self = .pedirRutina
        case .rutina: self = .rutina(try c.decode(RutinaReloj.self, forKey: .rutina))
        case .eventos: self = .eventos(try c.decode([EventoEnCola].self, forKey: .eventos))
        case .acuse: self = .acuse(try c.decode([AcuseEvento].self, forKey: .acuse))
        case .sinRutina: self = .sinRutina(motivo: try c.decode(String.self, forKey: .motivo))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Claves.self)
        try c.encode(tipo, forKey: .tipo)
        switch self {
        case .pedirRutina: break
        case .rutina(let r): try c.encode(r, forKey: .rutina)
        case .eventos(let e): try c.encode(e, forKey: .eventos)
        case .acuse(let a): try c.encode(a, forKey: .acuse)
        case .sinRutina(let m): try c.encode(m, forKey: .motivo)
        }
    }
}

/// El acuse de un evento: aplicado, o descartado con su motivo (otro día, una serie que ya no existe). En los dos
/// casos el reloj lo saca de la cola: reintentar no lo arreglaría.
public struct AcuseEvento: Codable, Equatable, Sendable {
    public enum Resultado: String, Codable, Sendable { case aplicado, repetido, descartado }
    public var id: UUID
    public var resultado: Resultado
    public var motivo: String?
    public init(id: UUID, resultado: Resultado, motivo: String? = nil) { self.id = id; self.resultado = resultado; self.motivo = motivo }
}
