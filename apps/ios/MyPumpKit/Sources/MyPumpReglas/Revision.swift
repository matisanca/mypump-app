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
        guard let dFin = DiaCalendario.numero(fin) else { return nil }
        let vals = serie.filter { p in
            guard let d = DiaCalendario.numero(p.fecha) else { return false }
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
        guard let dHoy = DiaCalendario.numero(hoy), let m7 = media(serie, hasta: hoy, dias: 7),
              let m7prev = media(serie, hasta: DiaCalendario.texto(dHoy - 7), dias: 7) else { return nil }
        return ((m7 - m7prev) * 1000).jsEntero
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

    /// `Number.prototype.toFixed(1)`, exacto como JS.
    static func toFixed1(_ x: Double) -> String { NumeroJS.toFixed(x, 1) }
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
public enum DiaCalendario {
    public static func numero(_ f: String) -> Int? {
        let p = f.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
        guard let d = Formateadores.utc.date(from: c) else { return nil }
        return Int((d.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    public static func texto(_ n: Int) -> String {
        let c = Formateadores.utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(n) * 86_400))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// La semana de revisión y el aviso local (R2 de la 2.0.3). La semana termina el día de revisión del alumno (1 = lunes …
/// 7 = domingo; 7 es la semana ISO de siempre): su lunes es el lunes ISO de (fecha + (7 − día)), la misma cuenta que el
/// servidor. Vectores: apps/shared/vectores/aviso_revision.json.
public enum SemanaRevision {
    /// Lo que dice la pantalla de Revisión: un alumno no sabía si era diaria o semanal. Sin nombrar un día: cada alumno tiene el suyo.
    public static let explicacion = "La revisión es semanal: una vez por semana subís tus 3 fotos y completás el check. No hace falta hacerla todos los días."
    public static let diaPorDefecto = 7
    /// El aviso sale el día de revisión a las 11:00, hora del teléfono (es cuando se arma la ronda de Mati).
    public static let minutosAviso = 11 * 60

    /// Un día fuera de 1…7 (un dato raro) vale el domingo.
    public static func normalizado(_ dia: Int?) -> Int {
        guard let dia, (1...7).contains(dia) else { return diaPorDefecto }
        return dia
    }

    /// El lunes de la semana de revisión de `fecha`.
    public static func lunes(_ fecha: String, dia: Int = diaPorDefecto) -> String {
        guard let n = DiaCalendario.numero(fecha) else { return fecha }
        return FotosProgreso.lunes(DiaCalendario.texto(n + 7 - normalizado(dia)))
    }

    /// Completa: lo mismo que deja el badge de Revisión en cero (el check guardado y las tres fotos de la semana).
    public static func completa(checkinEnviado: Bool, posesDeLaSemana: Set<String>) -> Bool {
        FotosProgreso.pendientes(checkinEnviado: checkinEnviado, posesDeLaSemana: posesDeLaSemana).total == 0
    }

    /// El día del próximo aviso: el día de revisión que viene (hoy, si es ese día antes de las 11). Si la semana de
    /// revisión de hoy ya está completa y ese aviso cae en la misma semana, se saltea al de la semana siguiente: quien
    /// subió todo el sábado no recibe nada el domingo.
    public static func fechaAviso(hoy: String, minutos: Int, completa: Bool, dia: Int = diaPorDefecto) -> String? {
        guard let n = DiaCalendario.numero(hoy) else { return nil }
        let d = normalizado(dia)
        let dow = ((n + 3) % 7 + 7) % 7 + 1   // 1970-01-01 fue jueves: 1 = lunes … 7 = domingo
        var delta = ((d - dow) % 7 + 7) % 7
        if delta == 0 && minutos >= minutosAviso { delta = 7 }
        var aviso = n + delta
        if completa && lunes(DiaCalendario.texto(aviso), dia: d) == lunes(hoy, dia: d) { aviso += 7 }
        return DiaCalendario.texto(aviso)
    }
}

/// Fotos de progreso (cliente.html:7476-7962): tres poses por semana (lunes ISO), la racha de semanas completas, el
/// recordatorio semanal y el comparador antes/después (que espera a las 4 semanas: antes compara luz y retención de
/// líquido, no cambios reales).
public enum FotosProgreso {
    public static let avisoTitulo = "Tus fotos de la semana"
    public static let avisoCuerpo = "Esta semana todavía no subiste tus fotos. Sacalas en el mismo lugar y con la misma luz que siempre, con la misma ropa, el celu vertical a la altura del ombligo y a 2 o 3 metros. Frente, perfil y espalda. Así vemos bien cómo venís"

    /// El aviso de la pestaña Revisión: mientras falte alguna de las tres de esta semana (el mismo criterio del banner).
    /// Sin saber qué hay en el servidor no se dice nada: no se le puede decir «no subiste» a quien ya las subió.
    public static func mostrarAviso(cargadas: Bool, posesDeLaSemana: Set<String>) -> Bool {
        cargadas && posesDeLaSemana.count < 3
    }

    public static let poses: [(clave: String, etiqueta: String)] = [("frente", "Frente"), ("perfil", "Perfil"), ("espalda", "Espalda")]
    public static let maxPendientes = 3
    /// El servidor corta el body de más de 3 MB; el data URL se filtra antes de encolar.
    public static let maxCaracteres = 2_400_000

    /// `_lunesISO`: el lunes de la semana de esa fecha.
    public static func lunes(_ fecha: String) -> String {
        guard let n = DiaCalendario.numero(fecha) else { return fecha }
        // 1970-01-01 fue jueves: (n + 3) % 7 da 0 para el lunes.
        let dow = ((n + 3) % 7 + 7) % 7
        return DiaCalendario.texto(n - dow)
    }

    /// Las poses de esta semana: las del servidor más las que esperan subir.
    public static func posesDeLaSemana(_ fotos: [FotoProgreso], pendientes: [(pose: String, fecha: String)], semana: String) -> Set<String> {
        var s = Set(fotos.filter { $0.semanaLunes == semana }.map(\.pose))
        for p in pendientes where lunes(p.fecha) == semana { s.insert(p.pose) }
        return s
    }

    /// Las semanas con alguna foto, en orden.
    public static func semanas(_ fotos: [FotoProgreso]) -> [String] { Array(Set(fotos.map(\.semanaLunes))).sorted() }

    /// "🔥 N semanas seguidas": semanas con las tres poses, consecutivas hacia atrás desde la última completa.
    public static func racha(_ fotos: [FotoProgreso]) -> Int {
        var porSemana: [String: Set<String>] = [:]
        for f in fotos { porSemana[f.semanaLunes, default: []].insert(f.pose) }
        let completas = porSemana.keys.sorted().filter { porSemana[$0]?.count == 3 }
        guard let ultima = completas.last, let nUltima = DiaCalendario.numero(ultima) else { return 0 }
        var serie = 0
        for (i, s) in completas.enumerated().reversed() {
            if s == DiaCalendario.texto(nUltima - (completas.count - 1 - i) * 7) { serie += 1 } else { break }
        }
        return serie
    }

    /// Lo que falta de la semana (badge de Revisión y banner en las otras pestañas).
    public static func pendientes(checkinEnviado: Bool, posesDeLaSemana: Set<String>) -> (faltaCheck: Bool, faltanFotos: Bool, total: Int) {
        let faltaCheck = !checkinEnviado
        let faltanFotos = posesDeLaSemana.count < 3
        return (faltaCheck, faltanFotos, (faltaCheck ? 1 : 0) + (faltanFotos ? 1 : 0))
    }

    /// El texto del banner ("Te faltan tu check y tus fotos de la semana").
    public static func textoRecordatorio(faltaCheck: Bool, faltanFotos: Bool) -> String? {
        if faltaCheck && faltanFotos { return "Te faltan tu check y tus fotos de la semana" }
        if faltaCheck { return "Te falta tu check de la semana" }
        if faltanFotos { return "Te faltan tus fotos de la semana" }
        return nil
    }

    /// El pie del comparador: "8 semanas · -2,4 kg" (el peso es el primero cargado desde el lunes de cada semana).
    public static func resumenComparador(primera: String, ultima: String, peso: [PesoCorporal.Punto]) -> String {
        func pesoEn(_ sem: String) -> Double? { peso.filter { $0.fecha >= sem }.min { $0.fecha < $1.fecha }?.kg }
        let semDif = Int(jsRound(Double((DiaCalendario.numero(ultima) ?? 0) - (DiaCalendario.numero(primera) ?? 0)) / 7))
        var r = "\(semDif) semana\(semDif == 1 ? "" : "s")"
        if let p0 = pesoEn(primera), let p1 = pesoEn(ultima) {
            let d = p1 - p0
            r += " · \(d > 0 ? "+" : "")\(PesoCorporal.kg(d)) kg"
        }
        return r
    }
}
