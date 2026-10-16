import SwiftUI
import Network
import MyPumpDatos

/// Qué ve el cliente según el estado de su cuenta: bienvenida (sin link o link vencido), arranque, sin conexión sin
/// copia guardada, o la app. Los links `app.mypumpteam.com/?t=` (universal links) entran desde cualquier estado; uno
/// con otro token cambia de cuenta, como en la web (ACC-10).
struct RaizApp<Contenido: View>: View {
    let modelo: ModeloApp
    @ViewBuilder let contenido: () -> Contenido
    @Environment(\.scenePhase) private var fase
    @State private var onboarding = false

    private static var versionInstalada: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    var body: some View {
        Group {
            switch modelo.fase {
            case .listo:
                if PalancaRemota.debajo(Self.versionInstalada, de: modelo.palanca.versionMinimaIOS) {
                    ActualizarApp()
                } else {
                    // El aviso arriba y las pestañas DEBAJO (no con `safeAreaInset`: en iOS 26 las barras de navegación de
                    // las pestañas no se corrían y el aviso tapaba el botón de volver, en la demo y sin conexión).
                    VStack(spacing: 0) {
                        if modelo.esDemo { if !DemoUI.captura { BarraDemo(modelo: modelo) } } else if modelo.desdeCache { BannerSinConexion() }
                        contenido()
                    }
                    .overlay(alignment: .bottom) {
                        AvisoGuardado(estado: modelo.estadoGuardado)
                            .padding(.bottom, 96)   // arriba de la barra de pestañas
                    }
                }
            case .cargando:
                Arranque()
            case .sinServicio:
                SinConexion(modelo: modelo)
            case .sinToken, .tokenInvalido:
                AccesoView(modelo: modelo)
            }
        }
        .animation(.snappy, value: modelo.fase)
        // Un link tocado con la cuenta andando que no se usó: se avisa y se sigue en la cuenta (hallazgo 11).
        .alert("Este link ya no sirve", isPresented: avisoLink(.vencido)) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Seguís con tu cuenta.")
        }
        .alert("Sin conexión", isPresented: avisoLink(.sinConexion)) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("No pudimos abrir ese link. Probá de nuevo cuando tengas señal.")
        }
        .onOpenURL { url in
            Task {
                await modelo.entrar(con: url.absoluteString)
                // `?scene=diet` abre esa pestaña y `?diag=health` el diagnóstico de Salud (ACC-09).
                let parametros = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let escena = parametros.first { $0.name == "scene" }?.value
                if let d = DestinoAviso(escena: escena) { CentroAvisos.shared.destino = d }
                if parametros.first(where: { $0.name == "diag" })?.value == "health" { CentroAvisos.shared.diagnosticoSalud = true }
            }
        }
        .task { if modelo.fase == .cargando { await modelo.cargar() } }
        .onChange(of: fase, initial: true) { _, nueva in
            // Nada de sondeos con la app en segundo plano (CHA-04).
            modelo.enPrimerPlano = nueva == .active
            switch nueva {
            case .active:
                CentroAvisos.shared.cancelarFinDescanso()
                // Con la cuenta, también los avisos (`ModeloApp.conAvisos`): el del domingo es de una vez y se vuelve a
                // armar cada vez que se usa la app (iOS la deja viva días sin un arranque nuevo), y un permiso dado desde
                // Ajustes registra el push al volver (hallazgo 9).
                Task { await modelo.alVolverAPrimerPlano() }
            case .background:
                // Un descanso corriendo avisa cuando termina aunque la app no esté a la vista (D8).
                if let d = modelo.entreno?.descanso.descanso, !d.terminado {
                    let fin = Date(timeIntervalSince1970: d.fin / 1000)
                    Task { await CentroAvisos.shared.programarFinDescanso(fin) }
                }
            default: break
            }
        }
        .background { MonitorDeRed { Task { await modelo.alVolverLaRed() } } }
        // Cerrada como sea (también deslizando), queda vista (hallazgo 12).
        .sheet(isPresented: $onboarding, onDismiss: { OnboardingPermisos.marcarVista() }) {
            OnboardingPermisos(modelo: modelo) { onboarding = false }
        }
        .task(id: modelo.fase == .listo && !modelo.esDemo && modelo.token != nil) {
            // La primera vez con una cuenta, 1,2 s después de pintar: Salud y Notificaciones (GEN-06). Nunca en la demo.
            guard modelo.fase == .listo, !modelo.esDemo, modelo.token != nil, OnboardingPermisos.pendiente else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            if !Task.isCancelled, modelo.fase == .listo, !modelo.esDemo { onboarding = true }
        }
        .task(id: modelo.fase == .listo && !modelo.esDemo) {
            // Con una cuenta: la local del domingo al día y el token de push refrescado (si ya hay permiso). Sin cuenta o
            // con el link vencido, el domingo se cancela (hallazgo 8 de la revisión del 15-oct).
            if modelo.fase == .listo && !modelo.esDemo {
                await CentroAvisos.shared.alEntrar()
            } else if modelo.fase == .tokenInvalido || modelo.fase == .sinToken {
                CentroAvisos.shared.cancelarDomingo()
            }
        }
    }

    private func avisoLink(_ aviso: ModeloApp.AvisoLink) -> Binding<Bool> {
        Binding(get: { modelo.avisoLink == aviso }, set: { if !$0 { modelo.avisoLink = nil } })
    }
}

/// Mientras se trae la cuenta por primera vez (con copia offline la app abre directo).
private struct Arranque: View {
    var body: some View {
        VStack(spacing: 24) {
            Marca()
            ProgressView().controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FondoMarca())
    }
}

/// Avisa cuando la red VUELVE (pasa de no disponible a disponible), no en el primer aviso del sistema: así un
/// reintento automático no se gasta apenas aparece la pantalla.
struct MonitorDeRed: View {
    let alVolver: () -> Void
    @State private var vigia: VigiaDeRed?

    var body: some View {
        Color.clear
            .onAppear { vigia = VigiaDeRed(alVolver: alVolver) }
            .onDisappear { vigia?.parar(); vigia = nil }
            .accessibilityHidden(true)
    }
}

@MainActor
final class VigiaDeRed {
    private let monitor = NWPathMonitor()
    private var anterior: NWPath.Status?
    private let alVolver: () -> Void

    init(alVolver: @escaping () -> Void) {
        self.alVolver = alVolver
        monitor.pathUpdateHandler = { [weak self] camino in
            let estado = camino.status
            Task { @MainActor in self?.cambio(estado) }
        }
        monitor.start(queue: .main)
    }

    private func cambio(_ estado: NWPath.Status) {
        defer { anterior = estado }
        guard let previo = anterior, previo != .satisfied, estado == .satisfied else { return }
        alVolver()
    }

    func parar() { monitor.cancel() }
}

/// Sin copia guardada y sin poder traer el plan (ACC-05): "Sin conexión" o "Servicio fuera de línea" según lo que pasó,
/// reintentar a mano y una sola recarga automática cuando vuelve la red.
/// La palanca remota pide una versión más nueva (`version_minima_ios`): una versión con un problema grave deja de
/// mostrarse hasta actualizar. La cola sigue subiendo sola lo que el cliente ya cargó.
private struct ActualizarApp: View {
    @Environment(\.openURL) private var abrir

    var body: some View {
        ContentUnavailableView {
            Label("Actualizá Pump Team", systemImage: "arrow.down.app")
        } description: {
            Text("Hay una versión nueva que necesitás para seguir. Lo que ya cargaste está guardado.")
        } actions: {
            Button {
                abrir(URL(string: "itms-apps://apps.apple.com/app/id6793259380")!)
            } label: {
                Text("Abrir el App Store").fontWeight(.semibold)
            }
            .buttonStyle(BotonMarca(compacto: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FondoMarca())
    }
}

private struct SinConexion: View {
    let modelo: ModeloApp
    @State private var reintentando = false
    @State private var yaReintentoSolo = false

    private var servidorCaido: Bool { modelo.ultimaFalla != nil && modelo.ultimaFalla != .red }

    var body: some View {
        VStack(spacing: 22) {
            ContentUnavailableView {
                Label(servidorCaido ? "Servicio fuera de línea" : "Sin conexión", systemImage: servidorCaido ? "icloud.slash" : "wifi.slash")
            } description: {
                Text(servidorCaido
                     ? "No pudimos traer tu plan. Estamos con un problema del servicio: probá de nuevo en unos minutos."
                     : "No pudimos traer tu plan. Cuando vuelva la señal lo intentamos solos.")
            } actions: {
                Button {
                    Task { await reintentar() }
                } label: {
                    if reintentando { ProgressView() } else { Text("Reintentar").fontWeight(.semibold) }
                }
                .buttonStyle(BotonMarca(compacto: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FondoMarca())
        .background {
            MonitorDeRed {
                guard !yaReintentoSolo else { return }
                yaReintentoSolo = true
                Task { await reintentar() }
            }
        }
    }

    private func reintentar() async {
        reintentando = true
        await modelo.cargar()
        reintentando = false
    }
}

/// En la demo: un aviso fijo arriba con la salida.
private struct BarraDemo: View {
    let modelo: ModeloApp

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Color.marcaTexto)
            Text("Estás viendo la demo").font(.subheadline.weight(.semibold))
            Spacer()
            Button("Salir") { Task { await modelo.salirDeDemo() } }
                .buttonStyle(BotonSecundario(compacto: true))
                .accessibilityIdentifier("salir-demo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
