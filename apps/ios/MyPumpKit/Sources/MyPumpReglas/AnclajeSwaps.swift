import Foundation
import MyPumpModelos

/// Un swap de comida está ANCLADO al alimento que reemplaza, no a su posición. Port de `_huellaFood` y
/// `_swapAplicable` (cliente.html:1990-2015).
///
/// La clave del swap es posicional (comida, opción, índice) y `mypump_publicar_cliente` conserva el `dieta_id`: si
/// Mati agrega un alimento antes, el swap caería sobre otro (la leche de Alejandro Romero, 28-ago). Por eso cada swap
/// guarda en `food_data._orig` lo que reemplazó, y solo se aplica si lo que hay hoy en esa posición es eso — o el
/// mismo alimento con la cantidad de OTRO tipo de día ("Avena 80 g" entreno / "Avena 50 g" descanso).
public enum AnclajeSwaps {
    /// `nombre|qty|unidad`, en minúsculas y sin espacios en los bordes. La qty como la imprime JS (`Number(x) || 0`).
    public static func huella(nombre: String?, qty: Double?, unidad: String?) -> String {
        let n = (nombre ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let u = (unidad ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(n)|\(numeroJS(qty))|\(u)"
    }

    public static func huella(_ a: Alimento) -> String { huella(nombre: a.nombre, qty: a.qty, unidad: a.unidad) }

    /// La huella del ancla `_orig` (viene del servidor tal cual: el nombre o la qty pueden ser número o texto).
    public static func huella(ancla: JSONValue) -> String {
        huella(nombre: textoJS(ancla["name"]), qty: numero(ancla["qty"]), unidad: textoJS(ancla["unit"]))
    }

    /// ¿El swap (su `food_data`) se aplica al alimento que se está mostrando?
    /// - Parameters:
    ///   - comidaId: nil cuando no se conoce la posición (en la web, `comidaId == null`).
    ///   - enPosicion: los alimentos de esa misma posición en TODOS los tipos de día.
    public static func aplica(foodData: JSONValue?, original: Alimento, comidaId: String?, enPosicion: () -> [Alimento]) -> Bool {
        guard let actual = foodData, actual != .null else { return false }
        guard let ancla = actual["_orig"], esVerdadero(ancla) else { return true }   // legado: sin ancla, se aplica
        let h = huella(ancla: ancla)
        if h == huella(original) { return true }
        guard comidaId != nil else { return false }
        let nombre = { (s: String?) in (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard nombre(textoJS(ancla["name"])) == nombre(original.nombre) else { return false }
        return enPosicion().contains { huella($0) == h }
    }

    // MARK: - Semántica de JS

    /// `!x` de JS sobre un valor JSON: null, false, 0, NaN y "" son falsos; objetos y arrays (aun vacíos) verdaderos.
    static func esVerdadero(_ v: JSONValue) -> Bool {
        switch v {
        case .null: return false
        case .bool(let b): return b
        case .numero(let d): return d != 0 && !d.isNaN
        case .texto(let s): return !s.isEmpty
        case .lista, .objeto: return true
        }
    }

    /// `Number(x)`: número tal cual; texto numérico → número; vacío → 0; lo demás NaN.
    static func numero(_ v: JSONValue?) -> Double? {
        switch v {
        case .numero(let d): return d
        case .texto(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? 0 : Double(t)
        case .bool(let b): return b ? 1 : 0
        case .null: return 0
        default: return nil
        }
    }

    /// `String(x || '')` para nombre/unidad.
    static func textoJS(_ v: JSONValue?) -> String? {
        switch v {
        case .texto(let s): return s
        case .numero(let d): return d == 0 ? nil : numeroJS(d)
        case .bool(let b): return b ? "true" : nil
        default: return nil
        }
    }

    /// Cómo imprime JS `Number(qty) || 0`: NaN, nil y 0 → "0"; enteros sin ".0"; el resto con su representación más
    /// corta (la de Swift coincide con la de JS en el rango que se usa).
    static func numeroJS(_ d: Double?) -> String {
        guard let d, !d.isNaN, d != 0 else { return "0" }
        if d == d.rounded(), abs(d) < 1e21 { return String(Int64(d)) }
        return "\(d)"
    }
}
