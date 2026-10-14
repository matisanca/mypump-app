import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Un transporte que contesta lo que se le programa a las subidas (`nil` = sin red); lo demás, `[]`.
final class Guion: Transporte, @unchecked Sendable {
    let lock = NSLock()
    var respuestas: [(Int, String)?] = []
    var pedidos: [String] = []
    func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) {
        let esSubida = p.url?.path.hasSuffix("upload") == true
        let r: (Int, String)? = lock.withLock {
            pedidos.append(p.url?.path ?? "")
            if !esSubida { return (200, "[]") }
            return respuestas.isEmpty ? nil : respuestas.removeFirst()
        }
        guard let r else { throw URLError(.notConnectedToInternet) }
        return (Data(r.1.utf8), HTTPURLResponse(url: p.url!, statusCode: r.0, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("Fotos de progreso: la cola como la web")
@MainActor
struct FotosTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-fotos-\(UUID().uuidString)")
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    func modelo(_ g: Guion) -> ModeloFotos {
        ModeloFotos(cliente: ClienteRPC(transporte: g), token: "tokenDePrueba_0000000000", disco: Disco(raiz: raiz, token: "tokenDePrueba_0000000000"))
    }

    @Test func sinRedQuedaGuardadaYNoGastaIntentos() async {
        let g = Guion(); g.respuestas = [nil, nil]
        let m = modelo(g)
        #expect(await m.subir(pose: "frente", jpeg: jpeg) == .sinConexion)
        await m.drenar()
        #expect(m.pendientes.values.first?.intentos == 0)
        // Sobrevive a cerrar la app.
        let otra = modelo(g)
        #expect(otra.pendientes.count == 1)
    }

    @Test func elServidorCaidoGastaIntentosYAlOctavoSeDeja() async {
        let g = Guion(); g.respuestas = Array(repeating: (503, #"{"ok":false}"#), count: 9)
        let m = modelo(g)
        _ = await m.subir(pose: "perfil", jpeg: jpeg)
        for _ in 0..<7 { await m.drenar() }
        #expect(m.pendientes.values.first?.intentos == 7)
        await m.drenar()
        #expect(m.pendientes.isEmpty)
    }

    @Test func unRechazoNoTrabaLaCola() async {
        let g = Guion(); g.respuestas = [nil, nil, (400, #"{"ok":false,"error":"no es un JPEG"}"#), (200, #"{"ok":true,"semana_lunes":"2026-10-12","pose":"perfil"}"#)]
        let m = modelo(g)
        _ = await m.subir(pose: "frente", jpeg: jpeg)
        _ = await m.subir(pose: "perfil", jpeg: jpeg)
        #expect(m.pendientes.count == 2)
        await m.drenar()   // frente: 400 → se descarta y sigue; perfil: ok
        #expect(m.pendientes.isEmpty)
    }

    @Test func rechazadaAlSubirYLimites() async {
        let g = Guion(); g.respuestas = [(403, #"{"ok":false,"error":"token inválido"}"#), nil, nil, nil]
        let m = modelo(g)
        #expect(await m.subir(pose: "frente", jpeg: jpeg) == .rechazada("token inválido"))
        #expect(m.pendientes.isEmpty)
        for p in ["frente", "perfil", "espalda"] { _ = await m.subir(pose: p, jpeg: jpeg) }
        #expect(m.pendientes.count == 3)
        // Una cuarta pose (otra clave) no entra; reemplazar una de las tres sí.
        let otra = ModeloFotos(cliente: ClienteRPC(transporte: g), token: "tokenDePrueba_0000000000",
                               disco: Disco(raiz: raiz, token: "tokenDePrueba_0000000000"))
        #expect(otra.pendientes.count == 3)
        #expect(await m.subir(pose: "frente", jpeg: Data(count: 1_900_000)) == .muyPesada)
    }

    /// REV-03: el tope es de 3 en la cola, de cualquier semana. Con 3 de la semana pasada que no salieron (por ejemplo,
    /// las que trajo la migración), una de esta semana no entra ni sale: "cola llena".
    @Test func conTresEnLaColaUnaCuartaNoEntra() async {
        let g = Guion(); g.respuestas = [nil]
        let disco = Disco(raiz: raiz, token: "tokenDePrueba_0000000000")
        let viejas = Dictionary(uniqueKeysWithValues: ["frente", "perfil", "espalda"].map { p in
            ("2026-10-05|\(p)", FotoPendiente(pose: p, fecha: "2026-10-07", dataUrl: "data:image/jpeg;base64,/9j/"))
        })
        disco.guardar(viejas, FotoPendiente.archivo)
        let m = modelo(g)
        #expect(m.pendientes.count == 3)
        #expect(await m.subir(pose: "frente", jpeg: jpeg) == .colaLlena)
        #expect(m.pendientes.count == 3 && g.pedidos.filter { $0.hasSuffix("upload") }.isEmpty)
    }
}
