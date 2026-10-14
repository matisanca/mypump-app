import Foundation
import JavaScriptCore
import SQLite3
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

// La migración del almacenamiento viejo con archivos de WebKit DE VERDAD: `ItemTable(key TEXT UNIQUE, value BLOB)` con el
// valor en UTF-16LE, en modo WAL y con los datos SOLO en el `-wal`, que es como queda con la app cerrada (el `.sqlite3`
// tiene 4 KB vacíos y leerlo solo da cero claves). Los formatos salen de la web: `main` y `v1.0.11` (la que tienen los
// iPhone), y `v1.0.2` para la cola sin `_id`.

private let tokenA = "tokAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"   // 32, como los de sembrar.mjs
private let tokenB = "tokBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
private let rutinaR1 = "11111111-1111-4111-8111-111111111111"
private let rutinaR2 = "22222222-2222-4222-8222-222222222222"
private let dietaD = "00000000-0000-4000-8000-000000000d1e"
private let sesionS = "6f0c2a8e-5b1d-4c7e-9a3f-2d8e1b7c4a90"
/// 14-oct-2026 12:00 en Buenos Aires.
private let ahora = Date(timeIntervalSince1970: 1_791_990_000)
private let ahoraMs = ahora.timeIntervalSince1970 * 1000
private let baires = TimeZone(identifier: "America/Argentina/Buenos_Aires")!

// MARK: - El WebKit de mentira (con archivos de verdad)

/// `Library/WebKit/WebsiteData/…` (iPhone) o `Library/WebKit/<bundle>/WebsiteData/…` (simulador), con el formato nuevo
/// (iOS 17+) y/o el anterior. Por defecto, el del iPhone: el del simulador era el único que se probaba, y en el TF-0 la
/// 2.0.0 (100) no encontró nada en un iPhone de verdad.
private struct WebKitFalso {
    enum Disposicion {
        case telefono, simulador
        var prefijo: String { self == .telefono ? "WebKit/WebsiteData" : "WebKit/\(LectorLegado.bundle)/WebsiteData" }
    }

    let library: URL
    let disposicion: Disposicion

    var dbActual: URL {
        library.appendingPathComponent("\(disposicion.prefijo)/Default/HASH_ARRIBA/HASH_FRAME/LocalStorage/localstorage.sqlite3")
    }
    var dbAnterior: URL {
        library.appendingPathComponent("\(disposicion.prefijo)/LocalStorage/capacitor_localhost_0.localstorage")
    }

    init(_ raiz: URL, _ disposicion: Disposicion = .telefono) {
        library = raiz.appendingPathComponent("Library", isDirectory: true)
        self.disposicion = disposicion
        let fm = FileManager.default
        try? fm.createDirectory(at: dbActual.deletingLastPathComponent(), withIntermediateDirectories: true)
        // El archivo `origin`: dos orígenes serializados (arriba y frame), con bytes binarios en el medio.
        var origen = Data([0x01, 0x00, 0x00, 0x00])
        for _ in 0..<2 {
            origen.append(contentsOf: Array("capacitor".utf8)); origen.append(0x00)
            origen.append(contentsOf: Array("localhost".utf8)); origen.append(contentsOf: [0x00, 0xFF, 0xFF])
        }
        try? origen.write(to: dbActual.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("origin"))
        // Otro origen al lado, que no es el de la app: no se tiene que leer.
        let otro = library.appendingPathComponent("\(disposicion.prefijo)/Default/OTRO/OTRO")
        try? fm.createDirectory(at: otro.appendingPathComponent("LocalStorage"), withIntermediateDirectories: true)
        try? Data("https\u{0}app.mypumpteam.com\u{0}https\u{0}app.mypumpteam.com".utf8).write(to: otro.appendingPathComponent("origin"))
    }

    /// Escribe como WebKit y deja el archivo como queda con la app cerrada: todo en el `-wal`. Se arma en un taller con la
    /// conexión abierta, se copian db + wal + shm, y recién después se cierra (al cerrar la última conexión SQLite pasa
    /// el wal al archivo principal: eso queda en el taller).
    func escribir(_ items: [String: String], borrar: [String] = [], en destino: URL? = nil) throws {
        let db = destino ?? dbActual
        let fm = FileManager.default
        let taller = fm.temporaryDirectory.appendingPathComponent("taller-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: taller, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: taller) }
        let t = taller.appendingPathComponent("ls.sqlite3")
        for s in ["", "-wal", "-shm"] where fm.fileExists(atPath: db.path + s) {
            try fm.copyItem(atPath: db.path + s, toPath: t.path + s)
        }
        var c: OpaquePointer?
        guard sqlite3_open(t.path, &c) == SQLITE_OK else { throw ErrorLegado.sqlite("taller") }
        func ejecutar(_ sql: String) throws {
            guard sqlite3_exec(c, sql, nil, nil, nil) == SQLITE_OK else { throw ErrorLegado.sqlite(String(cString: sqlite3_errmsg(c))) }
        }
        try ejecutar("PRAGMA journal_mode=WAL")
        try ejecutar("PRAGMA wal_autocheckpoint=0")
        try ejecutar("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB NOT NULL ON CONFLICT FAIL)")
        try ejecutar("BEGIN")
        for k in borrar {
            var st: OpaquePointer?
            sqlite3_prepare_v2(c, "DELETE FROM ItemTable WHERE key = ?", -1, &st, nil)
            sqlite3_bind_text(st, 1, k, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_step(st); sqlite3_finalize(st)
        }
        for (k, v) in items {
            var st: OpaquePointer?
            sqlite3_prepare_v2(c, "INSERT INTO ItemTable (key, value) VALUES (?, ?)", -1, &st, nil)
            sqlite3_bind_text(st, 1, k, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            var bytes: [UInt8] = []
            bytes.reserveCapacity(v.utf16.count * 2)
            for u in v.utf16 { bytes.append(UInt8(u & 0xFF)); bytes.append(UInt8(u >> 8)) }
            _ = bytes.withUnsafeBytes { p in
                sqlite3_bind_blob(st, 2, p.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard sqlite3_step(st) == SQLITE_DONE else { throw ErrorLegado.sqlite(String(cString: sqlite3_errmsg(c))) }
            sqlite3_finalize(st)
        }
        try ejecutar("COMMIT")
        try fm.createDirectory(at: db.deletingLastPathComponent(), withIntermediateDirectories: true)
        for s in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: db.path + s)
            if fm.fileExists(atPath: t.path + s) { try fm.copyItem(atPath: t.path + s, toPath: db.path + s) }
        }
        sqlite3_close(c)
        // La fecha tiene que moverse aunque el tamaño no cambie (en el teléfono pasa sola).
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(Double.random(in: 1...1000))], ofItemAtPath: db.path + "-wal")
    }
}

/// Lo que ve WebKit: las claves en el archivo (db + wal), leídas con SQLite aparte del lector.
private func claves(_ w: WebKitFalso) throws -> [String: String] {
    try LectorLegado.leer(library: w.library)?.items ?? [:]
}

// MARK: - Datos como los escribe la web

private func fecha(_ i: Int) -> String {
    FechaLegado.sumar("2026-10-14", -(i % 300), zona: baires)
}

/// Una cola como la de la web: `{_id, kind, payload, dedupeKey, tries, ts}` con dedupeKeys únicas (la web borra la
/// pendiente con la misma al encolar). Los 9 kinds; `carga` y `estado` con y sin `sesionId`.
private func colaWeb(_ n: Int, t0: Double = 1_791_900_000_000, conId: Bool = true, rutina: Bool = true) -> [JSONValue] {
    let kinds = ["carga", "estado", "swap", "swap_del", "habito", "comida", "peso", "checkin", "chat"]
    var ops: [JSONValue] = []
    for i in 0..<n {
        let kind = kinds[i % kinds.count]
        let dia = "b2d\(1 + i % 3)"
        let sesion: JSONValue = i % 2 == 0 ? .texto(sesionS) : .null
        var payload: [String: JSONValue]
        let dk: String
        switch kind {
        case "carga":
            payload = ["sesionId": sesion, "diaId": .texto(dia), "semana": .numero(3), "datos": .objeto([
                "diaId": .texto(dia), "ejercicioId": .texto("press-banca-\(dia)-\(i)"), "ejercicioNombre": .texto("Press inclinado 45° — mancuernas"),
                "serie": .numero(Double(1 + i % 4)), "peso": .numero(62.5), "reps": .numero(8), "rir": .numero(0), "notas": .null])]
            dk = "carga_\(dia)_press-banca-\(dia)-\(i)_\(i % 4)"
        case "estado":
            payload = ["sesionId": sesion, "semana": .numero(3), "diaId": .texto(dia), "exId": .texto("remo-\(dia)-\(i)"),
                       "seriesObjetivo": .numero(3), "status": .texto("completo"), "manual": .bool(false)]
            dk = "estado_\(dia)_remo-\(dia)-\(i)"
        case "swap":
            payload = ["dietaId": .texto(dietaD), "comidaId": .texto("desayuno"), "optIdx": .numero(Double(i % 4)), "foodIdx": .numero(Double(i)),
                       "food": .objeto(["name": .texto("Ricota descremada"), "qty": .numero(150), "unit": .texto("g"), "kcal": .numero(207),
                                        "_orig": .objeto(["name": .texto("Queso untable light"), "qty": .numero(60), "unit": .texto("g")])])]
            dk = "swap_\(dietaD)_desayuno_\(i % 4)_\(i)"
        case "swap_del":
            payload = ["dietaId": .texto(dietaD), "comidaId": .texto("almuerzo"), "optIdx": .numero(0), "foodIdx": .numero(Double(i))]
            dk = "swap_\(dietaD)_almuerzo_0_\(i)"
        case "habito":
            payload = ["fecha": .texto(fecha(i)), "campo": .texto("vasos_agua"), "valor": .texto("\(i % 12)")]
            dk = "habito|\(fecha(i))|vasos_agua"
        case "comida":
            payload = ["fecha": .texto(fecha(i)), "comidaId": .texto("almuerzo"), "opcion": .texto("Opción B"), "estado": .texto("comido"),
                       "excl": .lista([.numero(1)])]
            dk = "comida|\(fecha(i))|almuerzo"
        case "peso":
            payload = ["fecha": .texto(fecha(i)), "valor": .numero(81.4)]
            dk = "peso_\(fecha(i))"
        case "checkin":
            payload = ["fecha": .texto(fecha(i)), "datos": .objeto(["energia": .numero(4), "descanso": .numero(3), "hambre": .numero(2),
                                                                     "adherencia": .numero(5), "nota": .texto("Semana dura, dormí poco 😴")])]
            dk = "checkin_\(fecha(i))"
        default:
            let texto = "Mati, ¿cambio el jalón por remo? ñandú \(i)"
            payload = ["contenido": .texto(texto)]
            dk = "chat_\(Int(t0) + i)_\(String(texto.prefix(40)))"
        }
        var o: [String: JSONValue] = ["kind": .texto(kind), "payload": .objeto(payload), "dedupeKey": .texto(dk),
                                      "tries": .numero(Double([0, 0, 1, 3][i % 4])), "ts": .numero(t0 + Double(i))]
        if conId { o["_id"] = .texto("\(Int(t0) + i)_\(i + 1)") }
        ops.append(.objeto(o))
    }
    return ops
}

private func json(_ v: JSONValue) -> String {
    String(decoding: try! JSONEncoder().encode(v), as: UTF8.self)
}

private func fotoOffline(rutina: String, dias: [String] = ["b2d1", "b2d2", "b2d3"], ts: Double = 1_791_900_000_000) -> String {
    json(.objeto([
        "info": .objeto(["cliente_id": .texto("test-nativa-ios"), "nombre": .texto("Test Nativa"), "perfil": .texto("natural")]),
        "rutina": .objeto(["id": .texto(rutina), "version": .numero(3), "semana_actual": .numero(3),
                           "estructura": .objeto(["dias": .lista(dias.map { .objeto(["id": .texto($0), "nombre": .texto($0), "bloques": .lista([])]) })])]),
        "dieta": .null, "ts": .numero(ts),
    ]))
}

/// Un teléfono con la Capacitor: Library con WebKit, Application Support vacío, Keychain y UserDefaults propios.
private struct Telefono {
    let raiz: URL
    let webkit: WebKitFalso
    let entorno: EntornoLegado
    let almacen = TokenEnMemoria()
    let ajustes: UserDefaults
    let suite: String

    init(_ disposicion: WebKitFalso.Disposicion = .telefono) {
        raiz = FileManager.default.temporaryDirectory.appendingPathComponent("legado-\(UUID().uuidString)", isDirectory: true)
        webkit = WebKitFalso(raiz, disposicion)
        entorno = EntornoLegado(library: webkit.library, soporte: raiz.appendingPathComponent("Application Support", isDirectory: true))
        suite = "legado-test-\(UUID().uuidString)"
        ajustes = UserDefaults(suiteName: suite)!
    }

    func faseL(cuentaViva: String? = nil, en momento: Date = ahora) throws -> EjecutorLegado.Resultado {
        try EjecutorLegado.faseLocal(entorno: entorno, almacen: almacen, ajustes: ajustes, ahora: momento, zona: baires, cuentaViva: cuentaViva)
    }

    var archivos: ArchivosLegado { ArchivosLegado(carpeta: entorno.carpeta) }
    func disco(_ t: String = tokenA) -> Disco { entorno.disco(t) }
    func cola(_ t: String = tokenA) -> Outbox.Persistido {
        disco(t).leer(Outbox.Persistido.self, "outbox.json") ?? Outbox.Persistido()
    }

    func limpiar() {
        ajustes.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: raiz)
    }
}

// MARK: - Un servidor de mentira para la Fase R

private actor Llamadas {
    var lista: [(String, JSONValue)] = []
    func anotar(_ f: String, _ p: JSONValue) { lista.append((f, p)) }
    func de(_ f: String) -> [JSONValue] { lista.filter { $0.0 == f }.map(\.1) }
}

private struct ServidorLegado: Transporte {
    let llamadas: Llamadas
    let responder: @Sendable (String, JSONValue) -> (Int, String)
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url!.lastPathComponent
        let p = (try? JSONDecoder().decode(JSONValue.self, from: pedido.httpBody ?? Data())) ?? .null
        await llamadas.anotar(fn, p)
        let (status, cuerpo) = responder(fn, p)
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// Una base con estado para los swaps de comida: lo que se guarda, después se lee.
private actor BaseDeSwaps: Transporte {
    private var swaps: [String: JSONValue] = [:]   // "comida/opt/food" → food_data

    init(_ iniciales: [String]) {
        for k in iniciales { swaps[k] = .objeto(["name": .texto("de otro teléfono")]) }
    }

    func claves() -> Set<String> { Set(swaps.keys) }

    func filas() -> [FoodSwap] {
        swaps.sorted { $0.key < $1.key }.compactMap { k, v in
            let p = k.split(separator: "/").map(String.init)
            let fila: JSONValue = .objeto(["comida_id": .texto(p[0]), "opt_idx": .numero(Double(p[1]) ?? 0), "food_idx": .numero(Double(p[2]) ?? 0),
                                           "food_data": v])
            return try? JSONDecoder().decode(FoodSwap.self, from: JSONEncoder().encode(fila))
        }
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url!.lastPathComponent
        let p = (try? JSONDecoder().decode(JSONValue.self, from: pedido.httpBody ?? Data())) ?? .null
        func clave() -> String {
            "\(p["p_comida_id"]?.comoTexto ?? "")/\(Int(p["p_opt_idx"]?.comoNumero ?? 0))/\(Int(p["p_food_idx"]?.comoNumero ?? 0))"
        }
        let cuerpo: String
        switch fn {
        case "mypump_get_dieta_activa": cuerpo = #"[{"id":"\#(dietaD)","version":1,"estructura":{"comidas":[]}}]"#
        case "mypump_get_food_swaps":
            cuerpo = String(decoding: try JSONEncoder().encode(JSONValue.lista(swaps.sorted { $0.key < $1.key }.map { k, v in
                let q = k.split(separator: "/").map(String.init)
                return .objeto(["comida_id": .texto(q[0]), "opt_idx": .numero(Double(q[1]) ?? 0), "food_idx": .numero(Double(q[2]) ?? 0), "food_data": v])
            })), as: UTF8.self)
        case "mypump_save_food_swap":
            swaps[clave()] = p["p_food_data"] ?? .null
            cuerpo = #"[{"ok":true}]"#
        case "mypump_delete_food_swap":
            cuerpo = swaps.removeValue(forKey: clave()) == nil ? "false" : "true"
        default: cuerpo = "[]"
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func rutinaActiva(_ id: String, dias: [String] = ["b2d1", "b2d2", "b2d3"]) -> String {
    let d = dias.map { #"{"id":"\#($0)","nombre":"\#($0)","bloques":[]}"# }.joined(separator: ",")
    return #"[{"id":"\#(id)","version":3,"semana_actual":3,"tiene_siguiente":false,"estructura":{"dias":[\#(d)]}}]"#
}

/// Contesta como la base: OK a cada escritura; `get_cliente_info` según el token; la rutina activa que se pida.
private func servidor(_ llamadas: Llamadas, activa: String = rutinaR1, clientes: [String: String] = [tokenA: "test-nativa-ios"]) -> ClienteRPC {
    ClienteRPC(transporte: ServidorLegado(llamadas: llamadas) { fn, p in
        switch fn {
        case "mypump_get_cliente_info":
            guard let t = p["p_token"]?.comoTexto, let c = clientes[t] else { return (200, "[]") }
            return (200, #"[{"cliente_id":"\#(c)","nombre":"Test","perfil":"natural"}]"#)
        case "mypump_get_rutina_activa": return (200, activa.isEmpty ? "[]" : rutinaActiva(activa))
        case "mypump_get_sesion_dia": return (200, "[]")
        case "mypump_iniciar_sesion": return (200, #""99999999-0000-4000-8000-000000000001""#)
        case "mypump_ingest_salud": return (200, "1")
        case "mypump_delete_food_swap", "mypump_desmarcar_comida": return (200, "true")
        case "mypump_set_habito", "mypump_marcar_comida", "mypump_save_food_swap", "mypump_guardar_checkin":
            return (200, #"[{"ok":true}]"#)
        default: return (200, #""00000000-0000-4000-8000-0000000000ff""#)
        }
    })
}

// MARK: - Tests

@Suite("Migración del almacenamiento viejo")
struct MigracionLegadoTests {

    @Test func quinientasOpsDeLosNueveKindsLeidasSoloDelWal() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let ops = colaWeb(500)
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(ops)),
                                 "mypump_offline_\(tokenA)": fotoOffline(rutina: rutinaR1)])
        // Es el caso real: el archivo principal tiene solo la cabecera y todo está en el -wal.
        let fm = FileManager.default
        let principal = (try fm.attributesOfItem(atPath: tel.webkit.dbActual.path)[.size] as? NSNumber)?.intValue ?? 0
        let wal = (try fm.attributesOfItem(atPath: tel.webkit.dbActual.path + "-wal")[.size] as? NSNumber)?.intValue ?? 0
        #expect(principal <= 4096 && wal > 100_000)
        let soloPrincipal = fm.temporaryDirectory.appendingPathComponent("solo-\(UUID().uuidString).sqlite3")
        try fm.copyItem(at: tel.webkit.dbActual, to: soloPrincipal)
        defer { try? fm.removeItem(at: soloPrincipal) }
        #expect(try LectorLegado.leerSQLite(soloPrincipal).0.isEmpty)   // sin el wal: cero claves

        let r = try tel.faseL()
        #expect(r.corrio && r.adoptoToken && r.tokenVigente == tokenA)
        #expect(tel.almacen.leer() == tokenA)
        let plan = try #require(r.plan)
        #expect(plan.conteos.opsPorKind.count == 9)
        #expect(plan.conteos.opsPorKind.values.reduce(0, +) == 500)
        #expect(plan.conteos.opsPorKind["carga"] == 56 && plan.conteos.opsPorKind["chat"] == 55)
        // Con sesión (o que no son de Entreno) van a la cola; las sin sesión esperan la validación de la Fase R.
        let sinSesion = ops.filter { o in ["carga", "estado"].contains(o["kind"]?.comoTexto ?? "") && o["payload"]?["sesionId"] == .null }
        #expect(r.porValidar == sinSesion.count && r.porValidar == 56)
        #expect(r.aLaCola == 500 - 56)
        let cola = tel.cola()
        #expect(cola.ops.count == 444)
        #expect(Set(cola.ops.map(\.kind)).count == 9)
        #expect(cola.ops.allSatisfy { $0.id.hasPrefix("legado-") })
        // El payload llega tal cual (el ejecutor de la cola lo manda igual que la web).
        let primera = try #require(cola.ops.first { $0.kind == "carga" })
        #expect(primera.payload["datos"]?["ejercicioNombre"]?.comoTexto == "Press inclinado 45° — mancuernas")
        #expect(primera.payload["datos"]?["rir"] == .numero(0))
        let pendientes = tel.archivos.pendientes
        #expect(pendientes.count == 1 && pendientes[0].propia && pendientes[0].ops.count == 56 && pendientes[0].rutinaFoto == rutinaR1)
        #expect(tel.archivos.libro.count == 500)
        // La copia cruda, antes de tocar nada: los tres archivos tal cual.
        let estado = try #require(tel.archivos.estado)
        let copia = tel.entorno.carpeta.appendingPathComponent(try #require(estado.copias.first))
        #expect(fm.fileExists(atPath: copia.appendingPathComponent("1-actual/localstorage.sqlite3-wal").path))
        #expect(fm.fileExists(atPath: copia.appendingPathComponent("1-actual/origin").path))
        #expect(estado.faseRPendiente && estado.escritura?.borrar["mypump_outbox_\(tokenA)"] != nil)
        // Y la foto offline sembró la caché de la cuenta, en el formato nativo.
        let offline = try #require(tel.disco().leer(ModeloApp.CopiaOffline.self, "offline.json"))
        #expect(offline.rutina?["id"]?.comoTexto == rutinaR1 && offline.info["cliente_id"]?.comoTexto == "test-nativa-ios")
    }

    @Test func colaSinIdComoLaV102() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let ops = colaWeb(30, conId: false)
        #expect(ops.allSatisfy { $0["_id"] == nil })
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(ops))])
        let r = try tel.faseL()
        #expect(r.aLaCola + r.porValidar == 30)
        let ids = tel.cola().ops.map(\.id)
        #expect(Set(ids).count == ids.count)
        // El id sale del contenido: otra lectura de los mismos datos da los mismos ids.
        let otra = MigracionLegado.planificar(try claves(tel.webkit), ahora: ahora, zona: baires)
        let vigente = try #require(otra.colas.first { $0.tipo == .vigente })
        #expect(Set(vigente.ops.filter { !$0.necesitaValidar }.map(\.operacion.id)) == Set(ids))
    }

    @Test func dosOpsIdenticasSinIdNoSeFunden() throws {
        // Sin `_id` dos entradas pueden ser idénticas; el índice entre idénticas las separa.
        let op: JSONValue = .objeto(["kind": .texto("peso"), "payload": .objeto(["fecha": .texto("2026-10-13"), "valor": .numero(80)]),
                                     "dedupeKey": .null, "tries": .numero(0), "ts": .numero(1)])
        let plan = MigracionLegado.planificar(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista([op, op]))], ahora: ahora)
        let ids = plan.colas.first?.ops.map(\.idLibro) ?? []
        #expect(ids.count == 2 && Set(ids).count == 2)
    }

    @Test func laColaAnonNuncaSeEjecuta() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(4))),
                                 "mypump_outbox_anon": json(.lista(colaWeb(7, t0: 5)))])
        let r = try tel.faseL()
        #expect(r.anon == 7)
        #expect(tel.cola().ops.count + (tel.archivos.pendientes.first?.ops.count ?? 0) == 4)
        #expect(tel.archivos.libro.values.filter { $0.destino == .anon }.count == 7)
        #expect(!tel.archivos.pendientes.contains { $0.clave == "mypump_outbox_anon" })
        // Y no se borra de la Capacitor: no se tomó.
        #expect(tel.archivos.estado?.escritura?.borrar["mypump_outbox_anon"] == nil)
    }

    @Test func lasClavesDemoNoSeAplican() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let swaps = #"{"jalon-d1-0":{"original":{"slug":"a","nombre":"A"},"current":{"slug":"b","nombre":"B"},"fijado":true,"semana":1,"diaId":"d1"}}"#
        try tel.webkit.escribir([
            "mypump_token": tokenA,
            "mypump_exercise_swaps_demo": swaps, "mypump_food_swaps_demo": #"{"swap_demo_x_0_0":{"original":null,"current":{"name":"Z"}}}"#,
            "mypump_swaps_migrados_demo": "1", "mypump_dia_visualizado_demo": "d2",
            "mypump_exercise_swaps_\(rutinaR1)": swaps, "mypump_dia_visualizado_\(rutinaR1)": "b2d2",
        ])
        let r = try tel.faseL()
        let plan = try #require(r.plan)
        #expect(plan.conteos.demo == 4)
        #expect(plan.sustituciones.keys.sorted() == [rutinaR1])
        #expect(tel.ajustes.string(forKey: "mypump_dia_visualizado_demo") == nil)
        #expect(tel.ajustes.string(forKey: "mypump_dia_visualizado_\(rutinaR1)") == "b2d2")
        #expect(!FileManager.default.fileExists(atPath: tel.disco().url(SustitucionEjercicio.archivo(rutinaId: "demo")).path))
        #expect(!FileManager.default.fileExists(atPath: tel.disco().url("swaps_demo.json").path))
        #expect(tel.disco().leer([String: SustitucionEjercicio].self, SustitucionEjercicio.archivo(rutinaId: rutinaR1))?.count == 1)
    }

    /// SER-14: si el cliente vuelve a la Capacitor, solo lo que cambió AHÍ desde la corrida anterior pisa lo del teléfono
    /// (con la hora de la corrida, para que gane también en el servidor) y lo que sacó ahí se saca; lo hecho en la nativa
    /// queda. Antes se pisaba todo con lo de la app vieja.
    @Test func laVueltaALaAppVieja_soloAplicaLoQueSeCambioAhi() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        func entrada(_ n: String) -> String {
            #"{"original":{"slug":"a","nombre":"A"},"current":{"slug":"b","nombre":"\#(n)"},"fijado":true,"semana":1,"diaId":"d1"}"#
        }
        let clave = "mypump_exercise_swaps_\(rutinaR1)"
        try tel.webkit.escribir(["mypump_token": tokenA, clave: "{\"jalon-d1-0\":\(entrada("B"))}"])
        _ = try tel.faseL()
        let nombre = SustitucionEjercicio.archivo(rutinaId: rutinaR1)
        let disco = tel.disco()
        var nativa = try #require(disco.leer([String: JSONValue].self, nombre))
        #expect(nativa["jalon-d1-0"]?["current"]?["nombre"]?.comoTexto == "B" && nativa["jalon-d1-0"]?["_ts"] == nil)
        #expect(!FileManager.default.fileExists(atPath: disco.url(SustitucionesServidor.archivoEncoladas(rutinaId: rutinaR1)).path))
        // En la nativa el cliente sustituye otro ejercicio.
        let propia: JSONValue = .objeto(["current": .objeto(["nombre": .texto("Nativa")]), "fijado": .bool(true), "_ts": .numero(500)])
        nativa["x-d1-1"] = propia
        disco.guardar(nativa, nombre)
        // Vuelve a la Capacitor: cambia la del jalón y agrega otra.
        try tel.webkit.escribir([clave: "{\"jalon-d1-0\":\(entrada("C")),\"nuevo-d2-0\":\(entrada("N"))}"])
        let momento = ahora.addingTimeInterval(3600)
        let r = try tel.faseL(en: momento)
        #expect(r.repeticion)
        let ms = momento.timeIntervalSince1970 * 1000
        let despues = try #require(disco.leer([String: JSONValue].self, nombre))
        #expect(despues["jalon-d1-0"]?["current"]?["nombre"]?.comoTexto == "C" && despues["jalon-d1-0"]?["_ts"] == .numero(ms.rounded(.down)))
        #expect(despues["nuevo-d2-0"]?["current"]?["nombre"]?.comoTexto == "N")
        #expect(despues["x-d1-1"] == propia, "lo hecho en la nativa quedó")
        // Lo que había quedó anotado como ya subido: al abrir, lo cambiado sale como guardado.
        #expect(disco.leer([String: JSONValue].self, SustitucionesServidor.archivoEncoladas(rutinaId: rutinaR1)) == nativa)
        // Otra vuelta: saca la nueva en la Capacitor y no toca la del jalón.
        try tel.webkit.escribir([clave: "{\"jalon-d1-0\":\(entrada("C"))}"])
        _ = try tel.faseL(en: momento.addingTimeInterval(3600))
        let otra = try #require(disco.leer([String: JSONValue].self, nombre))
        #expect(otra["nuevo-d2-0"] == nil, "lo que sacó en la app vieja se sacó")
        #expect(otra["jalon-d1-0"] == despues["jalon-d1-0"], "lo que no cambió ahí no se toca (ni su hora)")
        #expect(otra["x-d1-1"] == propia)
    }

    @Test func elTokenMarcadoInvalidoNoSeUsa() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_token_invalido": tokenA,
                                 "mypump_outbox_\(tokenA)": json(.lista(colaWeb(3)))])
        let r = try tel.faseL()
        #expect(!r.adoptoToken && r.tokenVigente == nil && tel.almacen.leer() == nil)
        #expect(r.plan?.tokenDescartado == true)
        // Su cola no se pierde ni se ejecuta: queda estacionada hasta saber de quién es.
        #expect(r.estacionadas == 3 && tel.cola().ops.isEmpty)
        #expect(tel.ajustes.string(forKey: "mypump_token_invalido") == tokenA)
        // Lo mismo si el que la nativa tiene marcado es el que dejó la Capacitor.
        let plan = MigracionLegado.planificar(["mypump_token": tokenB], ahora: ahora, contexto: ContextoMigracion(tokenInvalidoNativo: tokenB))
        #expect(plan.tokenVigente == nil && plan.tokenDescartado)
    }

    @Test func unicodeNulYUnMegaByteAByte() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let grande = String(repeating: "x", count: 1024 * 1024)
        let raro = "valor con \u{0} nulo, emoji 😀, acento á y \u{0}\u{0} al final\u{0}"
        try tel.webkit.escribir(["mypump_unicode_∂ñ😀": raro, "mypump_valor_grande": grande, "mypump_token": tokenA])
        let items = try claves(tel.webkit)
        #expect(items["mypump_unicode_∂ñ😀"] == raro)
        #expect(items["mypump_valor_grande"]?.utf16.count == 1024 * 1024 && items["mypump_valor_grande"] == grande)
        let lectura = try #require(try LectorLegado.leer(library: tel.webkit.library))
        #expect(lectura.firmas["mypump_unicode_∂ñ😀"] == FirmaValor.de(Array(raro.utf16)))
        // Una clave desconocida se cuenta, no se pierde (queda en la copia cruda) y no rompe nada.
        let r = try tel.faseL()
        #expect(r.plan?.conteos.desconocidas == 2)
    }

    @Test func elFormatoAnteriorTambienSeLee() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_tipo_dia": "descanso"], en: tel.webkit.dbAnterior)
        try tel.webkit.escribir(["mypump_tipo_dia": "entreno"])   // el nuevo es más reciente: gana
        let archivos = LectorLegado.ubicar(library: tel.webkit.library)
        #expect(archivos.map(\.formato) == [.anterior, .actual])
        let items = try claves(tel.webkit)
        #expect(items["mypump_token"] == tokenA && items["mypump_tipo_dia"] == "entreno")
    }

    /// TF-0, 14-oct: en el iPhone los archivos están en `Library/WebKit/WebsiteData` (sin el bundle en la ruta). La 2.0.0
    /// (100) los buscaba solo donde los deja el simulador, no encontró nada y mostró la bienvenida.
    @Test func enElIphoneLosEncuentraSinElBundleEnLaRuta() throws {
        let tel = Telefono(.telefono); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(3)))])
        let archivos = LectorLegado.ubicar(library: tel.webkit.library)
        #expect(archivos.map(\.ruta) == ["WebKit/WebsiteData/Default/HASH_ARRIBA/HASH_FRAME/LocalStorage/localstorage.sqlite3"])
        let r = try tel.faseL()
        #expect(r.huboLegado && r.corrio && r.adoptoToken && tel.almacen.leer() == tokenA)
        #expect(r.plan?.conteos.opsPorKind.values.reduce(0, +) == 3)
    }

    @Test func enElSimuladorTambien() throws {
        let tel = Telefono(.simulador); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA])
        try tel.webkit.escribir(["mypump_tipo_dia": "descanso"], en: tel.webkit.dbAnterior)
        let archivos = LectorLegado.ubicar(library: tel.webkit.library)
        #expect(archivos.map(\.formato) == [.anterior, .actual])
        #expect(archivos.allSatisfy { $0.ruta.hasPrefix("WebKit/\(LectorLegado.bundle)/WebsiteData/") })
        let r = try tel.faseL()
        #expect(r.adoptoToken && tel.almacen.leer() == tokenA)
    }

    /// Las dos a la vez no pasan en un teléfono, pero si pasaran se combinan como siempre: gana el archivo más nuevo.
    @Test func lasDosRutasJuntasSeCombinan() throws {
        let tel = Telefono(.telefono); defer { tel.limpiar() }
        let sim = WebKitFalso(tel.raiz, .simulador)
        try sim.escribir(["mypump_token": tokenB, "mypump_tipo_dia": "descanso"])
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: sim.dbActual.path + "-wal")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: sim.dbActual.path)
        try tel.webkit.escribir(["mypump_token": tokenA])
        let archivos = LectorLegado.ubicar(library: tel.webkit.library)
        #expect(archivos.count == 2 && archivos.last?.ruta.hasPrefix("WebKit/WebsiteData/") == true)
        let items = try claves(tel.webkit)
        #expect(items["mypump_token"] == tokenA && items["mypump_tipo_dia"] == "descanso")
    }

    // Las tres que tenía el gemelo de Android y faltaban acá (3b07452).

    /// La marca de OTRA migración (otro teléfono restaurado, otra instalación) no confirma nada.
    @Test func unaMarcaAjenaNoConfirmaLaEscritura() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let ajena = Marca(migracion: "99999999-9999-4999-8999-999999999999", corrida: 1, fecha: "2026-10-01T00:00:00Z", app: "2.0.0").texto
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_nativa_marca": ajena])
        let r = try tel.faseL()
        #expect(r.escrituraConfirmada == nil)
        let estado = try #require(tel.archivos.estado)
        #expect(estado.escrituraConfirmada == nil)
        #expect(estado.escritura != nil, "falta dejar la marca de esta migración")
        // La propia sí: con la de esta migración y nada para borrar, no queda escritura pendiente.
        try tel.webkit.escribir(["mypump_nativa_marca": Marca(migracion: estado.migracion, corrida: 1, fecha: "2026-10-14T15:00:00Z", app: nil).texto])
        let r2 = try tel.faseL()
        #expect(r2.escrituraConfirmada == 1)
        #expect(tel.archivos.estado?.escritura == nil)
    }

    /// Una cola que no es JSON no se importa ni se borra de la Capacitor (queda en la copia cruda y en el almacenamiento).
    @Test func unaColaIlegibleNoSeBorra() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": "[{roto"])
        let r = try tel.faseL()
        #expect(r.plan?.conteos.colasIlegibles == 1)
        #expect(tel.cola().ops.isEmpty)
        #expect(tel.archivos.estado?.escritura?.borrar["mypump_outbox_\(tokenA)"] == nil)
    }

    /// Sin almacenamiento viejo (hay un `origin` de la Capacitor pero ningún archivo de datos) no hace nada: ni copia ni
    /// estado, así el arranque de alguien que instaló la 2.0.0 de cero no deja rastros.
    @Test func sinLegadoNoHaceNada() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let r = try tel.faseL()
        #expect(!r.huboLegado && !r.corrio)
        #expect(!FileManager.default.fileExists(atPath: tel.entorno.carpeta.path))
    }

    @Test func sesionEnCursoVigenteYVencida() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let hace1h = ahoraMs - 3_600_000, hace7h = ahoraMs - 7 * 3_600_000
        let p = "mypump_sesion_\(tokenA)_"
        try tel.webkit.escribir([
            "mypump_token": tokenA,
            p + "b2d1": sesionS, p + "b2d1_semana": "3", p + "b2d1_start": String(Int(hace1h)),
            p + "b2d2": "otra", p + "b2d2_semana": "3", p + "b2d2_start": String(Int(hace7h)),
            p + "b2d3": "cerrada", p + "b2d3_semana": "3", p + "b2d3_start": String(Int(hace1h)), p + "b2d3_finalizada": "1",
            "mypump_rest_\(tokenA)": #"{"endsAt":\#(Int(ahoraMs) + 30_000),"target":90,"autoCloseAt":\#(Int(ahoraMs) + 32_000)}"#,
        ])
        let r = try tel.faseL()
        #expect(r.plan?.conteos.sesionesVigentes == 1 && r.plan?.conteos.sesionesVencidas == 2)
        let e = try #require(tel.disco().leer(EntrenoLegado.self, EntrenoLegado.archivo))
        #expect(e.sesiones.keys.sorted() == ["b2d1"])
        #expect(e.sesiones["b2d1"] == SesionLegada(sesionId: sesionS, semana: 3, start: hace1h, finalizada: false))
        #expect(e.descanso?.target == 90)
        // Los cachés de sesión se borran de la Capacitor en la escritura de vuelta (todos, vigentes o no).
        #expect(tel.archivos.estado?.escritura?.borrar.keys.filter { $0.hasPrefix("mypump_sesion_") }.count == 10)

        // Un descanso que ya terminó no se trae.
        let viejo = MigracionLegado.planificar(["mypump_token": tokenA, "mypump_rest_\(tokenA)": #"{"endsAt":1,"target":90,"autoCloseAt":2}"#], ahora: ahora)
        #expect(viejo.entreno?.descanso == nil && !viejo.conteos.descansoVigente)
    }

    @Test func temaClaroNoEsUnaEleccionOscuroSi() throws {
        let claro = MigracionLegado.planificar(["mypump-theme": "light"], ahora: ahora)
        #expect(claro.preferencias["mypump-theme"] == nil)
        let oscuro = MigracionLegado.planificar(["mypump-theme": "dark"], ahora: ahora)
        #expect(oscuro.preferencias["mypump-theme"] == "dark")

        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump-theme": "dark", "mypump_tipo_dia": "descanso", "mypump_notif_prefs": #"{"check":{"on":false,"hora":9,"min":30}}"#,
                                 "mypump_notif_pedido": "1", "mypump_onboarding_v1": "1", "mypump_health_connected": "1",
                                 "mypump_health_backfill_off": #"{"off":20,"alcance":60}"#, "mypump_health_last_sync": "2026-10-13T22:00:00.000Z",
                                 "mypump_health_diag": #"{"x":1}"#])
        tel.ajustes.set("entreno", forKey: "mypump_tipo_dia")   // la nativa ya tenía uno: gana el suyo
        _ = try tel.faseL()
        #expect(tel.ajustes.string(forKey: "mypump-theme") == "dark")
        #expect(tel.ajustes.string(forKey: "mypump_tipo_dia") == "entreno")
        #expect(tel.ajustes.string(forKey: "mypump_notif_prefs") == #"{"check":{"on":false,"hora":9,"min":30}}"#)
        #expect(tel.ajustes.string(forKey: "mypump_notif_pedido") == "1" && tel.ajustes.string(forKey: "mypump_onboarding_v1") == "1")
        #expect(tel.ajustes.string(forKey: "mypump_health_connected") == "1")
        #expect(tel.ajustes.string(forKey: "mypump_health_backfill_off") == #"{"off":20,"alcance":60}"#)
        #expect(tel.ajustes.string(forKey: "mypump_health_last_sync") == "2026-10-13T22:00:00.000Z")
        #expect(tel.ajustes.string(forKey: "mypump_health_diag") == nil)
    }

    @Test func dosCorridasDanLoMismo() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(120))),
                                 "mypump_outbox_\(tokenB)": json(.lista(colaWeb(5, t0: 9))), "mypump_outbox_anon": json(.lista(colaWeb(2, t0: 7))),
                                 "mypump_tipo_dia": "entreno"])
        let r1 = try tel.faseL()
        let cola1 = tel.cola(), libro1 = tel.archivos.libro, pendientes1 = tel.archivos.pendientes
        // Mismos archivos: ni siquiera corre.
        let r2 = try tel.faseL()
        #expect(r1.corrio && !r2.corrio)
        // Y si corre igual (la huella se movió sin cambiar nada), el libro mayor no deja duplicar.
        try tel.webkit.escribir([:])
        let r3 = try tel.faseL()
        #expect(r3.corrio && r3.repeticion && r3.aLaCola == 0 && r3.porValidar == 0 && r3.estacionadas == 0 && r3.anon == 0)
        #expect(r3.yaEnElLibro == 127)
        #expect(tel.cola().ops == cola1.ops)
        #expect(tel.archivos.libro.mapValues(\.destino) == libro1.mapValues(\.destino))
        #expect(tel.archivos.pendientes.map(\.ops) == pendientes1.map(\.ops))
        #expect(tel.archivos.estado?.corridas == 2)
    }

    @Test func seRepiteCuandoCambiaLaHuellaYSoloTraeLoNuevo() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let base = colaWeb(20)
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(base)), "mypump_tipo_dia": "entreno"])
        _ = try tel.faseL()
        let antes = tel.cola().ops.count
        // La nativa cambia el tipo de día; después el cliente vuelve a la Capacitor (plan B) y carga dos cosas más.
        tel.ajustes.set("descanso", forKey: "mypump_tipo_dia")
        let nuevas = colaWeb(2, t0: 1_792_000_000_000).map { op -> JSONValue in
            guard case .objeto(var o) = op else { return op }
            o["dedupeKey"] = .texto("nueva-\(o["ts"]?.comoNumero ?? 0)")
            return .objeto(o)
        }
        try tel.webkit.escribir(["mypump_outbox_\(tokenA)": json(.lista(base + nuevas))])
        let r = try tel.faseL()
        #expect(r.corrio && r.repeticion)
        #expect(r.yaEnElLibro == 20 && r.aLaCola + r.porValidar == 2)
        #expect(tel.cola().ops.count == antes + r.aLaCola)
        // El tipo de día no cambió en la Capacitor: no pisa lo que eligió en la nativa.
        #expect(tel.ajustes.string(forKey: "mypump_tipo_dia") == "descanso")
        // Si lo cambia en la Capacitor, es lo último que hizo: gana.
        try tel.webkit.escribir(["mypump_tipo_dia": "refeed"])
        _ = try tel.faseL()
        #expect(tel.ajustes.string(forKey: "mypump_tipo_dia") == "refeed")
    }

    @Test func unaOpViejaNoPisaAUnaNativaMasNueva() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        // La nativa ya tiene pendiente el agua de hoy, cargada DESPUÉS que la de la Capacitor.
        let nativa = Operacion(id: "nativa_1", kind: "habito", payload: .objeto(["fecha": .texto("2026-10-14"), "campo": .texto("vasos_agua"), "valor": .texto("6")]),
                               dedupeKey: "habito|2026-10-14|vasos_agua", ts: 2_000_000_000_000)
        _ = try Outbox.importarEnArchivo(tel.disco().url("outbox.json"), [nativa])
        let vieja: JSONValue = .objeto(["_id": .texto("1_1"), "kind": .texto("habito"), "dedupeKey": .texto("habito|2026-10-14|vasos_agua"),
                                        "payload": .objeto(["fecha": .texto("2026-10-14"), "campo": .texto("vasos_agua"), "valor": .texto("2")]),
                                        "tries": .numero(0), "ts": .numero(1_791_000_000_000)])
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista([vieja]))])
        let r = try tel.faseL()
        #expect(r.reemplazadas == 1 && r.aLaCola == 0)
        #expect(tel.cola().ops.map(\.id) == ["nativa_1"])
        #expect(tel.archivos.libro.values.first?.destino == .reemplazada)
    }

    @Test func unSurrogateSueltoNoTiraLaColaEntera() throws {
        // `'chat_' + Date.now() + '_' + contenido.slice(0, 40)` puede cortar un emoji a la mitad, y JSON.stringify lo
        // escribe como `\ud83d` suelto. JSONDecoder rechazaba el array entero.
        let contenido = String(repeating: "a", count: 39) + "😀 y sigue"
        let roto = #"[{"_id":"1_1","kind":"chat","payload":{"contenido":"\#(contenido)"},"dedupeKey":"chat_1_\#(String(repeating: "a", count: 39))\ud83d","tries":0,"ts":1},"#
            + #"{"_id":"2_2","kind":"peso","payload":{"fecha":"2026-10-13","valor":80},"dedupeKey":"peso_2026-10-13","tries":0,"ts":2},"#
            + #"{"_id":"3_3","kind":"chat","payload":{"contenido":"barra \\ud83d literal"},"dedupeKey":"x\udc00y","tries":0,"ts":3}]"#
        #expect((try? JSONDecoder().decode(JSONValue.self, from: Data(roto.utf8))) == nil)   // lo que pasaba
        let plan = MigracionLegado.planificar(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": roto], ahora: ahora)
        let ops = try #require(plan.colas.first).ops
        #expect(ops.count == 3)
        #expect(ops[0].operacion.payload["contenido"]?.comoTexto == contenido)
        #expect(ops[0].operacion.dedupeKey == "chat_1_" + String(repeating: "a", count: 39) + "\u{FFFD}")
        #expect(ops[2].operacion.payload["contenido"]?.comoTexto == #"barra \ud83d literal"#)   // una barra escapada no es un escape
        #expect(ops[2].operacion.dedupeKey == "x\u{FFFD}y")
    }

    @Test func fotosYSwapsDeComidaQuedanParaSusModelos() throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let foto = "data:image/jpeg;base64,/9j/" + String(repeating: "A", count: 2000)
        try tel.webkit.escribir([
            "mypump_token": tokenA,
            "mypump_fotoq_\(tokenA)": #"{"2026-10-12|frente":{"pose":"frente","fecha":"2026-10-13","dataUrl":"\#(foto)","intentos":1},"#
                + #""2026-09-28|perfil":{"pose":"perfil","fecha":"2026-09-30","dataUrl":"\#(foto)","intentos":0},"#
                + #""2026-10-12|espalda":{"pose":"espalda","fecha":"2026-10-13","intentos":0}}"#,
            "mypump_food_swaps_\(dietaD)": #"{"swap_\#(dietaD)_desayuno_0_1":{"original":{"name":"Queso"},"current":{"name":"Ricota","qty":150}}}"#,
            "mypump_food_swaps_otra-dieta": #"{"swap_otra-dieta_cena_0_0":{"original":null,"current":{"name":"Pollo"}}}"#,
            "mypump_swaps_migrados_otra-dieta": "1",
        ])
        let r = try tel.faseL()
        let fotos = try #require(tel.disco().leer([String: FotoPendiente].self, FotoPendiente.archivo))
        #expect(fotos.keys.sorted() == ["2026-09-28|perfil", "2026-10-12|frente"])   // sin dataUrl la web la tira
        #expect(fotos["2026-10-12|frente"] == FotoPendiente(pose: "frente", fecha: "2026-10-13", dataUrl: foto, intentos: 1))
        #expect(r.plan?.conteos.fotosFueraDeVentana == 1)
        // Los swaps de comida sin migrar quedan donde los busca ModeloApp, sin la marca: su hidratación los sube.
        let swaps = try #require(tel.disco().leer([String: SwapLocal].self, "swaps_\(dietaD).json"))
        #expect(swaps["swap_\(dietaD)_desayuno_0_1"]?.current["name"]?.comoTexto == "Ricota")
        #expect(tel.disco().leer(Bool.self, "swaps_migrados_\(dietaD)") == nil)
        #expect(tel.disco().leer(Bool.self, "swaps_migrados_otra-dieta") == true)
    }

    @Test func sustitucionSinFijadoCuentaComoFijada() throws {
        let s = MigracionLegado.leerSustituciones(#"""
        {"a-d1-0":{"original":{"slug":"Wide-Grip_Lat_Pulldown","nombre":"Jalón al pecho","images":null},"current":{"slug":"Seated_Cable_Rows","nombre":"Remo","equipment":"cable","images":{"eccentric":"https://x/e.jpg","_matched_slug":"Seated_Cable_Rows"}},"fijado":false,"semana":"3","diaId":"b2d1"},
         "b-d2-1":{"original":{"slug":"x","nombre":"Press"},"current":{"slug":"y","nombre":"Press Smith 🏋️"},"semana":1,"diaId":"b2d2"},
         "c-d3-2":{"original":{"nombre":"Curl"},"current":{"nombre":"Curl sentado"},"fijado":null},
         "roto":{"original":{"nombre":"sin current"}}}
        """#)
        #expect(s.keys.sorted() == ["a-d1-0", "b-d2-1", "c-d3-2"])
        #expect(s["a-d1-0"]?.fijado == false && s["a-d1-0"]?.semana == 3 && s["a-d1-0"]?.current.images?["_matched_slug"]?.comoTexto == "Seated_Cable_Rows")
        #expect(s["b-d2-1"]?.fijado == true && s["b-d2-1"]?.current.nombre == "Press Smith 🏋️")
        #expect(s["c-d3-2"]?.fijado == false)   // `null` no es `undefined`: la web lo deja como no fijado
    }

    @Test func conLaColaVivaTodoPasaPorLaFaseR() throws {
        // El modelo ya existía (la Fase L se demoró): su cola está viva y escribir el archivo la pisaría.
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(18)))])
        tel.almacen.guardar(tokenA)
        let r = try tel.faseL(cuentaViva: tokenA)
        #expect(r.aLaCola == 0 && r.porValidar == 18)
        #expect(!FileManager.default.fileExists(atPath: tel.disco().url("outbox.json").path))
        #expect(tel.archivos.pendientes.first?.ops.count == 18)
    }
}

@Suite("Migración: la Fase R")
@MainActor
struct FaseRemotaLegadoTests {
    private func cola(_ tel: Telefono, _ cliente: ClienteRPC) -> Outbox {
        let escrituras = Escrituras(cliente: cliente, token: tokenA)
        return Outbox(archivo: tel.disco().url("outbox.json"), reintentoAutomatico: false) { op in await escrituras.ejecutar(op) }
    }

    @Test func lasSinSesionContraOtraRutinaVanAFallidos() async throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(18))),
                                 "mypump_offline_\(tokenA)": fotoOffline(rutina: rutinaR1)])
        _ = try tel.faseL()
        // Mati activó otro bloque: la rutina activa ya no es la de la foto.
        let llamadas = Llamadas()
        let cliente = servidor(llamadas, activa: rutinaR2)
        let o = cola(tel, cliente)
        let r = await FaseRemotaLegado.correr(entorno: tel.entorno, token: tokenA, clienteId: "test-nativa-ios", cliente: cliente, outbox: o,
                                              recibo: ReciboEnDisco(carpeta: tel.entorno.carpeta.appendingPathComponent("recibos")), ahora: ahora, zona: baires)
        #expect(r.paraRevisar == 2 && r.aLaCola == 0 && !r.sinRed)
        let f = await o.fallidos
        #expect(f.count == 2 && f.allSatisfy { $0.motivo == "para revisar: la rutina activa ya no es la de la foto" })
        #expect(f.allSatisfy { ["carga", "estado"].contains($0.op.kind) && $0.op.payload["sesionId"] == .null })
        // Nunca se creó una sesión para ellas.
        let iniciadas = await llamadas.de("mypump_iniciar_sesion"), buscadas = await llamadas.de("mypump_get_sesion_dia")
        #expect(iniciadas.isEmpty && buscadas.isEmpty)
        #expect(tel.archivos.libro.values.filter { $0.destino == .paraRevisar }.count == 2)
        #expect(tel.archivos.pendientes.isEmpty)
        #expect(tel.archivos.estado?.faseRPendiente == false)
    }

    @Test func lasSinSesionDeLaMismaRutinaSeMandanYLasDeUnDiaQueNoEstaNo() async throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(18))),
                                 "mypump_offline_\(tokenA)": fotoOffline(rutina: rutinaR1)])
        _ = try tel.faseL()
        let llamadas = Llamadas()
        // Misma rutina, pero Mati sacó el día b2d2 al republicarla.
        let cliente = ClienteRPC(transporte: ServidorLegado(llamadas: llamadas) { fn, p in
            switch fn {
            case "mypump_get_rutina_activa": return (200, rutinaActiva(rutinaR1, dias: ["b2d1", "b2d3"]))
            case "mypump_get_sesion_dia": return (200, "[]")
            case "mypump_iniciar_sesion": return (200, #""99999999-0000-4000-8000-000000000001""#)
            case "mypump_ingest_salud": return (200, "1")
            case "mypump_delete_food_swap", "mypump_desmarcar_comida": return (200, "true")
            default: return (200, #"[{"ok":true}]"#)
            }
        })
        let o = cola(tel, cliente)
        let r = await FaseRemotaLegado.correr(entorno: tel.entorno, token: tokenA, clienteId: "test-nativa-ios", cliente: cliente, outbox: o,
                                              recibo: ReciboEnDisco(carpeta: tel.entorno.carpeta.appendingPathComponent("recibos")), ahora: ahora, zona: baires)
        // colaWeb(18): las sin sesión son carga i=9 (b2d1) y estado i=1 (b2d2).
        #expect(r.aLaCola == 1 && r.paraRevisar == 1)
        #expect(await o.fallidos.first?.motivo == "para revisar: el día no está en la rutina activa")
        // Se mandó por la cola normal (resolveSesion: get_sesion_dia → iniciar_sesion → registrar_carga), con las demás.
        let cargas = await llamadas.de("mypump_registrar_carga")
        #expect(cargas.contains { $0["p_sesion_id"]?.comoTexto == "99999999-0000-4000-8000-000000000001" && $0["p_dia_id"]?.comoTexto == "b2d1" })
        #expect(await llamadas.de("mypump_iniciar_sesion").count == 1)
        #expect(await o.pendientes == 0)
        // El recibo quedó en disco, sin contenido crudo.
        let recibo = try String(contentsOf: tel.entorno.carpeta.appendingPathComponent("recibos/recibo-1.json"), encoding: .utf8)
        #expect(!recibo.contains(tokenA) && !recibo.contains("Press inclinado") && recibo.contains("\"paraRevisar\":1"))
        #expect(r.recibo == .soloLocal)
    }

    @Test func colaDeUnTokenRotado() async throws {
        for (caso, clientes, esperado) in [("mismo", [tokenA: "c1", tokenB: "c1"], "reasignada"),
                                           ("otro", [tokenA: "c1", tokenB: "c2"], "otroCliente"),
                                           ("revocado", [tokenA: "c1"], "noResuelve")] {
            let tel = Telefono(); defer { tel.limpiar() }
            let foto = "data:image/jpeg;base64,/9j/AAAA"
            try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenB)": json(.lista(colaWeb(9, t0: 50))),
                                     "mypump_offline_\(tokenB)": fotoOffline(rutina: rutinaR1),
                                     "mypump_fotoq_\(tokenB)": #"{"2026-10-12|frente":{"pose":"frente","fecha":"2026-10-13","dataUrl":"\#(foto)","intentos":0}}"#])
            let l = try tel.faseL()
            #expect(l.estacionadas == 9, "\(caso)")
            let llamadas = Llamadas()
            let cliente = servidor(llamadas, clientes: clientes)
            let o = cola(tel, cliente)
            let r = await FaseRemotaLegado.correr(entorno: tel.entorno, token: tokenA, clienteId: "c1", cliente: cliente, outbox: o,
                                                  recibo: ReciboEnDisco(carpeta: tel.entorno.carpeta.appendingPathComponent("recibos")), ahora: ahora, zona: baires)
            let destinos = Set(tel.archivos.libro.values.map(\.destino.rawValue))
            let fotos = tel.disco().leer([String: FotoPendiente].self, FotoPendiente.archivo) ?? [:]
            switch esperado {
            case "reasignada":
                #expect(r.reasignadas == 9 && destinos == ["reasignada"])
                let cargas = await llamadas.de("mypump_registrar_carga"), chats = await llamadas.de("mypump_agregar_comentario")
                #expect(cargas.count == 1 && chats.count == 1)
                #expect(fotos.count == 1)
                #expect(tel.archivos.pendientes.isEmpty)
                // Ya es de esta cuenta: la escritura de vuelta saca su cola de la Capacitor.
                #expect(tel.archivos.estado?.escritura?.borrar["mypump_outbox_\(tokenB)"] != nil)
            default:
                #expect(r.reasignadas == 0 && destinos == [esperado], "\(caso)")
                let cargas = await llamadas.de("mypump_registrar_carga"), quedan = await o.pendientes
                #expect(cargas.isEmpty && quedan == 0, "\(caso)")
                #expect(fotos.isEmpty, "\(caso)")
                #expect(tel.archivos.pendientes.first?.estado.rawValue == esperado, "\(caso)")
                #expect(tel.archivos.estado?.escritura?.borrar["mypump_outbox_\(tokenB)"] == nil, "\(caso)")
            }
            // Nunca se preguntó con el token de otra persona más que para saber de quién era.
            #expect(await llamadas.de("mypump_get_cliente_info").allSatisfy { $0["p_token"]?.comoTexto == tokenB })
        }
    }

    @Test func sinRedQuedaPendienteYNoSeEscribeDeVuelta() async throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(10)))])
        _ = try tel.faseL()
        struct SinRed: Transporte { func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) } }
        let cliente = ClienteRPC(transporte: SinRed())
        let o = cola(tel, cliente)
        let r = await FaseRemotaLegado.correr(entorno: tel.entorno, token: tokenA, clienteId: "c1", cliente: cliente, outbox: o,
                                              recibo: ReciboEnDisco(carpeta: tel.entorno.carpeta.appendingPathComponent("recibos")), ahora: ahora)
        #expect(r.sinRed && r.recibo == nil)
        #expect(tel.archivos.pendientes.first?.ops.count == 2)
        #expect(FaseRemotaLegado.escrituraPendiente(entorno: tel.entorno) == nil)   // la Fase R no terminó
        #expect(FaseRemotaLegado.hayPendiente(entorno: tel.entorno))
    }

    @Test func escrituraDeVueltaConfirmadaEnElArranqueSiguiente() async throws {
        let tel = Telefono(); defer { tel.limpiar() }
        let p = "mypump_sesion_\(tokenA)_"
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(12))), "mypump_outbox_anon": json(.lista(colaWeb(2))),
                                 "mypump_offline_\(tokenA)": fotoOffline(rutina: rutinaR1), p + "b2d1": sesionS, p + "b2d1_semana": "3",
                                 "mypump_tipo_dia": "entreno"])
        _ = try tel.faseL()
        let llamadas = Llamadas()
        let cliente = servidor(llamadas)
        let o = cola(tel, cliente)
        _ = await FaseRemotaLegado.correr(entorno: tel.entorno, token: tokenA, clienteId: "test-nativa-ios", cliente: cliente, outbox: o,
                                          recibo: ReciboEnDisco(carpeta: tel.entorno.carpeta.appendingPathComponent("recibos")), ahora: ahora)
        let cambios = try #require(FaseRemotaLegado.escrituraPendiente(entorno: tel.entorno, app: "2.0.0 (100)", ahora: ahora))
        #expect(Set(cambios.borrar.keys) == ["mypump_outbox_\(tokenA)", p + "b2d1", p + "b2d1_semana"])

        // La escritura de vuelta, con el MISMO script que corre en el WebView, sobre un localStorage hecho con el archivo.
        var ls = try claves(tel.webkit)
        ls[p + "b2d1_semana"] = "4"   // cambió después de leerla: no se borra
        let resultado = try correrScript(cambios, en: &ls)
        #expect(resultado == ["mypump_outbox_\(tokenA)": "borrada", p + "b2d1": "borrada", p + "b2d1_semana": "cambio", "mypump_nativa_marca": "ok"])
        FaseRemotaLegado.registrarEscritura(entorno: tel.entorno, cambios: cambios, resultado: resultado)
        #expect(tel.archivos.estado?.escrituraHecha == 1 && tel.archivos.estado?.escritura == nil)

        // El archivo de WebKit queda como lo bajaría el WebView.
        let antes = try claves(tel.webkit)
        let borradas = antes.keys.filter { ls[$0] == nil }
        try tel.webkit.escribir(ls.filter { antes[$0.key] != $0.value }, borrar: borradas)

        // Arranque siguiente: la Ruta B lee la marca y lo confirma; no hay nada nuevo para traer.
        let r = try tel.faseL()
        #expect(r.corrio && r.escrituraConfirmada == 1)
        #expect(r.aLaCola == 0 && r.porValidar == 0 && r.anon == 0 && r.yaEnElLibro == 2)   // solo queda la anon (no se toma)
        let estado = try #require(tel.archivos.estado)
        #expect(estado.escrituraConfirmada == 1)
        #expect(estado.escritura?.borrar.keys.sorted() == [p + "b2d1_semana"])   // lo que cambió se reintenta
        #expect(Marca.leer(try claves(tel.webkit)["mypump_nativa_marca"])?.migracion == estado.migracion)
    }

    @Test func siLaEscrituraNoLlegoAlDiscoSeRepite() async throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(3)))])
        _ = try tel.faseL()
        let cliente = servidor(Llamadas())
        _ = await FaseRemotaLegado.correr(entorno: tel.entorno, token: tokenA, clienteId: "test-nativa-ios", cliente: cliente, outbox: cola(tel, cliente),
                                          recibo: ReciboEnDisco(carpeta: tel.entorno.carpeta.appendingPathComponent("recibos")), ahora: ahora)
        let cambios = try #require(FaseRemotaLegado.escrituraPendiente(entorno: tel.entorno))
        FaseRemotaLegado.registrarEscritura(entorno: tel.entorno, cambios: cambios, resultado: ["mypump_nativa_marca": "ok"])
        #expect(FaseRemotaLegado.escrituraPendiente(entorno: tel.entorno) == nil)
        // El proceso murió antes de que WebKit bajara al disco: los archivos no cambiaron.
        let r = try tel.faseL()
        #expect(!r.corrio)
        #expect(FaseRemotaLegado.escrituraPendiente(entorno: tel.entorno)?.borrar == cambios.borrar)
    }

    /// Si la marca no quedó escrita (el WebView contestó "fallo"), la escritura no cuenta como hecha: sigue pendiente.
    @Test func sinLaMarcaLaEscrituraSiguePendiente() async throws {
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(3)))])
        _ = try tel.faseL()
        let cliente = servidor(Llamadas())
        _ = await FaseRemotaLegado.correr(entorno: tel.entorno, token: tokenA, clienteId: "test-nativa-ios", cliente: cliente, outbox: cola(tel, cliente),
                                          recibo: ReciboEnDisco(carpeta: tel.entorno.carpeta.appendingPathComponent("recibos")), ahora: ahora)
        let cambios = try #require(FaseRemotaLegado.escrituraPendiente(entorno: tel.entorno))
        FaseRemotaLegado.registrarEscritura(entorno: tel.entorno, cambios: cambios,
                                            resultado: ["mypump_outbox_\(tokenA)": "borrada", "mypump_nativa_marca": "fallo"])
        #expect(tel.archivos.estado?.escrituraHecha == nil)
        #expect(FaseRemotaLegado.escrituraPendiente(entorno: tel.entorno)?.borrar == cambios.borrar)
    }

    /// Con el recibo confirmado por el servidor, la copia cruda se borra a los 90 días (y antes no).
    @Test func laCopiaCrudaSeBorraNoventaDiasDespuesDelReciboConfirmado() async throws {
        struct Confirma: ReciboMigracion { func enviar(_ r: ReciboLegado, token: String) async -> EntregaRecibo { .confirmado } }
        let tel = Telefono(); defer { tel.limpiar() }
        try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista(colaWeb(3)))])
        _ = try tel.faseL()
        let cliente = servidor(Llamadas())
        let r = await FaseRemotaLegado.correr(entorno: tel.entorno, token: tokenA, clienteId: "test-nativa-ios", cliente: cliente,
                                              outbox: cola(tel, cliente), recibo: Confirma(), ahora: ahora)
        #expect(r.recibo == .confirmado)
        let copias = try #require(tel.archivos.estado?.copias)
        #expect(copias.count == 1)
        let copia = tel.entorno.carpeta.appendingPathComponent(copias[0])
        FaseRemotaLegado.podarCopias(entorno: tel.entorno, ahora: ahora.addingTimeInterval(89 * 86_400))
        #expect(FileManager.default.fileExists(atPath: copia.path))
        FaseRemotaLegado.podarCopias(entorno: tel.entorno, ahora: ahora.addingTimeInterval(91 * 86_400))
        #expect(!FileManager.default.fileExists(atPath: copia.path))
        #expect(tel.archivos.estado?.copias.isEmpty == true)
    }

    @Test func losSwapsDeComidaSinMigrarSeSubenAntesDeDrenar() async throws {
        // Un teléfono de la v1.0.11 (sin la marca de migrados) con un swap local que el servidor nunca vio, y en la cola
        // vieja un swap de OTRA posición. Si la Fase R drenara primero, la hidratación del modelo vería el servidor con
        // algo, tomaría el merge y tiraría el local (lo vio la prueba en el simulador). Se decide antes de drenar.
        for (caso, servidorTiene, marcaNativa, esperado) in [("vacío", false, false, 1), ("ya tiene uno", true, false, 0),
                                                           ("marca nativa", false, true, 0)] {
            let tel = Telefono(); defer { tel.limpiar() }
            let c1: JSONValue = .objeto(["_id": .texto("1_1"), "kind": .texto("swap"), "dedupeKey": .texto("swap_\(dietaD)_c1_0_0"),
                                         "payload": .objeto(["dietaId": .texto(dietaD), "comidaId": .texto("c1"), "optIdx": .numero(0), "foodIdx": .numero(0),
                                                             "food": .objeto(["name": .texto("Ricota"), "_orig": .objeto(["name": .texto("Pollo")])])]),
                                         "tries": .numero(0), "ts": .numero(1)])
            try tel.webkit.escribir(["mypump_token": tokenA, "mypump_outbox_\(tokenA)": json(.lista([c1])),
                                     "mypump_food_swaps_\(dietaD)": #"{"swap_\#(dietaD)_c3_0_0":{"original":{"name":"Merluza"},"current":{"name":"Atún","_orig":{"name":"Merluza","qty":250,"unit":"g"}}}}"#])
            _ = try tel.faseL()
            if marcaNativa { tel.disco().guardar(true, "swaps_migrados_\(dietaD)") }
            let base = BaseDeSwaps(servidorTiene ? ["c4/0/0"] : [])
            let cliente = ClienteRPC(transporte: base)
            let escrituras = Escrituras(cliente: cliente, token: tokenA)
            let o = Outbox(archivo: tel.disco().url("outbox.json"), reintentoAutomatico: false) { op in await escrituras.ejecutar(op) }
            let r = await FaseRemotaLegado.correr(entorno: tel.entorno, token: tokenA, clienteId: "c1", cliente: cliente, outbox: o,
                                                  recibo: ReciboEnDisco(carpeta: tel.entorno.carpeta.appendingPathComponent("recibos")), ahora: ahora)
            #expect(r.swapsSinMigrar == esperado, "\(caso)")
            await o.drenar()
            let enLaBase = await base.claves()
            #expect(enLaBase.contains("c1/0/0"), "\(caso)")   // el de la cola vieja sale siempre
            #expect(enLaBase.contains("c3/0/0") == (esperado == 1), "\(caso)")
            // Y la hidratación del modelo, corra cuando corra, ya no lo pierde: o está en la base o está en la cola.
            let pendientes = (await o.pendientesPorClave()).mapValues(\.kind)
            let remotos = await base.filas()
            let locales = tel.disco().leer([String: SwapLocal].self, "swaps_\(dietaD).json") ?? [:]
            let h = SwapsDeComida.hidratar(remotos: remotos, locales: locales, dietaId: dietaD, pendientes: pendientes,
                                           yaMigrado: tel.disco().leer(Bool.self, "swaps_migrados_\(dietaD)") ?? false, enPosicion: { _, _, _ in [] })
            if esperado == 1 { #expect(h?.swaps["swap_\(dietaD)_c3_0_0"] != nil, "\(caso)") }
        }
    }

    @Test func elScriptCalculaLaMismaFirmaQueSwift() throws {
        // El FNV-1a de JavaScript (charCodeAt + Math.imul) tiene que dar lo mismo que el de Swift, también con emoji,
        // nulos y surrogates sueltos (que en Swift solo existen como unidades UTF-16).
        let ctx = try #require(JSContext())
        ctx.evaluateScript("function firma(s){let h=0x811c9dc5;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,0x01000193);}return [s.length,h>>>0];}")
        for s in ["", "a", "Mati, ¿cambio el jalón? 😀", "nulo\u{0}adentro", String(repeating: "x", count: 100_000)] {
            let r = try #require(ctx.objectForKeyedSubscript("firma").call(withArguments: [s])?.toArray())
            let f = FirmaValor.de(Array(s.utf16))
            #expect((r[0] as? NSNumber)?.intValue == f.unidades && (r[1] as? NSNumber)?.uint32Value == f.fnv)
        }
        let suelto = try #require(ctx.evaluateScript(#"firma("a\ud83db")"#)?.toArray())
        let f = FirmaValor.de([0x61, 0xD83D, 0x62] as [UInt16])
        #expect((suelto[1] as? NSNumber)?.uint32Value == f.fnv)
    }
}

/// Corre `scriptEscritura` con JavaScriptCore sobre un `localStorage` en memoria.
@MainActor
private func correrScript(_ c: FaseRemotaLegado.CambiosEscritura, en ls: inout [String: String]) throws -> [String: String] {
    let ctx = try #require(JSContext())
    let almacen = NSMutableDictionary(dictionary: ls)
    let get: @convention(block) (String) -> Any = { k in almacen[k] ?? NSNull() }
    let set: @convention(block) (String, String) -> Void = { k, v in almacen[k] = v }
    let remove: @convention(block) (String) -> Void = { k in almacen.removeObject(forKey: k) }
    let local = JSValue(newObjectIn: ctx)!
    local.setObject(get, forKeyedSubscript: "getItem" as NSString)
    local.setObject(set, forKeyedSubscript: "setItem" as NSString)
    local.setObject(remove, forKeyedSubscript: "removeItem" as NSString)
    ctx.setObject(local, forKeyedSubscript: "localStorage" as NSString)
    ctx.exceptionHandler = { _, e in Issue.record("JS: \(e?.toString() ?? "?")") }
    let f = ctx.evaluateScript("(function(borrar, marca) {\n\(FaseRemotaLegado.scriptEscritura)\n})")!
    let args = FaseRemotaLegado.argumentosEscritura(c)
    let r = f.call(withArguments: [args["borrar"]!, args["marca"]!])
    ls = (almacen as? [String: String]) ?? [:]
    return (r?.toDictionary() as? [String: String]) ?? [:]
}
