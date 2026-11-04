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
        #if DEBUG
        if DemoUI.historialDeMuestra { ModeloEntreno.historialDeMuestra = { DemoUI.filasDeMuestra($0) } }
        #endif
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
                .task {
                    entrarEnDemoSiSePide()
                    // El Apple Watch (2.2): la rutina al reloj y sus series a la cola. Callado sin reloj con la app.
                    PuenteReloj.compartido.activar()
                }
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
        Proveedor.modelo.entrarEnDemo(rutina: DemoUI.cardioDePrueba ? DemoUI.conCintaDePrueba(rutina) : rutina, dieta: dieta, guia: DemoGuia.datos,
                                      suplementacion: DemoSuplementacion.datos)
        #endif
    }
}

/// Las pestañas: Entreno · Dieta · [Suplementación] · Chat · Revisión. Mis datos cuelga de Revisión, y Salud se abre en
/// una hoja desde la tarjeta Recuperación de arriba de Revisión (2.1.0, `Navegacion.saludAbierta`). En iPad (iOS 18+) la
/// barra de arriba se puede convertir en barra lateral.
struct Raiz: View {
    let datos: Muestras
    @State private var modelo = Proveedor.modelo
    // `simctl launch … -pestana dieta` abre directo en esa pestaña (capturas y pruebas de interfaz).
    @State private var navegacion = Navegacion(pestaña: Pestaña(argumento: UserDefaults.standard.string(forKey: "pestana") ?? "") ?? .entreno)
    /// La bienvenida de «Tu guía» (la primera vez, sin ningún video visto) y si se cerró con «Ver mi guía».
    @State private var bienvenidaGuia = false
    @State private var bienvenidaAbreGuia = false

    enum Pestaña: String, Hashable {
        case entreno, dieta, chat, revision, salud, suplementacion

        /// `-pestana progreso` (scripts y pruebas viejas) es Salud desde la 2.1.
        init?(argumento: String) { self.init(rawValue: argumento == "progreso" ? "salud" : argumento) }
    }

    /// Entreno: comentarios de Mati sin leer en los ejercicios. Chat: lo de Mati que llegó con el chat cerrado.
    /// Revisión: lo que falta de la semana (check y fotos). Siempre los reales: en la demo y en los bocetos, ninguno.
    private var badgeEntreno: Int { modelo.conMuestras ? 0 : modelo.entreno?.sinLeerEntreno ?? 0 }
    private var badgeChat: Int { modelo.conMuestras ? 0 : modelo.chat?.noLeidos ?? 0 }
    private var badgeRevision: Int { modelo.conMuestras ? 0 : modelo.pendientesDeLaSemana.total }
    /// La pestaña Suplementación: solo si `mypump_suplementacion` devolvió algo (o la demo trae la muestra).
    private var suplementacionVisible: ModeloSuplementacion? { modelo.suplementacion.flatMap { $0.hay ? $0 : nil } }

    /// Corresponde la bienvenida: hay guía sin ningún video visto, no salió nunca, se está en Entreno y no hay otra hoja.
    /// Sale del resumen y de la copia (nunca del get).
    private var pedirBienvenida: Bool {
        GuiaUI.bienvenidaPermitida && GuiaUI.modelo?.mostrarBienvenida == true && navegacion.pestaña == .entreno
            && !navegacion.saludAbierta && !bienvenidaGuia
    }

    private func presentarBienvenida() async {
        guard pedirBienvenida else { return }
        // Primero los permisos de la primera vez (la hoja de `RaizApp`): la bienvenida espera a que se cierren.
        while OnboardingPermisos.pendiente && !modelo.esDemo && modelo.token != nil {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
        }
        // Que se vea Entreno un momento antes (y que termine de irse la hoja de permisos, si estaba).
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled, pedirBienvenida, !OnboardingPermisos.pendiente || modelo.esDemo || modelo.token == nil else { return }
        bienvenidaGuia = true
    }

    var body: some View {
        @Bindable var navegacion = navegacion
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $navegacion.pestaña) {
                    Tab("Entreno", systemImage: "dumbbell.fill", value: Pestaña.entreno) { entreno }
                        .badge(badgeEntreno)
                    Tab("Dieta", systemImage: "fork.knife", value: Pestaña.dieta) { dieta }
                    if let s = suplementacionVisible {
                        Tab("Suplementación", systemImage: "pills.fill", value: Pestaña.suplementacion) { suplementacion(s) }
                    }
                    Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: Pestaña.chat) { chat }
                        .badge(badgeChat)
                    Tab("Revisión", systemImage: "checklist", value: Pestaña.revision) { revision }
                        .badge(badgeRevision)
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                TabView(selection: $navegacion.pestaña) {
                    entreno.tabItem { Label("Entreno", systemImage: "dumbbell.fill") }.tag(Pestaña.entreno)
                        .badge(badgeEntreno)
                    dieta.tabItem { Label("Dieta", systemImage: "fork.knife") }.tag(Pestaña.dieta)
                    if let s = suplementacionVisible {
                        suplementacion(s).tabItem { Label("Suplementación", systemImage: "pills.fill") }.tag(Pestaña.suplementacion)
                    }
                    chat.tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }.tag(Pestaña.chat)
                        .badge(badgeChat)
                    revision.tabItem { Label("Revisión", systemImage: "checklist") }.tag(Pestaña.revision)
                        .badge(badgeRevision)
                }
            }
        }
        .environment(navegacion)
        // Salud, en una hoja (desde la tarjeta de Revisión, un aviso o un link). Cambiar de pestaña la cierra.
        .sheet(isPresented: $navegacion.saludAbierta) {
            SaludView(datos: datos, alCerrar: { navegacion.saludAbierta = false })
                .environment(navegacion)
        }
        // `-pestana salud`: Revisión con la hoja de Salud abierta; el viejo `progreso`, en Fuerza.
        .onAppear {
            if navegacion.pestaña == .salud {
                navegacion.irASalud(UserDefaults.standard.string(forKey: "pestana") == "progreso" ? .fuerza : nil)
            }
        }
        .onChange(of: suplementacionVisible != nil, initial: true) { _, con in
            if !con, navegacion.pestaña == .suplementacion { navegacion.pestaña = .entreno }
        }
        // «Tu guía», la primera vez: la bienvenida a pantalla completa. «Ver mi guía» la abre en Entreno al cerrarse la hoja.
        .sheet(isPresented: $bienvenidaGuia, onDismiss: {
            guard bienvenidaAbreGuia else { return }
            bienvenidaAbreGuia = false
            navegacion.pestaña = .entreno
            navegacion.abrirGuia = true
        }) {
            if let g = GuiaUI.modelo {
                BienvenidaGuia(modelo: g, nombreCuenta: modelo.info?.nombre, ver: { bienvenidaAbreGuia = true; bienvenidaGuia = false }, despues: { bienvenidaGuia = false })
            }
        }
        .task(id: pedirBienvenida) { await presentarBienvenida() }
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
        // R2 de la 2.0.3: completar la semana de revisión (o terminar de cargarla al abrir) vuelve a armar el aviso del
        // domingo, que se saltea si ya está todo.
        .onChange(of: modelo.semanaDeRevisionCompleta) { Task { await CentroAvisos.shared.alCambiarLaSemana() } }
        #if DEBUG
        // `-verAvisoDomingo YES`: lo agendado del domingo, para que la prueba de interfaz lo lea.
        .overlay(alignment: .top) { if UserDefaults.standard.bool(forKey: "verAvisoDomingo") { AvisoDomingoDePrueba() } }
        #endif
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
    private func suplementacion(_ s: ModeloSuplementacion) -> some View { SuplementacionView(modelo: s).islaDeDescanso() }
}

#if DEBUG
/// `-verAvisoDomingo YES`: cuándo está agendado el aviso del domingo ("2026-11-08 11:00", o "sin aviso"), releído cada
/// segundo. Solo para la prueba de interfaz del R2 de la 2.0.3: lo agendado no se ve desde XCUITest.
private struct AvisoDomingoDePrueba: View {
    @State private var texto = ""
    var body: some View {
        Text(texto.isEmpty ? "sin aviso" : texto)
            .font(.caption2.monospaced())
            .padding(4)
            .background(.yellow)
            .accessibilityIdentifier("aviso-domingo")
            .task {
                while !Task.isCancelled {
                    texto = await CentroAvisos.shared.avisoDomingoAgendado()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}
#endif
