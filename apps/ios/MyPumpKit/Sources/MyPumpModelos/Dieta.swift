import Foundation

/// Fila de `mypump_get_dieta_activa`.
public struct DietaActiva: Decodable, Sendable, Equatable {
    public let id: String
    public let version: Int
    /// `var`: la app la guarda ya normalizada (`NormalizarDieta`), como la web guarda `DIET`.
    public var estructura: EstructuraDieta

    enum CodingKeys: String, CodingKey { case id, version, estructura }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id) ?? ""
        version = c.entero(.version) ?? 1
        estructura = (try? c.decode(EstructuraDieta.self, forKey: .estructura)) ?? EstructuraDieta()
    }
}

/// `mypump_dietas.estructura`. Formato A: `macros_target` + `comidas`. Formato B: `tipos_dia[]`, cada uno con lo suyo
/// (ver `docs/SCHEMA_DIETA.md`). Las opciones A/B/C/D son POR COMIDA: el cliente combina desayuno A con almuerzo B.
public struct EstructuraDieta: Decodable, Sendable, Equatable {
    public var macrosTarget: Macros?
    public var comidas: [Comida]
    public var tiposDia: [TipoDia]

    enum CodingKeys: String, CodingKey { case macrosTarget = "macros_target", comidas, tiposDia = "tipos_dia" }

    public init(macrosTarget: Macros? = nil, comidas: [Comida] = [], tiposDia: [TipoDia] = []) {
        self.macrosTarget = macrosTarget; self.comidas = comidas; self.tiposDia = tiposDia
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        macrosTarget = try? c.decodeIfPresent(Macros.self, forKey: .macrosTarget)
        comidas = c.lista(Comida.self, .comidas)
        tiposDia = c.lista(TipoDia.self, .tiposDia)
    }
}

public struct TipoDia: Decodable, Sendable, Equatable {
    public var id: String
    public var nombre: String?
    public var macrosTarget: Macros?
    public var comidas: [Comida]

    enum CodingKeys: String, CodingKey { case id, nombre, macrosTarget = "macros_target", comidas }

    public init(id: String, nombre: String? = nil, macrosTarget: Macros? = nil, comidas: [Comida] = []) {
        self.id = id; self.nombre = nombre; self.macrosTarget = macrosTarget; self.comidas = comidas
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id) ?? ""
        nombre = c.texto(.nombre)
        macrosTarget = try? c.decodeIfPresent(Macros.self, forKey: .macrosTarget)
        comidas = c.lista(Comida.self, .comidas)
    }
}

public struct Comida: Decodable, Sendable, Equatable {
    public var id: String
    public var nombre: String?
    public var opciones: [Opcion]

    enum CodingKeys: String, CodingKey { case id, nombre = "name", opciones = "options" }

    public init(id: String, nombre: String? = nil, opciones: [Opcion] = []) {
        self.id = id; self.nombre = nombre; self.opciones = opciones
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id) ?? ""
        nombre = c.texto(.nombre)
        opciones = c.lista(Opcion.self, .opciones)
    }
}

public struct Opcion: Decodable, Sendable, Equatable {
    public var nombre: String?
    public var alimentos: [Alimento]

    enum CodingKeys: String, CodingKey { case nombre = "name", alimentos = "foods" }

    public init(nombre: String? = nil, alimentos: [Alimento] = []) { self.nombre = nombre; self.alimentos = alimentos }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = c.texto(.nombre)
        alimentos = c.lista(Alimento.self, .alimentos)
    }
}

/// Un alimento del plan. En `meals` del Cerebro y en FOOD_DB las macros son por 100 g; acá (en la estructura publicada)
/// son el TOTAL de esa `qty`, igual que en `food_data` de un swap. La qty de un contable va en unidades.
public struct Alimento: Decodable, Sendable, Equatable {
    public var nombre: String
    public var qty: Double?
    public var unidad: String?
    public var gramosPorUnidad: Double?
    public var kcal: Double?
    public var prot: Double?
    public var carb: Double?
    public var fat: Double?
    public var categoria: String?
    public var sustituible: Bool?

    enum CodingKeys: String, CodingKey {
        case nombre = "name", qty, unidad = "unit", gramosPorUnidad = "unitGrams", kcal, prot, carb, fat
        case categoria = "category", sustituible = "swappable"
    }

    public init(nombre: String, qty: Double? = nil, unidad: String? = nil, kcal: Double? = nil, prot: Double? = nil,
                carb: Double? = nil, fat: Double? = nil, categoria: String? = nil) {
        self.nombre = nombre; self.qty = qty; self.unidad = unidad; self.kcal = kcal; self.prot = prot
        self.carb = carb; self.fat = fat; self.categoria = categoria
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = c.texto(.nombre) ?? ""
        qty = c.decimal(.qty)
        unidad = c.texto(.unidad)
        gramosPorUnidad = c.decimal(.gramosPorUnidad)
        kcal = c.decimal(.kcal); prot = c.decimal(.prot); carb = c.decimal(.carb); fat = c.decimal(.fat)
        categoria = c.texto(.categoria)
        sustituible = c.booleano(.sustituible)
    }
}

public struct Macros: Decodable, Sendable, Equatable {
    public var kcal: Double?
    public var prot: Double?
    public var carb: Double?
    public var fat: Double?

    enum CodingKeys: String, CodingKey { case kcal, prot, carb, fat }

    public init(kcal: Double? = nil, prot: Double? = nil, carb: Double? = nil, fat: Double? = nil) {
        self.kcal = kcal; self.prot = prot; self.carb = carb; self.fat = fat
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kcal = c.decimal(.kcal); prot = c.decimal(.prot); carb = c.decimal(.carb); fat = c.decimal(.fat)
    }
}
