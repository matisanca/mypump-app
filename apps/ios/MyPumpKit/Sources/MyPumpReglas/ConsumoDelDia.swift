import Foundation
import MyPumpModelos

/// Lo que el cliente marcó de una comida hoy: «✓ Comí» o «✗ Salté» (DIE-05) y, si la comió, qué alimentos dejó (DIE-06).
/// Una por (cliente, fecha, comida) en `mypump_comidas_marcadas`, la misma que escribe la web. Volvió en D25 (27-oct):
/// los clientes de 2.0.x no podían seguir lo que comían ni ver las calorías del día.
public struct MarcaComida: Codable, Equatable, Sendable {
    public enum Estado: String, Codable, Sendable { case comido, saltado }

    /// El nombre de la opción con que se marcó (el de la opción, o su letra si no tiene): lo comido se cuenta con esa,
    /// aunque después se mire otra.
    public var opcion: String?
    public var estado: Estado
    /// Los alimentos de esa opción que NO comió (índices), sin repetir y en orden.
    public var excluidos: [Int]

    public init(opcion: String?, estado: Estado, excluidos: [Int] = []) {
        self.opcion = opcion; self.estado = estado; self.excluidos = Self.normalizar(excluidos)
    }

    /// La fila del servidor. Un estado que no es «comido» ni «saltado» no es una marca (la web tampoco la cuenta).
    public init?(_ fila: ComidaMarcada) {
        guard let e = fila.estado.flatMap(Estado.init(rawValue:)) else { return nil }
        self.init(opcion: fila.opcionElegida, estado: e, excluidos: fila.foodsExcluidos)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        opcion = try? c.decodeIfPresent(String.self, forKey: .opcion)
        estado = try c.decode(Estado.self, forKey: .estado)
        excluidos = Self.normalizar((try? c.decodeIfPresent([Int].self, forKey: .excluidos)) ?? [])
    }

    static func normalizar(_ x: [Int]) -> [Int] { Array(Set(x.filter { $0 >= 0 })).sorted() }
}

/// «Consumido hoy» (DIE-07): lo comido según las marcas, contra el objetivo del día. Es `calcularConsumido` de la web
/// (vectores en `apps/shared/vectores/consumo_dia.json`) más lo que la web no conoce: los ajustes del día de D22
/// (`consumo_dia_ajustes.json`, generados acá; Android los tiene que dar igual).
public enum ConsumoDelDia {
    public struct Consumo: Equatable, Sendable {
        public var kcal = 0.0
        public var prot = 0.0
        public var carb = 0.0
        public var fat = 0.0
        /// Las comidas del día que cuentan: todas menos las que hoy no come («Hoy no la como»).
        public var comidas = 0
        /// Cuántas de esas marcó «Comí» y cuántas «Salté».
        public var hechas = 0
        public var salteadas = 0

        public init() {}
        public var macros: Macros { Macros(kcal: kcal, prot: prot, carb: carb, fat: fat) }
        /// Las que todavía no marcó.
        public var pendientes: Int { max(0, comidas - hechas - salteadas) }
    }

    /// La letra de una opción (0 = A).
    public static func letra(_ i: Int) -> String { String(UnicodeScalar(65 + max(0, min(i, 25))).map(Character.init) ?? "A") }

    /// El nombre con que se guarda la opción `i` al marcar: el suyo (como la web), o su letra si no tiene. La web guarda
    /// «A» para cualquier opción sin nombre (3 de 100 dietas publicadas): acá, la letra de la que se ve.
    public static func nombreOpcion(_ c: Comida, _ i: Int) -> String {
        if let n = c.opciones[safe: i]?.nombre, !n.isEmpty { return n }
        return letra(i)
    }

    /// La opción de una marca: la primera con ese nombre (como la web); si ninguna se llama así, la opción sin nombre con
    /// esa letra (la marcó una app); si no, la A.
    public static func indiceOpcion(_ c: Comida, nombre: String?) -> Int {
        guard let nombre, !nombre.isEmpty else { return 0 }
        if let i = c.opciones.firstIndex(where: { $0.nombre == nombre }) { return i }
        if let i = c.opciones.indices.first(where: { (c.opciones[$0].nombre ?? "").isEmpty && letra($0) == nombre }) { return i }
        return 0
    }

    /// La opción que hay que mostrar de una comida sin elegir otra: la que comió, si la marcó «Comí».
    public static func opcionDeLaMarca(_ c: Comida, _ m: MarcaComida?) -> Int? {
        guard let m, m.estado == .comido else { return nil }
        return indiceOpcion(c, nombre: m.opcion)
    }

    /// Las marcas por comida desde las filas del servidor (si una comida viene dos veces, vale la última, como la web).
    public static func marcas(_ filas: [ComidaMarcada]) -> [String: MarcaComida] {
        var r: [String: MarcaComida] = [:]
        for f in filas where !f.comidaId.isEmpty { r[f.comidaId] = MarcaComida(f) }
        return r
    }

    /// Lo comido hoy.
    /// - Las marcadas «Comí» con la opción de la marca, con sus reemplazos (`efectivo`) y, si hoy hay ajustes, con las
    ///   porciones de hoy (lo que le pasan las anteriores incluido), menos los alimentos que destildó.
    /// - «Salté» no suma. Las que hoy no come no suman ni cuentan entre las comidas, aunque tengan marca (la web no conoce
    ///   los ajustes: ahí cuentan).
    /// - Más las comidas libres del día.
    /// `vistas` es la opción que se ve de cada comida (las no comidas también importan: lo que se compensa de una a la
    /// siguiente depende de la opción). Sin ajustes, es exactamente lo de la web, con las sumas en el mismo orden.
    public static func calcular(_ comidas: [Comida], marcas: [String: MarcaComida], libres: [ComidaLibre],
                                ajustes: [String: AjusteComida] = [:], vistas: [String: Int] = [:],
                                efectivo: (_ comidaId: String, _ opcion: Int, _ idx: Int, _ original: Alimento) -> Alimento = { $3 })
        -> Consumo {
        let delDia = comidas.map { c -> AjustePorciones.ComidaDelDia in
            let elegida = opcionDeLaMarca(c, marcas[c.id]) ?? vistas[c.id] ?? ajustes[c.id]?.opcion ?? 0
            let o = c.opciones.isEmpty ? 0 : min(max(0, elegida), c.opciones.count - 1)
            let alimentos = (c.opciones[safe: o]?.alimentos ?? []).enumerated().map { efectivo(c.id, o, $0.offset, $0.element) }
            return AjustePorciones.ComidaDelDia(id: c.id, nombre: c.nombre ?? "", opcion: o, alimentos: alimentos)
        }
        let ajustadas = ajustes.isEmpty ? [:] : AjustePorciones.dia(delDia, ajustes: ajustes)
        var t = Consumo()
        for c in delDia {
            if ajustes[c.id]?.omitida == true { continue }
            t.comidas += 1
            guard let m = marcas[c.id] else { continue }
            guard m.estado == .comido else { t.salteadas += 1; continue }
            t.hechas += 1
            let excluidos = Set(m.excluidos)
            for (i, a) in (ajustadas[c.id]?.alimentos ?? c.alimentos).enumerated() where !excluidos.contains(i) {
                t.kcal += a.kcal ?? 0
                t.prot += a.prot ?? 0
                t.carb += a.carb ?? 0
                t.fat += a.fat ?? 0
            }
        }
        for l in libres {
            t.kcal += l.kcal ?? 0
            t.prot += l.prot ?? 0
            t.carb += l.carb ?? 0
            t.fat += l.fat ?? 0
        }
        return t
    }
}
