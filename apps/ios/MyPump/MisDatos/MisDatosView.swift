import SwiftUI
import MyPumpModelos

/// Mis datos (propuesta D3 de la paridad): un lugar fijo para recuperación, salud, recordatorios, privacidad y
/// borrado. Hoy en la web solo se llega desde la card de Recuperación.
struct MisDatosView: View {
    let datos: Muestras
    @State private var recordatorio = true
    @State private var hora = Calendar.current.date(from: DateComponents(hour: 11)) ?? .now
    @State private var mostrarScore = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 8)
                        Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(.secondary)
                    }
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recuperación").font(.headline)
                        Text(estadoRecuperacion).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                Toggle("Mostrarme el score", isOn: $mostrarScore).tint(Color.exito)
            }
            Section("Salud") {
                LabeledContent("Apple Health") { Text("Conectar").foregroundStyle(Color.marcaTexto) }
                LabeledContent("Pasos hoy", value: "—")
                LabeledContent("Sueño de anoche", value: "—")
            }
            Section("Recordatorios") {
                Toggle("Tu revisión de la semana", isOn: $recordatorio).tint(Color.exito)
                if recordatorio {
                    DatePicker("Domingos a las", selection: $hora, displayedComponents: .hourAndMinute)
                }
            }
            Section("Tu información") {
                Label("Respaldo científico del plan", systemImage: "book.closed")
                Label("Política de privacidad", systemImage: "hand.raised")
                Label("Eliminar mis datos", systemImage: "trash").foregroundStyle(Color.peligro)
            }
            Section {
                LabeledContent("Versión", value: "2.0.0 (100)")
            } footer: {
                Text("MyPump no es un dispositivo médico. Ante cualquier duda de salud, consultá a tu médico.")
            }
        }
        .navigationTitle("Mis datos")
    }

    private var estadoRecuperacion: String {
        guard let ultima = datos.recuperacion.last else { return "Conectá tu reloj o Apple Health" }
        if let s = ultima.score { return "\(s)/100 · \(ultima.banda ?? "")" }
        switch ultima.estado {
        case "calibrando": return "Calibrando: \(ultima.diasDatos ?? 0)/14 días"
        default: return "Todavía no hay datos suficientes"
        }
    }
}
