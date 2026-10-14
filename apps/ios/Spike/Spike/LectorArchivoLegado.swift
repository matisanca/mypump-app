import Foundation
import SQLite3

/// Ruta B: lee el localStorage que dejó la app Capacitor directo del archivo de WebKit.
///
/// Dos formatos posibles dentro del contenedor de la app:
/// - iOS 17+: `Library/WebKit/<bundle>/WebsiteData/Default/<hash>/<hash>/LocalStorage/localstorage.sqlite3`,
///   con un archivo `origin` al lado que dice de qué origen es. El hash depende de una sal, así que se identifica
///   leyendo `origin`, no recalculando el hash.
/// - Anterior: `Library/WebKit/<bundle>/WebsiteData/LocalStorage/capacitor_localhost_0.localstorage`. WebKit lo
///   migra recién cuando abre ese origen, así que puede seguir ahí si el cliente no abrió la app desde iOS 16.
///
/// Lo escrito hace poco vive en el `-wal`: se copian los tres archivos y se abre la copia.
struct LecturaArchivo: Sendable {
    let ruta: String
    let formato: String
    let items: [String: String]
}

enum ErrorLegado: Error, CustomStringConvertible {
    case sqlite(String)
    case webView(String)

    var description: String {
        switch self {
        case .sqlite(let s): return "sqlite: \(s)"
        case .webView(let s): return "webview: \(s)"
        }
    }
}

enum LectorArchivoLegado {
    static func leer(bundleID: String = Bundle.main.bundleIdentifier ?? "com.pumpteam.mypump") throws -> [LecturaArchivo] {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let base = library.appendingPathComponent("WebKit/\(bundleID)/WebsiteData")
        var resultados: [LecturaArchivo] = []

        let porDefecto = base.appendingPathComponent("Default")
        for top in (try? fm.contentsOfDirectory(at: porDefecto, includingPropertiesForKeys: nil)) ?? [] {
            for frame in (try? fm.contentsOfDirectory(at: top, includingPropertiesForKeys: nil)) ?? [] {
                guard let origen = try? Data(contentsOf: frame.appendingPathComponent("origin")),
                      esCapacitorLocalhost(origen) else { continue }
                let db = frame.appendingPathComponent("LocalStorage/localstorage.sqlite3")
                if fm.fileExists(atPath: db.path) {
                    resultados.append(LecturaArchivo(ruta: db.path, formato: "ios17+", items: try leerSQLite(db)))
                }
            }
        }

        let anterior = base.appendingPathComponent("LocalStorage/capacitor_localhost_0.localstorage")
        if fm.fileExists(atPath: anterior.path) {
            resultados.append(LecturaArchivo(ruta: anterior.path, formato: "anterior", items: try leerSQLite(anterior)))
        }
        return resultados
    }

    /// El archivo `origin` guarda dos orígenes (el de arriba y el del frame). Los dos tienen que ser capacitor://localhost.
    static func esCapacitorLocalhost(_ data: Data) -> Bool {
        let imprimible = String(decoding: data.map { (0x20..<0x7f).contains($0) ? $0 : 0x20 }, as: UTF8.self)
        return imprimible.components(separatedBy: "capacitor").count - 1 >= 2
            && imprimible.components(separatedBy: "localhost").count - 1 >= 2
    }

    static func leerSQLite(_ url: URL) throws -> [String: String] {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("legado-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let copia = tmp.appendingPathComponent("ls.sqlite3")
        try fm.copyItem(at: url, to: copia)
        for sufijo in ["-wal", "-shm"] {
            let origen = URL(fileURLWithPath: url.path + sufijo)
            if fm.fileExists(atPath: origen.path) {
                try fm.copyItem(at: origen, to: URL(fileURLWithPath: copia.path + sufijo))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copia.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw ErrorLegado.sqlite("no abre \(url.lastPathComponent)")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key, value FROM ItemTable", -1, &stmt, nil) == SQLITE_OK else {
            throw ErrorLegado.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var items: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let k = sqlite3_column_text(stmt, 0) else { continue }
            let n = Int(sqlite3_column_bytes(stmt, 1))
            var valor = ""
            if n > 0, let p = sqlite3_column_blob(stmt, 1) {
                // WebKit guarda el valor en UTF-16 (little endian en Apple Silicon y en los iPhone).
                valor = String(data: Data(bytes: p, count: n), encoding: .utf16LittleEndian) ?? ""
            }
            items[String(cString: k)] = valor
        }
        return items
    }
}
