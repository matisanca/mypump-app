import SwiftUI

@main
struct MyPumpApp: App {
    @State private var datos = Muestras.cargar()

    var body: some Scene {
        WindowGroup {
            Raiz(datos: datos)
                .tint(Color.marcaTexto)
        }
    }
}

/// Las 5 pestañas de la app actual: Entreno · Dieta · Chat · Revisión · Progreso. Mis datos cuelga de Revisión.
struct Raiz: View {
    let datos: Muestras
    // Bocetos: `simctl launch … -pestana dieta` abre directo en esa pestaña para sacar capturas.
    @State private var pestaña = Pestaña(rawValue: UserDefaults.standard.string(forKey: "pestana") ?? "") ?? .entreno

    enum Pestaña: String { case entreno, dieta, chat, revision, progreso }

    var body: some View {
        TabView(selection: $pestaña) {
            EntrenoView(datos: datos)
                .tabItem { Label("Entreno", systemImage: "dumbbell.fill") }.tag(Pestaña.entreno)
            DietaView(datos: datos)
                .tabItem { Label("Dieta", systemImage: "fork.knife") }.tag(Pestaña.dieta)
            ChatView(datos: datos)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }.tag(Pestaña.chat)
                .badge(1)
            RevisionView(datos: datos)
                .tabItem { Label("Revisión", systemImage: "checklist") }.tag(Pestaña.revision)
                .badge(2)
            ProgresoView(datos: datos)
                .tabItem { Label("Progreso", systemImage: "chart.line.uptrend.xyaxis") }.tag(Pestaña.progreso)
        }
        .sensoryFeedback(.selection, trigger: pestaña)
    }
}
