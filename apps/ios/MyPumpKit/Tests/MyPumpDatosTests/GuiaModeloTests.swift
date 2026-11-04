import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Un servidor de mentira para «Tu guía»: contesta cada RPC con lo que se le diga y anota lo que le llegó.
final class ServidorGuia: Transporte, @unchecked Sendable {
    private let cerrojo = NSLock()
    private var _respuestas: [String: String] = [:]
    private var _llamadas: [(fn: String, cuerpo: JSONValue)] = []
    private var _sinRed = false

    init(_ respuestas: [String: String] = [:]) { _respuestas = respuestas }

    var sinRed: Bool {
        get { cerrojo.withLock { _sinRed } }
        set { cerrojo.withLock { _sinRed = newValue } }
    }
    func responder(_ fn: String, _ cuerpo: String) { cerrojo.withLock { _respuestas[fn] = cuerpo } }
    var llamadas: [(fn: String, cuerpo: JSONValue)] { cerrojo.withLock { _llamadas } }
    func llamadas(a fn: String) -> [JSONValue] { llamadas.filter { $0.fn == fn }.map(\.cuerpo) }

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url?.lastPathComponent ?? ""
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
        let (r, sinRed): (String?, Bool) = cerrojo.withLock {
            _llamadas.append((fn, cuerpo))
            return (_respuestas[fn], _sinRed)
        }
        if sinRed { throw URLError(.notConnectedToInternet) }
        return (Data((r ?? "true").utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
private func hasta(_ condicion: () -> Bool, _ segundos: Double = 3) async {
    let limite = Date().addingTimeInterval(segundos)
    while !condicion() && Date() < limite { try? await Task.sleep(for: .milliseconds(20)) }
}

@Suite("Tu guía: el modelo (lecturas, cola y copia)", .serialized)
@MainActor
struct GuiaModeloTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-guia-\(UUID().uuidString)")
    let token = "tok_prueba_guia_123456"

    private func armar(_ servidor: ServidorGuia, automatico: Bool = false) -> (ModeloGuia, Outbox, Disco) {
        let cliente = ClienteRPC(transporte: servidor)
        let disco = Disco(raiz: raiz, token: token)
        let escrituras = Escrituras(cliente: cliente, token: token)
        let cola = Outbox(archivo: disco.url("outbox.json"), reintentoAutomatico: automatico) { await escrituras.ejecutar($0) }
        let m = ModeloGuia(cliente: cliente, token: token, outbox: cola, disco: disco)
        Task { await cola.observar(estado: { _ in }, abandonadas: { ops in Task { @MainActor in m.alAbandonar(ops) } },
                                   guardadas: { ops in Task { @MainActor in m.alGuardar(ops) } }) }
        return (m, cola, disco)
    }

    @Test func abrirTraeLaGuiaYLaGuarda() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json])
        let (m, _, disco) = armar(s)
        #expect(m.estado == .cargando)
        await m.abrir()
        #expect(m.estado == .lista && !m.desdeCache)
        #expect(m.guia?.nombrePila == "Marcelo")
        #expect(m.clips.first?.id == "FT-25a")
        #expect(disco.leer(Guia.self, "guia.json")?.clips.count == 13)
        #expect(s.llamadas(a: "entregas_app_get").first?["p_token"] == .texto(token))
        #expect(m.resumen == ResumenGuia(ok: true, total: 13, vistos: 4, minutosRestantes: 7.4), "la tarjeta sigue a la guía abierta")
    }

    @Test func sinRedUsaLaCopiaYSinCopiaLoDice() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json])
        let (m, _, _) = armar(s)
        await m.abrir()
        s.sinRed = true
        let (otro, _, _) = armar(s)
        #expect(otro.estado == .lista && otro.desdeCache, "arranca con la copia")
        await otro.abrir()
        #expect(otro.estado == .lista && otro.desdeCache)
        #expect(otro.guia?.clips.count == 13)

        let vacio = ModeloGuia(cliente: ClienteRPC(transporte: s), token: "otro_token_sin_copia_1", outbox: nil,
                               disco: Disco(raiz: raiz, token: "otro_token_sin_copia_1"))
        await vacio.abrir()
        #expect(vacio.estado == .sinRed)
    }

    @Test func okFalseHaceDesaparecerTodo() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json, "entregas_app_resumen": #"{"ok":true,"total":13,"vistos":4,"minutos_restantes":7.4}"#])
        let (m, _, disco) = armar(s)
        await m.actualizarResumen()
        #expect(m.mostrarTarjeta)
        await m.abrir()
        s.responder("entregas_app_get", #"{"ok":false}"#)
        await m.abrir()
        #expect(m.estado == .oculta && m.guia == nil && !m.mostrarTarjeta)
        #expect(disco.leer(Guia.self, "guia.json") == nil, "la copia se borra")
        #expect(disco.leer(ResumenGuia.self, "guia_resumen.json")?.ok == false)
    }

    @Test func elResumenEsSoloParaLaTarjetaYNoLlamaAlGet() async {
        let s = ServidorGuia(["entregas_app_resumen": #"{"ok":true,"total":20,"vistos":0,"minutos_restantes":14.5}"#])
        let (m, _, _) = armar(s)
        await m.actualizarResumen()
        #expect(m.resumen == ResumenGuia(ok: true, total: 20, vistos: 0, minutosRestantes: 14.5))
        #expect(s.llamadas(a: "entregas_app_get").isEmpty, "el get marca abierto_en: nunca sin que el cliente abra")
        // Se guarda: otro arranque la muestra sin red.
        s.sinRed = true
        let (otro, _, _) = armar(s)
        #expect(otro.mostrarTarjeta)
        await otro.actualizarResumen()
        #expect(otro.mostrarTarjeta, "sin red queda lo guardado")
        s.sinRed = false
        s.responder("entregas_app_resumen", "false")
        await otro.actualizarResumen()
        #expect(!otro.mostrarTarjeta)
    }

    @Test func elAvanceVaPorLaColaUnoPorVideoYGanaElMayor() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json])
        let (m, cola, disco) = armar(s)
        await m.abrir()
        s.sinRed = true
        await m.avance(video: "FT-2a", segundos: 30, visto: false)
        await m.avance(video: "FT-2a", segundos: 20, visto: true)
        await m.avance(video: "FT-2a", segundos: 25, visto: false)
        await m.avance(video: "MC-7a", segundos: 10, visto: false)
        let ops = await cola.operaciones
        #expect(ops.count == 2, "una por video")
        let a = ops.first { $0.payload["video"] == .texto("FT-2a") }
        #expect(a?.payload["segundos"] == .numero(30) && a?.payload["visto"] == .bool(true))
        #expect(a?.dedupeKey == "guia_avance_FT-2a")
        #expect(m.guia?.clips.first { $0.id == "FT-2a" }?.visto == true, "se ve visto enseguida")
        #expect(disco.leer(Guia.self, "guia.json")?.clips.first { $0.id == "FT-2a" }?.visto == true, "y queda en la copia")
        #expect(m.resumen?.vistos == 5)
        s.sinRed = false
        await cola.drenar()
        let llamadas = s.llamadas(a: "entregas_app_avance")
        #expect(llamadas.count == 2)
        #expect(llamadas.first?["p_segundos"] == .numero(30) && llamadas.first?["p_visto"] == .bool(true))
        #expect(llamadas.first?["p_video"] == .texto("FT-2a"))
        #expect(await cola.pendientes == 0)
    }

    @Test func loPendienteGanaSobreElServidor() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json])
        let (m, cola, _) = armar(s)
        await m.abrir()
        s.sinRed = true
        await m.avance(video: "MC-7a", segundos: 100, visto: true)
        _ = await m.enviarDudaPorTexto(video: "FT-3a", "¿Cuántas aproximaciones?")
        // Otra apertura trae del servidor lo de antes (todavía sin lo de la cola).
        s.sinRed = false
        let (otro, _, _) = (ModeloGuia(cliente: ClienteRPC(transporte: ServidorGuia(["entregas_app_get": GuiaMuestra.json])), token: token,
                                       outbox: cola, disco: Disco(raiz: raiz, token: token)), 0, 0)
        await otro.abrir()
        #expect(otro.guia?.clips.first { $0.id == "MC-7a" }?.visto == true)
        #expect(otro.pendientes.map(\.texto) == ["¿Cuántas aproximaciones?"])
    }

    @Test func dudaDeVideoGuardadaSeSumaYNoSeDeduplica() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json, "entregas_app_duda": "true"])
        let (m, cola, _) = armar(s)
        await m.abrir()
        s.sinRed = true
        m.borradores["FT-9a"] = "  otra duda  "
        #expect(await m.enviarDuda(video: "FT-9a"))
        m.borradores["FT-9a"] = "otra duda"
        #expect(await m.enviarDuda(video: "FT-9a"))
        #expect(await cola.pendientes == 2, "dos dudas iguales son dos dudas")
        #expect(m.pendientes.count == 2 && m.envios["FT-9a"] == .enviando)
        #expect(m.borradores["FT-9a"] == "")
        s.sinRed = false
        await cola.drenar()
        await hasta { m.pendientes.isEmpty }
        #expect(m.envios["FT-9a"] == .listo)
        #expect(ReglasGuiaRenglones.de(m.guia?.clips.first { $0.id == "FT-9a" }?.duda) == ["¿Puedo cambiar el arroz por fideos?", "otra duda", "otra duda"])
        #expect(s.llamadas(a: "entregas_app_duda").map { $0["p_texto"] } == [.texto("otra duda"), .texto("otra duda")])
    }

    @Test func falseDevuelveElTextoAlCampo() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json, "entregas_app_duda": "false", "entregas_app_llamada_duda": "false"])
        let (m, cola, _) = armar(s)
        await m.abrir()
        m.borradores["FT-2a"] = "mi duda"
        await m.enviarDuda(video: "FT-2a")
        m.borradores["FT-2a"] = "lo que escribía después"
        await cola.drenar()
        await hasta { m.envios["FT-2a"] == .noSeGuardo }
        #expect(m.envios["FT-2a"] == .noSeGuardo)
        #expect(m.borradores["FT-2a"] == "mi duda\nlo que escribía después", "no se pierde nada")
        #expect(m.pendientes.isEmpty && m.guia?.clips.first { $0.id == "FT-2a" }?.duda == nil)
        m.borradores[""] = "para la llamada"
        await m.enviarDudaLlamada()
        await cola.drenar()
        await hasta { m.envios[""] == .noSeGuardo }
        #expect(m.borradores[""] == "para la llamada")
        #expect(m.guia?.dudasLlamada.count == 1)
    }

    @Test func dudaDeLaLlamadaYSuTope() async {
        let treinta = (1...29).map { #"{"texto":"d\#($0)"}"# }.joined(separator: ",")
        var json = GuiaMuestra.json
        json = json.replacingOccurrences(of: #""dudas_llamada":[{"texto":"¿Puedo entrenar a la noche?","en":"2026-11-04T10:12:00-03:00"}]"#,
                                         with: "\"dudas_llamada\":[\(treinta)]")
        let s = ServidorGuia(["entregas_app_get": json, "entregas_app_llamada_duda": "true"])
        let (m, cola, _) = armar(s)
        await m.abrir()
        #expect(m.dudasLlamadaContadas == 29 && m.puedeSumarDudaLlamada)
        m.borradores[""] = "la 30"
        #expect(await m.enviarDudaLlamada())
        #expect(!m.puedeSumarDudaLlamada, "la de la cola cuenta")
        m.borradores[""] = "la 31"
        #expect(await !m.enviarDudaLlamada(), "con 30 no se manda")
        #expect(m.borradores[""] == "la 31")
        await cola.drenar()
        await hasta { m.envios[""] == .listo }
        #expect(m.guia?.dudasLlamada.last?.texto == "la 30" && m.guia?.dudasLlamada.count == 30)
        #expect(s.llamadas(a: "entregas_app_llamada_duda").count == 1)
    }

    @Test func vacioOMasDeMilNoSeMandan() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json])
        let (m, cola, _) = armar(s)
        await m.abrir()
        m.borradores["FT-2a"] = "   "
        #expect(await !m.enviarDuda(video: "FT-2a"))
        m.borradores["FT-2a"] = String(repeating: "x", count: 1001)
        #expect(await !m.enviarDuda(video: "FT-2a"))
        #expect(await cola.pendientes == 0)
    }

    @Test func elAvanceNoAvisaYUnFalseLoDaPorHecho() async {
        #expect(Outbox.silenciosas.contains(ModeloGuia.kindAvance))
        #expect(!Outbox.silenciosas.contains(ModeloGuia.kindDuda))
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json, "entregas_app_avance": "false"])
        let (m, cola, _) = armar(s)
        await m.abrir()
        await m.avance(video: "FT-2a", segundos: 12, visto: false)
        await cola.drenar()
        let fallidos = await cola.fallidos
        let quedan = await cola.pendientes
        #expect(quedan == 0 && fallidos.isEmpty, "false = token caído o sin guía: nada que reintentar")
    }
}

/// Atajo de los tests: los renglones de una duda acumulada.
enum ReglasGuiaRenglones {
    static func de(_ s: String?) -> [String] { (s ?? "").split(separator: "\n").map(String.init) }
}

extension ModeloGuia {
    /// Escribe en el borrador y manda (atajo de los tests).
    func enviarDudaPorTexto(video: String, _ texto: String) async -> Bool {
        borradores[video] = texto
        return await enviarDuda(video: video)
    }
}
