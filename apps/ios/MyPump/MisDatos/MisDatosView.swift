import SwiftUI
import UIKit
import MyPumpModelos
import MyPumpDatos

/// Mis datos (propuesta D3 de la paridad): un lugar fijo para recuperación, salud, recordatorios, privacidad y
/// borrado. Hoy en la web solo se llega desde la card de Recuperación. Con la forma de Ajustes: filas con ícono en
/// azulejo de color. El recordatorio del domingo es el de `CentroAvisos` (NOT-05/06); Salud y el diagnóstico quedan
/// listos para `ModeloSalud`.
struct MisDatosView: View {
    let datos: Muestras
    @State private var modelo = Proveedor.modelo
    /// `mypump_notif_prefs`: se lee al entrar y cada cambio se guarda y reprograma.
    @State private var preferencias = CentroAvisos.shared.preferencias
    @State private var permisoNegado = false
    @State private var mostrarScore = true
    @State private var fuentes = false
    @State private var pagina: Pagina?

    /// Las páginas legales de la web, en Safari dentro de la app (como hoy).
    enum Pagina: String, Identifiable {
        case privacidad = "https://app.mypumpteam.com/privacidad.html"
        case borrado = "https://app.mypumpteam.com/eliminar-datos.html"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section {
                recuperacion
                Toggle(isOn: $mostrarScore) {
                    Label { Text("Mostrarme el score") } icon: { IconoAzulejo("eye.fill", color: .gray) }
                }
                .tint(Color.marcaVivo)
            }

            // El lugar de ModeloSalud (lo hace otro agente): la conexión con Salud de Apple, lo del día y el
            // diagnóstico (SAL-09…13). Hoy son filas de boceto.
            Section("Salud") {
                LabeledContent {
                    Button("Conectar") {}.buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                } label: {
                    Label { Text("Salud de Apple") } icon: { IconoAzulejo("heart.fill", color: .corazon) }
                }
                LabeledContent {
                    Text("—").foregroundStyle(.secondary)
                } label: {
                    Label { Text("Pasos hoy") } icon: { IconoAzulejo("figure.walk", color: .alerta) }
                }
                LabeledContent {
                    Text("—").foregroundStyle(.secondary)
                } label: {
                    Label { Text("Sueño de anoche") } icon: { IconoAzulejo("bed.double.fill", color: .sueno) }
                }
                NavigationLink {
                    ContentUnavailableView("Diagnóstico de Salud", systemImage: "stethoscope",
                                           description: Text("Qué datos llegan de Salud de Apple y cuándo fue la última sincronización."))
                        .navigationTitle("Diagnóstico")
                } label: {
                    Label { Text("Diagnóstico de Salud") } icon: { IconoAzulejo("stethoscope", color: .gray) }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { preferencias.check.on }, set: { on in
                    withAnimation(.snappy) { preferencias.check.on = on }
                    guardar(activar: on)
                })) {
                    Label { Text("Tu revisión de la semana") } icon: { IconoAzulejo("bell.badge.fill", color: .peligro) }
                }
                .tint(Color.marcaVivo)
                .accessibilityIdentifier("recordatorio-domingo")
                if preferencias.check.on {
                    DatePicker(selection: hora, displayedComponents: .hourAndMinute) {
                        Label { Text("Domingos a las") } icon: { IconoAzulejo("calendar", color: .agua) }
                    }
                }
            } header: {
                Text("Recordatorios")
            } footer: {
                if modelo.conMuestras {
                    Text("En la demo los recordatorios no se activan.")
                } else if permisoNegado && preferencias.check.on {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Las notificaciones de MyPump están apagadas en el iPhone, así que el aviso no va a llegar.")
                        Button("Activarlas en Ajustes") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .fontWeight(.semibold)
                    }
                } else {
                    Text("Te avisamos para que cargues tus fotos, tu check y tu peso antes de la devolución de Mati.")
                }
            }
            .disabled(modelo.conMuestras)

            Section("Tu información") {
                Button { fuentes = true } label: {
                    fila("Respaldo científico del plan", icono: "book.closed.fill", color: .marcaTexto)
                }
                .tint(.primary)
                Button { pagina = .privacidad } label: {
                    fila("Política de privacidad", icono: "hand.raised.fill", color: .agua)
                }
                .tint(.primary)
                Button(role: .destructive) { pagina = .borrado } label: {
                    Label { Text("Eliminar mis datos").foregroundStyle(Color.peligro) } icon: {
                        IconoAzulejo("trash.fill", color: .peligro)
                    }
                }
            }

            Section {
                LabeledContent("Versión", value: "2.0.0 (100)")
            } footer: {
                Text("MyPump no es un dispositivo médico. Ante cualquier duda de salud, consultá a tu médico.")
            }
        }
        .margenesDeLectura()
        .task { permisoNegado = await CentroAvisos.shared.permiso() == .denied }
        .navigationTitle("Mis datos")
        .tint(Color.marcaTexto)
        .sheet(isPresented: $fuentes) { FuentesView() }
        .sheet(item: $pagina) { p in
            NavegadorInterno(url: URL(string: p.rawValue)!).ignoresSafeArea()
        }
    }

    /// La hora del recordatorio como `Date` para el selector (solo importan la hora y los minutos).
    private var hora: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: preferencias.check.hora, minute: preferencias.check.min)) ?? .now },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                preferencias.check.hora = c.hour ?? 11
                preferencias.check.min = c.minute ?? 0
                guardar(activar: false)
            })
    }

    /// Guarda las preferencias y reprograma la local del domingo. Al prenderla sin permiso, lo pide (si ya lo negó,
    /// iOS no vuelve a mostrar la hoja: se avisa y se lleva a Ajustes).
    private func guardar(activar: Bool) {
        CentroAvisos.shared.preferencias = preferencias
        Task {
            if activar {
                permisoNegado = !(await CentroAvisos.shared.activar())
            } else {
                await CentroAvisos.shared.reprogramar()
            }
        }
    }

    private func fila(_ titulo: String, icono: String, color: Color) -> some View {
        HStack {
            Label { Text(titulo).foregroundStyle(.primary) } icon: { IconoAzulejo(icono, color: color) }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    // MARK: Recuperación

    private var recuperacion: some View {
        let ultima = datos.recuperacion.last
        let dias = ultima?.diasDatos ?? 0
        let score = ultima?.score
        return HStack(spacing: Espacio.m) {
            AnilloProgreso(fraccion: score.map { Double($0) / 100 } ?? Double(dias) / 14,
                           grosor: 7,
                           color: score == nil ? .sueno : .marcaVivo) {
                if let score {
                    Text("\(score)").font(.numeroMediano)
                } else {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text("Recuperación").font(.headline)
                Text(estadoRecuperacion).font(.subheadline).foregroundStyle(.secondary)
                if score == nil {
                    ProgressView(value: Double(dias), total: 14)
                        .tint(Color.sueno)
                        .frame(maxWidth: 160)
                        .padding(.top, 4)
                        .accessibilityLabel("\(dias) de 14 días de datos")
                }
            }
        }
        .padding(.vertical, Espacio.xs)
        .accessibilityElement(children: .combine)
    }

    private var estadoRecuperacion: String {
        guard let ultima = datos.recuperacion.last else { return "Conectá tu reloj o Salud de Apple" }
        if let s = ultima.score { return "\(s)/100 · \(ultima.banda ?? "")" }
        switch ultima.estado {
        case "calibrando": return "Calibrando: \(ultima.diasDatos ?? 0)/14 días"
        default: return "Todavía no hay datos suficientes"
        }
    }
}
