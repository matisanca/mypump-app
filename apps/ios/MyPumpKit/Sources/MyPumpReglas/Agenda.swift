import Foundation
import MyPumpModelos

/// Las reglas de los videos obligatorios y de la agenda de la entrega (2.2.0), puras y con tests. La app no calcula
/// franjas: las muestra en la hora del teléfono, agrupadas por día, y decide qué tarjeta va según lo que dijo el servidor.
public enum ReglasAgenda {
    /// Desde cuánto antes del inicio aparece «Entrar» en la tarjeta de Entreno.
    public static let minutosAntesEntrar: Double = 30
    /// La consulta de una reserva pendiente: cada 5 s durante 60 s (después, al volver a primer plano).
    public static let sondeoCada: Double = 5
    public static let sondeoMaximo: Double = 60

    // MARK: - Obligatorios

    /// Los que cuentan para habilitar la agenda: los que traen `obligatorio: true`. Si NINGÚN clip trae el campo (servidor
    /// viejo), todos los de la lista que tienen url (como el resumen, sin los de los suplementos).
    public static func obligatorios(_ g: Guia?) -> [ClipGuia] {
        guard let g else { return [] }
        // Con el mismo filtro que el resumen y el servidor: sin los de «Tu suplementación» que nombra un suplemento.
        if g.clips.contains(where: { $0.obligatorio != nil }) { return ReglasGuia.deLaLista(g).filter { $0.obligatorio == true } }
        return ReglasGuia.deLaLista(g).filter { $0.url != nil }
    }

    public static func esObligatorio(_ c: ClipGuia, en g: Guia?) -> Bool { obligatorios(g).contains { $0.id == c.id } }

    /// Cuántos obligatorios faltan ver (`visto` ya incluye la tilde manual de la web).
    public static func faltan(_ g: Guia?) -> Int { obligatorios(g).filter { !$0.visto }.count }

    /// El primero que falta, en el orden de la lista: el que abre «Ir al próximo video».
    public static func primeroQueFalta(_ g: Guia?) -> ClipGuia? { obligatorios(g).first { !$0.visto } }

    /// «Te faltan 2 videos para habilitar la agenda».
    public static func textoContador(_ n: Int) -> String {
        n == 1 ? "Te falta 1 video para habilitar la agenda" : "Te faltan \(n) videos para habilitar la agenda"
    }

    /// La etiqueta discreta de los obligatorios (la marca de los datos no se muestra).
    public static let etiquetaObligatorio = "Para ver antes de la entrega"

    // MARK: - Qué se muestra

    /// Un aviso arriba de las franjas.
    public enum Aviso: Equatable, Sendable {
        /// La franja se ocupó (al reservar, o el daemon la encontró tomada).
        case tomada
        /// La franja ya no existe o venció.
        case vencida
        /// Otra falla (`vencida`, `error` o un motivo que no se conoce): se elige otra.
        case error
        /// La demo: no se crea ninguna videollamada.
        case demo

        public var texto: String {
            switch self {
            case .tomada: "Ese horario se ocupó recién, elegí otro."
            case .vencida: "Ese horario ya no está disponible, elegí otro."
            case .error: "No pudimos reservar ese horario, elegí otro."
            case .demo: "En la demo no se crea ninguna videollamada."
            }
        }
    }

    public enum Vista: Equatable, Sendable {
        /// Sin agenda: el servidor no la tiene (PGRST202), dijo `ok: false` o nunca respondió. Como la 2.1.0.
        case nada
        /// Mati todavía no dio el OK de horarios (`autorizada: false` o sin el campo).
        case noAutorizada(faltan: Int)
        /// Autorizada y con videos sin ver. Con 0 (los vio recién y el servidor todavía no se enteró), «habilitando».
        case bloqueada(faltan: Int)
        case franjas(aviso: Aviso?)
        case sinFranjas(aviso: Aviso?)
        case reservando
        case confirmada(ReservaAgenda, aviso: Aviso?)
    }

    /// `faltanLocal`: lo que cuenta la guía en el teléfono, solo de respaldo: si la agenda trae `faltan`, manda ese (el
    /// servidor filtra los clips como el resumen).
    /// `enCola`: hay una reserva saliendo. `aviso`: lo último que dijo `reservar` (tomada, vencida, error o la demo).
    public static func vista(_ a: AgendaGuia?, faltanLocal: Int?, enCola: Bool, aviso: Aviso? = nil) -> Vista {
        guard let a, a.ok else { return .nada }
        if enCola { return .reservando }
        if let r = a.reserva {
            switch r.estado {
            case .confirmada: return .confirmada(r, aviso: aviso == .demo ? .demo : nil)
            case .pendiente: return .reservando
            case .fallo: break
            }
        }
        let faltan = a.faltan ?? faltanLocal ?? 0
        guard a.autorizada else { return .noAutorizada(faltan: faltan) }
        guard a.habilitada else { return .bloqueada(faltan: faltan) }
        let av = aviso ?? (a.reserva?.estado == .fallo ? (a.reserva?.motivo == "tomada" ? .tomada : .error) : nil)
        return a.franjas.isEmpty ? .sinFranjas(aviso: av) : .franjas(aviso: av)
    }

    /// El texto de la agenda bloqueada.
    public static func textoBloqueada(_ faltan: Int) -> String {
        faltan > 0 ? "Cuando termines los videos de arriba se habilita la agenda. \(faltan == 1 ? "Te falta 1" : "Te faltan \(faltan)")."
                   : "Ya viste todo. Estamos habilitando tu agenda…"
    }

    public static let textoNoAutorizada = "Cuando termines de ver todo te habilitamos la agenda."
    public static let textoSinFranjas = "Ahora no hay horarios libres. Te escribimos por WhatsApp para coordinar."
    public static let textoReservando = "Estamos reservando tu horario…"
    public static let textoCambiar = "¿Necesitás cambiarla? Escribinos por WhatsApp"
    public static let textoZonaTelefono = "Horario de tu teléfono"

    // MARK: - Horas

    static let zonaBA = ReglasGuia.zonaBA

    public struct Chip: Equatable, Sendable, Identifiable {
        public var id: String { franja.id }
        public let franja: FranjaAgenda
        public let inicio: Date
        public let fin: Date
        /// «10:00 a 12:00», en la zona del teléfono.
        public let texto: String
    }

    public struct Dia: Equatable, Sendable, Identifiable {
        public let id: String
        /// «jueves 12 de noviembre».
        public let titulo: String
        public let chips: [Chip]
    }

    /// Las franjas por día en la zona del teléfono, de la más temprana a la más tardía. Las que no se entienden o ya
    /// empezaron (una copia vieja) no van.
    public static func dias(_ franjas: [FranjaAgenda], zona: TimeZone = .current, ahora: Date = Date()) -> [Dia] {
        let chips: [Chip] = franjas.compactMap { f in
            guard let i = ReglasGuia.instante(f.inicio), let fi = ReglasGuia.instante(f.fin), fi > i, i > ahora else { return nil }
            return Chip(franja: f, inicio: i, fin: fi, texto: "\(hora(i, zona: zona)) a \(hora(fi, zona: zona))")
        }.sorted { $0.inicio < $1.inicio }
        var orden: [String] = []
        var porDia: [String: [Chip]] = [:]
        for c in chips {
            let k = claveDia(c.inicio, zona: zona)
            if porDia[k] == nil { orden.append(k) }
            porDia[k, default: []].append(c)
        }
        return orden.map { k in Dia(id: k, titulo: diaLargo(porDia[k]![0].inicio, zona: zona), chips: porDia[k]!) }
    }

    /// La zona del teléfono da otra hora que Argentina para alguna de estas fechas: va «Horario de tu teléfono».
    public static func difiereDeArgentina(_ fechas: [Date], zona: TimeZone = .current) -> Bool {
        fechas.contains { zona.secondsFromGMT(for: $0) != zonaBA.secondsFromGMT(for: $0) }
    }

    /// «¿Confirmás la entrega el jueves 12 a las 10:00? Dura unas 2 horas.» Si el teléfono está en otra zona, también la
    /// hora de Argentina.
    public static func textoConfirmar(_ c: Chip, zona: TimeZone = .current) -> String {
        let ar = difiereDeArgentina([c.inicio], zona: zona) ? " (\(hora(c.inicio, zona: zonaBA)) en Argentina)" : ""
        return "¿Confirmás la entrega el \(diaCorto(c.inicio, zona: zona)) a las \(hora(c.inicio, zona: zona))\(ar)? Dura unas 2 horas."
    }

    /// «Tu entrega: jueves 12 de noviembre, 10:00 a 12:00».
    public static func textoConfirmada(_ r: ReservaAgenda, zona: TimeZone = .current) -> String? {
        guard let i = ReglasGuia.instante(r.inicio), let f = ReglasGuia.instante(r.fin) else { return nil }
        return "Tu entrega: \(diaLargo(i, zona: zona)), \(hora(i, zona: zona)) a \(hora(f, zona: zona))"
    }

    /// «Entrar» en la tarjeta de Entreno: confirmada, con link, desde 30 min antes hasta el fin de la franja.
    public static func puedeEntrar(_ r: ReservaAgenda?, ahora: Date = Date()) -> Bool {
        guard let r, r.estado == .confirmada, r.meetUrl != nil,
              let i = ReglasGuia.instante(r.inicio), let f = ReglasGuia.instante(r.fin) else { return false }
        return ahora >= i.addingTimeInterval(-minutosAntesEntrar * 60) && ahora < f
    }

    /// «Tu entrega empieza a las 10:00» (o «empezó», si ya arrancó).
    public static func textoEntrar(_ r: ReservaAgenda, zona: TimeZone = .current, ahora: Date = Date()) -> String {
        guard let i = ReglasGuia.instante(r.inicio) else { return "Tu entrega" }
        return "Tu entrega \(ahora >= i ? "empezó" : "empieza") a las \(hora(i, zona: zona))"
    }

    // MARK: - La demo

    /// Las franjas de la demo (`Demo.bundle/agenda.json`) corridas para que la primera caiga mañana, con los mismos días de
    /// diferencia entre sí y la misma hora de Argentina. Si ya están en el futuro, quedan como vinieron.
    public static func correrAlFuturo(_ fs: [FranjaAgenda], ahora: Date = Date()) -> [FranjaAgenda] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zonaBA
        guard let primero = fs.compactMap({ ReglasGuia.instante($0.inicio) }).min(), primero <= ahora,
              let manana = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: ahora)),
              let dias = cal.dateComponents([.day], from: cal.startOfDay(for: primero), to: manana).day else { return fs }
        let iso = ISO8601DateFormatter()
        iso.timeZone = zonaBA
        iso.formatOptions = [.withInternetDateTime]
        func correr(_ s: String) -> String? {
            ReglasGuia.instante(s).flatMap { cal.date(byAdding: .day, value: dias, to: $0) }.map(iso.string(from:))
        }
        return fs.compactMap { f in
            guard let i = correr(f.inicio), let fi = correr(f.fin) else { return nil }
            return FranjaAgenda(id: f.id, inicio: i, fin: fi)
        }
    }

    // MARK: - Formatos

    public static func hora(_ d: Date, zona: TimeZone) -> String { formato("HH:mm", zona).string(from: d) }

    public static func diaLargo(_ d: Date, zona: TimeZone) -> String { formato("EEEE d 'de' MMMM", zona).string(from: d) }

    public static func diaCorto(_ d: Date, zona: TimeZone) -> String { formato("EEEE d", zona).string(from: d) }

    static func claveDia(_ d: Date, zona: TimeZone) -> String { formato("yyyy-MM-dd", zona).string(from: d) }

    private static func formato(_ f: String, _ zona: TimeZone) -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_AR")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = zona
        fmt.dateFormat = f
        return fmt
    }
}
