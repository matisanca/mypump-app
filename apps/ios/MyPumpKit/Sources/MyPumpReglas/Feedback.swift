import Foundation
import MyPumpModelos

/// «Me duele» por ejercicio (2.3.0, `supabase/propuestas/nativa_feedback_alumno.sql`). Los valores son los del servidor; los
/// textos, los de `TextosFeedback`. Gemelo de Feedback.kt; `apps/shared/fixtures/feedback/casos.json` hace fallar si difieren.
public enum ReglasMolestia {
    public static let maxNota = 500

    public struct Opcion: Equatable, Sendable, Identifiable {
        public let id: String
        public let texto: String
    }

    /// Zona → nombre, si es femenino y lo que va después del lado («Muslo derecho adelante»).
    static let zonas: [(id: String, nombre: String, femenino: Bool, cola: String)] = [
        ("cuello", "Cuello", false, ""), ("hombro", "Hombro", false, ""), ("pecho", "Pecho", false, ""), ("brazo", "Brazo", false, ""),
        ("codo", "Codo", false, ""), ("antebrazo", "Antebrazo", false, ""), ("muneca", "Muñeca o mano", true, ""),
        ("abdomen", "Abdomen", false, ""), ("espalda_alta", "Espalda alta", true, ""), ("espalda_baja", "Espalda baja", true, ""),
        ("cadera", "Cadera", true, ""), ("gluteo", "Glúteo", false, ""), ("muslo_frente", "Muslo", false, " adelante"),
        ("muslo_atras", "Muslo", false, " atrás"), ("rodilla", "Rodilla", true, ""), ("pantorrilla", "Pantorrilla", true, ""),
        ("tobillo", "Tobillo o pie", false, ""),
    ]
    public static let lados = ["izquierdo", "derecho", "ambos", "centro"]

    /// Lo que se puede elegir cuando la zona tiene lado.
    public static let ladosElegibles = [Opcion(id: "derecho", texto: TextosFeedback.dueleLadoDerecho), Opcion(id: "izquierdo", texto: TextosFeedback.dueleLadoIzquierdo),
                                        Opcion(id: "ambos", texto: TextosFeedback.dueleLadoAmbos)]

    public static let desde = [Opcion(id: "hoy", texto: "Hoy"), Opcion(id: "esta_semana", texto: "Esta semana"),
                               Opcion(id: "semanas", texto: "Hace unas semanas"), Opcion(id: "mas_de_un_mes", texto: "Más de un mes")]
    public static let cuando = [Opcion(id: "al_bajar", texto: "Al bajar"), Opcion(id: "al_subir", texto: "Al subir"),
                                Opcion(id: "todo_el_recorrido", texto: "En todo el recorrido"), Opcion(id: "despues", texto: "Después de entrenar"),
                                Opcion(id: "al_dia_siguiente", texto: "Al día siguiente")]
    public static let tipo = [Opcion(id: "punzante", texto: "Punzante"), Opcion(id: "sordo", texto: "Sordo, de fondo"),
                              Opcion(id: "hormigueo", texto: "Hormigueo")]

    /// La escala simple: cuatro escalones que se guardan como 2, 5, 7 y 9 de 10.
    public struct Nivel: Equatable, Sendable, Identifiable {
        public let id: Int
        public let texto: String
    }
    public static let niveles = [Nivel(id: 2, texto: "Poco"), Nivel(id: 5, texto: "Bastante"), Nivel(id: 7, texto: "Mucho"), Nivel(id: 9, texto: "No puedo seguir")]

    /// El escalón de una intensidad guardada (0 a 10): hasta 3 poco, hasta 5 bastante, hasta 7 mucho.
    public static func nivel(_ intensidad: Int) -> Nivel {
        intensidad <= 3 ? niveles[0] : intensidad <= 5 ? niveles[1] : intensidad <= 7 ? niveles[2] : niveles[3]
    }

    /// Desde «Mucho» se suma la línea de dejar el ejercicio por hoy. No es un diagnóstico: es no seguir cargando algo que duele.
    public static func esFuerte(_ intensidad: Int) -> Bool { intensidad >= 7 }

    public static func zonaValida(_ z: String) -> Bool { zonas.contains { $0.id == z } }

    /// «Hombro derecho», «Muñeca o mano izquierda», «Muslo derecho adelante», «Rodilla, los dos lados», «Espalda baja».
    public static func nombreZona(_ zona: String, lado: String) -> String {
        guard let z = zonas.first(where: { $0.id == zona }) else { return "" }
        switch lado {
        case "izquierdo": return "\(z.nombre) \(z.femenino ? "izquierda" : "izquierdo")\(z.cola)"
        case "derecho": return "\(z.nombre) \(z.femenino ? "derecha" : "derecho")\(z.cola)"
        case "ambos": return "\(z.nombre)\(z.cola), los dos lados"
        default: return z.nombre + z.cola
        }
    }

    /// Por puntos de código, como cuenta el SQL.
    public static func nota(_ s: String) -> String {
        var v = String.UnicodeScalarView(); v.append(contentsOf: s.unicodeScalars.prefix(maxNota)); return String(v)
    }

    /// Lo que se manda. `completa` = se puede avisar.
    public struct Borrador: Equatable, Sendable {
        public var zona: String?
        public var lado: String?
        public var desde: String?
        public var cuando: String?
        public var tipo: String?
        public var intensidad: Int?
        public var nota = ""
        public init() {}

        public init(_ m: Molestia) {
            zona = m.zona; lado = m.lado; desde = m.desde; cuando = m.cuando; tipo = m.tipo; nota = m.nota ?? ""
            intensidad = m.intensidad.map { ReglasMolestia.nivel($0).id }
        }

        public var completa: Bool {
            guard let zona, let lado, let desde, let cuando, let tipo, let intensidad else { return false }
            return ReglasMolestia.zonaValida(zona) && ReglasMolestia.lados.contains(lado)
                && ReglasMolestia.desde.contains { $0.id == desde } && ReglasMolestia.cuando.contains { $0.id == cuando }
                && ReglasMolestia.tipo.contains { $0.id == tipo } && (0...10).contains(intensidad)
        }

        public var nombreZona: String? { zona.flatMap { z in lado.map { ReglasMolestia.nombreZona(z, lado: $0) } } }
    }
}

/// Una molestia como la devuelve `mypump_feedback_get`. Al alumno no le llega nada interno (ni destino ni resolución).
public struct Molestia: Equatable, Sendable, Identifiable {
    public let id: String
    public let ejercicioId: String
    public let ejercicioNombre: String
    public let zona: String
    public let lado: String
    public var desde: String?
    public var cuando: String?
    public var tipo: String?
    public var intensidad: Int?
    public var nota: String?
    /// `avisada` o `resuelta`. Otro valor (de un servidor más nuevo) se descarta al decodificar.
    public let estado: String

    public var abierta: Bool { estado == "avisada" }
    public var nombreZona: String { ReglasMolestia.nombreZona(zona, lado: lado) }

    public init?(_ j: JSONValue?) {
        guard let j, let id = j["id"]?.comoTexto, !id.isEmpty, let e = j["ejercicio_id"]?.comoTexto, !e.isEmpty,
              let zona = j["zona"]?.comoTexto, ReglasMolestia.zonaValida(zona),
              let estado = j["estado"]?.comoTexto, estado == "avisada" || estado == "resuelta" else { return nil }
        let lado = j["lado"]?.comoTexto ?? "centro"
        self.id = id; ejercicioId = e; ejercicioNombre = j["ejercicio_nombre"]?.comoTexto ?? ""
        self.zona = zona; self.lado = ReglasMolestia.lados.contains(lado) ? lado : "centro"; self.estado = estado
        desde = j["desde"]?.comoTexto; cuando = j["cuando"]?.comoTexto; tipo = j["tipo"]?.comoTexto
        if let n = j["intensidad"]?.comoNumero, n.isFinite, (0...10).contains(n) { intensidad = Int(n) }
        nota = j["nota"]?.comoTexto.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// «Lo compré / lo estoy tomando»: una marca por ítem, una sola vez, y se puede cambiar.
public enum ReglasSupleEstado {
    public enum Estado: String, Sendable, CaseIterable, Identifiable {
        case comprado, tomando, noLoConsigo = "no_lo_consigo", loDeje = "lo_deje"
        public var id: String { rawValue }

        /// Lo que elige el alumno.
        public var accion: String {
            switch self {
            case .comprado: "Lo compré"
            case .tomando: "Lo estoy tomando"
            case .noLoConsigo: "No lo consigo"
            case .loDeje: "Lo dejé"
            }
        }

        /// Cómo queda marcado.
        public var marcado: String {
            switch self {
            case .comprado: "Comprado"
            case .tomando: "Lo estás tomando"
            case .noLoConsigo: "No lo conseguís"
            case .loDeje: "Lo dejaste"
            }
        }
    }

    /// La clave de un ítem, la misma cuenta que `mypump_suple_clave`: minúsculas, sin tildes y con un solo espacio.
    public static func clave(_ nombre: String) -> String {
        let tabla: [Character: Character] = ["á": "a", "à": "a", "ä": "a", "â": "a", "é": "e", "è": "e", "ë": "e", "ê": "e", "í": "i", "ì": "i", "ï": "i", "î": "i",
                                             "ó": "o", "ò": "o", "ö": "o", "ô": "o", "ú": "u", "ù": "u", "ü": "u", "û": "u", "ñ": "n"]
        let plano = String(nombre.precomposedStringWithCanonicalMapping.lowercased().map { tabla[$0] ?? $0 })
        return plano.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public struct Fila: Equatable, Sendable, Identifiable {
        public let id: String          // la clave
        public let nombre: String
        public let estado: Estado?
    }

    /// Lo que se puede marcar: cada suplemento una vez, en el orden del plan. Los protectores (fármacos) no van nunca; lo
    /// que «sale» tampoco, salvo que ya tenga una marca.
    public static func filas(_ items: [ItemSuplemento], marcas: [String: Estado]) -> [Fila] {
        var vistos = Set<String>()
        var salen: [Fila] = []
        for it in items where !it.protector {
            let k = clave(it.nombre)
            guard !k.isEmpty, vistos.insert(k).inserted else { continue }
            if it.estado == "sale", marcas[k] == nil { continue }
            salen.append(Fila(id: k, nombre: it.nombre.trimmingCharacters(in: .whitespacesAndNewlines), estado: marcas[k]))
        }
        return salen
    }

    /// «2 de 5 marcados», para el encabezado.
    public static func resumen(_ filas: [Fila]) -> String {
        "\(filas.filter { $0.estado != nil }.count) de \(filas.count) marcados"
    }
}

/// Lo que devuelve `mypump_feedback_get`. Tolerante: lo que no se entiende se descarta.
public struct EstadoFeedback: Equatable, Sendable {
    public var dueleHabilitado = false
    public var molestias: [Molestia] = []
    public var supleHabilitado = false
    public var marcas: [String: ReglasSupleEstado.Estado] = [:]

    public init() {}

    public init?(_ j: JSONValue) {
        guard case .objeto = j else { return nil }
        if case .bool(let b)? = j["me_duele"]?["habilitado"] { dueleHabilitado = b }
        if case .lista(let l)? = j["me_duele"]?["molestias"] { molestias = l.compactMap { Molestia($0) } }
        if case .bool(let b)? = j["suple_estado"]?["habilitado"] { supleHabilitado = b }
        if case .lista(let l)? = j["suple_estado"]?["items"] {
            for x in l {
                if let k = x["item"]?.comoTexto, !k.isEmpty, let e = x["estado"]?.comoTexto.flatMap(ReglasSupleEstado.Estado.init(rawValue:)) { marcas[k] = e }
            }
        }
    }

    /// La molestia que se muestra en un ejercicio: la abierta, o la última cerrada.
    public func molestia(ejercicio id: String) -> Molestia? {
        let suyas = molestias.filter { $0.ejercicioId == id }
        return suyas.first { $0.abierta } ?? suyas.first
    }
}
