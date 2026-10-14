import Foundation
import MyPumpModelos

/// `normalizarDieta` (cliente.html:1842): lo que la web hace con la dieta publicada ANTES de mostrarla o indexarla.
/// - Se van las comidas sin ninguna opción con alimentos, y de las que quedan, las opciones vacías. Los swaps de comida
///   se guardan con el índice de la opción: sin esto una opción vacía en el medio corría los índices y lo reemplazado en
///   una app no se veía en la otra (y el anclaje podía borrar el swap de la otra).
/// - Sin `macros_target` con kcal > 0, el objetivo es la suma de la opción A de cada comida, redondeada.
/// - `tipos_dia: []` es lo mismo que no tenerlos.
public enum NormalizarDieta {
    public struct Resultado: Sendable {
        public let estructura: EstructuraDieta
        /// Hay al menos una comida en algún plan.
        public let usable: Bool
        /// Para el aviso "a tu plan le falta información" (no es para el cliente: es para que Mati lo corrija).
        public let problemas: [String]
    }

    public static func normalizar(_ entrada: EstructuraDieta) -> Resultado {
        var e = entrada
        var problemas: [String] = []
        func limpiar(_ comidas: [Comida], _ objetivo: Macros?) -> ([Comida], Macros) {
            let quedan = comidas.compactMap { c -> Comida? in
                let opciones = c.opciones.filter { !$0.alimentos.isEmpty }
                guard !opciones.isEmpty else {
                    problemas.append("\(c.nombre.flatMap { $0.isEmpty ? nil : $0 } ?? "Una comida"): sin opciones cargadas.")
                    return nil
                }
                var c = c
                c.opciones = opciones
                return c
            }
            if let m = objetivo, let k = m.kcal, k > 0 { return (quedan, m) }
            var kcal = 0.0, prot = 0.0, carb = 0.0, fat = 0.0
            for c in quedan {
                for a in c.opciones.first?.alimentos ?? [] {
                    kcal += oCero(a.kcal); prot += oCero(a.prot); carb += oCero(a.carb); fat += oCero(a.fat)
                }
            }
            problemas.append("El plan no traía el objetivo de calorías; se calculó con la opción A.")
            return (quedan, Macros(kcal: jsRound(kcal), prot: jsRound(prot), carb: jsRound(carb), fat: jsRound(fat)))
        }
        if e.tiposDia.isEmpty {
            (e.comidas, e.macrosTarget) = { let r = limpiar(e.comidas, e.macrosTarget); return (r.0, r.1) }()
            return Resultado(estructura: e, usable: !e.comidas.isEmpty, problemas: problemas)
        }
        e.tiposDia = e.tiposDia.map { t in
            var t = t
            let r = limpiar(t.comidas, t.macrosTarget)
            t.comidas = r.0
            t.macrosTarget = r.1
            return t
        }
        return Resultado(estructura: e, usable: e.tiposDia.contains { !$0.comidas.isEmpty }, problemas: problemas)
    }

    /// `Number(x) || 0`.
    private static func oCero(_ x: Double?) -> Double {
        guard let x, !x.isNaN else { return 0 }
        return x
    }
}
