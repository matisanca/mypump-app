import SwiftUI
import MyPumpDatos
import MyPumpReglas

/// A dónde se va dentro de la app: la pestaña y, en Revisión, una sección o Mis datos. La usan tocar un aviso
/// (`CentroAvisos.destino`) y el banner de "te falta tu check" de Entreno y Dieta.
@MainActor @Observable
final class Navegacion {
    var pestaña: Raiz.Pestaña
    /// Una sección de Revisión a la que desplazarse ("fotos", "check", "peso", "midia"); Revisión la consume al llegar.
    var anclaRevision: String?
    /// Abrir Mis datos (desde Revisión).
    var misDatos = false

    init(pestaña: Raiz.Pestaña) { self.pestaña = pestaña }

    /// NOT-03: train/diet/progress/myday/revision/salud; lo desconocido ya llega como Chat.
    func ir(a destino: DestinoAviso) {
        switch destino {
        case .entreno: pestaña = .entreno
        case .dieta: pestaña = .dieta
        case .chat: pestaña = .chat
        case .progreso: pestaña = .progreso
        case .revision: pestaña = .revision
        case .miDia:
            pestaña = .revision
            anclaRevision = "midia"
        case .misDatos:
            pestaña = .revision
            misDatos = true
        }
    }
}

/// "Te faltan tu check y tus fotos de la semana · entrá a Revisión" (GEN-03), arriba de Entreno y Dieta. Tocarlo lleva
/// a Revisión. Con todo hecho, en la demo o sin cuenta no se ve.
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
