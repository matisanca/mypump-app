import Foundation

/// El permiso para la IA (D7, guía 5.1.2(i) de Apple; `supabase/migrations/nativa_002_consentimiento_ia.sql`). Cubre todo
/// lo que lee los datos del cliente con IA: el chat (Codex), la foto del plato o de la etiqueta (OpenAI) y la ronda del
/// domingo (Claude). Con un "no", el servidor no le pasa nada a ningún modelo: el chat lo contesta Mati, la foto no se
/// analiza y la ronda usa los respaldos sin IA.
public enum ConsentimientoIA {
    /// La decisión, en el disco de la cuenta (para el arranque sin red).
    public static let archivo = "consentimiento-ia.json"
    /// La clave de la cola: gana la última decisión.
    public static let clave = "consentimiento_ia"

    public struct Guardado: Codable, Equatable, Sendable {
        public let acepta: Bool
        public init(acepta: Bool) { self.acepta = acepta }
    }
}
