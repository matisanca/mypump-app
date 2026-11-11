import SwiftUI
import MyPumpDatos
import MyPumpReglas

/// A dónde se va dentro de la app: la pestaña y, en Revisión, una sección o Mis datos; en Salud, el segmento. La usan
/// tocar un aviso (`CentroAvisos.destino`), el banner de "te falta tu check" y los botones «Ir a Revisión» de Cuerpo.
@MainActor @Observable
final class Navegacion {
    /// Cambiar de pestaña (tocarla, un aviso, «Ir a Revisión», el banner) cierra la hoja de Salud si estaba abierta.
    var pestaña: Raiz.Pestaña { didSet { saludAbierta = false } }
    /// Una sección de Revisión a la que desplazarse ("fotos", "check"); Revisión la consume al llegar. Las que se mudaron
    /// a Salud en la 2.1 ("peso" a Cuerpo; "reloj" y la vieja "midia" a Recuperación) cambian de pestaña (`irARevision`).
    var anclaRevision: String?
    /// El segmento de Salud que hay que mostrar; Salud lo consume al llegar.
    var segmentoSalud: SegmentoSalud?
    /// Abrir Mis datos (desde Revisión).
    var misDatos = false
    /// Abrir Documentos dentro de Mis datos (el aviso del contrato pendiente); Mis datos lo consume al llegar.
    var documentos = false
    /// La hoja de Salud. Desde la 2.1.0 Salud no es una pestaña: se abre desde la tarjeta Recuperación de arriba de
    /// Revisión (pedido de Mati, 4-nov), un aviso o un link.
    var saludAbierta = false
    /// Abrir «Estudios y órdenes» dentro de Mis datos, en la primera tarjeta nueva (un aviso, `?scene=estudios` o la
    /// tarjeta de arriba de Entreno). Mis datos lo consume: espera a saber si la sección existe y, si no, se queda ahí.
    var estudios = false
    /// Abrir «Tu guía» en Entreno (el «Ver mi guía» de la bienvenida); Entreno lo consume al llegar.
    var abrirGuia = false

    init(pestaña: Raiz.Pestaña) { self.pestaña = pestaña }

    /// NOT-03: train/diet/progress/myday/revision/salud/estudios; lo desconocido ya llega como Chat.
    func ir(a destino: DestinoAviso) {
        switch destino {
        case .entreno: pestaña = .entreno
        case .dieta: pestaña = .dieta
        case .chat: pestaña = .chat
        case .fuerza: irASalud(.fuerza)
        case .revision: pestaña = .revision
        case .recuperacion: irASalud(.recuperacion)
        case .misDatos:
            pestaña = .revision
            misDatos = true
        case .estudios: irAEstudios()
        }
    }

    /// Documentos: Revisión → Mis datos → Documentos (el aviso «Tenés el contrato pendiente de firma»).
    func irADocumentos() {
        pestaña = .revision
        misDatos = true
        documentos = true
    }
    /// Mis datos → Estudios y órdenes. Primero Mis datos, que existe siempre: si la sección no está disponible (la palanca
    /// apagada, la cuenta sin la función, el `get` caído), el alumno queda ahí y nunca en una pantalla en blanco.
    func irAEstudios() {
        pestaña = .revision
        misDatos = true
        estudios = true
    }

    /// Salud, en la hoja sobre Revisión (los avisos y `?scene=progress|myday` llegan acá). Primero la pestaña: cambiarla
    /// cierra la hoja. La hoja se pide en la vuelta siguiente: si quedó `saludAbierta` en true sin mostrarse (otra hoja
    /// abierta cuando llegó un aviso), el false de la pestaña tiene que llegar a SwiftUI antes del true; si no, la tarjeta
    /// dejaba de abrir Salud (revisión, hallazgo 1).
    func irASalud(_ segmento: SegmentoSalud?) {
        segmentoSalud = segmento
        pestaña = .revision
        Task { @MainActor in self.saludAbierta = true }
    }

    /// Una sección de Revisión; las que se mudaron a Salud van a su segmento.
    func irARevision(_ ancla: String) {
        switch ancla {
        case "peso": irASalud(.cuerpo)
        case "reloj", "midia": irASalud(.recuperacion)
        default:
            anclaRevision = ancla
            pestaña = .revision
        }
    }
}

/// Los tres segmentos de Salud (2.1).
enum SegmentoSalud: String, CaseIterable, Identifiable {
    case recuperacion, fuerza, cuerpo
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .recuperacion: "Recuperación"
        case .fuerza: "Fuerza"
        case .cuerpo: "Cuerpo"
        }
    }
}

/// "Te faltan tu check y tus fotos de la semana · entrá a Revisión" (GEN-03), arriba de Entreno, Dieta, Chat y Salud
/// (la web lo pone en todas las escenas menos Revisión). Tocarlo lleva a Revisión. Con todo hecho, en la demo o sin
/// cuenta no se ve.
struct BannerRevision: View {
    @State private var modelo = Proveedor.modelo
    @Environment(Navegacion.self) private var navegacion: Navegacion?

    var body: some View {
        let p = modelo.pendientesDeLaSemana
        if !modelo.conMuestras, let texto = FotosProgreso.textoRecordatorio(faltaCheck: p.faltaCheck, faltanFotos: p.faltanFotos) {
            Button {
                withAnimation(.snappy) {
                    navegacion?.anclaRevision = p.faltaCheck && !p.faltanFotos ? "check" : "fotos"
                    navegacion?.pestaña = .revision
                }
            } label: {
                HStack(spacing: Espacio.s) {
                    Image(systemName: "checklist")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.sobreMarca)
                        .frame(width: 32, height: 32)
                        .background(Color.marca, in: .circle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(texto).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text("Entrá a Revisión: es un minuto y Mati lo ve antes de tu devolución.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(Espacio.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficieTarjeta(radio: Radio.control + 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre Revisión")
            .accessibilityIdentifier("banner-revision")
        }
    }
}
