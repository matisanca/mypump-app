import Foundation
import MyPumpModelos

// La cola B de la 2.3.0: «Tu recorrido» (`fin_plan`), «Dónde comprarlo» (`compras_pais`) y «Entreno en casa» (`casa`).
// Acá va la lectura tolerante de lo que contesta el servidor y las reglas sin estado; el contrato está en
// `supabase/propuestas/nativa_fin_plan.sql`, `nativa_compras_pais.sql` y `nativa_casa.sql`.
//
// En las tres vale lo mismo: lo que no se entiende, no se muestra. Nunca se inventa un dato.

// MARK: - Tu recorrido

public struct LogroRecorrido: Codable, Equatable, Sendable {
    public let titulo: String
    public let valor: String
    public let detalle: String?
    public init(titulo: String, valor: String, detalle: String? = nil) { self.titulo = titulo; self.valor = valor; self.detalle = detalle }
}

/// Lo que armó Mati para el alumno. La app lo muestra tal cual.
public struct ResumenRecorrido: Codable, Equatable, Sendable {
    public let titulo: String?
    public let mensaje: String?
    public let logros: [LogroRecorrido]

    /// nil si no hay ni un logro bien formado: sin logros no hay nada que mostrar.
    public init?(_ j: JSONValue?) {
        guard let j, case .lista(let l)? = j["logros"] else { return nil }
        let logros: [LogroRecorrido] = l.prefix(Recorrido.maxLogros).compactMap { x in
            guard let t = Recorrido.texto(x["titulo"]), let v = Recorrido.texto(x["valor"]) else { return nil }
            return LogroRecorrido(titulo: t, valor: v, detalle: Recorrido.texto(x["detalle"]))
        }
        guard !logros.isEmpty else { return nil }
        self.logros = logros
        titulo = Recorrido.texto(j["titulo"])
        mensaje = Recorrido.texto(j["mensaje"])
    }
}

public struct EstadoRecorrido: Codable, Equatable, Sendable {
    public enum Estado: String, Codable, Sendable { case publicado, pedido, agendado }
    public var estado: Estado
    public let resumen: ResumenRecorrido
    public let respuestas: [String: String]
    /// `true`: el horario se elige en la app. Solo cambia el texto de la confirmación.
    public let agendaEnLaApp: Bool

    /// nil = no se muestra: apagado, no visible, un estado que esta versión no conoce o un resumen sin logros.
    public init?(_ j: JSONValue) {
        guard j["habilitado"] == .bool(true), j["visible"] == .bool(true),
              let e = j["estado"]?.comoTexto.flatMap(Estado.init(rawValue:)), let r = ResumenRecorrido(j["resumen"]) else { return nil }
        estado = e
        resumen = r
        var resp: [String: String] = [:]
        for k in Recorrido.preguntas.map(\.clave) { if let t = Recorrido.texto(j["respuestas"]?[k]) { resp[k] = t } }
        respuestas = resp
        agendaEnLaApp = j["agenda"]?.comoTexto == "app"
    }
}

public enum Recorrido {
    public struct Pregunta: Equatable, Sendable, Identifiable {
        public let clave: String
        public let texto: String
        public var id: String { clave }
    }

    public static let preguntas: [Pregunta] = [
        Pregunta(clave: "mejor", texto: "¿Qué fue lo mejor de estos meses?"),
        Pregunta(clave: "costo", texto: "¿Qué te costó más?"),
        Pregunta(clave: "objetivo", texto: "¿Qué te gustaría lograr ahora?"),
    ]
    public static let maxRespuesta = 500
    public static let maxLogros = 6

    /// Un texto del servidor: sin espacios de más; vacío o de otro tipo = nil.
    static func texto(_ j: JSONValue?) -> String? {
        guard let s = j?.comoTexto?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// Lo que viaja en `p_respuestas`: solo las tres claves, recortadas y con tope; las vacías no van.
    public static func respuestasParaEnviar(_ r: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for p in preguntas {
            let t = String((r[p.clave] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxRespuesta))
            if !t.isEmpty { out[p.clave] = t }
        }
        return out
    }

    /// La marca de «ya se abrió sola»: cambia si Mati publica otro resumen, y ahí se vuelve a mostrar una vez.
    public static func huella(_ r: ResumenRecorrido) -> String {
        ([r.titulo ?? "", r.mensaje ?? ""] + r.logros.flatMap { [$0.titulo, $0.valor, $0.detalle ?? ""] }).joined(separator: "\u{1f}")
    }
}

// MARK: - Dónde comprarlo

public struct OpcionCompra: Codable, Equatable, Sendable {
    public let producto: String
    public let tienda: String
    /// Solo `https://`; cualquier otra cosa queda en nil y la opción se muestra sin botón.
    public let url: URL?
    public let nota: String?
    public init(producto: String, tienda: String, url: URL? = nil, nota: String? = nil) { self.producto = producto; self.tienda = tienda; self.url = url; self.nota = nota }
}

public struct ComprasItem: Codable, Equatable, Sendable {
    public let nombre: String
    public let opciones: [OpcionCompra]
}

public enum Compras {
    public static let maxOpciones = 4

    /// La dirección de una tienda: `https`, con dominio, sin usuario ni contraseña, sin espacios y de largo razonable.
    public static func urlSegura(_ s: String?) -> URL? {
        guard let s, s.count <= 2000, s.hasPrefix("https://"), !s.contains(where: { $0.isWhitespace || $0.isNewline }),
              let c = URLComponents(string: s), c.scheme == "https", let h = c.host, !h.isEmpty, c.user == nil, c.password == nil else { return nil }
        return c.url
    }

    /// Los ítems con al menos una opción bien formada. `habilitado` false, otra forma o nada que mostrar: lista vacía.
    public static func items(_ j: JSONValue) -> [ComprasItem] {
        guard j["habilitado"] == .bool(true), case .lista(let l)? = j["items"] else { return [] }
        return l.compactMap { x in
            guard let n = Recorrido.texto(x["nombre"]), case .lista(let os)? = x["opciones"] else { return nil }
            let opciones: [OpcionCompra] = os.prefix(maxOpciones).compactMap { o in
                guard let p = Recorrido.texto(o["producto"]), let t = Recorrido.texto(o["tienda"]) else { return nil }
                return OpcionCompra(producto: p, tienda: t, url: urlSegura(o["url"]?.comoTexto), nota: Recorrido.texto(o["nota"]))
            }
            return opciones.isEmpty ? nil : ComprasItem(nombre: n, opciones: opciones)
        }
    }

    /// Las opciones del ítem de la pestaña con ese nombre: tiene que coincidir entero (salvo espacios de afuera).
    public static func opciones(para nombre: String, en items: [ComprasItem]) -> [OpcionCompra] {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return [] }
        return items.first { $0.nombre == n }?.opciones ?? []
    }
}

// MARK: - Entreno en casa

public struct TipoCasa: Codable, Equatable, Sendable, Identifiable {
    public let tipo: String
    public let nombre: String
    /// Al marcarlo se puede anotar hasta cuántos kilos.
    public let kg: Bool
    public init(tipo: String, nombre: String, kg: Bool = false) { self.tipo = tipo; self.nombre = nombre; self.kg = kg }
    public var id: String { tipo }
}

public struct EquipoCasa: Codable, Equatable, Sendable {
    public let tipo: String
    public let kg: Double?
    public init(tipo: String, kg: Double? = nil) { self.tipo = tipo; self.kg = kg }
}

public struct CargaCasa: Codable, Equatable, Sendable {
    public let id: String
    public let estado: String
    /// `gimnasio` o `casa`. Otro valor se trata como gimnasio (lo de siempre).
    public let enCasa: Bool
    public let equipos: [EquipoCasa]
    public let sinEquipo: Bool
    public let nota: String?

    public init?(_ j: JSONValue?) {
        guard let j, let id = j["id"]?.comoTexto, let estado = j["estado"]?.comoTexto else { return nil }
        self.id = id
        self.estado = estado
        enCasa = j["lugar"]?.comoTexto == "casa"
        var es: [EquipoCasa] = []
        if case .lista(let l)? = j["equipos"] {
            es = l.compactMap { e in e["tipo"]?.comoTexto.map { EquipoCasa(tipo: $0, kg: e["kg"]?.comoNumero.flatMap { $0 > 0 ? $0 : nil }) } }
        }
        equipos = es
        sinEquipo = j["sin_equipo"] == .bool(true)
        nota = Recorrido.texto(j["nota"])
    }
}

public struct EstadoCasa: Codable, Equatable, Sendable {
    public let tipos: [TipoCasa]
    public let abierta: CargaCasa?
    public let vigente: CargaCasa?

    /// nil: no es una respuesta con `habilitado:true`, o no trae la lista para marcar.
    public init?(_ j: JSONValue) {
        guard j["habilitado"] == .bool(true), case .lista(let l)? = j["tipos"] else { return nil }
        var vistos = Set<String>()
        tipos = l.compactMap { t in
            guard let tipo = t["tipo"]?.comoTexto, !tipo.isEmpty, let n = Recorrido.texto(t["nombre"]), vistos.insert(tipo).inserted else { return nil }
            return TipoCasa(tipo: tipo, nombre: n, kg: t["kg"] == .bool(true))
        }
        guard !tipos.isEmpty else { return nil }
        abierta = CargaCasa(j["abierta"])
        vigente = CargaCasa(j["vigente"])
    }
}

public enum Casa {
    public static let kilosMaximo = 400.0
    public static let maxNota = 300

    /// El interruptor está prendido: la carga abierta es de casa o, sin carga abierta, la vigente es de casa.
    public static func prendido(_ e: EstadoCasa?) -> Bool {
        guard let e else { return false }
        if let a = e.abierta { return a.enCasa }
        return e.vigente?.enCasa ?? false
    }

    /// Con una carga ya enviada el lugar no se cambia hasta que quede lista.
    public static func fijo(_ e: EstadoCasa?) -> Bool {
        guard let a = e?.abierta else { return false }
        return a.estado != "borrador"
    }

    public enum Pantalla: Equatable, Sendable { case ninguna, lista, recibido, vigente }

    /// Qué muestra Mi gimnasio del lado de casa. `ninguna` = lo de siempre (el gimnasio).
    public static func pantalla(_ e: EstadoCasa?) -> Pantalla {
        guard let e else { return .ninguna }
        if let a = e.abierta {
            guard a.enCasa else { return .ninguna }
            return a.estado == "borrador" ? .lista : .recibido
        }
        return e.vigente?.enCasa == true ? .vigente : .ninguna
    }

    /// Los kilos que escribió: «20», «12,5». Fuera de 1 a 400 o que no es un número = nil (no viaja).
    public static func kilos(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let v = Double(t), v >= 1, v <= kilosMaximo else { return nil }
        return (v * 10).rounded() / 10
    }

    /// «hasta 20 kg», «hasta 12,5 kg».
    public static func textoKilos(_ kg: Double) -> String {
        let s = kg == kg.rounded() ? String(Int(kg)) : String(format: "%.1f", kg).replacingOccurrences(of: ".", with: ",")
        return "hasta \(s) kg"
    }

    /// Se puede enviar: algo marcado, o «No tengo nada de esto» (nunca las dos cosas).
    public static func puedeEnviar(marcados: Set<String>, sinEquipo: Bool) -> Bool { sinEquipo ? marcados.isEmpty : !marcados.isEmpty }

    /// Lo que viaja en `p_equipos`: en el orden de la lista del servidor, solo tipos de esa lista, kilos solo donde van.
    public static func equiposParaEnviar(tipos: [TipoCasa], marcados: Set<String>, kilos: [String: String]) -> [EquipoCasa] {
        tipos.filter { marcados.contains($0.tipo) }.map { t in
            EquipoCasa(tipo: t.tipo, kg: t.kg ? kilos[t.tipo].flatMap(Casa.kilos) : nil)
        }
    }
}
