import Foundation

/// Formateadores de fechas y calendarios compartidos. Crear un `ISO8601DateFormatter` o un `DateFormatter` cuesta unos
/// 0,1-0,3 ms (arma ICU por dentro): Progreso los creaba por fila y, con el historial más largo que deja el servidor
/// (48 filas por ejercicio, 2.880 en total), tardaba 1,5 s en el hilo principal (15-oct). Usar uno ya armado desde varios
/// hilos es seguro mientras nadie lo modifique: por eso se arman una vez, y lo que se devuelve no se toca.
public enum Formateadores {
    /// `2026-10-14T13:59:00.123Z` / `…+00:00`, con milisegundos.
    nonisolated(unsafe) public static let isoConDecimales: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Lo mismo sin decimales.
    nonisolated(unsafe) public static let isoSinDecimales: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// El gregoriano en UTC (las cuentas de días de calendario, como `new Date("YYYY-MM-DD")` de JS).
    public static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// El gregoriano en esa zona (nunca el calendario que el cliente eligió en Ajustes: JS siempre usa el gregoriano). Se
    /// arma una vez por zona; si el teléfono cambia de zona, `.current` trae otra y se arma la nueva.
    public static func gregoriano(_ zona: TimeZone) -> Calendar {
        cache.lock.lock(); defer { cache.lock.unlock() }
        if let c = cache.calendarios[zona.identifier] { return c }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        cache.calendarios[zona.identifier] = c
        return c
    }

    /// Un `DateFormatter` gregoriano con ese patrón, zona y locale. Es compartido: solo `string(from:)` y `date(from:)`.
    public static func fecha(_ patron: String, zona: TimeZone, locale: String) -> DateFormatter {
        let clave = "\(patron)|\(zona.identifier)|\(locale)"
        cache.lock.lock(); defer { cache.lock.unlock() }
        if let f = cache.formatos[clave] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zona
        f.dateFormat = patron
        cache.formatos[clave] = f
        return f
    }

    /// Un instante del servidor: ISO con `T` o con espacio (PostgREST), con microsegundos (ISO8601DateFormatter no lee
    /// más de 3 decimales: se recortan) y con la zona como `+00` (se completa a `+00:00`). nil si no se puede leer.
    public static func instante(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        var s = iso.replacingOccurrences(of: " ", with: "T")
        if let punto = s.firstIndex(of: "."), let fin = s[punto...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let decimales = s[s.index(after: punto)..<fin]
            s.replaceSubrange(s.index(after: punto)..<fin, with: String(decimales.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0))
        }
        // `[+-]\d\d$` a mano: compilar la expresión regular en cada fila también se notaba.
        let u = Array(s.utf8.suffix(3))
        if u.count == 3, u[0] == 0x2B || u[0] == 0x2D, (0x30...0x39).contains(u[1]), (0x30...0x39).contains(u[2]) { s += ":00" }
        return isoConDecimales.date(from: s) ?? isoSinDecimales.date(from: s)
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var calendarios: [String: Calendar] = [:]
        var formatos: [String: DateFormatter] = [:]
    }

    private static let cache = Cache()
}
