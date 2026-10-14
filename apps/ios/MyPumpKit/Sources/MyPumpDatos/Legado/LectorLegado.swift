import Foundation
import SQLite3

/// Un archivo del almacenamiento viejo, con la ruta RELATIVA a `Library`: el UUID de la carpeta del contenedor cambia
/// al reinstalar (lo vio la espía en el simulador), así que nunca se guarda una ruta absoluta.
public struct ArchivoLegado: Codable, Equatable, Sendable {
    /// Las rutas van debajo de `WebKit/WebsiteData/` en el iPhone y de `WebKit/<bundle>/WebsiteData/` en el simulador.
    public enum Formato: String, Codable, Sendable {
        /// iOS 17+: `…/WebsiteData/Default/<hash>/<hash>/LocalStorage/localstorage.sqlite3`.
        case actual
        /// iOS ≤16: `…/WebsiteData/LocalStorage/capacitor_localhost_0.localstorage`. WebKit lo migra recién cuando abre
        /// ese origen, así que sigue ahí si el cliente no abrió MyPump desde que actualizó iOS.
        case anterior
    }
    public let formato: Formato
    public let ruta: String
}

/// Fecha y tamaño del archivo principal y de su `-wal` (el `-shm` no: es un índice que cambia con solo leer). Si la
/// huella cambia desde la última migración, alguien volvió a la Capacitor y la migración se repite.
public struct HuellaLegado: Codable, Equatable, Sendable {
    public struct Archivo: Codable, Equatable, Sendable {
        public let ruta: String
        public let bytes: Int64
        public let modificado: Double
    }
    public let archivos: [Archivo]
}

/// Cuántas unidades UTF-16 tiene un valor y su FNV-1a de 32 bits sobre esas unidades, tal como están en el archivo
/// (antes de convertirlas a `String`). La escritura de vuelta lo recalcula en JavaScript con `charCodeAt` para
/// comprobar que la clave sigue igual antes de borrarla: es exacto aunque el valor tenga un surrogate suelto, que al
/// pasar a `String` se vuelve U+FFFD.
public struct FirmaValor: Codable, Equatable, Hashable, Sendable {
    public let unidades: Int
    public let fnv: UInt32

    static func de<C: Collection>(_ u: C) -> FirmaValor where C.Element == UInt16 {
        var h: UInt32 = 0x811C9DC5
        for x in u { h = (h ^ UInt32(x)) &* 0x0100_0193 }
        return FirmaValor(unidades: u.count, fnv: h)
    }
}

public struct LecturaLegado: Sendable {
    public let items: [String: String]
    public let firmas: [String: FirmaValor]
    public let huella: HuellaLegado
    public let archivos: [ArchivoLegado]
}

public enum ErrorLegado: Error, Equatable, CustomStringConvertible {
    case sqlite(String)
    case archivo(String)

    public var description: String {
        switch self {
        case .sqlite(let s): return "sqlite: \(s)"
        case .archivo(let s): return "archivo: \(s)"
        }
    }
}

/// Ruta B: lee el `localStorage` que dejó la app Capacitor directo de los archivos de WebKit, sin levantar un WebView.
/// Probado en iOS 17.5, 18.6 y 26.5 (docs/NATIVA_SPIKE_ALMACENAMIENTO.md).
///
/// Nunca abre el original: copia db + wal + shm a un temporal y abre la COPIA. Lo reciente vive en el `-wal` (con la
/// app cerrada el `.sqlite3` tiene 4 KB vacíos), y SQLite al cerrar la última conexión pasa el wal al archivo principal
/// y lo borra: abrir el original lo modificaría.
public enum LectorLegado {
    public static let bundle = "com.pumpteam.mypump"

    /// Los archivos del origen `capacitor://localhost`, del más viejo al más nuevo (al combinar, gana el último). El
    /// formato nuevo se reconoce por el archivo `origin` de su carpeta, no recalculando el hash: depende de una sal.
    ///
    /// Se recorre todo `Library/WebKit`, sin armar la ruta: en el iPhone WebKit guarda en `WebKit/WebsiteData` y en el
    /// simulador en `WebKit/<bundle>/WebsiteData`. La 2.0.0 (100) buscaba solo la del simulador, y en el TF-0 (iPhone con
    /// iOS 27) no encontró nada: arrancó como recién instalada y pidió el link.
    public static func ubicar(library: URL) -> [ArchivoLegado] {
        let fm = FileManager.default
        var encontrados: [(ArchivoLegado, Double)] = []
        guard let recorrido = fm.enumerator(at: library.appendingPathComponent("WebKit", isDirectory: true),
                                            includingPropertiesForKeys: nil) else { return [] }
        for case let url as URL in recorrido {
            switch url.lastPathComponent {
            case "capacitor_localhost_0.localstorage" where url.deletingLastPathComponent().lastPathComponent == "LocalStorage":
                encontrados.append((ArchivoLegado(formato: .anterior, ruta: relativa(url, a: library)), -1))
            case "origin":
                guard let origen = try? Data(contentsOf: url), esCapacitorLocalhost(origen) else { continue }
                let db = url.deletingLastPathComponent().appendingPathComponent("LocalStorage/localstorage.sqlite3")
                guard fm.fileExists(atPath: db.path) else { continue }
                encontrados.append((ArchivoLegado(formato: .actual, ruta: relativa(db, a: library)), modificado(db) ?? 0))
            default:
                continue
            }
        }
        return encontrados.sorted { ($0.1, $0.0.ruta) < ($1.1, $1.0.ruta) }.map(\.0)
    }

    /// El archivo `origin` guarda dos orígenes (el de arriba y el del frame). Los dos tienen que ser capacitor://localhost.
    static func esCapacitorLocalhost(_ data: Data) -> Bool {
        let imprimible = String(decoding: data.map { (0x20..<0x7f).contains($0) ? $0 : 0x20 }, as: UTF8.self)
        return imprimible.components(separatedBy: "capacitor").count - 1 >= 2
            && imprimible.components(separatedBy: "localhost").count - 1 >= 2
    }

    /// Solo `stat`: barata, se mira en cada arranque.
    public static func huella(library: URL, archivos: [ArchivoLegado]) -> HuellaLegado {
        var h: [HuellaLegado.Archivo] = []
        for a in archivos {
            for sufijo in ["", "-wal"] {
                let url = library.appendingPathComponent(a.ruta + sufijo)
                guard let at = try? FileManager.default.attributesOfItem(atPath: url.path) else { continue }
                let bytes = (at[.size] as? NSNumber)?.int64Value ?? -1
                let fecha = (at[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                h.append(.init(ruta: a.ruta + sufijo, bytes: bytes, modificado: fecha))
            }
        }
        return HuellaLegado(archivos: h)
    }

    /// Lee y combina todos los archivos. nil = no hay almacenamiento viejo. Un error de lectura TIRA: no es lo mismo
    /// que "vacío" (con el teléfono bloqueado o un archivo a medio copiar, concluir "no había nada" perdería todo).
    public static func leer(library: URL) throws -> LecturaLegado? {
        let archivos = ubicar(library: library)
        guard !archivos.isEmpty else { return nil }
        let huella = huella(library: library, archivos: archivos)
        var items: [String: String] = [:]
        var firmas: [String: FirmaValor] = [:]
        for a in archivos {
            let (i, f) = try leerSQLite(library.appendingPathComponent(a.ruta))
            items.merge(i) { _, nuevo in nuevo }
            firmas.merge(f) { _, nuevo in nuevo }
        }
        return LecturaLegado(items: items, firmas: firmas, huella: huella, archivos: archivos)
    }

    /// La copia cruda, ANTES de tocar nada: los archivos tal cual (db, wal, shm y `origin`), uno por carpeta. Devuelve
    /// las rutas copiadas, relativas a `destino`.
    @discardableResult
    public static func copiarCrudo(library: URL, archivos: [ArchivoLegado], a destino: URL) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: destino, withIntermediateDirectories: true)
        var copiados: [String] = []
        for (n, a) in archivos.enumerated() {
            let carpeta = "\(n + 1)-\(a.formato.rawValue)"
            let dir = destino.appendingPathComponent(carpeta, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let db = library.appendingPathComponent(a.ruta)
            var fuentes = ["", "-wal", "-shm"].map { URL(fileURLWithPath: db.path + $0) }
            if a.formato == .actual { fuentes.append(db.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("origin")) }
            for f in fuentes where fm.fileExists(atPath: f.path) {
                let d = dir.appendingPathComponent(f.lastPathComponent)
                try? fm.removeItem(at: d)
                try fm.copyItem(at: f, to: d)
                copiados.append("\(carpeta)/\(f.lastPathComponent)")
            }
        }
        return copiados
    }

    /// `ItemTable(key TEXT UNIQUE, value BLOB)` con el valor en UTF-16LE. Se abre una copia de db + wal + shm.
    static func leerSQLite(_ url: URL) throws -> ([String: String], [String: FirmaValor]) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("legado-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let copia = tmp.appendingPathComponent("ls.sqlite3")
        do { try fm.copyItem(at: url, to: copia) } catch { throw ErrorLegado.archivo("no se pudo copiar \(url.lastPathComponent): \(error)") }
        for sufijo in ["-wal", "-shm"] {
            let origen = URL(fileURLWithPath: url.path + sufijo)
            if fm.fileExists(atPath: origen.path) {
                do { try fm.copyItem(at: origen, to: URL(fileURLWithPath: copia.path + sufijo)) }
                catch { throw ErrorLegado.archivo("no se pudo copiar \(origen.lastPathComponent): \(error)") }
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copia.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let m = db.map { String(cString: sqlite3_errmsg($0)) } ?? "?"
            sqlite3_close(db)
            throw ErrorLegado.sqlite("no abre \(url.lastPathComponent): \(m)")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key, value FROM ItemTable", -1, &stmt, nil) == SQLITE_OK else {
            let m = String(cString: sqlite3_errmsg(db))
            if m.contains("no such table") { return ([:], [:]) }   // un origen creado y nunca escrito
            throw ErrorLegado.sqlite(m)
        }
        defer { sqlite3_finalize(stmt) }

        var items: [String: String] = [:]
        var firmas: [String: FirmaValor] = [:]
        while true {
            let r = sqlite3_step(stmt)
            if r == SQLITE_DONE { break }
            guard r == SQLITE_ROW else { throw ErrorLegado.sqlite(String(cString: sqlite3_errmsg(db))) }
            let (clave, _) = columna(stmt, 0)
            let (valor, unidades) = columna(stmt, 1)
            items[clave] = valor
            firmas[clave] = FirmaValor.de(unidades)
        }
        return (items, firmas)
    }

    /// Una columna como texto y sus unidades UTF-16. WebKit guarda el valor como BLOB en UTF-16LE (los iPhone y Apple
    /// Silicon son little endian) y la clave como TEXT; se aceptan las dos formas en las dos columnas. Nunca devuelve
    /// "vacío" por un valor raro: `String(decoding:)` cambia lo inválido por U+FFFD (`String(data:encoding:)` daba nil,
    /// y con `?? ""` el valor se perdía en silencio).
    private static func columna(_ stmt: OpaquePointer?, _ i: Int32) -> (String, [UInt16]) {
        let n = Int(sqlite3_column_bytes(stmt, i))
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_BLOB:
            guard n > 0, let p = sqlite3_column_blob(stmt, i) else { return ("", []) }
            let bytes = UnsafeRawBufferPointer(start: p, count: n)
            var u = [UInt16]()
            u.reserveCapacity(n / 2)
            var k = 0
            while k + 1 < n { u.append(UInt16(bytes[k]) | UInt16(bytes[k + 1]) << 8); k += 2 }
            return (String(decoding: u, as: UTF16.self), u)
        case SQLITE_NULL:
            return ("", [])
        default:
            guard n > 0, let p = sqlite3_column_text(stmt, i) else { return ("", []) }
            let s = String(decoding: UnsafeBufferPointer(start: p, count: n), as: UTF8.self)
            return (s, Array(s.utf16))
        }
    }

    private static func modificado(_ url: URL) -> Double? {
        // El más nuevo de db y wal: lo último que escribió WebKit puede estar solo en el wal.
        [url.path, url.path + "-wal"].compactMap {
            ((try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date)?.timeIntervalSince1970
        }.max()
    }

    static func relativa(_ url: URL, a library: URL) -> String {
        let l = library.standardizedFileURL.resolvingSymlinksInPath().path
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        return p.hasPrefix(l + "/") ? String(p.dropFirst(l.count + 1)) : url.lastPathComponent
    }
}
