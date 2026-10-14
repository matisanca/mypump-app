import Foundation
import MyPumpModelos

/// A dónde lleva tocar un aviso: el `destino` que mandan `push.py` (comentarios del coach) y la notificación local del
/// domingo. Uno desconocido, como el histórico `comentarios`, cae a Chat (NOT-03).
public enum DestinoAviso: String, Sendable, Equatable {
    case entreno, dieta, chat, revision, progreso, miDia, misDatos

    /// `?scene=<escena>` del link (ACC-09): solo una escena que existe; cualquier otra cosa no hace nada (en la web,
    /// una escena inexistente dejaba la app en blanco).
    public init?(escena: String?) {
        guard let escena, ["train", "diet", "chat", "revision", "progress", "salud", "myday"].contains(escena) else { return nil }
        self.init(destino: escena)
    }

    public init(destino: String?) {
        switch destino {
        case "train": self = .entreno
        case "diet": self = .dieta
        case "progress": self = .progreso
        case "myday": self = .miDia
        case "revision": self = .revision
        case "salud": self = .misDatos
        default: self = .chat
        }
    }
}

/// `mypump_notif_prefs` (notificaciones.js): un solo recordatorio, la revisión del domingo, apagable y con hora. Lo
/// guardado se mezcla sobre los valores por defecto campo por campo; claves viejas (entreno, peso, racha) se ignoran.
public struct PreferenciasAvisos: Codable, Equatable, Sendable {
    public struct Recordatorio: Codable, Equatable, Sendable {
        public var on: Bool
        public var hora: Int
        public var min: Int
        public init(on: Bool, hora: Int, min: Int) { self.on = on; self.hora = hora; self.min = min }
    }

    public var check: Recordatorio

    public static let porDefecto = PreferenciasAvisos(check: Recordatorio(on: true, hora: 11, min: 0))
    public static let clave = "mypump_notif_prefs"
    /// Ids fijos de la Capacitor: reprogramar pisa en vez de duplicar. 1001, 1003 y 1004 ya no existen pero siguen
    /// agendados en los teléfonos que abrieron la app antes de que se sacaran: se cancelan siempre.
    public static let idRevision = "1002"
    public static let idsViejos = ["1001", "1003", "1004"]

    public init(check: Recordatorio) { self.check = check }

    public static func leer(_ texto: String?) -> PreferenciasAvisos {
        var p = porDefecto
        guard let texto, let d = texto.data(using: .utf8), let j = try? JSONDecoder().decode(JSONValue.self, from: d),
              case .objeto(let o) = j, case .objeto(let c)? = o["check"] else { return p }
        if case .bool(let on)? = c["on"] { p.check.on = on }
        if let h = c["hora"]?.comoNumero { p.check.hora = Int(h) }
        if let m = c["min"]?.comoNumero { p.check.min = Int(m) }
        return p
    }

    public var texto: String {
        (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? "{}"
    }
}

/// El token de APNs como lo registraba la Capacitor: hex en MAYÚSCULAS. `mypump_push_devices.token` es UNIQUE como
/// texto: en minúsculas el mismo teléfono quedaría registrado dos veces y recibiría todo doble.
public enum TokenPush {
    public static func hex(_ d: Data) -> String { d.map { String(format: "%02X", $0) }.joined() }
}

extension ModeloApp {
    /// `registrarPush`: directo; solo si cambió desde el último que se mandó (`mypump_push_token`, la misma clave que la
    /// web). Devuelve si quedó registrado.
    public func registrarPush(dispositivo: String, version: String?, defaults: UserDefaults = .standard) async -> Bool {
        guard let t = token, !esDemo else { return false }
        if defaults.string(forKey: "mypump_push_token") == dispositivo { return true }
        let r = await cliente.llamar("mypump_registrar_push", ["p_token": .texto(t), "p_device": .texto(dispositivo),
                                                              "p_plataforma": .texto("ios"), "p_app_version": version.map(JSONValue.texto) ?? .null])
        guard case .success(let v) = r, v == .bool(true) else { return false }
        defaults.set(dispositivo, forKey: "mypump_push_token")
        return true
    }
}
