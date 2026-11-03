import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// El código de barras en el modelo (2.1, S3): la pregunta a Open Food Facts (solo el código, con el User-Agent propio),
/// la caché por código en el teléfono y lo que pasa sin red o con Open Food Facts caído.
@Suite("Dieta: buscar un código de barras", .serialized)
@MainActor
struct BarrasDietaTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("barras-\(UUID().uuidString)")

    /// Open Food Facts de mentira: contesta lo que diga `respuesta` y anota cada pedido.
    final class OFF: Transporte, @unchecked Sendable {
        private let lock = NSLock()
        private var _pedidos: [URLRequest] = []
        var pedidos: [URLRequest] { lock.withLock { _pedidos } }
        var respuesta: (Int, String)? = (200, "{}")
        func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
            lock.withLock { _pedidos.append(pedido) }
            guard let (s, cuerpo) = respuesta else { throw URLError(.notConnectedToInternet) }
            return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: s, httpVersion: nil, headerFields: nil)!)
        }
    }

    static let yogur = #"{"code":"7791337006355","status":1,"product":{"product_name":"Yogurisimo sabor Natural","brands":"La serenisima","serving_quantity":200,"serving_size":"200 g","nutriments":{"energy-kcal_100g":81.5,"energy-kj_100g":341.8,"proteins_100g":7,"carbohydrates_100g":6.25,"fat_100g":3.15}}}"#

    func modelo(_ t: OFF, token: String = "AAAAAAAAAAAAAAAAAAAA") -> ModeloApp {
        ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(token), raizDisco: raiz)
    }

    @Test func encontradoQuedaEnLaCacheYNoVuelveALaRed() async throws {
        let off = OFF()
        off.respuesta = (200, Self.yogur)
        let m = modelo(off)
        guard case .lectura(.encontrado(let p)) = await m.buscarCodigo("7791337006355") else { Issue.record("no lo encontró"); return }
        #expect(p.nombre == "Yogurisimo sabor Natural (La serenisima)" && p.por100.kcal == 82 && p.gramosMedida == 200)
        let pedido = try #require(off.pedidos.first)
        #expect(pedido.url?.absoluteString.hasPrefix("https://world.openfoodfacts.org/api/v2/product/7791337006355.json?fields=") == true)
        #expect(pedido.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("PumpTeam/") == true)
        #expect(pedido.value(forHTTPHeaderField: "User-Agent")?.hasSuffix(" (iOS)") == true)
        #expect(pedido.httpBody == nil && pedido.timeoutInterval == CodigoBarras.esperaSegundos)

        // La segunda vez sale de la caché, también en otro arranque (quedó en el disco de la cuenta).
        off.respuesta = nil
        #expect(await m.buscarCodigo("7791337006355") == .lectura(.encontrado(p)))
        #expect(await modelo(off).buscarCodigo("7791337006355") == .lectura(.encontrado(p)))
        #expect(off.pedidos.count == 1)
        // Otra cuenta del teléfono tiene su caché.
        #expect(await modelo(off, token: "BBBBBBBBBBBBBBBBBBBB").buscarCodigo("7791337006355") == .sinRed)
    }

    @Test func noEncontradoEs404ConStatus0() async {
        let off = OFF()
        off.respuesta = (404, #"{"code":"7790742000101","status":0,"status_verbose":"product not found"}"#)
        let m = modelo(off)
        #expect(await m.buscarCodigo("7790742000101") == .lectura(.noEncontrado))
        #expect(await m.buscarCodigo("7790742000101") == .lectura(.noEncontrado))
        #expect(off.pedidos.count == 1, "El no encontrado también se guarda (un día)")
    }

    @Test func sinRedOCaidoNoGuardaNada() async {
        let off = OFF()
        let m = modelo(off)
        off.respuesta = nil
        #expect(await m.buscarCodigo("7791337006355") == .sinRed)
        off.respuesta = (503, "<html>Page temporarily unavailable</html>")
        #expect(await m.buscarCodigo("7791337006355") == .sinRed)
        off.respuesta = (429, #"{"status":0}"#)
        #expect(await m.buscarCodigo("7791337006355") == .sinRed)
        off.respuesta = (200, Self.yogur)
        guard case .lectura(.encontrado) = await m.buscarCodigo("7791337006355") else { Issue.record("no volvió a preguntar"); return }
        #expect(off.pedidos.count == 4)
    }

    @Test func elPropioCreadoDesdeUnCodigoApareceAlVolverAEscanearlo() async {
        let off = OFF()
        off.respuesta = (404, #"{"status":0}"#)
        let m = modelo(off)
        #expect(await m.buscarCodigo("7790742000101") == .lectura(.noEncontrado))
        let c = AgregadosComida.Candidato(nombre: "Leche de la Mini", por100: MacrosPor100(kcal: 60, p: 3, c: 5, g: 3), unidad: "porcion",
                                          gramosPorUnidad: 200, origen: .propio, codigo: "7790742000101")
        m.recordarCodigoPropio("7790742000101", c)
        guard case .lectura(.encontrado(let p)) = await m.buscarCodigo("7790742000101") else { Issue.record("no apareció el propio"); return }
        #expect(p.propio && p.candidato.origen == .propio && p.candidato.codigo == "7790742000101" && p.gramosMedida == 200)
        #expect(off.pedidos.count == 1)
    }

    @Test func sinStatusNumerico0o1NoSeGuarda() async {
        let off = OFF()
        let m = modelo(off)
        for cuerpo in [#"{"product":{}}"#, #"{"status":"1","product":{}}"#, #"{"status":2}"#, "[]"] {
            off.respuesta = (200, cuerpo)
            #expect(await m.buscarCodigo("7791337006355") == .sinRed, "\(cuerpo)")
        }
        off.respuesta = (200, Self.yogur)
        guard case .lectura(.encontrado) = await m.buscarCodigo("7791337006355") else { Issue.record("no volvió a preguntar"); return }
        #expect(off.pedidos.count == 5)
    }

    /// Un Open Food Facts que no contesta nunca (cancelable, como URLSession).
    final class Colgado: Transporte {
        func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw URLError(.unknown)
        }
    }

    @Test func laConsultaTienePlazoTotal() async {
        let m = modelo(OFF())
        m.transporteBarras = Colgado()
        m.esperaBarras = 0.3
        let t0 = Date()
        #expect(await m.buscarCodigo("7791337006355") == .sinRed)
        #expect(Date().timeIntervalSince(t0) < 5)
        #expect(CodigoBarras.esperaSegundos == 8 && ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: OFF()),
                                                               almacen: TokenEnMemoria(nil), raizDisco: raiz).esperaBarras == 8)
    }

    @Test func alSalirSeBorraLoBuscado() async {
        let off = OFF()
        off.respuesta = (200, Self.yogur)
        let m = modelo(off)
        guard case .lectura(.encontrado) = await m.buscarCodigo("7791337006355") else { Issue.record("no lo encontró"); return }
        let archivo = Disco(raiz: raiz, token: "AAAAAAAAAAAAAAAAAAAA").url(ModeloApp.archivoCodigos)
        #expect(FileManager.default.fileExists(atPath: archivo.path))
        m.salir()
        #expect(m.cacheCodigos == nil)
        #expect(!FileManager.default.fileExists(atPath: archivo.path))
        off.respuesta = nil
        #expect(await modelo(off).buscarCodigo("7791337006355") == .sinRed, "Volver a entrar no lo encuentra en el teléfono")
    }

    @Test func laDemoNoPreguntaAOpenFoodFactsNiVeLaCacheDeLaCuenta() async {
        let off = OFF()
        off.respuesta = (200, Self.yogur)
        let m = modelo(off)
        guard case .lectura(.encontrado) = await m.buscarCodigo("7791337006355") else { Issue.record("no lo encontró"); return }
        m.entrarEnDemo(rutina: Data("{}".utf8), dieta: Data("{}".utf8))
        #expect(m.cacheCodigos == nil)
        #expect(await m.buscarCodigo("7791337006355") == .lectura(.noEncontrado))
        #expect(await m.buscarCodigo("7790742000101") == .lectura(.noEncontrado))
        #expect(off.pedidos.count == 1)
    }

    @Test func elPropioEditadoDejaDeAparecerConLosValoresViejos() async throws {
        let off = OFF()
        let m = modelo(off)
        func fila(_ kcal: Int) -> String {
            #"[{"name":"Leche X","kcal":\#(kcal),"prot":3,"carb":5,"fat":3,"unit":"porcion","unit_grams":200,"category":null}]"#
        }
        func crear(_ kcal: Double) async throws -> AlimentoPropio {
            guard case .success(let d) = AlimentoPropioNuevo.preparar(nombre: "Leche X", kcal: kcal, prot: 3, carb: 5, fat: 3, unidad: "porcion",
                                                                      gramosPorUnidad: 200, categoria: "") else { throw URLError(.unknown) }
            off.respuesta = (200, fila(Int(kcal)))
            guard case .success(let a) = await m.crearAlimentoPropio(d) else { throw URLError(.badServerResponse) }
            return a
        }
        let a = try await crear(120)
        let codigo = "7790742000101"
        m.recordarCodigoPropio(codigo, AgregadosComida.Candidato(
            nombre: a.nombre, por100: MacrosPor100(kcal: a.kcal ?? 0, p: a.prot ?? 0, c: a.carb ?? 0, g: a.fat ?? 0), unidad: a.unidad,
            gramosPorUnidad: a.gramosPorUnidad, origen: .propio, codigo: codigo))
        let antes = off.pedidos.count
        guard case .lectura(.encontrado(let p)) = await m.buscarCodigo(codigo), p.propio else { Issue.record("no apareció el propio"); return }
        #expect(off.pedidos.count == antes)
        // Se editó (mismo nombre, otras kcal): el código ya no trae el viejo y vuelve a preguntar.
        _ = try await crear(150)
        off.respuesta = (404, #"{"status":0}"#)
        #expect(await m.buscarCodigo(codigo) == .lectura(.noEncontrado))
        #expect(off.pedidos.count == antes + 2)
    }
}
