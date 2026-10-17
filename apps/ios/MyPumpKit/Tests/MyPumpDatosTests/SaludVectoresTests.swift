import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

// La nativa contra el bridge REAL de la web (scripts/nativa/vectores-salud.mjs): las mismas respuestas del plugin, en el
// mismo orden, tienen que dar las MISMAS consultas (ventanas al milisegundo), los MISMOS lotes a la base, el mismo
// resultado y el mismo estado guardado. Igualdad total: sin tolerancias.

private let raizRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

struct ArchivoSalud: Decodable {
    let fuente: String
    let casos: [CasoSalud]
}

struct CasoSalud: Decodable {
    let nombre: String
    let accion: String
    let tz: String
    let ahora: Double
    let fuentes: [[String]]
    let estadoInicial: [String: String]
    let consultas: [JSONValue]
    let rpc: [JSONValue]
    let resultado: JSONValue
    let progreso: [[Int]]
    let estadoFinal: [String: String]
    let diag: JSONValue?
}

func cargarSalud(_ nombre: String) throws -> ArchivoSalud {
    try JSONDecoder().decode(ArchivoSalud.self, from: Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/\(nombre).json")))
}

/// Hace de plugin: contesta lo que contestó el plugin imitado, en orden, y anota cualquier consulta distinta.
final class FuenteGrabada: FuenteSalud, @unchecked Sendable {
    let iosMayor = 18
    private let consultas: [JSONValue]
    private let fuentes: [[String]]
    private var i = 0
    private(set) var fallas: [String] = []
    private let candado = NSLock()

    init(_ c: CasoSalud) { consultas = c.consultas; fuentes = c.fuentes }

    var pendientes: Int { candado.withLock { consultas.count - i } }

    private func siguiente(_ m: String, _ chequear: (JSONValue) -> String?) throws -> JSONValue {
        try candado.withLock {
            guard i < consultas.count else {
                fallas.append("consulta de más: \(m)")
                throw ErrorFuenteSalud("de más")
            }
            let e = consultas[i]
            i += 1
            if e["m"]?.comoTexto != m {
                fallas.append("#\(i - 1): la web hizo \(e["m"]?.comoTexto ?? "?"), la nativa \(m)")
                throw ErrorFuenteSalud("orden")
            }
            if let dif = chequear(e) { fallas.append("#\(i - 1) \(m): \(dif)") }
            if let err = e["error"]?.comoTexto { throw ErrorFuenteSalud(err) }
            return e
        }
    }

    private func textos(_ j: JSONValue?) -> [String] {
        guard case .lista(let a) = j else { return [] }
        return a.compactMap(\.comoTexto)
    }

    private func ventana(_ e: JSONValue, _ desde: Double, _ hasta: Double) -> String? {
        e["desde"]?.comoNumero == desde && e["hasta"]?.comoNumero == hasta ? nil
            : "ventana web \(e["desde"]?.comoNumero ?? -1)…\(e["hasta"]?.comoNumero ?? -1), nativa \(desde)…\(hasta)"
    }

    private func muestra(_ fila: JSONValue, sueno: Bool) -> MuestraSalud {
        guard case .lista(let a) = fila else { return MuestraSalud(inicio: 0, fin: 0, valor: 0, fuenteId: "", fuenteNombre: "") }
        let f = Int(a[3].comoNumero ?? 0)
        return MuestraSalud(inicio: a[0].comoNumero ?? 0, fin: a[1].comoNumero ?? 0, valor: a[2].comoNumero ?? 0,
                            fuenteId: fuentes[f][0], fuenteNombre: fuentes[f][1], estadoSueno: sueno ? a[4].comoTexto : nil)
    }

    func disponible() async -> Bool { (try? siguiente("isAvailable") { _ in nil }) != nil }

    func pedirLectura(_ tipos: [String]) async throws {
        // Desvío a propósito (Alan Fried, 17-oct): la nativa pide en una sola hoja el núcleo y el resto, que la web pide
        // en dos tandas. Si la web hizo las dos sin error, la hoja única vale por las dos; si alguna falló, la hoja
        // única falla sin consumir nada y la nativa repite las tandas de la web.
        if let unida = hojaUnica(tipos) {
            if unida { return }
            throw ErrorFuenteSalud("la hoja entera falla, como una tanda de la web")
        }
        _ = try siguiente("requestAuthorization") { e in self.textos(e["read"]) == tipos ? nil : "web \(self.textos(e["read"])), nativa \(tipos)" }
    }

    /// nil: no es la hoja única. true: vale por las dos tandas de la web. false: alguna tanda de la web falló.
    private func hojaUnica(_ tipos: [String]) -> Bool? {
        candado.withLock {
            guard i < consultas.count, consultas[i]["m"]?.comoTexto == "requestAuthorization" else { return nil }
            let primera = textos(consultas[i]["read"])
            guard tipos.count > primera.count, Array(tipos.prefix(primera.count)) == primera else { return nil }
            guard consultas[i]["error"]?.comoTexto == nil, i + 1 < consultas.count,
                  consultas[i + 1]["m"]?.comoTexto == "requestAuthorization", consultas[i + 1]["error"]?.comoTexto == nil,
                  primera + textos(consultas[i + 1]["read"]) == tipos else { return false }
            i += 2
            return true
        }
    }

    func permisos(_ tipos: [String]) async throws -> PermisosSalud {
        let e = try siguiente("checkAuthorization") { e in self.textos(e["read"]) == tipos ? nil : "web \(self.textos(e["read"])), nativa \(tipos)" }
        return PermisosSalud(preguntados: textos(e["r"]?["readAuthorized"]), pendientes: textos(e["r"]?["readDenied"]))
    }

    func agregado(_ dataType: String, agregacion: String, desde: Double, hasta: Double) async throws -> [BaldeDiario] {
        let e = try siguiente("queryAggregated") { e in
            e["dataType"]?.comoTexto != dataType ? "tipo web \(e["dataType"]?.comoTexto ?? "?"), nativa \(dataType)"
                : e["agg"]?.comoTexto != agregacion ? "agregación \(agregacion)" : self.ventana(e, desde, hasta)
        }
        guard case .lista(let filas) = e["r"] else { return [] }
        return filas.compactMap { f in
            guard case .lista(let a) = f else { return nil }
            return BaldeDiario(inicio: a[0].comoNumero ?? 0, valor: a[2].comoNumero ?? 0)
        }
    }

    func muestras(_ dataType: String, desde: Double, hasta: Double, limite: Int) async throws -> [MuestraSalud] {
        let e = try siguiente("readSamples") { e in
            e["dataType"]?.comoTexto != dataType ? "tipo web \(e["dataType"]?.comoTexto ?? "?"), nativa \(dataType)"
                : e["limite"]?.comoNumero != Double(limite) || e["asc"] != .bool(true) ? "límite/orden" : self.ventana(e, desde, hasta)
        }
        guard case .lista(let filas) = e["r"] else { return [] }
        return filas.map { muestra($0, sueno: dataType == "sleep") }
    }

    func entrenos(desde: Double, hasta: Double) async throws -> [EntrenoCrudo] {
        let e = try siguiente("queryWorkouts") { e in self.ventana(e, desde, hasta) }
        guard case .lista(let filas) = e["r"] else { return [] }
        return filas.compactMap { f in
            guard case .lista(let a) = f else { return nil }
            return EntrenoCrudo(tipo: a[0].comoTexto ?? "", duracion: a[1].comoNumero ?? 0, inicio: a[2].comoNumero ?? 0, fin: a[3].comoNumero ?? 0,
                                kcal: a[4].comoNumero, distancia: a[5].comoNumero)
        }
    }
}

/// Hace de base: compara cada lote con el de la web y contesta lo mismo que contestó la base imitada.
final class BaseGrabada: Transporte, @unchecked Sendable {
    private let esperado: [JSONValue]
    private var i = 0
    private(set) var fallas: [String] = []
    private let candado = NSLock()

    init(_ c: CasoSalud) { esperado = c.rpc }
    var pendientes: Int { candado.withLock { esperado.count - i } }

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url?.lastPathComponent ?? ""
        // Las lecturas que hace el modelo para repintar (get_salud, get_recuperacion…) no son parte del vector.
        guard fn == "mypump_ingest_salud" || fn == "mypump_ingest_entrenos" else {
            let vacio = fn == "mypump_get_mostrar_recuperacion" ? "true" : "[]"
            return (Data(vacio.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let e: JSONValue? = candado.withLock {
            guard i < esperado.count else { fallas.append("lote de más a \(fn)"); return nil }
            defer { i += 1 }
            return esperado[i]
        }
        guard let e else { throw URLError(.badServerResponse) }
        let n = candado.withLock { i - 1 }
        if e["fn"]?.comoTexto != fn { candado.withLock { fallas.append("rpc #\(n): la web llamó \(e["fn"]?.comoTexto ?? "?"), la nativa \(fn)") } }
        let lote = cuerpo?[fn == "mypump_ingest_salud" ? "p_registros" : "p_entrenos"]
        if lote != e["lote"] { candado.withLock { fallas.append("rpc #\(n) \(fn): \(diferencia(e["lote"], lote))") } }
        if cuerpo?["p_token"] != e["token"] { candado.withLock { fallas.append("rpc #\(n): token distinto") } }
        let r = e["r"]
        let url = pedido.url!
        if r?["success"] == .bool(true) {
            let datos = try JSONEncoder().encode(r?["data"] ?? .null)
            return (datos, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let error = r?["error"]?.comoTexto ?? ""
        if error.contains("Load failed") { throw URLError(.notConnectedToInternet) }
        let cuerpoError = try JSONEncoder().encode(JSONValue.objeto(["code": .texto("42501"), "message": .texto(error)]))
        return (cuerpoError, HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!)
    }

    private func diferencia(_ a: JSONValue?, _ b: JSONValue?) -> String {
        guard case .lista(let x) = a, case .lista(let y) = b else { return "web \(String(describing: a).prefix(200)), nativa \(String(describing: b).prefix(200))" }
        if x.count != y.count { return "web \(x.count) filas, nativa \(y.count)" }
        for (k, (p, q)) in zip(x, y).enumerated() where p != q { return "fila \(k): web \(p), nativa \(q)" }
        return "?"
    }
}

@MainActor
struct Corrida {
    let caso: CasoSalud
    let fuente: FuenteGrabada
    let base: BaseGrabada
    let almacen: AlmacenSaludEnMemoria
    let sinc: SincronizadorSalud
    var progreso: [[Int]] = []

    init(_ c: CasoSalud) {
        caso = c
        fuente = FuenteGrabada(c)
        base = BaseGrabada(c)
        almacen = AlmacenSaludEnMemoria(c.estadoInicial)
        let ahora = Date(timeIntervalSince1970: c.ahora / 1000)
        // Contra los vectores de la web, con el bug de la web (la noche partida del historial) igual que ella.
        sinc = SincronizadorSalud(fuente: fuente, cliente: ClienteRPC(transporte: base), token: "tok-de-prueba-nativa-0001",
                                  almacen: almacen, ahora: { ahora }, zona: TimeZone(identifier: c.tz)!, descartarNochesPartidas: false)
    }

    /// Corre la acción del caso y devuelve todas las diferencias con la web.
    mutating func diferencias() async -> [String] {
        var difs: [String] = []
        final class Ticks { var lista: [[Int]] = [] }
        let ticks = Ticks()
        sinc.alProgresar = { h, t in ticks.lista.append([h, t]) }
        let r = caso.resultado
        func igual<T: Equatable>(_ campo: String, _ web: T?, _ nativa: T?) {
            if web != nativa { difs.append("\(campo): web \(String(describing: web)), nativa \(String(describing: nativa))") }
        }
        func entero(_ j: JSONValue?) -> Int? { j?.comoNumero.map { Int($0) } }
        func bool(_ j: JSONValue?) -> Bool? { if case .bool(let b) = j { return b }; return nil }

        switch caso.accion {
        case "sync":
            let s = await sinc.sincronizar()
            igual("ok", bool(r["ok"]), s.ok)
            igual("ingresados", entero(r["ingresados"]), s.ingresados)
            igual("entrenos", entero(r["entrenos"]), s.entrenos)
            let errWeb = r["errorIngesta"]?.comoTexto
            if errWeb?.contains("Load failed") == true { igual("hubo error de ingesta", true, s.errorIngesta != nil) }
            else { igual("errorIngesta", errWeb, s.errorIngesta) }
        case "backfill":
            let h = await sinc.historial()
            igual("ok", bool(r["ok"]), h.ok)
            igual("saltado", bool(r["saltado"]) ?? false, h.saltado)
            if !h.saltado {
                igual("ingresados", entero(r["ingresados"]), h.ingresados)
                igual("ventanasFallidas", entero(r["ventanasFallidas"]), h.ventanasFallidas)
            }
        case "conectar":
            let c = await sinc.conectar(esperarHistorial: true)
            let h = await c.historial?.value
            igual("ok", bool(r["ok"]), c.ok)
            igual("preguntados", entero(r["preguntados"]), c.preguntados)
            igual("total", entero(r["total"]), c.total)
            igual("sinDatos", bool(r["sinDatos"]), c.sinDatos)
            let b = r["backfill"]
            igual("historial.ok", bool(b?["ok"]), h?.ok)
            igual("historial.saltado", bool(b?["saltado"]) ?? false, h?.saltado)
            igual("historial.sinDatos", bool(b?["sinDatos"]), h?.sinDatos)
            if h?.saltado == false {
                igual("historial.ingresados", entero(b?["ingresados"]), h?.ingresados)
                igual("historial.ventanasFallidas", entero(b?["ventanasFallidas"]), h?.ventanasFallidas)
            }
        case "estado":
            let e = await sinc.estado()
            igual("disponible", bool(r["disponible"]), e.disponible)
            igual("conectado", bool(r["conectado"]), e.conectado)
            igual("sinDatos", bool(r["sinDatos"]), e.sinDatos)
            igual("preguntados", entero(r["preguntados"]), e.preguntados)
            igual("total", entero(r["total"]), e.total)
            igual("ultimaSync", r["ultimaSync"]?.comoTexto, e.ultimaSync)
        default:
            difs.append("acción desconocida \(caso.accion)")
        }
        igual("avance del historial", caso.progreso, ticks.lista)
        var final = almacen.todo
        final[ClaveSalud.diag] = nil
        igual("estado guardado", caso.estadoFinal, final)
        if let d = caso.diag, case .objeto = d {
            let mio = sinc.ultimoIntento
            igual("diag.paso", d["paso"]?.comoTexto, mio?["paso"]?.comoTexto)
            igual("diag.preguntados", entero(d["preguntados"]), entero(mio?["preguntados"]))
            igual("diag.total", entero(d["total"]), entero(mio?["total"]))
            igual("diag.rechazados", d["rechazados"], mio?["rechazados"])
        }
        difs += fuente.fallas + base.fallas
        if fuente.pendientes > 0 { difs.append("la web hizo \(fuente.pendientes) consultas más") }
        if base.pendientes > 0 { difs.append("la web mandó \(base.pendientes) lotes más") }
        return difs
    }
}

@Suite("Salud: misma salida que healthkit-bridge.js", .serialized)
@MainActor
struct SaludVectoresTests {
    func verificar(_ archivo: String, minimo: Int) async throws {
        let v = try cargarSalud(archivo)
        #expect(v.casos.count >= minimo)
        for c in v.casos {
            var corrida = Corrida(c)
            let difs = await corrida.diferencias()
            #expect(difs.isEmpty, "\(c.nombre): \(difs.prefix(6).joined(separator: " | "))")
        }
    }

    @Test func sincronizarSieteDias() async throws { try await verificar("salud_sync", minimo: 20) }
    @Test func historialDeSesentaDias() async throws { try await verificar("salud_backfill", minimo: 9) }
    @Test func conectarYEstado() async throws { try await verificar("salud_conectar", minimo: 6) }

    /// Cuánto cubren los vectores (para el informe): registros y entrenos que tienen que salir idénticos.
    @Test func coberturaDeLosVectores() throws {
        var registros = 0, entrenos = 0, consultas = 0, tipos = Set<String>()
        for archivo in ["salud_sync", "salud_backfill", "salud_conectar"] {
            for c in try cargarSalud(archivo).casos {
                consultas += c.consultas.count
                for r in c.rpc {
                    guard case .lista(let lote) = r["lote"] else { continue }
                    if r["fn"]?.comoTexto == "mypump_ingest_salud" {
                        registros += lote.count
                        for x in lote { if let t = x["tipo"]?.comoTexto { tipos.insert(t) } }
                    } else { entrenos += lote.count }
                }
            }
        }
        #expect(registros > 5000)
        #expect(entrenos > 100)
        // Todos los tipos que manda el iPhone salen en algún vector.
        let todos = Set(PuenteSalud.agregados.map(\.tipo) + PuenteSalud.muestras.map(\.tipo)
            + ["sueno_min", "sueno_medio_min", "sueno_eficiencia_pct", "sueno_ligero_min", "sueno_profundo_min", "sueno_rem_min", "hrv_ms"])
        #expect(todos.subtracting(tipos).isEmpty, "sin vector: \(todos.subtracting(tipos).sorted())")
        print("vectores de salud: \(registros) registros, \(entrenos) entrenos, \(consultas) consultas al plugin, \(tipos.count) tipos")
    }
}


/// Registra lo que se manda a `ingest_salud` y contesta que entró todo.
final class BaseQueAnota: Transporte, @unchecked Sendable {
    private let candado = NSLock()
    private var _lotes: [[JSONValue]] = []
    var lotes: [[JSONValue]] { candado.withLock { _lotes } }
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url?.lastPathComponent ?? ""
        var respuesta = "[]"
        if fn == "mypump_ingest_salud" || fn == "mypump_ingest_entrenos" {
            let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            if case .lista(let l)? = cuerpo?[fn == "mypump_ingest_salud" ? "p_registros" : "p_entrenos"] {
                if fn == "mypump_ingest_salud" { candado.withLock { _lotes.append(l) } }
                respuesta = String(l.count)
            }
        } else if fn == "mypump_get_mostrar_recuperacion" { respuesta = "true" }
        return (Data(respuesta.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("Salud: el historial no pisa la noche de hoy (desvío a propósito de la web)", .serialized)
@MainActor
struct SaludNocheParcialTests {
    /// Corre "conectar-primera-vez" y devuelve las filas de sueño que mandó el HISTORIAL con fecha de hoy.
    func suenoDeHoyEnElHistorial(descartar: Bool) async throws -> [JSONValue] {
        let caso = try cargarSalud("salud_conectar").casos.first { $0.nombre == "conectar-primera-vez" }!
        let ahora = Date(timeIntervalSince1970: caso.ahora / 1000)
        let zona = TimeZone(identifier: caso.tz)!
        let base = BaseQueAnota()
        let sinc = SincronizadorSalud(fuente: FuenteGrabada(caso), cliente: ClienteRPC(transporte: base), token: "tok-de-prueba-nativa-0001",
                                      almacen: AlmacenSaludEnMemoria(caso.estadoInicial), ahora: { ahora }, zona: zona,
                                      descartarNochesPartidas: descartar)
        let c = await sinc.conectar(esperarHistorial: true)
        _ = await c.historial?.value
        let hoy = RelojLocal(zona: zona).ymd(caso.ahora / 1)
        // El primer lote es la sincronización de 7 días; lo que sigue es el historial.
        return base.lotes.dropFirst().flatMap { $0 }.filter {
            ($0["tipo"]?.comoTexto ?? "").hasPrefix("sueno") && $0["fecha"]?.comoTexto == hoy
        }
    }

    @Test func conElArregloNoSeMandaLaNochePartida() async throws {
        let partidas = try await suenoDeHoyEnElHistorial(descartar: true)
        #expect(partidas.isEmpty, "\(partidas)")
    }

    @Test func sinElArregloSeMandaba() async throws {
        // Lo que hace la web hoy: confirma que el test de arriba muerde.
        let partidas = try await suenoDeHoyEnElHistorial(descartar: false)
        #expect(!partidas.isEmpty)
    }
}
