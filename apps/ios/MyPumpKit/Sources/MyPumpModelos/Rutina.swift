import Foundation

/// Fila de `mypump_get_rutina_activa`.
public struct RutinaActiva: Decodable, Sendable, Equatable {
    public let id: String
    public let version: Int
    public let estructura: EstructuraRutina
    public private(set) var semanaActual: Int
    public let fechaInicio: String?
    public let fechaFin: String?
    public let tieneSiguiente: Bool

    enum CodingKeys: String, CodingKey {
        case id, version, estructura
        case semanaActual = "semana_actual", fechaInicio = "fecha_inicio", fechaFin = "fecha_fin", tieneSiguiente = "tiene_siguiente"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id) ?? ""
        version = c.entero(.version) ?? 1
        estructura = (try? c.decode(EstructuraRutina.self, forKey: .estructura)) ?? EstructuraRutina()
        semanaActual = c.entero(.semanaActual) ?? 1
        fechaInicio = c.texto(.fechaInicio)
        fechaFin = c.texto(.fechaFin)
        tieneSiguiente = c.booleano(.tieneSiguiente) ?? false
    }

    /// La misma rutina en otra semana: al pasar de semana no cambia nada más. Para cuando el servidor ya avanzó y la
    /// rutina nueva no llegó (`ModeloEntreno.avanzarSemana`).
    public func conSemana(_ s: Int) -> RutinaActiva {
        var r = self
        r.semanaActual = s
        return r
    }
}

/// `mypump_rutinas.estructura`, tal como la publica el Cerebro (`expandirRutinaParaMyPump`). Ver la 001 y
/// `docs/NATIVA_CONTRATO.md`.
public struct EstructuraRutina: Decodable, Sendable, Equatable {
    public var nombrePlan: String?
    public var perfil: PerfilPlan?
    public var semanasTotal: Int?
    public var dias: [Dia]
    public var mensajesSemana: [MensajeSemana]
    public var semanaOffset: Int?
    public var fase: Int?

    enum CodingKeys: String, CodingKey {
        case nombrePlan = "nombre_plan", perfil, semanasTotal = "semanas_total", dias
        case mensajesSemana = "mensajes_semana", semanaOffset = "semana_offset", fase
    }

    public init(nombrePlan: String? = nil, perfil: PerfilPlan? = nil, semanasTotal: Int? = nil, dias: [Dia] = [],
                mensajesSemana: [MensajeSemana] = [], semanaOffset: Int? = nil, fase: Int? = nil) {
        self.nombrePlan = nombrePlan; self.perfil = perfil; self.semanasTotal = semanasTotal; self.dias = dias
        self.mensajesSemana = mensajesSemana; self.semanaOffset = semanaOffset; self.fase = fase
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombrePlan = c.texto(.nombrePlan)
        perfil = try? c.decodeIfPresent(PerfilPlan.self, forKey: .perfil)
        semanasTotal = c.entero(.semanasTotal)
        dias = c.lista(Dia.self, .dias)
        mensajesSemana = c.lista(MensajeSemana.self, .mensajesSemana)
        semanaOffset = c.entero(.semanaOffset)
        fase = c.entero(.fase)
    }
}

public struct PerfilPlan: Decodable, Sendable, Equatable {
    public let nivel: String?
    public let split: String?
    public let diasSemana: Int?
    public let objetivo: String?
    public let resumen: String?

    enum CodingKeys: String, CodingKey { case nivel, split, diasSemana, objetivo, resumen }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nivel = c.texto(.nivel); split = c.texto(.split); diasSemana = c.entero(.diasSemana)
        objetivo = c.texto(.objetivo); resumen = c.texto(.resumen)
    }
}

public struct MensajeSemana: Decodable, Sendable, Equatable {
    public let n: Int?
    public let titulo: String?
    public let msg: String?

    enum CodingKeys: String, CodingKey { case n, titulo, msg }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = c.entero(.n); titulo = c.texto(.titulo); msg = c.texto(.msg)
    }
}

/// Un día de la rutina. El `id` es una clave opaca (`d<n>`, `b<v>d<n>`, `r<n>d<n>`, `lun`…): nunca se parsea.
public struct Dia: Decodable, Sendable, Equatable {
    public var id: String?
    public var n: Int?
    public var nombre: String?
    public var abreviado: String?
    public var bloques: [Bloque]
    public var esComodin: Bool?
    public var reemplaza: [String]?

    enum CodingKeys: String, CodingKey {
        case id, n, nombre, abreviado, bloques, esComodin = "es_comodin", reemplaza
    }

    public init(id: String? = nil, n: Int? = nil, nombre: String? = nil, abreviado: String? = nil, bloques: [Bloque] = [],
                esComodin: Bool? = nil, reemplaza: [String]? = nil) {
        self.id = id; self.n = n; self.nombre = nombre; self.abreviado = abreviado; self.bloques = bloques
        self.esComodin = esComodin; self.reemplaza = reemplaza
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id)
        n = c.entero(.n)
        nombre = c.texto(.nombre)
        abreviado = c.texto(.abreviado)
        bloques = c.lista(Bloque.self, .bloques)   // un bloque vaciado puede venir null (Facundo, d4)
        esComodin = c.booleano(.esComodin)
        reemplaza = c.textos(.reemplaza)
    }
}

public struct Bloque: Decodable, Sendable, Equatable {
    public var titulo: String?
    public var subtitulo: String?
    public var ejercicios: [Ejercicio]

    enum CodingKeys: String, CodingKey { case titulo, subtitulo, ejercicios }

    public init(titulo: String? = nil, subtitulo: String? = nil, ejercicios: [Ejercicio] = []) {
        self.titulo = titulo; self.subtitulo = subtitulo; self.ejercicios = ejercicios
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titulo = c.texto(.titulo)
        subtitulo = c.texto(.subtitulo)
        ejercicios = c.lista(Ejercicio.self, .ejercicios)
    }
}

/// Un ejercicio. El `id` es del LUGAR en la rutina (`slug-d<n>-<i>`), no del ejercicio: el historial va por
/// `claveEjercicio(nombre efectivo)`.
public struct Ejercicio: Decodable, Sendable, Equatable {
    public var id: String
    public var nombre: String
    public var tipo: String?
    public var descansoSegundos: Int?
    public var notasTecnica: String?
    public var videoURL: String?
    public var imagenes: Imagenes?
    public var catalogoSlug: String?
    /// `_matched_slug` suelto (245 ejercicios reales lo tienen fuera de `images`).
    public var matchedSlug: String?
    public var progresion: [Progresion]
    // Campos viejos: los usa la demo de la web y los planes de antes de la progresión por semana.
    public var series: Int?
    public var reps: String?
    public var rirObjetivo: String?
    /// `rir` suelto: último respaldo de `getProgresionActual` (`ej.rir_objetivo ?? ej.rir`).
    public var rirSuelto: String?

    enum CodingKeys: String, CodingKey {
        case id, nombre, tipo, descansoSegundos = "descanso_segundos", notasTecnica = "notas_tecnica"
        case videoURL = "video_url", imagenes = "images", catalogoSlug = "catalogo_slug", matchedSlug = "_matched_slug"
        case progresion, series, reps, rirObjetivo = "rir_objetivo", rirSuelto = "rir"
    }

    public init(id: String, nombre: String, tipo: String? = nil, descansoSegundos: Int? = nil, notasTecnica: String? = nil,
                videoURL: String? = nil, imagenes: Imagenes? = nil, catalogoSlug: String? = nil, matchedSlug: String? = nil,
                progresion: [Progresion] = [], series: Int? = nil, reps: String? = nil, rirObjetivo: String? = nil) {
        self.id = id; self.nombre = nombre; self.tipo = tipo; self.descansoSegundos = descansoSegundos
        self.notasTecnica = notasTecnica; self.videoURL = videoURL; self.imagenes = imagenes; self.catalogoSlug = catalogoSlug
        self.matchedSlug = matchedSlug; self.progresion = progresion; self.series = series; self.reps = reps
        self.rirObjetivo = rirObjetivo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id) ?? ""
        nombre = c.texto(.nombre) ?? ""
        tipo = c.texto(.tipo)
        descansoSegundos = c.entero(.descansoSegundos)
        notasTecnica = c.texto(.notasTecnica)
        videoURL = c.texto(.videoURL)
        imagenes = try? c.decodeIfPresent(Imagenes.self, forKey: .imagenes)
        catalogoSlug = c.texto(.catalogoSlug)
        matchedSlug = c.texto(.matchedSlug)
        progresion = c.lista(Progresion.self, .progresion)
        series = c.entero(.series)
        reps = c.texto(.reps)
        rirObjetivo = c.texto(.rirObjetivo)
        rirSuelto = c.texto(.rirSuelto)
    }
}

public struct Imagenes: Decodable, Sendable, Equatable {
    public var eccentric: String?
    public var concentric: String?
    /// El slug que lee la app para los sustitutos (no `catalogo_slug`). Ver `reference_sustitutos_ejercicio_app`.
    public var matchedSlug: String?

    enum CodingKeys: String, CodingKey { case eccentric, concentric, matchedSlug = "_matched_slug" }

    public init(eccentric: String? = nil, concentric: String? = nil, matchedSlug: String? = nil) {
        self.eccentric = eccentric; self.concentric = concentric; self.matchedSlug = matchedSlug
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eccentric = c.texto(.eccentric); concentric = c.texto(.concentric); matchedSlug = c.texto(.matchedSlug)
    }
}

/// Una semana de la progresión, YA CALCULADA por el Cerebro: la app la muestra, no la inventa.
public struct Progresion: Decodable, Sendable, Equatable {
    public var semana: Int?
    public var series: Int?
    public var reps: String?
    public var rir: String?
    public var titulo: String?

    enum CodingKeys: String, CodingKey { case semana, series, reps, rir, titulo }

    public init(semana: Int? = nil, series: Int? = nil, reps: String? = nil, rir: String? = nil, titulo: String? = nil) {
        self.semana = semana; self.series = series; self.reps = reps; self.rir = rir; self.titulo = titulo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        semana = c.entero(.semana); series = c.entero(.series); reps = c.texto(.reps); rir = c.texto(.rir); titulo = c.texto(.titulo)
    }
}
