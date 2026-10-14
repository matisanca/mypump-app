import Foundation
import HealthKit

/// Siembra en la Salud del simulador 62 días de datos sintéticos, con lo que más le cuesta a la paridad: muestras que
/// cruzan la medianoche (HealthKit las reparte entre días en los agregados), horas con fracciones de milisegundo (el
/// ISO del plugin redondea), más de 5000 lecturas de FC en la semana (la ventana se parte), lecturas justo en el borde de
/// las ventanas, noches con etapas, despierto, solo "en cama" y siestas, HRV de noche, de madrugada y de día, pesadas a
/// la misma hora y entrenos con y sin energía o distancia. Todo sale de una semilla: dos corridas siembran lo mismo.
///
/// HealthKit no deja que otra app escriba minutos de ejercicio ni temperatura de muñeca: esos dos se comparan vacíos (los
/// cubren los vectores). Tampoco se pueden sembrar dos fuentes desde una sola app: la elección de fuente también la
/// cubren los vectores.
enum Sembrador {
    static let cantidades: [HKQuantityTypeIdentifier] = [
        .stepCount, .activeEnergyBurned, .restingHeartRate, .heartRate, .heartRateVariabilitySDNN, .bodyMass, .respiratoryRate,
        .oxygenSaturation, .bodyFatPercentage, .distanceWalkingRunning, .flightsClimbed, .basalEnergyBurned, .bodyTemperature,
        .bloodGlucose,
    ]

    static var escritura: Set<HKSampleType> {
        var s = Set<HKSampleType>(cantidades.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        s.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        s.insert(HKObjectType.categoryType(forIdentifier: .mindfulSession)!)
        s.insert(HKObjectType.workoutType())
        return s
    }

    /// Todo lo que lee el bridge (más lo sembrado).
    static var lectura: Set<HKObjectType> {
        var s = Set<HKObjectType>(escritura)
        for id in [HKQuantityTypeIdentifier.appleExerciseTime, .appleSleepingWristTemperature] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) }
        }
        return s
    }

    /// Borra lo que sembró este banco antes (solo lo de esta app).
    static func borrar(_ store: HKHealthStore) async throws -> Int {
        var n = 0
        let deEsteBanco = HKQuery.predicateForObjects(from: HKSource.default())
        for t in escritura {
            n += try await store.deleteObjects(of: t, predicate: deEsteBanco)
        }
        return n
    }

    struct PRNG {
        var a: UInt32
        mutating func siguiente() -> Double {
            a &+= 0x6D2B_79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
        mutating func entre(_ lo: Double, _ hi: Double, _ dec: Int = 0) -> Double {
            let p = pow(10, Double(dec))
            return ((lo + siguiente() * (hi - lo)) * p).rounded() / p
        }
    }

    static func sembrar(_ store: HKHealthStore, ahora: Date, semilla: UInt32 = 2026) async throws -> Int {
        var r = PRNG(a: semilla)
        let cal = Calendar.current
        let hoy = cal.startOfDay(for: ahora)
        /// `dia` días antes de hoy, a las h:m (los minutos pueden pasar de 59: se suman) y `s` segundos con fracción.
        func t(_ dia: Int, _ h: Int, _ m: Int = 0, _ s: Double = 0) -> Date {
            let base = cal.date(byAdding: .day, value: -dia, to: hoy)!
            return cal.date(byAdding: .minute, value: h * 60 + m, to: base)!.addingTimeInterval(s)
        }
        func q(_ id: HKQuantityTypeIdentifier, _ unidad: HKUnit, _ v: Double, _ ini: Date, _ fin: Date? = nil) -> HKQuantitySample? {
            let f = fin ?? ini
            guard f <= ahora, let tipo = HKObjectType.quantityType(forIdentifier: id) else { return nil }
            return HKQuantitySample(type: tipo, quantity: HKQuantity(unit: unidad, doubleValue: v), start: ini, end: f)
        }
        func sueno(_ v: HKCategoryValueSleepAnalysis, _ ini: Date, _ fin: Date) -> HKCategorySample? {
            guard fin <= ahora else { return nil }
            return HKCategorySample(type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, value: v.rawValue, start: ini, end: fin)
        }
        let lpm = HKUnit.count().unitDivided(by: .minute())
        var objetos: [HKObject] = []
        func sumar(_ x: HKObject?) { if let x { objetos.append(x) } }

        for d in stride(from: 61, through: 0, by: -1) {
            // Pasos: uno que cruza la medianoche (salvo hoy) y uno con fracción de ms.
            sumar(q(.stepCount, .count(), r.entre(800, 2500), t(d, 8, 0, 0.000_4), t(d, 8, 30)))
            sumar(q(.stepCount, .count(), r.entre(2000, 6000), t(d, 12), t(d, 13)))
            if d > 0 { sumar(q(.stepCount, .count(), 600, t(d, 23, 50), t(d - 1, 0, 20))) }
            sumar(q(.activeEnergyBurned, .kilocalorie(), r.entre(120, 380, 3), t(d, 9), t(d, 10)))
            sumar(q(.activeEnergyBurned, .kilocalorie(), r.entre(40, 200, 2), t(d, 18), t(d, 19, 15)))
            sumar(q(.restingHeartRate, lpm, r.entre(48, 60), t(d, 4)))
            if d % 4 == 0 { sumar(q(.restingHeartRate, lpm, r.entre(50, 62, 1), t(d, 5, 30))) }
            sumar(q(.bodyMass, .gramUnit(with: .kilo), r.entre(81, 83, 2), t(d, 7, 45)))
            if d % 5 == 0 {   // dos pesadas a la misma hora: gana la última que devuelve HealthKit
                sumar(q(.bodyMass, .gramUnit(with: .kilo), 82.15, t(d, 20)))
                sumar(q(.bodyMass, .gramUnit(with: .kilo), 82.35, t(d, 20)))
            }
            sumar(q(.distanceWalkingRunning, .meter(), r.entre(500, 4000, 1), t(d, 9), t(d, 9, 40)))
            sumar(q(.distanceWalkingRunning, .meter(), r.entre(200, 1500, 3), t(d, 17), t(d, 17, 20)))
            sumar(q(.flightsClimbed, .count(), r.entre(1, 8), t(d, 10), t(d, 10, 5)))
            for k in 0..<4 { sumar(q(.basalEnergyBurned, .kilocalorie(), r.entre(400, 470, 3), t(d, k * 6), t(d, k * 6 + 5, 59))) }
            if d % 3 == 0 { sumar(q(.bodyFatPercentage, .percent(), r.entre(0.14, 0.2, 3), t(d, 7, 46))) }
            if d % 4 == 1 { sumar(q(.bodyTemperature, .degreeCelsius(), r.entre(36.1, 37.2, 2), t(d, 8, 30))) }
            if d % 6 == 2 { sumar(q(.bloodGlucose, HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)), r.entre(80, 110, 1), t(d, 8, 5))) }
            for k in 0..<3 { sumar(q(.respiratoryRate, lpm, r.entre(12, 17, 1), t(d, 1 + k, 20))) }
            for k in 0..<2 { sumar(q(.oxygenSaturation, .percent(), r.entre(0.93, 1, 2), t(d, 2 + k, 45))) }
            // HRV: de noche, en el borde del despertar, de madrugada fuera del sueño y de día.
            sumar(q(.heartRateVariabilitySDNN, .secondUnit(with: .milli), r.entre(35, 70, 3), t(d, 2, 10)))
            sumar(q(.heartRateVariabilitySDNN, .secondUnit(with: .milli), r.entre(35, 70, 3), t(d, 3, 30, 0.000_6)))
            sumar(q(.heartRateVariabilitySDNN, .secondUnit(with: .milli), r.entre(35, 70, 3), t(d, 6, 50)))
            if d % 2 == 0 { sumar(q(.heartRateVariabilitySDNN, .secondUnit(with: .milli), r.entre(25, 45, 2), t(d, 9, 15))) }
            sumar(q(.heartRateVariabilitySDNN, .secondUnit(with: .milli), r.entre(20, 40, 2), t(d, 15)))
            // FC: cada 2 min la última semana (más de 5000 en la ventana de 7 días), cada 10 antes.
            let paso = d <= 8 ? 2 : 10
            for m in stride(from: 0, to: 24 * 60, by: paso) { sumar(q(.heartRate, lpm, r.entre(52, 118, 1), t(d, 0, m))) }
            // Meditación con segundos y fracciones (el valor es la duración en minutos).
            if d % 2 == 1 {
                let ini = t(d, 22, 0, 0.123_4)
                sumar(HKCategorySample(type: HKObjectType.categoryType(forIdentifier: .mindfulSession)!, value: 0, start: ini,
                                       end: ini.addingTimeInterval(r.entre(180, 900, 4))))
            }
            // La noche que termina el día d (empieza el d+1 a la noche).
            let acuesta = t(d + 1, 23, Int(r.entre(0, 50)))
            switch d % 7 {
            case 3:   // solo "en cama" (el iPhone sin reloj): estimado al 90 %
                sumar(sueno(.inBed, acuesta, t(d, 7, 10)))
            case 5:   // "dormido" sin etapas
                sumar(sueno(.asleepUnspecified, acuesta, t(d, 6, 40)))
            default:
                sumar(sueno(.inBed, acuesta.addingTimeInterval(-600), t(d, 7, 0)))
                var c = acuesta
                for (v, mins) in [(HKCategoryValueSleepAnalysis.asleepCore, 50.0), (.asleepDeep, 60), (.asleepREM, 25), (.awake, 9),
                                  (.asleepCore, 140.5), (.asleepREM, 40), (.asleepCore, 75), (.awake, 6)] {
                    let f = c.addingTimeInterval(mins * 60 + r.entre(0, 600))
                    sumar(sueno(v, c, f))
                    c = f
                }
            }
            if d % 9 == 4 { sumar(sueno(.asleepUnspecified, t(d, 15, 10), t(d, 15, 52))) }   // siesta
        }
        // Entrenos con FC propia adentro.
        let entrenos: [(HKWorkoutActivityType, Int, Int, Double, Double?, Double?)] = [
            (.running, 2, 7, 1800.9, 300.5, 5000), (.traditionalStrengthTraining, 1, 18, 3725.4, 412.49, nil), (.cycling, 4, 7, 2700, nil, 12_345.6),
            (.yoga, 6, 20, 2400, nil, nil), (.soccer, 12, 20, 3000.5, 640, 6120.4), (.highIntensityIntervalTraining, 33, 8, 1500.25, 280, nil),
            (.walking, 45, 10, 3300, 150.75, 4321),
        ]
        for (tipo, d, h, dur, kcal, dist) in entrenos {
            let ini = t(d, h, 0, 0.000_3)
            let fin = ini.addingTimeInterval(dur)
            sumar(HKWorkout(activityType: tipo, start: ini, end: fin, duration: dur,
                            totalEnergyBurned: kcal.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) },
                            totalDistance: dist.map { HKQuantity(unit: .meter(), doubleValue: $0) }, metadata: nil))
            for s in stride(from: 0.0, through: dur, by: 5) { sumar(q(.heartRate, lpm, r.entre(110, 175, 1), ini.addingTimeInterval(s))) }
        }
        // Justo en la medianoche de hace 7 días (el borde de la ventana) y de hace 5 (la costura del historial).
        sumar(q(.stepCount, .count(), 333, t(7, 0), t(7, 0, 5)))
        sumar(q(.stepCount, .count(), 444, t(5, 0), t(5, 0, 5)))

        for i in stride(from: 0, to: objetos.count, by: 2000) {
            try await store.save(Array(objetos[i..<min(i + 2000, objetos.count)]))
        }
        return objetos.count
    }
}
