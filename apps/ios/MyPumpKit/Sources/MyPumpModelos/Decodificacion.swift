import Foundation

/// Lo que publica el Cerebro no tiene esquema fijo: `series` puede ser número o null, `reps` texto ("6-8", "10 min"),
/// `reemplaza` un array o un texto suelto, los bloques pueden venir null. Estos lectores nunca tiran: devuelven nil
/// cuando el valor no sirve, y la regla de normalización (como `normalizarRutina` de la web) decide el default.
extension KeyedDecodingContainer {
    func entero(_ k: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: k) { return v }
        if let d = try? decodeIfPresent(Double.self, forKey: k), d.isFinite { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    func decimal(_ k: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: k), d.isFinite { return d }
        if let s = try? decodeIfPresent(String.self, forKey: k) {
            return Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    func texto(_ k: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: k) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: k), d.isFinite { return String(d) }
        return nil
    }

    func booleano(_ k: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: k) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return ["true", "1", "si", "sí"].contains(s.lowercased()) }
        return nil
    }

    /// Array de textos; acepta un texto suelto como array de uno (pasa en `reemplaza`).
    func textos(_ k: Key) -> [String]? {
        if let a = try? decodeIfPresent([String?].self, forKey: k) { return a.compactMap { $0 } }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return [s] }
        return nil
    }

    /// Array que tolera elementos null o con forma rota: se descartan, no rompen el resto.
    func lista<T: Decodable>(_ tipo: T.Type, _ k: Key) -> [T] {
        guard let crudos = try? decodeIfPresent([Opcional<T>].self, forKey: k) else { return [] }
        return crudos.compactMap(\.valor)
    }
}

/// Envoltorio que decodifica un elemento o nil si no se puede, sin hacer fallar al array.
struct Opcional<T: Decodable>: Decodable {
    let valor: T?
    init(from decoder: Decoder) throws {
        valor = try? T(from: decoder)
    }
}

/// Valor JSON arbitrario. Hace falta donde la nativa tiene que devolver al servidor lo mismo que recibió, como el
/// `food_data` de un swap (con `_orig`, `_dev` y lo que se agregue mañana).
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case numero(Double)
    case texto(String)
    case lista([JSONValue])
    case objeto([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .numero(d) }
        else if let s = try? c.decode(String.self) { self = .texto(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .lista(a) }
        else { self = .objeto(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .numero(let d): try c.encode(d)
        case .texto(let s): try c.encode(s)
        case .lista(let a): try c.encode(a)
        case .objeto(let o): try c.encode(o)
        }
    }

    public subscript(clave: String) -> JSONValue? {
        if case .objeto(let o) = self { return o[clave] }
        return nil
    }

    public var comoTexto: String? { if case .texto(let s) = self { return s }; return nil }
    public var comoNumero: Double? { if case .numero(let d) = self { return d }; return nil }
}
