import Foundation
import Testing
@testable import MyPumpDatos

/// Batería (2.3.2, punto 3): las fotos del catálogo se bajan una vez y después salen de la memoria o del disco.
@Suite("Batería: las fotos del catálogo quedan en el teléfono")
struct CacheFotosCatalogoTests {
    let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("fotos-catalogo-\(UUID().uuidString)")
    let url = URL(string: "https://ejemplo.supabase.co/storage/v1/object/public/exercise-images/Press/0.jpg")!

    final class Red: @unchecked Sendable {
        private let lock = NSLock()
        private var _pedidos = 0
        private var _caida = false
        private var _estado = 200
        var pedidos: Int { lock.withLock { _pedidos } }
        var caida: Bool { get { lock.withLock { _caida } } set { lock.withLock { _caida = newValue } } }
        var estado: Int { get { lock.withLock { _estado } } set { lock.withLock { _estado = newValue } } }
        var demora: Duration = .zero
        func bajar(_ u: URL) async throws -> (Data, URLResponse) {
            lock.withLock { _pedidos += 1 }
            if demora != .zero { try await Task.sleep(for: demora) }
            if caida { throw URLError(.notConnectedToInternet) }
            return (Data("foto \(u.lastPathComponent)".utf8), HTTPURLResponse(url: u, statusCode: estado, httpVersion: nil, headerFields: nil)!)
        }
    }

    func cache(_ red: Red, ahora: @escaping @Sendable () -> Date = { Date() }) -> CacheFotosCatalogo {
        CacheFotosCatalogo(carpeta: carpeta, bajar: { try await red.bajar($0) }, ahora: ahora)
    }

    @Test func seBajaUnaVezYDespuesSaleDeLaMemoria() async {
        let red = Red()
        let c = cache(red)
        #expect(c.enMemoria(url) == nil)
        #expect(await c.datos(url) == Data("foto 0.jpg".utf8))
        #expect(await c.datos(url) != nil)
        #expect(c.enMemoria(url) != nil, "la pantalla la pinta al instante")
        #expect(red.pedidos == 1)
    }

    @Test func otroArranqueLaLeeDelDiscoSinRed() async {
        let red = Red()
        _ = await cache(red).datos(url)
        red.caida = true
        let otra = cache(red)
        #expect(await otra.datos(url) == Data("foto 0.jpg".utf8))
        #expect(red.pedidos == 1, "del disco, sin pedir")
    }

    @Test func vencidaSeBajaDeNuevoYSinRedSirveLaVieja() async {
        let red = Red()
        _ = await cache(red).datos(url)
        let despues = Date().addingTimeInterval(CacheFotosCatalogo.vigencia + 60)
        let vencida = cache(red, ahora: { despues })
        #expect(await vencida.datos(url) != nil)
        #expect(red.pedidos == 2, "pasada la vigencia se vuelve a bajar")
        red.caida = true
        let sinRed = cache(red, ahora: { despues.addingTimeInterval(CacheFotosCatalogo.vigencia + 60) })
        #expect(await sinRed.datos(url) == Data("foto 0.jpg".utf8), "sin red, la guardada aunque esté vencida")
    }

    @Test func loQueFallaNoSeGuardaYSeReintenta() async {
        let red = Red()
        red.estado = 404
        let c = cache(red)
        #expect(await c.datos(url) == nil)
        red.caida = true
        #expect(await c.datos(url) == nil)
        red.caida = false
        red.estado = 200
        #expect(await c.datos(url) != nil)
        #expect(red.pedidos == 3)
    }

    @Test func dosPedidosALaVezSonUnoSolo() async {
        let red = Red()
        red.demora = .milliseconds(100)
        let c = cache(red)
        async let a = c.datos(url)
        async let b = c.datos(url)
        let (x, y) = await (a, b)
        #expect(x != nil && y != nil)
        #expect(red.pedidos == 1)
    }
}
