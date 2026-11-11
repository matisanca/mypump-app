import Foundation

/// Documentos (contrato y consentimiento, firma propia en `firma.mypumpteam.com`): lo que devuelve
/// `mypump_contrato_get(p_token)`, `{"documentos":[{id, tipo, titulo, estado, firmado_en, revocado_en}], "pendientes": n}`.
/// La app no firma nada: muestra el estado y abre la página del servicio en el navegador del sistema.
///
/// Tolerante como el resto: un documento con un tipo o un estado que la app no conoce (o sin id) se descarta sin tirar los
/// demás; una respuesta con otra forma es una lista vacía.
public enum TipoDocumento: String, Codable, Sendable, CaseIterable {
    case servicioAR = "servicio_ar"
    case servicioExt = "servicio_ext"
    case consentimientoAR = "consentimiento_ar"

    /// El contrato de coaching (Argentina o exterior); el consentimiento es otra cosa.
    public var esContrato: Bool { self == .servicioAR || self == .servicioExt }
}

public enum EstadoDocumento: String, Codable, Sendable, CaseIterable {
    case pendiente, firmado, revocado
}

public struct DocumentoFirma: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let tipo: TipoDocumento
    /// El título de la plantilla; la app muestra su propio nombre por tipo (`TextosDocumentos.nombre`).
    public let titulo: String?
    public let estado: EstadoDocumento
    /// timestamptz ISO, como lo da `jsonb_build_object`.
    public let firmadoEn: String?
    public let revocadoEn: String?

    public init(id: String, tipo: TipoDocumento, titulo: String? = nil, estado: EstadoDocumento,
                firmadoEn: String? = nil, revocadoEn: String? = nil) {
        self.id = id; self.tipo = tipo; self.titulo = titulo; self.estado = estado
        self.firmadoEn = firmadoEn; self.revocadoEn = revocadoEn
    }

    enum CodingKeys: String, CodingKey {
        case id, tipo, titulo, estado
        case firmadoEn = "firmado_en"
        case revocadoEn = "revocado_en"
    }

    struct Desconocido: Error {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texto(.id), !id.isEmpty,
              let tipo = c.texto(.tipo).flatMap(TipoDocumento.init(rawValue:)),
              let estado = c.texto(.estado).flatMap(EstadoDocumento.init(rawValue:)) else { throw Desconocido() }
        self.id = id
        self.tipo = tipo
        self.estado = estado
        titulo = c.texto(.titulo)
        firmadoEn = c.texto(.firmadoEn)
        revocadoEn = c.texto(.revocadoEn)
    }
}

public struct RespuestaDocumentos: Codable, Equatable, Sendable {
    public var documentos: [DocumentoFirma]

    public init(documentos: [DocumentoFirma]) { self.documentos = documentos }

    enum CodingKeys: String, CodingKey { case documentos }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        documentos = c.lista(DocumentoFirma.self, .documentos)
    }
}

/// Lo que contesta `POST <firma>/api/app/documentos`: `{"documentos":[{id, tipo, estado, firmado_en, url}]}`. Solo
/// importan el id y el enlace; un elemento sin los dos se descarta.
public struct EnlaceDocumento: Decodable, Equatable, Sendable {
    public let id: String
    public let url: String

    enum CodingKeys: String, CodingKey { case id, url }

    public init(id: String, url: String) { self.id = id; self.url = url }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.texto(.id), !id.isEmpty, let url = c.texto(.url), !url.isEmpty else {
            throw DocumentoFirma.Desconocido()
        }
        self.id = id; self.url = url
    }
}

public struct RespuestaEnlacesDocumentos: Decodable, Equatable, Sendable {
    public var documentos: [EnlaceDocumento]

    enum CodingKeys: String, CodingKey { case documentos }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        documentos = c.lista(EnlaceDocumento.self, .documentos)
    }
}
