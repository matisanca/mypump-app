import Foundation

/// 2.3.1: «¿Cómo se lee?» de la cabecera de Dieta. Texto corto en pasos, para que cualquiera lo entienda. Mismos textos
/// en Android y la web (`apps/shared/vectores/como_se_lee.json`). `video`: lugar para un video opcional (sin URL no se
/// muestra el botón).
public enum ComoSeLee {
    public static let boton = "¿Cómo se lee?"
    public static let titulo = "Cómo se lee tu dieta"
    public static let pasos = [
        "Cada tarjeta es una comida del día, con lo que tenés que comer y cuántas calorías suma.",
        "Si una comida tiene opciones (A, B…), elegí una sola: cualquiera te sirve igual.",
        "Cuando comés, tocá «Comí». Arriba se va sumando lo que comiste en el día.",
        "¿No conseguís un alimento? Tocá el botón de las dos flechas y elegí otro parecido.",
    ]
    public static let verVideo = "Ver el video"
    public static let cerrar = "Entendido"
    public static let video: String? = nil

    /// La URL del video, solo si es https.
    public static func urlVideo(_ v: String? = video) -> URL? {
        guard let t = v?.trimmingCharacters(in: .whitespaces), t.hasPrefix("https://"),
              !t.contains(where: { $0.isWhitespace || "\"'<>".contains($0) }),
              let u = URL(string: t), u.scheme == "https", u.host?.isEmpty == false else { return nil }
        return u
    }
}
