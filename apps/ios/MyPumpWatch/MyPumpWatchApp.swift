import SwiftUI
import MyPumpReloj

/// La app del Apple Watch (tanda 3, 2.2): la rutina del día con la corona, el descanso con háptica, FC y calorías en vivo
/// (sin guardar en Salud), y una cola propia que pasa al iPhone por WatchConnectivity.
///
/// Para el simulador y las capturas: `-demo` (la rutina de muestra, sin iPhone) y `-pantalla lista|ejercicio|descanso|
/// resumen|vacio` para abrir directo en una pantalla.
@main
struct MyPumpWatchApp: App {
    @State private var estado = EstadoReloj()
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            RaizReloj()
                .environment(estado)
                .tint(Marca.verde)
        }
        .onChange(of: fase) { _, f in
            if f == .active { estado.alActivarse() }
        }
    }
}

/// El verde del logo en oscuro (#5BBE62), como la Live Activity del teléfono.
enum Marca {
    static let verde = Color(red: 0x5B / 255, green: 0xBE / 255, blue: 0x62 / 255)
    static let oro = Color(red: 0xFA / 255, green: 0xCB / 255, blue: 0x39 / 255)
}
