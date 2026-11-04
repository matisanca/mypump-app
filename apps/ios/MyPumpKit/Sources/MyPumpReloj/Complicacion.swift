import Foundation
import MyPumpReglas

/// Lo que muestran las complicaciones del reloj: el próximo entreno y el descanso en curso. Lo escribe la app del reloj
/// (en el contenedor del App Group) cada vez que cambia algo, y la extensión de complicaciones solo lo lee.
public struct EstadoComplicacion: Codable, Equatable, Sendable {
    public static let archivo = "complicacion.json"

    /// «Tirón A — ancho»
    public var titulo: String?
    /// «3 de 6 ejercicios», «Hecho», «Próximo»
    public var detalle: String?
    public var hechos: Int
    public var total: Int
    /// ms: el fin del descanso que corre (nil = sin descanso).
    public var finDescanso: Double?
    /// s: el objetivo del descanso.
    public var objetivoDescanso: Double?
    public var actualizado: Double

    public init(titulo: String? = nil, detalle: String? = nil, hechos: Int = 0, total: Int = 0, finDescanso: Double? = nil,
                objetivoDescanso: Double? = nil, actualizado: Double = 0) {
        self.titulo = titulo; self.detalle = detalle; self.hechos = hechos; self.total = total
        self.finDescanso = finDescanso; self.objetivoDescanso = objetivoDescanso; self.actualizado = actualizado
    }

    /// Del estado de la sesión del reloj. Con el día hecho (o sin rutina para hoy) muestra el próximo entreno.
    public static func de(_ s: SesionReloj, ahora: Double) -> EstadoComplicacion {
        guard let r = s.rutina else { return EstadoComplicacion(titulo: nil, detalle: "Abrí Pump Team", actualizado: ahora) }
        let d = s.descansoEnCurso(ahora: ahora)
        let total = r.ejercicios.count, hechos = r.ejercicios.filter(\.terminado).count
        if s.todoHecho, let p = r.proximo {
            return EstadoComplicacion(titulo: TextoReloj.titulo(p.nombre), detalle: "Próximo", hechos: 0, total: p.ejercicios, actualizado: ahora)
        }
        let detalle = s.todoHecho ? "Hecho" : "\(hechos) de \(total) ejercicios"
        return EstadoComplicacion(titulo: TextoReloj.titulo(r.nombreDia), detalle: detalle, hechos: hechos, total: total,
                                  finDescanso: d.map(\.fin), objetivoDescanso: d.map(\.objetivo), actualizado: ahora)
    }

    public static func leer(_ url: URL) -> EstadoComplicacion? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EstadoComplicacion.self, from: d)
    }

    public func guardar(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// Textos del reloj.
public enum TextoReloj {
    /// "TIRÓN A — ANCHO" → "Tirón A — Ancho" (como `Bonito.titulo` del teléfono); lo que no viene en mayúsculas queda igual.
    public static func titulo(_ s: String) -> String { s == s.uppercased() ? s.localizedCapitalized : s }

    /// 22.5 → "22,5"; 80 → "80"
    public static func kg(_ k: Double?) -> String {
        guard let k else { return "—" }
        return JS.texto((k * 100).rounded() / 100).replacingOccurrences(of: ".", with: ",")
    }

    /// La línea de una serie de preparación: «16-20 × 20 kg», «5 × Barra sola», «5 reps».
    public static func preparacion(_ p: Preparacion.Serie) -> String {
        if let k = p.textoKg { return "\(p.reps) × \(p.barraSola ? k : "\(k) kg")" }
        return "\(p.reps) reps"
    }
}
