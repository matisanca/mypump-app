import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Un servidor de mentira para la agenda: cada RPC contesta lo que se le diga (cuerpo y status), anota lo que le llegó y
/// puede quedarse sin red.
final class ServidorAgenda: Transporte, @unchecked Sendable {
    private let cerrojo = NSLock()
    private var _respuestas: [String: (Int, String)] = [:]
    private var _colas: [String: [(Int, String)]] = [:]
    private var _llamadas: [(fn: String, cuerpo: JSONValue)] = []
    private var _sinRed = false

    init(_ r: [String: String] = [:]) { _respuestas = r.mapValues { (200, $0) } }

    var sinRed: Bool {
        get { cerrojo.withLock { _sinRed } }
        set { cerrojo.withLock { _sinRed = newValue } }
    }
    func responder(_ fn: String, _ cuerpo: String, status: Int = 200) { cerrojo.withLock { _respuestas[fn] = (status, cuerpo) } }
    /// Respuestas de una sola vez, en orden (después, la fija).
    func encadenar(_ fn: String, _ cuerpos: [String]) { cerrojo.withLock { _colas[fn] = cuerpos.map { (200, $0) } } }
    func llamadas(a fn: String) -> [JSONValue] { cerrojo.withLock { _llamadas.filter { $0.fn == fn }.map(\.cuerpo) } }

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url?.lastPathComponent ?? ""
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
        let (r, sinRed): ((Int, String)?, Bool) = cerrojo.withLock {
            _llamadas.append((fn, cuerpo))
            if _sinRed { return (nil, true) }
            if var c = _colas[fn], !c.isEmpty { let x = c.removeFirst(); _colas[fn] = c; return (x, false) }
            return (_respuestas[fn], false)
        }
        if sinRed { throw URLError(.notConnectedToInternet) }
        let (status, texto) = r ?? (200, "true")
        return (Data(texto.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
private func hasta(_ condicion: () -> Bool, _ segundos: Double = 3) async {
    let limite = Date().addingTimeInterval(segundos)
    while !condicion() && Date() < limite { try? await Task.sleep(for: .milliseconds(20)) }
}

private let sinFuncion = #"{"code":"PGRST202","message":"Could not find the function"}"#
private let franjas = #"[{"id":"f1","inicio":"2099-11-12T10:00:00-03:00","fin":"2099-11-12T12:00:00-03:00"},{"id":"f2","inicio":"2099-11-12T14:00:00-03:00","fin":"2099-11-12T16:00:00-03:00"}]"#
private let habilitada = #"{"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"franjas":\#(franjas),"reserva":null}"#
private let pendiente = #"{"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"reserva":{"id":"r","inicio":"2099-11-12T10:00:00-03:00","fin":"2099-11-12T12:00:00-03:00","estado":"pendiente"}}"#
private let confirmada = #"{"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"reserva":{"id":"r","inicio":"2099-11-12T10:00:00-03:00","fin":"2099-11-12T12:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/abc-defg-hij"}}"#
private let reservaOk = #"{"ok":true,"reserva":{"id":"r","inicio":"2099-11-12T10:00:00-03:00","fin":"2099-11-12T12:00:00-03:00","estado":"pendiente"}}"#

@Suite("Agenda de la entrega: el modelo y la cola (2.2.0)", .serialized)
@MainActor
struct AgendaModeloTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-agenda-\(UUID().uuidString)")
    let token = "tok_prueba_agenda_123456"

    private func armar(_ s: ServidorAgenda, automatico: Bool = false) -> (ModeloGuia, Outbox, Disco) {
        let cliente = ClienteRPC(transporte: s)
        let disco = Disco(raiz: raiz, token: token)
        let escrituras = Escrituras(cliente: cliente, token: token)
        let cola = Outbox(archivo: disco.url("outbox.json"), reintentoAutomatico: automatico) { await escrituras.ejecutar($0) }
        let m = ModeloGuia(cliente: cliente, token: token, outbox: cola, disco: disco)
        Task { await cola.observar(estado: { _ in }, abandonadas: { ops in Task { @MainActor in m.alAbandonar(ops) } },
                                   guardadas: { ops in Task { @MainActor in m.alGuardar(ops) } }) }
        return (m, cola, disco)
    }

    // MARK: - Sin el servidor nuevo, la 2.1.0

    @Test func sinLa021TodoQuedaComoEnLa210() async {
        // El get y el resumen de siempre (sin campos nuevos) y la agenda que no existe.
        let s = ServidorAgenda(["entregas_app_get": GuiaMuestra.json,
                                "entregas_app_resumen": #"{"ok":true,"total":11,"vistos":4,"minutos_restantes":6.2,"mostrar_tarjeta":true}"#])
        s.responder("entregas_app_agenda", sinFuncion, status: 404)
        let (m, _, disco) = armar(s)
        await m.actualizarResumen()
        await m.abrir()
        await m.agenda.consultar()
        #expect(m.vistaAgenda == .nada && !m.agenda.disponible && !m.agenda.desdeCache)
        #expect(disco.leer(AgendaGuia.self, "guia_agenda.json") == nil)
        #expect(m.clips.first?.id == "FT-25a" && ReglasGuia.bloques(m.clips).allSatisfy { !$0.novedad })
        #expect(m.avanceNovedad == nil && m.tarjetaDestacada && m.reservaParaEntrar() == nil)
        #expect(m.resumen == ResumenGuia(ok: true, total: 11, vistos: 4, minutosRestantes: 6.2, mostrarTarjetaServidor: true))
        // Ocultar sigue igual: queda oculta (sin novedad no vuelve).
        m.quitarDeEntreno()
        #expect(!m.mostrarTarjeta && m.mostrarFila)
        // Otro rechazo (400) tampoco muestra nada; una agenda guardada de antes se borra.
        disco.guardar(AgendaGuia(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(habilitada.utf8))) ?? .null), "guia_agenda.json")
        let (m2, _, _) = armar(s)
        #expect(m2.agenda.disponible, "la copia de antes")
        await m2.agenda.consultar()
        #expect(!m2.agenda.disponible && disco.leer(AgendaGuia.self, "guia_agenda.json") == nil)
    }

    @Test func okFalseYSinRed() async {
        let s = ServidorAgenda(["entregas_app_agenda": habilitada])
        let (m, _, disco) = armar(s)
        await m.agenda.consultar()
        #expect(m.agenda.disponible && !m.agenda.desdeCache && disco.leer(AgendaGuia.self, "guia_agenda.json") != nil)
        // Sin red: lo guardado, con «Sin conexión».
        s.sinRed = true
        await m.agenda.consultar()
        #expect(m.agenda.disponible && m.agenda.desdeCache)
        // Al volver a abrir la app sin red, la copia.
        let (m2, _, _) = armar(s)
        #expect(m2.agenda.agenda?.franjas.count == 2)
        s.sinRed = false
        s.responder("entregas_app_agenda", #"{"ok":false,"motivo":"sin_guia"}"#)
        await m.agenda.consultar()
        #expect(m.vistaAgenda == .nada && disco.leer(AgendaGuia.self, "guia_agenda.json") == nil)
    }

    // MARK: - La reserva por la cola

    @Test func reservarEsIdempotenteYSinRedNoGastaIntentos() async {
        let s = ServidorAgenda(["entregas_app_agenda": habilitada, "entregas_app_reservar": reservaOk])
        let (m, cola, _) = armar(s)
        await m.agenda.consultar()
        let f = m.agenda.agenda!.franjas[0]
        s.sinRed = true
        // Dos toques seguidos: una sola op.
        await m.agenda.reservar(f)
        await m.agenda.reservar(m.agenda.agenda!.franjas[1])
        var ops = await cola.operaciones.filter { $0.kind == ModeloAgenda.kind }
        #expect(ops.count == 1 && m.agenda.enCola?.id == "f1")
        #expect(m.vistaAgenda == .reservando)
        let pid = ops[0].payload["id"]?.comoTexto
        #expect(pid.flatMap(UUID.init(uuidString:)) != nil && ops[0].payload["franja"] == .texto("f1"))
        // Sin red, dos pasadas: sigue en la cola, sin gastar intentos, con el mismo p_id.
        await cola.drenarTodo(); await cola.drenarTodo()
        ops = await cola.operaciones.filter { $0.kind == ModeloAgenda.kind }
        #expect(ops.count == 1 && ops[0].tries == 0 && ops[0].payload["id"]?.comoTexto == pid)
        // Vuelve la red: sale con ese mismo p_id.
        s.sinRed = false
        await cola.drenarTodo()
        let pedidos = s.llamadas(a: "entregas_app_reservar")
        #expect(pedidos.count == 3 && Set(pedidos.map { $0["p_id"]?.comoTexto ?? "" }).count == 1 && pedidos.last?["p_franja"] == .texto("f1"))
        #expect(pedidos.last?["p_token"] == .texto(token))
        await hasta { m.agenda.enCola == nil }
        #expect(m.agenda.reserva?.estado == .pendiente && m.vistaAgenda == .reservando)
        let vacia = await cola.operaciones
        #expect(vacia.isEmpty)
        // Ya hay una vigente: otra franja no se encola.
        await m.agenda.reservar(f)
        let sigue = await cola.operaciones
        #expect(sigue.isEmpty)
    }

    @Test func pendienteSeConsultaHastaConfirmarse() async {
        let s = ServidorAgenda(["entregas_app_agenda": habilitada, "entregas_app_reservar": reservaOk])
        let cliente = ClienteRPC(transporte: s)
        let disco = Disco(raiz: raiz, token: token)
        let escrituras = Escrituras(cliente: cliente, token: token)
        let cola = Outbox(archivo: nil, reintentoAutomatico: false) { await escrituras.ejecutar($0) }
        let a = ModeloAgenda(cliente: cliente, token: token, outbox: cola, disco: disco, esperaSondeo: .milliseconds(30))
        Task { await cola.observar(estado: { _ in }, abandonadas: { _ in }, guardadas: { ops in Task { @MainActor in a.alGuardar(ops) } }) }
        await a.consultar()
        await a.reservar(a.agenda!.franjas[0])
        s.encadenar("entregas_app_agenda", [pendiente, pendiente])
        s.responder("entregas_app_agenda", confirmada)
        await cola.drenarTodo()
        await hasta({ a.reserva?.estado == .confirmada }, 5)
        #expect(a.reserva?.meetUrl?.absoluteString == "https://meet.google.com/abc-defg-hij")
        guard case .confirmada = ReglasAgenda.vista(a.agenda, faltanLocal: 0, enCola: false) else { Issue.record("no se confirmó"); return }
        await hasta({ !a.sondeando }, 2)
        #expect(!a.sondeando, "confirmada, el sondeo para")
        // La copia guarda la confirmada: sin red, el link sigue a mano.
        #expect(disco.leer(AgendaGuia.self, "guia_agenda.json")?.reserva?.meetUrl != nil)
    }

    @Test func elSondeoTieneTope() async {
        let s = ServidorAgenda(["entregas_app_agenda": pendiente])
        let reloj = RelojPrueba()
        let a = ModeloAgenda(cliente: ClienteRPC(transporte: s), token: token, outbox: nil, disco: nil, esperaSondeo: .milliseconds(20),
                             reloj: { reloj.ahora })
        await a.consultar()
        #expect(a.sondeando)
        reloj.ahora += 61
        await hasta({ !a.sondeando }, 2)
        #expect(!a.sondeando, "pasados los 60 s se deja de consultar")
        // Al volver a primer plano: una consulta y otra ventana.
        let antes = s.llamadas(a: "entregas_app_agenda").count
        await a.alVolver()
        #expect(s.llamadas(a: "entregas_app_agenda").count == antes + 1 && a.sondeando)
        a.pararSondeo()
        #expect(!a.sondeando)
    }

    @Test func tomadaVuelveALasFranjas() async {
        let s = ServidorAgenda(["entregas_app_agenda": habilitada, "entregas_app_reservar": #"{"ok":false,"motivo":"tomada"}"#])
        let (m, cola, _) = armar(s)
        await m.agenda.consultar()
        await m.agenda.reservar(m.agenda.agenda!.franjas[0])
        s.responder("entregas_app_agenda", #"{"ok":true,"autorizada":true,"habilitada":true,"franjas":[{"id":"f2","inicio":"2099-11-12T14:00:00-03:00","fin":"2099-11-12T16:00:00-03:00"}]}"#)
        await cola.drenarTodo()
        await hasta { m.agenda.enCola == nil && m.agenda.agenda?.franjas.count == 1 }
        #expect(m.vistaAgenda == .franjas(aviso: .tomada) && m.agenda.anuncio == "Ese horario se ocupó recién, elegí otro.")
        let quedan = await cola.operaciones, fallidos = await cola.fallidos
        #expect(quedan.isEmpty && fallidos.isEmpty)
        // Elegir otra borra el aviso.
        s.responder("entregas_app_reservar", reservaOk)
        await m.agenda.reservar(m.agenda.agenda!.franjas[0])
        #expect(m.agenda.aviso == nil)
    }

    @Test func elFalloDelDaemonVuelveConLasFranjas() async {
        let s = ServidorAgenda(["entregas_app_agenda": #"{"ok":true,"autorizada":true,"habilitada":true,"franjas":\#(franjas),"reserva":{"inicio":"2099-11-12T10:00:00-03:00","fin":"2099-11-12T12:00:00-03:00","estado":"fallo","motivo":"tomada"}}"#])
        let (m, _, _) = armar(s)
        await m.agenda.consultar()
        #expect(m.vistaAgenda == .franjas(aviso: .tomada))
        // `vencida` (más de 30 min pendiente) o un motivo que no se conoce: «No pudimos reservar…», con las franjas.
        for motivo in ["vencida", "otro_nuevo", "null"] {
            let v = motivo == "null" ? "null" : "\"\(motivo)\""
            s.responder("entregas_app_agenda", #"{"ok":true,"autorizada":true,"habilitada":true,"franjas":\#(franjas),"reserva":{"inicio":"2099-11-12T10:00:00-03:00","fin":"2099-11-12T12:00:00-03:00","estado":"fallo","motivo":\#(v)}}"#)
            await m.agenda.consultar()
            #expect(m.vistaAgenda == .franjas(aviso: .error), "\(motivo)")
        }
        #expect(ReglasAgenda.Aviso.error.texto == "No pudimos reservar ese horario, elegí otro.")
    }

    @Test func yaTieneMuestraLaVigenteYLosDemasMotivos() async {
        let s = ServidorAgenda(["entregas_app_agenda": habilitada,
                                "entregas_app_reservar": #"{"ok":false,"motivo":"ya_tiene","reserva":{"id":"otra","inicio":"2099-11-13T10:00:00-03:00","fin":"2099-11-13T12:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/x"}}"#])
        let (m, cola, _) = armar(s)
        await m.agenda.consultar()
        s.encadenar("entregas_app_agenda", [#"{"ok":true,"autorizada":true,"habilitada":true,"reserva":{"id":"otra","inicio":"2099-11-13T10:00:00-03:00","fin":"2099-11-13T12:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/x"}}"#])
        await m.agenda.reservar(m.agenda.agenda!.franjas[0])
        await cola.drenarTodo()
        await hasta { m.agenda.reserva?.id == "otra" }
        #expect(m.agenda.reserva?.estado == .confirmada)
        for (motivo, aviso) in [("franja", ReglasAgenda.Aviso.vencida), ("error", .error), ("raro", .error)] {
            let s2 = ServidorAgenda(["entregas_app_agenda": habilitada, "entregas_app_reservar": #"{"ok":false,"motivo":"\#(motivo)"}"#])
            let (m2, c2, _) = armar(s2)
            await m2.agenda.consultar()
            await m2.agenda.reservar(m2.agenda.agenda!.franjas[0])
            await c2.drenarTodo()
            await hasta { m2.agenda.enCola == nil }
            #expect(m2.agenda.aviso == aviso, "\(motivo)")
        }
        // `obligatorios` y `autorizada`: la agenda vuelve a decir qué pasa (sin aviso).
        let s3 = ServidorAgenda(["entregas_app_agenda": habilitada, "entregas_app_reservar": #"{"ok":false,"motivo":"autorizada"}"#])
        let (m3, c3, _) = armar(s3)
        await m3.agenda.consultar()
        await m3.agenda.reservar(m3.agenda.agenda!.franjas[0])
        s3.responder("entregas_app_agenda", #"{"ok":true,"autorizada":false,"faltan":0}"#)
        await c3.drenarTodo()
        await hasta { m3.agenda.agenda?.autorizada == false }
        #expect(m3.agenda.aviso == nil && m3.vistaAgenda == .noAutorizada(faltan: 0))
    }

    @Test func sinLaFuncionDeReservarNoSeTraba() async {
        let s = ServidorAgenda(["entregas_app_agenda": habilitada])
        s.responder("entregas_app_reservar", sinFuncion, status: 404)
        let (m, cola, _) = armar(s)
        await m.agenda.consultar()
        await m.agenda.reservar(m.agenda.agenda!.franjas[0])
        await cola.drenarTodo()
        await hasta { m.agenda.enCola == nil }
        let quedan = await cola.operaciones
        #expect(m.agenda.aviso == .error && quedan.isEmpty)
    }

    @Test func laReservaDeLaColaSobreviveAlCierre() async {
        let s = ServidorAgenda(["entregas_app_agenda": habilitada, "entregas_app_reservar": reservaOk])
        let (m, cola, _) = armar(s)
        await m.agenda.consultar()
        s.sinRed = true
        await m.agenda.reservar(m.agenda.agenda!.franjas[1])
        await cola.drenarTodo()
        // Otra apertura con la misma cola guardada: «reservando» y sin otra op.
        let (m2, cola2, _) = armar(s)
        await m2.agenda.cargarDeLaCola()
        #expect(m2.agenda.enCola?.id == "f2" && m2.vistaAgenda == .reservando)
        await m2.agenda.reservar(m2.agenda.agenda!.franjas[0])
        let ops = await cola2.operaciones
        #expect(ops.filter { $0.kind == ModeloAgenda.kind }.count == 1)
    }

    @Test func laReservaNoFrenaLaColaDeLasDemas() async {
        // En su carril: sin respuesta de reservar, el avance sale igual.
        let s = ServidorAgenda(["entregas_app_agenda": habilitada, "entregas_app_get": GuiaMuestra.jsonV2()])
        s.responder("entregas_app_reservar", "{}", status: 503)
        let (m, cola, _) = armar(s)
        await m.abrir()
        await m.agenda.consultar()
        await m.agenda.reservar(m.agenda.agenda!.franjas[0])
        await m.avance(video: "FT-26a", segundos: 30, visto: true)
        await cola.drenar()
        let ops = await cola.operaciones
        #expect(ops.map(\.kind) == [ModeloAgenda.kind], "el avance salió; la reserva espera")
        #expect(ops[0].tries == 0)
    }

    // MARK: - Con la guía

    @Test func verElUltimoObligatorioConsultaLaAgenda() async {
        let s = ServidorAgenda(["entregas_app_get": GuiaMuestra.jsonV2(),
                                "entregas_app_agenda": #"{"ok":true,"autorizada":true,"habilitada":false,"faltan":1}"#])
        let (m, cola, _) = armar(s)
        await m.abrir()
        await m.agenda.consultar()
        #expect(m.vistaAgenda == .bloqueada(faltan: 1) && m.faltanLocal == 1 && m.faltanAgenda == 1)
        let antes = s.llamadas(a: "entregas_app_agenda").count
        s.responder("entregas_app_agenda", habilitada)
        await m.avance(video: "N-1", segundos: 20, visto: true)
        #expect(m.faltanLocal == 0)
        await cola.drenarTodo()
        await hasta { m.vistaAgenda == .franjas(aviso: nil) }
        #expect(s.llamadas(a: "entregas_app_agenda").count >= antes + 1)
        #expect(m.vistaAgenda == .franjas(aviso: nil))
        // Ver uno que no cuenta no consulta de nuevo.
        let despues = s.llamadas(a: "entregas_app_agenda").count
        await m.avance(video: "FT-26a", segundos: 30, visto: true)
        await cola.drenarTodo()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(s.llamadas(a: "entregas_app_agenda").count == despues)
    }

    @Test func laNovedadHaceVolverLaTarjetaOcultada() async {
        let s = ServidorAgenda(["entregas_app_resumen": #"{"ok":true,"total":6,"vistos":4,"minutos_restantes":2,"mostrar_tarjeta":true}"#])
        let (m, _, disco) = armar(s)
        await m.actualizarResumen()
        m.quitarDeEntreno(ahora: ReglasGuia.instante("2026-11-04T18:00:00-03:00")!)
        #expect(!m.mostrarTarjeta)
        #expect(disco.leer(Double.self, "guia_quitada_en.json") != nil && disco.leer(Bool.self, "guia_quitada.json") == true)
        // Llega la tanda nueva, aprobada después de ocultarla: vuelve, como NOVEDAD.
        s.responder("entregas_app_resumen", #"{"ok":true,"total":6,"vistos":4,"minutos_restantes":2,"mostrar_tarjeta":true,"novedad_en":"2026-11-05T12:00:00-03:00","nuevos_total":2,"nuevos_vistos":0}"#)
        await m.actualizarResumen()
        #expect(m.mostrarTarjeta && m.tarjetaDestacada && m.avanceNovedad?.total == 2)
        // Ocultarla de nuevo guarda la fecha de ahora: con la misma novedad queda oculta, también al reabrir.
        m.quitarDeEntreno()
        #expect(!m.mostrarTarjeta)
        let (m2, _, _) = armar(s)
        #expect(!m2.mostrarTarjeta && m2.mostrarFila)
        // Volver a mostrar borra las dos marcas.
        m2.volverAMostrarEnEntreno()
        #expect(disco.leer(Double.self, "guia_quitada_en.json") == nil && disco.leer(Bool.self, "guia_quitada.json") == nil)
    }

    @Test func unaMarcaDeLa210SinFechaVuelveConLaNovedad() async {
        let disco = Disco(raiz: raiz, token: token)
        disco.guardar(true, "guia_quitada.json")
        let s = ServidorAgenda(["entregas_app_resumen": #"{"ok":true,"total":6,"vistos":4,"minutos_restantes":2,"mostrar_tarjeta":true}"#])
        let (m, _, _) = armar(s)
        await m.actualizarResumen()
        #expect(!m.mostrarTarjeta, "sin novedad, como la 2.1.0")
        s.responder("entregas_app_resumen", #"{"ok":true,"total":6,"vistos":4,"minutos_restantes":2,"mostrar_tarjeta":true,"novedad_en":"2026-11-05T12:00:00-03:00"}"#)
        await m.actualizarResumen()
        #expect(m.mostrarTarjeta)
    }

    @Test func laGuiaAbiertaConservaLoNuevoDelResumen() async {
        let s = ServidorAgenda(["entregas_app_get": GuiaMuestra.jsonV2(),
                                "entregas_app_resumen": #"{"ok":true,"total":6,"vistos":4,"minutos_restantes":1.0,"mostrar_tarjeta":true,"novedad_en":"2026-11-05T12:00:00-03:00","nuevos_total":2,"nuevos_vistos":1,"reserva":{"inicio":"2099-11-12T10:00:00-03:00","fin":"2099-11-12T12:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/abc"}}"#])
        let (m, cola, _) = armar(s)
        await m.actualizarResumen()
        await m.abrir()
        await m.avance(video: "N-1", segundos: 20, visto: true)
        // La tarjeta sigue la guía (lo nuevo, visto), sin perder la fecha, la novedad ni la reserva del resumen.
        #expect(m.resumen?.novedadEn == "2026-11-05T12:00:00-03:00" && m.resumen?.reserva?.estado == .confirmada)
        #expect(m.resumen?.nuevosTotal == 2 && m.resumen?.nuevosVistos == 2)
        #expect(m.avanceNovedad == nil)
        // Con el avance en la cola, el resumen del servidor (que todavía no lo tiene) no hace retroceder lo nuevo.
        await m.actualizarResumen()
        #expect(m.resumen?.nuevosVistos == 2 && m.avanceNovedad == nil)
        await cola.drenarTodo()
        #expect(m.reservaParaEntrar(ahora: ReglasGuia.instante("2099-11-12T09:45:00-03:00")!) != nil)
        #expect(m.reservaParaEntrar(ahora: ReglasGuia.instante("2099-11-12T09:00:00-03:00")!) == nil)
    }

    // MARK: - La demo

    @Test func laDemoSeHabilitaSolaYConfirmaSinVideollamada() async {
        let a = AgendaGuia(ok: true, autorizada: true, habilitada: false, franjas: [
            FranjaAgenda(id: "d1", inicio: "2099-11-12T10:00:00-03:00", fin: "2099-11-12T12:00:00-03:00")])
        let m = ModeloGuia(muestra: GuiaMuestra.guiaV2, agenda: a)
        #expect(m.vistaAgenda == .bloqueada(faltan: 1))
        await m.avance(video: "N-1", segundos: 30, visto: true)
        #expect(m.vistaAgenda == .franjas(aviso: nil))
        await m.agenda.reservar(FranjaAgenda(id: "d1", inicio: "2099-11-12T10:00:00-03:00", fin: "2099-11-12T12:00:00-03:00"))
        guard case .confirmada(let r, .demo) = m.vistaAgenda else { Issue.record("la demo no confirmó: \(m.vistaAgenda)"); return }
        #expect(r.meetUrl == nil && ReglasAgenda.Aviso.demo.texto == "En la demo no se crea ninguna videollamada.")
        // Sin autorizar (el punto de control) la demo también lo muestra.
        let n = ModeloGuia(muestra: GuiaMuestra.guiaV2, agenda: AgendaGuia(ok: true, autorizada: false))
        #expect(n.vistaAgenda == .noAutorizada(faltan: 1))
        // Sin agenda en la muestra: nada (la maqueta de la 2.1.0).
        #expect(ModeloGuia(muestra: GuiaMuestra.guia).vistaAgenda == .nada)
    }
}

final class RelojPrueba: @unchecked Sendable {
    private let cerrojo = NSLock()
    private var _ahora: Double = 1_000
    var ahora: Double {
        get { cerrojo.withLock { _ahora } }
        set { cerrojo.withLock { _ahora = newValue } }
    }
}
