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

/// Las firmas de `progreso/urls` (cuenta los pedidos) y las subidas, siempre OK; lo demás, `[]`.
final class Firmas: Transporte, @unchecked Sendable {
    let lock = NSLock()
    var pedidosDeURLs = 0
    func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = p.url?.path ?? ""
        var cuerpo = "[]"
        if ruta.hasSuffix("progreso/urls") {
            lock.withLock { pedidosDeURLs += 1 }
            cuerpo = #"{"ok":true,"fotos":[{"semana_lunes":"2026-10-12","pose":"frente","url":"https://fotos.test/f.jpg"}]}"#
        } else if ruta.hasSuffix("upload") {
            cuerpo = #"{"ok":true}"#
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: p.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// Como el servicio real: cada pedido de `progreso/urls` firma de nuevo y da URLs distintas. Las subidas, OK (o sin red).
final class FirmasQueCambian: Transporte, @unchecked Sendable {
    let lock = NSLock()
    let semana: String
    private var firmas = 0
    private var _sinRed = false
    var sinRed: Bool { get { lock.withLock { _sinRed } } set { lock.withLock { _sinRed = newValue } } }
    init(semana: String) { self.semana = semana }
    func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = p.url?.path ?? ""
        var cuerpo = "[]"
        if ruta.hasSuffix("progreso/urls") {
            let n = lock.withLock { firmas += 1; return firmas }
            cuerpo = #"{"ok":true,"fotos":[{"semana_lunes":"\#(semana)","pose":"frente","url":"https://fotos.test/\#(semana)/frente.jpg?token=firma\#(n)"}]}"#
        } else if ruta.hasSuffix("upload") {
            if sinRed { throw URLError(.notConnectedToInternet) }
            cuerpo = #"{"ok":true}"#
        } else if ruta.hasSuffix("mypump_get_fotos_progreso") {
            cuerpo = #"[{"semana_lunes":"\#(semana)","pose":"frente","fecha":"\#(semana)"}]"#
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: p.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
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

    /// REV-05: las URLs firmadas duran 1 h y se guardan 50 minutos: la segunda firma no pide; `forzar` sí, y subir una
    /// foto invalida lo guardado (que aparezca la miniatura nueva).
    @Test func lasURLsFirmadasSeGuardan() async {
        let t = Firmas()
        let m = ModeloFotos(cliente: ClienteRPC(transporte: t), token: "tokenDePrueba_0000000000",
                            disco: Disco(raiz: raiz, token: "tokenDePrueba_0000000000"))
        #expect(await m.firmar())
        #expect(m.urls["2026-10-12|frente"] != nil)
        #expect(await m.firmar())
        #expect(t.pedidosDeURLs == 1, "la segunda no tenía que pedir")
        #expect(await m.firmar(forzar: true))
        #expect(t.pedidosDeURLs == 2)
        #expect(await m.subir(pose: "perfil", jpeg: jpeg) == .guardada)
        #expect(await m.firmar())
        #expect(t.pedidosDeURLs == 3)
    }

    /// Al REEMPLAZAR la foto de una pose que ya estaba subida esa semana, la miniatura seguía mostrando la vieja: la
    /// pantalla firmaba de nuevo solo cuando cambiaba cuántas fotos hay (lo encontró el agente de Revisión de Android
    /// contra la base real). Ahora, con la foto guardada, se firma de nuevo; cada firma es otra URL (como el servicio),
    /// así que tampoco sale la vieja del caché de imágenes.
    @Test func reemplazarUnaFotoDeLaSemanaFirmaDeNuevo() async throws {
        let semana = FotosProgreso.lunes(FechaLocal.hoy())
        let t = FirmasQueCambian(semana: semana)
        let m = ModeloFotos(cliente: ClienteRPC(transporte: t), token: "tokenDePrueba_0000000000",
                            disco: Disco(raiz: raiz, token: "tokenDePrueba_0000000000"))
        // Ya había una de frente esta semana, con su miniatura.
        #expect(await m.firmar())
        let vieja = try #require(m.urls["\(semana)|frente"])
        #expect(await m.subir(pose: "frente", jpeg: jpeg) == .guardada)
        let nueva = try #require(m.urls["\(semana)|frente"])
        #expect(nueva != vieja, "la miniatura seguía con la URL de la foto de antes")

        // Lo mismo si la foto quedó en la cola sin señal y sale después.
        t.sinRed = true
        #expect(await m.subir(pose: "frente", jpeg: jpeg) == .sinConexion)
        t.sinRed = false
        await m.drenar()
        let otra = try #require(m.urls["\(semana)|frente"])
        #expect(otra != nueva, "al subir lo que estaba en la cola no se firmó de nuevo")
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
