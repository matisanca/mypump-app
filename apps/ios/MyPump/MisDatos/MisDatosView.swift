import SwiftUI
import UIKit
import UserNotifications
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos
import MyPumpReloj

/// Mis datos (propuesta D3 de la paridad): un lugar fijo para recuperación, salud, privacidad y borrado. Hoy en la web
/// solo se llega desde la card de Recuperación. Con la forma de Ajustes: filas con ícono en azulejo de color. La
/// recuperación abre los datos de salud de `ModeloSalud` (con "Mostrarme el score" y Salud de Apple, cuyo título abre el
/// diagnóstico con 5 toques); sin cuenta no existe. Ni la IA ni el aviso del domingo se configuran acá (pedido de Mati,
/// 14-oct): la IA trabaja bajo su aprobación y el aviso llega como un mensaje suyo (`CentroAvisos`). Solo queda, si
/// falta, el permiso de notificaciones del sistema.
struct MisDatosView: View {
    let datos: Muestras
    @State private var logrosALaVista = false
    @State private var modelo = Proveedor.modelo
    /// El permiso de notificaciones (nil = todavía no se sabe). Sin él no llegan ni los mensajes de Mati ni su aviso del
    /// domingo: se ofrece activarlo.
    @State private var permiso: UNAuthorizationStatus?
    @Environment(\.scenePhase) private var fase
    /// D5: "dark" o nada (sigue al teléfono). Lo lee la raíz de la app.
    @AppStorage("mypump-theme") private var tema = ""
    @State private var fuentes = false
    @State private var pagina: Pagina?
    /// Tanda 4: la fila del conteo de reps, con el reloj emparejado y la app del reloj instalada, o con series grabadas
    /// en el iPhone (para poder exportarlas o borrarlas aunque ya no haya reloj).
    @State private var calibracionVisible = false
    @State private var verDocumentos = false
    @Environment(Navegacion.self) private var navegacion: Navegacion?

    /// Las páginas legales de la web, en Safari dentro de la app (como hoy).
    enum Pagina: String, Identifiable {
        case privacidad = "https://app.mypumpteam.com/privacidad.html"
        case borrado = "https://app.mypumpteam.com/eliminar-datos.html"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            // La recuperación (SAL-09…13), «Estudios y órdenes» y «Presión arterial» se mudaron a «Mi salud» (11/11): acá queda
            // una sola fila que lleva ahí. Los datos de salud (score, Salud de Apple) se abren desde la card de Recuperación.
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
                         ? "Las notificaciones de Pump Team están apagadas en el \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"): los mensajes de Mati no te van a llegar hasta que las prendas."
                         : "Para que te lleguen los mensajes de Mati.")
                }
            }

            // Simplificar (11/11): unos 10 renglones en tres grupos cortos. Lo que salió tiene su lugar: Novedades en Revisión
            // (debajo de la devolución), Mi gimnasio y Mi técnica en «Mi gimnasio y mi técnica» (Entreno) y las fotos de inicio
            // en su tarjeta de Revisión (fija mientras estén pedidas; el aviso `fotos_inicio` la abre).
            Section("Mi plan") {
                // «Tu recorrido con Mati» (palanca `fin_plan`), mientras se vea: abre la misma hoja que la tarjeta.
                FilaRecorridoMisDatos()
                // Documentos (contrato y consentimiento): solo si `mypump_contrato_get` devolvió alguno.
                if let docs = modelo.conMuestras ? nil : modelo.documentos, docs.hay {
                    NavigationLink { DocumentosView(modelo: docs) } label: {
                        Label { Text(TextosDocumentos.entradaMisDatos) } icon: {
                            IconoAzulejo("doc.text.fill", color: docs.contratoPendiente ? .alerta : .marcaTexto)
                        }
                    }
                    .badge(docs.contratoPendiente ? Text("Pendiente").foregroundStyle(Color.alerta) : nil)
                    .accessibilityIdentifier("mis-datos-documentos")
                }
                // «Tu guía» fuera de Entreno: después de la entrega, si la quitó o a los 7 días de verla entera (su lugar
                // fijo; nunca se oculta del todo). Sale del resumen, sin cartel.
                if let guia = GuiaUI.modelo, guia.filaMisDatos() {
                    NavigationLink { GuiaView(modelo: guia) } label: {
                        Label { Text("Ver mi guía") } icon: { IconoAzulejo("play.rectangle.fill", color: .marcaTexto) }
                    }
                    .accessibilityIdentifier("mis-datos-guia")
                }
                // «Mi salud» (11/11): donde estaban la recuperación, «Estudios y órdenes» y «Presión arterial». Atajo.
                if filaMiSalud { FilaMiSaludMisDatos() }
                Button { fuentes = true } label: {
                    fila("Respaldo científico del plan", icono: "book.closed.fill", color: .marcaTexto)
                }
                .tint(.primary)
            }

            Section {
                Toggle(isOn: Binding(get: { tema == "dark" }, set: { tema = $0 ? "dark" : "" })) {
                    Label { Text("Siempre en modo oscuro") } icon: { IconoAzulejo("moon.fill", color: .sueno) }
                }
                .tint(Color.marcaVivo)
                .accessibilityIdentifier("tema-oscuro")
                if calibracionVisible, let cuenta = cuentaCalibracion {
                    NavigationLink { CalibracionView(cuenta: cuenta) } label: {
                        Label { Text("Conteo de reps") } icon: { IconoAzulejo("waveform.path.ecg", color: .agua) }
                    }
                    .accessibilityIdentifier("mis-datos-calibracion")
                }
            } header: {
                Text("Ajustes")
            } footer: {
                // En iPad no dice "iPhone" (lo encontró la revisión de Android).
                let equipo = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
                VStack(alignment: .leading, spacing: 4) {
                    Text(tema == "dark" ? "La app queda oscura aunque tu \(equipo) esté en claro." : "La app sigue a tu \(equipo): clara u oscura, como lo tengas.")
                    if calibracionVisible, cuentaCalibracion != nil {
                        Text(modelo.palanca.contadorRepsReloj
                             ? "Conteo de reps: experimental. El Apple Watch cuenta las repeticiones de cada serie y te las propone."
                             : "Conteo de reps: experimental. Por ahora el Apple Watch no propone las repeticiones.")
                    }
                }
            }

            // Logros (2.3.0): con la palanca prendida, o con el permiso dado (para poder sacarlo siempre).
            // Una vez a la vista, la sección no se va mientras Mis datos siga abierto: al apagar el interruptor con la palanca
            // apagada tiene que quedar el «Listo, no se comparte nada más.».
            if !modelo.conMuestras, let wins = modelo.wins, wins.visibleEnMisDatos || logrosALaVista {
                SeccionLogros(wins: wins)
                    .onAppear { logrosALaVista = true }
            }

            Section("Privacidad") {
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
                Text("Pump Team no es un dispositivo médico. Ante cualquier duda de salud, consultá a tu médico.")
            }
        }
        .margenesDeLectura()
        .task { permiso = await CentroAvisos.shared.permiso() }
        .onAppear { calibracionVisible = conFilaCalibracion }
        // Al volver de Ajustes el permiso pudo cambiar.
        .onChange(of: fase) { _, nueva in
            if nueva == .active {
                calibracionVisible = conFilaCalibracion
                Task { permiso = await CentroAvisos.shared.permiso() }
            }
        }
        .navigationTitle("Mis datos")
        .tint(Color.marcaTexto)
        .sheet(isPresented: $fuentes) { FuentesView() }
        // El aviso del contrato pendiente pide Documentos: se abre y se consume. Sin documentos (un error, o ya no
        // hay), queda Mis datos.
        .navigationDestination(isPresented: $verDocumentos) {
            if let docs = modelo.documentos { DocumentosView(modelo: docs) }
        }
        .onChange(of: navegacion?.documentos ?? false, initial: true) { _, abrir in
            guard abrir else { return }
            navegacion?.documentos = false
            if modelo.documentos?.hay == true { verDocumentos = true }
        }
        .sheet(item: $pagina) { p in
            NavegadorInterno(url: URL(string: p.rawValue)!).ignoresSafeArea()
        }
    }

    /// La cuenta para el modo calibración (el hash del reloj, nunca el token). Sin cuenta o en la demo, no hay modo.
    private var cuentaCalibracion: String? {
        guard !modelo.conMuestras, let c = modelo.entreno?.cuentaReloj, c != "demo" else { return nil }
        return c
    }

    private var conFilaCalibracion: Bool {
        guard let cuenta = cuentaCalibracion else { return false }
        // Si se mandaron series, la fila queda aunque ya no haya reloj: desde acá se revoca.
        return PuenteReloj.compartido.hayReloj || UserDefaults.standard.bool(forKey: DatosCalibracion.claveSeManda(cuenta))
            || !DatosCalibracion.sesiones().isEmpty
    }

    /// La fila «Mi salud»: con cuenta (estaba la recuperación) o con Estudios o Presión habilitados.
    private var filaMiSalud: Bool {
        (!modelo.conMuestras && modelo.salud != nil) || modelo.estudios?.habilitado == true || modelo.presion?.habilitado == true
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
