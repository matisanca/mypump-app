import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Los casos de scripts/test-outbox.mjs (cada uno encierra un bug real), con la cola nativa. Los dobles devuelven lo
/// que devuelve la API REAL (apps/shared/fixtures/errores/): un test que mockea un contrato inventado pasa con el bug
/// vivo (lección del 19-sep).

private let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Transporte que contesta una respuesta grabada de la API.
private struct Grabado: Transporte {
    let status: Int
    let cuerpo: String
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    static func de(_ nombre: String) throws -> Grabado {
        let d = try Data(contentsOf: raiz.appendingPathComponent("apps/shared/fixtures/errores/\(nombre).json"))
        let j = try JSONDecoder().decode(JSONValue.self, from: d)
        return Grabado(status: Int(j["status"]?.comoNumero ?? 0), cuerpo: j["cuerpo"]?.comoTexto ?? "")
    }
}

private struct SinRed: Transporte {
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) }
}

private struct PortalCautivo: Transporte {
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        (Data("<html>Iniciá sesión en el wifi del gym</html>".utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor Registro {
    var enviados: [String] = []
    func anotar(_ s: String) { enviados.append(s) }
}

private func cola(_ ejecutor: @escaping Outbox.Ejecutor) -> Outbox {
    Outbox(archivo: nil, reintentoAutomatico: false, ejecutor: ejecutor)
}

private func carga(_ serie: Int) -> JSONValue { .objeto(["diaId": .texto("d1"), "semana": .numero(1), "datos": .objeto(["serie": .numero(Double(serie))])]) }

private let ok: ResultadoOp = .respuesta(.success(.texto("row-id")))

@Suite("Outbox: los casos de la web")
struct OutboxTests {
    @Test func loEncoladoDuranteElVueloNoSePierde() async {
        let r = Registro()
        let o = Outbox(archivo: nil, reintentoAutomatico: true) { op in
            await r.anotar(op.dedupeKey ?? "")
            try? await Task.sleep(for: .milliseconds(40))
            return ok
        }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        try? await Task.sleep(for: .milliseconds(10))
        await o.encolar("carga", carga(2), dedupeKey: "k2")
        try? await Task.sleep(for: .milliseconds(400))
        #expect(await r.enviados.contains("k2"))
        #expect(await o.pendientes == 0)
    }

    @Test func tampocoSePierdeDelDisco() async throws {
        let archivo = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: archivo) }
        let o = Outbox(archivo: archivo, reintentoAutomatico: true) { _ in try? await Task.sleep(for: .milliseconds(60)); return ok }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        try await Task.sleep(for: .milliseconds(10))
        await o.encolar("carga", carga(2), dedupeKey: "k2")
        let enDisco = try JSONDecoder().decode(Outbox.Persistido.self, from: Data(contentsOf: archivo))
        #expect(enDisco.ops.contains { $0.dedupeKey == "k2" })
        // Y una cola nueva sobre el mismo archivo la levanta (sobrevive a cerrar la app).
        let otra = Outbox(archivo: archivo, reintentoAutomatico: false) { _ in ok }
        #expect(await otra.pendientes >= 1)
    }

    @Test(arguments: ["token_invalido_escritura", "token_invalido_lectura"])
    func nullOListaVaciaNoCuentanComoGuardado(fixture: String) async throws {
        let cliente = ClienteRPC(config: .produccion, transporte: try Grabado.de(fixture))
        let o = cola { _ in .respuesta(await cliente.llamar("mypump_registrar_carga", [:])) }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        await o.drenar()
        #expect(await o.pendientes == 1)
    }

    @Test func unCeroTampoco() async {
        let o = cola { _ in .respuesta(.success(.numero(0))) }
        await o.encolar("peso", .objeto([:]), dedupeKey: "p")
        await o.drenar()
        #expect(await o.pendientes == 1)
    }

    @Test func falseSiCuenta() async throws {
        // desmarcar algo que no estaba: la RPC devuelve false y el objetivo está cumplido.
        let cliente = ClienteRPC(config: .produccion, transporte: try Grabado.de("boolean_false"))
        let o = cola { _ in .respuesta(await cliente.llamar("mypump_desmarcar_comida", [:])) }
        await o.encolar("comida", .objeto([:]), dedupeKey: "c")
        await o.drenar()
        #expect(await o.pendientes == 0)
    }

    @Test func unRechazoRealGastaIntentosYTerminaEnFallidos() async throws {
        let cliente = ClienteRPC(config: .produccion, transporte: try Grabado.de("tipo_invalido"))
        let o = cola { _ in .respuesta(await cliente.llamar("mypump_registrar_carga", [:])) }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        for _ in 0..<12 where await o.pendientes > 0 { await o.drenar() }
        #expect(await o.pendientes == 0)
        let f = await o.fallidos
        #expect(f.count == 1)   // no se pierde: queda para el diagnóstico y el recibo
        #expect(f.first?.op.tries == 8)
    }

    @Test func sinRedTreintaPasadasNoAbandonanNada() async {
        let cliente = ClienteRPC(config: .produccion, transporte: SinRed())
        let o = cola { _ in .respuesta(await cliente.llamar("mypump_registrar_carga", [:])) }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        await o.encolar("carga", carga(2), dedupeKey: "k2")
        for _ in 0..<30 { await o.drenar() }
        #expect(await o.pendientes == 2)
        #expect(await o.operaciones.allSatisfy { $0.tries == 0 })
    }

    @Test func portalCautivoEsFaltaDeRed() async {
        let cliente = ClienteRPC(config: .produccion, transporte: PortalCautivo())
        let o = cola { _ in .respuesta(await cliente.llamar("mypump_registrar_carga", [:])) }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        for _ in 0..<12 { await o.drenar() }
        #expect(await o.pendientes == 1)
    }

    @Test(arguments: [503, 429, 408, 500])
    func transitorioNoGastaIntentos(status: Int) async {
        let cliente = ClienteRPC(config: .produccion, transporte: Grabado(status: status, cuerpo: "{\"message\":\"x\"}"))
        let o = cola { _ in .respuesta(await cliente.llamar("mypump_registrar_carga", [:])) }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        for _ in 0..<12 { await o.drenar() }
        #expect(await o.pendientes == 1)
    }

    @Test func sinRedNoSigueMandandoLasDemas() async {
        let r = Registro()
        let o = cola { op in await r.anotar(op.id); return .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "x"))) }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        await o.encolar("carga", carga(2), dedupeKey: "k2")
        for _ in 0..<30 { await o.drenar() }
        #expect(await r.enviados.count <= 31)
        #expect(await o.pendientes == 2)
    }

    @Test func cuandoVuelveLaRedSeMandan() async {
        let red = Bandera()
        let o = cola { _ in await red.valor ? ok : .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "x"))) }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        for _ in 0..<10 { await o.drenar() }
        await red.prender()
        await o.drenar()
        #expect(await o.pendientes == 0)
    }

    @Test func unThrowDeRedNoGastaIntentos() async {
        let o = cola { _ in throw URLError(.networkConnectionLost) }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        for _ in 0..<12 { await o.drenar() }
        #expect(await o.pendientes == 1)
    }

    @Test func unBugNuestroGastaIntentosYNoCongelaALasDeAtras() async {
        struct Bug: Error {}
        let r = Registro()
        let o = cola { op in
            if op.dedupeKey == "k1" { throw Bug() }
            await r.anotar(op.dedupeKey ?? "")
            return ok
        }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        await o.encolar("carga", carga(2), dedupeKey: "k2")
        for _ in 0..<12 where await o.pendientes > 0 { await o.drenar() }
        #expect(await r.enviados.contains("k2"))
        #expect(await o.pendientes == 0)
        #expect(await o.fallidos.count == 1)
    }

    @Test func ganaLaUltimaDecisionPorClave() async {
        let r = Registro()
        let o = cola { op in await r.anotar(op.payload["estado"]?.comoTexto ?? "null"); return .respuesta(.success(.bool(false))) }
        await o.encolar("comida", .objeto(["estado": .texto("comido")]), dedupeKey: "comida|2026-09-19|c2")
        await o.encolar("comida", .objeto(["estado": .null]), dedupeKey: "comida|2026-09-19|c2")
        #expect(await o.pendientes == 1)
        await o.drenar()
        #expect(await r.enviados == ["null"])
        #expect(await o.pendientes == 0)
    }

    @Test func drenarEsperaLaPasadaEnCurso() async {
        let fin = Bandera()
        let o = Outbox(archivo: nil, reintentoAutomatico: true) { _ in
            try? await Task.sleep(for: .milliseconds(80))
            await fin.prender()
            return ok
        }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        try? await Task.sleep(for: .milliseconds(15))
        await o.drenar()
        #expect(await fin.valor)
    }

    @Test func abandonarDejaElAvisoDePerdido() async {
        let estados = Estados()
        let o = cola { _ in .respuesta(.failure(ErrorRPC(clase: .permanente, status: 400, codigo: "22P02", mensaje: "boom"))) }
        await o.observar(estado: { e in estados.anotar(e) }, abandonadas: { _ in })
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        for _ in 0..<12 where await o.pendientes > 0 { await o.drenar() }
        #expect(estados.lista.last == .perdido)
    }

    @Test func tokenCaidoEstacionaSinGastar() async {
        let o = cola { _ in .tokenCaido }
        await o.encolar("carga", carga(1), dedupeKey: "k1")
        for _ in 0..<20 { await o.drenar() }
        #expect(await o.pendientes == 1)
        #expect(await o.operaciones.first?.tries == 0)
    }

    @Test func importarRespetaOrdenYNoDuplica() async {
        let o = cola { _ in ok }
        let viejas = (1...3).map { Operacion(id: "legado_\($0)", kind: "carga", payload: carga($0), dedupeKey: "k\($0)", ts: Double($0)) }
        await o.importar(viejas)
        await o.importar(viejas)
        #expect(await o.operaciones.map(\.id) == ["legado_1", "legado_2", "legado_3"])
    }

    @Test func pgrst202EsPermanenteYSeReconoce() async throws {
        let r = await ClienteRPC(config: .produccion, transporte: try Grabado.de("pgrst202")).llamar("x", [:])
        guard case .failure(let e) = r else { Issue.record("tenía que fallar"); return }
        #expect(e.clase == .permanente && e.funcionInexistente)
        let p = await ClienteRPC(config: .produccion, transporte: try Grabado.de("p0001")).llamar("x", [:])
        guard case .failure(let e2) = p else { Issue.record("tenía que fallar"); return }
        #expect(e2.codigo == "P0001" && e2.mensaje == "token invalido")
    }
}

private actor Bandera {
    var valor = false
    func prender() { valor = true }
}

/// Registro sincrónico: los avisos llegan en orden (con un Task por aviso, el orden no está garantizado).
private final class Estados: @unchecked Sendable {
    private let lock = NSLock()
    private var _lista: [EstadoGuardado] = []
    var lista: [EstadoGuardado] { lock.withLock { _lista } }
    func anotar(_ e: EstadoGuardado) { lock.withLock { _lista.append(e) } }
}
