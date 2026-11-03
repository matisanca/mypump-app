import Foundation
@preconcurrency import HealthKit
import MyPumpReloj

/// La FC y las calorías en vivo con `HKWorkoutSession` + `HKLiveWorkoutBuilder`. NO se guarda nada en Salud (decisión de
/// Mati): al terminar, el builder se descarta (`discardWorkout`) en vez de `finishWorkout`. La sesión de entreno además
/// deja la app viva con la muñeca baja (el descanso sigue vibrando).
///
/// Si no hay permiso o HealthKit no está, el entreno anda igual sin FC ni calorías.
@MainActor
final class EntrenoSalud: NSObject {
    var alMedir: ((SaludEntreno) -> Void)?

    private let tienda = HKHealthStore()
    private var sesion: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var medida = SaludEntreno()
    private var sumaFC = 0.0, muestrasFC = 0.0

    private static let fc = HKQuantityType(.heartRate)
    private static let energia = HKQuantityType(.activeEnergyBurned)

    /// Arranca la sesión de entreno (una sola vez por entreno).
    func empezar() {
        guard sesion == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let aCompartir: Set<HKSampleType> = [HKObjectType.workoutType()]
        let aLeer: Set<HKObjectType> = [Self.fc, Self.energia]
        tienda.requestAuthorization(toShare: aCompartir, read: aLeer) { [weak self] ok, _ in
            guard ok else { return }
            Task { @MainActor in self?.abrir() }
        }
    }

    private func abrir() {
        guard sesion == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        guard let s = try? HKWorkoutSession(healthStore: tienda, configuration: config) else { return }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: tienda, workoutConfiguration: config)
        b.delegate = self
        sesion = s
        builder = b
        medida = SaludEntreno()
        sumaFC = 0; muestrasFC = 0
        let inicio = Date()
        s.startActivity(with: inicio)
        b.beginCollection(withStart: inicio) { _, _ in }
    }

    /// Termina la sesión y DESCARTA el entreno (no va a Salud).
    func terminar() {
        guard let s = sesion, let b = builder else { return }
        s.end()
        b.endCollection(withEnd: Date()) { _, _ in
            b.discardWorkout()
        }
        sesion = nil
        builder = nil
    }

    fileprivate func actualizar(_ estadisticas: [HKQuantityType: HKStatistics]) {
        if let e = estadisticas[Self.fc] {
            let unidad = HKUnit.count().unitDivided(by: .minute())
            medida.fcActual = e.mostRecentQuantity()?.doubleValue(for: unidad)
            medida.fcMedia = e.averageQuantity()?.doubleValue(for: unidad)
            medida.fcMaxima = e.maximumQuantity()?.doubleValue(for: unidad)
        }
        if let e = estadisticas[Self.energia] {
            medida.kcal = e.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        alMedir?(medida)
    }
}

extension EntrenoSalud: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var e: [HKQuantityType: HKStatistics] = [:]
        for t in collectedTypes {
            if let q = t as? HKQuantityType, let s = workoutBuilder.statistics(for: q) { e[q] = s }
        }
        let estadisticas = e
        Task { @MainActor in self.actualizar(estadisticas) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
