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
    /// Con suplementación (2.1.0) Salud sale de la barra: se abre en una hoja desde el botón de arriba de Revisión, al lado
    /// de Mis datos. Lo pone la raíz según haya o no suplementación.
    var saludEnMas = false
    /// La hoja de Salud (solo con `saludEnMas`).
    var saludAbierta = false

    init(pestaña: Raiz.Pestaña) { self.pestaña = pestaña }

    /// NOT-03: train/diet/progress/myday/revision/salud; lo desconocido ya llega como Chat.
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
        }
    }

    /// Salud, en su pestaña o, con suplementación, en la hoja (los avisos y `?scene=progress|myday` llegan acá).
    func irASalud(_ segmento: SegmentoSalud?) {
        segmentoSalud = segmento
        if saludEnMas { saludAbierta = true } else { pestaña = .salud }
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
