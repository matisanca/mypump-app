import Foundation

/// La identidad de un ejercicio para el historial: port exacto de `claveEjercicio` (cliente.html:2092), gemela de
/// `mypump_clave_ejercicio` en SQL (072), de `clave_ejercicio` en Python y de `_norm` del Cerebro. Si se toca una,
/// se tocan todas.
///
/// Ojo: NO usar `folding(options: .diacriticInsensitive)`. Convierte "ø" en "o", y la web la descarta. Solo se borra
/// el rango U+0300–U+036F después de NFD, como hace JS.
public enum ClaveEjercicio {
    private static let parentesis = try! NSRegularExpression(pattern: #"\(.*?\)"#)
    private static let noAlfanumerico = try! NSRegularExpression(pattern: "[^a-z0-9 ]+")
    private static let espacios = try! NSRegularExpression(pattern: " +")

    public static func de(_ nombre: String?) -> String {
        var s = (nombre ?? "").lowercased().decomposedStringWithCanonicalMapping
        s = String(String.UnicodeScalarView(s.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }))
        s = reemplazar(parentesis, en: s, por: " ")          // "(cabeza medial)" es el músculo, no el ejercicio
        s = reemplazar(noAlfanumerico, en: s, por: " ")
        s = reemplazar(espacios, en: s, por: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func reemplazar(_ re: NSRegularExpression, en s: String, por r: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: r)
    }
}
