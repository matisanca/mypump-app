import Foundation

/// Números con la semántica exacta de JavaScript.
public enum NumeroJS {
    /// `Number.prototype.toFixed(d)`: redondea sobre el valor EXACTO del double, no sobre `x × 10ⁿ` (que ya trae error):
    /// 0.15 vale 0,1499… y da "0.1"; un empate exacto (1.25) va al mayor, "1.3". Un negativo conserva el signo aunque
    /// redondee a cero ("-0.0"). La media de 60,0 y 60,1 da "60.0", como la web (la revisión encontró "60,1").
    public static func toFixed(_ x: Double, _ d: Int) -> String {
        guard x.isFinite else { return x.isNaN ? "NaN" : (x > 0 ? "Infinity" : "-Infinity") }
        if abs(x) >= 1e21 { return String(x) }
        let negativo = x < 0
        // %.60f imprime el valor binario exacto hasta 60 decimales: alcanza para decidir el redondeo de 1 o 2 decimales.
        let texto = String(format: "%.60f", abs(x))
        let partes = texto.split(separator: ".", omittingEmptySubsequences: false)
        var entero = Array(partes[0])
        let fraccion = Array(partes.count > 1 ? partes[1] : "")
        var digitos = Array(fraccion.prefix(d))
        while digitos.count < d { digitos.append("0") }
        let resto = fraccion.dropFirst(d)
        let primero = resto.first ?? "0"
        let haciaArriba = primero > "5" || (primero == "5")   // ≥ 0,5 del último lugar: JS elige el n mayor en el empate
        if haciaArriba {
            // Sumar 1 al último dígito, con acarreo hacia la parte entera.
            var todo = entero + digitos
            var i = todo.count - 1
            while i >= 0 {
                if todo[i] == "9" { todo[i] = "0"; i -= 1 } else { todo[i] = Character(String(todo[i].wholeNumberValue! + 1)); break }
            }
            if i < 0 { todo.insert("1", at: 0) }
            entero = Array(todo.prefix(todo.count - d))
            digitos = Array(todo.suffix(d))
        }
        let numero = String(entero) + (d > 0 ? "." + String(digitos) : "")
        return (negativo ? "-" : "") + numero
    }
}
