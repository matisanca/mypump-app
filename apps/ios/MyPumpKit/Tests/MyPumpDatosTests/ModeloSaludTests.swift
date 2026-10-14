import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Una base que contesta por función (y la ruta de los relojes) y anota lo que se llamó.
final class BasePorFuncion: Transporte, @unchecked Sendable {
    var respuestas: [String: (Int, JSONValue)] = [:]
    /// Respuestas que cambian entre llamadas (el sondeo de `get_conexiones`).
    var secuencia: [String: [JSONValue]] = [:]
    private(set) var llamadas: [(fn: String, cuerpo: JSONValue?)] = []
    private let candado = NSLock()

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let url = pedido.url!
        let fn = url.path.hasPrefix("/rest/v1/rpc/") ? url.lastPathComponent : url.path
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let (status, json): (Int, JSONValue) = candado.withLock {
            llamadas.append((fn, cuerpo))
            if var s = secuencia[fn], !s.isEmpty {
                let r = s.removeFirst()
                secuencia[fn] = s.isEmpty ? nil : s
                return (200, r)
            }
            return respuestas[fn] ?? (404, .objeto(["code": .texto("PGRST202"), "message": .texto("no existe")]))
        }
        if status == 0 { throw URLError(.notConnectedToInternet) }
        return (try JSONEncoder().encode(json), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func cuantas(_ fn: String) -> Int { candado.withLock { llamadas.filter { $0.fn == fn }.count } }
    func ultima(_ fn: String) -> JSONValue? { candado.withLock { llamadas.last { $0.fn == fn }?.cuerpo } }
}

private func fila(_ fecha: String, _ tipo: String, _ valor: Double, _ fuente: String = "apple_health") -> JSONValue {
    .objeto(["fecha": .texto(fecha), "tipo": .texto(tipo), "valor": .numero(valor), "fuente": .texto(fuente), "detalle": .null])
}

@Suite("ModeloSalud: lecturas, Mi reloj y sin HealthKit")
@MainActor
struct ModeloSaludTests {
    let hoy = FechaLocal.hoy()

    func modelo(_ base: BasePorFuncion, fuente: (any FuenteSalud)? = nil) -> ModeloSalud {
        ModeloSalud(cliente: ClienteRPC(transporte: base), token: "tok-de-prueba-nativa-0001", fuente: fuente, almacen: AlmacenSaludEnMemoria())
    }

    @Test func cargaSaludRecuperacionYPreferencia() async {
        let base = BasePorFuncion()
        base.respuestas["mypump_get_salud"] = (200, .lista([fila(hoy, "pasos", 8000), fila(hoy, "sueno_min", 420, "oura")]))
        base.respuestas["mypump_get_recuperacion"] = (200, .lista([.objeto(["fecha": .texto(hoy), "score": .numero(74), "estado": .texto("ok"),
                                                                             "banda": .texto("media"), "componentes": .objeto([:])])]))
        base.respuestas["mypump_get_mostrar_recuperacion"] = (200, .bool(false))
        let m = modelo(base)
        await m.cargar()
        #expect(m.salud.count == 2 && m.recuperacion.first?.score == 74)
        #expect(m.mostrarRecuperacion == false)
        #expect(m.cardRecuperacion == .oculto)
        #expect(m.resumenSalud?.pasosHoy == 8000 && m.resumenSalud?.suenoAnoche == 420)
        // 60 días: de hoy − 59 a hoy.
        let p = base.ultima("mypump_get_salud")
        #expect(p?["p_hasta"]?.comoTexto == hoy)
        #expect(p?["p_desde"]?.comoTexto == DiaCalendario.texto(DiaCalendario.numero(hoy)! - 59))
        #expect(base.ultima("mypump_get_recuperacion")?["p_dias"] == .numero(14))
        // null o un error cuentan como "mostrar".
        base.respuestas["mypump_get_mostrar_recuperacion"] = (200, .null)
        await m.cargar()
        #expect(m.mostrarRecuperacion)
        base.respuestas["mypump_get_mostrar_recuperacion"] = (500, .objeto(["message": .texto("caída")]))
        await m.cargar()
        #expect(m.mostrarRecuperacion)
    }

    @Test func mostrarElScoreEsOptimista() async {
        let base = BasePorFuncion()
        base.respuestas["mypump_set_mostrar_recuperacion"] = (200, .bool(true))
        let m = modelo(base)
        await m.cambiarMostrarRecuperacion(false)
        #expect(m.mostrarRecuperacion == false)
        #expect(base.ultima("mypump_set_mostrar_recuperacion")?["p_mostrar"] == .bool(false))
    }

    @Test func sinHealthKitNoHaceNada() async {
        let base = BasePorFuncion()
        let m = modelo(base)
        let c = await m.conectar()
        #expect(!c.ok && c.motivo == "no_disponible")
        let s = await m.sincronizar()
        #expect(!s.ok)
        #expect(!m.disponible && !m.conectado)
        #expect(base.cuantas("mypump_ingest_salud") == 0)
        #expect(m.cardRecuperacion == .sinConectar)
    }

    @Test func relojesVisiblesYTextos() async {
        let base = BasePorFuncion()
        base.respuestas["/api/wearables/disponibles"] = (200, .objeto(["proveedores": .lista([.objeto(["id": .texto("oura"), "nombre": .texto("Oura")])])]))
        base.respuestas["mypump_get_conexiones"] = (200, .lista([.objeto(["proveedor": .texto("whoop"), "estado": .texto("error"),
                                                                           "ultimo_pull_en": .null])]))
        let m = modelo(base)
        await m.cargarRelojes()
        // Oura porque el servidor lo ofrece; WHOOP porque ya lo tenía (aunque hoy no se ofrezca).
        #expect(m.relojesVisibles.map(\.id) == ["oura", "whoop"])
        #expect(m.relojesVisibles[1].enError && !m.relojesVisibles[1].conectado)
        #expect(m.textoRelojes.hasPrefix("Si usás Oura o WHOOP, conectalo"))
        // Lo que ofrece el servidor se pregunta una sola vez.
        await m.cargarRelojes()
        #expect(base.cuantas("/api/wearables/disponibles") == 1)
        let url = m.urlConectar("oura")
        #expect(url?.absoluteString == "https://app.mypumpteam.com/api/wearables/iniciar?t=tok-de-prueba-nativa-0001&proveedor=oura")
    }

    @Test func sinRedNoSeOfreceNingunReloj() async {
        let base = BasePorFuncion()
        base.respuestas["/api/wearables/disponibles"] = (0, .null)
        base.respuestas["mypump_get_conexiones"] = (200, .lista([]))
        let m = modelo(base)
        await m.cargarRelojes()
        #expect(m.relojesDisponibles == [] && m.relojesVisibles.isEmpty)
    }

    @Test func esperaLaConexionYRecarga() async {
        let base = BasePorFuncion()
        base.secuencia["mypump_get_conexiones"] = [
            .lista([]),
            .lista([.objeto(["proveedor": .texto("oura"), "estado": .texto("pendiente")])]),
            .lista([.objeto(["proveedor": .texto("oura"), "estado": .texto("conectada"), "ultimo_pull_en": .texto("2026-10-14T13:59:00.123456+00:00")])]),
        ]
        base.respuestas["mypump_get_salud"] = (200, .lista([]))
        base.respuestas["mypump_get_recuperacion"] = (200, .lista([]))
        base.respuestas["mypump_get_mostrar_recuperacion"] = (200, .bool(true))
        base.respuestas["/api/wearables/disponibles"] = (200, .objeto(["proveedores": .lista([.objeto(["id": .texto("oura")])])]))
        let m = modelo(base)
        await m.cargarRelojes()
        let ok = await m.esperarConexion("oura", cada: .milliseconds(5), intentos: 40)
        #expect(ok)
        #expect(m.esperandoReloj == nil)
        #expect(m.relojesVisibles.first?.conectado == true)
        #expect(m.relojesVisibles.first?.ultimaSincronizacion?.hasSuffix("oct") == true)
        #expect(base.cuantas("mypump_get_salud") == 1)   // al conectar se recargan salud y recuperación
    }

    @Test func dejaDePreguntarALos40Intentos() async {
        let base = BasePorFuncion()
        base.respuestas["mypump_get_conexiones"] = (200, .lista([]))
        let m = modelo(base)
        let ok = await m.esperarConexion("whoop", cada: .milliseconds(1), intentos: 40)
        #expect(!ok)
        #expect(base.cuantas("mypump_get_conexiones") == 40)
    }

    @Test func quitarDesconectaYRelee() async {
        let base = BasePorFuncion()
        base.respuestas["mypump_desconectar_wearable"] = (200, .bool(true))
        base.respuestas["mypump_get_conexiones"] = (200, .lista([]))
        base.respuestas["/api/wearables/disponibles"] = (200, .objeto(["proveedores": .lista([])]))
        let m = modelo(base)
        await m.quitar("oura")
        #expect(base.ultima("mypump_desconectar_wearable")?["p_proveedor"]?.comoTexto == "oura")
        #expect(base.cuantas("mypump_get_conexiones") == 1)
    }

    @Test func conectarConHealthKitSincronizaYDejaElHistorialDeFondo() async throws {
        // El caso "conectar-primera-vez" de los vectores, a través del modelo.
        let caso = try cargarSalud("salud_conectar").casos.first { $0.nombre == "conectar-primera-vez" }!
        let base = BaseGrabada(caso)
        let fuente = FuenteGrabada(caso)
        let almacen = AlmacenSaludEnMemoria(caso.estadoInicial)
        let ahora = Date(timeIntervalSince1970: caso.ahora / 1000)
        let m = ModeloSalud(cliente: ClienteRPC(transporte: base), token: "tok-de-prueba-nativa-0001", fuente: fuente, almacen: almacen,
                            ahora: { ahora }, zona: TimeZone(identifier: caso.tz)!)
        let r = await m.conectar()
        #expect(r.ok && m.conectado)
        _ = await r.historial?.value
        #expect(fuente.fallas.isEmpty, "\(fuente.fallas.prefix(3))")
        #expect(fuente.pendientes == 0)
        #expect(almacen.leer(ClaveSalud.historialHecho) == "1")
        #expect(ModeloSalud.textoSincronizacion(ResultadoSync(ok: true, motivo: nil, ingresados: 0, entrenos: 0, errorIngesta: nil)) == "Ya estabas al día.")
    }
}

// MARK: - Contra el backend real, con la cuenta test-nativa-ios (y ninguna otra)

private let registro = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Developer/nativa-evidencia/privado/cuentas-prueba.json")

private func tokenIOS() -> String? {
    guard let d = try? Data(contentsOf: registro), let j = try? JSONDecoder().decode(JSONValue.self, from: d) else { return nil }
    return j["test-nativa-ios"]?["token"]?.comoTexto
}

@Suite("Salud contra el backend real (test-nativa-ios)", .enabled(if: tokenIOS() != nil), .serialized)
@MainActor
struct SaludIntegracionTests {
    /// Lo que arma la nativa entra a la base tal cual: el caso "sintetica-normal" de los vectores (fechas del
    /// 7 al 14-oct-2026) se manda a la cuenta de prueba y se relee. El upsert es por (cliente, fecha, tipo, fuente):
    /// correrlo de nuevo no duplica.
    @Test func ingestaYRelectura() async throws {
        let token = try #require(tokenIOS())
        let caso = try cargarSalud("salud_sync").casos.first { $0.nombre == "sintetica-normal" }!
        let ahora = Date(timeIntervalSince1970: caso.ahora / 1000)
        let fuente = FuenteGrabada(caso)
        let sinc = SincronizadorSalud(fuente: fuente, cliente: ClienteRPC(), token: token, almacen: AlmacenSaludEnMemoria(caso.estadoInicial),
                                      ahora: { ahora }, zona: TimeZone(identifier: caso.tz)!)
        let r = await sinc.sincronizar()
        #expect(fuente.fallas.isEmpty)
        #expect(r.errorIngesta == nil, "la base rechazó: \(r.errorIngesta ?? "")")
        let enviados = caso.rpc.filter { $0["fn"]?.comoTexto == "mypump_ingest_salud" }.flatMap { if case .lista(let l) = $0["lote"] { return l }; return [] }
        #expect(r.ingresados == enviados.count, "la base aceptó \(r.ingresados) de \(enviados.count)")

        let filas = try await ClienteRPC().filas("mypump_get_salud", ["p_token": .texto(token), "p_desde": .texto("2026-10-07"), "p_hasta": .texto("2026-10-14")],
                                                 como: FilaSalud.self).get()
        var faltan: [String] = []
        for e in enviados {
            let fecha = e["fecha"]?.comoTexto ?? "", tipo = e["tipo"]?.comoTexto ?? ""
            guard let f = filas.first(where: { $0.fecha.hasPrefix(fecha) && $0.tipo == tipo && $0.fuente == "apple_health" }) else { faltan.append("\(fecha) \(tipo)"); continue }
            if f.valor != e["valor"]?.comoNumero { faltan.append("\(fecha) \(tipo): \(String(describing: f.valor)) ≠ \(String(describing: e["valor"]))") }
            // Sin detalle la clave no viaja y la base guarda NULL (no un JSON null).
            if e["detalle"] == nil && f.detalle != nil && f.detalle != .null { faltan.append("\(fecha) \(tipo): detalle \(String(describing: f.detalle))") }
            if let d = e["detalle"], f.detalle != d { faltan.append("\(fecha) \(tipo): detalle \(String(describing: f.detalle)) ≠ \(d)") }
        }
        #expect(faltan.isEmpty, "\(faltan.prefix(5))")
    }

    @Test func preferenciaRelojesYConexiones() async throws {
        let token = try #require(tokenIOS())
        let m = ModeloSalud(cliente: ClienteRPC(), token: token, fuente: nil, almacen: AlmacenSaludEnMemoria())
        await m.cambiarMostrarRecuperacion(false)
        await m.cargar()
        #expect(m.mostrarRecuperacion == false)
        await m.cambiarMostrarRecuperacion(true)
        await m.cargar()
        #expect(m.mostrarRecuperacion)
        #expect(m.cargado)
        await m.cargarRelojes()
        #expect(m.relojesDisponibles != nil)
        #expect(m.conexiones.allSatisfy { ["oura", "whoop"].contains($0.proveedor) })
    }
}
