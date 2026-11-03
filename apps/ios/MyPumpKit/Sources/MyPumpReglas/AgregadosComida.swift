import Foundation
import MyPumpModelos

/// Las macros de un alimento cada 100 g (las de la base y las de los alimentos propios).
public struct MacrosPor100: Codable, Equatable, Sendable {
    public var kcal: Double
    public var p: Double
    public var c: Double
    public var g: Double

    public init(kcal: Double, p: Double, c: Double, g: Double) { self.kcal = kcal; self.p = p; self.c = c; self.g = g }

    public init(from decoder: Decoder) throws {
        let x = try decoder.container(keyedBy: CodingKeys.self)
        func n(_ k: CodingKeys) throws -> Double {
            let v = try x.decode(Double.self, forKey: k)
            guard v.isFinite, v >= 0, v <= 10000 else { throw DecodingError.dataCorruptedError(forKey: k, in: x, debugDescription: "fuera de rango") }
            return v
        }
        kcal = try n(.kcal); p = try n(.p); c = try n(.c); g = try n(.g)
    }
}

/// Un alimento que el cliente sumó a una comida del plan (2.0.3, D1: «comí 80 g de puré de zapallo y no lo pude cargar»,
/// «el huevo lo tuve que poner en extras y no en la misma comida»). Vive en el ajuste de esa comida y de ese día
/// (`AjusteComida.agregados`), con las macros ya calculadas por la cantidad: así la ficha y el brief lo leen sin la base.
public struct AlimentoAgregado: Codable, Equatable, Sendable {
    public enum Origen: String, Codable, Sendable { case base, propio }

    public var nombre: String
    /// La cantidad en `unidad`: «g» o una medida casera («unidad», «palma», «taza»…).
    public var cantidad: Double
    public var unidad: String
    /// Los gramos de una `unidad` que no es «g» (para volver a editarla igual). nil en gramos.
    public var gramosUnidad: Double?
    /// Los gramos de la cantidad (lo mismo que `cantidad` si es en gramos).
    public var gramos: Double
    /// Por la cantidad: kcal enteras y macros con un decimal, como `AjustePorciones.conCantidad`.
    public var kcal: Double
    public var p: Double
    public var c: Double
    public var g: Double
    /// Para recalcular al cambiar la cantidad sin volver a buscar el alimento (un propio se puede borrar).
    public var por100: MacrosPor100
    public var origen: Origen
    /// Cuándo se agregó (ms): lo identifica dentro de la comida.
    public var ts: Int64

    enum CodingKeys: String, CodingKey {
        case nombre, cantidad, unidad, gramosUnidad, gramos, kcal, p, c, g, por100, origen, ts = "_ts"
    }

    public init(nombre: String, cantidad: Double, unidad: String, gramosUnidad: Double?, gramos: Double, kcal: Double,
                p: Double, c: Double, g: Double, por100: MacrosPor100, origen: Origen, ts: Int64) {
        self.nombre = nombre; self.cantidad = cantidad; self.unidad = unidad; self.gramosUnidad = gramosUnidad
        self.gramos = gramos; self.kcal = kcal; self.p = p; self.c = c; self.g = g; self.por100 = por100
        self.origen = origen; self.ts = ts
    }

    /// Estricto: lo que no tiene sentido (sin nombre, cantidad cero, macros negativas o absurdas) no es un agregado y el
    /// ajuste lo descarta (solo ese, no el ajuste entero). Igual en Android.
    public init(from decoder: Decoder) throws {
        let x = try decoder.container(keyedBy: CodingKeys.self)
        func n(_ k: CodingKeys, max: Double) throws -> Double {
            let v = try x.decode(Double.self, forKey: k)
            guard v.isFinite, v >= 0, v <= max else { throw DecodingError.dataCorruptedError(forKey: k, in: x, debugDescription: "fuera de rango") }
            return v
        }
        nombre = try x.decode(String.self, forKey: .nombre).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty else { throw DecodingError.dataCorruptedError(forKey: .nombre, in: x, debugDescription: "sin nombre") }
        cantidad = try n(.cantidad, max: 100000)
        guard cantidad > 0 else { throw DecodingError.dataCorruptedError(forKey: .cantidad, in: x, debugDescription: "cero") }
        unidad = ((try? x.decodeIfPresent(String.self, forKey: .unidad)) ?? nil).flatMap { $0.isEmpty ? nil : $0 } ?? "g"
        gramosUnidad = (try? x.decodeIfPresent(Double.self, forKey: .gramosUnidad)).flatMap { $0 }.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        gramos = try n(.gramos, max: 100000)
        kcal = try n(.kcal, max: 30000)
        p = try n(.p, max: 10000); c = try n(.c, max: 10000); g = try n(.g, max: 10000)
        por100 = try x.decode(MacrosPor100.self, forKey: .por100)
        origen = (try? x.decode(Origen.self, forKey: .origen)) ?? .base
        let t = try x.decode(Double.self, forKey: .ts)
        guard t.isFinite, t >= 0, t < 1e15 else { throw DecodingError.dataCorruptedError(forKey: .ts, in: x, debugDescription: "ts") }
        ts = Int64(t)
    }

    public func encode(to encoder: Encoder) throws {
        var x = encoder.container(keyedBy: CodingKeys.self)
        try x.encode(nombre, forKey: .nombre)
        try x.encode(cantidad, forKey: .cantidad)
        try x.encode(unidad, forKey: .unidad)
        try x.encodeIfPresent(gramosUnidad, forKey: .gramosUnidad)
        try x.encode(gramos, forKey: .gramos)
        try x.encode(kcal, forKey: .kcal)
        try x.encode(p, forKey: .p)
        try x.encode(c, forKey: .c)
        try x.encode(g, forKey: .g)
        try x.encode(por100, forKey: .por100)
        try x.encode(origen, forKey: .origen)
        try x.encode(ts, forKey: .ts)
    }

    /// Como alimento de la comida (para las sumas, lo consumido y las filas).
    public var alimento: Alimento {
        Alimento(nombre: nombre, qty: cantidad, unidad: unidad, kcal: kcal, prot: p, carb: c, fat: g)
    }

    /// El alimento del que salió, para volver a abrir la hoja de cantidad.
    public var candidato: AgregadosComida.Candidato {
        AgregadosComida.Candidato(nombre: nombre, por100: por100, unidad: gramosUnidad != nil ? unidad : nil,
                                  gramosPorUnidad: gramosUnidad, origen: origen)
    }
}

/// Las cuentas de los alimentos agregados a una comida (D1) y de la hoja de cantidad (D2). Puro: lo usan las vistas y los
/// tests, igual en iOS y en Android (vectores en `apps/shared/vectores/agregados_comida.json`).
public enum AgregadosComida {
    /// Topes (la fila del día no puede pasar los 16000 bytes de nativa_004): por comida, por día y el tamaño del JSON.
    public static let maximoPorComida = 8
    public static let maximoPorDia = 24
    public static let maximoBytes = 12000
    /// Lo más que se lee de una comida (una fila rota no puede traer mil).
    static let maximoAlLeer = 50
    public static let largoNombre = 80

    /// Un alimento que se puede agregar: de la base (food-db) o propio del cliente. Macros por 100 g.
    public struct Candidato: Equatable, Sendable {
        public let nombre: String
        public let por100: MacrosPor100
        /// La medida casera que trae la base («unidad», «rebanada»…), con sus gramos.
        public let unidad: String?
        public let gramosPorUnidad: Double?
        public let origen: AlimentoAgregado.Origen

        public init(nombre: String, por100: MacrosPor100, unidad: String?, gramosPorUnidad: Double?, origen: AlimentoAgregado.Origen) {
            self.nombre = nombre; self.por100 = por100; self.unidad = unidad; self.gramosPorUnidad = gramosPorUnidad; self.origen = origen
        }

        public init(_ a: AlimentoBase) {
            self.init(nombre: a.nombre, por100: MacrosPor100(kcal: a.kcal, p: a.prot, c: a.carb, g: a.fat),
                      unidad: a.unidad, gramosPorUnidad: a.gramosPorUnidad, origen: a.esPropio ? .propio : .base)
        }
    }

    /// Una forma de contar la cantidad: «g» (gramos = 1) o una medida casera con sus gramos.
    public struct Medida: Equatable, Sendable, Hashable {
        public let nombre: String
        public let gramos: Double
        public init(nombre: String, gramos: Double) { self.nombre = nombre; self.gramos = gramos }
        public static let gramo = Medida(nombre: "g", gramos: 1)
        public var esGramo: Bool { nombre == "g" }
    }

    /// Las medidas de un alimento: siempre gramos y, si la hay, una casera. Primero la de la base (huevo: «unidad» de
    /// 60 g); si no, la de la porción casera de la web (`porcionReferencia`: palma, taza, puño, cucharada…).
    public static func medidas(_ c: Candidato) -> [Medida] {
        if let u = c.unidad, let gu = c.gramosPorUnidad, gu.isFinite, gu > 0 {
            let n = PorcionCasera.normalizar(u)
            if !["", "g", "gr", "grs", "gramo", "gramos", "ml", "cc"].contains(n) {
                let nombre = ["u", "un", "uni", "unid", "unidad", "unidades"].contains(n) ? "unidad" : PorcionCasera.singular(n)
                return [.gramo, Medida(nombre: nombre, gramos: gu)]
            }
        }
        if let m = medidaCasera(c.nombre) { return [.gramo, m] }
        return [.gramo]
    }

    /// La medida casera de un alimento que va en gramos, con los mismos gramos con que la web arma «la mano»
    /// (`PorcionCasera.referencia`). nil si la web no da una (o es «libre», como las hojas verdes).
    public static func medidaCasera(_ nombre: String) -> Medida? {
        let name = PorcionCasera.normalizar(nombre)
        guard !name.isEmpty else { return nil }
        func has(_ kw: String...) -> Bool { kw.contains { name.contains($0) } }
        if has("mani", "cacahuate") && has("mantequilla", "manteca", "crema", "pasta", "untable") { return Medida(nombre: "cucharada", gramos: 16) }
        if has("leche", "bebida", "jugo", "zumo", "licuado", "gaseosa", "kefir", "caldo", "infusion", "yogur bebible", "chocolatada") {
            return Medida(nombre: "vaso", gramos: 200)
        }
        if has("aceite", "oliva", "ghee") || has("manteca", "mantequilla") { return Medida(nombre: "cucharada", gramos: 15) }
        if has("almendra", "nuez", "nueces", "castana", "avellana", "pistacho", "mani", "cacahuate", "frutos secos",
               "semilla", "girasol", "chia", "lino", "mix de") { return Medida(nombre: "puñado", gramos: 30) }
        if has("whey", "proteina en polvo", "caseina") { return Medida(nombre: "scoop", gramos: 30) }
        if has("atun") { return Medida(nombre: "lata", gramos: 120) }
        if has("pollo", "pechuga", "carne", "nalga", "bife", "cerdo", "lomo", "pescado", "merluza", "pavo", "salmon",
               "cuadril", "cuadrada", "peceto", "asado", "bondiola", "milanesa", "tira", "magra", "roast", "colita") {
            // La palma es de 100 g cocido; en crudo, lo que pesa antes de perder el 25 %.
            return Medida(nombre: "palma", gramos: has("crud") ? jsRound(100 / 0.75) : 100)
        }
        if has("arroz", "fideo", "pasta", "avena", "quinoa", "polenta", "tallarin", "noqui", "cuscus", "couscous",
               "trigo", "mostacho", "spaghetti", "ravioli") {
            if has("avena") { return Medida(nombre: "taza", gramos: 80) }
            if has("cocid", "hervid", "al dente") { return Medida(nombre: "taza", gramos: 175) }
            if has("fideo", "pasta", "tallarin", "noqui", "mostacho", "spaghetti", "ravioli", "cuscus", "couscous") {
                return Medida(nombre: "taza en crudo", gramos: 100)
            }
            if has("quinoa") { return Medida(nombre: "taza en crudo", gramos: 170) }
            if has("polenta") { return Medida(nombre: "taza en crudo", gramos: 150) }
            return Medida(nombre: "taza en crudo", gramos: 185)
        }
        if has("lenteja", "garbanzo", "poroto", "alubia", "frijol", "chaucha seca") { return Medida(nombre: "taza", gramos: 190) }
        if has("papa", "patata", "batata", "boniato") && !has("papaya") {
            // Puré: va por taza (la de los cocidos); la papa entera, por unidad mediana.
            if has("pure") { return Medida(nombre: "taza", gramos: 175) }
            return Medida(nombre: "mediana", gramos: 150)
        }
        if has("lechuga", "rucula", "radicheta", "escarola", "hojas verdes", "mix de hojas") { return nil }
        if has("brocoli", "brecol", "coliflor", "calabaza", "zapallo", "zanahoria", "espinaca", "morron", "pimiento",
               "berenjena", "zucchini", "zapallito", "repollo", "remolacha", "chaucha", "cebolla", "tomate", "verdura") {
            return Medida(nombre: "puño", gramos: 90)
        }
        if has("ricota", "untable", "yogur", "yoghurt", "queso blanco", "queso crema", "cottage", "requeson") {
            return Medida(nombre: "taza", gramos: 245)
        }
        if has("frutilla", "arandano", "mora", "frambuesa", "frutos rojos", "berries") { return Medida(nombre: "puñado", gramos: 80) }
        if has("palta", "aguacate") { return Medida(nombre: "palta", gramos: 140) }
        if has("pan") && !has("rallado") { return Medida(nombre: "rebanada", gramos: 30) }
        if has("tostada") { return Medida(nombre: "tostada", gramos: has("arroz") ? 9 : 25) }
        return nil
    }

    /// La búsqueda de la hoja de agregar, sobre la base con los propios: cada palabra de la consulta (sin tildes ni
    /// mayúsculas) tiene que estar en el nombre. Primero los que empiezan con la primera palabra; después, el orden de la
    /// base. Como mucho `limite`. Sin consulta, nada.
    public static func buscar(_ base: BaseAlimentos, _ consulta: String, limite: Int = 60) -> [AlimentoBase] {
        let palabras = SustitucionAlimentos.normalizar(consulta).split(whereSeparator: { $0 == " " || $0 == "/" }).map(String.init)
        guard let primera = palabras.first else { return [] }
        let todos = base.alimentos.filter { a in palabras.allSatisfy { a.normalizado.contains($0) } }
        let empiezan = todos.filter { $0.normalizado.hasPrefix(primera) }
        let resto = todos.filter { !$0.normalizado.hasPrefix(primera) }
        return Array((empiezan + resto).prefix(limite))
    }

    /// La medida con que abre la hoja: la de la base si la trae (1 huevo), si no 100 g.
    public static func inicial(_ c: Candidato) -> (cantidad: Double, medida: Medida) {
        let ms = medidas(c)
        if c.unidad != nil, ms.count > 1 { return (1, ms[1]) }
        return (100, .gramo)
    }

    /// De a cuánto cambian − y +: 5 g (10 g desde 100 g) o media medida.
    public static func paso(_ cantidad: Double, _ m: Medida) -> Double {
        m.esGramo ? (cantidad >= 100 ? 10 : 5) : 0.5
    }

    /// Lo que se puede poner: de 1 g a 2 kg, o de media a 50 medidas, en porciones servibles (gramos enteros, medias).
    public static func acotar(_ cantidad: Double, _ m: Medida) -> Double {
        guard cantidad.isFinite else { return m.esGramo ? 1 : 0.5 }
        if m.esGramo { return min(2000, max(1, jsRound(cantidad))) }
        return min(50, max(0.5, jsRound(cantidad * 2) / 2))
    }

    public static func subir(_ cantidad: Double, _ m: Medida) -> Double {
        let p = paso(cantidad, m)
        // Desde una cantidad fuera de la grilla (37 g), el + lleva a la siguiente de la grilla (40 g).
        let siguiente = m.esGramo ? ((cantidad / p).rounded(.down) + 1) * p : cantidad + p
        return acotar(siguiente, m)
    }

    public static func bajar(_ cantidad: Double, _ m: Medida) -> Double {
        let p = paso(max(0, cantidad - 1), m)
        let anterior = m.esGramo ? ((cantidad / p).rounded(.up) - 1) * p : cantidad - p
        return acotar(anterior, m)
    }

    /// El agregado con esa cantidad: los gramos y las macros por la cantidad (kcal enteras, macros con un decimal).
    public static func agregado(_ c: Candidato, cantidad: Double, medida m: Medida, ts: Int64) -> AlimentoAgregado {
        let q = acotar(cantidad, m)
        let gramos = jsRound(q * m.gramos * 10) / 10
        let f = gramos / 100
        let nombre = String(c.nombre.trimmingCharacters(in: .whitespacesAndNewlines).prefix(largoNombre))
        return AlimentoAgregado(nombre: nombre, cantidad: q, unidad: m.nombre, gramosUnidad: m.esGramo ? nil : m.gramos,
                                gramos: gramos, kcal: jsRound(c.por100.kcal * f), p: jsRound(c.por100.p * f * 10) / 10,
                                c: jsRound(c.por100.c * f * 10) / 10, g: jsRound(c.por100.g * f * 10) / 10,
                                por100: c.por100, origen: c.origen, ts: ts)
    }

    /// Por qué no se puede agregar uno más (nil: se puede). `ajustes` es el día con el agregado ya puesto.
    public static func motivoNoEntra(_ ajustes: [String: AjusteComida], comidaId: String) -> String? {
        if (ajustes[comidaId]?.agregados.count ?? 0) > maximoPorComida {
            return "Llegaste a \(maximoPorComida) alimentos agregados en esta comida."
        }
        if ajustes.values.reduce(0, { $0 + $1.agregados.count }) > maximoPorDia {
            return "Llegaste a \(maximoPorDia) alimentos agregados en el día."
        }
        if bytes(ajustes) > maximoBytes { return "No entran más alimentos agregados hoy." }
        return nil
    }

    /// Lo que pesa el día en JSON (lo que la base acota a 16000 bytes).
    public static func bytes(_ ajustes: [String: AjusteComida]) -> Int {
        (try? JSONEncoder().encode(ajustes))?.count ?? Int.max
    }

    /// Los agregados de la comida como alimentos (los de una comida que hoy no se come no cuentan, pero quedan guardados).
    public static func alimentos(_ aj: AjusteComida?) -> [Alimento] {
        guard let aj, !aj.omitida else { return [] }
        return aj.agregados.map(\.alimento)
    }

    /// Los tildes de «Comí» de una comida son índices: los del plan (0..<n) y después los agregados (n + j). Al borrar el
    /// agregado `j`, su tilde se va y los de los siguientes bajan uno (si no, se destildaba otro alimento).
    public static func excluidosTrasBorrar(_ excluidos: [Int], alimentosPlan n: Int, borrado j: Int) -> [Int] {
        let k = n + j
        return excluidos.compactMap { $0 == k ? nil : ($0 > k ? $0 - 1 : $0) }
    }

    /// Los agregados de una comida en el `resumen` que lee la ficha (nativa_004): nombre, cantidad, gramos y macros.
    /// Vacío, la clave no va (el renglón queda como antes).
    public static func resumen(_ aj: AjusteComida?) -> [JSONValue] {
        (aj?.agregados ?? []).map {
            .objeto(["nombre": .texto($0.nombre), "cantidad": .numero($0.cantidad), "unidad": .texto($0.unidad),
                     "gramos": .numero($0.gramos), "kcal": .numero($0.kcal), "p": .numero($0.p), "c": .numero($0.c),
                     "g": .numero($0.g)])
        }
    }
}
