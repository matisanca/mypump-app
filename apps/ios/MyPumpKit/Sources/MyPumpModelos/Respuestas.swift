import Foundation

// Filas que devuelven las RPC de lectura (ver docs/NATIVA_CONTRATO.md §2). Las fechas quedan como texto ISO: las
// interpreta la capa de reglas con calendario gregoriano y en_US_POSIX.

public struct ClienteInfo: Decodable, Sendable, Equatable {
    public let clienteId: String
    public let nombre: String?
    public let perfil: String?
    enum CodingKeys: String, CodingKey { case clienteId = "cliente_id", nombre, perfil }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clienteId = c.texto(.clienteId) ?? ""; nombre = c.texto(.nombre); perfil = c.texto(.perfil)
    }
}

/// `get_historico_por_clave` (trae `clave`) y el camino viejo por lugar (`ejercicio_id`).
public struct RegistroHistorico: Decodable, Sendable, Equatable {
    public let clave: String?
    public let ejercicioId: String?
    public let registradoEn: String
    public let pesoKg: Double?
    public let reps: Int?
    public let rir: Int?
    public let serie: Int?
    public let notas: String?
    public let ejercicioNombre: String?
    enum CodingKeys: String, CodingKey {
        case clave, ejercicioId = "ejercicio_id", registradoEn = "registrado_en", pesoKg = "peso_kg"
        case reps = "reps_realizadas", rir = "rir_real", serie = "serie_numero", notas, ejercicioNombre = "ejercicio_nombre"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clave = c.texto(.clave); ejercicioId = c.texto(.ejercicioId); registradoEn = c.texto(.registradoEn) ?? ""
        pesoKg = c.decimal(.pesoKg); reps = c.entero(.reps); rir = c.entero(.rir); serie = c.entero(.serie)
        notas = c.texto(.notas); ejercicioNombre = c.texto(.ejercicioNombre)
    }
}

/// `get_registros_sesion` (fila de `mypump_registros_carga`).
public struct RegistroSesion: Decodable, Sendable, Equatable {
    public let ejercicioId: String
    public let serie: Int
    public let pesoKg: Double?
    public let reps: Int?
    public let rir: Int?
    public let ejercicioNombre: String?
    public let notas: String?
    enum CodingKeys: String, CodingKey {
        case ejercicioId = "ejercicio_id", serie = "serie_numero", pesoKg = "peso_kg", reps = "reps_realizadas"
        case rir = "rir_real", ejercicioNombre = "ejercicio_nombre", notas
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ejercicioId = c.texto(.ejercicioId) ?? ""; serie = c.entero(.serie) ?? 1; pesoKg = c.decimal(.pesoKg)
        reps = c.entero(.reps); rir = c.entero(.rir); ejercicioNombre = c.texto(.ejercicioNombre); notas = c.texto(.notas)
    }
}

public struct EstadoEjercicio: Decodable, Sendable, Equatable {
    public let ejercicioId: String
    public let status: String
    public let seriesCompletadas: Int?
    public let marcadoManualmente: Bool
    enum CodingKeys: String, CodingKey {
        case ejercicioId = "ejercicio_id", status, seriesCompletadas = "series_completadas", marcadoManualmente = "marcado_manualmente"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ejercicioId = c.texto(.ejercicioId) ?? ""; status = c.texto(.status) ?? "pendiente"
        seriesCompletadas = c.entero(.seriesCompletadas); marcadoManualmente = c.booleano(.marcadoManualmente) ?? false
    }
}

/// `get_sesion_dia` (con `id`) y `get_sesiones_semana` (sin `id`).
public struct Sesion: Decodable, Sendable, Equatable {
    public let id: String?
    public let diaId: String
    public let semana: Int?
    public let iniciadaEn: String?
    public let finalizadaEn: String?
    enum CodingKeys: String, CodingKey { case id, diaId = "dia_id", semana, iniciadaEn = "iniciada_en", finalizadaEn = "finalizada_en" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id); diaId = c.texto(.diaId) ?? ""; semana = c.entero(.semana)
        iniciadaEn = c.texto(.iniciadaEn); finalizadaEn = c.texto(.finalizadaEn)
    }
    public var cerrada: Bool { finalizadaEn != nil }
}

public struct HabitosDia: Decodable, Sendable, Equatable {
    public let fecha: String?
    public let entrenamiento: String?
    public let comioSegunPlan: Bool?
    public let durmioBien: Bool?
    public let cardio: Bool?
    public let vasosAgua: Int?
    enum CodingKeys: String, CodingKey {
        case fecha, entrenamiento, comioSegunPlan = "comio_segun_plan", durmioBien = "durmio_bien", cardio, vasosAgua = "vasos_agua"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fecha = c.texto(.fecha); entrenamiento = c.texto(.entrenamiento); comioSegunPlan = c.booleano(.comioSegunPlan)
        durmioBien = c.booleano(.durmioBien); cardio = c.booleano(.cardio); vasosAgua = c.entero(.vasosAgua)
    }
}

public struct Racha: Decodable, Sendable, Equatable {
    public let streak: Int
    public let ultimoDiaValido: String?
    enum CodingKeys: String, CodingKey { case streak, ultimoDiaValido = "ultimo_dia_valido" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = c.entero(.streak) ?? 0; ultimoDiaValido = c.texto(.ultimoDiaValido)
    }
}

public struct DiaAdherencia: Decodable, Sendable, Equatable {
    public let fecha: String
    public let entrenamiento: String?
    public let comioSegunPlan: Bool?
    public let durmioBien: Bool?
    public let vasosAgua: Int?
    public let esValido: Bool
    enum CodingKeys: String, CodingKey {
        case fecha, entrenamiento, comioSegunPlan = "comio_segun_plan", durmioBien = "durmio_bien", vasosAgua = "vasos_agua", esValido = "es_valido"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fecha = c.texto(.fecha) ?? ""; entrenamiento = c.texto(.entrenamiento); comioSegunPlan = c.booleano(.comioSegunPlan)
        durmioBien = c.booleano(.durmioBien); vasosAgua = c.entero(.vasosAgua); esValido = c.booleano(.esValido) ?? false
    }
}

public struct ComidaMarcada: Decodable, Sendable, Equatable {
    public let comidaId: String
    public let opcionElegida: String?
    public let estado: String?
    public let marcadaEn: String?
    public let foodsExcluidos: [Int]
    enum CodingKeys: String, CodingKey {
        case comidaId = "comida_id", opcionElegida = "opcion_elegida", estado, marcadaEn = "marcada_en", foodsExcluidos = "foods_excluidos"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        comidaId = c.texto(.comidaId) ?? ""; opcionElegida = c.texto(.opcionElegida); estado = c.texto(.estado)
        marcadaEn = c.texto(.marcadaEn); foodsExcluidos = c.lista(Int.self, .foodsExcluidos)
    }
}

public struct ComidaLibre: Decodable, Sendable, Equatable {
    public let id: String
    public let fecha: String?
    public let hora: String?
    public let descripcion: String?
    public let kcal: Double?
    public let prot: Double?
    public let carb: Double?
    public let fat: Double?
    public let detalle: JSONValue?
    enum CodingKeys: String, CodingKey { case id, fecha, hora, descripcion, kcal, prot, carb, fat, detalle }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id) ?? ""; fecha = c.texto(.fecha); hora = c.texto(.hora); descripcion = c.texto(.descripcion)
        kcal = c.decimal(.kcal); prot = c.decimal(.prot); carb = c.decimal(.carb); fat = c.decimal(.fat)
        detalle = try? c.decodeIfPresent(JSONValue.self, forKey: .detalle)
    }
}

public struct FoodSwap: Decodable, Sendable, Equatable {
    public let comidaId: String
    public let optIdx: Int
    public let foodIdx: Int
    /// Se conserva entero (`_orig`, `_dev`, `_isCustom`…) para devolverlo igual al servidor.
    public let foodData: JSONValue
    enum CodingKeys: String, CodingKey { case comidaId = "comida_id", optIdx = "opt_idx", foodIdx = "food_idx", foodData = "food_data" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        comidaId = c.texto(.comidaId) ?? ""; optIdx = c.entero(.optIdx) ?? 0; foodIdx = c.entero(.foodIdx) ?? 0
        foodData = (try? c.decode(JSONValue.self, forKey: .foodData)) ?? .null
    }
}

public struct AlimentoPropio: Decodable, Sendable, Equatable {
    public let nombre: String
    public let kcal: Double?
    public let prot: Double?
    public let carb: Double?
    public let fat: Double?
    public let unidad: String?
    public let gramosPorUnidad: Double?
    public let categoria: String?
    enum CodingKeys: String, CodingKey {
        case nombre = "name", kcal, prot, carb, fat, unidad = "unit", gramosPorUnidad = "unit_grams", categoria = "category"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = c.texto(.nombre) ?? ""; kcal = c.decimal(.kcal); prot = c.decimal(.prot); carb = c.decimal(.carb)
        fat = c.decimal(.fat); unidad = c.texto(.unidad); gramosPorUnidad = c.decimal(.gramosPorUnidad); categoria = c.texto(.categoria)
    }
}

public struct PreferenciasCliente: Decodable, Sendable, Equatable {
    public let excluir: [String]
    public let idioma: String
    enum CodingKeys: String, CodingKey { case excluir, idioma }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        excluir = c.textos(.excluir) ?? []; idioma = c.texto(.idioma) ?? "es"
    }
}

public struct Comentario: Decodable, Sendable, Equatable {
    public let id: String
    public let ambito: String
    public let referenciaId: String?
    public let referenciaNombre: String?
    public let autor: String
    public let contenido: String
    public let leidoPorCliente: Bool?
    public let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, ambito, referenciaId = "referencia_id", referenciaNombre = "referencia_nombre", autor, contenido
        case leidoPorCliente = "leido_por_cliente", createdAt = "created_at"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id) ?? ""; ambito = c.texto(.ambito) ?? "general"; referenciaId = c.texto(.referenciaId)
        referenciaNombre = c.texto(.referenciaNombre); autor = c.texto(.autor) ?? ""; contenido = c.texto(.contenido) ?? ""
        leidoPorCliente = c.booleano(.leidoPorCliente); createdAt = c.texto(.createdAt) ?? ""
    }
}

/// `get_chat` y `chat_nuevos` (este último sin `leido_por_cliente`).
public struct MensajeChat: Decodable, Sendable, Equatable {
    public let id: String
    public let autor: String
    public let contenido: String
    public let leidoPorCliente: Bool?
    public let createdAt: String
    enum CodingKeys: String, CodingKey { case id, autor, contenido, leidoPorCliente = "leido_por_cliente", createdAt = "created_at" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id) ?? ""; autor = c.texto(.autor) ?? ""; contenido = c.texto(.contenido) ?? ""
        leidoPorCliente = c.booleano(.leidoPorCliente); createdAt = c.texto(.createdAt) ?? ""
    }
    public var esDelCoach: Bool { autor == "coach" }
}

public struct FilaSalud: Decodable, Sendable, Equatable {
    public let fecha: String
    public let tipo: String
    public let valor: Double?
    public let fuente: String?
    public let detalle: JSONValue?
    enum CodingKeys: String, CodingKey { case fecha, tipo, valor, fuente, detalle }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fecha = c.texto(.fecha) ?? ""; tipo = c.texto(.tipo) ?? ""; valor = c.decimal(.valor); fuente = c.texto(.fuente)
        detalle = try? c.decodeIfPresent(JSONValue.self, forKey: .detalle)
    }
}

public struct Recuperacion: Decodable, Sendable, Equatable {
    public let fecha: String
    public let score: Int?
    public let estado: String?
    public let banda: String?
    public let diasDatos: Int?
    public let bandaProvisoria: Bool?
    public let estadoAutonomico: String?
    public let hrvMetrica: String?
    public let discordancia: Bool?
    public let cobertura: JSONValue?
    public let motivos: JSONValue?
    enum CodingKeys: String, CodingKey {
        case fecha, score, estado, banda, diasDatos = "dias_datos", bandaProvisoria = "banda_provisoria"
        case estadoAutonomico = "estado_autonomico", hrvMetrica = "hrv_metrica", discordancia, cobertura, motivos
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fecha = c.texto(.fecha) ?? ""; score = c.entero(.score); estado = c.texto(.estado); banda = c.texto(.banda)
        diasDatos = c.entero(.diasDatos); bandaProvisoria = c.booleano(.bandaProvisoria); estadoAutonomico = c.texto(.estadoAutonomico)
        hrvMetrica = c.texto(.hrvMetrica); discordancia = c.booleano(.discordancia)
        cobertura = try? c.decodeIfPresent(JSONValue.self, forKey: .cobertura)
        motivos = try? c.decodeIfPresent(JSONValue.self, forKey: .motivos)
    }
}

public struct Conexion: Decodable, Sendable, Equatable {
    public let proveedor: String
    public let estado: String
    public let ultimoPullEn: String?
    enum CodingKeys: String, CodingKey { case proveedor, estado, ultimoPullEn = "ultimo_pull_en" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proveedor = c.texto(.proveedor) ?? ""; estado = c.texto(.estado) ?? ""; ultimoPullEn = c.texto(.ultimoPullEn)
    }
}

public struct CheckinSemana: Decodable, Sendable, Equatable {
    public let energia: Int?
    public let descanso: Int?
    public let hambre: Int?
    public let adherencia: Int?
    public let nota: String?
    enum CodingKeys: String, CodingKey { case energia, descanso, hambre, adherencia, nota }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energia = c.entero(.energia); descanso = c.entero(.descanso); hambre = c.entero(.hambre)
        adherencia = c.entero(.adherencia); nota = c.texto(.nota)
    }
}

public struct FotoProgreso: Decodable, Sendable, Equatable {
    public let semanaLunes: String
    public let pose: String
    public let tomadaEl: String?
    public let createdAt: String?
    enum CodingKeys: String, CodingKey { case semanaLunes = "semana_lunes", pose, tomadaEl = "tomada_el", createdAt = "created_at" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        semanaLunes = c.texto(.semanaLunes) ?? ""; pose = c.texto(.pose) ?? ""; tomadaEl = c.texto(.tomadaEl); createdAt = c.texto(.createdAt)
    }
}
