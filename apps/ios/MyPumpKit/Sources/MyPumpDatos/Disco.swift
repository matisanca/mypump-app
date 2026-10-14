import CryptoKit
import Foundation

/// Archivos JSON del cliente en Application Support, uno por cuenta (la carpeta lleva un hash del token, como la web
/// lleva el token en la clave de localStorage: dos cuentas en el mismo teléfono no se mezclan). Escritura atómica.
public struct Disco: Sendable {
    public let carpeta: URL

    public init(raiz: URL? = nil, token: String) {
        let base = raiz ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let hash = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        carpeta = base.appendingPathComponent("MyPump/cuenta-\(hash)", isDirectory: true)
    }

    public func url(_ nombre: String) -> URL { carpeta.appendingPathComponent(nombre) }

    public func leer<T: Decodable>(_ tipo: T.Type, _ nombre: String) -> T? {
        guard let d = try? Data(contentsOf: url(nombre)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    public func guardar<T: Encodable>(_ valor: T, _ nombre: String) {
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            try JSONEncoder().encode(valor).write(to: url(nombre), options: [.atomic])
        } catch {}
    }

    public func borrar(_ nombre: String) { try? FileManager.default.removeItem(at: url(nombre)) }
}
