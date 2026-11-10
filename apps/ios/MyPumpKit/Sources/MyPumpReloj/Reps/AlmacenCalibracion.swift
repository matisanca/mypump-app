import Foundation

/// Una carpeta de archivos `.mpcal` con tope de espacio (tanda 4). El reloj guarda ahí cada serie hasta que el iPhone
/// la recibe; el iPhone junta las series en un archivo por sesión hasta que el alumno las exporta o las borra. Si se
/// pasa del tope, se borran los archivos más viejos (nunca se llena el disco por esto).
public struct AlmacenCalibracion: Sendable {
    public let carpeta: URL
    public let tope: Int

    /// El tope del reloj (30 MB ≈ 100 series largas) y el del iPhone (150 MB).
    public static let topeReloj = 30 * 1_024 * 1_024
    public static let topeIPhone = 150 * 1_024 * 1_024

    public init(carpeta: URL, tope: Int) { self.carpeta = carpeta; self.tope = tope }

    public struct Archivo: Equatable, Sendable {
        public var url: URL
        public var bytes: Int
        public var fecha: Date
    }

    /// Los archivos, del más viejo al más nuevo.
    public func archivos() -> [Archivo] {
        let fm = FileManager.default
        let claves: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: claves) else { return [] }
        return urls.filter { $0.pathExtension == ArchivoCalibracion.extension_ }.compactMap { u in
            let v = try? u.resourceValues(forKeys: Set(claves))
            return Archivo(url: u, bytes: v?.fileSize ?? 0, fecha: v?.contentModificationDate ?? .distantPast)
        }.sorted { ($0.fecha, $0.url.lastPathComponent) < ($1.fecha, $1.url.lastPathComponent) }
    }

    public var bytes: Int { archivos().reduce(0) { $0 + $1.bytes } }

    /// Escribe un archivo nuevo (reemplaza si ya existe) y respeta el tope.
    @discardableResult
    public func guardar(_ d: Data, nombre: String) throws -> URL {
        try crear()
        let u = carpeta.appendingPathComponent(nombre)
        try d.write(to: u, options: .atomic)
        recortar(sin: u)
        return u
    }

    /// Agrega registros al final de un archivo (lo crea si no existe) y respeta el tope.
    @discardableResult
    public func anexar(_ d: Data, nombre: String) throws -> URL {
        try crear()
        let u = carpeta.appendingPathComponent(nombre)
        if FileManager.default.fileExists(atPath: u.path) {
            let h = try FileHandle(forWritingTo: u)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: d)
        } else {
            try d.write(to: u, options: .atomic)
        }
        recortar(sin: u)
        return u
    }

    public func borrar(_ u: URL) { try? FileManager.default.removeItem(at: u) }
    public func borrarTodo() { archivos().forEach { borrar($0.url) } }

    /// Borra los más viejos hasta quedar bajo el tope (nunca el que se acaba de escribir).
    public func recortar(sin protegido: URL? = nil) {
        var lista = archivos()
        var total = lista.reduce(0) { $0 + $1.bytes }
        while total > tope, let i = lista.firstIndex(where: { $0.url.standardizedFileURL != protegido?.standardizedFileURL }) {
            borrar(lista[i].url)
            total -= lista[i].bytes
            lista.remove(at: i)
        }
    }

    private func crear() throws { try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true) }
}

/// El modo calibración: grabar las series a archivo (acelerómetro y giroscopio) para evaluar el contador. Apagado por
/// defecto y por cuenta: es aparte del contador, que va para todos. Viaja al reloj con la rutina (`RutinaReloj.calibracion`).
public struct ModoCalibracion: @unchecked Sendable {
    /// Las cuentas que lo prendieron (hashes, nunca tokens).
    static let clavePrendidas = "mypump-calibracion-prendidas"

    public static let textoPrivacidad = """
        Apagado por defecto. Prendido, durante cada serie el Apple Watch graba el movimiento del reloj, con el ejercicio, \
        las reps que cargás y las que contó el reloj, para evaluar y mejorar el conteo. Se guarda en el reloj y en este iPhone.
        """

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Las cuentas que grabaron en este iPhone (hashes).
    public var cuentas: [String] { defaults.stringArray(forKey: Self.clavePrendidas) ?? [] }

    public func prendido(cuenta: String) -> Bool {
        guard cuenta != "demo", !cuenta.isEmpty else { return false }
        return (defaults.stringArray(forKey: Self.clavePrendidas) ?? []).contains(cuenta)
    }

    public func poner(_ prender: Bool, cuenta: String) {
        guard cuenta != "demo", !cuenta.isEmpty else { return }
        var c = Set(defaults.stringArray(forKey: Self.clavePrendidas) ?? [])
        if prender { c.insert(cuenta) } else { c.remove(cuenta) }
        defaults.set(c.sorted(), forKey: Self.clavePrendidas)
    }
}
