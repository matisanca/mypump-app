import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// La fila del ejemplo del contrato, como la devuelve PostgREST (una lista de filas).
private let filaEjemplo = """
[{"suplementacion":{"titulo":"Tu suplementación","dia":[{"id":"cena","nombre":"Con la cena"}],
  "items":[{"nombre":"Magnesio","cantidad":"400 mg","momento":"cena","estado":"nuevo"},
           {"nombre":"Multivitamínico","estado":"sale","por_que":"Ya lo cubrís con la dieta"}]},
  "fase":"final","actualizado":"2026-11-04T18:30:00+00:00","esquema":1}]
"""

@Suite("Suplementación: el modelo (RPC, copia y demo)", .serialized)
@MainActor
struct SuplementacionModeloTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-supl-\(UUID().uuidString)")
    let token = "tok_prueba_supl_123456"

    private func armar(_ s: ServidorGuia) -> (ModeloSuplementacion, Disco) {
        let disco = Disco(raiz: raiz, token: token)
        return (ModeloSuplementacion(cliente: ClienteRPC(transporte: s), token: token, disco: disco), disco)
    }

    @Test func unaFilaMuestraLaPestanaYQuedaGuardada() async throws {
        let s = ServidorGuia(["mypump_suplementacion": filaEjemplo])
        let (m, disco) = armar(s)
        #expect(!m.hay)
        await m.cargar()
        #expect(m.hay && !m.desdeCache)
        #expect(m.vista?.momentos.map(\.titulo) == ["Con la cena"])
        #expect(m.vista?.sale.map(\.nombre) == ["Multivitamínico"])
        #expect(s.llamadas(a: "mypump_suplementacion") == [.objeto(["p_token": .texto(token)])], "solo el token, como los mypump_get_*")
        #expect(disco.leer(RespuestaSuplementacion.self, "suplementacion.json")?.fase == "final")
        // Otro arranque, sin red: la copia se ve desde el principio.
        s.sinRed = true
        let otro = ModeloSuplementacion(cliente: ClienteRPC(transporte: s), token: token, disco: disco)
        #expect(otro.hay)
        await otro.cargar()
        #expect(otro.hay && otro.desdeCache)
    }

    @Test func ceroFilasSacaLaPestanaYBorraLaCopia() async {
        let s = ServidorGuia(["mypump_suplementacion": filaEjemplo])
        let (m, disco) = armar(s)
        await m.cargar()
        #expect(m.hay)
        s.responder("mypump_suplementacion", "[]")
        await m.cargar()
        #expect(!m.hay && !m.desdeCache)
        #expect(disco.leer(RespuestaSuplementacion.self, "suplementacion.json") == nil)
    }

    @Test func sinRedYSinCopiaNoHay() async {
        let s = ServidorGuia()
        s.sinRed = true
        let (m, _) = armar(s)
        await m.cargar()
        #expect(!m.hay && !m.desdeCache)
    }

    @Test func unaFilaSinItemsEsComoNoTener() async {
        let s = ServidorGuia(["mypump_suplementacion": #"[{"suplementacion":{"dia":[],"items":[]},"esquema":1}]"#])
        let (m, _) = armar(s)
        await m.cargar()
        #expect(!m.hay)
    }

    @Test func laDemoNoTocaLaRed() async throws {
        struct SinRed: Transporte { func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) } }
        let app = ModeloApp(cliente: ClienteRPC(transporte: SinRed()), almacen: TokenEnMemoria(nil), raizDisco: raiz)
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../shared/demo")
        app.entrarEnDemo(rutina: try Data(contentsOf: base.appendingPathComponent("rutina.json")),
                         dieta: try Data(contentsOf: base.appendingPathComponent("dieta.json")),
                         suplementacion: try Data(contentsOf: base.appendingPathComponent("suplementacion.json")))
        let m = try #require(app.suplementacion)
        #expect(m.hay)
        await m.cargar()
        #expect(m.hay && !m.desdeCache)
        await app.salirDeDemo()
        #expect(app.suplementacion == nil)
        // La demo sin la muestra: sin pestaña.
        app.entrarEnDemo(rutina: try Data(contentsOf: base.appendingPathComponent("rutina.json")),
                         dieta: try Data(contentsOf: base.appendingPathComponent("dieta.json")))
        #expect(app.suplementacion == nil)
    }
}
