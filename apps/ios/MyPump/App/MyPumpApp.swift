import SwiftUI
import UIKit
import MyPumpDatos
import MyPumpReglas

@main
struct MyPumpApp: App {
    @UIApplicationDelegateAdaptor(DelegadoApp.self) private var delegado
    /// Las muestras de los bocetos (solo DEBUG; en la tienda, vacías).
    @State private var datos = Muestras.deLaApp()
    /// El motor de Entreno y su descanso: arriba de las pestañas, así el descanso se ve en cualquiera.
    @State private var entrenamiento = Entrenamiento()

    init() {
        // Apple Health cableada explícita (si no, ModeloSalud la busca por nombre y un renombre la apagaría sin avisar).
        ModeloSalud.fuenteDelSistema = FuenteHealthKit()
        // Los avisos de las pestañas con los colores de la marca: el verde del logo con el número en blanco.
        UITabBarItem.appearance().badgeColor = UIColor(hex: 0x1D9330)
        UITabBarItem.appearance().setBadgeTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        // El catálogo de ejercicios empaquetado: hasta que llega el del servidor, y para arrancar sin red.
        if let url = Bundle.main.url(forResource: "catalogo-ejercicios", withExtension: "json", subdirectory: "Bases.bundle"),
           let datos = try? Data(contentsOf: url), let c = try? CatalogoEjercicios(json: datos) {
            ModeloApp.catalogoEmpaquetado = c
        }
    }

    /// D5: el tema sigue al teléfono, salvo que el cliente haya elegido oscuro (en la web, o en Mis datos). La migración
    /// trae solo el `'dark'`: `theme.js` escribe `'light'` en cada carga, así que el claro no es una elección.
    @AppStorage("mypump-theme") private var tema = ""

    var body: some Scene {
        WindowGroup {
            raiz
                .environment(entrenamiento)
                // Los números como la web (`toLocaleString('es-AR')`), sea cual sea la región del teléfono: con la de
                // EE. UU. se veía "2,454 kcal" al lado de "15,1 g". Lo toman los `Text` con números interpolados o con
                // `format:` y los gráficos. Los campos son de texto (coma → punto): no cambia cómo se lee lo que se escribe.
                .environment(\.locale, Locale(identifier: "es_AR"))
                .tint(Color.marcaTexto)
                .preferredColorScheme(tema == "dark" ? .dark : nil)
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
    /// pantalla (por ejemplo, Dieta con la dieta de ejemplo). Los bocetos también entran a la demo: así Entreno y
    /// Dieta tienen su motor y su plan de ejemplo sin cuenta.
    @MainActor private func entrarEnDemoSiSePide() {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "entrar") == "demo" || UserDefaults.standard.bool(forKey: "bocetos"),
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
    @State private var modelo = Proveedor.modelo
    // `simctl launch … -pestana dieta` abre directo en esa pestaña (capturas y pruebas de interfaz).
    @State private var navegacion = Navegacion(pestaña: Pestaña(rawValue: UserDefaults.standard.string(forKey: "pestana") ?? "") ?? .entreno)

    enum Pestaña: String, Hashable { case entreno, dieta, chat, revision, progreso }

    /// Entreno: comentarios de Mati sin leer en los ejercicios. Chat: lo de Mati que llegó con el chat cerrado.
    /// Revisión: lo que falta de la semana (check y fotos). Siempre los reales: en la demo y en los bocetos, ninguno.
    private var badgeEntreno: Int { modelo.conMuestras ? 0 : modelo.entreno?.sinLeerEntreno ?? 0 }
    private var badgeChat: Int { modelo.conMuestras ? 0 : modelo.chat?.noLeidos ?? 0 }
    private var badgeRevision: Int { modelo.conMuestras ? 0 : modelo.pendientesDeLaSemana.total }

    var body: some View {
        @Bindable var navegacion = navegacion
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $navegacion.pestaña) {
                    Tab("Entreno", systemImage: "dumbbell.fill", value: Pestaña.entreno) { entreno }
                        .badge(badgeEntreno)
                    Tab("Dieta", systemImage: "fork.knife", value: Pestaña.dieta) { dieta }
                    Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: Pestaña.chat) { chat }
                        .badge(badgeChat)
                    Tab("Revisión", systemImage: "checklist", value: Pestaña.revision) { revision }
                        .badge(badgeRevision)
                    Tab("Progreso", systemImage: "chart.line.uptrend.xyaxis", value: Pestaña.progreso) { progreso }
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                TabView(selection: $navegacion.pestaña) {
                    entreno.tabItem { Label("Entreno", systemImage: "dumbbell.fill") }.tag(Pestaña.entreno)
                        .badge(badgeEntreno)
                    dieta.tabItem { Label("Dieta", systemImage: "fork.knife") }.tag(Pestaña.dieta)
                    chat.tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }.tag(Pestaña.chat)
                        .badge(badgeChat)
                    revision.tabItem { Label("Revisión", systemImage: "checklist") }.tag(Pestaña.revision)
                        .badge(badgeRevision)
                    progreso.tabItem { Label("Progreso", systemImage: "chart.line.uptrend.xyaxis") }.tag(Pestaña.progreso)
                }
            }
        }
        .environment(navegacion)
        .accesorioDeDescanso()
        // La barra de pestañas queda siempre entera: achicarla al bajar, como Música, empeoraba mucho el uso (Mati,
        // 15-oct). No volver a ponerle `tabBarMinimizeBehavior`.
        .sensoryFeedback(.selection, trigger: navegacion.pestaña)
        // Tocar un aviso (también en un arranque en frío): a su pestaña, y el destino se consume.
        .onChange(of: CentroAvisos.shared.destino, initial: true) { _, destino in
            guard let destino else { return }
            withAnimation(.snappy) { navegacion.ir(a: destino) }
            CentroAvisos.shared.destino = nil
        }
        // `?diag=health` (SAL-13): el diagnóstico de Salud directo, sin los cinco toques. Sin cuenta no hay qué diagnosticar.
        .sheet(isPresented: Binding(get: { CentroAvisos.shared.diagnosticoSalud && modelo.salud != nil },
                                    set: { if !$0 { CentroAvisos.shared.diagnosticoSalud = false } })) {
            if let salud = modelo.salud { NavigationStack { DiagnosticoSaludView(modelo: salud) } }
        }
    }

    private var entreno: some View { EntrenoView(datos: datos).islaDeDescanso() }
    private var dieta: some View { DietaView(datos: datos).islaDeDescanso() }
    private var chat: some View { ChatView(datos: datos).islaDeDescanso() }
    private var revision: some View { RevisionView(datos: datos).islaDeDescanso() }
    private var progreso: some View { ProgresoView(datos: datos).islaDeDescanso() }
}
