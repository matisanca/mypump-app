import Foundation
import MyPumpModelos

/// Un alimento de la base contra la que se buscan sustitutos (`window.MYPUMP_FOOD_DB` de la web). Macros POR 100 g.
///
/// La base viene armada de la web: `apps/shared/food-db.json` es el MYPUMP_FOOD_DB que calcula food-db.js (categoría
/// inferida y medida casera por `detectUnit`), generado por scripts/nativa/vectores-alimentos.mjs. Acá no se porta
/// el armado: se empaqueta el resultado.
public struct AlimentoBase: Sendable, Equatable {
    public let nombre: String
    /// Por 100 g, ya con el `|| 0` con que los lee el motor (undefined, null y NaN valen 0).
    public let kcal: Double
    public let prot: Double
    public let carb: Double
    public let fat: Double
    public let categoria: String?
    /// Medida casera ("unidad", "rebanada"…). Solo cuenta si hay `gramosPorUnidad`.
    public let unidad: String?
    /// Gramos de una unidad. nil cuando la web lo tiene en falso (sin dato, 0).
    public let gramosPorUnidad: Double?
    /// `_isCustom`: alimento propio del cliente (mypump_custom_foods).
    public let esPropio: Bool

    // Lo que el motor calcula sobre el nombre de cada candidato, hecho una sola vez (son funciones puras del nombre).
    /// `name.toLowerCase()` en unidades UTF-16: la identidad del alimento para la web.
    let minusculas: [UInt16]
    /// `_norm(name)`: minúsculas sin tildes, contra el que corren las preferencias y los universales.
    let normalizado: String
    /// `_isUniversal(name)`.
    let universal: Bool
    /// `_enLabel(name)` ("" si ninguna etiqueta matchea).
    let nombreIngles: String

    public init(nombre: String, kcal: Double, prot: Double, carb: Double, fat: Double, categoria: String?,
                unidad: String? = nil, gramosPorUnidad: Double? = nil, esPropio: Bool = false) {
        self.nombre = nombre
        self.kcal = kcal; self.prot = prot; self.carb = carb; self.fat = fat
        self.categoria = categoria
        self.unidad = unidad
        self.gramosPorUnidad = SemanticaJS.verdadero(gramosPorUnidad) ? gramosPorUnidad : nil
        self.esPropio = esPropio
        minusculas = SemanticaJS.minusculas(nombre)
        normalizado = SustitucionAlimentos.normalizar(nombre)
        universal = SustitucionAlimentos.esUniversal(normalizado: normalizado)
        nombreIngles = SustitucionAlimentos.etiquetaIngles(normalizado: normalizado)
    }
}

extension AlimentoBase: Decodable {
    enum CodingKeys: String, CodingKey {
        case nombre = "name", kcal, prot, carb, fat, categoria = "category", unidad = "unit"
        case gramosPorUnidad = "unitGrams", esPropio = "_isCustom"
    }

    /// Un elemento de food-db.json (`{name, kcal, prot, carb, fat, category, unit?, unitGrams?}`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func numero(_ k: CodingKeys) -> Double? { try? c.decodeIfPresent(Double.self, forKey: k) }
        func texto(_ k: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: k) }
        self.init(nombre: texto(.nombre) ?? "",
                  kcal: SemanticaJS.oCero(numero(.kcal)), prot: SemanticaJS.oCero(numero(.prot)),
                  carb: SemanticaJS.oCero(numero(.carb)), fat: SemanticaJS.oCero(numero(.fat)),
                  categoria: texto(.categoria), unidad: texto(.unidad), gramosPorUnidad: numero(.gramosPorUnidad),
                  esPropio: (try? c.decodeIfPresent(Bool.self, forKey: .esPropio)) == true)
    }
}

/// La base completa. El orden importa: es el de la web, y el ranking desempata por él.
public struct BaseAlimentos: Sendable, Equatable {
    public let alimentos: [AlimentoBase]
    /// De qué commit de la web salió (`fuente` de food-db.json).
    public let fuente: String?

    public init(_ alimentos: [AlimentoBase], fuente: String? = nil) {
        self.alimentos = alimentos
        self.fuente = fuente
    }

    private struct Archivo: Decodable {
        let fuente: String?
        let alimentos: [AlimentoBase]
    }

    /// Lee food-db.json: `{"fuente": …, "alimentos": [...]}` (o el array pelado de MYPUMP_FOOD_DB).
    public init(json: Data) throws {
        if let archivo = try? JSONDecoder().decode(Archivo.self, from: json) {
            self.init(archivo.alimentos, fuente: archivo.fuente)
        } else {
            self.init(try JSONDecoder().decode([AlimentoBase].self, from: json))
        }
    }

    /// Suma los alimentos propios del cliente como `hydrateSwapsAndCustomFoodsFromBackend` (cliente.html:5936): en
    /// orden, cada uno REEMPLAZA en su lugar al que tenga el mismo nombre en minúsculas, o se agrega al final.
    /// `Number(null)` es 0 y `unit_grams` 0 o null queda sin medida casera, igual que en la web.
    public func conPropios(_ propios: [AlimentoPropio]) -> BaseAlimentos {
        var lista = alimentos
        for p in propios {
            let a = AlimentoBase(nombre: p.nombre, kcal: SemanticaJS.oCero(p.kcal), prot: SemanticaJS.oCero(p.prot),
                                 carb: SemanticaJS.oCero(p.carb), fat: SemanticaJS.oCero(p.fat), categoria: p.categoria,
                                 unidad: p.unidad, gramosPorUnidad: p.gramosPorUnidad, esPropio: true)
            if let i = lista.firstIndex(where: { $0.minusculas == a.minusculas }) { lista[i] = a } else { lista.append(a) }
        }
        return BaseAlimentos(lista, fuente: fuente)
    }
}

/// Lo de JavaScript que el motor de alimentos necesita con su semántica exacta.
///
/// Swift compara texto por equivalencia canónica: "Vacío" con la í compuesta y con la tilde suelta (NFD) son el
/// mismo `String`, y `Set`, `contains` y `replacingOccurrences` también los igualan. JS compara unidades UTF-16: son
/// dos alimentos distintos. Por eso los nombres se comparan y se buscan por `utf16`.
enum SemanticaJS {
    /// `x || 0` sobre un número: undefined, null, 0 y NaN valen 0.
    static func oCero(_ x: Double?) -> Double {
        guard let x, !x.isNaN else { return 0 }
        return x
    }

    /// `if (x)` sobre un número: ni undefined, ni 0, ni NaN.
    static func verdadero(_ x: Double?) -> Bool {
        guard let x else { return false }
        return x != 0 && !x.isNaN
    }

    /// `a === b` entre textos.
    static func iguales(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.utf16.elementsEqual(b.utf16)
    }

    /// `s.toLowerCase()` como clave de comparación. Única diferencia conocida con `lowercased()`: JS aplica la sigma
    /// final del griego (Σ al final de palabra → ς) y Swift no. No toca ninguna regla (son todas latinas); solo
    /// separaría dos nombres griegos que difieran justo en eso.
    static func minusculas(_ s: String) -> [UInt16] { Array(s.lowercased().utf16) }

    /// `s.includes(sub)`.
    static func incluye(_ s: [UInt16], _ sub: [UInt16]) -> Bool {
        if sub.isEmpty { return true }
        guard sub.count <= s.count else { return false }
        for i in 0...(s.count - sub.count) where s[i] == sub[0] {
            var j = 1
            while j < sub.count, s[i + j] == sub[j] { j += 1 }
            if j == sub.count { return true }
        }
        return false
    }

    /// Lo que `trim()` de JS considera espacio: WhiteSpace + LineTerminator. Incluye U+FEFF y NO incluye U+0085
    /// (al revés que `.whitespacesAndNewlines`).
    private static let espacios: Set<UInt16> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002,
                                                0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028,
                                                0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]

    /// `s.trim()`.
    static func recortar(_ s: String) -> String {
        let u = Array(s.utf16)
        var i = 0, j = u.count
        while i < j, espacios.contains(u[i]) { i += 1 }
        while j > i, espacios.contains(u[j - 1]) { j -= 1 }
        return String(decoding: u[i..<j], as: UTF16.self)
    }

    /// `Math.max(a, b)`: con un NaN da NaN (`max` de Swift devuelve el otro según el orden).
    static func max(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        return a > b ? a : b
    }
}
