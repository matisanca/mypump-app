import Foundation
import MyPumpModelos

/// «Lo que más te importa»: las reglas de `pack.html` (`partesDolor`, `htmlDolor` y `htmlExtra`), con los mismos casos que
/// Android (`apps/shared/fixtures/guia/dolor-casos.json`). Sin `dolor`, o con el texto en blanco, no hay vista y la guía
/// queda como en la 2.2.0.
public enum ReglasDolor {
    public static let tituloBloque = "Lo que más te importa"
    public static let tituloVideos = "Tus videos sobre esto"

    /// Una parte aparte: un párrafo «## Título» del texto y lo que le sigue.
    public struct Parte: Equatable, Sendable {
        public let titulo: String
        public let parrafos: [String]
    }

    public struct Vista: Equatable, Sendable {
        public let subtitulo: String?
        public let parrafos: [String]
        public let partes: [Parte]
    }

    /// Qué capítulo va en cada recuadro y cuáles siguen en la lista de siempre.
    public struct Reparto: Equatable, Sendable {
        public let principal: ReglasGuia.Bloque?
        public let partes: [ReglasGuia.Bloque?]
        public let resto: [ReglasGuia.Bloque]
    }

    public enum EstadoPaso: Equatable, Sendable { case hecho, ahora, pendiente }

    public struct Paso: Equatable, Sendable, Identifiable {
        public let id: String
        public let numero: Int
        public let titulo: String
        public let estado: EstadoPaso
    }

    public struct Introduccion: Equatable, Sendable {
        public let texto: String
        public let pasos: [Paso]
    }

    /// `/^lo que m[aá]s te importa$/i`, sobre el título sin espacios en las puntas.
    public static func esBloqueDolor(_ titulo: String?) -> Bool {
        recortar(titulo ?? "").lowercased().replacingOccurrences(of: "á", with: "a") == "lo que mas te importa"
    }

    public static func vista(_ dolor: DolorGuia?) -> Vista? {
        guard let dolor, !recortar(dolor.texto).isEmpty else { return nil }
        var principal: [String] = []
        var partes: [(titulo: String, parrafos: [String])] = []
        for crudo in dividir(dolor.texto) {
            let t = recortar(crudo)
            if let titulo = tituloDeParte(t) {
                partes.append((titulo, []))
            } else if let p = limpiarParrafo(t) {
                if partes.isEmpty { principal.append(p) } else { partes[partes.count - 1].parrafos.append(p) }
            }
        }
        // Lo que había era solo markup: es lo mismo que vacío.
        guard !principal.isEmpty || !partes.isEmpty else { return nil }
        let subtitulo = dolor.titulo.map(limpiarLinea).flatMap { $0.isEmpty || esBloqueDolor($0) ? nil : $0 }
        return Vista(subtitulo: subtitulo, parrafos: principal, partes: partes.map { Parte(titulo: $0.titulo, parrafos: $0.parrafos) })
    }

    /// Los capítulos de cada recuadro: el del dolor y los que se llaman como una parte. Un capítulo va una sola vez (si dos
    /// partes se titulan igual, va en la primera). «Novedad» nunca entra. Sin vista, todo sigue en `resto`.
    public static func reparto(_ bloques: [ReglasGuia.Bloque], _ v: Vista?) -> Reparto {
        guard let v else { return Reparto(principal: nil, partes: [], resto: bloques) }
        var usados: Set<String> = []
        func tomar(_ cumple: (ReglasGuia.Bloque) -> Bool) -> ReglasGuia.Bloque? {
            guard let b = bloques.first(where: { !$0.novedad && !usados.contains($0.id) && cumple($0) }) else { return nil }
            usados.insert(b.id)
            return b
        }
        let principal = tomar { esBloqueDolor($0.titulo) }
        let partes = v.partes.map { p in tomar { $0.titulo == p.titulo } }
        return Reparto(principal: principal, partes: partes, resto: bloques.filter { !usados.contains($0.id) })
    }

    /// Los videos del recuadro van primero también en el reproductor, como `PRIO` en la web. Los `nuevo` no pasan por acá.
    public static func conDolorPrimero(_ clips: [ClipGuia], _ dolor: DolorGuia?) -> [ClipGuia] {
        guard let v = vista(dolor) else { return clips }
        func rango(_ c: ClipGuia) -> Int {
            let t = ReglasGuia.claveBloque(c)
            if esBloqueDolor(t) { return 0 }
            if let i = v.partes.firstIndex(where: { $0.titulo == t }) { return i + 1 }
            return Int.max
        }
        return clips.enumerated().sorted { a, b in
            let (ra, rb) = (rango(a.element), rango(b.element))
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// La línea y los pasos de arriba de la guía, solo con `dolor` y antes de la videollamada. Son dos pasos, los de la web
    /// sin el de entrar a la app. Sin fecha, la línea va sin fecha.
    public static func introduccion(_ g: Guia?, hayDudas: Bool, ahora: Date = Date()) -> Introduccion? {
        guard let g, vista(g.dolor) != nil, !ReglasGuia.yaPaso(g.fechaEntrega, ahora: ahora) else { return nil }
        let cuando = ReglasGuia.fechaLlamada(g.fechaEntrega).map { " del \($0)" } ?? ""
        let lista = ReglasGuia.deLaLista(g)
        let vistos = !lista.isEmpty && lista.allSatisfy(\.visto)
        return Introduccion(texto: "Antes de nuestra videollamada\(cuando), hacé estos dos pasos.", pasos: [
            Paso(id: "videos", numero: 1, titulo: "Mirá tus videos", estado: vistos ? .hecho : .ahora),
            Paso(id: "dudas", numero: 2, titulo: "Dejá tus dudas", estado: hayDudas ? .hecho : .pendiente),
        ])
    }

    /// Lo que dice VoiceOver de un paso.
    public static func textoHablado(_ p: Paso, de total: Int) -> String {
        let estado = p.estado == .hecho ? ", hecho" : p.estado == .ahora ? ", es el que sigue" : ""
        return "Paso \(p.numero) de \(total), \(p.titulo)\(estado)"
    }

    // MARK: - Texto

    private static let espacio = "[\\s\\x0B\\p{Z}\\uFEFF]"
    private static let blancos: CharacterSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))

    private static func recortar(_ s: String) -> String { s.trimmingCharacters(in: blancos) }

    /// `split(/\n\s*\n/)`: los párrafos van separados por una línea en blanco.
    private static func dividir(_ s: String) -> [String] {
        let r = regex("\\r?\\n\(espacio)*?\\n")
        let n = s as NSString
        var out: [String] = [], desde = 0
        for m in r.matches(in: s, range: NSRange(location: 0, length: n.length)) {
            out.append(n.substring(with: NSRange(location: desde, length: m.range.location - desde)))
            desde = m.range.location + m.range.length
        }
        out.append(n.substring(from: desde))
        return out
    }

    /// `/^##\s+(.+)$/`: un párrafo de una sola línea.
    private static func tituloDeParte(_ t: String) -> String? {
        guard t.hasPrefix("##"), !t.contains(where: \.isNewline),
              let primero = t.dropFirst(2).unicodeScalars.first, blancos.contains(primero) else { return nil }
        let titulo = limpiarInline(recortar(String(t.dropFirst(2))))
        return titulo.isEmpty ? nil : titulo
    }

    /// El párrafo como lo lee el cliente: un salto simple es un espacio (como en el HTML), salvo en una lista, y sin las
    /// marcas de markdown. nil si no queda texto.
    private static func limpiarParrafo(_ t: String) -> String? {
        var hayLista = false
        var lineas: [String] = []
        for cruda in t.components(separatedBy: .newlines) {
            let s = quitar(regla: "^#{1,6}(?:\(espacio)+|$)", de: quitar(regla: "^>\(espacio)*", de: recortar(cruda)))
            if esSeparador(s) { continue }
            if let i = rango(de: "^[-*+•]\(espacio)+", en: s) {
                hayLista = true
                let resto = limpiarInline(String(s[i.upperBound...]))
                if !resto.isEmpty { lineas.append("• " + resto) }
            } else {
                let limpia = limpiarInline(s)
                if !limpia.isEmpty { lineas.append(limpia) }
            }
        }
        guard !lineas.isEmpty else { return nil }
        return lineas.joined(separator: hayLista ? "\n" : " ")
    }

    private static func limpiarLinea(_ s: String) -> String {
        limpiarInline(quitar(regla: "^#{1,6}(?:\(espacio)+|$)", de: recortar(s)))
    }

    private static func esSeparador(_ s: String) -> Bool {
        rango(de: "^([-*_])(?:\(espacio)*\\1){2,}\(espacio)*$", en: s) != nil
    }

    private static let inlines: [(String, String)] = [
        ("!?\\[([^\\]]+)\\]\\([^)\\s]+\\)", "$1"),
        ("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*", "$1"),
        ("(?<![\\p{L}\\p{N}_])__(?=\\S)(.+?)(?<=\\S)__(?![\\p{L}\\p{N}_])", "$1"),
        ("~~(?=\\S)(.+?)(?<=\\S)~~", "$1"),
        ("(?<![\\p{L}\\p{N}_*])\\*(?=[^\\s*])(.+?)(?<=[^\\s*])\\*(?![\\p{L}\\p{N}_*])", "$1"),
        ("(?<![\\p{L}\\p{N}_])_(?=[^\\s_])(.+?)(?<=[^\\s_])_(?![\\p{L}\\p{N}_])", "$1"),
        ("`([^`\\n]+)`", "$1"),
    ]

    private static func limpiarInline(_ s: String) -> String {
        var t = s
        for (p, plantilla) in inlines {
            t = regex(p).stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: plantilla)
        }
        return recortar(t)
    }

    private static func quitar(regla p: String, de s: String) -> String {
        regex(p).stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
    }

    private static func rango(de p: String, en s: String) -> Range<String.Index>? {
        regex(p).firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)).flatMap { Range($0.range, in: s) }
    }

    private static func regex(_ p: String) -> NSRegularExpression {
        // Los patrones son constantes de este archivo: si uno no compila, lo agarran los tests.
        try! NSRegularExpression(pattern: p)
    }
}
