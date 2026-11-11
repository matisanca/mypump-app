import Foundation

/// «Mi gimnasio y mi técnica» (simplificar, OK de Mati del 11/11): Tu gimnasio (con «Entreno en casa» adentro) y Mi
/// técnica en una sola pantalla, con un renglón grande al final de Entreno. Cada bloque va con su palanca de siempre
/// (`gimnasio_fotos`, `casa`, `tecnica_video`): acá no hay palancas nuevas. Mismos textos en iPhone y Android
/// (`nativa-evidencia/mi-salud/DECISIONES.md`, iOS simplificar 4).
public enum DondeEntreno {
    public static let tituloAmbos = "Mi gimnasio y mi técnica"
    public static let tituloGimnasio = "Mi gimnasio"
    public static let tituloTecnica = "Mi técnica"
    public static let bajadaAmbos = "Las fotos de tu gimnasio y los videos de tu técnica"
    public static let bajadaGimnasio = "Las fotos de tu gimnasio o lo que tenés en casa"
    public static let bajadaTecnica = "Tus videos y lo que te respondió Mati"
    /// El botón del renglón cuando hay una respuesta nueva: la abre directo.
    public static let verRespuesta = "Ver lo que te respondió Mati"
    public static let vacio = "Por ahora no hay nada para mostrar acá."
    public static let cerrar = "Cerrar"

    /// El título del renglón y de la pantalla, según lo que haya. nil: no hay ninguno de los dos.
    public static func titulo(gimnasio: Bool, tecnica: Bool) -> String? {
        switch (gimnasio, tecnica) {
        case (true, true): tituloAmbos
        case (true, false): tituloGimnasio
        case (false, true): tituloTecnica
        case (false, false): nil
        }
    }

    public static func bajada(gimnasio: Bool, tecnica: Bool) -> String? {
        switch (gimnasio, tecnica) {
        case (true, true): bajadaAmbos
        case (true, false): bajadaGimnasio
        case (false, true): bajadaTecnica
        case (false, false): nil
        }
    }

    /// Cuántos días una respuesta de técnica sigue «nueva» en el renglón de Entreno.
    public static let diasRespuestaReciente = 7

    /// La respuesta de Mati más nueva, publicada en los últimos 7 días. Sin fecha legible, no cuenta (la lista la sigue
    /// mostrando).
    public static func respuestaReciente(_ envios: [EnvioTecnica], ahora: Date = Date()) -> EnvioTecnica? {
        envios
            .filter { $0.estado == .publicado && $0.devolucion != nil }
            .compactMap { e in e.publicadoEn.flatMap(ReglasGuia.instante).map { (envio: e, en: $0) } }
            .filter { ahora.timeIntervalSince($0.en) < Double(diasRespuestaReciente) * 86_400 }
            .max { $0.en < $1.en }?
            .envio
    }
}
