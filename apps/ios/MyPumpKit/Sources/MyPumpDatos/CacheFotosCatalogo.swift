import CryptoKit
import Foundation

/// Las fotos de los ejercicios del catálogo, guardadas en el teléfono (batería, 2.3.2). El bucket público responde
/// `cache-control: private, no-cache`, así que `AsyncImage` volvía a preguntar en cada aparición. Las fotos del catálogo no
/// suelen cambiar, pero la URL no lleva versión: se guardan en memoria y en disco (`Caches/`, que iOS puede vaciar si
/// falta lugar) y pasada `vigencia` se revalidan con el `ETag` (`If-None-Match`): si no cambió, el servidor contesta 304
/// sin la foto y la guardada vale otras 24 h. Sin red, la guardada sirve aunque esté vencida. Dos pedidos de la misma
/// foto a la vez son uno solo.
public final class CacheFotosCatalogo: @unchecked Sendable {
    public typealias Bajar = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// La de la app: `Caches/fotos-catalogo`.
    public static let compartida = CacheFotosCatalogo(
        carpeta: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("fotos-catalogo"))

    /// Cuánto vale una foto guardada antes de revalidarla (revisión: la URL no lleva versión; antes eran 7 días).
    public static let vigencia: TimeInterval = 24 * 3600

    private let memoria = NSCache<NSURL, NSData>()
    private let carpeta: URL?
    private let bajar: Bajar
    private let ahora: @Sendable () -> Date
    private let lock = NSLock()
    private var enVuelo: [URL: Task<Data?, Never>] = [:]

    public init(carpeta: URL?, bajar: Bajar? = nil, ahora: @escaping @Sendable () -> Date = { Date() }) {
        self.carpeta = carpeta
        self.ahora = ahora
        memoria.totalCostLimit = 24 * 1024 * 1024
        if let bajar {
            self.bajar = bajar
        } else {
            // Sin la caché de URLSession: la guarda esta clase (una sola copia).
            let config = URLSessionConfiguration.default
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 30
            let sesion = URLSession(configuration: config)
            self.bajar = { pedido in try await sesion.data(for: pedido) }
        }
        if let carpeta { try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true) }
    }

    /// Lo que ya está en memoria, sin esperar (la pantalla la pinta al instante).
    public func enMemoria(_ url: URL) -> Data? { memoria.object(forKey: url as NSURL) as Data? }

    /// La foto: de la memoria, del disco si no venció, o de la red. nil si no hay ni red ni copia.
    public func datos(_ url: URL) async -> Data? {
        if let d = enMemoria(url) { return d }
        let guardada = leerDisco(url)
        if let g = guardada, !g.vencida {
            guardarMemoria(url, g.datos)
            return g.datos
        }
        let tarea: Task<Data?, Never> = lock.withLock {
            if let t = enVuelo[url] { return t }
            let t = Task { await self.traer(url, guardada: guardada) }
            enVuelo[url] = t
            return t
        }
        let nueva = await tarea.value
        lock.withLock { if enVuelo[url] == tarea { enVuelo[url] = nil } }
        if let nueva { return nueva }
        // Sin red o el servidor caído: la guardada, aunque esté vencida.
        if let g = guardada { guardarMemoria(url, g.datos); return g.datos }
        return nil
    }

    private func traer(_ url: URL, guardada: (datos: Data, vencida: Bool, etag: String?)?) async -> Data? {
        var pedido = URLRequest(url: url)
        if let etag = guardada?.etag { pedido.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (d, r) = try? await bajar(pedido), let http = r as? HTTPURLResponse else { return nil }
        let archivo = archivo(url)
        // No cambió: la guardada vale otra vigencia, sin bajarla de nuevo.
        if http.statusCode == 304, let g = guardada {
            if let archivo { try? FileManager.default.setAttributes([.modificationDate: ahora()], ofItemAtPath: archivo.path) }
            guardarMemoria(url, g.datos)
            return g.datos
        }
        guard http.statusCode == 200, !d.isEmpty else { return nil }
        guardarMemoria(url, d)
        if let archivo {
            try? d.write(to: archivo, options: .atomic)
            try? FileManager.default.setAttributes([.modificationDate: ahora()], ofItemAtPath: archivo.path)
            let marca = Self.archivoEtag(archivo)
            if let etag = http.value(forHTTPHeaderField: "ETag"), !etag.isEmpty {
                try? Data(etag.utf8).write(to: marca, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: marca)
            }
        }
        return d
    }

    private static func archivoEtag(_ archivo: URL) -> URL { archivo.appendingPathExtension("etag") }

    private func guardarMemoria(_ url: URL, _ d: Data) { memoria.setObject(d as NSData, forKey: url as NSURL, cost: d.count) }

    private func leerDisco(_ url: URL) -> (datos: Data, vencida: Bool, etag: String?)? {
        guard let archivo = archivo(url), let d = try? Data(contentsOf: archivo), !d.isEmpty else { return nil }
        let fecha = (try? FileManager.default.attributesOfItem(atPath: archivo.path))?[.modificationDate] as? Date ?? .distantPast
        let edad = ahora().timeIntervalSince(fecha)
        let vencida = edad < 0 || edad >= Self.vigencia
        // El ETag se lee solo si hace falta revalidar.
        let etag = vencida ? (try? Data(contentsOf: Self.archivoEtag(archivo))).flatMap { String(data: $0, encoding: .utf8) } : nil
        return (d, vencida, etag)
    }

    private func archivo(_ url: URL) -> URL? {
        guard let carpeta else { return nil }
        let h = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return carpeta.appendingPathComponent(h + "." + (url.pathExtension.isEmpty ? "img" : url.pathExtension))
    }
}
