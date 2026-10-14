import SwiftUI
import Observation

/// El descanso entre series. Cuenta contra una FECHA de fin, no con un contador: sobrevive a irse de la app y volver.
/// Al llegar a cero avisa (vibración, barra verde) y a los 2 s se cierra solo, como en la web (SES-04).
@MainActor @Observable
final class Descanso {
    private(set) var fin: Date?
    private(set) var total: TimeInterval = 90
    private(set) var ejercicio: String?
    /// Llegó a cero: se muestra "¡A la próxima serie!" en verde durante 2 s.
    private(set) var terminado = false
    /// Cambia en cada ajuste de ±15 (para el háptico).
    private(set) var ajustes = 0

    @ObservationIgnored private var tarea: Task<Void, Never>?

    var activo: Bool { fin != nil }

    func restante(a fecha: Date) -> TimeInterval {
        guard let fin else { return 0 }
        return max(0, fin.timeIntervalSince(fecha))
    }

    /// 90 s si el ejercicio no trae descanso o trae 0.
    func empezar(segundos: Int?, ejercicio: String?, yaPasaron: TimeInterval = 0) {
        let s = TimeInterval((segundos ?? 0) > 0 ? segundos! : 90)
        total = s
        fin = .now.addingTimeInterval(s - yaPasaron)
        self.ejercicio = ejercicio
        terminado = false
        programarFin()
    }

    func ajustar(_ delta: TimeInterval) {
        guard let actual = fin, !terminado else { return }
        let nuevo = max(Date.now, actual.addingTimeInterval(delta))
        fin = nuevo
        total = max(total, nuevo.timeIntervalSinceNow)
        ajustes += 1
        programarFin()
    }

    func saltar() {
        tarea?.cancel()
        withAnimation(.smooth) {
            fin = nil
            terminado = false
        }
    }

    private func programarFin() {
        tarea?.cancel()
        guard let fin else { return }
        tarea = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, fin.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.snappy) { self.terminado = true }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) {
                self.fin = nil
                self.terminado = false
            }
        }
    }
}

/// Lo que el cliente va cargando en la sesión de hoy (boceto: vive en memoria). Al cablear, esto lo respalda el outbox.
@MainActor @Observable
final class SesionEnCurso {
    struct ValoresSerie: Equatable {
        var reps = ""
        var kg = ""
        var rir: Int?
        var confirmada = false
    }

    enum Final: Equatable { case completo, completoSinDatos }

    /// Cuándo arrancó (con "Empezar entrenamiento" o con la primera serie).
    private(set) var inicio: Date?
    private var series: [String: [Int: ValoresSerie]] = [:]
    private var finales: [String: Final] = [:]

    func valores(_ ejercicioId: String, serie: Int) -> ValoresSerie {
        series[ejercicioId]?[serie] ?? ValoresSerie()
    }

    func guardar(_ v: ValoresSerie, ejercicioId: String, serie: Int) {
        series[ejercicioId, default: [:]][serie] = v
        if v.confirmada, inicio == nil { inicio = .now }
    }

    func confirmadas(_ ejercicioId: String) -> Int {
        series[ejercicioId]?.values.filter(\.confirmada).count ?? 0
    }

    func final(_ ejercicioId: String) -> Final? { finales[ejercicioId] }

    func terminar(_ ejercicioId: String, _ f: Final?) { finales[ejercicioId] = f }

    func empezar() { if inicio == nil { inicio = .now } }

    func reiniciar() {
        inicio = nil
        series = [:]
        finales = [:]
    }
}
