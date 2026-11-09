import Foundation
import Security

/// Dónde vive el acceso del cliente (el token de su link). En la app: el Keychain, accesible después del primer
/// desbloqueo (la sincronización de salud en segundo plano lo necesita). En los tests: memoria.
public protocol AlmacenToken: Sendable {
    func leer() -> String?
    func guardar(_ token: String?)
}

public final class TokenEnKeychain: AlmacenToken, @unchecked Sendable {
    private let servicio: String
    private let cuenta = "token"

    public init(servicio: String = "com.pumpteam.mypump.acceso") { self.servicio = servicio }

    public func leer() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicio,
                                kSecAttrAccount as String: cuenta, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public func guardar(_ token: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicio,
                                   kSecAttrAccount as String: cuenta]
        SecItemDelete(base as CFDictionary)
        guard let token, let d = token.data(using: .utf8) else { return }
        var nuevo = base
        nuevo[kSecValueData as String] = d
        nuevo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(nuevo as CFDictionary, nil)
    }
}

public final class TokenEnMemoria: AlmacenToken, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    public init(_ token: String? = nil) { self.token = token }
    public func leer() -> String? { lock.withLock { token } }
    public func guardar(_ t: String?) { lock.withLock { token = t } }
}

/// El token tiene que tener esta forma (la misma regex de la web: deeplink.js y cliente.html).
public enum FormatoToken {
    public static func valido(_ t: String) -> Bool {
        t.range(of: #"^[a-zA-Z0-9_-]{16,64}$"#, options: .regularExpression) != nil
    }

    /// Lo que pega el cliente: el link entero, a medias o el token solo (index.html:376-423). Le saca lo que agrega el
    /// copiar y pegar, para que un token válido no salga con «No reconocí ese link»: caracteres invisibles (las marcas de
    /// dirección de WhatsApp) y la puntuación de la frase alrededor.
    public static func extraer(de texto: String) -> String? {
        let t = limpio(texto)
        if valido(t) { return t }
        if let c = URLComponents(string: t.hasPrefix("http") ? t : "https://\(t)"),
           let q = c.queryItems?.first(where: { $0.name == "t" })?.value, valido(q) { return q }
        // Sin omitir el tramo vacío: `…/?TOKEN` no es un link (como la web y Android).
        if let ultimo = t.split(separator: "/").last.map(String.init)?.split(separator: "?", omittingEmptySubsequences: false).first.map(String.init),
           valido(ultimo) {
            return ultimo
        }
        // El mensaje entero de WhatsApp ("Hola! Este es tu link: https://…/?t=…"): el `[?&]t=` de la web, y un espacio o un
        // salto de línea alrededor del `t=` (nunca adentro del token: se cortaría o se pegaría con el texto que sigue).
        if let r = t.range(of: #"[?&]\s*t\s*=\s*[a-zA-Z0-9_-]{16,64}"#, options: .regularExpression),
           let igual = t[r].firstIndex(of: "=") {
            return String(t[t.index(after: igual)..<r.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // El link con el token en la ruta, adentro de un mensaje.
        if let r = t.range(of: #"/acceso/[a-zA-Z0-9_-]{16,64}"#, options: .regularExpression) {
            return String(t[r].dropFirst(8))
        }
        return nil
    }

    /// Nunca incluye `-` ni `_`, que son parte del token, ni `?`, que puede ser el principio de `?t=…` pegado a medias.
    private static let bordes = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!()[]{}<>\"'«»“”‘’"))

    private static func limpio(_ texto: String) -> String {
        var visibles = String.UnicodeScalarView()
        visibles.append(contentsOf: texto.unicodeScalars.filter { $0.properties.generalCategory != .format })
        return String(visibles).trimmingCharacters(in: bordes)
    }
}

/// La última cuenta con la que anduvo la nativa: el sha256 de su token, nunca el token. La migración vuelve a adoptar el
/// token de la app vieja solo si es el de esa cuenta. Si no, alguien que entró con su link y se le venció quedaba adentro de
/// la cuenta de la app vieja, que podía ser de otra persona (revisión adversarial del 15-oct, hallazgo 3).
public enum UltimaCuenta {
    public static let clave = "mypump_ultima_cuenta"

    public static func anotar(_ token: String, en ajustes: UserDefaults = .standard) {
        ajustes.set(JSONLegado.sha256(token), forKey: clave)
    }

    public static func hash(en ajustes: UserDefaults = .standard) -> String? { ajustes.string(forKey: clave) }
}
