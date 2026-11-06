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
        let d = Datos(nombre: n, kcal: jsRound(k * aCien), prot: r1(p), carb: r1(c), fat: r1(f), unidad: unidad,
                      gramosPorUnidad: (ug ?? 0) > 0 ? ug : nil, categoria: categoria)
        if imposible(d) {
            return .failure(ErrorFormulario(porUnidad(unidad)
                ? "Esos valores no entran en 1 \(texto(unidad)) de \(numeroJS(ug ?? 0)) g: revisá cuánto pesa o los valores."
                : "Esos valores no pueden ser de 100 \(unidad): si son de una porción, elegí «porción» y poné cuánto pesa."))
        }
        return .success(d)
    }

    /// Lo que 100 g no pueden tener: más de 100 g de macros (110 con el margen del redondeo de la etiqueta) o más calorías
    /// que el aceite (900). Con ml no se miran los macros, que en un líquido denso pasan de 100 por 100 ml. Desvío a
    /// propósito de la web, que lo guarda igual (27-oct): «1 rebanada de 15 g» con los valores del paquete quedó en 833 kcal
    /// y 133 g de proteína por 100 g, y con eso el motor de reemplazos calcula las porciones.
    public static let maximoMacrosPor100 = 110.0
    public static let maximoKcalPor100 = 950.0

    static func imposible(_ d: Datos) -> Bool {
        d.kcal > maximoKcalPor100 || (d.unidad != "ml" && d.prot + d.carb + d.fat > maximoMacrosPor100)
    }

    // MARK: - Lectura de la etiqueta y aviso de proteína en polvo (6-nov)

    /// En qué base vinieron los números de la foto de la etiqueta: de 1 porción de tantos gramos, por 100 g, o no se
    /// sabe (la etiqueta no dice cuánto pesa la porción; se le pregunta al cliente). Antes una porción sin gramos se
    /// tomaba como 100 g: un whey de 30 g = 132 kcal quedó en 132 kcal por 100 g y el reemplazo pidió 151 g (5 scoops).
    public enum BaseLectura: Equatable, Sendable { case porcion(Double), cien, desconocida }

    /// `base` la manda mini-vision desde el 6-nov ('porcion' | '100g' | 'desconocida'); con uno viejo se deduce de
    /// `porcion_g`, y sin gramos ya no se asume 100 g.
    public static func baseLectura(porcionG: Double?, base: String?) -> BaseLectura {
        let g: Double? = { guard let p = porcionG, p.isFinite, p > 0 else { return nil }; return p }()
        if base == "100g" { return .cien }
        if base == "desconocida" { return .desconocida }
        guard let g else { return .desconocida }
        return jsRound(g) == 100 ? .cien : .porcion(g)
    }

    public static let preguntaBase = "¿Estos valores son por 100 g o de 1 porción?"

    /// El renglón que queda después de leer la etiqueta: dice en qué base quedaron los números.
    public static func textoLectura(_ base: BaseLectura, confianzaBaja: Bool, avisos: [String] = []) -> String {
        let enBase: String
        switch base {
        case .porcion(let g): enBase = "Quedaron como valores de 1 porción de \(numeroJS(jsRound(g))) g."
        case .cien: enBase = "Quedaron como valores por 100 g."
        case .desconocida: enBase = "La etiqueta no dice cuánto pesa la porción. \(preguntaBase)"
        }
        if confianzaBaja {
            let detalle = avisos.isEmpty ? "" : " (\(avisos.joined(separator: "; ")))"
            return "⚠ La etiqueta se leyó con poca claridad\(detalle): revisá los valores antes de guardar. \(enBase)"
        }
        if base == .desconocida { return "✓ Etiqueta leída. \(enBase)" }
        return "✓ Etiqueta leída. \(enBase) Revisalos y tocá \"Crear y usar\"."
    }

    /// Una proteína en polvo tiene 350 a 420 kcal cada 100 g. Por debajo de este piso casi seguro se cargaron los valores
    /// de 1 scoop como si fueran de 100 g.
    public static let pisoKcalPolvoProteina = 300.0

    static func esPolvoDeProteina(_ nombre: String) -> Bool {
        let n = PorcionCasera.normalizar(nombre)
        if ["whey", "caseina", "isolat", "scoop", "proteina en polvo", "protein powder"].contains(where: { n.contains($0) }) {
            return true
        }
        return n.contains("prote") && n.contains("polvo")
    }

    /// El aviso (no frena el guardado) cuando un polvo de proteína queda con menos de 300 kcal por 100 g. nil si no aplica.
    public static func avisoPolvoProteina(nombre: String, kcal: Double?, prot: Double?, carb: Double?, fat: Double?,
                                          unidad: String, gramosPorUnidad: Double?) -> String? {
        guard esPolvoDeProteina(nombre) else { return nil }
        func num(_ x: Double?) -> Double { guard let x, x.isFinite, x > 0 else { return 0 } ; return x }
        let k = num(kcal) > 0 ? num(kcal) : num(prot) * 4 + num(carb) * 4 + num(fat) * 9
        guard k > 0 else { return nil }
        let porcion: Double
        if porUnidad(unidad) {
            guard let g = gramosPorUnidad, g.isFinite, g > 0 else { return nil }
            porcion = g
        } else {
            porcion = 100
        }
        guard k * 100 / porcion < pisoKcalPolvoProteina else { return nil }
        let que = porUnidad(unidad)
            ? "Revisá que los gramos de 1 \(texto(unidad)) sean los de la etiqueta."
            : "Si estos valores son de 1 scoop, elegí «porción» y poné cuánto pesa."
        return "Para una proteína en polvo son pocas calorías: suele tener 350 a 420 kcal cada 100 g. \(que)"
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
