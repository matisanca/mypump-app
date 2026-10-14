import Foundation

/// Una regex escrita para JavaScript, evaluada con la MISMA semántica en Swift.
///
/// La lógica que se porta de la web (categorías de alimentos, sustitutos, variantes de ejercicio…) está llena de
/// regex de JS sin flag `u`. Ahí `\b`, `\w` y `\d` son ASCII: "á" o "ñ" NO son letras de palabra. En ICU
/// (NSRegularExpression) sí lo son, así que `\bpan\b` daría distinto sobre "pané". Esta traducción reemplaza esas
/// clases por sus equivalentes ASCII explícitos y escapa lo que ICU interpreta distinto adentro de `[...]`.
/// Kotlin tiene el mismo problema (java.util.regex) y usa la misma traducción.
public struct JSRegex: @unchecked Sendable {
    private let re: NSRegularExpression

    public init(_ patronJS: String) {
        do {
            re = try NSRegularExpression(pattern: JSRegex.traducir(patronJS))
        } catch {
            preconditionFailure("regex de JS que no traduce: \(patronJS) → \(error)")
        }
    }

    /// `re.test(s)`
    public func prueba(_ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// `s.replace(/…/g, r)` con un reemplazo literal (sin `$1`).
    public func reemplazarTodo(_ s: String, por r: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                    withTemplate: NSRegularExpression.escapedTemplate(for: r))
    }

    private static let palabra = "[A-Za-z0-9_]"
    private static let limite = "(?:(?<=\(palabra))(?!\(palabra))|(?<!\(palabra))(?=\(palabra)))"
    private static let noLimite = "(?:(?<=\(palabra))(?=\(palabra))|(?<!\(palabra))(?!\(palabra)))"

    static func traducir(_ p: String) -> String {
        var out = ""
        var enClase = false
        var i = p.startIndex
        while i < p.endIndex {
            let c = p[i]
            if c == "\\" {
                let n = p.index(after: i)
                guard n < p.endIndex else { out.append(c); break }
                let e = p[n]
                if enClase {
                    switch e {
                    case "w": out += "A-Za-z0-9_"
                    case "d": out += "0-9"
                    case "b": out += "\\x08"     // en JS, \b adentro de una clase es backspace
                    default: out.append(c); out.append(e)
                    }
                } else {
                    switch e {
                    case "b": out += limite
                    case "B": out += noLimite
                    case "w": out += palabra
                    case "W": out += "[^A-Za-z0-9_]"
                    case "d": out += "[0-9]"
                    case "D": out += "[^0-9]"
                    default: out.append(c); out.append(e)
                    }
                }
                i = p.index(after: n)
                continue
            }
            if enClase {
                // ICU abre un conjunto anidado con '[' y hace operaciones con '&&': en JS son literales.
                if c == "[" || c == "&" { out += "\\\(c)"; i = p.index(after: i); continue }
                if c == "]" { enClase = false }
            } else if c == "[" {
                enClase = true
                out.append(c)
                i = p.index(after: i)
                // `[]` y `[^]` de JS: el ']' inmediato cierra la clase (vacía); en ICU sería literal.
                if i < p.endIndex, p[i] == "^" { out.append("^"); i = p.index(after: i) }
                continue
            }
            out.append(c)
            i = p.index(after: i)
        }
        return out
    }
}

/// `Math.round` de JS: redondea .5 hacia +∞ (Math.round(-2.5) = -2). `rounded()` de Swift va lejos del cero.
/// No es `floor(x + 0.5)`: con 0.49999999999999994 la suma ya redondea a 1.0 y daría 1 (JS da 0).
@inline(__always) public func jsRound(_ x: Double) -> Double {
    let piso = x.rounded(.down)
    return x - piso >= 0.5 ? piso + 1 : piso
}
