import Foundation
import MyPumpReglas

/// La última proporción conocida de cada clip, por id: al volver a cargarlo, el cuadro arranca con su forma y no salta del
/// 16:9 a la real. Se guarda en las preferencias (es poco y no es del cliente: ancho sobre alto de un video).
public struct ProporcionesVideo {
    static let clave = "guia.proporciones"
    /// Tope de clips guardados (una guía trae unos 20): si se pasa, se empieza de nuevo.
    static let tope = 300
    private let preferencias: UserDefaults

    public init(preferencias: UserDefaults = .standard) { self.preferencias = preferencias }

    private var todas: [String: Double] { preferencias.dictionary(forKey: Self.clave) as? [String: Double] ?? [:] }

    public func proporcion(_ id: String) -> Double? {
        todas[id].flatMap { ReglasVideo.proporcion(ancho: $0, alto: 1) }
    }

    static let claveRecuadros = "guia.recuadros"

    /// La zona útil detectada del clip (por id y url: si el clip se vuelve a exportar, se mide de nuevo). `.entero` es
    /// «ya se midió y no tiene franjas»; nil, «no se midió».
    public func recuadro(_ id: String, url: URL) -> RecuadroVideo? {
        guard let v = (preferencias.dictionary(forKey: Self.claveRecuadros) as? [String: [Double]])?[Self.clave(id, url)], v.count == 4,
              v.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }), v[2] > 0, v[3] > 0 else { return nil }
        return RecuadroVideo(x: v[0], y: v[1], ancho: v[2], alto: v[3])
    }

    public func guardar(_ r: RecuadroVideo, para id: String, url: URL) {
        guard !id.isEmpty else { return }
        var t = preferencias.dictionary(forKey: Self.claveRecuadros) as? [String: [Double]] ?? [:]
        if t.count >= Self.tope, t[Self.clave(id, url)] == nil { t = [:] }
        t[Self.clave(id, url)] = [r.x, r.y, r.ancho, r.alto]
        preferencias.set(t, forKey: Self.claveRecuadros)
    }

    /// Borra todo lo medido (las pruebas de interfaz).
    public func olvidarTodo() {
        preferencias.removeObject(forKey: Self.clave)
        preferencias.removeObject(forKey: Self.claveRecuadros)
    }

    private static func clave(_ id: String, _ url: URL) -> String { "\(id)|\(url.absoluteString)" }

    public func guardar(_ p: Double, para id: String) {
        guard !id.isEmpty, ReglasVideo.proporcion(ancho: p, alto: 1) != nil else { return }
        var t = todas
        if let viejo = t[id], abs(viejo - p) < 0.001 { return }
        if t.count >= Self.tope, t[id] == nil { t = [:] }
        t[id] = p
        preferencias.set(t, forKey: Self.clave)
    }
}
