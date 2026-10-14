import Foundation
import MyPumpModelos

/// La card de peso de Revisión (cliente.html:7330-7464): la serie diaria (la carga manual gana sobre el reloj), la
/// media móvil de 7 días y la diferencia de esa media contra la de la semana anterior, en gramos. El rango objetivo NO
/// se muestra al cliente (lo interpreta Mati).
public enum PesoCorporal {
    public struct Punto: Equatable, Sendable {
        public let fecha: String
        public let kg: Double
        public init(fecha: String, kg: Double) { self.fecha = fecha; self.kg = kg }
    }

    /// `_pesoSerie`: un punto por fecha, mayor a 0, en orden ascendente. Si en una fecha hay manual y de un reloj,
    /// gana el manual; entre dos del mismo tipo, el primero que vino.
    public static func serie(_ filas: [FilaSalud]) -> [Punto] {
        var porFecha: [String: FilaSalud] = [:]
        var orden: [String] = []
        for r in filas where r.tipo == "peso_kg" {
            if let prev = porFecha[r.fecha] {
                if prev.fuente != "manual" && r.fuente == "manual" { porFecha[r.fecha] = r }
            } else {
                porFecha[r.fecha] = r
                orden.append(r.fecha)
            }
        }
        return orden.compactMap { f -> Punto? in
            guard let r = porFecha[f], let v = r.valor, v > 0 else { return nil }
            return Punto(fecha: f, kg: v)
        }
        .sorted { $0.fecha < $1.fecha }
    }

    /// `_pesoMedia`: la media de los puntos con fecha en (fin − días, fin].
    public static func media(_ serie: [Punto], hasta fin: String, dias: Int) -> Double? {
        guard let dFin = Dia.numero(fin) else { return nil }
        let vals = serie.filter { p in
            guard let d = Dia.numero(p.fecha) else { return false }
            return d > dFin - dias && d <= dFin
        }.map(\.kg)
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }

    /// La línea del gráfico: la media de 7 días en cada punto (o el punto si no hay media).
    public static func lineaMedia(_ serie: [Punto]) -> [Punto] {
        serie.map { Punto(fecha: $0.fecha, kg: media(serie, hasta: $0.fecha, dias: 7) ?? $0.kg) }
    }

    /// Diferencia en gramos de la media de 7 días de hoy contra la de hace una semana (`deltaG`), o nil.
    public static func deltaSemanal(_ serie: [Punto], hoy: String) -> Int? {
        guard let dHoy = Dia.numero(hoy), let m7 = media(serie, hasta: hoy, dias: 7),
              let m7prev = media(serie, hasta: Dia.texto(dHoy - 7), dias: 7) else { return nil }
        return Int(jsRound((m7 - m7prev) * 1000))
    }

    /// "+350 g" / "-1,2 kg" (la parte en negrita de "Esta semana: … vs la semana pasada").
    public static func textoDelta(_ g: Int) -> String {
        let signo = g > 0 ? "+" : ""
        if abs(g) >= 1000 { return "\(signo)\(toFixed1(Double(g) / 1000).replacingOccurrences(of: ".", with: ",")) kg" }
        return "\(signo)\(g) g"
    }

    /// `v.toFixed(1).replace('.', ',')`.
    public static func kg(_ v: Double) -> String { toFixed1(v).replacingOccurrences(of: ".", with: ",") }

    /// Lo que escribe el cliente: coma o punto, entre 30 y 300 kg, redondeado a 100 g. Fuera de rango, nil.
    public static func leer(_ texto: String) -> Double? {
        guard let v = Double(texto.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
              v.isFinite, v >= 30, v <= 300 else { return nil }
        return jsRound(v * 10) / 10
    }

    /// `Number.prototype.toFixed(1)`: los empates se van lejos del cero.
    static func toFixed1(_ x: Double) -> String {
        let n = (abs(x) * 10).rounded(.toNearestOrAwayFromZero)
        let s = String(format: "%.1f", n / 10)
        return x < 0 && n != 0 ? "-" + s : s
    }
}

/// El check de la semana (CHECKIN_METRICAS): cuatro escalas de 1 a 5 y una nota opcional.
public enum CheckinSemanal {
    public struct Metrica: Equatable, Sendable {
        public let clave: String
        public let etiqueta: String
        public let bajo: String
        public let alto: String
    }

    public static let metricas: [Metrica] = [
        Metrica(clave: "energia", etiqueta: "Energía", bajo: "muy baja", alto: "excelente"),
        Metrica(clave: "descanso", etiqueta: "Descanso", bajo: "dormí mal", alto: "dormí bien"),
        Metrica(clave: "hambre", etiqueta: "Hambre", bajo: "sin hambre", alto: "mucha"),
        Metrica(clave: "adherencia", etiqueta: "Adherencia", bajo: "me costó", alto: "la seguí"),
    ]

    /// "Faltan: Energía, Hambre", o nil si están las cuatro.
    public static func faltan(_ valores: [String: Int]) -> String? {
        let f = metricas.filter { (valores[$0.clave] ?? 0) == 0 }.map(\.etiqueta)
        return f.isEmpty ? nil : "Faltan: \(f.joined(separator: ", "))"
    }
}

/// Mi Día: el ícono y el texto de la racha (renderMydayStreak).
public enum RachaTexto {
    public static func icono(_ n: Int) -> String { n >= 7 ? "🔥" : n >= 3 ? "⚡" : n >= 1 ? "✨" : "💤" }
}

/// Días de calendario como número (días desde 1970-01-01), para comparar fechas "YYYY-MM-DD" sin zonas horarias.
public enum Dia {
    public static func numero(_ f: String) -> Int? {
        let p = f.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: c) else { return nil }
        return Int((d.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    public static func texto(_ n: Int) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(n) * 86_400))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
