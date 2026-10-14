import Foundation

extension Double {
    /// `Int(x)` sin riesgo para mostrar: NaN o infinito valen 0 y lo de más de ±10^15 se acota. `Int()` de Swift cierra
    /// la app con un valor fuera de rango, y un plan con un número absurdo (ya pasó: macros corruptas de julio) no puede
    /// tirar abajo la pantalla. Redondea al más cercano.
    public var enteroSeguro: Int {
        guard isFinite else { return 0 }
        return Int(Swift.max(-1e15, Swift.min(1e15, rounded())))
    }

    /// `Math.round` de JS, sin riesgo.
    public var jsEntero: Int {
        let r = jsRound(self)
        guard r.isFinite else { return 0 }
        return Int(Swift.max(-1e15, Swift.min(1e15, r)))
    }
}
