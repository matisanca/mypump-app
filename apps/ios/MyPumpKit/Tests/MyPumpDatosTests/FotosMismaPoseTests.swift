import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Un servicio de fotos con compuerta: cada subida tiene su guion (esperar la compuerta, contestar, o sin red), y lo que
/// guarda queda como lo deja el upsert del servicio real: gana la última que termina.
final class ServicioConCompuerta: Transporte, @unchecked Sendable {
    enum Paso { case sinRed, ok, okDespuesDeLaCompuerta }
    let lock = NSLock()
    var guion: [Paso] = []
    var recibidas: [String] = []
    var guardada: [String: String] = [:]   // pose → imagen que quedó en el bucket
    var abierta = false

    var cuantasRecibidas: Int { lock.withLock { recibidas.count } }
    func abrir() { lock.withLock { abierta = true } }

    func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) {
        guard p.url?.path.hasSuffix("upload") == true else {
            return (Data("[]".utf8), HTTPURLResponse(url: p.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let cuerpo = (try? JSONDecoder().decode(JSONValue.self, from: p.httpBody ?? Data())) ?? .null
        let imagen = cuerpo["imagen_base64"]?.comoTexto ?? ""
        let pose = cuerpo["pose"]?.comoTexto ?? ""
        let paso: Paso = lock.withLock {
            recibidas.append(imagen)
            return guion.isEmpty ? .sinRed : guion.removeFirst()
        }
        switch paso {
        case .sinRed:
            throw URLError(.networkConnectionLost)
        case .okDespuesDeLaCompuerta:
            while !lock.withLock({ abierta }) { try await Task.sleep(for: .milliseconds(5)) }
            fallthrough
        case .ok:
            lock.withLock { guardada[pose] = imagen }
            return (Data(#"{"ok":true}"#.utf8), HTTPURLResponse(url: p.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
}

/// La revisión adversarial del 15-oct: el cliente vuelve a sacar la foto de una pose mientras la cola sube la vieja (en
/// Android la cámara es otra app y al volver la app drena). La pasada borraba la clave al terminar bien con la VIEJA y
/// se llevaba la NUEVA; o la vieja terminaba después y el upsert la dejaba en el bucket.
@Suite("Fotos: la misma pose dos veces", .serialized)
@MainActor
struct FotosMismaPoseTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("fotos-misma-pose-\(UUID().uuidString)")
    let vieja = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01])
    let nueva = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x02])
    let token = "tokenDePrueba_0000000000"

    func dataURL(_ d: Data) -> String { "data:image/jpeg;base64," + d.base64EncodedString() }

    /// La vieja quedó en la cola sin señal; la pasada la está subiendo y el cliente saca la nueva, que espera su turno.
    func carrera(_ guion: [ServicioConCompuerta.Paso]) async throws -> (ModeloFotos, ServicioConCompuerta, ModeloFotos.Resultado) {
        let s = ServicioConCompuerta()
        s.guion = guion
        let m = ModeloFotos(cliente: ClienteRPC(transporte: s), token: token, disco: Disco(raiz: raiz, token: token))
        #expect(await m.subir(pose: "frente", jpeg: vieja) == .sinConexion)
        let clave = "\(m.semanaActual)|frente"
        async let pasada: Void = m.drenar()
        while s.cuantasRecibidas < 2 { try await Task.sleep(for: .milliseconds(5)) }
        async let r = m.subir(pose: "frente", jpeg: nueva)
        // Que la nueva ya esté en la cola esperando su turno (o, si no espera, que ya haya salido).
        let tope = Date().addingTimeInterval(5)
        while m.pendientes[clave]?.dataUrl != dataURL(nueva) && s.cuantasRecibidas < 3 && Date() < tope {
            try await Task.sleep(for: .milliseconds(5))
        }
        s.abrir()
        await pasada
        return (m, s, await r)
    }

    @Test func laNuevaQueNoSalioQuedaEnLaCola() async throws {
        let (m, _, r) = try await carrera([.sinRed, .okDespuesDeLaCompuerta, .sinRed])
        let clave = "\(m.semanaActual)|frente"
        #expect(r == .sinConexion)
        #expect(m.pendientes[clave]?.dataUrl == dataURL(nueva), "subir dijo que quedaba guardada y la pasada la borró")
        let enDisco = Disco(raiz: raiz, token: token).leer([String: FotoPendiente].self, FotoPendiente.archivo)
        #expect(enDisco?[clave]?.dataUrl == dataURL(nueva), "tampoco quedó en el disco")
    }

    @Test func enElBucketQuedaLaNueva() async throws {
        let (m, s, r) = try await carrera([.sinRed, .okDespuesDeLaCompuerta, .ok])
        #expect(r == .guardada)
        #expect(s.guardada["frente"] == dataURL(nueva), "el bucket quedó con la foto vieja")
        #expect(m.pendientes.isEmpty)
    }
}

/// El orden de `handleFotoUpload`: la fecha, el token, `overLimit` (que SUMA el intento) y recién después el bucket. Con
/// el storage caído cada intento gasta uno de los 12 del día.
final class ServicioConTope: Transporte, @unchecked Sendable {
    let lock = NSLock()
    var usados = 0
    var bucketCaido = true
    func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) {
        func r(_ s: Int, _ c: String) -> (Data, URLResponse) { (Data(c.utf8), HTTPURLResponse(url: p.url!, statusCode: s, httpVersion: nil, headerFields: nil)!) }
        guard p.url?.path.hasSuffix("upload") == true else { return r(200, "[]") }
        return lock.withLock {
            if usados >= 12 { return r(429, #"{"ok":false,"error":"muchas fotos por hoy, probá mañana"}"#) }
            usados += 1
            return bucketCaido ? r(502, #"{"ok":false,"error":"no se pudo guardar la foto"}"#) : r(200, #"{"ok":true}"#)
        }
    }
}

@Suite("Fotos: con el storage caído, un intento por apertura", .serialized)
@MainActor
struct FotosTopeTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("fotos-tope-\(UUID().uuidString)")

    /// Con dos en la cola, seis aperturas gastaban los 12 del día (revisión adversarial del 15-oct): después decía «Hoy ya
    /// subiste muchas fotos» sin que hubiera entrado ninguna. Ahora el 5xx corta la pasada: seis aperturas, seis intentos.
    @Test func elStorageCaidoGastaUnIntentoPorApertura() async {
        let s = ServicioConTope()
        let token = "tokenDePrueba_0000000000"
        let disco = Disco(raiz: raiz, token: token)
        let lunes = DiaCalendario.texto((DiaCalendario.numero(FotosProgreso.lunes(FechaLocal.hoy())) ?? 0) - 7)
        let fecha = DiaCalendario.texto((DiaCalendario.numero(lunes) ?? 0) + 3)
        disco.guardar(Dictionary(uniqueKeysWithValues: ["perfil", "espalda"].map { p in
            ("\(lunes)|\(p)", FotoPendiente(pose: p, fecha: fecha, dataUrl: "data:image/jpeg;base64,/9j/"))
        }), FotoPendiente.archivo)
        let m = ModeloFotos(cliente: ClienteRPC(transporte: s), token: token, disco: disco)
        for _ in 0..<6 { await m.drenar() }
        #expect(s.lock.withLock { s.usados } == 6, "cada apertura tiene que gastar un solo intento del día")
        #expect(m.pendientes.count == 2, "con el storage caído no se pierde ninguna")
        s.lock.withLock { s.bucketCaido = false }
        #expect(await m.subir(pose: "frente", jpeg: Data([0xFF, 0xD8, 0xFF, 0xE0])) == .guardada)
    }
}
