import Foundation
import MyPumpModelos

/// Un swap de comida como lo guarda el teléfono (`STATE.foodSwaps[key]` de la web): `current` es el `food_data`
/// tal cual va y viene del servidor.
public struct SwapLocal: Codable, Equatable, Sendable {
    public var original: JSONValue?
    public var current: JSONValue

    public init(original: JSONValue? = nil, current: JSONValue) { self.original = original; self.current = current }
}

/// Una escritura que la hidratación pide encolar (`swap` o `swap_del`), con la misma clave que usa la web.
public struct OpSwap: Equatable, Sendable {
    public let kind: String
    public let clave: String
    public let comidaId: String
    public let optIdx: Int
    public let foodIdx: Int
    public let food: JSONValue?

    public var payload: JSONValue {
        var o: [String: JSONValue] = [:]
        o["comidaId"] = .texto(comidaId)
        o["optIdx"] = .numero(Double(optIdx))
        o["foodIdx"] = .numero(Double(foodIdx))
        if let food { o["food"] = food }
        return .objeto(o)
    }
}

public enum SwapsDeComida {
    /// `swap_<DIETA_ID>_<comida>_<opt>_<food>`: la clave del mapa local, el dedupe de la cola y la key de la web.
    public static func clave(dietaId: String, comidaId: String, optIdx: Int, foodIdx: Int) -> String {
        "swap_\(dietaId)_\(comidaId)_\(optIdx)_\(foodIdx)"
    }

    /// `_conAncla`: el sustituto con el alimento que reemplaza adentro, en `_orig` (nombre, cantidad, unidad).
    /// Como `JSON.stringify`, lo que no tiene valor no se escribe.
    public static func conAncla(_ sustituto: JSONValue, original: Alimento) -> JSONValue {
        var o: [String: JSONValue] = [:]
        if case .objeto(let s) = sustituto { o = s }
        var ancla: [String: JSONValue] = ["name": .texto(original.nombre)]
        if let q = original.qty { ancla["qty"] = .numero(q) }
        if let u = original.unidad { ancla["unit"] = .texto(u) }
        o["_orig"] = .objeto(ancla)
        return .objeto(o)
    }

    /// `_foodsEnPosicion`: los alimentos de esa posición en el plan activo primero y después en los demás tipos de día.
    public static func enPosicion(_ dieta: EstructuraDieta, tipoActivo: String?, comidaId: String, optIdx: Int, foodIdx: Int) -> [Alimento] {
        let planes: [[Comida]]
        if dieta.tiposDia.isEmpty {
            planes = [dieta.comidas]
        } else {
            let activo = dieta.tiposDia.first { $0.id == tipoActivo }
            let resto = dieta.tiposDia.filter { $0.id != activo?.id }
            planes = ([activo].compactMap { $0 } + resto).map(\.comidas)
        }
        return planes.compactMap { comidas in
            comidas.first { $0.id == comidaId }?.opciones[safe: optIdx]?.alimentos[safe: foodIdx]
        }
    }

    public struct Hidratacion: Equatable, Sendable {
        /// El mapa resultante (lo que se muestra y se guarda en el teléfono).
        public var swaps: [String: SwapLocal]
        /// Lo que hay que encolar, en orden.
        public var operaciones: [OpSwap]
        /// Se puede marcar "migrado" ya (la rama de migración lo decide recién después de drenar la cola).
        public var marcarMigrado: Bool
        /// La rama de migración encoló: hay que drenar y marcar migrado solo si no quedó ningún swap pendiente.
        public var migrando: Bool
    }

    /// Port de la mitad de `hydrateSwapsAndCustomFoodsFromBackend` que trata los swaps (cliente.html:5956-6027) y de
    /// `_anclarOSacarSwap` (5900). Devuelve nil si `remotos` es nil: no se pudo preguntar (red) y no se toca nada —
    /// tratarlo como "cero swaps" volvía a subir lo que el cliente o Mati habían borrado.
    ///
    /// - Parameter pendientes: clave → kind de lo que está en la cola sin subir. Lo que el cliente hizo gana.
    public static func hidratar(remotos: [FoodSwap]?, locales: [String: SwapLocal], dietaId: String,
                                pendientes: [String: String], yaMigrado: Bool,
                                enPosicion: (String, Int, Int) -> [Alimento]) -> Hidratacion? {
        guard let remotos else { return nil }
        var swaps = locales
        var ops: [OpSwap] = []
        var migrando = false

        if remotos.isEmpty && !locales.isEmpty && yaMigrado {
            // El servidor es la fuente de verdad y está vacío: lo local se borró en otro lado. Queda solo lo pendiente.
            swaps = locales.filter { pendientes[$0.key] != nil }
        } else if remotos.isEmpty && !locales.isEmpty {
            // Migración, una vez por dispositivo: lo local de antes del backend sube POR LA COLA.
            let patron = "^swap_\(NSRegularExpression.escapedPattern(for: dietaId))_(.+?)_(\\d+)_(\\d+)$"
            let re = try? NSRegularExpression(pattern: patron)
            for (clave, swap) in locales.sorted(by: { $0.key < $1.key }) where swap.current != .null {
                guard let re, let m = re.firstMatch(in: clave, range: NSRange(clave.startIndex..., in: clave)),
                      let rc = Range(m.range(at: 1), in: clave), let ro = Range(m.range(at: 2), in: clave),
                      let rf = Range(m.range(at: 3), in: clave), let o = Int(clave[ro]), let f = Int(clave[rf]) else { continue }
                ops.append(OpSwap(kind: "swap", clave: clave, comidaId: String(clave[rc]), optIdx: o, foodIdx: f, food: swap.current))
            }
            migrando = !ops.isEmpty
        } else if !remotos.isEmpty {
            var nuevos: [String: SwapLocal] = [:]
            for s in remotos {
                let clave = clave(dietaId: dietaId, comidaId: s.comidaId, optIdx: s.optIdx, foodIdx: s.foodIdx)
                nuevos[clave] = SwapLocal(original: nil, current: s.foodData)
                if let op = anclarOSacar(&nuevos, clave: clave, fila: s, pendientes: pendientes, enPosicion: enPosicion) { ops.append(op) }
            }
            for (clave, local) in locales where pendientes[clave] != nil { nuevos[clave] = local }   // local más nuevo, sin subir
            for (clave, kind) in pendientes where kind == "swap_del" { nuevos[clave] = nil }        // una reversión pendiente no resucita
            swaps = nuevos
        }
        let marcar = !remotos.isEmpty || swaps.isEmpty
        return Hidratacion(swaps: swaps, operaciones: ops, marcarMigrado: marcar, migrando: migrando)
    }

    /// `_anclarOSacarSwap`: un swap remoto legado (sin `_orig`) se ancla al alimento actual y se re-sube; uno anclado que
    /// ya no coincide con NINGÚN tipo de día se saca y se borra en el backend. Lo pendiente del cliente no se toca.
    static func anclarOSacar(_ mapa: inout [String: SwapLocal], clave: String, fila: FoodSwap, pendientes: [String: String],
                             enPosicion: (String, Int, Int) -> [Alimento]) -> OpSwap? {
        guard let actual = mapa[clave]?.current, actual != .null else { return nil }
        if pendientes[clave] != nil { return nil }
        let candidatos = enPosicion(fila.comidaId, fila.optIdx, fila.foodIdx)
        guard let primero = candidatos.first else { return nil }   // posición inexistente: no se aplica de todos modos
        guard let ancla = actual["_orig"], AnclajeSwaps.esVerdadero(ancla) else {
            let anclado = conAncla(actual, original: primero)
            mapa[clave]?.current = anclado
            return OpSwap(kind: "swap", clave: clave, comidaId: fila.comidaId, optIdx: fila.optIdx, foodIdx: fila.foodIdx, food: anclado)
        }
        let h = AnclajeSwaps.huella(ancla: ancla)
        if !candidatos.contains(where: { AnclajeSwaps.huella($0) == h }) {
            mapa[clave] = nil
            return OpSwap(kind: "swap_del", clave: clave, comidaId: fila.comidaId, optIdx: fila.optIdx, foodIdx: fila.foodIdx, food: nil)
        }
        return nil
    }

    /// `getEffectiveFood`: el alimento a mostrar en esa posición (el sustituto si el swap aplica).
    public static func efectivo(_ original: Alimento, swap: SwapLocal?, comidaId: String?,
                                enPosicion: () -> [Alimento]) -> (alimento: Alimento, sustituido: Bool) {
        guard let swap, AnclajeSwaps.aplica(foodData: swap.current, original: original, comidaId: comidaId, enPosicion: enPosicion),
              let a = try? JSONDecoder().decode(Alimento.self, from: JSONEncoder().encode(swap.current)) else {
            return (original, false)
        }
        return (a, true)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
