import SwiftUI
import MyPumpDatos

@main
struct MyPumpApp: App {
    @State private var datos = Muestras.cargar()
    @State private var descanso = Descanso()
    @State private var sesion = SesionEnCurso()

    var body: some Scene {
        WindowGroup {
            raiz
                .environment(descanso)
                .environment(sesion)
                .tint(Color.marcaTexto)
                .task { entrarEnDemoSiSePide() }
        }
    }

    @ViewBuilder @MainActor private var raiz: some View {
        #if DEBUG
        // Capturas de diseño (`-bocetos YES`): las pestañas con las muestras, sin pasar por la bienvenida ni usar
        // ningún token. Solo en DEBUG.
        if UserDefaults.standard.bool(forKey: "bocetos") {
            Raiz(datos: datos)
        } else {
            RaizApp(modelo: Proveedor.modelo) { Raiz(datos: datos) }
        }
        #else
        RaizApp(modelo: Proveedor.modelo) { Raiz(datos: datos) }
        #endif
    }

    /// `-entrar demo` (DEBUG): lo mismo que tocar "Ver demo" en la bienvenida, para capturar la demo sin tocar la
    /// pantalla (por ejemplo, Dieta con la dieta de ejemplo).
    @MainActor private func entrarEnDemoSiSePide() {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "entrar") == "demo",
              let r = Bundle.main.url(forResource: "rutina", withExtension: "json", subdirectory: "Demo.bundle"),
              let d = Bundle.main.url(forResource: "dieta", withExtension: "json", subdirectory: "Demo.bundle"),
              let rutina = try? Data(contentsOf: r), let dieta = try? Data(contentsOf: d) else { return }
        Proveedor.modelo.entrarEnDemo(rutina: rutina, dieta: dieta)
        #endif
    }
}

/// Las 5 pestañas de la app actual: Entreno · Dieta · Chat · Revisión · Progreso. Mis datos cuelga de Revisión.
/// En iPad (iOS 18+) la barra de arriba se puede convertir en barra lateral.
struct Raiz: View {
    let datos: Muestras
    // Bocetos: `simctl launch … -pestana dieta` abre directo en esa pestaña para sacar capturas.
    @State private var pestaña = Pestaña(rawValue: UserDefaults.standard.string(forKey: "pestana") ?? "") ?? .entreno
    @Environment(Descanso.self) private var descanso

    enum Pestaña: String, Hashable { case entreno, dieta, chat, revision, progreso }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $pestaña) {
                    Tab("Entreno", systemImage: "dumbbell.fill", value: Pestaña.entreno) { entreno }
                    Tab("Dieta", systemImage: "fork.knife", value: Pestaña.dieta) { dieta }
                    Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: Pestaña.chat) { chat }
                        .badge(1)
                    Tab("Revisión", systemImage: "checklist", value: Pestaña.revision) { revision }
                        .badge(2)
                    Tab("Progreso", systemImage: "chart.line.uptrend.xyaxis", value: Pestaña.progreso) { progreso }
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                TabView(selection: $pestaña) {
                    entreno.tabItem { Label("Entreno", systemImage: "dumbbell.fill") }.tag(Pestaña.entreno)
                    dieta.tabItem { Label("Dieta", systemImage: "fork.knife") }.tag(Pestaña.dieta)
                    chat.tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }.tag(Pestaña.chat)
                        .badge(1)
                    revision.tabItem { Label("Revisión", systemImage: "checklist") }.tag(Pestaña.revision)
                        .badge(2)
                    progreso.tabItem { Label("Progreso", systemImage: "chart.line.uptrend.xyaxis") }.tag(Pestaña.progreso)
                }
            }
        }
        .accesorioDeDescanso(descanso)
        .barraQueSeAchica()
        .sensoryFeedback(.selection, trigger: pestaña)
    }

    private var entreno: some View { EntrenoView(datos: datos).islaDeDescanso(descanso) }
    private var dieta: some View { DietaView(datos: datos).islaDeDescanso(descanso) }
    private var chat: some View { ChatView(datos: datos).islaDeDescanso(descanso) }
    private var revision: some View { RevisionView(datos: datos).islaDeDescanso(descanso) }
    private var progreso: some View { ProgresoView(datos: datos).islaDeDescanso(descanso) }
}
