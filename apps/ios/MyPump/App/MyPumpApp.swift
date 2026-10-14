import SwiftUI

@main
struct MyPumpApp: App {
    @State private var datos = Muestras.cargar()
    @State private var descanso = Descanso()
    @State private var sesion = SesionEnCurso()

    var body: some Scene {
        WindowGroup {
            RaizApp(modelo: Proveedor.modelo) { Raiz(datos: datos) }
                .environment(descanso)
                .environment(sesion)
                .tint(Color.marcaTexto)
        }
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
