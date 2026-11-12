import Foundation

/// 2.3.1: los reemplazos de comida no suben las kcal del plan en silencio. Mismas reglas y vectores que la web
/// (`window.MyPump.reemplazosKcal`) y Android (`apps/shared/vectores/reemplazos_kcal.json`).
/// - Arriba («Disponibles en cualquier país») solo los universales con hasta 15 % de desvío; abajo, primero los propios
///   con hasta 15 % y después todo lo demás ordenado por desvío (sin dato al final, en el orden del motor).
/// - Un reemplazo que suma más del 10 % o más de 60 kcal pide confirmación.
/// - La cabecera de Dieta dice cuánto suman los reemplazos del día.
public enum ReemplazosKcal {
    public static let desvioArriba = 0.15
    public static let confirmarFraccion = 0.10
    public static let confirmarKcal = 60.0
    public static let usarIgual = "Usar igual"
    public static let elegirOtro = "Elegir otro"
    public static let deshacer = "Deshacer"

    /// Desvío relativo del reemplazo contra el original; `nil` sin kcal en el original («sin dato»).
    public static func desvio(original: Double?, reemplazo: Double?) -> Double? {
        guard let o = original, o.isFinite, o > 0, let r = reemplazo, r.isFinite else { return nil }
        return (r - o) / o
    }

    /// El «+N %» de cada opción, o `nil` para mostrar «sin dato».
    public static func desvioPct(original: Double?, reemplazo: Double?) -> Int? {
        desvio(original: original, reemplazo: reemplazo).map { ($0 * 100).jsEntero }
    }

    public static func ordenar<T>(_ items: [T], kcalOriginal: Double?, kcal: (T) -> Double?, universal: (T) -> Bool,
                                  propio: (T) -> Bool) -> (universales: [T], resto: [T]) {
        let conD = items.enumerated().map { (i: $0.offset, x: $0.element, d: desvio(original: kcalOriginal, reemplazo: kcal($0.element))) }
        func cerca(_ d: Double?) -> Bool { d.map { abs($0) <= desvioArriba + 1e-9 } ?? false }
        let universales = conD.filter { universal($0.x) && cerca($0.d) }
        let propios = conD.filter { !universal($0.x) && propio($0.x) && cerca($0.d) }
        let tomados = Set((universales + propios).map(\.i))
        let resto = conD.filter { !tomados.contains($0.i) }.sorted { a, b in
            switch (a.d, b.d) {
            case let (da?, db?): abs(da) != abs(db) ? abs(da) < abs(db) : a.i < b.i
            case (nil, nil): a.i < b.i
            case (nil, _): false
            case (_, nil): true
            }
        }
        return (universales.map(\.x), (propios + resto).map(\.x))
    }

    /// Cuántas kcal suma el reemplazo por día (redondeado como `Math.round`).
    public static func suma(original: Double?, reemplazo: Double?) -> Int {
        guard let r = reemplazo, r.isFinite else { return 0 }
        let o = original.flatMap { $0.isFinite ? $0 : nil } ?? 0
        return (r - o).jsEntero
    }

    public static func pideConfirmacion(original: Double?, reemplazo: Double?) -> Bool {
        guard let r = reemplazo, r.isFinite else { return false }
        let o = original.flatMap { $0.isFinite ? $0 : nil } ?? 0
        let s = r - o
        guard s > 0 else { return false }
        if s > confirmarKcal { return true }
        guard let d = desvio(original: original, reemplazo: reemplazo) else { return false }
        return d > confirmarFraccion + 1e-9
    }

    public static func textoConfirmacion(original: Double?, reemplazo: Double?) -> String {
        "Este cambio suma \(suma(original: original, reemplazo: reemplazo)) kcal a esta comida y a todos tus días. ¿Lo usás igual?"
    }

    /// El renglón de la cabecera de Dieta con la suma de los reemplazos del día; `nil` si no mueven nada.
    public static func renglon(suma: Double) -> String? {
        let n = suma.isFinite ? suma.jsEntero : 0
        if n == 0 { return nil }
        return n > 0 ? "Tus reemplazos suman +\(n) kcal" : "Tus reemplazos restan \(-n) kcal"
    }
}
