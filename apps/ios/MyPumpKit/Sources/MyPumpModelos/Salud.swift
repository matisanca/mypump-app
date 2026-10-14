import Foundation

// Filas de salud que no tenía Respuestas.swift: la recuperación con sus componentes (la escena "Mis datos" muestra
// cómo se arma el score) y los relojes que ofrece el servidor.

/// `get_recuperacion` entera (`Recuperacion` de Respuestas.swift no trae `componentes`). La última fila es la más nueva.
public struct RecuperacionDia: Decodable, Sendable, Equatable {
    public let fecha: String
    public let score: Int?
    public let estado: String?
    public let banda: String?
    public let diasDatos: Int?
    public let bandaProvisoria: Bool?
    public let estadoAutonomico: String?
    public let hrvMetrica: String?
    public let discordancia: Bool?
    /// `{sueno_min, fc_reposo, …}`: lo que ya se sabe mientras calibra.
    public let cobertura: JSONValue?
    /// `{autonomico: {score, peso}, sueno: …, carga: …, subjetivo: …, otros: …}`. Los pesos vienen SIN normalizar.
    public let componentes: JSONValue?
    /// `[{tipo, dir, valor, baseline, agudo}]`: hechos, la frase se arma en el cliente.
    public let motivos: JSONValue?

    enum CodingKeys: String, CodingKey {
        case fecha, score, estado, banda, diasDatos = "dias_datos", bandaProvisoria = "banda_provisoria"
        case estadoAutonomico = "estado_autonomico", hrvMetrica = "hrv_metrica", discordancia, cobertura, componentes, motivos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fecha = c.texto(.fecha) ?? ""; score = c.entero(.score); estado = c.texto(.estado); banda = c.texto(.banda)
        diasDatos = c.entero(.diasDatos); bandaProvisoria = c.booleano(.bandaProvisoria); estadoAutonomico = c.texto(.estadoAutonomico)
        hrvMetrica = c.texto(.hrvMetrica); discordancia = c.booleano(.discordancia)
        cobertura = try? c.decodeIfPresent(JSONValue.self, forKey: .cobertura)
        componentes = try? c.decodeIfPresent(JSONValue.self, forKey: .componentes)
        motivos = try? c.decodeIfPresent(JSONValue.self, forKey: .motivos)
    }

    public init(fecha: String, score: Int? = nil, estado: String? = nil, banda: String? = nil, diasDatos: Int? = nil,
                bandaProvisoria: Bool? = nil, estadoAutonomico: String? = nil, hrvMetrica: String? = nil, discordancia: Bool? = nil,
                cobertura: JSONValue? = nil, componentes: JSONValue? = nil, motivos: JSONValue? = nil) {
        self.fecha = fecha; self.score = score; self.estado = estado; self.banda = banda; self.diasDatos = diasDatos
        self.bandaProvisoria = bandaProvisoria; self.estadoAutonomico = estadoAutonomico; self.hrvMetrica = hrvMetrica
        self.discordancia = discordancia; self.cobertura = cobertura; self.componentes = componentes; self.motivos = motivos
    }
}

/// `GET /api/wearables/disponibles`: `{proveedores: [{id, nombre}]}`.
public struct ProveedoresDisponibles: Decodable, Sendable, Equatable {
    public struct Proveedor: Decodable, Sendable, Equatable {
        public let id: String
        public let nombre: String?
    }
    public let proveedores: [Proveedor]

    enum CodingKeys: String, CodingKey { case proveedores }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proveedores = c.lista(Proveedor.self, .proveedores)
    }
}
