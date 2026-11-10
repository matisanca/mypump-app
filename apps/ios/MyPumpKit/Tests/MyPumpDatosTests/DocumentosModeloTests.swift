import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Un servidor de prueba para Documentos: la RPC de Supabase y el servicio de firma, cada uno con su status.
private final class ServidorDocumentos: Transporte, @unchecked Sendable {
    private let cerrojo = NSLock()
    private var _rpc: (Int, String) = (200, #"{"documentos":[],"pendientes":0}"#)
    private var _firma: (Int, String) = (200, #"{"documentos":[]}"#)
    private var _sinRed = false
    private var _pedidos: [URLRequest] = []

    var rpc: (Int, String) { get { cerrojo.withLock { _rpc } } set { cerrojo.withLock { _rpc = newValue } } }
    var firma: (Int, String) { get { cerrojo.withLock { _firma } } set { cerrojo.withLock { _firma = newValue } } }
    var sinRed: Bool { get { cerrojo.withLock { _sinRed } } set { cerrojo.withLock { _sinRed = newValue } } }
    var pedidos: [URLRequest] { cerrojo.withLock { _pedidos } }

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let (sinRed, r): (Bool, (Int, String)) = cerrojo.withLock {
            _pedidos.append(pedido)
            return (_sinRed, pedido.url?.host == "firma.mypumpteam.com" ? _firma : _rpc)
        }
        if sinRed { throw URLError(.notConnectedToInternet) }
        return (Data(r.1.utf8), HTTPURLResponse(url: pedido.url!, statusCode: r.0, httpVersion: nil, headerFields: nil)!)
    }
}

private let dos = """
{"documentos":[
  {"id":"d1","tipo":"servicio_ar","titulo":"Contrato","estado":"pendiente","firmado_en":null,"revocado_en":null},
  {"id":"d2","tipo":"consentimiento_ar","titulo":"Consentimiento","estado":"firmado","firmado_en":"2026-11-10T15:03:22.123456+00:00","revocado_en":null}
],"pendientes":1}
"""

@Suite("Documentos: el modelo (RPC, error = sin documentos, enlace)", .serialized)
@MainActor
struct DocumentosModeloTests {
    let token = "tok_prueba_docs_123456"

    private func armar(_ s: ServidorDocumentos) -> ModeloDocumentos {
        ModeloDocumentos(cliente: ClienteRPC(transporte: s), token: token)
    }

    @Test func traeLosDocumentosConElToken() async throws {
        let s = ServidorDocumentos()
        s.rpc = (200, dos)
        let m = armar(s)
        #expect(!m.hay)
        await m.cargar()
        #expect(m.hay && m.contratoPendiente)
        #expect(m.documentos.map(\.id) == ["d1", "d2"])
        let p = try #require(s.pedidos.first)
        #expect(p.url?.path == "/rest/v1/rpc/mypump_contrato_get")
        let cuerpo = try JSONDecoder().decode(JSONValue.self, from: try #require(p.httpBody))
        #expect(cuerpo == .objeto(["p_token": .texto(token)]))
    }

    @Test func cualquierErrorEsSinDocumentos() async {
        let s = ServidorDocumentos()
        s.rpc = (200, dos)
        let m = armar(s)
        await m.cargar()
        #expect(m.hay)
        // Token inválido (28000), la función todavía no está (PGRST202), un 5xx, sin red, una forma rara: nada.
        for r in [(401, #"{"code":"28000","message":"token inválido"}"#), (404, #"{"code":"PGRST202","message":"no existe"}"#),
                  (503, "caído"), (200, "<html>portal</html>"), (200, "null"), (200, "[]")] {
            s.rpc = (200, dos); await m.cargar(); #expect(m.hay)
            s.rpc = r
            await m.cargar()
            #expect(!m.hay && !m.contratoPendiente, "\(r)")
        }
        s.rpc = (200, dos); await m.cargar(); #expect(m.hay)
        s.sinRed = true
        await m.cargar()
        #expect(!m.hay)
    }

    @Test func elConsentimientoSoloNoPrendeElAviso() async {
        let s = ServidorDocumentos()
        s.rpc = (200, #"{"documentos":[{"id":"x","tipo":"consentimiento_ar","estado":"pendiente"},{"id":"y","tipo":"servicio_ext","estado":"firmado","firmado_en":"2026-11-01T12:00:00+00:00"}]}"#)
        let m = armar(s)
        await m.cargar()
        #expect(m.hay && !m.contratoPendiente)
    }

    @Test func elEnlaceSalDelServicioDeFirma() async throws {
        let s = ServidorDocumentos()
        s.rpc = (200, dos)
        s.firma = (200, #"{"documentos":[{"id":"d2","tipo":"consentimiento_ar","estado":"firmado","url":"https://firma.mypumpteam.com/f/otro"},{"id":"d1","tipo":"servicio_ar","estado":"pendiente","firmado_en":null,"url":"https://firma.mypumpteam.com/f/abc.def"}]}"#)
        let m = armar(s)
        await m.cargar()
        let u = await m.enlace(de: m.documentos[0])
        #expect(u?.absoluteString == "https://firma.mypumpteam.com/f/abc.def")
        let p = try #require(s.pedidos.last)
        #expect(p.url?.absoluteString == "https://firma.mypumpteam.com/api/app/documentos")
        #expect(p.httpMethod == "POST")
        #expect(p.value(forHTTPHeaderField: "Authorization") == nil, "el token va en el cuerpo, como pide el servicio")
        #expect(try JSONDecoder().decode(JSONValue.self, from: try #require(p.httpBody)) == .objeto(["token": .texto(token)]))
    }

    @Test func sinServicioNoHayEnlace() async {
        let s = ServidorDocumentos()
        s.rpc = (200, dos)
        let m = armar(s)
        await m.cargar()
        let d = m.documentos[0]
        s.firma = (401, #"{"error":"token"}"#); #expect(await m.enlace(de: d) == nil)
        s.firma = (502, "Bad gateway"); #expect(await m.enlace(de: d) == nil)
        s.firma = (200, #"{"documentos":[]}"#); #expect(await m.enlace(de: d) == nil, "otro documento no se abre")
        s.firma = (200, "<html></html>"); #expect(await m.enlace(de: d) == nil)
        s.sinRed = true; #expect(await m.enlace(de: d) == nil)
    }

    @Test func soloSeAbreHttpsDelPropioServicio() {
        let firma = ConfigBackend.firmaProduccion
        #expect(ModeloDocumentos.enlaceSeguro("https://firma.mypumpteam.com/f/x", servicio: firma) != nil)
        #expect(ModeloDocumentos.enlaceSeguro("https://FIRMA.mypumpteam.com/f/x", servicio: firma) != nil)
        #expect(ModeloDocumentos.enlaceSeguro("http://firma.mypumpteam.com/f/x", servicio: firma) == nil)
        #expect(ModeloDocumentos.enlaceSeguro("https://otro.example.com/f/x", servicio: firma) == nil)
        #expect(ModeloDocumentos.enlaceSeguro("https://firma.mypumpteam.com.example.com/f/x", servicio: firma) == nil)
        #expect(ModeloDocumentos.enlaceSeguro("javascript:alert(1)", servicio: firma) == nil)
        #expect(ModeloDocumentos.enlaceSeguro("", servicio: firma) == nil)
    }

    @Test func laDemoYSalirNoTienenDocumentos() async throws {
        struct SinRed: Transporte { func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) } }
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-docs-\(UUID().uuidString)")
        let app = ModeloApp(cliente: ClienteRPC(transporte: SinRed()), almacen: TokenEnMemoria(nil), raizDisco: raiz)
        #expect(app.documentos == nil)
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../shared/demo")
        app.entrarEnDemo(rutina: try Data(contentsOf: base.appendingPathComponent("rutina.json")),
                         dieta: try Data(contentsOf: base.appendingPathComponent("dieta.json")))
        #expect(app.documentos == nil)
    }
}
