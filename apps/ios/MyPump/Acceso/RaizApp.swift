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

    var body: some View {
        Group {
            switch modelo.fase {
            case .listo:
                contenido()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if modelo.esDemo { BarraDemo(modelo: modelo) } else if modelo.desdeCache { BannerSinConexion() }
                    }
                    .overlay(alignment: .bottom) {
                        AvisoGuardado(estado: modelo.estadoGuardado)
                            .padding(.bottom, 96)   // arriba de la barra de pestañas
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
        .onOpenURL { url in
            Task {
                await modelo.entrar(con: url.absoluteString)
                // `?scene=diet` abre esa pestaña (ACC-09).
                let escena = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "scene" }?.value
                if let d = DestinoAviso(escena: escena) { CentroAvisos.shared.destino = d }
            }
        }
        .task { if modelo.fase == .cargando { await modelo.cargar() } }
        .onChange(of: fase, initial: true) { _, nueva in
            // Nada de sondeos con la app en segundo plano (CHA-04).
            modelo.enPrimerPlano = nueva == .active
            if nueva == .active { Task { await modelo.alVolverAPrimerPlano() } }
        }
        .background { MonitorDeRed { Task { await modelo.alVolverLaRed() } } }
        .task(id: modelo.fase == .listo && !modelo.esDemo) {
            // Con una cuenta: la local del domingo al día y el token de push refrescado (si ya hay permiso).
            if modelo.fase == .listo && !modelo.esDemo { await CentroAvisos.shared.alEntrar() }
        }
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
                .buttonStyle(.borderedProminent)
                .tint(Color.marca)
                .foregroundStyle(Color.sobreMarca)
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
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityIdentifier("salir-demo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
