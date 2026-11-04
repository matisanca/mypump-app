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
/// - Por eso `pedirDia` y los días de la rutina (`dias`, `avisoDia`) no subieron la versión: un iPhone de la versión 1
///   sin `pedirDia` lo lee como `desconocido` (no contesta `incompatible`: eso queda para las versiones) y el reloj, sin
///   respuesta, deja de esperar y lo avisa; un reloj viejo ignora los campos nuevos. Subirla haría que un lado viejo
///   marque «incompatible» y deje de pasar las series, que sí entiende.
///
/// El iPhone es el único que habla con el servidor: el reloj le manda eventos (iniciar, confirmar serie, terminar) y el
/// iPhone los pasa a su cola (Outbox) por el mismo camino que un toque en la pantalla. Cada evento lleva un id: el
/// iPhone recuerda los ya aplicados (`AplicadosReloj`), así un reenvío no duplica una serie, y le acusa recibo al reloj
/// (`acuse`). Nada se descarta en silencio: lo que el iPhone no puede aplicar AHORA vuelve como `pendiente` (sigue en la
/// cola del reloj y se reintenta) y lo que no va a poder aplicar nunca, como `rechazado` con un motivo que el reloj le
/// muestra al alumno. Cada evento lleva la cuenta (un hash, nunca el token) y la rutina en la que se hizo.
///
/// Si al iPhone le llega una versión más nueva que la suya, contesta `incompatible` con la suya: el reloj deja de
/// reenviar y pide actualizar la app del iPhone (y al revés).
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

    /// Lo que se contesta a un sobre de una versión que no se entiende: `incompatible` con la versión propia, para que el
    /// otro lado deje de reenviar y le diga al alumno qué actualizar. nil si el sobre se puede leer (o es otro fallo).
    public static func respuestaIncompatible(_ d: [String: Any], ahora: Double) -> [String: Any]? {
        do { _ = try leer(d); return nil } catch {
            switch error {
            case .versionNueva, .versionVieja: return try? diccionario(SobreReloj(.incompatible(version: version), enviado: ahora))
            default: return nil
            }
        }
    }

    /// El texto para el alumno cuando el otro lado habla la versión `v`.
    public static func textoIncompatible(_ v: Int, enElReloj: Bool) -> String {
        let actualizarIPhone = enElReloj ? v < version : v > version
        return actualizarIPhone ? "Actualizá Pump Team en el iPhone para usar el reloj." : "Actualizá Pump Team en el reloj."
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
    /// Reloj → iPhone: «abrí este día del plan» (el alumno lo eligió en el reloj). El iPhone lo abre con su propio
    /// selector (`cambiarDia`) y contesta con la `rutina` de ese día; si no puede, con la del día que tiene y `avisoDia`.
    /// Un iPhone viejo no conoce el tipo y no contesta nada (el reloj deja de esperar y avisa).
    case pedirDia(diaId: String)
    /// iPhone → reloj: la rutina del día tal como está en el teléfono (la última gana).
    case rutina(RutinaReloj)
    /// Reloj → iPhone: eventos de la cola del reloj, en orden.
    case eventos([EventoEnCola])
    /// iPhone → reloj: estos eventos ya están aplicados en el teléfono (o se descartaron a propósito: ver `motivo`).
    case acuse([AcuseEvento])
    /// iPhone → reloj: no hay rutina para mostrar (sin cuenta, sin rutina activa).
    case sinRutina(motivo: String)
    /// Cualquiera → el otro: no puedo leer tu versión; la mía es `version`.
    case incompatible(version: Int)

    public enum Tipo: String, Codable, Sendable { case pedirRutina, pedirDia, rutina, eventos, acuse, sinRutina, incompatible }

    public var tipo: Tipo {
        switch self {
        case .pedirRutina: .pedirRutina
        case .pedirDia: .pedirDia
        case .rutina: .rutina
        case .eventos: .eventos
        case .acuse: .acuse
        case .sinRutina: .sinRutina
        case .incompatible: .incompatible
        }
    }
}

extension MensajeReloj: Codable {
    private enum Claves: String, CodingKey { case tipo, diaId, rutina, eventos, acuse, motivo, version }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        switch try c.decode(Tipo.self, forKey: .tipo) {
        case .pedirRutina: self = .pedirRutina
        case .pedirDia: self = .pedirDia(diaId: try c.decode(String.self, forKey: .diaId))
        case .rutina: self = .rutina(try c.decode(RutinaReloj.self, forKey: .rutina))
        case .eventos: self = .eventos(try c.decode([EventoEnCola].self, forKey: .eventos))
        case .acuse: self = .acuse(try c.decode([AcuseEvento].self, forKey: .acuse))
        case .sinRutina: self = .sinRutina(motivo: try c.decode(String.self, forKey: .motivo))
        case .incompatible: self = .incompatible(version: try c.decode(Int.self, forKey: .version))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Claves.self)
        try c.encode(tipo, forKey: .tipo)
        switch self {
        case .pedirRutina: break
        case .pedirDia(let d): try c.encode(d, forKey: .diaId)
        case .rutina(let r): try c.encode(r, forKey: .rutina)
        case .eventos(let e): try c.encode(e, forKey: .eventos)
        case .acuse(let a): try c.encode(a, forKey: .acuse)
        case .sinRutina(let m): try c.encode(m, forKey: .motivo)
        case .incompatible(let v): try c.encode(v, forKey: .version)
        }
    }
}

/// El acuse de un evento.
/// - `aplicado` / `repetido`: ya está en el iPhone; sale de la cola del reloj.
/// - `pendiente`: el iPhone no lo puede aplicar ahora (otro día abierto, la demo, otra cuenta, sin red al cerrar): sigue
///   en la cola del reloj y se reintenta; el motivo se muestra como «esperando».
/// - `rechazado`: no se va a poder aplicar nunca (la rutina o la semana cambiaron, la serie ya no existe): sale de la cola
///   y el reloj le muestra al alumno «Esta serie no se pudo guardar: <motivo>».
public struct AcuseEvento: Codable, Equatable, Sendable {
    public enum Resultado: String, Codable, Sendable { case aplicado, repetido, pendiente, rechazado }
    public var id: UUID
    public var resultado: Resultado
    public var motivo: String?
    public init(id: UUID, resultado: Resultado, motivo: String? = nil) { self.id = id; self.resultado = resultado; self.motivo = motivo }
}
