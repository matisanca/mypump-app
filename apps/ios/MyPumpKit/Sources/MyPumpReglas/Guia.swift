import Foundation
import MyPumpModelos

/// Las reglas de «Tu guía», puras y con tests: las mismas que `pack.html` de la obra de entregas (la web), así lo que se
/// ve en un lado se ve igual en el otro. La vista y el reproductor solo las usan.
public enum ReglasGuia {
    /// Tope de una duda (la base acepta de 1 a 1000 caracteres).
    public static let maxTexto = 1000
    /// Tope de dudas para la videollamada, compartido con la web.
    public static let maxDudasLlamada = 30
    /// Lo que dura la placa al cambiar de video.
    public static let placaSegundos: Double = 2.6
    /// La base acepta `p_segundos` de 0 a 36000.
    public static let maxSegundos = 36_000

    // MARK: - Bloques

    /// «Tu app» (como lo escriba el servidor) va primero, como en la web.
    public static func esBloqueApp(_ bloque: String?) -> Bool {
        (bloque ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "tu app"
    }

    /// Los clips en el orden en que se muestran: el que trae el servidor, con los de «Tu app» adelante (estable).
    public static func ordenados(_ clips: [ClipGuia]) -> [ClipGuia] {
        clips.filter { esBloqueApp($0.bloque) } + clips.filter { !esBloqueApp($0.bloque) }
    }

    /// Lo que recorta `entregas_012` alrededor del bloque: `[\s\u00a0\ufeff]` del regex (`\s` de Postgres es espacio,
    /// tab, salto de línea, retorno, tab vertical y salto de página).
    private static let espaciosDelServidor: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "\u{A0}", "\u{FEFF}"]

    /// «Tu suplementación» como el regex de `entregas_012` (`~* '^…tu suplementaci[oóÓ]n…$'`): escalar por escalar (una ó
    /// descompuesta, NFD, no es la ó del regex aunque Swift las compare iguales), sin distinguir mayúsculas en ASCII y con o,
    /// ó u Ó. Un bloque nil no es ese bloque.
    public static func esBloqueSuplementacion(_ bloque: String?) -> Bool {
        guard let bloque else { return false }
        var e = Array(bloque.unicodeScalars)
        while let f = e.first, espaciosDelServidor.contains(f) { e.removeFirst() }
        while let l = e.last, espaciosDelServidor.contains(l) { e.removeLast() }
        let base = Array("tu suplementaci".unicodeScalars)
        guard e.count == base.count + 2 else { return false }
        for (x, y) in zip(e, base) where x.properties.lowercaseMapping != String(y) { return false }
        let o = e[base.count]
        guard o == "o" || o == "O" || o == "\u{F3}" || o == "\u{D3}" else { return false }
        return e[base.count + 1] == "n" || e[base.count + 1] == "N"
    }

    /// Los ids de los clips que nombra un suplemento (`nombraVideo`: nombre no vacío, estado distinto de «sale» y
    /// `video_id` no vacío), como `nombrados` en la web y en `entregas_012`.
    public static func nombradosPorSuplementos(_ s: SuplementacionGuia?) -> Set<String> {
        Set((s?.items ?? []).compactMap(\.nombraVideo))
    }

    /// Los clips de la lista, de «Viste X de N» y del reproductor (web del 4/11, A5): los del bloque «Tu suplementación» que
    /// nombra un suplemento se ven solo debajo de ese suplemento, con «Ver por qué». Si ningún suplemento los nombra,
    /// quedan en la lista para no perderlos. Mismo orden que `ordenados`.
    ///
    /// 2.2.0: los `nuevo` van primero, en el orden del servidor (el bloque «Novedad»); después, los de siempre. Sin ningún
    /// `nuevo` (servidor viejo), el orden de la 2.1.0 tal cual.
    public static func deLaLista(_ g: Guia?) -> [ClipGuia] {
        guard let g else { return [] }
        let nombrados = nombradosPorSuplementos(g.suplementacion)
        let lista = g.clips.filter { !(esBloqueSuplementacion($0.bloque) && nombrados.contains($0.id)) }
        return lista.filter(\.nuevo) + ordenados(lista.filter { !$0.nuevo })
    }

    /// El clip de un «Ver por qué»: el que nombra el suplemento, si existe y tiene url (como `vid` en la web).
    public static func clipDeSuplemento(_ g: Guia?, videoId: String?) -> ClipGuia? {
        guard let videoId, let c = g?.clips.first(where: { $0.id == videoId }), c.url != nil else { return nil }
        return c
    }

    /// El rótulo del botón, como la web: «Ver por qué (N s)», al menos 1 s.
    public static func rotuloVerPorQue(_ c: ClipGuia) -> String {
        "Ver por qué (\(max(1, Int((c.minutos * 60).rounded()))) s)"
    }

    public struct Bloque: Equatable, Sendable, Identifiable {
        /// El del bloque «Novedad» no choca con un bloque del servidor que se llame igual.
        public var id: String { novedad ? ReglasGuia.idNovedad : titulo }
        public let titulo: String
        /// Índices en la lista de `ordenados`.
        public let indices: [Int]
        public let minutos: Double
        /// 2.2.0: el bloque «Novedad», con los clips `nuevo`, arriba de todo.
        public var novedad: Bool = false
        public var esApp: Bool { !novedad && ReglasGuia.esBloqueApp(titulo) }
    }

    /// La clave del bloque «Novedad» (y de su fila en la pantalla).
    public static let idNovedad = "_novedad"

    /// La clave del bloque de un clip (la que usa `Bloque.id`): «Novedad» si es nuevo; si no, su bloque o «Videos».
    public static func claveBloque(_ c: ClipGuia) -> String {
        c.nuevo ? idNovedad : (c.bloque?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Videos"
    }

    /// Agrupa por `bloque` respetando el orden en que aparece cada uno (los nombres vienen del servidor, tal cual). Un
    /// clip sin bloque va a «Videos», como en la web. Los `nuevo` van juntos en «Novedad» (2.2.0).
    public static func bloques(_ clips: [ClipGuia]) -> [Bloque] {
        var titulos: [String] = []
        var indices: [String: [Int]] = [:]
        for (i, c) in clips.enumerated() {
            let t = claveBloque(c)
            if indices[t] == nil { titulos.append(t) }
            indices[t, default: []].append(i)
        }
        return titulos.map { t in
            let ix = indices[t] ?? []
            let m = ix.reduce(0) { $0 + clips[$1].minutos }
            return t == idNovedad ? Bloque(titulo: "Novedad", indices: ix, minutos: m, novedad: true) : Bloque(titulo: t, indices: ix, minutos: m)
        }
    }

    /// «4 videos, unos 2 minutos». El de «Novedad»: «3 videos nuevos para vos · 9 min».
    public static func textoBloque(_ b: Bloque) -> String {
        let n = b.indices.count
        if b.novedad {
            return "\(n) \(n == 1 ? "video nuevo" : "videos nuevos") para vos · \(max(1, Int(b.minutos.rounded()))) min"
        }
        let m = max(1, Int(b.minutos.rounded()))
        return "\(n) \(n == 1 ? "video" : "videos"), \(unos(m, corto: false))"
    }

    /// «unos 12 minutos» / «unos 12 min»; con 1, «1 minuto» / «1 min» (nunca «unos 1 minutos»).
    static func unos(_ m: Int, corto: Bool) -> String {
        m == 1 ? (corto ? "1 min" : "1 minuto") : "unos \(m) \(corto ? "min" : "minutos")"
    }

    /// «te quedan 12 min» / «te queda 1 min».
    static func teQuedan(_ m: Int, corto: Bool) -> String {
        m == 1 ? "te queda 1 \(corto ? "min" : "minuto")" : "te quedan \(m) \(corto ? "min" : "minutos")"
    }

    /// La duración de una fila, «1:12».
    public static func duracion(minutos: Double) -> String {
        let s = Int((minutos * 60).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// «1 minuto y 12 segundos», para VoiceOver.
    public static func duracionHablada(minutos: Double) -> String {
        let s = Int((minutos * 60).rounded())
        let m = s / 60, r = s % 60
        var partes: [String] = []
        if m > 0 { partes.append(m == 1 ? "1 minuto" : "\(m) minutos") }
        if r > 0 || m == 0 { partes.append(r == 1 ? "1 segundo" : "\(r) segundos") }
        return partes.joined(separator: " y ")
    }

    // MARK: - Avance

    public struct Avance: Equatable, Sendable, Codable {
        public let total: Int
        public let vistos: Int
        public let minutosRestantes: Double

        public init(total: Int, vistos: Int, minutosRestantes: Double) {
            self.total = total; self.vistos = vistos; self.minutosRestantes = minutosRestantes
        }

        public var completo: Bool { total > 0 && vistos >= total }
        public var fraccion: Double { total > 0 ? min(1, Double(vistos) / Double(total)) : 0 }
    }

    public static func avance(_ clips: [ClipGuia]) -> Avance {
        Avance(total: clips.count, vistos: clips.filter(\.visto).count,
               minutosRestantes: clips.filter { !$0.visto }.reduce(0) { $0 + $1.minutos })
    }

    /// La línea de la cabecera, igual que la web: «Viste 4 de 13, te quedan unos 12 minutos».
    public static func textoAvance(_ a: Avance) -> String {
        if a.completo { return "Viste todos, nos vemos en la videollamada" }
        let m = max(1, Int(a.minutosRestantes.rounded()))
        return "Viste \(a.vistos) de \(a.total), \(m == 1 ? "te queda 1 minuto" : "te quedan unos \(m) minutos")"
    }

    /// La línea de la tarjeta de inicio: «4 de 13 videos, te quedan 12 min».
    public static func textoTarjeta(_ a: Avance) -> String {
        if a.completo { return a.total == 1 ? "Viste el video" : "Viste los \(a.total) videos" }
        let min = max(1, Int(a.minutosRestantes.rounded()))
        if a.vistos == 0 { return "\(a.total) \(a.total == 1 ? "video corto" : "videos cortos"), \(unos(min, corto: true))" }
        return "\(a.vistos) de \(a.total) videos, \(teQuedan(min, corto: true))"
    }

    // MARK: - Guía destacada (pedido de Mati, 4-nov: «súper llamativo, súper guiado, porque es lo primero»)

    /// Cómo se ve la tarjeta de Entreno: verde y protagonista mientras falte algo; compacta (blanca, con el tilde) con
    /// todo visto, así no molesta.
    public enum EstiloTarjeta: Equatable, Sendable { case destacada, compacta }

    public static func estiloTarjeta(_ a: Avance) -> EstiloTarjeta { a.completo ? .compacta : .destacada }

    /// El botón de la tarjeta destacada.
    public static func botonTarjeta(_ a: Avance) -> String { a.vistos == 0 ? "Ver mi guía" : "Seguir viendo" }

    // MARK: - Novedad (2.2.0, fase 2 de la guía)

    /// El avance de la tarjeta «NOVEDAD EN TU GUÍA»: con `novedad_en` (del resumen o de la copia) y algún nuevo sin ver,
    /// cuenta solo los nuevos. nil = la tarjeta de la 2.1.0 tal cual (sin `novedad_en`, o vio todo lo nuevo).
    ///
    /// Si la copia guardada todavía no sabe de esa tanda (no abrió la guía desde que llegó, y la tarjeta nunca pide el get),
    /// cuenta con el resumen mientras falte algo: la tanda nueva es lo que falta.
    public static func avanceNovedad(_ r: ResumenGuia?, guia: Guia?) -> Avance? {
        guard let n = r?.novedadEn ?? guia?.novedadEn else { return nil }
        let nuevos = deLaLista(guia).filter(\.nuevo)
        // El resumen trae el avance de la tanda nueva: manda ese. Los minutos, de la copia si la tiene; si no, los del resumen.
        if let r, r.ok, let t = r.nuevosTotal, let v = r.nuevosVistos {
            guard t > 0, v < t else { return nil }
            let copiaAlDia = !nuevos.isEmpty && (guia?.novedadEn == n || r.novedadEn == nil)
            let min = copiaAlDia ? nuevos.filter { !$0.visto }.reduce(0) { $0 + $1.minutos } : r.minutosRestantes
            return Avance(total: t, vistos: v, minutosRestantes: min)
        }
        if !nuevos.isEmpty, guia?.novedadEn == n || r?.novedadEn == nil {
            let a = avance(nuevos)
            return a.completo ? nil : a
        }
        if let g = guia, g.novedadEn == n { return nil }   // la copia está al día y no trae nuevos
        guard let r, r.ok, r.total > 0, r.vistos < r.total else { return nil }
        return Avance(total: r.total, vistos: r.vistos, minutosRestantes: r.minutosRestantes)
    }

    /// La línea de la tarjeta con novedad: «2 videos nuevos, unos 3 min» o «1 de 2 videos nuevos, te quedan 2 min».
    public static func textoTarjetaNovedad(_ a: Avance) -> String {
        let min = max(1, Int(a.minutosRestantes.rounded()))
        if a.vistos == 0 { return "\(a.total) \(a.total == 1 ? "video nuevo" : "videos nuevos"), \(unos(min, corto: true))" }
        return "\(a.vistos) de \(a.total) videos nuevos, \(teQuedan(min, corto: true))"
    }

    /// La marca de «Ocultar» sigue valiendo: sin `novedad_en`, como en la 2.1.0. Con una novedad posterior a la marca (o
    /// una marca de antes de la 2.2.0, sin fecha), la tarjeta vuelve.
    public static func quitadaVigente(quitada: Bool, marca: Date?, novedadEn: String?) -> Bool {
        guard quitada else { return false }
        guard let n = novedadEn, let d = instante(n) else { return true }
        guard let marca else { return false }
        return d <= marca
    }

    /// La bienvenida de la primera vez: con la tarjeta en Entreno (guía con videos, `mostrar_tarjeta` y sin quitar), sin
    /// ningún video visto y una sola vez por cliente. Sale del resumen: nunca pide el get.
    public static func mostrarBienvenida(_ r: ResumenGuia?, yaVista: Bool, quitada: Bool, ahora: Date = Date()) -> Bool {
        guard !yaVista, let r, r.vistos == 0 else { return false }
        return tarjetaEnEntreno(r, quitada: quitada, ahora: ahora)
    }

    /// «Hola Tomás». Sin nombre en la guía, el nombre de pila de la cuenta (la primera palabra de `nombre`, como Android); si
    /// tampoco hay, «Hola».
    public static func tituloBienvenida(_ nombrePila: String?, nombreCuenta: String? = nil) -> String {
        var n = (nombrePila ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty {
            n = (nombreCuenta ?? "").split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        }
        return n.isEmpty ? "Hola" : "Hola \(n)"
    }

    /// El texto de la bienvenida, en la voz de Mati.
    public static func textoBienvenida(_ a: Avance) -> String {
        let min = max(1, Int(a.minutosRestantes.rounded()))
        let cuantos = a.total == 1 ? "Es un video corto que armé para vos, de \(unos(min, corto: true))."
                                   : "Son \(a.total) videos cortos que armé para vos, \(unos(min, corto: true))."
        return "Antes de empezar, mirá tu guía. \(cuantos) Así en la videollamada vamos directo a lo tuyo."
    }

    // MARK: - Textos

    /// La línea de un clip puede traer «indicación ||| motivo»: la indicación es «Qué hacer» y el motivo, «Para qué».
    public static func partes(_ motivo: String?) -> (hacer: String, paraQue: String) {
        let m = motivo ?? ""
        guard let r = m.range(of: "|||") else { return ("", m.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return (String(m[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines),
                String(m[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// ¿Ya pasó la videollamada? Con hora, contra este instante; solo la fecha, contra hoy en Buenos Aires (como la web).
    public static func yaPaso(_ fecha: String?, ahora: Date = Date()) -> Bool {
        guard let f = fecha?.trimmingCharacters(in: .whitespaces), !f.isEmpty else { return false }
        if f.count > 10 {
            guard let d = fechaISO(f) else { return false }
            return d < ahora
        }
        return String(f.prefix(10)) < diaEnBuenosAires(ahora)
    }

    /// «miércoles 4/11», en la hora de Buenos Aires (la de Mati), como la web.
    public static func fechaLlamada(_ fecha: String?) -> String? {
        guard let f = fecha, let d = fechaISO(f) ?? fechaISO(f + "T12:00:00-03:00") else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zonaBA
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_AR")
        fmt.timeZone = zonaBA
        fmt.dateFormat = "EEEE"
        let c = cal.dateComponents([.day, .month], from: d)
        return "\(fmt.string(from: d)) \(c.day ?? 0)/\(c.month ?? 0)"
    }

    /// El texto de una duda listo para mandar: sin espacios en las puntas y de 1 a 1000 caracteres. nil si no se puede.
    public static func textoParaMandar(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= maxTexto else { return nil }
        return t
    }

    /// Las dudas acumuladas de un video (`duda`, una por renglón).
    public static func renglones(_ duda: String?) -> [String] {
        (duda ?? "").split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
    }

    /// Cuántas veces está una duda en lo que trajo el servidor para un video (las dudas van una tras otra, separadas por
    /// un salto de línea; una duda puede tener varios renglones). Para saber si una duda que se mandó ya llegó.
    public static func veces(_ texto: String, en duda: String?) -> Int {
        guard let duda, !texto.isEmpty else { return 0 }
        let todo = duda.components(separatedBy: "\n"), buscado = texto.components(separatedBy: "\n")
        guard buscado.count <= todo.count else { return 0 }
        var n = 0, i = 0
        while i + buscado.count <= todo.count {
            if Array(todo[i..<(i + buscado.count)]) == buscado { n += 1; i += buscado.count } else { i += 1 }
        }
        return n
    }

    /// Lo mismo para las dudas de la videollamada (una por fila).
    public static func veces(_ texto: String, en dudas: [DudaLlamada]) -> Int {
        dudas.filter { $0.texto == texto }.count
    }

    /// `*negrita*` del PDF en tramos: (texto, en negrita).
    public static func negritas(_ s: String) -> [(texto: String, negrita: Bool)] {
        var out: [(String, Bool)] = []
        var resto = Substring(s)
        while let a = resto.firstIndex(of: "*"), let b = resto[resto.index(after: a)...].firstIndex(of: "*"), b > resto.index(after: a) {
            if a > resto.startIndex { out.append((String(resto[..<a]), false)) }
            out.append((String(resto[resto.index(after: a)..<b]), true))
            resto = resto[resto.index(after: b)...]
        }
        if !resto.isEmpty { out.append((String(resto), false)) }
        return out
    }

    // MARK: - Reproducción

    /// El video con el que abre: el primero sin ver que se pueda reproducir; si vio todos, el primero que se pueda.
    public static func inicial(_ clips: [ClipGuia]) -> Int? {
        clips.firstIndex { !$0.visto && $0.url != nil } ?? clips.firstIndex { $0.url != nil }
    }

    /// El siguiente que se puede reproducir (saltea los que todavía se están subiendo).
    public static func siguiente(_ clips: [ClipGuia], desde i: Int) -> Int? {
        guard i + 1 < clips.count else { return nil }
        return clips[(i + 1)...].firstIndex { $0.url != nil }
    }

    public static func anterior(_ clips: [ClipGuia], desde i: Int) -> Int? {
        guard i > 0, i <= clips.count else { return nil }
        return clips[..<i].lastIndex { $0.url != nil }
    }

    /// Desde dónde retoma: si no está visto y quedó entre el segundo 5 y 5 segundos antes del final. nil = desde el
    /// principio. Sin la duración todavía, no se sabe: desde el principio.
    public static func retomar(_ clip: ClipGuia, duracion: Double) -> Double? {
        guard !clip.visto, duracion.isFinite, duracion > 0 else { return nil }
        let s = Double(clip.segundos)
        return s > 5 && s < duracion - 5 ? s : nil
    }

    /// El video quedó en el final (terminó): tocarlo de nuevo lo arranca desde cero.
    public static func estaAlFinal(_ t: Double, duracion: Double) -> Bool {
        guard t.isFinite, duracion.isFinite, duracion > 0 else { return false }
        return t >= duracion - 0.5
    }

    /// 1x → 1,25x → 1,5x → 1x.
    public static func velocidadSiguiente(_ v: Float) -> Float {
        switch v {
        case ..<1.1: return 1.25
        case ..<1.4: return 1.5
        default: return 1
        }
    }

    /// «1x», «1,25x», «1,5x».
    public static func textoVelocidad(_ v: Float) -> String {
        let s = v == v.rounded() ? String(Int(v)) : String(format: "%g", v).replacingOccurrences(of: ".", with: ",")
        return "\(s)x"
    }

    /// La ceja de la placa: «Otro tema · Video 3 de 13».
    public static func textoPlaca(_ i: Int, de total: Int) -> String { "Otro tema · Video \(i + 1) de \(total)" }

    /// La ceja del reproductor: «Video 3 de 13 · Tu app».
    public static func textoNumero(_ i: Int, de total: Int, bloque: String?) -> String {
        let b = bloque.flatMap { $0.isEmpty ? nil : $0 }
        return "Video \(i + 1) de \(total)" + (b.map { " · \($0)" } ?? "")
    }

    // MARK: - Después de la entrega

    /// Cuánto sigue la tarjeta en Entreno después de la videollamada (`entregas_014`: 48 h exactas).
    public static let horasTarjetaDespues: Double = 48

    /// `mostrar_tarjeta` con la regla de `entregas_014`: se lee primero `ok` (con false, nada). Si el servidor lo mandó,
    /// manda eso. Si no vino (vuelta atrás a la 012), la misma cuenta con `fecha_entrega`: null o antes de las 48 h
    /// siguientes. Sin ninguno de los dos, o con una fecha que no se entiende, se muestra (como antes).
    public static func mostrarTarjeta(_ r: ResumenGuia?, ahora: Date = Date()) -> Bool {
        guard let r, r.ok else { return false }
        if let m = r.mostrarTarjetaServidor { return m }
        guard let f = r.fechaEntrega, let d = instante(f) else { return true }
        return ahora < d.addingTimeInterval(horasTarjetaDespues * 3600)
    }

    /// La tarjeta va en Entreno: hay guía con videos, el servidor (o la cuenta) dice que sí y el cliente no la quitó.
    public static func tarjetaEnEntreno(_ r: ResumenGuia?, quitada: Bool, ahora: Date = Date()) -> Bool {
        r?.hayGuia == true && !quitada && mostrarTarjeta(r, ahora: ahora)
    }

    /// La fila «Ver mi guía» de Mis datos: con `ok: true` y la tarjeta fuera de Entreno (por la fecha o porque la quitó).
    public static func filaEnMisDatos(_ r: ResumenGuia?, quitada: Bool, ahora: Date = Date()) -> Bool {
        r?.ok == true && !tarjetaEnEntreno(r, quitada: quitada, ahora: ahora)
    }

    /// «Volver a mostrar en Entreno»: solo si la quitó y la tarjeta todavía correspondería.
    public static func puedeVolverAMostrar(_ r: ResumenGuia?, quitada: Bool, ahora: Date = Date()) -> Bool {
        quitada && tarjetaEnEntreno(r, quitada: false, ahora: ahora)
    }

    /// Un instante del servidor: ISO con zona (con o sin fracción, de cualquier largo; con «T» o con espacio, como lo
    /// escribe Postgres). Solo la fecha cuenta desde el principio de ese día en Buenos Aires.
    public static func instante(_ s: String) -> Date? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count == 10 { t += "T00:00:00-03:00" }
        if t.count > 10, t[t.index(t.startIndex, offsetBy: 10)] == " " {
            t.replaceSubrange(t.index(t.startIndex, offsetBy: 10)...t.index(t.startIndex, offsetBy: 10), with: "T")
        }
        // La fracción a milésimas (el formateador no entiende microsegundos) y «+00» a «+00:00».
        if let r = t.range(of: #"\.\d+"#, options: .regularExpression) {
            let frac = t[r].dropFirst()
            t.replaceSubrange(r, with: "." + String((frac + "000").prefix(3)))
        }
        if t.range(of: #"[+-]\d{2}$"#, options: .regularExpression) != nil { t += ":00" }
        return fechaISO(t)
    }

    // MARK: - Fechas

    static let zonaBA = TimeZone(identifier: "America/Argentina/Buenos_Aires") ?? TimeZone(secondsFromGMT: -3 * 3600)!

    static func diaEnBuenosAires(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zonaBA
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func fechaISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Cuándo guarda el avance un video que se está reproduciendo: como `timeupdate` de la web, cada 10 s de diferencia con
/// lo último guardado y al pasar el 80 % (ahí con visto); y al terminar. Un video ya visto sigue mandando visto: la base
/// nunca lo vuelve a false y la cola, que deja solo la última op de cada video, tampoco lo pierde.
public struct AvanceVideo: Equatable, Sendable {
    public struct Guardado: Equatable, Sendable {
        public let segundos: Int
        public let visto: Bool
    }

    public private(set) var ultimo: Double
    public private(set) var visto: Bool

    /// `desde`: donde arranca (lo retomado), así retomar no dispara un guardado enseguida.
    public init(visto: Bool, desde: Double = 0) {
        self.visto = visto
        ultimo = desde.isFinite ? max(0, desde) : 0
    }

    /// Se llama con la posición mientras corre (cada segundo, por ejemplo).
    public mutating func alAvanzar(_ t: Double, duracion: Double) -> Guardado? {
        guard t.isFinite, t >= 0 else { return nil }
        let pasa80 = duracion.isFinite && duracion > 0 && t / duracion >= 0.8
        guard abs(t - ultimo) >= 10 || (pasa80 && !visto) else { return nil }
        ultimo = t
        if pasa80 { visto = true }
        return Guardado(segundos: Self.segundos(t), visto: visto)
    }

    /// Al terminar: la duración entera, con visto.
    public mutating func alTerminar(duracion: Double) -> Guardado {
        visto = true
        let d = duracion.isFinite && duracion > 0 ? duracion : ultimo
        ultimo = d
        return Guardado(segundos: Self.segundos(d), visto: true)
    }

    /// Al salir a mitad de video (cerrar, cambiar de video): lo último, si avanzó algo desde lo guardado.
    public mutating func alSalir(_ t: Double) -> Guardado? {
        guard t.isFinite, t > ultimo + 1 else { return nil }
        ultimo = t
        return Guardado(segundos: Self.segundos(t), visto: visto)
    }

    static func segundos(_ t: Double) -> Int { Int(min(Double(ReglasGuia.maxSegundos), max(0, t.rounded()))) }
}

// MARK: - Suplementación

/// «Tu suplementación» como «Tu día» del PDF: un grupo por momento del día, en el orden de `dia`; lo que no tiene
/// momento va en «Además»; lo que sale, en «Dejás de tomar». Port de `bloqueSuple` de la web.
public struct VistaSuplementacion: Equatable, Sendable {
    public struct Fila: Equatable, Sendable, Identifiable {
        public let id: String
        public let nombre: String
        public let cantidad: String?
        public let nota: String?
        public let nuevo: Bool
        public let opcional: Bool
        /// El «por qué», el detalle y «Ver por qué» van solo en la primera toma del ítem.
        public let porQue: String?
        public let detalle: [String]
        public let videoId: String?
        /// El índice del ítem en `items`: la pestaña Suplementación abre su detalle (en cualquiera de sus tomas).
        public let item: Int
    }

    public struct Momento: Equatable, Sendable, Identifiable {
        public let id: String
        public let titulo: String
        public let filas: [Fila]
    }

    public struct Sale: Equatable, Sendable {
        public let nombre: String
        public let porQue: String?
        public let detalle: [String]
        /// El índice del ítem en `items`.
        public let item: Int
    }

    public let titulo: String
    public let accion: String?
    public let momentos: [Momento]
    public let sigue: String?
    public let sale: [Sale]
    /// Los ítems tal como vinieron: el detalle de la pestaña Suplementación lee de acá (`Fila.item`, `Sale.item`).
    public let items: [ItemSuplemento]

    /// Los momentos que conoce el PDF, en su orden del día.
    public static let momentosConocidos: [(String, String)] = [
        ("despertar", "Al despertar"), ("ayunas", "En ayunas"), ("desayuno", "Desayuno"), ("media_manana", "Media mañana"),
        ("almuerzo", "Almuerzo"), ("merienda", "Merienda"), ("pre", "Antes de entrenar"), ("intra", "Mientras entrenás"),
        ("post", "Después de entrenar"), ("cena", "Cena"), ("dormir", "Antes de dormir"), ("noche", "Si te despertás de noche"),
    ]

    /// nil si no hay nada que mostrar (null, vacía o sin ítems).
    public init?(_ s: SuplementacionGuia?) {
        guard let s, !s.items.isEmpty else { return nil }
        var def: [String: MomentoDia] = [:]
        for m in s.dia where def[m.id] == nil { def[m.id] = m }

        struct Toma { let item: Int; let nombre: String?; let cantidad: String?; let nota: String? }
        var tomas: [String: [Toma]] = [:]
        var ordenAparicion: [String] = []
        var sueltos: [Toma] = []
        var sale: [Sale] = []
        for (i, it) in s.items.enumerated() {
            if it.estado == "sale" {
                sale.append(Sale(nombre: it.nombre, porQue: it.porQue, detalle: it.detalle, item: i))
                continue
            }
            let ts: [Toma]?
            if !it.tomas.isEmpty {
                ts = it.tomas.map { Toma(item: i, nombre: $0.nombre, cantidad: $0.cantidad, nota: $0.nota) }
            } else if let m = it.momento, !m.isEmpty {
                ts = [Toma(item: i, nombre: nil, cantidad: it.cantidad, nota: it.nota)]
            } else {
                ts = nil
            }
            guard let ts else {
                sueltos.append(Toma(item: i, nombre: nil, cantidad: it.cantidad, nota: it.nota))
                continue
            }
            let momentos = !it.tomas.isEmpty ? it.tomas.map { $0.momento ?? "" } : [it.momento ?? ""]
            for (t, m) in zip(ts, momentos) {
                if tomas[m] == nil { ordenAparicion.append(m) }
                tomas[m, default: []].append(t)
            }
        }

        var orden = s.dia.map(\.id)
        for (m, _) in Self.momentosConocidos where tomas[m] != nil && !orden.contains(m) { orden.append(m) }
        for m in ordenAparicion where !orden.contains(m) { orden.append(m) }
        if s.dia.isEmpty {
            func pos(_ m: String) -> Int { Self.momentosConocidos.firstIndex { $0.0 == m } ?? 98 }
            orden = orden.enumerated().sorted { (pos($0.element), $0.offset) < (pos($1.element), $1.offset) }.map(\.element)
        }

        var vistos = Set<Int>()
        func fila(_ t: Toma, _ n: Int, momento: String) -> Fila {
            let it = s.items[t.item]
            let primera = vistos.insert(t.item).inserted
            return Fila(id: "\(momento)-\(t.item)-\(n)", nombre: t.nombre.flatMap { $0.isEmpty ? nil : $0 } ?? it.nombre,
                        cantidad: t.cantidad.flatMap { $0.isEmpty ? nil : $0 }, nota: Self.mayuscula(t.nota),
                        nuevo: it.estado == "nuevo", opcional: it.opcional,
                        porQue: primera ? it.porQue : nil, detalle: primera ? it.detalle : [],
                        videoId: primera ? it.videoId : nil, item: t.item)
        }
        var grupos: [Momento] = []
        for m in orden {
            guard let ts = tomas[m] else { continue }
            let titulo = Self.titulo(momento: m, definido: def[m])
            grupos.append(Momento(id: m, titulo: titulo, filas: ts.enumerated().map { fila($1, $0, momento: m) }))
        }
        if !sueltos.isEmpty {
            grupos.append(Momento(id: "_ademas", titulo: "Además", filas: sueltos.enumerated().map { fila($1, $0, momento: "_ademas") }))
        }
        titulo = s.titulo.flatMap { $0.isEmpty ? nil : $0 } ?? "Tu suplementación"
        accion = s.accion
        momentos = grupos
        sigue = s.sigueTexto
        self.sale = sale
        items = s.items
    }

    static let nombresConocidos = Dictionary(momentosConocidos, uniquingKeysWith: { a, _ in a })

    /// El título de un momento: el `nombre` de `dia` si lo trae, si no el texto propio del id, y si el id no se conoce, el
    /// id legible («raro_x» → «Raro x»).
    public static func titulo(momento m: String, dia: [MomentoDia]) -> String {
        titulo(momento: m, definido: dia.first { $0.id == m })
    }

    static func titulo(momento m: String, definido: MomentoDia?) -> String {
        definido?.nombre.flatMap { $0.isEmpty ? nil : $0 } ?? nombresConocidos[m]
            ?? mayuscula(m.replacingOccurrences(of: "_", with: " ")) ?? m
    }

    static func mayuscula(_ s: String?) -> String? {
        let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = t.first else { return nil }
        return p.uppercased() + t.dropFirst()
    }
}
