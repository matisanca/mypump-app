import Foundation
import MyPumpModelos

/// Las reglas de los videos obligatorios y de la agenda de la entrega (2.2.0), puras y con tests. La app no calcula
/// franjas: las muestra en la hora del teléfono, agrupadas por día, y decide qué tarjeta va según lo que dijo el servidor.
public enum ReglasAgenda {
    /// Desde cuánto antes del inicio aparece la tarjeta de la entrega en Entreno.
    public static let minutosAntesEntrar: Double = 30
    /// Durante la franja, con la pantalla abierta y sin la sala abierta, la agenda se consulta cada 30 s.
    public static let salaCada: Double = 30
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
    public static let etiquetaObligatorio = "Para ver antes de la videollamada"

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
        /// El cambio ya no se puede desde la app (`tope` o `plazo`).
        case sinCambio

        public var texto: String {
            switch self {
            case .tomada: "Ese horario se ocupó recién, elegí otro."
            case .vencida: "Ese horario ya no está disponible, elegí otro."
            case .error: "No pudimos reservar ese horario, elegí otro."
            case .demo: "En la demo no se crea ninguna videollamada."
            case .sinCambio: "Ese cambio ya no se puede hacer desde la app. Escribinos por el chat."
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
    public static let textoSinFranjas = "Ahora no hay horarios libres. Mirá de nuevo más tarde o escribinos por el chat."
    public static let textoReservando = "Estamos reservando tu horario…"
    public static let textoCambiar = "¿Necesitás cambiarla? Escribinos por el chat."
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

        public init(id: String, titulo: String, chips: [Chip]) { self.id = id; self.titulo = titulo; self.chips = chips }
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

    /// «¿Confirmás tu videollamada de comienzo el jueves 12 a las 10:00? Dura alrededor de 1 hora.» Si el teléfono está en
    /// otra zona, también la hora de Argentina. La duración sale de la franja (Mati cambia horarios y duración solo con datos).
    public static func textoConfirmar(_ c: Chip, zona: TimeZone = .current, tipo: TipoVideollamada = .comienzo) -> String {
        let ar = difiereDeArgentina([c.inicio], zona: zona) ? " (\(hora(c.inicio, zona: zonaBA)) en Argentina)" : ""
        let dura = textoDuracion(desde: c.inicio, hasta: c.fin).map { " \($0)" } ?? ""
        return "¿Confirmás tu \(nombre(tipo)) el \(diaCorto(c.inicio, zona: zona)) a las \(hora(c.inicio, zona: zona))\(ar)?\(dura)"
    }

    /// El encabezado de las franjas: «Elegí un horario para la videollamada.» y, si todas duran lo mismo (redondeado), la
    /// duración. Si duran distinto, la de cada una va en la hoja de confirmación.
    public static func textoElegir(_ chips: [Chip]) -> String {
        let base = "Elegí un horario para la videollamada."
        let duraciones = Set(chips.map { textoDuracion(desde: $0.inicio, hasta: $0.fin) })
        guard duraciones.count == 1, let d = duraciones.first, let d else { return base }
        return "\(base) \(d)"
    }

    /// «Dura unas 2 horas», «Dura alrededor de 1 hora», «Dura unos 45 minutos»: de fin − inicio, a la media hora si pasa
    /// de 1 h y a los 15 min si no. nil si la franja no tiene sentido.
    public static func textoDuracion(desde inicio: Date, hasta fin: Date) -> String? {
        duracion(desde: inicio, hasta: fin).map { "Dura \($0)." }
    }

    /// Lo que va después de «Dura» (y en `{duracion}` de los textos de Mati): «unas 2 horas», «alrededor de 1 hora»,
    /// «unos 45 minutos».
    public static func duracion(desde inicio: Date, hasta fin: Date) -> String? {
        let total = fin.timeIntervalSince(inicio) / 60
        guard total.isFinite, total > 0 else { return nil }
        if total > 60 {
            let medias = Int((total / 30).rounded())
            let horas = medias / 2, media = medias % 2 == 1
            if horas == 1 { return media ? "alrededor de 1 hora y media" : "alrededor de 1 hora" }
            return "unas \(horas) horas\(media ? " y media" : "")"
        }
        let cuartos = max(1, Int((total / 15).rounded()))
        if cuartos == 4 { return "alrededor de 1 hora" }
        return "unos \(cuartos * 15) minutos"
    }

    /// «Jueves 12 de noviembre, de 10:00 a 11:00» (sin dos puntos después del nombre: regla de los textos del alumno).
    public static func textoConfirmada(_ r: ReservaAgenda, zona: TimeZone = .current) -> String? {
        guard let i = ReglasGuia.instante(r.inicio), let f = ReglasGuia.instante(r.fin) else { return nil }
        return "\(mayuscula(diaLargo(i, zona: zona))), de \(hora(i, zona: zona)) a \(hora(f, zona: zona))"
    }

    // MARK: - La videollamada (2.3.0): cómo se nombra, la tarjeta fija, la cuenta regresiva y los avisos

    /// «videollamada de comienzo» o «de revisión». Al alumno nunca se le dice «entrega».
    public static func nombre(_ t: TipoVideollamada) -> String {
        t == .revision ? "videollamada de revisión" : "videollamada de comienzo"
    }

    /// «Tu videollamada de comienzo».
    public static func tituloTarjeta(_ t: TipoVideollamada) -> String { "Tu \(nombre(t))" }

    /// Desde cuántos minutos antes del inicio se habilita «Entrar» (Mati, 10/11: Meet restringido, Mati lo admite y el
    /// alumno espera en la sala). El servidor lo puede cambiar con `entrar_desde_min`.
    public static let entrarDesdeMin = 10

    public static let textoDesdeAca = "Vas a entrar a la videollamada desde acá."
    public static let textoAdmite = "Mati te admite en la sala. Si tarda un poco, esperá ahí sin salir."
    /// «¿Cómo entro?», en el orden en que pasan las cosas.
    public static let ayudaEntrar = [
        "Tocás Entrar y se abre Google Meet. Si no lo tenés instalado, se abre en el navegador y funciona igual.",
        "Mati te admite en la sala. Esperá ahí, no hace falta salir y volver a entrar.",
        "Si se corta, volvé a la app y tocá Entrar de nuevo.",
        "Si no podés entrar, escribinos por el chat.",
    ]

    /// En qué está el botón «Entrar».
    public enum EstadoEntrar: Equatable, Sendable {
        /// Todavía no: faltan estos segundos para que se habilite.
        case falta(segundos: Double)
        /// Habilitado (desde `desdeMin` antes hasta el fin).
        case habilitado
        /// En la ventana pero el link todavía no llegó (el daemon no lo cargó): sin botón activo.
        case preparando
        /// Terminó, o no es una reserva confirmada.
        case nada
    }

    public static func estadoEntrar(_ r: ReservaAgenda?, ahora: Date = Date(), desdeMin: Int? = nil) -> EstadoEntrar {
        guard let r, r.estado == .confirmada, let i = ReglasGuia.instante(r.inicio), let f = ReglasGuia.instante(r.fin),
              ahora < f else { return .nada }
        let desde = i.addingTimeInterval(-Double(desdeMin ?? entrarDesdeMin) * 60)
        // Si Mati ya abrió la sala, se puede entrar antes (espera en la sala igual).
        if ahora < desde, r.salaAbiertaEn == nil || r.meetUrl == nil { return .falta(segundos: desde.timeIntervalSince(ahora)) }
        return r.meetUrl == nil ? .preparando : .habilitado
    }

    /// Debajo del botón apagado: lejos, «Se habilita 10 minutos antes de empezar»; a menos de un día, la cuenta regresiva.
    public static func textoCuenta(_ e: EstadoEntrar, desdeMin: Int? = nil) -> String? {
        switch e {
        case .falta(let s) where s >= 24 * 3600:
            return "Se habilita \(desdeMin ?? entrarDesdeMin) minutos antes de empezar"
        case .falta(let s):
            return "Se habilita en \(cuenta(s))"
        case .preparando:
            return "Estamos preparando la sala. El botón se activa en un momento."
        case .habilitado, .nada:
            return nil
        }
    }

    /// «2 h 15 min», «25 min», «menos de 1 min». Redondea para arriba: nunca dice 0 antes de tiempo.
    public static func cuenta(_ segundos: Double) -> String {
        guard segundos.isFinite, segundos > 0 else { return "menos de 1 min" }
        let min = Int((segundos / 60).rounded(.up))
        if segundos < 60 { return "menos de 1 min" }
        if min < 60 { return "\(min) min" }
        let h = min / 60, m = min % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// La etiqueta de arriba de la tarjeta: «Hoy», «Mañana», «En 3 días» (por día del calendario, en la zona del teléfono).
    public static func cuando(_ r: ReservaAgenda, zona: TimeZone = .current, ahora: Date = Date()) -> String? {
        guard let i = ReglasGuia.instante(r.inicio) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        guard let d = cal.dateComponents([.day], from: cal.startOfDay(for: ahora), to: cal.startOfDay(for: i)).day else { return nil }
        switch d {
        case ..<0: return nil
        case 0: return "Hoy"
        case 1: return "Mañana"
        default: return "En \(d) días"
        }
    }

    /// «10:00 en Argentina», solo si el teléfono da otra hora.
    public static func horaArgentina(_ d: Date, zona: TimeZone = .current) -> String? {
        difiereDeArgentina([d], zona: zona) ? "\(hora(d, zona: zonaBA)) en Argentina" : nil
    }

    /// La reserva de la tarjeta fija de Entreno: confirmada (o reservándose) y que no terminó.
    public static func paraTarjeta(_ r: ReservaAgenda?, ahora: Date = Date()) -> Bool {
        guard let r, r.vigente, let f = ReglasGuia.instante(r.fin) else { return false }
        return ahora < f
    }

    /// Un aviso local de la videollamada (sin permisos nuevos: solo si la app ya los tenía).
    public struct AvisoLocal: Equatable, Sendable {
        public let id: String
        public let fecha: Date
        public let titulo: String
        public let cuerpo: String
    }

    public static let idAvisoDia = "mypump-videollamada-dia"
    public static let idAvisoEntrar = "mypump-videollamada-entrar"

    /// Un día antes y cuando se habilita «Entrar». Los que ya pasaron no van. Sin reserva confirmada, ninguno.
    public static func avisosLocales(_ r: ReservaAgenda?, ahora: Date = Date(), zona: TimeZone = .current, desdeMin: Int? = nil) -> [AvisoLocal] {
        guard let r, r.estado == .confirmada, let i = ReglasGuia.instante(r.inicio) else { return [] }
        let h = hora(i, zona: zona)
        let desde = desdeMin ?? entrarDesdeMin
        let n = nombre(r.tipo)
        let todos = [
            AvisoLocal(id: idAvisoDia, fecha: i.addingTimeInterval(-24 * 3600), titulo: "Mañana es tu \(n)",
                       cuerpo: "Es a las \(h). Vas a entrar desde la app, en Entreno."),
            AvisoLocal(id: idAvisoEntrar, fecha: i.addingTimeInterval(-Double(desde) * 60), titulo: "Ya podés entrar a tu \(n)",
                       cuerpo: "Abrí la app y tocá Entrar. Mati te admite en la sala."),
        ]
        return todos.filter { $0.fecha > ahora }
    }

    // MARK: - Elegir y cambiar el horario (palanca `elegir_horario`)

    /// «Elegí el horario de tu videollamada de comienzo».
    public static func tituloElegir(_ t: TipoVideollamada) -> String { "Elegí el horario de tu \(nombre(t))" }

    /// «Dura alrededor de 1 hora y vas a entrar desde la app.» (la duración, de las franjas si todas duran lo mismo).
    public static func textoElegirPantalla(_ chips: [Chip]) -> String {
        let durs = Set(chips.map { duracion(desde: $0.inicio, hasta: $0.fin) })
        if durs.count == 1, let d = durs.first, let d { return "Dura \(d) y vas a entrar desde la app." }
        return "Vas a entrar desde la app."
    }

    /// El botón de abajo con un horario elegido: «Confirmar jueves 12, 10:00» o «Cambiar al viernes 13, 12:00».
    public static func textoBotonElegir(_ c: Chip, cambiando: Bool, zona: TimeZone = .current) -> String {
        let d = "\(diaCorto(c.inicio, zona: zona)), \(hora(c.inicio, zona: zona))"
        return cambiando ? "Cambiar al \(d)" : "Confirmar \(d)"
    }

    /// Se puede cambiar desde la app: lo dice el servidor, quedan cambios, no pasó el plazo y hay horarios.
    public static func puedeCambiar(_ a: AgendaGuia?, ahora: Date = Date()) -> Bool {
        guard let a, a.ok, let r = a.reserva, r.estado == .confirmada, let c = a.cambio, c.permitido, !a.franjas.isEmpty else { return false }
        if let n = c.restantes, n <= 0 { return false }
        if let h = c.hasta.flatMap(ReglasGuia.instante), ahora >= h { return false }
        if let i = ReglasGuia.instante(r.inicio), ahora >= i { return false }
        return true
    }

    /// «Podés cambiarlo 1 vez, hasta el miércoles 11 a las 10:00.»
    public static func textoTope(_ c: CambioAgenda?, zona: TimeZone = .current) -> String? {
        guard let c, c.permitido else { return nil }
        let veces = c.restantes.map { $0 == 1 ? " 1 vez" : " \($0) veces" } ?? ""
        let hasta = c.hasta.flatMap(ReglasGuia.instante).map { ", hasta el \(diaCorto($0, zona: zona)) a las \(hora($0, zona: zona))" } ?? ""
        return "Podés cambiarlo\(veces)\(hasta)."
    }

    /// Lo que se ve arriba al cambiar: «Ahora es el jueves 12 a las 10:00.»
    public static func textoAhoraEs(_ r: ReservaAgenda, zona: TimeZone = .current) -> String? {
        ReglasGuia.instante(r.inicio).map { "Ahora es el \(diaCorto($0, zona: zona)) a las \(hora($0, zona: zona))." }
    }

    static func mayuscula(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
    public static func mayusculaPublica(_ s: String) -> String { mayuscula(s) }

    // MARK: - Entrar (cambio de Mati, 6/11: el cliente nunca entra directo)

    /// La tarjeta de la entrega en Entreno: confirmada, desde `avisoMin` antes (el de la agenda; si no vino, 30) hasta el
    /// fin de la franja.
    public static func enVentana(_ r: ReservaAgenda?, ahora: Date = Date(), avisoMin: Int? = nil) -> Bool {
        guard let r, r.estado == .confirmada, let i = ReglasGuia.instante(r.inicio), let f = ReglasGuia.instante(r.fin) else { return false }
        let antes = avisoMin.map(Double.init) ?? minutosAntesEntrar
        return ahora >= i.addingTimeInterval(-antes * 60) && ahora < f
    }

    /// El botón para entrar (Mati, 10/11): confirmada, con link, desde `desdeMin` (10) antes del inicio hasta el fin. El
    /// Meet es restringido: Mati lo admite y el alumno espera en la sala, así que ya no se espera `sala_abierta_en`.
    public static func puedeEntrar(_ r: ReservaAgenda?, ahora: Date = Date(), desdeMin: Int? = nil) -> Bool {
        estadoEntrar(r, ahora: ahora, desdeMin: desdeMin) == .habilitado
    }

    /// En la ventana y todavía sin el link o sin la sala abierta: la pantalla abierta consulta la agenda cada 30 s (para el
    /// link que falta y para «Mati ya está en la sala»).
    public static func esperandoSala(_ r: ReservaAgenda?, ahora: Date = Date(), avisoMin: Int? = nil) -> Bool {
        guard enVentana(r, ahora: ahora, avisoMin: avisoMin), let r else { return false }
        return r.meetUrl == nil || r.salaAbiertaEn == nil
    }

    /// Es el día de la entrega (en la zona del teléfono) y todavía no terminó.
    public static func esHoy(_ r: ReservaAgenda, zona: TimeZone = .current, ahora: Date = Date()) -> Bool {
        guard let i = ReglasGuia.instante(r.inicio), let f = ReglasGuia.instante(r.fin), ahora < f else { return false }
        return claveDia(i, zona: zona) == claveDia(ahora, zona: zona) || ahora >= i
    }

    /// Con el botón: «Mati ya está en la sala» o «Ya podés entrar».
    public static func textoEntrar(_ r: ReservaAgenda, zona: TimeZone = .current) -> String {
        r.salaAbiertaEn != nil ? "Mati ya está en la sala" : "Ya podés entrar"
    }

    /// El día de la videollamada, sin el botón todavía.
    public static func textoEsperandoSala(_ r: ReservaAgenda, zona: TimeZone = .current, desdeMin: Int? = nil) -> String {
        let h = ReglasGuia.instante(r.inicio).map { hora($0, zona: zona) } ?? ""
        return "Tu \(nombre(r.tipo)) es hoy a las \(h). El botón para entrar se habilita \(desdeMin ?? entrarDesdeMin) minutos antes."
    }

    // MARK: - Los textos que edita Mati (spec §7)

    /// Las claves de `textos` en `entregas_app_agenda`. Una que no está acá se ignora.
    public enum Clave: String, CaseIterable, Sendable {
        case bloqueada, noAutorizada = "no_autorizada", titulo, encabezado, confirmar, pendiente, confirmada
        case hoySinSala = "hoy_sin_sala", salaAbierta = "sala_abierta", fallo, sinFranjas = "sin_franjas", cambiar
        case entrenoAviso = "entreno_aviso"
    }

    /// Los textos de la agenda: el de Mati si vino y no está vacío, con `{hora}`, `{dia}`, `{duracion}` y `{faltan}`
    /// reemplazados; si no, el de la app. Si el de Mati pide un valor que acá no hay (`{hora}` sin hora), va el de la app:
    /// nunca se muestra una llave.
    public struct Textos: Equatable, Sendable {
        public let servidor: [String: String]

        public init(_ servidor: [String: String] = [:]) { self.servidor = servidor }

        public func texto(_ clave: Clave, propio: String, hora: String? = nil, dia: String? = nil, duracion: String? = nil,
                          faltan: Int? = nil) -> String {
            guard var t = servidor[clave.rawValue], !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return propio }
            for (llave, valor) in [("{hora}", hora), ("{dia}", dia), ("{duracion}", duracion), ("{faltan}", faltan.map(String.init))]
            where t.contains(llave) {
                guard let valor else { return propio }
                t = t.replacingOccurrences(of: llave, with: valor)
            }
            return t
        }

        public var titulo: String { titulo(.comienzo) }
        public func titulo(_ t: TipoVideollamada) -> String { texto(.titulo, propio: "Agendá tu \(ReglasAgenda.nombre(t))") }
        public var noAutorizada: String { texto(.noAutorizada, propio: ReglasAgenda.textoNoAutorizada) }
        public var sinFranjas: String { texto(.sinFranjas, propio: ReglasAgenda.textoSinFranjas) }
        public var pendiente: String { texto(.pendiente, propio: ReglasAgenda.textoReservando) }
        public var cambiar: String { texto(.cambiar, propio: ReglasAgenda.textoCambiar) }

        /// Con 0 («Ya viste todo…») no hay clave: es el instante en que el servidor todavía no se enteró.
        public func bloqueada(_ faltan: Int) -> String {
            faltan > 0 ? texto(.bloqueada, propio: ReglasAgenda.textoBloqueada(faltan), faltan: faltan) : ReglasAgenda.textoBloqueada(0)
        }

        /// Tomada, vencida o error: el mismo texto de Mati para todas. La demo no se pisa.
        public func fallo(_ a: Aviso) -> String { a == .demo ? a.texto : texto(.fallo, propio: a.texto) }

        public func encabezado(_ chips: [Chip]) -> String {
            let durs = Set(chips.map { ReglasAgenda.duracion(desde: $0.inicio, hasta: $0.fin) })
            let una = durs.count == 1 ? durs.first ?? nil : nil
            return texto(.encabezado, propio: ReglasAgenda.textoElegir(chips), duracion: una)
        }

        public func confirmar(_ c: Chip, zona: TimeZone = .current, tipo: TipoVideollamada = .comienzo) -> String {
            texto(.confirmar, propio: ReglasAgenda.textoConfirmar(c, zona: zona, tipo: tipo), hora: ReglasAgenda.hora(c.inicio, zona: zona),
                  dia: ReglasAgenda.diaCorto(c.inicio, zona: zona), duracion: ReglasAgenda.duracion(desde: c.inicio, hasta: c.fin))
        }

        public func confirmada(_ r: ReservaAgenda, zona: TimeZone = .current) -> String? {
            guard let propio = ReglasAgenda.textoConfirmada(r, zona: zona), let i = ReglasGuia.instante(r.inicio),
                  let f = ReglasGuia.instante(r.fin) else { return nil }
            return texto(.confirmada, propio: propio, hora: ReglasAgenda.hora(i, zona: zona), dia: ReglasAgenda.diaLargo(i, zona: zona),
                         duracion: ReglasAgenda.duracion(desde: i, hasta: f))
        }

        /// Con el botón: «Mati ya está en la videollamada» (la clave `sala_abierta`) o el respaldo de la hora de inicio.
        public func entrar(_ r: ReservaAgenda, zona: TimeZone = .current) -> String {
            let propio = ReglasAgenda.textoEntrar(r, zona: zona)
            return r.salaAbiertaEn != nil ? texto(.salaAbierta, propio: propio) : propio
        }

        public func hoySinSala(_ r: ReservaAgenda, zona: TimeZone = .current) -> String {
            texto(.hoySinSala, propio: ReglasAgenda.textoEsperandoSala(r, zona: zona), hora: horaInicio(r, zona))
        }

        /// La tarjeta de Entreno antes de que se abra la sala: `entreno_aviso` si vino; si no, el mismo de la guía.
        public func entrenoAviso(_ r: ReservaAgenda, zona: TimeZone = .current) -> String {
            texto(.entrenoAviso, propio: hoySinSala(r, zona: zona), hora: horaInicio(r, zona))
        }

        private func horaInicio(_ r: ReservaAgenda, _ zona: TimeZone) -> String? {
            ReglasGuia.instante(r.inicio).map { ReglasAgenda.hora($0, zona: zona) }
        }
    }

    // MARK: - La demo

    /// Las franjas de la demo (`Demo.bundle/agenda.json`) corridas para que la primera caiga el próximo día hábil, con la
    /// misma hora de Argentina y los mismos días hábiles de diferencia entre sí. Como el servidor (`agenda_lib.huecos`),
    /// solo de lunes a viernes: nunca un sábado ni un domingo. Si ya están en el futuro, quedan como vinieron.
    public static func correrAlFuturo(_ fs: [FranjaAgenda], ahora: Date = Date()) -> [FranjaAgenda] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zonaBA
        guard let primero = fs.compactMap({ ReglasGuia.instante($0.inicio) }).min(), primero <= ahora else { return fs }
        let base = cal.startOfDay(for: primero)
        let hoy = cal.startOfDay(for: ahora)
        let iso = ISO8601DateFormatter()
        iso.timeZone = zonaBA
        iso.formatOptions = [.withInternetDateTime]
        func correr(_ s: String, _ dias: Int) -> String? {
            ReglasGuia.instante(s).flatMap { cal.date(byAdding: .day, value: dias, to: $0) }.map(iso.string(from:))
        }
        return fs.compactMap { f in
            guard let i = ReglasGuia.instante(f.inicio) else { return nil }
            let dia = cal.startOfDay(for: i)
            let destino = diaHabil(1 + habilesEntre(base, dia, cal), desde: hoy, cal)
            guard let dias = cal.dateComponents([.day], from: dia, to: destino).day,
                  let ni = correr(f.inicio, dias), let nf = correr(f.fin, dias) else { return nil }
            return FranjaAgenda(id: f.id, inicio: ni, fin: nf)
        }
    }

    /// De lunes a viernes, como las franjas del servidor.
    public static func esHabil(_ d: Date, _ cal: Calendar) -> Bool { !cal.isDateInWeekend(d) }

    /// El `n`-ésimo día hábil después de `desde` (n = 1: el próximo), a las 0 de ese día.
    public static func diaHabil(_ n: Int, desde: Date, _ cal: Calendar) -> Date {
        var d = cal.startOfDay(for: desde)
        var k = 0
        while k < max(n, 1) {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            if esHabil(d, cal) { k += 1 }
        }
        return d
    }

    /// Cuántos días hábiles hay después de `a` hasta `b` inclusive (0 si `b` no es posterior).
    static func habilesEntre(_ a: Date, _ b: Date, _ cal: Calendar) -> Int {
        var d = cal.startOfDay(for: a)
        var k = 0
        while d < b {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? b
            if d <= b, esHabil(d, cal) { k += 1 }
        }
        return k
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
