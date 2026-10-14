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
        .onOpenURL { url in Task { await modelo.entrar(con: url.absoluteString) } }
        .task { if modelo.fase == .cargando { await modelo.cargar() } }
        .onChange(of: fase) { _, nueva in
            switch nueva {
            case .active:
                modelo.chat?.empezarSondeo()
                Task { await modelo.alVolverAPrimerPlano() }
            case .background:
                // Nada de sondeos con la app en segundo plano (CHA-04).
                modelo.chat?.pararSondeo()
            default: break
            }
        }
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

/// Sin red y sin copia guardada (ACC-05): reintentar a mano, y una sola recarga automática cuando vuelve la red.
private struct SinConexion: View {
    let modelo: ModeloApp
    @State private var reintentando = false
    @State private var yaReintentoSolo = false
    @State private var monitor: NWPathMonitor?

    var body: some View {
        VStack(spacing: 22) {
            ContentUnavailableView {
                Label("Sin conexión", systemImage: "wifi.slash")
            } description: {
                Text("No pudimos traer tu plan. Cuando vuelva la señal lo intentamos solos.")
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
        .onAppear {
            let m = NWPathMonitor()
            m.pathUpdateHandler = { camino in
                guard camino.status == .satisfied else { return }
                Task { @MainActor in
                    guard !yaReintentoSolo else { return }
                    yaReintentoSolo = true
                    await reintentar()
                }
            }
            m.start(queue: .main)
            monitor = m
        }
        .onDisappear { monitor?.cancel() }
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
