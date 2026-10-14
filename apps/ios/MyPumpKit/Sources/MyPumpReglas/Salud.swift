import Foundation
import MyPumpModelos

// Salud de iPhone: lo que hace hoy public/js/healthkit-bridge.js con lo que le entrega el plugin
// @capgo/capacitor-health 8.9.3 (Health.swift), portado tal cual. Los vectores de
// scripts/nativa/vectores-salud.mjs corren el bridge real y la nativa tiene que dar lo mismo, registro por registro.
//
// Las horas se manejan como en la web: milisegundos desde 1970 (enteros guardados en Double, como un número de JS) y
// fechas locales con el calendario gregoriano en la zona del teléfono. Toda resta de tiempos se hace en ms, igual que
// el bridge, para que los redondeos den lo mismo hasta en el .5.

/// Las tablas del bridge (`AGG`, `SAMPLES`, `NUCLEO`), la fuente y la métrica de HRV del iPhone.
public enum PuenteSalud {
    /// `mypump_salud_diaria.fuente`. El motor desempata por fuente y el coach ve de dónde salió el dato.
    public static let fuente = "apple_health"
    /// HealthKit solo tiene SDNN; el motor le da menos peso que a un rMSSD.
    public static let metricaHRV = "sdnn"
    /// `readSamples` no pagina: si vuelven exactamente estas, se parte la ventana al medio.
    public static let limiteMuestras = 5000
    public static let loteSalud = 300
    public static let loteEntrenos = 200

    /// Camino A: `queryAggregated`, solo los tres que el plugin agrega sin rechazar.
    public struct Agregado: Sendable, Equatable {
        public let dataType: String
        public let tipo: String
        public let agregacion: String
    }

    public static let agregados: [Agregado] = [
        Agregado(dataType: "steps", tipo: "pasos", agregacion: "sum"),
        Agregado(dataType: "calories", tipo: "kcal_activas", agregacion: "sum"),
        Agregado(dataType: "restingHeartRate", tipo: "fc_reposo", agregacion: "average"),
    ]

    /// Cómo se colapsan las muestras de un día.
    public enum Como: String, Sendable { case suma, mediana, ultimo }

    /// Camino B: `readSamples` y agregación propia.
    public struct TipoMuestra: Sendable, Equatable {
        public let dataType: String
        public let tipo: String
        public let como: Como
        /// Se multiplica solo si el valor es ≤ 1 (SpO2 y grasa a veces vienen 0-1).
        public let escala: Double?
        /// Conversión fija de unidad (m → km).
        public let factor: Double?
        /// Un tipo que esta versión de iOS no conoce hace fallar el pedido de permisos entero.
        public let minIOS: Int?

        init(_ dataType: String, _ tipo: String, _ como: Como, escala: Double? = nil, factor: Double? = nil, minIOS: Int? = nil) {
            self.dataType = dataType; self.tipo = tipo; self.como = como; self.escala = escala; self.factor = factor; self.minIOS = minIOS
        }
    }

    /// El orden importa: es el de los registros que salen. En Android cambian `basalCalories` (mediana) y faltan los
    /// `soloIOS` (exerciseTime, oxygenSaturation, appleSleepingWristTemperature, bodyTemperature, bloodGlucose,
    /// mindfulness); acá es iPhone.
    public static let muestras: [TipoMuestra] = [
        TipoMuestra("exerciseTime", "actividad_min", .suma),
        TipoMuestra("respiratoryRate", "respiracion_rpm", .mediana),
        TipoMuestra("oxygenSaturation", "spo2_pct", .mediana, escala: 100),
        TipoMuestra("appleSleepingWristTemperature", "temp_muneca_c", .mediana, minIOS: 16),
        TipoMuestra("bodyFat", "grasa_pct", .mediana, escala: 100),
        TipoMuestra("weight", "peso_kg", .ultimo),
        TipoMuestra("distance", "distancia_km", .suma, factor: 0.001),
        TipoMuestra("flightsClimbed", "pisos", .suma),
        TipoMuestra("basalCalories", "kcal_basales", .suma),
        TipoMuestra("bodyTemperature", "temp_corporal_c", .mediana),
        TipoMuestra("bloodGlucose", "glucosa_mg_dl", .mediana),
        TipoMuestra("mindfulness", "mindful_min", .suma),
        TipoMuestra("heartRate", "fc_media", .mediana),
    ]

    /// Lo que sostiene el score de recuperación: va en la primera tanda de permisos y sola.
    public static let nucleo = ["steps", "calories", "restingHeartRate", "sleep", "heartRateVariability", "weight"]

    /// `soportado(m)`: con `iosMayor` 0 (desconocido) se pide igual, como la web.
    public static func soportado(_ m: TipoMuestra, iosMayor: Int) -> Bool {
        guard let min = m.minIOS else { return true }
        return iosMayor == 0 || iosMayor >= min
    }

    /// `tiposLectura()`: todo lo que se lee, en el orden del bridge. 'workouts' es el permiso de los entrenamientos.
    public static func tiposLectura(iosMayor: Int) -> [String] {
        agregados.map(\.dataType) + muestras.filter { soportado($0, iosMayor: iosMayor) }.map(\.dataType)
            + ["sleep", "heartRateVariability", "workouts"]
    }

    /// La tanda secundaria: todo lo que no es núcleo.
    public static func resto(iosMayor: Int) -> [String] {
        tiposLectura(iosMayor: iosMayor).filter { !nucleo.contains($0) }
    }
}

// MARK: - Lo que entra (lo que el plugin le entrega al bridge)

/// Una muestra de `readSamples`. Las horas, redondeadas al ms (el ISO con milisegundos que el plugin le pasa a la web).
public struct MuestraSalud: Sendable, Equatable {
    public var inicio: Double
    public var fin: Double
    /// En la unidad del plugin (`defaultUnit`): HRV en ms, SpO2 y grasa en 0-1, distancia en m, temperatura en °C.
    /// En el sueño y la meditación, la duración en minutos.
    public var valor: Double
    /// `sourceId`: el bundle id de la app o el reloj que la escribió.
    public var fuenteId: String
    /// `sourceName`.
    public var fuenteNombre: String
    /// Solo sueño: el `sleepState` del plugin (inBed, asleep, awake, light, deep, rem) o nil si el valor no lo conoce.
    public var estadoSueno: String?

    public init(inicio: Double, fin: Double, valor: Double, fuenteId: String, fuenteNombre: String, estadoSueno: String? = nil) {
        self.inicio = inicio; self.fin = fin; self.valor = valor; self.fuenteId = fuenteId; self.fuenteNombre = fuenteNombre
        self.estadoSueno = estadoSueno
    }
}

/// Un balde diario de `queryAggregated` (solo los que tienen valor).
public struct BaldeDiario: Sendable, Equatable {
    public var inicio: Double
    public var valor: Double
    public init(inicio: Double, valor: Double) { self.inicio = inicio; self.valor = valor }
}

/// Un entrenamiento de `queryWorkouts` (`workoutToPayload`).
public struct EntrenoCrudo: Sendable, Equatable {
    /// `workoutType` del plugin ("running", "strengthTraining", "other"…).
    public var tipo: String
    /// Segundos ENTEROS: el plugin hace `Int(workout.duration)`.
    public var duracion: Double
    public var inicio: Double
    public var fin: Double
    /// kcal (`totalEnergyBurned`).
    public var kcal: Double?
    /// Metros (`totalDistance`).
    public var distancia: Double?

    public init(tipo: String, duracion: Double, inicio: Double, fin: Double, kcal: Double? = nil, distancia: Double? = nil) {
        self.tipo = tipo; self.duracion = duracion; self.inicio = inicio; self.fin = fin; self.kcal = kcal; self.distancia = distancia
    }
}

// MARK: - Lo que sale

/// Una fila para `mypump_ingest_salud`.
public struct RegistroSalud: Sendable, Equatable {
    public var fecha: String
    public var tipo: String
    public var valor: Double
    public var fuente: String
    public var detalle: JSONValue?

    public init(fecha: String, tipo: String, valor: Double, fuente: String = PuenteSalud.fuente, detalle: JSONValue? = nil) {
        self.fecha = fecha; self.tipo = tipo; self.valor = valor; self.fuente = fuente; self.detalle = detalle
    }

    /// Sin `detalle` la clave NO va: la base guarda `NULL` si falta, y un `null` explícito quedaría como JSON null.
    public var json: JSONValue {
        var o: [String: JSONValue] = ["fecha": .texto(fecha), "tipo": .texto(tipo), "valor": .numero(valor), "fuente": .texto(fuente)]
        if let detalle { o["detalle"] = detalle }
        return .objeto(o)
    }
}

/// Una fila para `mypump_ingest_entrenos`. Van las nueve claves siempre, con null donde no hay dato (como la web).
public struct EntrenoSalud: Sendable, Equatable {
    public var inicio: String
    public var fin: String?
    public var tipo: String
    public var duracionMin: Double?
    public var kcal: Double?
    public var distanciaKm: Double?
    public var fcMedia: Double?
    public var fcMax: Double?
    public var fuente: String

    public var json: JSONValue {
        func n(_ x: Double?) -> JSONValue { x.map(JSONValue.numero) ?? .null }
        return .objeto(["inicio": .texto(inicio), "fin": fin.map(JSONValue.texto) ?? .null, "tipo": .texto(tipo),
                        "duracion_min": n(duracionMin), "kcal": n(kcal), "distancia_km": n(distanciaKm),
                        "fc_media": n(fcMedia), "fc_max": n(fcMax), "fuente": .texto(fuente)])
    }
}

// MARK: - Fechas y horas locales, como el `Date` de JS

/// Las cuentas de calendario que el bridge hace con `Date` de JS: gregoriano, en la zona del teléfono (nunca el
/// calendario que el cliente eligió en Ajustes: JS siempre usa el gregoriano).
public struct RelojLocal: Sendable {
    public let calendario: Calendar

    public init(zona: TimeZone = .current) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        calendario = c
    }

    public static func fecha(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }
    public static func ms(_ d: Date) -> Double { (d.timeIntervalSince1970 * 1000).rounded() }

    /// `ymd(d)`: la fecha local "YYYY-MM-DD".
    public func ymd(_ ms: Double) -> String {
        let c = calendario.dateComponents([.year, .month, .day], from: Self.fecha(ms))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `getHours()` y `getMinutes()`.
    public func horaYMinutos(_ ms: Double) -> (hora: Int, minutos: Int) {
        let c = calendario.dateComponents([.hour, .minute], from: Self.fecha(ms))
        return (c.hour ?? 0, c.minute ?? 0)
    }

    /// El comienzo del día local `y-m-d` (si la medianoche no existe por un cambio de hora, el primer instante).
    private func inicioDelDia(_ y: Int, _ m: Int, _ d: Int, hora: Int = 0) -> Double {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        let mediodia = calendario.date(from: c) ?? Date(timeIntervalSince1970: 0)
        if hora == 12 { return Self.ms(mediodia) }
        return Self.ms(calendario.startOfDay(for: mediodia))
    }

    /// `haceNDias(n)`: la medianoche local de hace `n` días (0 = hoy).
    public func medianoche(haceDias n: Int, desde ahora: Double) -> Double {
        let c = calendario.dateComponents([.year, .month, .day], from: Self.fecha(ahora))
        return inicioDelDia(c.year ?? 1970, c.month ?? 1, (c.day ?? 1) - n)
    }

    /// Desde dónde se pide el sueño: el mediodía local del día anterior a `ms` (la noche que se imputa al día del
    /// borde empezó la tarde anterior).
    public func mediodiaDelDiaAnterior(_ ms: Double) -> Double {
        let c = calendario.dateComponents([.year, .month, .day], from: Self.fecha(ms))
        return inicioDelDia(c.year ?? 1970, c.month ?? 1, (c.day ?? 1) - 1, hora: 12)
    }

    /// `new Date(ms).toISOString()`.
    public static func iso(_ ms: Double) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let segundos = (ms / 1000).rounded(.down)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: segundos))
        let resto = Int(ms - segundos * 1000)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0, resto)
    }

    /// `Date.parse` de un ISO: el de `marcarSync` ("…T13:59:00.000Z") o un timestamptz de PostgREST
    /// ("2026-10-14 13:59:00.123456+00:00", con microsegundos, que ISO8601DateFormatter no lee).
    public static func desdeISO(_ texto: String) -> Double? {
        var s = texto.replacingOccurrences(of: " ", with: "T")
        if let punto = s.firstIndex(of: ".") {
            let fin = s[s.index(after: punto)...].firstIndex { !$0.isNumber } ?? s.endIndex
            let fraccion = s[s.index(after: punto)..<fin]
            s.replaceSubrange(punto..<fin, with: "." + String((fraccion + "000").prefix(3)))
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return ms(d) }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s).map(ms)
    }
}
