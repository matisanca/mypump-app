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

/// El aviso del domingo (pedido de Mati, 14-oct): no se configura y llega como un mensaje suyo, con el título de sus
/// mensajes del chat ("Mati", mig 057) y su forma de escribirles a los clientes (sin dos puntos, guiones ni emojis).
/// Reusa el id 1002 de la Capacitor: reprogramar pisa el que dejó la app vieja.
public enum AvisoDomingo {
    public static let id = PreferenciasAvisos.idRevision
    public static let titulo = "Mati"
    public static let cuerpo = "Cómo venís esta semana? Subí tu revisión así te hago la devolución"
    public static let destino = "revision"
    /// Domingo a las 11:00, hora del teléfono: es cuando se arma la ronda de Mati.
    public static let diaDeLaSemana = 1
    public static let hora = 11
    public static let minuto = 0

    /// El domingo que viene a las 11:00 (hoy, si es domingo antes de las 11), con año, mes y día: el aviso es de UNA vez
    /// y la app lo vuelve a armar cada vez que abre con la cuenta. Repetido cada semana le seguía llegando para siempre
    /// a quien dejó la app o tiene el link vencido (un ex cliente recibiendo "mensajes de Mati"; revisión del 15-oct,
    /// hallazgo 8). Quien usa la app no lo nota: lo arma cada vez que la abre.
    public static func proximo(desde ahora: Date, calendario: Calendar = .current) -> DateComponents? {
        var patron = DateComponents()
        patron.weekday = diaDeLaSemana
        patron.hour = hora
        patron.minute = minuto
        guard let fecha = calendario.nextDate(after: ahora, matching: patron, matchingPolicy: .nextTime) else { return nil }
        return calendario.dateComponents([.year, .month, .day, .hour, .minute], from: fecha)
    }
}

/// `mypump_notif_prefs` (notificaciones.js): un solo recordatorio, la revisión del domingo, apagable y con hora. La
/// nativa ya no lo lee para agendar (ver `AvisoDomingo`); queda por los ids y por lo que trae la migración. Lo
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
        // Una hora imposible (o un 1e20, que cerraba la app) deja la de siempre: el aviso nunca queda sin poder sonar.
        if let h = c["hora"]?.comoNumero, h == h.rounded(), (0...23).contains(h) { p.check.hora = Int(h) }
        if let m = c["min"]?.comoNumero, m == m.rounded(), (0...59).contains(m) { p.check.min = Int(m) }
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
    /// Cada cuánto se vuelve a registrar el mismo token de APNs con la misma cuenta.
    static let pushVigencia: TimeInterval = 7 * 86_400

    /// `registrarPush`: directo; solo si cambió desde el último que se mandó (`mypump_push_token`, la misma clave que la
    /// web), si es otra cuenta (`mypump_push_cuenta`, una huella, nunca el token: con el link de otra cuenta en el mismo
    /// teléfono, los avisos seguían yendo a la anterior; lo encontró el agente de Android, 14-oct), o si pasaron 7 días
    /// (`mypump_push_fecha`): si `push.py` dio de baja la fila, el teléfono no volvía a registrarse mientras su token no
    /// cambiara (revisión del 15-oct, hallazgo 9). Devuelve si quedó registrado.
    public func registrarPush(dispositivo: String, version: String?, defaults: UserDefaults = .standard, ahora: Date = Date()) async -> Bool {
        guard let t = token, !esDemo else { return false }
        let cuenta = Self.huellaPush(t)
        let ms = ahora.timeIntervalSince1970 * 1000
        if defaults.string(forKey: "mypump_push_token") == dispositivo, defaults.string(forKey: "mypump_push_cuenta") == cuenta,
           let fecha = defaults.object(forKey: "mypump_push_fecha") as? Double, ms >= fecha, ms - fecha < Self.pushVigencia * 1000 {
            return true
        }
        let r = await cliente.llamar("mypump_registrar_push", ["p_token": .texto(t), "p_device": .texto(dispositivo),
                                                              "p_plataforma": .texto("ios"), "p_app_version": version.map(JSONValue.texto) ?? .null])
        guard case .success(let v) = r, v == .bool(true) else { return false }
        defaults.set(dispositivo, forKey: "mypump_push_token")
        defaults.set(cuenta, forKey: "mypump_push_cuenta")
        defaults.set(ms, forKey: "mypump_push_fecha")
        return true
    }

    /// La de la carpeta de la cuenta (`Disco`), igual que `RegistroPush.huella` de Android.
    static func huellaPush(_ token: String) -> String { Disco.huella(token) }
}
