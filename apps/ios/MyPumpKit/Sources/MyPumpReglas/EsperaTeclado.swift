import Foundation

/// El OK del panel de carga cuando vuelve a verse al cerrarse el teclado (2.3.3, caso Sebastián del 19/11): mientras se
/// escribe el peso el panel se esconde, y al cerrarse el teclado aparece justo donde está el dedo. El toque que lo cerró
/// (o uno apurado justo después) no puede registrar la serie: durante `ms` el OK no toma toques. No se pone gris: el toque
/// se ignora sin aviso. Es la misma regla que `EsperaTrasTeclado` de Android, con el reloj de afuera (en milisegundos).
public struct EsperaTrasTeclado: Equatable, Sendable {
    public static let porDefecto: Double = 500
    public let ms: Double
    /// El panel está escondido (teclado arriba).
    public private(set) var oculto = false
    private var desde: Double?

    public init(ms: Double = Self.porDefecto) { self.ms = ms }

    /// Se llama cada vez que cambia si el panel se ve. Solo el paso de escondido a visible arranca la espera: repetir el
    /// mismo estado no la reinicia.
    public mutating func ver(oculto nuevo: Bool, ahora: Double) {
        if oculto && !nuevo { desde = ahora }
        oculto = nuevo
    }

    /// Si el OK puede registrar ahora.
    public func admite(ahora: Double) -> Bool {
        guard !oculto else { return false }
        guard let d = desde else { return true }
        return ahora - d >= ms
    }
}
