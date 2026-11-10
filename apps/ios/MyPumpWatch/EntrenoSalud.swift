import Foundation
@preconcurrency import HealthKit
import MyPumpReloj

/// La FC y las calorías en vivo con `HKWorkoutSession` + `HKLiveWorkoutBuilder`. Al cerrarse, el entreno se GUARDA en
/// Salud/Fitness si `SesionReloj.cierreSalud` dice que fue un entreno de verdad; si no (sin series, la demo, sin permiso),
/// se descarta. La duración y las calorías son las que midió el builder: no se inventa ninguna muestra. El iPhone no lo
/// vuelve a ingerir (`PuenteSalud.bundleDelReloj`). La sesión de entreno además deja la app viva con la muñeca baja (el
/// descanso sigue vibrando).
///
/// Si no hay permiso o HealthKit no está, el entreno anda igual sin FC ni calorías, y no se guarda nada.
@MainActor
final class EntrenoSalud: NSObject {
    var alMedir: ((SaludEntreno) -> Void)?
    /// La sesión de entreno corre o se cortó: sin ella, con la muñeca baja el sistema suspende la app y los sensores.
    var alCambiarViva: ((Bool) -> Void)?
    /// Cómo cerrar lo medido si el sistema corta la sesión (otro entreno en el reloj, por ejemplo): lo hecho hasta ahí no se pierde.
    var alCortarse: (() -> CierreSalud)?

    private let tienda = HKHealthStore()
    private var sesion: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var medida = SaludEntreno()
    private var sumaFC = 0.0, muestrasFC = 0.0
    /// Las sesiones que se están cerrando, hasta que el sistema confirma que terminaron.
    private struct Cierre { let sesion: HKWorkoutSession; let builder: HKLiveWorkoutBuilder; let cierre: CierreSalud }
    private var cierres: [ObjectIdentifier: Cierre] = [:]
    /// El permiso se contesta en diferido: si en el medio se terminó el día, la sesión ya no se abre.
    private var quiereAbrir = false

    private static let fc = HKQuantityType(.heartRate)
    private static let energia = HKQuantityType(.activeEnergyBurned)

    /// Arranca la sesión de entreno (una sola vez por entreno).
    func empezar() {
        guard sesion == nil, HKHealthStore.isHealthDataAvailable() else { return }
        quiereAbrir = true
        let aCompartir: Set<HKSampleType> = [HKObjectType.workoutType()]
        let aLeer: Set<HKObjectType> = [Self.fc, Self.energia]
        // HealthKit llama a estas closures en su cola. El SDK ya las declara `@Sendable` (no heredan el MainActor); se
        // escribe igual para que quede a la vista.
        tienda.requestAuthorization(toShare: aCompartir, read: aLeer) { @Sendable [weak self] ok, _ in
            guard ok else { return }
            Task { @MainActor in self?.abrir() }
        }
    }

    private func abrir() {
        guard sesion == nil, quiereAbrir else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        guard let s = try? HKWorkoutSession(healthStore: tienda, configuration: config) else { return }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: tienda, workoutConfiguration: config)
        b.delegate = self
        s.delegate = self
        sesion = s
        builder = b
        medida = SaludEntreno()
        sumaFC = 0; muestrasFC = 0
        let inicio = Date()
        s.startActivity(with: inicio)
        b.beginCollection(withStart: inicio) { @Sendable _, _ in }
    }

    /// Termina la sesión y la cierra según `cierre` (una sola vez: las llamadas siguientes no hacen nada).
    func terminar(_ cierre: CierreSalud) {
        quiereAbrir = false
        guard let s = sesion, let b = builder else { return }
        sesion = nil
        builder = nil
        cerrar(s, b, cierre)
        alCambiarViva?(false)
    }

    /// Apple pide esperar a que la sesión pase a `.ended` antes de cerrar el builder. Si el sistema no avisa (una sesión que
    /// nunca llegó a correr), a los 5 s se cierra igual, para no dejar un entreno abierto.
    private func cerrar(_ s: HKWorkoutSession, _ b: HKLiveWorkoutBuilder, _ cierre: CierreSalud) {
        let id = ObjectIdentifier(s)
        cierres[id] = Cierre(sesion: s, builder: b, cierre: cierre)
        s.delegate = self
        s.end()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.completar(id)
        }
    }

    private func completar(_ id: ObjectIdentifier) {
        guard let c = cierres.removeValue(forKey: id) else { return }
        let b = c.builder
        let fin: Date? = {
            // `requestAuthorization` da ok aunque lo nieguen: lo que vale es el estado de escritura.
            guard case .guardar(let ms) = c.cierre,
                  tienda.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return nil }
            let f = Date(timeIntervalSince1970: ms / 1000)
            if let inicio = b.startDate, f <= inicio { return nil }
            return f
        }()
        b.endCollection(withEnd: fin ?? Date()) { @Sendable ok, _ in
            guard ok, fin != nil else { b.discardWorkout(); return }
            // Si Salud no lo acepta el entreno sigue en MyPump: no se reintenta ni se le avisa al alumno.
            b.finishWorkout { @Sendable w, _ in if w == nil { b.discardWorkout() } }
        }
    }

    /// La sesión que el sistema guardó al cerrarse la app a mitad de un entreno. `seguir`: el día sigue en curso y se
    /// retoma la medición; si no, se cierra según `cierre` (no queda un entreno abierto).
    func recuperar(seguir: Bool, cierre: CierreSalud) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        tienda.recoverActiveWorkoutSession { @Sendable [weak self] s, _ in
            guard let s else { return }
            Task { @MainActor in self?.adoptar(s, seguir: seguir, cierre: cierre) }
        }
    }

    private func adoptar(_ s: HKWorkoutSession, seguir: Bool, cierre: CierreSalud) {
        let b = s.associatedWorkoutBuilder()
        if seguir, sesion == nil {
            b.delegate = self
            s.delegate = self
            sesion = s
            builder = b
            alCambiarViva?(s.state == .running)
            return
        }
        guard s !== sesion else { return }
        // Con el día en curso ya hay otra sesión midiendo: la recuperada se descarta para no dejar dos entrenos solapados.
        cerrar(s, b, seguir ? .descartar : cierre)
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

extension EntrenoSalud: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        let corre = toState == .running
        let cerro = toState == .ended || toState == .stopped
        let termino = toState == .ended
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            self.cambioSesion(workoutSession, corre: corre, cerro: cerro)
            if termino { self.completar(id) }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            self.cambioSesion(workoutSession, corre: false, cerro: true)
            self.completar(id)
        }
    }

    /// Solo la sesión vigente: la que cerró `terminar` ya no está (la guarda o la descarta `completar`). Si se cortó sola,
    /// se cierra lo medido y queda libre para volver a abrirse.
    fileprivate func cambioSesion(_ s: HKWorkoutSession, corre: Bool, cerro: Bool) {
        guard s === sesion else { return }
        if cerro {
            // Se cortó sola: se cierra de verdad para que `empezar` pueda abrir otra sin chocar con esta, y lo medido hasta
            // acá se guarda con la misma regla que un cierre normal (sin series confirmadas, se descarta).
            let b = builder
            sesion = nil
            builder = nil
            if let b { cerrar(s, b, alCortarse?() ?? .descartar) } else { s.end() }
        }
        alCambiarViva?(corre)
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
