import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Documentos (contrato y consentimiento): `mypump_contrato_get(p_token)`, solo lectura y sin copia en el disco. Se
/// trae al cargar la cuenta y al volver a primer plano (quien firmó en el navegador vuelve y ve «Firmado»).
///
/// - Al menos un documento: aparece la fila «Documentos» de Mis datos (y, con un contrato pendiente, el aviso de Entreno).
/// - Cualquier error (sin red, token inválido, la función todavía no está en la base) es «sin documentos», en silencio:
///   ni la fila ni el aviso aparecen, y nada se rompe.
///
/// La app no firma: `enlace(de:)` pide al servicio de firma el enlace personal del documento y la pantalla lo abre en el
/// navegador del sistema.
@MainActor @Observable
public final class ModeloDocumentos {
    public static let funcion = "mypump_contrato_get"

    public private(set) var documentos: [DocumentoFirma] = []

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored private var cargaEnCurso: Task<Void, Never>?

    public init(cliente: ClienteRPC, token: String) {
        self.cliente = cliente; self.token = token
    }

    /// Hay al menos un documento: la fila de Mis datos aparece.
    public var hay: Bool { !documentos.isEmpty }
    /// Un contrato de coaching sin firmar: el aviso de la pantalla principal.
    public var contratoPendiente: Bool { TextosDocumentos.hayContratoPendiente(documentos) }

    /// Trae los documentos. Si ya hay una carga en vuelo, espera esa.
    public func cargar() async {
        if let t = cargaEnCurso { await t.value; return }
        let t = Task { await self.traer() }
        cargaEnCurso = t
        await t.value
        cargaEnCurso = nil
    }

    private func traer() async {
        let nuevos: [DocumentoFirma]
        switch await cliente.llamar(Self.funcion, ["p_token": .texto(token)]) {
        case .failure:
            nuevos = []
        case .success(let j):
            nuevos = (try? JSONEncoder().encode(j)).flatMap { try? JSONDecoder().decode(RespuestaDocumentos.self, from: $0) }?.documentos ?? []
        }
        if nuevos != documentos { documentos = nuevos }
    }

    /// El enlace personal del documento (firmar, o ver y bajar el PDF si ya está firmado). nil si el servicio no contesta,
    /// no lo conoce o devuelve algo que no es una página https del propio servicio de firma.
    public func enlace(de documento: DocumentoFirma) async -> URL? {
        guard case .success(let r) = await cliente.enlacesDocumentos(token: token),
              let crudo = r.documentos.first(where: { $0.id == documento.id })?.url else { return nil }
        return Self.enlaceSeguro(crudo, servicio: cliente.config.firma)
    }

    /// Solo se abre https y en el mismo host que el servicio de firma: nunca otro esquema ni otro sitio.
    static func enlaceSeguro(_ texto: String, servicio: URL) -> URL? {
        guard let u = URL(string: texto), u.scheme?.lowercased() == "https",
              let host = u.host?.lowercased(), host == servicio.host?.lowercased() else { return nil }
        return u
    }
}

extension ClienteRPC {
    /// `POST <firma>/api/app/documentos` con `{token}`: los documentos del dueño del token, cada uno con su enlace. 401 si
    /// el token no vale. Sin auth en el header (como `vision`).
    public func enlacesDocumentos(token: String) async -> Result<RespuestaEnlacesDocumentos, ErrorRPC> {
        var pedido = URLRequest(url: config.firma.appendingPathComponent("api/app/documentos"), timeoutInterval: 20)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.httpBody = try? JSONEncoder().encode(JSONValue.objeto(["token": .texto(token)]))
        switch await enviar(pedido) {
        case .failure(let e): return .failure(e)
        case .success(let j):
            guard let datos = try? JSONEncoder().encode(j),
                  let r = try? JSONDecoder().decode(RespuestaEnlacesDocumentos.self, from: datos) else {
                return .failure(ErrorRPC(clase: .permanente, status: 200, codigo: "DECODE", mensaje: "documentos: forma inesperada"))
            }
            return .success(r)
        }
    }
}
