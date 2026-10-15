import Foundation
import HealthKit
import MyPumpDatos
import MyPumpReglas

/// HealthKit consultado EXACTAMENTE como lo consulta hoy el plugin de la app Capacitor (@capgo/capacitor-health 8.9.3,
/// ios/Sources/HealthPlugin/Health.swift): los mismos identificadores, la misma `defaultUnit`, los mismos predicados
/// (`options: []` para leer muestras y entrenos, `.strictStartDate` para los agregados), el ancla a la medianoche local,
/// el orden, el límite, `Int(workout.duration)` y las horas redondeadas al milisegundo con el mismo ISO8601DateFormatter.
/// Lo que hace el bridge con eso vive en MyPumpReglas (PuenteSalud) y se prueba con los vectores de la web.
///
/// Solo LEE: `requestAuthorization(toShare: [])` siempre. El kit la encuentra por nombre (`ModeloSalud.fuenteDelSistema`).
@objc(FuenteHealthKit)
final class FuenteHealthKit: NSObject, FuenteSalud, @unchecked Sendable {
    private let store = HKHealthStore()
    let iosMayor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    override init() { super.init() }

    // MARK: - Tipos (HealthDataType del plugin)

    enum Tipo {
        case cantidad(HKQuantityTypeIdentifier, HKUnit)
        case sueno
        case meditacion
    }

    /// `quantityType()` / `sampleType()` / `defaultUnit` del plugin, para los tipos que pide el bridge. `totalCalories`,
    /// `bloodPressure`, `height`, `distanceCycling` y `basalBodyTemperature` no se piden nunca.
    static func tipo(_ dataType: String) throws -> Tipo {
        let lpm = HKUnit.count().unitDivided(by: .minute())
        switch dataType {
        case "steps": return .cantidad(.stepCount, .count())
        case "distance": return .cantidad(.distanceWalkingRunning, .meter())
        case "calories": return .cantidad(.activeEnergyBurned, .kilocalorie())
        case "heartRate": return .cantidad(.heartRate, lpm)
        case "restingHeartRate": return .cantidad(.restingHeartRate, lpm)
        case "weight": return .cantidad(.bodyMass, .gramUnit(with: .kilo))
        case "respiratoryRate": return .cantidad(.respiratoryRate, lpm)
        case "oxygenSaturation": return .cantidad(.oxygenSaturation, .percent())
        case "heartRateVariability": return .cantidad(.heartRateVariabilitySDNN, .secondUnit(with: .milli))
        case "bloodGlucose": return .cantidad(.bloodGlucose, HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)))
        case "bodyTemperature": return .cantidad(.bodyTemperature, .degreeCelsius())
        case "flightsClimbed": return .cantidad(.flightsClimbed, .count())
        case "exerciseTime": return .cantidad(.appleExerciseTime, .minute())
        case "bodyFat": return .cantidad(.bodyFatPercentage, .percent())
        case "appleSleepingWristTemperature": return .cantidad(.appleSleepingWristTemperature, .degreeCelsius())
        case "basalCalories": return .cantidad(.basalEnergyBurned, .kilocalorie())
        case "sleep": return .sueno
        case "mindfulness": return .meditacion
        default: throw ErrorFuenteSalud("Unsupported health data type: \(dataType).")
        }
    }

    static func tipoDeMuestra(_ t: Tipo, _ dataType: String) throws -> HKSampleType {
        switch t {
        case .cantidad(let id, _):
            guard let q = HKObjectType.quantityType(forIdentifier: id) else {
                throw ErrorFuenteSalud("The health data type \(dataType) is not available on this device.")
            }
            return q
        case .sueno: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        case .meditacion: return HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        }
    }

    /// `parseTypesWithWorkouts` + `readAuthorizationObjectTypes`: un tipo desconocido tira el pedido entero.
    private func objetosDeLectura(_ tipos: [String]) throws -> Set<HKObjectType> {
        var set = Set<HKObjectType>()
        for t in tipos {
            if t == "workouts" { set.insert(HKObjectType.workoutType()); continue }
            set.insert(try Self.tipoDeMuestra(try Self.tipo(t), t))
        }
        return set
    }

    // MARK: - Permisos

    func disponible() async -> Bool { HKHealthStore.isHealthDataAvailable() }

    func pedirLectura(_ tipos: [String]) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw ErrorFuenteSalud("Health data is not available on this device.") }
        let lectura = try objetosDeLectura(tipos)
        let store = self.store
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: lectura) { ok, error in
                if let error { c.resume(throwing: ErrorFuenteSalud(error.localizedDescription)) }
                else if ok { c.resume() }
                else { c.resume(throwing: ErrorFuenteSalud("Authorization request was not granted.")) }
            }
        }
    }

    /// `checkAuthorization`: `.unnecessary` = ya se preguntó (HealthKit NUNCA dice si el cliente dijo que sí).
    func permisos(_ tipos: [String]) async throws -> PermisosSalud {
        var preguntados: [String] = [], pendientes: [String] = []
        for t in tipos {
            let objetos: Set<HKObjectType>
            if t == "workouts" { objetos = [HKObjectType.workoutType()] }
            else {
                let tipo = try Self.tipo(t)   // desconocido: tira, como parseTypesWithWorkouts
                guard let s = try? Self.tipoDeMuestra(tipo, t) else { pendientes.append(t); continue }
                objetos = [s]
            }
            let estado = try? await store.statusForAuthorizationRequest(toShare: [], read: objetos)
            if estado == .unnecessary { preguntados.append(t) } else { pendientes.append(t) }
        }
        return PermisosSalud(preguntados: preguntados, pendientes: pendientes)
    }

    // MARK: - Fechas como las ve la web

    /// El ISO del plugin (`.withInternetDateTime, .withFractionalSeconds`) redondea al ms: se pasa por el mismo
    /// formateador para que la nativa vea la hora que vio la web (y no la de HealthKit con microsegundos).
    private static func ms(_ d: Date, _ f: ISO8601DateFormatter) -> Double {
        f.date(from: f.string(from: d)).map(RelojLocal.ms) ?? RelojLocal.ms(d)
    }

    /// Y al revés: la fecha que el plugin parsea del `toISOString()` del bridge.
    private static func fecha(_ ms: Double) -> Date {
        formateador().date(from: RelojLocal.iso(ms)) ?? RelojLocal.fecha(ms)
    }

    private static func formateador() -> ISO8601DateFormatter { Formateadores.isoConDecimales }

    // MARK: - Consultas

    /// `queryAggregated(bucket: 'day')`: HKStatisticsCollectionQuery, ancla en la medianoche local (Calendar.current
    /// del teléfono, como el plugin), un día por balde, `.strictStartDate`, solo los baldes con valor.
    func agregado(_ dataType: String, agregacion: String, desde: Double, hasta: Double) async throws -> [BaldeDiario] {
        let soportadas: [String: [String]] = ["steps": ["sum"], "distance": ["sum"], "calories": ["sum"],
                                              "heartRate": ["average", "min", "max"], "weight": ["average", "min", "max"],
                                              "restingHeartRate": ["average", "min", "max"]]
        if dataType == "sleep" { throw ErrorFuenteSalud("Aggregated queries are not supported for sleep data. Use readSamples instead.") }
        guard let ok = soportadas[dataType] else {
            throw ErrorFuenteSalud("Aggregated queries are not supported for \(dataType). Use readSamples instead.")
        }
        guard ok.contains(agregacion) else { throw ErrorFuenteSalud("Unsupported aggregation '\(agregacion)' for \(dataType).") }
        guard case .cantidad(let id, let unidad) = try Self.tipo(dataType), let tipo = HKObjectType.quantityType(forIdentifier: id) else {
            throw ErrorFuenteSalud("The health data type \(dataType) is not available on this device.")
        }
        let inicio = Self.fecha(desde), fin = Self.fecha(hasta)
        guard fin >= inicio else { throw ErrorFuenteSalud("endDate must be greater than or equal to startDate.") }
        let calendario = Calendar.current
        guard let ancla = calendario.date(from: calendario.dateComponents([.year, .month, .day], from: inicio)) else {
            throw ErrorFuenteSalud("Failed to create anchor date")
        }
        let opciones: HKStatisticsOptions = switch agregacion {
        case "average": .discreteAverage
        case "min": .discreteMin
        case "max": .discreteMax
        default: .cumulativeSum
        }
        let predicado = HKQuery.predicateForSamples(withStart: inicio, end: fin, options: .strictStartDate)
        let store = self.store
        return try await withCheckedThrowingContinuation { c in
            let q = HKStatisticsCollectionQuery(quantityType: tipo, quantitySamplePredicate: predicado, options: opciones, anchorDate: ancla,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, coleccion, error in
                if let error { c.resume(throwing: ErrorFuenteSalud(error.localizedDescription)); return }
                guard let coleccion else { c.resume(returning: []); return }
                let f = Self.formateador()
                var baldes: [BaldeDiario] = []
                coleccion.enumerateStatistics(from: inicio, to: fin) { e, _ in
                    let cantidad: HKQuantity? = switch agregacion {
                    case "average": e.averageQuantity()
                    case "min": e.minimumQuantity()
                    case "max": e.maximumQuantity()
                    default: e.sumQuantity()
                    }
                    if let v = cantidad?.doubleValue(for: unidad) { baldes.append(BaldeDiario(inicio: Self.ms(e.startDate, f), valor: v)) }
                }
                c.resume(returning: baldes)
            }
            store.execute(q)
        }
    }

    /// `readSamples(limit, ascending: true)`: HKSampleQuery con `predicateForSamples(options: [])` (toda muestra que se
    /// solape con la ventana), por fecha de inicio ascendente.
    func muestras(_ dataType: String, desde: Double, hasta: Double, limite: Int) async throws -> [MuestraSalud] {
        let tipo = try Self.tipo(dataType)
        let tipoMuestra = try Self.tipoDeMuestra(tipo, dataType)
        let inicio = Self.fecha(desde), fin = Self.fecha(hasta)
        guard fin >= inicio else { throw ErrorFuenteSalud("endDate must be greater than or equal to startDate.") }
        let predicado = HKQuery.predicateForSamples(withStart: inicio, end: fin, options: [])
        let orden = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let store = self.store
        return try await withCheckedThrowingContinuation { c in
            let q = HKSampleQuery(sampleType: tipoMuestra, predicate: predicado, limit: limite, sortDescriptors: [orden]) { _, muestras, error in
                if let error { c.resume(throwing: ErrorFuenteSalud(error.localizedDescription)); return }
                let f = Self.formateador()
                var out: [MuestraSalud] = []
                for s in muestras ?? [] {
                    let fuente = s.sourceRevision.source
                    let ini = Self.ms(s.startDate, f), finMs = Self.ms(s.endDate, f)
                    switch tipo {
                    case .cantidad(_, let unidad):
                        guard let q = s as? HKQuantitySample else { continue }
                        let v = q.quantity.doubleValue(for: unidad)
                        guard v.isFinite else { continue }   // readSamplePayload descarta lo no finito
                        out.append(MuestraSalud(inicio: ini, fin: finMs, valor: v, fuenteId: fuente.bundleIdentifier, fuenteNombre: fuente.name))
                    case .sueno, .meditacion:
                        guard let cat = s as? HKCategorySample else { continue }
                        let minutos = cat.endDate.timeIntervalSince(cat.startDate) / 60.0
                        let estado = tipo.esSueno ? Self.estadoSueno(cat.value) : nil
                        out.append(MuestraSalud(inicio: ini, fin: finMs, valor: minutos, fuenteId: fuente.bundleIdentifier, fuenteNombre: fuente.name,
                                                estadoSueno: estado))
                    }
                }
                c.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// `sleepStateFromValue`: los de iOS 16 (core, deep, REM) salen como light, deep y rem; uno desconocido, sin estado.
    static func estadoSueno(_ v: Int) -> String? {
        switch v {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: "inBed"
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: "asleep"
        case HKCategoryValueSleepAnalysis.awake.rawValue: "awake"
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: "light"
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: "deep"
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: "rem"
        default: nil
        }
    }

    /// `queryWorkouts({startDate, endDate})`: el bridge no pasa límite ni orden, así que son los 100 más nuevos.
    func entrenos(desde: Double, hasta: Double) async throws -> [EntrenoCrudo] {
        let inicio = Self.fecha(desde), fin = Self.fecha(hasta)
        guard fin >= inicio else { throw ErrorFuenteSalud("endDate must be greater than or equal to startDate.") }
        let predicado = HKQuery.predicateForSamples(withStart: inicio, end: fin, options: [])
        let orden = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let store = self.store
        return try await withCheckedThrowingContinuation { c in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicado, limit: 100, sortDescriptors: [orden]) { _, muestras, error in
                if let error { c.resume(throwing: ErrorFuenteSalud(error.localizedDescription)); return }
                let ws = (muestras as? [HKWorkout]) ?? []
                let f = Self.formateador()
                c.resume(returning: ws.map { w in
                    EntrenoCrudo(tipo: Self.tipoEntreno(w.workoutActivityType), duracion: Double(Int(w.duration)),
                                 inicio: Self.ms(w.startDate, f), fin: Self.ms(w.endDate, f),
                                 kcal: Self.energia(w), distancia: Self.distancia(w))
                })
            }
            store.execute(q)
        }
    }

    /// `workout.totalEnergyBurned` y `totalDistance`, como el plugin (deprecados en iOS 18 pero vigentes).
    private static func energia(_ w: HKWorkout) -> Double? { w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) }
    private static func distancia(_ w: HKWorkout) -> Double? { w.totalDistance?.doubleValue(for: .meter()) }

    /// `WorkoutType.fromHKWorkoutActivityType` del plugin, tal cual (lo que no está, "other").
    static func tipoEntreno(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: "running"
        case .cycling: "cycling"
        case .walking: "walking"
        case .swimming: "swimming"
        case .yoga: "yoga"
        case .traditionalStrengthTraining: "strengthTraining"
        case .hiking: "hiking"
        case .tennis: "tennis"
        case .basketball: "basketball"
        case .soccer: "soccer"
        case .americanFootball: "americanFootball"
        case .archery: "archery"
        case .australianFootball: "australianFootball"
        case .badminton: "badminton"
        case .barre: "barre"
        case .baseball: "baseball"
        case .bowling: "bowling"
        case .boxing: "boxing"
        case .climbing: "climbing"
        case .cooldown: "cooldown"
        case .coreTraining: "coreTraining"
        case .cricket: "cricket"
        case .crossCountrySkiing: "crossCountrySkiing"
        case .crossTraining: "crossTraining"
        case .curling: "curling"
        case .discSports: "discSports"
        case .downhillSkiing: "downhillSkiing"
        case .elliptical: "elliptical"
        case .equestrianSports: "equestrianSports"
        case .fencing: "fencing"
        case .fishing: "fishing"
        case .fitnessGaming: "fitnessGaming"
        case .flexibility: "flexibility"
        case .functionalStrengthTraining: "functionalStrengthTraining"
        case .golf: "golf"
        case .gymnastics: "gymnastics"
        case .handball: "handball"
        case .handCycling: "handCycling"
        case .highIntensityIntervalTraining: "highIntensityIntervalTraining"
        case .hockey: "hockey"
        case .hunting: "hunting"
        case .jumpRope: "jumpRope"
        case .kickboxing: "kickboxing"
        case .lacrosse: "lacrosse"
        case .martialArts: "martialArts"
        case .mindAndBody: "mindAndBody"
        case .mixedCardio: "mixedCardio"
        case .paddleSports: "paddleSports"
        case .pickleball: "pickleball"
        case .pilates: "pilates"
        case .play: "play"
        case .preparationAndRecovery: "preparationAndRecovery"
        case .racquetball: "racquetball"
        case .rowing: "rowing"
        case .rugby: "rugby"
        case .sailing: "sailing"
        case .skatingSports: "skatingSports"
        case .snowboarding: "snowboarding"
        case .snowSports: "snowSports"
        case .softball: "softball"
        case .squash: "squash"
        case .stairs: "stairs"
        case .stepTraining: "stepTraining"
        case .surfingSports: "surfingSports"
        case .tableTennis: "tableTennis"
        case .taiChi: "taiChi"
        case .trackAndField: "trackAndField"
        case .volleyball: "volleyball"
        case .waterFitness: "waterFitness"
        case .waterPolo: "waterPolo"
        case .waterSports: "waterSports"
        case .wheelchairRunPace: "wheelchairRunPace"
        case .wheelchairWalkPace: "wheelchairWalkPace"
        case .wrestling: "wrestling"
        case .cardioDance: "cardioDance"
        case .socialDance: "socialDance"
        case .transition: "transition"
        case .underwaterDiving: "underwaterDiving"
        // `.dance` (52) está deprecado desde iOS 14 pero el plugin lo nombra: un entreno viejo sale "dance".
        default: t.rawValue == 52 ? "dance" : "other"
        }
    }
}

private extension FuenteHealthKit.Tipo {
    var esSueno: Bool { if case .sueno = self { return true }; return false }
}
