import Foundation
import MyPumpModelos

/// El alimento al que se le puso una cantidad a mano. La dieta se vuelve a publicar con el mismo id (013): si en esa
/// posición queda otro alimento u otra unidad, la cantidad no vale (60 g de avena no son 60 g de aceite).
public struct AnclaAlimento: Codable, Equatable, Sendable {
    public var nombre: String
    public var unidad: String?

    public init(nombre: String, unidad: String?) { self.nombre = nombre; self.unidad = unidad }
    public init(_ a: Alimento) { self.init(nombre: a.nombre, unidad: a.unidad) }

    /// El mismo alimento: el nombre sin espacios de más ni mayúsculas, y la misma unidad (g, gr y gramos son una).
    public func coincide(con a: Alimento) -> Bool {
        Self.normal(nombre) == Self.normal(a.nombre) && Self.unidadNormal(unidad) == Self.unidadNormal(a.unidad)
    }

    static func normal(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    static func unidadNormal(_ u: String?) -> String {
        let n = normal(u ?? "")
        if ["", "g", "gr", "grs", "gramo", "gramos"].contains(n) { return "g" }
        if n == "cc" { return "ml" }
        return n
    }
}

/// Lo que el cliente cambió de una comida en un día (feedback del 20-oct: «si tengo más hambre en una comida, agregar
/// cuántas calorías más quiero y que recalcule las porciones; después restarlas en la siguiente», y Emilio García
/// Álvarez: «hoy no fui a entrenar, saco el pre-entreno… cómo puedo jugar con los gramos»). No es «Comí / Salté» (D10):
/// es el plan del día, ajustado por el cliente.
public struct AjusteComida: Codable, Equatable, Sendable {
    /// Kcal que se suman (o restan) a esta comida, de a `AjustePorciones.paso`.
    public var deltaKcal: Int
    /// Lo que esta comida se aparta del plan se compensa en la siguiente.
    public var compensar: Bool
    /// Hoy no la come.
    public var omitida: Bool
    /// La opción (0 = A) a la que aplican las cantidades a mano: si el cliente cambia de opción, no valen.
    public var opcion: Int
    /// Cantidades puestas a mano, por índice del alimento en la opción, en la unidad del plan (g o unidades).
    public var cantidades: [String: Double]
    /// A qué alimento corresponde cada cantidad (las pone `AjustePorciones.anclar` al guardar). Sin ancla, vale.
    public var anclas: [String: AnclaAlimento]

    public init(deltaKcal: Int = 0, compensar: Bool = true, omitida: Bool = false, opcion: Int = 0,
                cantidades: [String: Double] = [:], anclas: [String: AnclaAlimento] = [:]) {
        self.deltaKcal = deltaKcal; self.compensar = compensar; self.omitida = omitida; self.opcion = opcion
        self.cantidades = cantidades; self.anclas = anclas
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deltaKcal = (try? c.decode(Int.self, forKey: .deltaKcal)) ?? 0
        compensar = (try? c.decode(Bool.self, forKey: .compensar)) ?? true
        omitida = (try? c.decode(Bool.self, forKey: .omitida)) ?? false
        opcion = (try? c.decode(Int.self, forKey: .opcion)) ?? 0
        cantidades = ((try? c.decode([String: Double].self, forKey: .cantidades)) ?? [:]).filter { $0.value.isFinite && $0.value >= 0 }
        anclas = (try? c.decode([String: AnclaAlimento].self, forKey: .anclas)) ?? [:]
    }

    /// Sin nada que cambie la comida: se borra.
    public var neutro: Bool { deltaKcal == 0 && cantidades.isEmpty && !omitida }
}

/// Las porciones de una comida (y del día) con los ajustes del cliente. Puro: lo usan las vistas y los tests, igual en
/// iOS y en Android (vectores en `apps/shared/vectores/ajuste_porciones.json`).
public enum AjustePorciones {
    /// De a cuánto se suma o se resta.
    public static let paso = 50
    /// Ni menos de un cuarto ni más del triple de lo del plan: más allá ya no es la misma comida (para no comerla, «Hoy
    /// no la como»).
    public static let factorMinimo = 0.25
    public static let factorMaximo = 3.0

    public struct ComidaDelDia: Sendable, Equatable {
        public let id: String
        public let nombre: String
        /// La opción elegida (0 = A).
        public let opcion: Int
        /// Los alimentos de esa opción como se ven hoy (con los reemplazos).
        public let alimentos: [Alimento]
        public init(id: String, nombre: String, opcion: Int, alimentos: [Alimento]) {
            self.id = id; self.nombre = nombre; self.opcion = opcion; self.alimentos = alimentos
        }
    }

    public struct ComidaAjustada: Sendable, Equatable {
        public let alimentos: [Alimento]
        /// Kcal del plan (sin ajustes) y las de hoy.
        public let kcalPlan: Double
        public let kcal: Double
        /// Lo que puso el cliente en esta comida.
        public let deltaPropio: Int
        public let omitida: Bool
        /// Lo que le llega de las comidas anteriores (negativo: hay que comer menos) y de cuáles.
        public let compensacion: Double
        public let compensaDe: [String]
        /// Lo que le llegó y no pudo absorber (no la come, nada se puede escalar o llegó al tope): pasa a la siguiente.
        public let noAbsorbido: Double
        /// Índices de los alimentos que cambiaron respecto del plan.
        public let cambiados: Set<Int>
        /// Lo que la comida se apartó del plan por el cliente (kcal, ya redondeadas las porciones): es lo que se compensa
        /// en la siguiente. Cero si solo recibe; sin comerla, menos todo el plan.
        public let propio: Double
        /// Hay que mostrarla como ajustada (por el cliente o por lo que le llega).
        public var ajustada: Bool { omitida || !cambiados.isEmpty }
        /// Lo que tomó de las anteriores.
        public var absorbido: Double { compensacion - noAbsorbido }
    }

    /// Las de peso van de a 5 g (de a 1 si son menos de 20 g); las contables, de a media unidad.
    public static func esPeso(_ unidad: String?) -> Bool {
        let u = (unidad ?? "g").lowercased().trimmingCharacters(in: .whitespaces)
        return ["g", "gr", "grs", "gramo", "gramos", "ml", "cc", ""].contains(u)
    }

    public static func redondear(_ q: Double, unidad: String?) -> Double {
        guard q.isFinite, q > 0 else { return 0 }
        if esPeso(unidad) { return q < 20 ? max(1, jsRound(q)) : max(5, jsRound(q / 5) * 5) }
        return max(0.5, jsRound(q * 2) / 2)
    }

    /// De a cuánto cambia el botón de un alimento: 5 g (10 g desde 100 g) o media unidad.
    public static func pasoCantidad(_ a: Alimento) -> Double {
        guard esPeso(a.unidad) else { return 0.5 }
        return (a.qty ?? 0) >= 100 ? 10 : 5
    }

    /// El mismo alimento con otra cantidad: las macros, proporcionales (son el TOTAL de la qty del plan).
    public static func conCantidad(_ a: Alimento, _ qty: Double) -> Alimento {
        guard let q0 = a.qty, q0 > 0, qty.isFinite, qty >= 0 else { return a }
        let f = qty / q0
        var b = a
        b.qty = qty
        b.kcal = a.kcal.map { jsRound($0 * f) }
        b.prot = a.prot.map { jsRound($0 * f * 10) / 10 }
        b.carb = a.carb.map { jsRound($0 * f * 10) / 10 }
        b.fat = a.fat.map { jsRound($0 * f * 10) / 10 }
        return b
    }

    public static func kcal(_ alimentos: [Alimento]) -> Double { alimentos.reduce(0) { $0 + ($1.kcal ?? 0) } }

    /// Los alimentos que se pueden agrandar o achicar: con cantidad y kcal, y no puestos a mano.
    static func escalables(_ alimentos: [Alimento], fijos: Set<Int>) -> [Int] {
        alimentos.indices.filter { !fijos.contains($0) && (alimentos[$0].kcal ?? 0) > 0 && (alimentos[$0].qty ?? 0) > 0 }
    }

    /// El escalón fino de una cantidad, el mismo del redondeo: 1 g por debajo de 20 g, 5 g arriba; media unidad.
    static func escalon(_ q: Double, unidad: String?) -> Double {
        esPeso(unidad) ? (q < 20 ? 1 : 5) : 0.5
    }

    /// Una comida: primero las cantidades a mano; después, si hay `deltaKcal`, el resto de los alimentos por el mismo
    /// factor (así se mantiene la proporción de macros del plan), redondeado a porciones que se puedan servir. El
    /// redondeo de las contables salta fuerte (medio huevo son 39 kcal): al final se afina de a un escalón por vez, en el
    /// alimento que más acerque al objetivo, hasta que ninguno lo mejore.
    public static func escalar(_ alimentos: [Alimento], deltaKcal: Double, cantidades: [Int: Double] = [:]) -> [Alimento] {
        var r = alimentos.enumerated().map { i, a in cantidades[i].map { conCantidad(a, $0) } ?? a }
        guard deltaKcal.isFinite, deltaKcal != 0 else { return r }
        let libres = escalables(alimentos, fijos: Set(cantidades.keys))
        let base = libres.reduce(0.0) { $0 + (alimentos[$1].kcal ?? 0) }
        guard base > 0 else { return r }
        let f = factor(base, deltaKcal)
        for i in libres {
            let a = alimentos[i]
            r[i] = conCantidad(a, redondear((a.qty ?? 0) * f, unidad: a.unidad))
        }
        afinar(&r, alimentos, libres: libres, objetivo: base * f, sube: deltaKcal > 0)
        return r
    }

    /// El factor de los alimentos libres para sumarles `delta` kcal, dentro de los topes.
    static func factor(_ base: Double, _ delta: Double) -> Double {
        min(factorMaximo, max(factorMinimo, (base + delta) / base))
    }

    /// Acerca la suma de `libres` a `objetivo` moviendo un escalón por vez, sin salir de los topes de cada alimento
    /// (un cuarto y el triple de lo del plan) ni cruzar el plan al revés de lo pedido: si se sumó, ninguno queda por
    /// debajo de lo del plan; si se restó, ninguno por arriba. Gana el que deja el error más chico; si empatan, el primero.
    static func afinar(_ r: inout [Alimento], _ plan: [Alimento], libres: [Int], objetivo: Double, sube: Bool) {
        for _ in 0..<60 {
            let actual = libres.reduce(0.0) { $0 + (r[$1].kcal ?? 0) }
            let resto = objetivo - actual
            guard abs(resto) >= 1 else { return }
            var mejor: (i: Int, qty: Double, error: Double)?
            for i in libres {
                let a = plan[i], q0 = a.qty ?? 0, q = r[i].qty ?? 0
                let paso = escalon(resto > 0 ? q : max(0, q - 1), unidad: a.unidad)
                let nueva = resto > 0 ? q + paso : q - paso
                let minimo = max(redondear(q0 * factorMinimo, unidad: a.unidad), esPeso(a.unidad) ? 1 : 0.5, sube ? q0 : 0)
                let maximo = min(redondear(q0 * factorMaximo, unidad: a.unidad), sube ? .infinity : q0)
                guard nueva >= minimo, nueva <= maximo else { continue }
                let cambio = (conCantidad(a, nueva).kcal ?? 0) - (r[i].kcal ?? 0)
                let error = abs(resto - cambio)
                if error < abs(resto), mejor == nil || error < mejor!.error { mejor = (i, nueva, error) }
            }
            guard let m = mejor else { return }
            r[m.i] = conCantidad(plan[m.i], m.qty)
        }
    }

    /// Las cantidades a mano que valen hoy: de la opción elegida, en una posición que existe y del mismo alimento (sin
    /// ancla, recién puesta en la hoja, vale).
    public static func cantidadesValidas(_ c: ComidaDelDia, _ aj: AjusteComida?) -> [Int: Double] {
        guard let aj, aj.opcion == c.opcion else { return [:] }
        var r: [Int: Double] = [:]
        for (k, v) in aj.cantidades {
            guard let i = Int(k), c.alimentos.indices.contains(i), v.isFinite, v >= 0 else { continue }
            if let ancla = aj.anclas[k], !ancla.coincide(con: c.alimentos[i]) { continue }
            r[i] = v
        }
        return r
    }

    /// Al guardar: cada cantidad a mano con el alimento al que va, y afuera las que ya no valen.
    public static func anclar(_ a: AjusteComida, en c: ComidaDelDia) -> AjusteComida {
        var r = a
        let validas = cantidadesValidas(c, a)
        r.cantidades = Dictionary(uniqueKeysWithValues: validas.map { (String($0.key), $0.value) })
        r.anclas = Dictionary(uniqueKeysWithValues: validas.keys.map { (String($0), AnclaAlimento(c.alimentos[$0])) })
        return r
    }

    /// Las kcal de lo que se agranda o se achica parejo (sin lo puesto a mano): sobre eso se miden los topes.
    public static func baseEscalable(_ c: ComidaDelDia, _ aj: AjusteComida?) -> Double {
        escalables(c.alimentos, fijos: Set(cantidadesValidas(c, aj).keys)).reduce(0) { $0 + (c.alimentos[$1].kcal ?? 0) }
    }

    /// El día: cada comida con su ajuste y lo que le pasan las anteriores.
    /// - Lo que una comida se aparta del plan POR EL CLIENTE (sumó, restó, cambió gramos o no la come) va a la siguiente
    ///   si eligió compensar.
    /// - Lo que le llega y no puede absorber (no la come, no tiene nada que escalar o llegó al tope de un cuarto o el
    ///   triple) sigue de largo a la otra. Lo propio de la comida va primero; lo que llega entra en lo que queda.
    /// - La última no pasa nada: lo que le quede sin absorber es `sinCompensar` (la hoja lo avisa).
    public static func dia(_ comidas: [ComidaDelDia], ajustes: [String: AjusteComida]) -> [String: ComidaAjustada] {
        var r: [String: ComidaAjustada] = [:]
        var arrastre = 0.0
        var origenes: [String] = []
        for c in comidas {
            let aj = ajustes[c.id]
            let llega = arrastre, deQuien = origenes
            let plan = kcal(c.alimentos)
            let cantidades = cantidadesValidas(c, aj)
            let omitida = aj?.omitida == true
            let delta = Double(omitida ? 0 : aj?.deltaKcal ?? 0)
            let als: [Alimento]
            let noAbsorbido: Double
            if omitida {
                als = c.alimentos.map { ($0.qty ?? 0) > 0 ? conCantidad($0, 0) : $0 }
                noAbsorbido = llega
            } else {
                let base = escalables(c.alimentos, fijos: Set(cantidades.keys)).reduce(0.0) { $0 + (c.alimentos[$1].kcal ?? 0) }
                if base > 0 {
                    als = escalar(c.alimentos, deltaKcal: delta + llega, cantidades: cantidades)
                    noAbsorbido = jsRound(llega - base * (factor(base, delta + llega) - factor(base, delta)))
                } else {
                    als = escalar(c.alimentos, deltaKcal: 0, cantidades: cantidades)
                    noAbsorbido = llega
                }
            }
            let hoy = kcal(als)
            let cambiados = Set(c.alimentos.indices.filter { als[$0].qty != c.alimentos[$0].qty })
            // Lo que se apartó del plan por el cliente: lo de hoy menos el plan y lo que sí absorbió de las anteriores. Sin
            // nada propio (solo recibe), es cero: el redondeo de lo que absorbió no se le pasa a la siguiente.
            let propio = (aj?.neutro ?? true) ? 0 : jsRound(hoy - plan - (llega - noAbsorbido))
            r[c.id] = ComidaAjustada(alimentos: als, kcalPlan: plan, kcal: hoy, deltaPropio: Int(delta), omitida: omitida,
                                     compensacion: llega, compensaDe: llega != 0 ? deQuien : [], noAbsorbido: noAbsorbido,
                                     cambiados: cambiados, propio: propio)
            var siguiente = noAbsorbido
            var nuevosOrigenes = noAbsorbido != 0 ? deQuien : []
            if let aj, aj.compensar, propio != 0 {
                siguiente -= propio
                nuevosOrigenes.append(c.nombre)
            }
            arrastre = siguiente
            origenes = siguiente != 0 ? nuevosOrigenes : []
        }
        return r
    }

    /// La comida que recibe lo que sale de `id`: la primera de las siguientes que se come y tiene algo que escalar.
    public static func destino(_ comidas: [ComidaDelDia], ajustes: [String: AjusteComida], despuesDe id: String) -> ComidaDelDia? {
        guard let i = comidas.firstIndex(where: { $0.id == id }) else { return nil }
        return comidas[(i + 1)...].first { ajustes[$0.id]?.omitida != true && baseEscalable($0, ajustes[$0.id]) > 0 }
    }

    public struct CambioEnOtra: Equatable, Sendable {
        public let id: String
        public let nombre: String
        /// Cuánto cambia (kcal) y en cuánto queda.
        public let kcal: Double
        public let queda: Double
    }

    /// Lo que el ajuste de `id` le hace al resto del día, comparado con el día sin ese ajuste: cuánto cambia cada una de
    /// las siguientes y cuánto queda sin compensar al final. Es lo que explica la hoja.
    public static func efecto(_ comidas: [ComidaDelDia], ajustes: [String: AjusteComida],
                              de id: String) -> (cambios: [CambioEnOtra], sinCompensar: Double) {
        guard let i = comidas.firstIndex(where: { $0.id == id }) else { return ([], 0) }
        var sin = ajustes
        sin[id] = nil
        let con = dia(comidas, ajustes: ajustes), antes = dia(comidas, ajustes: sin)
        let cambios = comidas[(i + 1)...].compactMap { c -> CambioEnOtra? in
            guard let a = con[c.id], let b = antes[c.id], abs(a.kcal - b.kcal) >= 1 else { return nil }
            return CambioEnOtra(id: c.id, nombre: c.nombre, kcal: a.kcal - b.kcal, queda: a.kcal)
        }
        return (cambios, sinCompensar(comidas, con) - sinCompensar(comidas, antes))
    }

    /// Lo que llegó a la última comida y no pudo absorber (no había otra después).
    public static func sinCompensar(_ comidas: [ComidaDelDia], _ dia: [String: ComidaAjustada]) -> Double {
        guard let ultima = comidas.last, let u = dia[ultima.id] else { return 0 }
        return u.noAbsorbido
    }
}
