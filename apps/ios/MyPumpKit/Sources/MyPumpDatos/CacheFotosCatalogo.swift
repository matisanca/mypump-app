import CryptoKit
import Foundation

/// Las fotos de los ejercicios del catálogo, guardadas en el teléfono (batería, 2.3.2). El bucket público responde
/// `cache-control: private, no-cache`, así que `AsyncImage` volvía a preguntar en cada aparición. Las fotos del catálogo no
/// cambian bajo la misma URL: se guardan en memoria y en disco (`Caches/`, que iOS puede vaciar si falta lugar) y se
/// vuelven a bajar recién pasada `vigencia`. Sin red, la guardada sirve aunque esté vencida. Dos pedidos de la misma foto
/// a la vez son uno solo.
public final class CacheFotosCatalogo: @unchecked Sendable {
    public typealias Bajar = @Sendable (URL) async throws -> (Data, URLResponse)

    /// La de la app: `Caches/fotos-catalogo`.
    public static let compartida = CacheFotosCatalogo(
        carpeta: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("fotos-catalogo"))

    /// Cuánto vale una foto guardada antes de volver a bajarla.
    public static let vigencia: TimeInterval = 7 * 24 * 3600

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
            self.bajar = { url in try await sesion.data(from: url) }
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
            let t = Task { await self.traer(url) }
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

    private func traer(_ url: URL) async -> Data? {
        guard let (d, r) = try? await bajar(url), (r as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty else { return nil }
        guardarMemoria(url, d)
        if let archivo = archivo(url) { try? d.write(to: archivo, options: .atomic) }
        return d
    }

    private func guardarMemoria(_ url: URL, _ d: Data) { memoria.setObject(d as NSData, forKey: url as NSURL, cost: d.count) }

    private func leerDisco(_ url: URL) -> (datos: Data, vencida: Bool)? {
        guard let archivo = archivo(url), let d = try? Data(contentsOf: archivo), !d.isEmpty else { return nil }
        let fecha = (try? archivo.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let edad = ahora().timeIntervalSince(fecha)
        return (d, edad < 0 || edad >= Self.vigencia)
    }

    private func archivo(_ url: URL) -> URL? {
        guard let carpeta else { return nil }
        let h = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return carpeta.appendingPathComponent(h + "." + (url.pathExtension.isEmpty ? "img" : url.pathExtension))
    }
}
