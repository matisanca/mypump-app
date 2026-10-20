import ActivityKit
import Foundation

/// El descanso entre series como Live Activity (Ian Actis, 20-oct: «verlo en tiempo real en notificaciones, que quedan
/// 10 segundos y ya ir preparándote»): la cuenta regresiva en la pantalla bloqueada y en la Dynamic Island.
/// MISMA definición en `MyPump/Entreno/ActividadDescanso.swift` (la app la pide, la extensión la dibuja): ActivityKit
/// las une por el nombre y la forma, así que si cambia acá, cambia allá.
struct DescansoAtributos: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Cuándo termina el descanso.
        var fin: Date
        /// El objetivo en segundos (lo pedido más lo sumado con +15).
        var objetivo: Int
    }
}
