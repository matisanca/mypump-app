import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// La demo ("Ver demo", la que mira App Review): sin red, sin token y sin escribir nada.
@Suite("Demo")
@MainActor
struct DemoTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-demo-\(UUID().uuidString)")

    @Test func demoSinRedNiToken() async throws {
        struct SinRed: Transporte { func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) } }
        let m = ModeloApp(cliente: ClienteRPC(transporte: SinRed()), almacen: TokenEnMemoria(nil), raizDisco: raiz)
        #expect(m.fase == .sinToken)
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../shared/demo")
        m.entrarEnDemo(rutina: try Data(contentsOf: base.appendingPathComponent("rutina.json")),
                       dieta: try Data(contentsOf: base.appendingPathComponent("dieta.json")))
        #expect(m.fase == .listo && m.esDemo)
        #expect(!(m.rutina?.estructura.dias.isEmpty ?? true))
        #expect(!m.comidasDelDia.isEmpty)
        await m.cargar()   // "tirar para actualizar" en la demo: no la cierra
        #expect(m.fase == .listo && m.esDemo)
        // Un reemplazo en la demo queda en memoria y no sale a ningún lado.
        let c = try #require(m.comidasDelDia.first)
        let a = try #require(c.opciones.first?.alimentos.first)
        await m.sustituir(a, por: .objeto(["name": .texto("Ricota"), "qty": .numero(100), "unit": .texto("g"), "kcal": .numero(138),
                                           "prot": .numero(11), "carb": .numero(4), "fat": .numero(9)]), comidaId: c.id, opt: 0, idx: 0)
        #expect(m.efectivo(a, comidaId: c.id, opt: 0, idx: 0).sustituido)
        await m.salirDeDemo()
        #expect(m.fase == .sinToken && !m.esDemo && m.dieta == nil)
    }

}
