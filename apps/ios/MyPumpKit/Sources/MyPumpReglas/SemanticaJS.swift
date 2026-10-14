import Foundation

/// Lo que JavaScript hace con textos y números, igual. La lógica de Entreno de la web está llena de `parseInt`,
/// `parseFloat`, `${numero}`, `trim()` y `toUpperCase()`, y cada uno tiene su rareza: `parseInt("12abc")` es 12,
/// `parseFloat(",5")` es NaN, `${1e-7}` es "1e-7" (Swift imprime "1e-07"), `trim()` saca U+FEFF pero no U+0085, y
/// `toLowerCase()` conoce la sigma final. Acá viven esas reglas, una sola vez.
public enum JS {
    // MARK: - Blancos

    /// Los blancos de JS (`\s` y `trim`): WhiteSpace y LineTerminator del estándar.
    public static func esBlanco(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        default: return false
        }
    }

    /// `s.trim()`
    public static func trim(_ s: String) -> String {
        let u = s.unicodeScalars
        guard let ini = u.firstIndex(where: { !esBlanco($0) }), let fin = u.lastIndex(where: { !esBlanco($0) }) else { return "" }
        return String(u[ini...fin])
    }

    // MARK: - Números

    /// `parseInt(s, 10)`; con `base10: false` es `parseInt(s)`, que además acepta `0x`. nil es NaN.
    public static func parseInt(_ s: String?, base10: Bool = true) -> Double? {
        guard let s else { return nil }   // parseInt(null) es parseInt("null"): NaN
        let u = Array(s.unicodeScalars)
        var i = 0
        while i < u.count, esBlanco(u[i]) { i += 1 }
        var signo = 1.0
        if i < u.count, u[i] == "-" { signo = -1; i += 1 } else if i < u.count, u[i] == "+" { i += 1 }
        var base = 10.0
        if !base10, i + 1 < u.count, u[i] == "0", u[i + 1] == "x" || u[i + 1] == "X" { base = 16; i += 2 }
        var digitos: [Unicode.Scalar] = []
        while i < u.count, valorDigito(u[i], base: base) != nil { digitos.append(u[i]); i += 1 }
        guard !digitos.isEmpty else { return nil }
        if base == 10 {
            var t = ""
            t.unicodeScalars.append(contentsOf: digitos)
            return signo * (Double(t) ?? .nan)
        }
        return signo * digitos.reduce(0.0) { $0 * 16 + Double(valorDigito($1, base: 16)!) }
    }

    private static func valorDigito(_ u: Unicode.Scalar, base: Double) -> Int? {
        switch u.value {
        case 0x30...0x39: return Int(u.value - 0x30)
        case 0x61...0x66 where base == 16: return Int(u.value - 0x61 + 10)
        case 0x41...0x46 where base == 16: return Int(u.value - 0x41 + 10)
        default: return nil
        }
    }

    /// `parseFloat(s)`: el prefijo decimal más largo (con signo, punto y exponente), o `Infinity`. nil es NaN.
    public static func parseFloat(_ s: String?) -> Double? {
        guard let s else { return nil }
        let u = Array(s.unicodeScalars)
        var i = 0
        while i < u.count, esBlanco(u[i]) { i += 1 }
        var t = ""
        if i < u.count, u[i] == "+" || u[i] == "-" { t.unicodeScalars.append(u[i]); i += 1 }
        let infinito = Array("Infinity".unicodeScalars)
        if i + infinito.count <= u.count, Array(u[i..<(i + infinito.count)]) == infinito { return t == "-" ? -.infinity : .infinity }
        let esDigito = { (x: Unicode.Scalar) in x.value >= 0x30 && x.value <= 0x39 }
        var cuerpo = ""
        var hayDigitos = false
        while i < u.count, esDigito(u[i]) { cuerpo.unicodeScalars.append(u[i]); i += 1; hayDigitos = true }
        if i < u.count, u[i] == "." {
            var k = i + 1
            var fraccion = ""
            while k < u.count, esDigito(u[k]) { fraccion.unicodeScalars.append(u[k]); k += 1 }
            if hayDigitos || !fraccion.isEmpty {
                cuerpo += "." + fraccion
                i = k
                hayDigitos = true
            }
        }
        guard hayDigitos else { return nil }
        if i < u.count, u[i] == "e" || u[i] == "E" {
            var k = i + 1
            var exponente = "e"
            if k < u.count, u[k] == "+" || u[k] == "-" { exponente.unicodeScalars.append(u[k]); k += 1 }
            var digitos = ""
            while k < u.count, esDigito(u[k]) { digitos.unicodeScalars.append(u[k]); k += 1 }
            if !digitos.isEmpty { cuerpo += exponente + digitos }
        }
        // Swift no lee "5." ni ".5" en todas las versiones: se completa con ceros (el valor es el mismo).
        if cuerpo.hasPrefix(".") { cuerpo = "0" + cuerpo }
        cuerpo = cuerpo.replacingOccurrences(of: ".e", with: ".0e")
        if cuerpo.hasSuffix(".") { cuerpo += "0" }
        return Double(t + cuerpo)
    }

    /// `x || 0` sobre un número: nil (null/undefined), NaN, 0 y −0 dan 0.
    public static func oCero(_ d: Double?) -> Double {
        guard let d, !d.isNaN, d != 0 else { return 0 }
        return d
    }

    /// `String(x)` y `${x}` de un número de JS (Number::toString): los mismos dígitos más cortos que Swift, con el
    /// formato de JS ("1e-7" y no "1e-07", "100000000000000000000" hasta 1e21).
    public static func texto(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d == 0 { return "0" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        if d < 0 { return "-" + texto(-d) }
        let (digitos, n) = digitosCortos(d)
        let k = digitos.count
        if k <= n && n <= 21 { return digitos + String(repeating: "0", count: n - k) }
        if 0 < n && n <= 21 { return String(digitos.prefix(n)) + "." + String(digitos.dropFirst(n)) }
        if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + digitos }
        let e = n - 1
        let exponente = (e < 0 ? "-" : "+") + String(abs(e))
        if k == 1 { return digitos + "e" + exponente }
        return String(digitos.prefix(1)) + "." + String(digitos.dropFirst()) + "e" + exponente
    }

    /// `${x}` de un valor que puede ser null.
    public static func texto(_ d: Double?) -> String { d.map(texto) ?? "null" }

    /// Los dígitos significativos más cortos de `d` (> 0) y la posición del punto: d = 0.dígitos × 10^n.
    static func digitosCortos(_ d: Double) -> (String, Int) {
        let desc = d.description   // el más corto que vuelve al mismo Double
        let partes = desc.split(separator: "e", maxSplits: 1)
        let mantisa = String(partes[0])
        let exp = partes.count > 1 ? Int(partes[1]) ?? 0 : 0
        let enteros = mantisa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var digitos = Array(String(enteros[0]) + (enteros.count > 1 ? String(enteros[1]) : ""))
        var n = enteros[0].count + exp
        while digitos.first == "0" { digitos.removeFirst(); n -= 1 }
        while digitos.last == "0" { digitos.removeLast() }
        return (String(digitos), n)
    }

    // MARK: - Mayúsculas y minúsculas

    /// `s.toUpperCase()`: el mapeo completo de Unicode, sin idioma ("ß" → "SS").
    public static func mayusculas(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars { out += u.properties.uppercaseMapping }
        return out
    }

    /// `s.toLowerCase()`: el mapeo completo, sin idioma, con la sigma final ("ΟΔΟΣ" → "οδος").
    public static func minusculas(_ s: String) -> String {
        let u = Array(s.unicodeScalars)
        var out = ""
        for (i, c) in u.enumerated() {
            if c.value == 0x3A3, sigmaFinal(u, i) { out.unicodeScalars.append("\u{3C2}"); continue }
            out += c.properties.lowercaseMapping
        }
        return out
    }

    /// Final_Sigma: antes hay una letra con caso (saltando las ignorables) y después no.
    private static func sigmaFinal(_ u: [Unicode.Scalar], _ i: Int) -> Bool {
        var j = i - 1
        while j >= 0, u[j].properties.isCaseIgnorable { j -= 1 }
        guard j >= 0, u[j].properties.isCased else { return false }
        var k = i + 1
        while k < u.count, u[k].properties.isCaseIgnorable { k += 1 }
        return !(k < u.count && u[k].properties.isCased)
    }

    // MARK: - Igualdad

    /// `a === b` entre textos: unidad UTF-16 por unidad (el `==` de Swift perdona NFC contra NFD; JS no).
    public static func iguales(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return a.utf16.elementsEqual(b.utf16)
        default: return false
        }
    }

    /// Un texto en un `||` o un `if` de JS: null y "" son falsos.
    public static func verdadero(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}

/// Una regex de la web con su semántica exacta (sin flag `u`): `\b`, `\w`, `\d` y `$` (los traduce `JSRegex`), más
/// `\s` y `.` como los de JS y, con `i`, las mayúsculas como las junta JS: una letra coincide con su otra caja solo si
/// las dos son ASCII o las dos no lo son ("ſ" no es "s", el signo Kelvin no es "k"; "á" sí es "Á"). Con
/// NSRegularExpression y CASE_INSENSITIVE, "Swing con Kettlebell" escrito con el signo Kelvin "llevaría carga"; en la
/// web no.
struct RegexWeb: @unchecked Sendable {
    let re: NSRegularExpression

    init(_ patron: String, i: Bool = false) {
        let base = i ? RegexWeb.sinCaja(patron) : patron
        do {
            re = try NSRegularExpression(pattern: JSRegex.traducir(base))
        } catch {
            preconditionFailure("regex de la web que no traduce: \(patron) → \(error)")
        }
    }

    /// `re.test(s)`
    func prueba(_ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    /// `s.match(re)[n]` (sin flag `g`): el grupo `n` de la primera coincidencia.
    func grupo(_ s: String, _ n: Int) -> String? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: n), in: s) else { return nil }
        return String(s[r])
    }

    /// `s.match(/…/g)`: todas las coincidencias.
    func todas(_ s: String) -> [String] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

    /// `s.replace(/…/g, r)` con un reemplazo literal.
    func reemplazarTodo(_ s: String, por r: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: NSRegularExpression.escapedTemplate(for: r))
    }

    /// `s.split(re)[0]`: lo que hay antes de la primera coincidencia.
    func antesDeLaPrimera(_ s: String) -> String {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range, in: s) else { return s }
        return String(s[..<r.lowerBound])
    }

    // MARK: Traducción

    /// El flag `i` sin CASE_INSENSITIVE: cada letra se vuelve una clase con sus cajas válidas para JS.
    static func sinCaja(_ p: String) -> String {
        let u = Array(p.unicodeScalars)
        var out = ""
        var enClase = false
        var k = 0
        while k < u.count {
            let c = u[k]
            if c == "\\", k + 1 < u.count {
                out.unicodeScalars.append(c); out.unicodeScalars.append(u[k + 1]); k += 2
                continue
            }
            if enClase {
                if c == "]" { enClase = false; out.append("]") }
                else {
                    let v = cajas(c)
                    precondition(v.count == 1 || ((k == 0 || u[k - 1] != "-") && (k + 1 >= u.count || u[k + 1] != "-")),
                                 "rango con letras adentro de una clase y flag i: \(p)")
                    out.unicodeScalars.append(contentsOf: v)
                }
                k += 1
                continue
            }
            if c == "[" {
                enClase = true
                out.append("[")
                k += 1
                if k < u.count, u[k] == "^" { out.append("^"); k += 1 }
                continue
            }
            let v = cajas(c)
            if v.count > 1 { out.append("["); out.unicodeScalars.append(contentsOf: v); out.append("]") }
            else { out.unicodeScalars.append(c) }
            k += 1
        }
        return out
    }

    /// Las letras que JS (sin `u`) considera iguales a `c` con el flag `i`: Canonicalize = toUpperCase, salvo que
    /// pase de no-ASCII a ASCII o no sea una sola unidad.
    private static func cajas(_ c: Unicode.Scalar) -> [Unicode.Scalar] {
        func canonico(_ x: Unicode.Scalar) -> Unicode.Scalar {
            let m = Array(x.properties.uppercaseMapping.unicodeScalars)
            guard m.count == 1, m[0].value <= 0xFFFF, x.value <= 0xFFFF else { return x }
            if x.value >= 128 && m[0].value < 128 { return x }
            return m[0]
        }
        let base = canonico(c)
        var v: [Unicode.Scalar] = [c]
        for x in [c.properties.uppercaseMapping, c.properties.lowercaseMapping].compactMap({ s -> Unicode.Scalar? in
            let a = Array(s.unicodeScalars)
            return a.count == 1 ? a[0] : nil
        }) where !v.contains(x) && canonico(x) == base {
            v.append(x)
        }
        return v
    }

}
