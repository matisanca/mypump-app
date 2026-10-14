import CryptoKit
import Foundation
import MyPumpModelos

/// Lo que hace falta para leer lo que escribió JavaScript y para que el libro mayor sea determinista.
enum JSONLegado {
    /// `JSON.parse` tolerante: nil si no es JSON (la web hace `catch { queue = [] }` y sigue).
    ///
    /// `JSON.stringify` escribe un surrogate suelto como `\udXXX`. Pasa en la dedupeKey del chat, que la web arma con
    /// `contenido.slice(0, 40)`: si el corte cae en medio de un emoji, queda la mitad. JSONDecoder rechaza el texto
    /// ENTERO por esa sola entrada, y con él toda la cola. El suelto se cambia por U+FFFD antes de decodificar; el
    /// contenido del mensaje (que no se corta) no cambia.
    static func parsear(_ texto: String) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: Data(sanearSurrogados(texto).utf8))
    }

    static func sanearSurrogados(_ s: String) -> String {
        guard s.utf8.contains(0x5C) else { return s }   // sin barras no hay escapes
        let b = Array(s.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(b.count)
        func hex4(_ i: Int) -> UInt16? {
            guard i + 4 <= b.count else { return nil }
            var v: UInt16 = 0
            for c in b[i..<(i + 4)] {
                let d: UInt8
                switch c {
                case 0x30...0x39: d = c - 0x30
                case 0x41...0x46: d = c - 0x41 + 10
                case 0x61...0x66: d = c - 0x61 + 10
                default: return nil
                }
                v = v << 4 | UInt16(d)
            }
            return v
        }
        let reemplazo = Array(#"�"#.utf8)
        var i = 0
        while i < b.count {
            guard b[i] == 0x5C, i + 1 < b.count else { out.append(b[i]); i += 1; continue }
            // `\uXXXX`: lo único que puede venir roto. Cualquier otro escape (también `\\`) se copia entero, así una
            // barra escapada nunca se confunde con el comienzo de un escape.
            guard b[i + 1] == 0x75, let v = hex4(i + 2) else { out.append(b[i]); out.append(b[i + 1]); i += 2; continue }
            if (0xD800...0xDBFF).contains(v) {
                if i + 12 <= b.count, b[i + 6] == 0x5C, b[i + 7] == 0x75, let w = hex4(i + 8), (0xDC00...0xDFFF).contains(w) {
                    out.append(contentsOf: b[i..<(i + 12)])
                    i += 12
                } else {
                    out.append(contentsOf: reemplazo)
                    i += 6
                }
            } else if (0xDC00...0xDFFF).contains(v) {
                out.append(contentsOf: reemplazo)
                i += 6
            } else {
                out.append(contentsOf: b[i..<(i + 6)])
                i += 6
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Serialización canónica: claves ordenadas, sin espacios y los números enteros sin ".0". Es la base del id del
    /// libro mayor, así que tiene que dar lo mismo en cada corrida (no hace falta que coincida con JavaScript).
    static func canonico(_ v: JSONValue) -> String {
        var s = ""
        escribir(v, en: &s)
        return s
    }

    private static func escribir(_ v: JSONValue, en s: inout String) {
        switch v {
        case .null: s += "null"
        case .bool(let b): s += b ? "true" : "false"
        case .numero(let d): s += numero(d)
        case .texto(let t): cadena(t, en: &s)
        case .lista(let a):
            s += "["
            for (i, x) in a.enumerated() { if i > 0 { s += "," }; escribir(x, en: &s) }
            s += "]"
        case .objeto(let o):
            s += "{"
            for (i, k) in o.keys.sorted().enumerated() {
                if i > 0 { s += "," }
                cadena(k, en: &s)
                s += ":"
                escribir(o[k] ?? .null, en: &s)
            }
            s += "}"
        }
    }

    static func numero(_ d: Double) -> String {
        if d.isFinite, d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }

    private static func cadena(_ t: String, en s: inout String) {
        s += "\""
        for u in t.unicodeScalars {
            switch u {
            case "\"": s += "\\\""
            case "\\": s += "\\\\"
            case _ where u.value < 0x20: s += String(format: "\\u%04x", u.value)
            default: s.unicodeScalars.append(u)
            }
        }
        s += "\""
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `!!valor` de JavaScript.
    static func verdadero(_ v: JSONValue?) -> Bool {
        switch v {
        case .none, .some(.null): return false
        case .some(.bool(let b)): return b
        case .some(.numero(let d)): return d != 0 && !d.isNaN
        case .some(.texto(let t)): return !t.isEmpty
        case .some(.lista), .some(.objeto): return true
        }
    }

    /// Un número de la web, que pudo quedar como texto (`localStorage` guarda todo como texto).
    static func numero(_ v: JSONValue?) -> Double? {
        switch v {
        case .some(.numero(let d)) where d.isFinite: return d
        // "nan" o "inf" en texto también: el que no es finito no es un número que sirva (y `Int()` lo convierte cerrando la app).
        case .some(.texto(let t)): return Double(t.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        default: return nil
        }
    }

    static func texto(_ v: JSONValue?) -> String? {
        switch v {
        case .some(.texto(let t)): return t
        case .some(.numero(let d)): return numero(d)
        default: return nil
        }
    }
}
