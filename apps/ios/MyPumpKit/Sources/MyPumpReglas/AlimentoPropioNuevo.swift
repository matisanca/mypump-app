import Foundation
import MyPumpModelos

/// "Crear alimento personalizado" (`saveCustomFood`, cliente.html:9510): valida lo que cargó el cliente y lo lleva a
/// la base de la tabla, que es SIEMPRE por 100 g. Con g o ml los valores ya vienen por 100 g (como la etiqueta); con
/// cualquier otra unidad vienen de 1 porción y se convierten con los gramos por unidad. Sin esa conversión un yogur de
/// porción 30 g / 75 kcal entraba como 75 kcal por 100 g y el motor lo calculaba 3,5 veces por debajo.
public enum AlimentoPropioNuevo {
    /// Las unidades que ofrece el formulario, en su orden, con el texto del selector.
    public static let unidades: [(valor: String, texto: String)] = [
        ("g", "gramos (g)"), ("ml", "mililitros (ml)"), ("unidad", "unidad"), ("rebanada", "rebanada"),
        ("taza", "taza"), ("porcion", "porción"), ("cucharada", "cucharada"),
    ]

    /// Lo que se manda a `mypump_create_custom_food` (`foodData` de la web).
    public struct Datos: Equatable, Sendable {
        public var nombre: String
        public var kcal: Double
        public var prot: Double
        public var carb: Double
        public var fat: Double
        public var unidad: String
        public var gramosPorUnidad: Double?
        public var categoria: String
    }

    public static func porUnidad(_ unidad: String) -> Bool { unidad != "g" && unidad != "ml" }

    /// "porción" para mostrar; la web imprime el valor del selector ("porcion").
    public static func texto(_ unidad: String) -> String {
        unidad == "porcion" ? "porción" : unidad
    }

    /// El renglón que dice en qué base se cargan los números (cambia con la unidad, como `syncUnitGramsField`).
    public static func base(unidad: String, gramosPorUnidad: Double?) -> String {
        guard porUnidad(unidad) else { return "Poné los valores por 100 g, como vienen en la etiqueta." }
        let g = (gramosPorUnidad ?? 0) > 0 ? " (\(numeroJS(gramosPorUnidad!)) g)" : ""
        return "Poné los valores de 1 \(texto(unidad))\(g), lo que realmente comés."
    }

    /// Valida y convierte. Los números llegan ya leídos (nil = campo vacío o ilegible); negativos y no finitos
    /// valen 0 como en la web. Devuelve el mensaje de error de la web si no se puede guardar.
    public static func preparar(nombre: String, kcal: Double?, prot: Double?, carb: Double?, fat: Double?,
                                unidad: String, gramosPorUnidad: Double?, categoria: String) -> Result<Datos, ErrorFormulario> {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        func num(_ x: Double?) -> Double { guard let x, x.isFinite, x > 0 else { return 0 } ; return x }
        let p = num(prot), c = num(carb), f = num(fat)
        // Sin kcal se derivan de los macros (4/4/9): mucha gente sabe los macros pero no las calorías.
        let k: Double = { if let kcal, kcal.isFinite, kcal > 0 { return kcal } ; return jsRound(p * 4 + c * 4 + f * 9) }()
        let ug: Double? = porUnidad(unidad) ? gramosPorUnidad : nil

        guard !n.isEmpty else { return .failure(ErrorFormulario("El nombre es obligatorio.")) }
        if k <= 0 && p <= 0 && c <= 0 && f <= 0 { return .failure(ErrorFormulario("Cargá al menos las calorías o algún macro.")) }
        if porUnidad(unidad), !((ug ?? 0) > 0) {
            return .failure(ErrorFormulario("Para \"\(texto(unidad))\" indicá cuánto pesa 1 \(texto(unidad)) en gramos."))
        }

        let porcionG = porUnidad(unidad) ? (ug ?? 0) : 100
        let aCien = porcionG > 0 ? 100 / porcionG : 1
        func r1(_ x: Double) -> Double { jsRound(x * aCien * 10) / 10 }
        return .success(Datos(nombre: n, kcal: jsRound(k * aCien), prot: r1(p), carb: r1(c), fat: r1(f), unidad: unidad,
                              gramosPorUnidad: (ug ?? 0) > 0 ? ug : nil, categoria: categoria))
    }

    /// Lo que escribe el cliente en un campo numérico: acepta coma o punto decimal ("1,5" y "1.5"). Vacío o
    /// ilegible = nil.
    public static func leerNumero(_ texto: String) -> Double? {
        let t = texto.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }

    private static func numeroJS(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
    }
}

public struct ErrorFormulario: Error, Equatable, Sendable {
    public let mensaje: String
    public init(_ mensaje: String) { self.mensaje = mensaje }
}
