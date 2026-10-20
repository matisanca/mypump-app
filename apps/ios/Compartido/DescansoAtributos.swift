import ActivityKit
import Foundation

/// El descanso entre series como Live Activity (Ian Actis, 20-oct: «verlo en tiempo real en notificaciones, que quedan
/// 10 segundos y ya ir preparándote»): la cuenta regresiva en la pantalla bloqueada y en la Dynamic Island. La pide la
/// app (`ActividadDescanso`) y la dibuja la extensión (`DescansoWidget`): este archivo es de las dos (carpeta
/// sincronizada `Compartido`, en los dos targets), así nunca se desarman.
struct DescansoAtributos: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Cuándo termina el descanso.
        var fin: Date
        /// El objetivo en segundos (lo pedido más lo sumado con +15).
        var objetivo: Int
    }
}
