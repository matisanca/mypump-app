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
    private var _demoras: [String: Duration] = [:]

    init(_ respuestas: [String: String] = [:]) { _respuestas = respuestas }

    var sinRed: Bool {
        get { cerrojo.withLock { _sinRed } }
        set { cerrojo.withLock { _sinRed = newValue } }
    }
    func responder(_ fn: String, _ cuerpo: String) { cerrojo.withLock { _respuestas[fn] = cuerpo } }
    /// La respuesta de esa función tarda (contesta con lo que había al llegar el pedido).
    func demorar(_ fn: String, _ d: Duration?) { cerrojo.withLock { _demoras[fn] = d } }
    var llamadas: [(fn: String, cuerpo: JSONValue)] { cerrojo.withLock { _llamadas } }
    func llamadas(a fn: String) -> [JSONValue] { llamadas.filter { $0.fn == fn }.map(\.cuerpo) }

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url?.lastPathComponent ?? ""
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
        let (r, sinRed, demora): (String?, Bool, Duration?) = cerrojo.withLock {
            _llamadas.append((fn, cuerpo))
            return (_respuestas[fn], _sinRed, _demoras[fn])
        }
        if sinRed { throw URLError(.notConnectedToInternet) }
        if let demora { try? await Task.sleep(for: demora) }
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
        // Como `entregas_012`: sin los dos videos que nombran los suplementos (FT-1b y FT-4b).
        #expect(m.resumen == ResumenGuia(ok: true, total: 11, vistos: 4, minutosRestantes: 6.2), "la tarjeta sigue a la guía abierta")
    }

    @Test func sinRedUsaLaCopiaYSinCopiaLoDice() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json])
        let (m, _, _) = armar(s)
        await m.abrir()
        s.sinRed = true
        let (otro, _, _) = armar(s)
        #expect(otro.estado == .lista && !otro.desdeCache, "arranca con la copia, sin «Sin conexión» hasta que el get falle")
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

    // MARK: - Revisión adversarial (4/11)

    /// La muestra con una duda más en FT-9a (lo que trae un get si la duda ya llegó al servidor).
    private static let conNueva = GuiaMuestra.json.replacingOccurrences(of: "\"¿Puedo cambiar el arroz por fideos?\"",
                                                                         with: "\"¿Puedo cambiar el arroz por fideos?\\nnueva\"")

    @Test func cadaDudaLlevaSuPIdYLasViejasVanSinElCampo() async throws {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json, "entregas_app_duda": "true", "entregas_app_llamada_duda": "true"])
        let (m, cola, _) = armar(s)
        await m.abrir()
        _ = await m.enviarDudaPorTexto(video: "FT-9a", "con id")
        m.borradores[""] = "para la llamada"
        _ = await m.enviarDudaLlamada()
        await cola.importar([
            Operacion(id: "viejo_1", kind: ModeloGuia.kindDuda, payload: .objeto(["video": .texto("FT-9a"), "texto": .texto("vieja")]), dedupeKey: nil, ts: 1),
            Operacion(id: "viejo_2", kind: ModeloGuia.kindDudaLlamada, payload: .objeto(["texto": .texto("vieja"), "id": .texto("")]), dedupeKey: nil, ts: 2),
        ])
        await cola.drenar()
        let duda = s.llamadas(a: "entregas_app_duda"), llamada = s.llamadas(a: "entregas_app_llamada_duda")
        let id1 = try #require(duda.first?["p_id"]?.comoTexto)
        #expect(UUID(uuidString: id1) != nil && id1 == id1.lowercased())
        #expect(UUID(uuidString: llamada.first?["p_id"]?.comoTexto ?? "") != nil)
        #expect(id1 != llamada.first?["p_id"]?.comoTexto)
        #expect(duda.last?["p_id"] == nil, "una op vieja sin id va sin el campo")
        #expect(llamada.last?["p_id"] == nil, "nunca \"\": da 22P02")
    }

    @Test func elReintentoMandaElMismoPId() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json, "entregas_app_duda": "true"])
        let (m, cola, _) = armar(s)
        await m.abrir()
        s.sinRed = true
        _ = await m.enviarDudaPorTexto(video: "FT-9a", "reintento")
        await cola.drenar()
        s.sinRed = false
        await cola.drenar()
        let ids = s.llamadas(a: "entregas_app_duda").compactMap { $0["p_id"]?.comoTexto }
        #expect(ids.count == 2 && Set(ids).count == 1)
    }

    @Test func siElGetYaTraeLaDudaNoSeVeNiSeSumaDosVeces() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json, "entregas_app_duda": "true"])
        let (m, cola, _) = armar(s)
        await m.abrir()
        s.sinRed = true
        _ = await m.enviarDudaPorTexto(video: "FT-9a", "nueva")
        s.sinRed = false
        // Llegó al servidor pero la respuesta se perdió; el get la trae mientras sigue en la cola.
        s.responder("entregas_app_get", Self.conNueva)
        await m.abrir()
        #expect(m.pendientes.count == 1 && m.pendientesSinLlegar.isEmpty, "no se ve dos veces")
        await cola.drenar()
        await hasta { m.pendientes.isEmpty }
        #expect(ReglasGuiaRenglones.de(m.guia?.clips.first { $0.id == "FT-9a" }?.duda) == ["¿Puedo cambiar el arroz por fideos?", "nueva"])
    }

    @Test func unGetViejoNoBorraLaDudaRecienConfirmada() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json, "entregas_app_duda": "true"])
        let (m, cola, _) = armar(s)
        await m.abrir()
        // Un get sale (y tarda) antes de que la duda se confirme: vuelve sin ella.
        s.demorar("entregas_app_get", .milliseconds(600))
        let carga = Task { await m.abrir() }
        try? await Task.sleep(for: .milliseconds(100))
        _ = await m.enviarDudaPorTexto(video: "FT-9a", "nueva")
        await cola.drenar()
        await hasta { m.pendientes.isEmpty && m.envios["FT-9a"] == .listo }
        await carga.value
        #expect(ReglasGuiaRenglones.de(m.guia?.clips.first { $0.id == "FT-9a" }?.duda) == ["¿Puedo cambiar el arroz por fideos?", "nueva"])
        // Un get que sale después de la confirmación ya la trae: no se agrega de nuevo.
        s.demorar("entregas_app_get", nil)
        s.responder("entregas_app_get", Self.conNueva)
        await m.abrir()
        #expect(ReglasGuiaRenglones.de(m.guia?.clips.first { $0.id == "FT-9a" }?.duda) == ["¿Puedo cambiar el arroz por fideos?", "nueva"])
    }

    @Test func laDudaDeLaLlamadaQueYaLlegoNoCuentaDosVeces() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json])
        let (m, _, _) = armar(s)
        await m.abrir()
        let antes = m.dudasLlamadaContadas
        s.sinRed = true
        m.borradores[""] = "¿Y los domingos?"
        _ = await m.enviarDudaLlamada()
        #expect(m.dudasLlamadaContadas == antes + 1)
        s.sinRed = false
        s.responder("entregas_app_get", GuiaMuestra.json.replacingOccurrences(
            of: #""dudas_llamada":["#, with: #""dudas_llamada":[{"texto":"¿Y los domingos?","en":null},"#))
        await m.abrir()
        #expect(m.dudasLlamadaContadas == antes + 1, "la de la cola ya vino en el get")
    }

    @Test func dosAvancesALaVezSeMezclanSinPisarse() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json])
        let (m, cola, _) = armar(s)
        await m.abrir()
        s.sinRed = true
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await m.avance(video: "FT-2a", segundos: 40, visto: false) }
            g.addTask { await m.avance(video: "FT-2a", segundos: 20, visto: true) }
            g.addTask { await m.avance(video: "FT-2a", segundos: 30, visto: false) }
        }
        let ops = await cola.operaciones.filter { $0.kind == ModeloGuia.kindAvance }
        #expect(ops.count == 1)
        #expect(ops.first?.payload["segundos"] == .numero(40) && ops.first?.payload["visto"] == .bool(true))
        let c = m.guia?.clips.first { $0.id == "FT-2a" }
        #expect(c?.segundos == 40 && c?.visto == true)
    }

    @Test func laTarjetaNoRetrocedeConAvancesEnLaCola() async {
        let s = ServidorGuia(["entregas_app_get": GuiaMuestra.json])
        let (m, _, _) = armar(s)
        await m.abrir()
        let antes = m.resumen?.vistos ?? 0
        s.sinRed = true
        await m.avance(video: "FT-2a", segundos: 100, visto: true)
        #expect(m.resumen?.vistos == antes + 1)
        s.sinRed = false
        // El servidor todavía no recibió el avance.
        s.responder("entregas_app_resumen", #"{"ok":true,"total":11,"vistos":\#(antes),"minutos_restantes":6.2}"#)
        await m.actualizarResumen()
        #expect(m.resumen?.vistos == antes + 1)
    }

    // MARK: - Después de la entrega (entregas_014)

    @Test func conMostrarTarjetaFalseSaleDeEntrenoYQuedaLaFila() async {
        let s = ServidorGuia(["entregas_app_resumen": #"{"ok":true,"total":13,"vistos":4,"minutos_restantes":7.4,"fecha_entrega":"2026-10-01T14:00:00+00:00","mostrar_tarjeta":false}"#])
        let (m, _, _) = armar(s)
        await m.actualizarResumen()
        #expect(!m.mostrarTarjeta && m.mostrarFila && !m.puedeQuitarDeEntreno && !m.puedeVolverAMostrar)
        #expect(s.llamadas(a: "entregas_app_get").isEmpty, "nada de esto llama al get")
        // Abrir la guía recalcula los conteos pero no pierde `mostrar_tarjeta`.
        s.responder("entregas_app_get", GuiaMuestra.json)
        await m.abrir()
        #expect(m.resumen?.total == 11 && m.resumen?.mostrarTarjetaServidor == false && !m.mostrarTarjeta)
        // Con avances en la cola el resumen nuevo también trae su `mostrar_tarjeta`.
        s.sinRed = true
        await m.avance(video: "FT-2a", segundos: 100, visto: true)
        s.sinRed = false
        s.responder("entregas_app_resumen", #"{"ok":true,"total":11,"vistos":4,"minutos_restantes":6.2,"fecha_entrega":null,"mostrar_tarjeta":true}"#)
        await m.actualizarResumen()
        #expect(m.resumen?.vistos == 5 && m.mostrarTarjeta && !m.mostrarFila)
    }

    @Test func sinLosCamposSeCuentaConLaFechaDeLaGuia() async {
        let vieja = GuiaMuestra.json.replacingOccurrences(of: #""fecha_entrega":null"#, with: #""fecha_entrega":"2026-01-01T10:00:00-03:00""#)
        let s = ServidorGuia(["entregas_app_get": vieja])
        let (m, _, _) = armar(s)
        await m.abrir()
        #expect(m.resumen?.fechaEntrega == "2026-01-01T10:00:00-03:00" && m.resumen?.mostrarTarjetaServidor == nil)
        #expect(!m.mostrarTarjeta && m.mostrarFila)
    }

    @Test func quitarDeEntrenoQuedaEnElTelefonoPorCliente() async {
        let s = ServidorGuia(["entregas_app_resumen": #"{"ok":true,"total":13,"vistos":4,"minutos_restantes":7.4,"fecha_entrega":null,"mostrar_tarjeta":true}"#])
        let (m, _, _) = armar(s)
        await m.actualizarResumen()
        #expect(m.mostrarTarjeta && !m.mostrarFila && m.puedeQuitarDeEntreno)
        m.quitarDeEntreno()
        #expect(!m.mostrarTarjeta && m.mostrarFila && m.puedeVolverAMostrar)
        let (otro, _, _) = armar(s)
        #expect(otro.quitadaDeEntreno && !otro.mostrarTarjeta, "otro arranque recuerda que la quitó")
        let ajeno = ModeloGuia(cliente: ClienteRPC(transporte: s), token: "otro_cliente_123456", outbox: nil,
                               disco: Disco(raiz: raiz, token: "otro_cliente_123456"))
        #expect(!ajeno.quitadaDeEntreno, "es por cliente")
        otro.volverAMostrarEnEntreno()
        let (tercero, _, _) = armar(s)
        #expect(!tercero.quitadaDeEntreno && tercero.mostrarTarjeta)
        // Con mostrar_tarjeta false ya no se ofrece volver.
        m.quitarDeEntreno()
        s.responder("entregas_app_resumen", #"{"ok":true,"total":13,"vistos":4,"minutos_restantes":7.4,"mostrar_tarjeta":false}"#)
        await m.actualizarResumen()
        #expect(!m.puedeVolverAMostrar && m.mostrarFila)
        #expect(s.llamadas(a: "entregas_app_get").isEmpty)
    }

    @Test func okFalseNoDejaNiTarjetaNiFila() async {
        let s = ServidorGuia(["entregas_app_resumen": #"{"ok":false}"#])
        let (m, _, _) = armar(s)
        await m.actualizarResumen()
        #expect(!m.mostrarTarjeta && !m.mostrarFila)
    }

    @Test func laDemoGuardaElAvanceEnMemoriaYNoTocaLaRed() async {
        let m = ModeloGuia(muestra: GuiaMuestra.guia)
        #expect(m.mostrarTarjeta && !m.mostrarFila)
        let antes = m.resumen?.vistos ?? 0
        await m.avance(video: "FT-2a", segundos: 30, visto: true)
        #expect(m.guia?.clips.first { $0.id == "FT-2a" }?.visto == true && m.resumen?.vistos == antes + 1)
        await m.abrir()
        await m.actualizarResumen()
        #expect(m.estado == .lista)
        m.quitarDeEntreno()
        #expect(!m.mostrarTarjeta && m.mostrarFila)
        let despues = ModeloGuia(muestra: GuiaMuestra.guia, mostrarTarjeta: false)
        #expect(!despues.mostrarTarjeta && despues.mostrarFila)
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
