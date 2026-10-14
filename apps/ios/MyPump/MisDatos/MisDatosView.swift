import SwiftUI
import UIKit
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Mis datos (propuesta D3 de la paridad): un lugar fijo para recuperación, salud, recordatorios, privacidad y
/// borrado. Hoy en la web solo se llega desde la card de Recuperación. Con la forma de Ajustes: filas con ícono en
/// azulejo de color. La recuperación abre los datos de salud de `ModeloSalud` (con "Mostrarme el score" y Salud de
/// Apple, cuyo título abre el diagnóstico con 5 toques); sin cuenta no existe. El recordatorio del domingo es el de
/// `CentroAvisos` (NOT-05/06).
struct MisDatosView: View {
    let datos: Muestras
    @State private var modelo = Proveedor.modelo
    /// `mypump_notif_prefs`: se lee al entrar y cada cambio se guarda y reprograma.
    @State private var preferencias = CentroAvisos.shared.preferencias
    @State private var permisoNegado = false
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
            // Recuperación y salud (SAL-09…13): el resumen de hoy y, al tocarlo, todos los datos de ModeloSalud.
            if let salud = modelo.conMuestras ? nil : modelo.salud {
                Section {
                    NavigationLink {
                        SaludDetalleView(modelo: salud)
                    } label: {
                        ResumenRecuperacion(salud: salud)
                    }
                    .accessibilityIdentifier("mis-datos-salud")
                } footer: {
                    Text("Sueño, pulso, variabilidad y actividad, si mostrar el score, y la conexión con Salud de Apple.")
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
}

/// La recuperación de hoy en una fila: el anillo con el score (o los días de calibración) y qué pasa, con lo mismo que
/// muestra la card de Mi Día.
private struct ResumenRecuperacion: View {
    let salud: ModeloSalud

    var body: some View {
        let estado = Self.estado(salud.cardRecuperacion)
        HStack(spacing: Espacio.m) {
            AnilloProgreso(fraccion: estado.fraccion, grosor: 7, color: estado.color) {
                if let numero = estado.numero {
                    Text(numero).font(.numeroMediano).contentTransition(.numericText())
                } else {
                    Image(systemName: estado.icono)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text("Recuperación").font(.headline)
                Text(estado.texto).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Espacio.xs)
        .accessibilityElement(children: .combine)
    }

    private struct Estado {
        var numero: String?
        var icono = "waveform.path.ecg"
        var fraccion: Double = 0
        var color: Color = .sueno
        var texto: String
    }

    private static func estado(_ card: SaludVista.CardRecuperacion) -> Estado {
        switch card {
        case .sinConectar:
            return Estado(texto: "Conectá tu reloj o Salud de Apple")
        case .conectadoSinScore(let caso):
            return Estado(icono: "hourglass", texto: caso.frase)
        case .calibrando(let dias, let porcentaje, _):
            return Estado(icono: "chart.bar.fill", fraccion: Double(porcentaje) / 100, texto: "Calibrando: \(dias) de 14 días")
        case .oculto:
            return Estado(icono: "eye.slash", texto: "Tenés el score apagado")
        case .conScore(let c):
            let score = c.fila.score ?? 0
            return Estado(numero: "\(score)", fraccion: Double(score) / 100,
                          color: CardRecuperacionView.color(c.banda), texto: "\(score)/100 · \(c.bandaTexto)")
        }
    }
}
