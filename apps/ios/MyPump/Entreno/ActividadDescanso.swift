@preconcurrency import ActivityKit
import Foundation
import MyPumpReglas

/// MISMA definición que `DescansoWidget/DescansoAtributos.swift` (la extensión la dibuja): ActivityKit las une por el
/// nombre y la forma, así que si cambia acá, cambia allá.
struct DescansoAtributos: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var fin: Date
        var objetivo: Int
    }
}

/// El descanso como Live Activity (Ian Actis, 20-oct): arranca con el descanso, se corre con −15/+15 y se va al
/// saltarlo o cuando la barra se cierra. Si termina con la app en segundo plano, la actividad queda «vencida»
/// (`staleDate` = el fin) y la extensión muestra «¡A la próxima serie!»; se borra al volver a la app.
@MainActor
final class ActividadDescanso {
    private var actual: Activity<DescansoAtributos>?
    private var fin: Double?

    init() {
        // Las que quedaron de una sesión anterior (la app cerrada a la fuerza en medio de un descanso).
        for vieja in Activity<DescansoAtributos>.activities {
            Task { await vieja.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func sincronizar(_ d: Descanso?) {
        guard let d else { terminar(); return }
        guard d.fin != fin else { return }
        fin = d.fin
        let finFecha = Date(timeIntervalSince1970: d.fin / 1000)
        let contenido = ActivityContent(state: DescansoAtributos.ContentState(fin: finFecha, objetivo: Int(d.objetivo)),
                                        staleDate: finFecha)
        if let a = actual {
            Task { await a.update(contenido) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            actual = try? Activity.request(attributes: DescansoAtributos(), content: contenido, pushType: nil)
        }
    }

    func terminar() {
        fin = nil
        guard let a = actual else { return }
        actual = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
