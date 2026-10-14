import SwiftUI
import UIKit
import UserNotifications
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Mis datos (propuesta D3 de la paridad): un lugar fijo para recuperación, salud, privacidad y borrado. Hoy en la web
/// solo se llega desde la card de Recuperación. Con la forma de Ajustes: filas con ícono en azulejo de color. La
/// recuperación abre los datos de salud de `ModeloSalud` (con "Mostrarme el score" y Salud de Apple, cuyo título abre el
/// diagnóstico con 5 toques); sin cuenta no existe. Ni la IA ni el aviso del domingo se configuran acá (pedido de Mati,
/// 14-oct): la IA trabaja bajo su aprobación y el aviso llega como un mensaje suyo (`CentroAvisos`). Solo queda, si
/// falta, el permiso de notificaciones del sistema.
struct MisDatosView: View {
    let datos: Muestras
    @State private var modelo = Proveedor.modelo
    /// El permiso de notificaciones (nil = todavía no se sabe). Sin él no llegan ni los mensajes de Mati ni su aviso del
    /// domingo: se ofrece activarlo.
    @State private var permiso: UNAuthorizationStatus?
    @Environment(\.scenePhase) private var fase
    /// D5: "dark" o nada (sigue al teléfono). Lo lee la raíz de la app.
    @AppStorage("mypump-theme") private var tema = ""
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

            if permiso != nil && !conPermiso && !modelo.conMuestras {
                Section {
                    Button {
                        Task { await activarNotificaciones() }
                    } label: {
                        Label { Text(permiso == .denied ? "Activar en Ajustes" : "Activar notificaciones") } icon: {
                            IconoAzulejo("bell.badge.fill", color: .peligro)
                        }
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("activar-notificaciones")
                } header: {
                    Text("Notificaciones")
                } footer: {
                    Text(permiso == .denied
                         ? "Las notificaciones de MyPump están apagadas en el \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"): los mensajes de Mati no te van a llegar hasta que las prendas."
                         : "Para que te lleguen los mensajes de Mati.")
                }
            }

            Section {
                Toggle(isOn: Binding(get: { tema == "dark" }, set: { tema = $0 ? "dark" : "" })) {
                    Label { Text("Siempre en modo oscuro") } icon: { IconoAzulejo("moon.fill", color: .sueno) }
                }
                .tint(Color.marcaVivo)
                .accessibilityIdentifier("tema-oscuro")
            } header: {
                Text("Apariencia")
            } footer: {
                // En iPad no dice "iPhone" (lo encontró la revisión de Android).
                let equipo = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
                Text(tema == "dark" ? "La app queda oscura aunque tu \(equipo) esté en claro." : "La app sigue a tu \(equipo): clara u oscura, como lo tengas.")
            }

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
                LabeledContent("Versión", value: ArranqueMigracion.version)
                if InformeActualizacion.existe {
                    NavigationLink("Informe de la actualización") { InformeActualizacion() }
                }
            } footer: {
                Text("MyPump no es un dispositivo médico. Ante cualquier duda de salud, consultá a tu médico.")
            }
        }
        .margenesDeLectura()
        .task { permiso = await CentroAvisos.shared.permiso() }
        // Al volver de Ajustes el permiso pudo cambiar.
        .onChange(of: fase) { _, nueva in
            if nueva == .active { Task { permiso = await CentroAvisos.shared.permiso() } }
        }
        .navigationTitle("Mis datos")
        .tint(Color.marcaTexto)
        .sheet(isPresented: $fuentes) { FuentesView() }
        .sheet(item: $pagina) { p in
            NavegadorInterno(url: URL(string: p.rawValue)!).ignoresSafeArea()
        }
    }

    private var conPermiso: Bool { [.authorized, .provisional, .ephemeral].contains(permiso) }

    /// Pide el permiso (si ya lo negó, iOS no vuelve a mostrar la hoja: se lleva a Ajustes). Con el sí, `activar`
    /// agenda el aviso del domingo y registra el push.
    private func activarNotificaciones() async {
        if permiso == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
            return
        }
        await CentroAvisos.shared.activar()
        permiso = await CentroAvisos.shared.permiso()
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

/// Lo que hizo la migración desde la app vieja (`legado/registro.log`): conteos y estados, sin tokens ni contenido. Para
/// el soporte sin Xcode (la primera prueba en un iPhone, TF-0): se lee acá y se puede compartir con Mati.
struct InformeActualizacion: View {
    static var url: URL { EntornoLegado().carpeta.appendingPathComponent("registro.log") }
    static var existe: Bool { FileManager.default.fileExists(atPath: url.path) }

    @State private var texto = ""

    var body: some View {
        ScrollView {
            Text(texto.isEmpty ? "Todavía no hay nada registrado." : texto)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.fondo)
        .navigationTitle("Informe de la actualización")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !texto.isEmpty { ShareLink(item: texto) }
        }
        .task { texto = (try? String(contentsOf: Self.url, encoding: .utf8)) ?? "" }
    }
}
