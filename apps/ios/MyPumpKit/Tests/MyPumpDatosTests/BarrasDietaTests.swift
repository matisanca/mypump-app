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
}
