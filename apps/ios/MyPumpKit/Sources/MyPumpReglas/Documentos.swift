import Foundation
import MyPumpModelos

/// Los textos de Documentos (contrato y consentimiento), iguales en iOS, Android y la web. En el iPhone esta pantalla no
/// muestra nada de pagos ni precios: solo el estado y abrir el documento.
public enum TextosDocumentos {
    public static let titulo = "Documentos"
    public static let entradaMisDatos = "Documentos"
    public static let pie = "Tu contrato y tu consentimiento. Se abren en el navegador para leerlos, firmarlos o descargarlos."
    public static let avisoContrato = "Tenés el contrato pendiente de firma"
    public static let avisoContratoDetalle = "Tocá para leerlo y firmarlo."
    public static let errorAbrir = "No pudimos abrir el documento. Probá de nuevo en un rato o usá el enlace que te llegó por correo."
    public static let leerYFirmar = "Leer y firmar"
    public static let verDocumento = "Ver documento"

    public static func nombre(_ tipo: TipoDocumento) -> String {
        switch tipo {
        case .servicioAR, .servicioExt: "Contrato de coaching"
        case .consentimientoAR: "Consentimiento de atención médica"
        }
    }

    /// «Pendiente de firma», «Firmado el 10/11/2026», «Revocado el 10/11/2026». Sin fecha legible, el estado solo.
    public static func estado(_ d: DocumentoFirma, zona: TimeZone = .current) -> String {
        switch d.estado {
        case .pendiente: return "Pendiente de firma"
        case .firmado: return fechada("Firmado", d.firmadoEn, zona)
        case .revocado: return fechada("Revocado", d.revocadoEn, zona)
        }
    }

    public static func boton(_ estado: EstadoDocumento) -> String {
        estado == .pendiente ? leerYFirmar : verDocumento
    }

    /// El aviso de la pantalla principal: solo con un contrato de coaching pendiente (el consentimiento no lo prende).
    public static func hayContratoPendiente(_ docs: [DocumentoFirma]) -> Bool {
        docs.contains { $0.tipo.esContrato && $0.estado == .pendiente }
    }

    /// "dd/mm/aaaa" de un timestamptz, en la zona del teléfono. nil si no se entiende.
    public static func fecha(_ iso: String?, zona: TimeZone = .current) -> String? {
        guard let iso, let d = Formateadores.instante(iso) else { return nil }
        return Formateadores.fecha("dd/MM/yyyy", zona: zona, locale: "es_AR").string(from: d)
    }

    private static func fechada(_ palabra: String, _ iso: String?, _ zona: TimeZone) -> String {
        fecha(iso, zona: zona).map { "\(palabra) el \($0)" } ?? palabra
    }
}
