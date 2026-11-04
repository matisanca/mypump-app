import Foundation

/// La fila de `mypump_suplementacion(p_token)` (2.1.0, `docs/NATIVA_CONTRATO.md` sección 10): la suplementación natural
/// del cliente, con la misma forma que la de «Tu guía» (`SuplementacionGuia`: `dia`, `items`, `tomas`, `estado`…).
/// Token inválido o sin suplementación: cero filas, sin error.
///
/// Tolerante como el resto: nunca tira al decodificar (una forma rota deja `suplementacion` en nil y la pestaña no
/// aparece), y con un `esquema` mayor que 1 se toma lo que se entienda; los campos desconocidos se ignoran.
public struct RespuestaSuplementacion: Codable, Equatable, Sendable {
    public var suplementacion: SuplementacionGuia?
    /// `'final'` (la de después de la llamada) o `'pre'`.
    public var fase: String?
    /// timestamptz ISO de la última escritura.
    public var actualizado: String?
    /// La versión del contrato; hoy 1.
    public var esquema: Int

    public init(suplementacion: SuplementacionGuia?, fase: String? = nil, actualizado: String? = nil, esquema: Int = 1) {
        self.suplementacion = suplementacion; self.fase = fase; self.actualizado = actualizado; self.esquema = esquema
    }

    enum CodingKeys: String, CodingKey { case suplementacion, fase, actualizado, esquema }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suplementacion = (try? c.decodeIfPresent(SuplementacionGuia.self, forKey: .suplementacion)) ?? nil
        fase = c.texto(.fase)
        actualizado = c.texto(.actualizado)
        esquema = c.entero(.esquema) ?? 1
    }

    /// Hay algo que mostrar: al menos un ítem con nombre.
    public var hay: Bool { suplementacion.map { !$0.vacia } ?? false }
}
