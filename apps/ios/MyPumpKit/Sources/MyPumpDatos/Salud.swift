import Foundation
import MyPumpModelos
import MyPumpReglas

// Salud de iPhone, la parte que habla con HealthKit y con la base. HealthKit queda detrás de `FuenteSalud` (en la app,
// FuenteHealthKit; en los tests, un doble que reproduce lo que contestó el plugin), así todo esto se prueba sin
// teléfono.

/// Lo que el bridge le pide al plugin, con los mismos nombres de tipo (`dataType`) y las horas en ms. La
/// implementación de iPhone hace exactamente las consultas del plugin @capgo/capacitor-health 8.9.3 (Health.swift).
public protocol FuenteSalud: Sendable {
    /// La versión mayor de iOS (`iosMajor()`): decide qué tipos se pueden pedir.
    var iosMayor: Int { get }
    /// `isAvailable`: HKHealthStore.isHealthDataAvailable().
    func disponible() async -> Bool
    /// `requestAuthorization({read, write: []})`. Nunca escritura. Tira si un tipo no existe en este iOS.
    func pedirLectura(_ tipos: [String]) async throws
    /// `checkAuthorization`: qué tipos ya se preguntaron. HealthKit NUNCA dice si hay permiso de lectura.
    func permisos(_ tipos: [String]) async throws -> PermisosSalud
    /// `queryAggregated(bucket: 'day')`: HKStatisticsCollectionQuery anclada a la medianoche local, .strictStartDate.
    func agregado(_ dataType: String, agregacion: String, desde: Double, hasta: Double) async throws -> [BaldeDiario]
    /// `readSamples(limit, ascending: true)`: HKSampleQuery con el predicado sin límites estrictos.
    func muestras(_ dataType: String, desde: Double, hasta: Double, limite: Int) async throws -> [MuestraSalud]
    /// `queryWorkouts({startDate, endDate})`: límite 100, del más nuevo al más viejo.
    func entrenos(desde: Double, hasta: Double) async throws -> [EntrenoCrudo]
}

public struct PermisosSalud: Sendable, Equatable {
    /// Los tipos ya preguntados (le haya dicho el cliente que sí o que no).
    public let preguntados: [String]
    /// Los que falta preguntar (o que este iOS no tiene).
    public let pendientes: [String]
    public init(preguntados: [String], pendientes: [String]) { self.preguntados = preguntados; self.pendientes = pendientes }
}

/// Un error de la fuente con el texto que da el plugin (va al diagnóstico).
public struct ErrorFuenteSalud: Error, Sendable, Equatable, CustomStringConvertible {
    public let mensaje: String
    public init(_ mensaje: String) { self.mensaje = mensaje }
    public var description: String { mensaje }
}

// MARK: - Estado local (las claves `mypump_health_*` de la web)

/// Dónde vive el estado del sincronizador. Mismas claves y mismo formato que el localStorage de la web, así la
/// migración del almacenamiento viejo lo copia tal cual (NATIVA_CONTRATO §9).
public protocol AlmacenSalud: AnyObject, Sendable {
    func leer(_ clave: String) -> String?
    func escribir(_ clave: String, _ valor: String?)
}

public enum ClaveSalud {
    public static let conectado = "mypump_health_connected"        // "1"
    public static let ultimaSync = "mypump_health_last_sync"       // ISO de JS
    public static let denegado = "mypump_health_denegado"          // "1": la sospecha de "no llega nada"
    public static let rachaVacia = "mypump_health_racha_vacia"     // sincronizaciones vacías seguidas
    public static let historialHecho = "mypump_health_backfill_v1" // "1"
    public static let cursor = "mypump_health_backfill_off"        // {"off":20,"alcance":60} o "20" (formato viejo)
    public static let intento = "mypump_health_backfill_intento"   // ms del último reintento sin avance
    public static let diag = "mypump_health_diag"                  // último intento de conectar (JSON)
    public static let todas = [conectado, ultimaSync, denegado, rachaVacia, historialHecho, cursor, intento, diag]
}

/// En la app: UserDefaults (no es un secreto, y sobrevive a reinstalar igual que el localStorage de la web, que no).
public final class AlmacenSaludDefaults: AlmacenSalud, @unchecked Sendable {
    let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func leer(_ clave: String) -> String? { defaults.string(forKey: clave) }
    public func escribir(_ clave: String, _ valor: String?) {
        if let valor { defaults.set(valor, forKey: clave) } else { defaults.removeObject(forKey: clave) }
    }
}

/// Para los tests y las vistas previas.
public final class AlmacenSaludEnMemoria: AlmacenSalud, @unchecked Sendable {
    private var datos: [String: String]
    private let candado = NSLock()
    public init(_ datos: [String: String] = [:]) { self.datos = datos }
    public func leer(_ clave: String) -> String? { candado.withLock { datos[clave] } }
    public func escribir(_ clave: String, _ valor: String?) { candado.withLock { datos[clave] = valor } }
    public var todo: [String: String] { candado.withLock { datos } }
}

// MARK: - Resultados

/// `sync()`: `ok` es "corrí", no "se guardó". `errorIngesta` dice si el servidor rechazó lotes (sin él, 0 ingresados
/// es indistinguible de "no había nada nuevo").
public struct ResultadoSync: Sendable, Equatable {
    public let ok: Bool
    public let motivo: String?
    public let ingresados: Int
    public let entrenos: Int
    public let errorIngesta: String?
}

/// `backfill()`.
public struct ResultadoHistorial: Sendable, Equatable {
    public let ok: Bool
    public let saltado: Bool
    public let ingresados: Int
    public let ventanasFallidas: Int
    /// El veredicto "no llegó NADA", mirado al terminar (con los 60 días ya consultados).
    public var sinDatos: Bool
}

/// `connect()`. El historial sigue de fondo: `historial` es su tarea (la web devuelve la promesa).
public struct ResultadoConexion: Sendable {
    public let ok: Bool
    /// no_disponible | error_nativo
    public let motivo: String?
    public let detalle: String?
    public let preguntados: Int?
    public let total: Int
    public let sinDatos: Bool
    public let rechazados: [(tipo: String, error: String)]
    public let historial: Task<ResultadoHistorial, Never>?
}

/// `estado()`: lo que muestra la sección "Salud de Apple" de Mis datos.
public struct EstadoSalud: Sendable, Equatable {
    public let disponible: Bool
    public let conectado: Bool
    /// "No está llegando ningún dato" (deducido: HealthKit no informa el permiso de lectura).
    public let sinDatos: Bool
    /// Tipos ya preguntados, NO "permisos dados".
    public let preguntados: Int?
    public let total: Int
    public let pendientes: [String]
    public let errorEstado: String?
    public let ultimaSync: String?
    public let ios: Int
}

/// `diagnostico()`: qué trajo cada tipo y el error textual del que falló (la pantalla de 5 toques).
public struct DiagnosticoSalud: Sendable, Equatable {
    public struct Tipo: Sendable, Equatable {
        public let tipo: String
        public let dataType: String
        public let via: String
        public let n: Int
        public let primero: String?
        public let ultimo: String?
        public let error: String?
    }
    public struct NocheFuente: Sendable, Equatable {
        public let fecha: String
        /// fuente → estado → minutos
        public let fuentes: [String: [String: Int]]
    }
    public let disponible: Bool
    public let conToken: Bool
    public let errorIngesta: String?
    public let tipos: [Tipo]
    public let noches: [NocheFuente]
    public let errores: [String]
}

// MARK: - Recolección de una ventana (recolectar + recolectarEntrenos)

/// Las consultas del bridge para una ventana y su agregación, en el mismo orden: los tres agregados, las muestras de
/// cada tipo, el sueño (desde el mediodía anterior) y la HRV; los entrenos aparte, con la FC del entreno.
public struct RecolectorSalud: Sendable {
    public let fuente: any FuenteSalud
    public let reloj: RelojLocal

    public init(fuente: any FuenteSalud, reloj: RelojLocal) { self.fuente = fuente; self.reloj = reloj }

    /// Errores de lectura (el `__MYPUMP_DIAG` de la web): solo se juntan para el diagnóstico.
    public final class Errores: @unchecked Sendable {
        private var lista: [String] = []
        private let candado = NSLock()
        public init() {}
        func anotar(_ dataType: String, _ e: Error) { candado.withLock { lista.append("\(dataType): \(e)") } }
        public var todos: [String] { candado.withLock { lista } }
    }

    /// `leerMuestras`: si vuelven exactamente `limite`, quedaron más afuera: se parte la ventana al medio (hasta 4
    /// veces y si dura más de una hora) y se pegan las mitades sin repetir la muestra que cruza el corte.
    public func leer(_ dataType: String, desde: Double, hasta: Double, profundidad: Int = 0, errores: Errores? = nil) async -> [MuestraSalud] {
        let arr: [MuestraSalud]
        do {
            arr = try await fuente.muestras(dataType, desde: desde, hasta: hasta, limite: PuenteSalud.limiteMuestras)
        } catch {
            errores?.anotar(dataType, error)
            return []
        }
        if arr.count >= PuenteSalud.limiteMuestras && profundidad < 4 && hasta - desde > 3_600_000 {
            let medio = ((desde + hasta) / 2).rounded(.down)
            let a = await leer(dataType, desde: desde, hasta: medio, profundidad: profundidad + 1, errores: errores)
            let b = await leer(dataType, desde: medio, hasta: hasta, profundidad: profundidad + 1, errores: errores)
            return PuenteSalud.sinRepetidas(a, b)
        }
        return arr
    }

    /// `recolectar(desde, hasta)`.
    public func recolectar(desde: Double, hasta: Double, iosMayor: Int, errores: Errores? = nil) async -> [RegistroSalud] {
        var registros: [RegistroSalud] = []
        for a in PuenteSalud.agregados {
            do {
                let baldes = try await fuente.agregado(a.dataType, agregacion: a.agregacion, desde: desde, hasta: hasta)
                registros += PuenteSalud.agregados(baldes, tipo: a.tipo, reloj: reloj)
            } catch {
                errores?.anotar(a.dataType, error)
            }
        }
        for m in PuenteSalud.muestras where PuenteSalud.soportado(m, iosMayor: iosMayor) {
            let ms = await leer(m.dataType, desde: desde, hasta: hasta, errores: errores)
            registros += PuenteSalud.muestras(ms, de: m, reloj: reloj)
        }
        // El sueño se pide desde el mediodía anterior: la noche que se imputa al día del borde empezó la tarde de antes.
        // La del día anterior a la ventana queda partida y se descarta (fecha < corte) en vez de subirse a medias.
        let msSueno = await leer("sleep", desde: reloj.mediodiaDelDiaAnterior(desde), hasta: hasta, errores: errores)
        let sueno = PuenteSalud.procesarSueno(msSueno, reloj: reloj)
        let corte = reloj.ymd(desde)
        registros += sueno.filas.filter { $0.fecha >= corte }
        let noches = sueno.noches.filter { $0.fecha >= corte }
        let msHrv = await leer("heartRateVariability", desde: desde, hasta: hasta, errores: errores)
        registros += PuenteSalud.procesarHRV(msHrv, noches: noches, reloj: reloj)
        return registros
    }

    /// `recolectarEntrenos(desde, hasta)`. Si la consulta falla, no hay entrenos (la web hace lo mismo).
    public func entrenos(desde: Double, hasta: Double) async -> [EntrenoSalud] {
        let ws: [EntrenoCrudo]
        do { ws = try await fuente.entrenos(desde: desde, hasta: hasta) } catch { return [] }
        let fc = ws.isEmpty ? [] : await leer("heartRate", desde: desde, hasta: hasta)
        return PuenteSalud.entrenos(ws, fc: fc)
    }
}

// MARK: - Mi reloj (Oura, WHOOP)

extension ClienteRPC {
    /// `GET /api/wearables/disponibles`, sin auth: los proveedores con credenciales cargadas en el servidor. nil si no
    /// se pudo preguntar (sin red: no se muestra nada, es el fallo seguro).
    public func relojesDisponibles() async -> [String]? {
        var pedido = URLRequest(url: config.app.appendingPathComponent("api/wearables/disponibles"), timeoutInterval: 20)
        pedido.httpMethod = "GET"
        guard let (datos, respuesta) = try? await transporte.enviar(pedido),
              let http = respuesta as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let j = try? JSONDecoder().decode(ProveedoresDisponibles.self, from: datos) else { return nil }
        return j.proveedores.map(\.id)
    }

    /// `…/api/wearables/iniciar?t=<TOKEN>&proveedor=…`: redirige al OAuth del proveedor. Se abre en
    /// SFSafariViewController porque el token viaja en la query (nunca en un navegador que lo guarde en el historial
    /// compartido ni en un WebView propio).
    public func urlConectarReloj(token: String, proveedor: String) -> URL? {
        var c = URLComponents(url: config.app.appendingPathComponent("api/wearables/iniciar"), resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "t", value: token), URLQueryItem(name: "proveedor", value: proveedor)]
        return c?.url
    }
}
