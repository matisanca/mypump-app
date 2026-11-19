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

/// La semana de revisión y el aviso local (R2 de la 2.0.3). La semana es SIEMPRE de lunes a domingo (`FotosProgreso.lunes`):
/// el día de revisión del alumno (1 = lunes … 7 = domingo) solo mueve el aviso, no corre la semana. Vectores:
/// apps/shared/vectores/aviso_revision.json.
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

    /// La línea de la pestaña Revisión para quien no revisa el domingo. Con el domingo (lo de siempre) no se dice nada.
    public static func textoDia(_ dia: Int?) -> String? {
        let d = normalizado(dia)
        guard d != diaPorDefecto else { return nil }
        return "Tu día de revisión es el \(["lunes", "martes", "miércoles", "jueves", "viernes", "sábado"][d - 1])"
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
        if completa && FotosProgreso.lunes(DiaCalendario.texto(aviso)) == FotosProgreso.lunes(hoy) { aviso += 7 }
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

    // MARK: - El peso del comparador (2.3.3, el arreglo de la web: cliente.html `TuCambio.pesaje` y `cambio`)
    //
    // Antes era «el primero cargado desde el lunes», sin tope, sobre los 60 días de Salud: con una primera foto más vieja
    // tomaba un peso de meses después (Emmanuel veía +0,7 kg en vez de −4,6). Ahora el peso va en una serie aparte que
    // llega hasta la primera foto (`ModeloRevision.serieDelComparador`) y cada foto toma el de su semana:
    // · El de la misma semana (lunes a domingo): el primero cargado en ella.
    // · Si esa semana no tiene peso, el más cercano dentro de 7 días antes del lunes o 7 después del domingo. Empate: el de
    //   después (como la regla vieja, que miraba hacia adelante).
    // · Si tampoco hay, el pie dice solo «N semanas»: nunca un peso inventado.
    // Los casos están en apps/shared/vectores/tucambio.json (los corren iOS, Android y la web).

    /// Hasta cuántos días fuera de su semana se busca el peso de una foto.
    public static let pesoDiasCerca = 7
    /// Guarda de unidades: un cambio de más del 25 % del peso de la primera foto es imposible (libras contra kilos es un
    /// salto de más del 50 %). No hay tope por semana a propósito: con tirzepatida se bajan 3 a 4 kg en dos semanas.
    public static let guardaFraccion = 0.25

    /// El pesaje elegido para una semana de fotos: el día (`DiaCalendario.numero`) y los kg, o nil.
    static func pesaje(_ semana: String, _ peso: [PesoCorporal.Punto]) -> (n: Int, kg: Double)? {
        guard let l = DiaCalendario.numero(semana) else { return nil }
        let puntos = peso.compactMap { p -> (n: Int, kg: Double)? in
            guard let n = DiaCalendario.numero(p.fecha), p.kg > 0 else { return nil }
            return (n, p.kg)
        }
        var mejor: (n: Int, kg: Double)?
        var dist = Int.max
        for p in puntos.enumerated().sorted(by: { ($0.element.n, $0.offset) < ($1.element.n, $1.offset) }).map(\.element) {
            let x = p.n < l ? l - p.n : (p.n > l + 6 ? p.n - (l + 6) : 0)
            if x > pesoDiasCerca { continue }
            if x < dist || (x == dist && x > 0) { mejor = p; dist = x }
        }
        return mejor
    }

    /// El peso de una semana de fotos, o nil.
    public static func pesoDeSemana(_ semana: String, _ peso: [PesoCorporal.Punto]) -> Double? { pesaje(semana, peso)?.kg }

    /// Las semanas entre las dos fotos y el cambio de peso, o `kg: nil` si no se puede decir.
    public static func cambioComparador(primera: String, ultima: String, peso: [PesoCorporal.Punto]) -> (semanas: Int, kg: Double?) {
        let semanas = Int(jsRound(Double((DiaCalendario.numero(ultima) ?? 0) - (DiaCalendario.numero(primera) ?? 0)) / 7))
        guard let a = pesaje(primera, peso), let b = pesaje(ultima, peso) else { return (semanas, nil) }
        // Las dos puntas tienen que ser pesajes distintos, en orden y cada uno fuera de la semana de la otra foto. Con fotos
        // de semanas seguidas las ventanas de ±7 días se pisan: el alumno nuevo que todavía no se pesó en su segunda semana
        // veía «1 semana · 0,0 kg» (el mismo pesaje en las dos fotos) o el cambio dentro de la semana 1.
        func enSemana(_ n: Int, _ sem: String) -> Bool { DiaCalendario.numero(sem).map { n >= $0 && n <= $0 + 6 } ?? false }
        if a.n >= b.n || enSemana(a.n, ultima) || enSemana(b.n, primera) { return (semanas, nil) }
        let d = b.kg - a.kg
        if abs(d) > guardaFraccion * a.kg { return (semanas, nil) }
        return (semanas, d)
    }

    /// El pie del comparador: "8 semanas · -2,4 kg". Lo usan «Tu cambio» y el comparador clásico («Antes y ahora»).
    public static func resumenComparador(primera: String, ultima: String, peso: [PesoCorporal.Punto]) -> String {
        let c = cambioComparador(primera: primera, ultima: ultima, peso: peso)
        var r = "\(c.semanas) semana\(c.semanas == 1 ? "" : "s")"
        if let d = c.kg {
            var t = PesoCorporal.kg(d)
            if t == "-0,0" { t = "0,0" }
            r += " · \(d > 0 && t != "0,0" ? "+" : "")\(t) kg"
        }
        return r
    }

    /// Desde cuándo pedir el peso del comparador: el lunes de la semana de la foto más vieja menos 7 días (lo que necesita
    /// la regla de ±7 días). `fechas`: las semanas o los días de las fotos (AAAA-MM-DD). nil sin ninguna fecha válida.
    public static func desdePesoComparador(_ fechas: [String]) -> String? {
        let lunesValidos = fechas.filter { $0.count == 10 }.compactMap { DiaCalendario.numero(lunes($0)) }
        return lunesValidos.min().map { DiaCalendario.texto($0 - pesoDiasCerca) }
    }

    /// Si hace falta la serie aparte: los 60 días de Salud (de hoy − 59 a hoy) no llegan a `desde`.
    public static func necesitaPesoComparador(desde: String, hoy: String) -> Bool {
        guard let d = DiaCalendario.numero(desde), let h = DiaCalendario.numero(hoy) else { return false }
        return d < h - 59
    }
}
