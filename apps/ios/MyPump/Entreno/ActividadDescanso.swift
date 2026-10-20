@preconcurrency import ActivityKit
import Foundation
import MyPumpReglas

/// El descanso como Live Activity (Ian Actis, 20-oct): arranca con el descanso, se corre con −15/+15 y se va al saltarlo,
/// al terminar o al completar el día. Si termina con la app en segundo plano, la actividad queda «vencida»
/// (`staleDate` = el fin) y la extensión muestra «¡A la próxima serie!»; se cierra al volver a la app.
/// Los pedidos a ActivityKit van en orden (una cola): dos ±15 seguidos no pueden llegar al revés.
@MainActor
final class ActividadDescanso {
    private var actual: Activity<DescansoAtributos>?
    /// El fin que ya tiene la actividad (no se reenvía lo mismo 4 veces por segundo).
    private var fin: Double?
    /// Un fin que ActivityKit no aceptó tres veces: no se insiste en ese descanso.
    private var intentos: (fin: Double, veces: Int)?
    private var cola: Task<Void, Never>?

    init() {
        // La que quedó de antes (la app se cerró en medio de un descanso) se adopta: si el descanso se restaura, se
        // actualiza; si no, `limpiar` la cierra al mostrarse la app. Si hubiera más de una, las demás se cierran.
        let todas = Activity<DescansoAtributos>.activities
        actual = todas.first
        for extra in todas.dropFirst() { encolar { await extra.end(nil, dismissalPolicy: .immediate) } }
    }

    private func encolar(_ trabajo: @escaping () async -> Void) {
        let anterior = cola
        cola = Task { await anterior?.value; await trabajo() }
    }

    func sincronizar(_ d: Descanso?) {
        guard let d else { limpiar(); return }
        guard d.fin != fin else { return }
        let finFecha = Date(timeIntervalSince1970: d.fin / 1000)
        let contenido = ActivityContent(state: DescansoAtributos.ContentState(fin: finFecha, objetivo: Int(d.objetivo)),
                                        staleDate: finFecha)
        if let a = actual {
            fin = d.fin
            encolar { await a.update(contenido) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let i = intentos, i.fin == d.fin, i.veces >= 3 { return }
        actual = try? Activity.request(attributes: DescansoAtributos(), content: contenido, pushType: nil)
        if actual != nil {
            fin = d.fin
            intentos = nil
        } else {
            // Si falló (por ejemplo, se bloqueó el teléfono justo al pedirla), se reintenta en el próximo tick.
            intentos = (d.fin, (intentos?.fin == d.fin ? intentos!.veces : 0) + 1)
        }
    }

    /// Sin descanso a la vista: no tiene que quedar ninguna (la propia y cualquiera que haya quedado de antes).
    func limpiar() {
        fin = nil
        intentos = nil
        actual = nil
        for a in Activity<DescansoAtributos>.activities { encolar { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
