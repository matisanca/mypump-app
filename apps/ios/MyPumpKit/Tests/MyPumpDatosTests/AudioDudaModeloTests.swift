import Foundation
import Testing
@testable import MyPumpDatos
@testable import MyPumpModelos
@testable import MyPumpReglas

/// El servidor de mentira de la 019: las RPC por nombre, la subida a Storage con el status que se pida y la red que se
/// cae en un paso.
final class ServidorAudio: Transporte, @unchecked Sendable {
    private let cerrojo = NSLock()
    private var _rpc: [String: (Int, String)] = [:]
    private var _storage: (Int, String) = (200, #"{"Key":"entregas-audio/x.m4a"}"#)
    private var _sinRedEn: Set<String> = []
    private var _pedidos: [URLRequest] = []
    /// Respuestas que salen una vez, en orden, antes de la fija.
    private var _primero: [String: [String]] = [:]

    init() {
        _rpc = [
            "entregas_app_audio_iniciar": (200, #"{"ok":true,"id":"ID","bucket":"entregas-audio","ruta":"cliente/ID.m4a","mime":"audio/mp4"}"#),
            "entregas_app_audio_subido": (200, #"{"ok":true,"estado":"subido"}"#),
            "entregas_app_audios": (200, "[]"),
        ]
    }

    func rpc(_ fn: String, _ cuerpo: String, status: Int = 200) { cerrojo.withLock { _rpc[fn] = (status, cuerpo) } }
    func primero(_ fn: String, _ cuerpos: [String]) { cerrojo.withLock { _primero[fn] = cuerpos } }
    func storage(_ status: Int, _ cuerpo: String = "{}") { cerrojo.withLock { _storage = (status, cuerpo) } }
    /// `"storage"` o el nombre de la RPC: ese paso tira sin red.
    func sinRed(en paso: String?, _ si: Bool = true) { cerrojo.withLock { if let paso { if si { _sinRedEn.insert(paso) } else { _sinRedEn.remove(paso) } } else { _sinRedEn = [] } } }
    var pedidos: [URLRequest] { cerrojo.withLock { _pedidos } }
    func pedidos(a paso: String) -> [URLRequest] { pedidos.filter { Self.paso($0) == paso } }
    func cuerpo(_ p: URLRequest) -> JSONValue { p.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null }

    static func paso(_ p: URLRequest) -> String {
        let path = p.url?.path ?? ""
        return path.contains("/storage/v1/object/") ? "storage" : (p.url?.lastPathComponent ?? "")
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let paso = Self.paso(pedido)
        let (r, caida): ((Int, String)?, Bool) = cerrojo.withLock {
            _pedidos.append(pedido)
            if var q = _primero[paso], !q.isEmpty {
                let c = q.removeFirst(); _primero[paso] = q
                return ((200, c), _sinRedEn.contains(paso))
            }
            return (paso == "storage" ? _storage : _rpc[paso], _sinRedEn.contains(paso))
        }
        if caida { throw URLError(.notConnectedToInternet) }
        let (status, cuerpo) = r ?? (404, #"{"code":"PGRST202","message":"no existe"}"#)
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// El micrófono de mentira: escribe bytes en el archivo al terminar.
@MainActor
final class GrabadorDoble: GrabadorAudio {
    var permiso: PermisoMicrofono = .dado
    var respuestaPermiso = true
    var falla: AvisoAudio?
    var alInterrumpir: (@MainActor () -> Void)?
    private(set) var archivo: URL?
    private(set) var terminados = 0
    private(set) var pedidos = 0

    func pedirPermiso() async -> Bool { pedidos += 1; permiso = respuestaPermiso ? .dado : .negado; return respuestaPermiso }
    func empezar(en archivo: URL) -> AvisoAudio? {
        if let falla { return falla }
        self.archivo = archivo
        FileManager.default.createFile(atPath: archivo.path, contents: Data(repeating: 7, count: 4096))
        return nil
    }
    func terminar() { terminados += 1 }
}

/// Un reloj que avanza a mano.
final class RelojDoble: @unchecked Sendable {
    private let cerrojo = NSLock()
    private var _t: Double = 1000
    var t: Double { get { cerrojo.withLock { _t } } set { cerrojo.withLock { _t = newValue } } }
    func avanzar(_ s: Double) { t += s }
}

@MainActor
private func hasta(_ condicion: () -> Bool, _ segundos: Double = 3) async {
    let limite = Date().addingTimeInterval(segundos)
    while !condicion() && Date() < limite { try? await Task.sleep(for: .milliseconds(20)) }
}

@MainActor
private func hastaA(_ condicion: () async -> Bool, _ segundos: Double = 3) async {
    let limite = Date().addingTimeInterval(segundos)
    while await !condicion(), Date() < limite { try? await Task.sleep(for: .milliseconds(20)) }
}

@Suite("Tu guía: las dudas en audio (modelo y cola)", .serialized)
@MainActor
struct AudioDudaModeloTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("audio-\(UUID().uuidString)")
    let token = "token-de-prueba-audio"

    private struct Armado {
        let modelo: ModeloAudioDuda
        let cola: Outbox
        let grabador: GrabadorDoble
        let reloj: RelojDoble
        let disco: Disco
    }

    private func armar(_ s: ServidorAudio, automatico: Bool = false, sondeo: Duration = .milliseconds(30)) -> Armado {
        let cliente = ClienteRPC(transporte: s)
        let disco = Disco(raiz: raiz, token: token)
        let escrituras = Escrituras(cliente: cliente, token: token, carpetaAudios: disco.url("audios"))
        let cola = Outbox(archivo: disco.url("outbox.json"), reintentoAutomatico: automatico) { await escrituras.ejecutar($0) }
        let reloj = RelojDoble()
        let m = ModeloAudioDuda(cliente: cliente, token: token, outbox: cola, disco: disco, reloj: { reloj.t }, esperaSondeo: sondeo)
        let g = GrabadorDoble()
        m.grabador = g
        Task { await cola.observar(estado: { _ in }, abandonadas: { ops in Task { @MainActor in m.alAbandonar(ops) } },
                                   guardadas: { ops in Task { @MainActor in m.alGuardar(ops) } }) }
        return Armado(modelo: m, cola: cola, grabador: g, reloj: reloj, disco: disco)
    }

    /// Graba `segundos` y queda revisando.
    private func grabar(_ a: Armado, _ segundos: Double = 12) async {
        a.modelo.tocarGrabar()
        await hasta { a.modelo.maquina.grabando }
        a.reloj.avanzar(segundos)
        a.modelo.terminar()
    }

    private func archivos(_ a: Armado) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: a.disco.url("audios").path)) ?? []
    }

    @Test func grabarRevisarYMandarSubeConLos3PasosYBorraElArchivo() async {
        let s = ServidorAudio()
        let a = armar(s)
        var pausados = 0
        a.modelo.alEmpezar = { pausados += 1 }
        await grabar(a, 12.5)
        #expect(a.modelo.fase == .revisando(segundos: 12.5))
        #expect(pausados == 1)   // al grabar se pausa el video
        #expect(a.grabador.terminados == 1)
        #expect(archivos(a).count == 1)
        a.modelo.mandar()
        await hastaA { await a.cola.pendientes == 1 }
        #expect(a.modelo.fase == .reposo)
        #expect(a.modelo.filas.map(\.estado) == [.mandando])
        let op = await a.cola.operaciones[0]
        #expect(op.kind == "guia_audio" && op.dedupeKey == "guia_audio_\(op.payload["id"]!.comoTexto!)")
        await a.cola.drenar()
        await hasta { a.modelo.filas.first?.estado == .subido }
        #expect(await a.cola.pendientes == 0)
        // iniciar con el p_id, el mime y los bytes; la subida con el mime exacto y sin pisar; subido con el mismo p_id.
        let ini = s.cuerpo(s.pedidos(a: "entregas_app_audio_iniciar")[0])
        let id = op.payload["id"]!.comoTexto!
        #expect(ini["p_id"] == .texto(id) && ini["p_mime"] == .texto("audio/mp4") && ini["p_bytes"] == .numero(4096) && ini["p_segundos"] == .numero(13))
        let sub = s.pedidos(a: "storage")[0]
        #expect(sub.url?.path == "/storage/v1/object/entregas-audio/cliente/ID.m4a")
        #expect(sub.value(forHTTPHeaderField: "Content-Type") == "audio/mp4")
        #expect(sub.value(forHTTPHeaderField: "x-upsert") == "false")
        #expect(sub.value(forHTTPHeaderField: "apikey") != nil && sub.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
        #expect(sub.httpBody?.count == 4096)
        #expect(s.cuerpo(s.pedidos(a: "entregas_app_audio_subido")[0])["p_id"] == .texto(id))
        // Confirmado: el archivo local se borra.
        await hasta { archivos(a).isEmpty }
        #expect(archivos(a).isEmpty)
    }

    @Test func sinRedNoGastaIntentosYReintentaConElMismoId() async {
        let s = ServidorAudio()
        let a = armar(s)
        await grabar(a)
        a.modelo.mandar()
        await hastaA { await a.cola.pendientes == 1 }
        for paso in ["entregas_app_audio_iniciar", "storage", "entregas_app_audio_subido"] {
            s.sinRed(en: paso)
            await a.cola.drenar()
            #expect(await a.cola.operaciones.first?.tries == 0, "\(paso)")
            #expect(a.modelo.filas.map(\.estado) == [.mandando])
            s.sinRed(en: paso, false)
        }
        await a.cola.drenar()
        await hasta { a.modelo.filas.first?.estado == .subido }
        let ids = Set(s.pedidos(a: "entregas_app_audio_iniciar").compactMap { s.cuerpo($0)["p_id"]?.comoTexto })
        #expect(ids.count == 1)   // cada reintento pide el ticket con el mismo p_id
        #expect(s.pedidos(a: "entregas_app_audio_iniciar").count == 4)
    }

    @Test func un403OUn409DeStorageLoDecideSubido() async {
        for (status, cuerpo) in [(403, #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#),
                                 (409, "{}"), (400, #"{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}"#)] {
            let s = ServidorAudio()
            s.storage(status, cuerpo)
            let a = armar(s)
            await grabar(a)
            a.modelo.mandar()
            await hastaA { await a.cola.pendientes == 1 }
            await a.cola.drenar()
            await hasta { a.modelo.filas.first?.estado == .subido }
            #expect(a.modelo.filas.first?.estado == .subido)
            #expect(s.pedidos(a: "entregas_app_audio_subido").count == 1)
        }
    }

    @Test func unMotivoDelServidorSeMuestraYNoSeReintenta() async {
        for (motivo, aviso) in [("tope", AvisoAudio.tope), ("formato", .formato), ("largo", .largo), ("error", .yaFallo)] {
            let s = ServidorAudio()
            s.rpc("entregas_app_audio_iniciar", #"{"ok":false,"motivo":"\#(motivo)"}"#)
            let a = armar(s)
            await grabar(a)
            a.modelo.mandar()
            await hastaA { await a.cola.pendientes == 1 }
            await a.cola.drenar()
            await hasta { a.modelo.filas.first?.estado == .rechazado(aviso) }
            #expect(a.modelo.filas.first?.estado == .rechazado(aviso))
            #expect(a.modelo.anuncio == ReglasAudioDuda.texto(aviso))
            #expect(await a.cola.pendientes == 0)
            #expect(s.pedidos(a: "storage").isEmpty)
            await hasta { archivos(a).isEmpty }
            #expect(archivos(a).isEmpty)
        }
    }

    @Test func pendientesYStorageRechazadoGastanIntentoYAlFinalReintentar() async {
        let s = ServidorAudio()
        s.rpc("entregas_app_audio_iniciar", #"{"ok":false,"motivo":"pendientes"}"#)
        let a = armar(s)
        await grabar(a)
        a.modelo.mandar()
        await hastaA { await a.cola.pendientes == 1 }
        await a.cola.drenar()
        #expect(await a.cola.operaciones.first?.tries == 1)
        s.rpc("entregas_app_audio_iniciar", #"{"ok":true,"id":"ID","bucket":"entregas-audio","ruta":"cliente/ID.m4a","mime":"audio/mp4"}"#)
        // La subida «quizás subió» (403) pero subido dice siempre sin_archivo: gasta intento hasta abandonar.
        s.storage(403, #"{"statusCode":"403","error":"Unauthorized","message":"policy"}"#)
        s.rpc("entregas_app_audio_subido", #"{"ok":false,"motivo":"sin_archivo"}"#)
        for _ in 0..<8 { await a.cola.drenar() }
        await hasta { a.modelo.filas.first?.estado == .noSeMando }
        #expect(a.modelo.filas.first?.estado == .noSeMando)
        #expect(await a.cola.pendientes == 0)
        #expect(archivos(a).count == 1)   // abandonado: el archivo queda para «Reintentar»
        // «Reintentar»: el mismo p_id y el mismo archivo.
        s.storage(200)
        s.rpc("entregas_app_audio_subido", #"{"ok":true,"estado":"subido"}"#)
        let id = a.modelo.filas[0].id
        await a.modelo.reintentar(id)
        #expect(a.modelo.filas.first?.estado == .mandando)
        #expect(await a.cola.fallidos.isEmpty)
        await a.cola.drenar()
        await hasta { a.modelo.filas.first?.estado == .subido }
        #expect(s.cuerpo(s.pedidos(a: "entregas_app_audio_iniciar").last!)["p_id"] == .texto(id))
    }

    @Test func subidoSinArchivoVuelveASubirYVencidoPideElTicketDeNuevo() async {
        for motivo in ["sin_archivo", "vencido"] {
            let s = ServidorAudio()
            s.primero("entregas_app_audio_subido", [#"{"ok":false,"motivo":"\#(motivo)"}"#])
            let a = armar(s)
            await grabar(a)
            a.modelo.mandar()
            await hastaA { await a.cola.pendientes == 1 }
            await a.cola.drenar()
            await hasta { a.modelo.filas.first?.estado == .subido }
            #expect(a.modelo.filas.first?.estado == .subido, "\(motivo)")
            // Una vuelta más en el mismo intento: dos tickets con el mismo p_id, dos subidas y dos subido.
            #expect(s.pedidos(a: "entregas_app_audio_iniciar").count == 2 && s.pedidos(a: "storage").count == 2)
            #expect(Set(s.pedidos(a: "entregas_app_audio_iniciar").compactMap { s.cuerpo($0)["p_id"]?.comoTexto }).count == 1)
            #expect(s.pedidos(a: "entregas_app_audio_subido").count == 2)
        }
    }

    @Test func subidoConTamanoSeRechaza() async {
        let s = ServidorAudio()
        s.rpc("entregas_app_audio_subido", #"{"ok":false,"motivo":"tamano"}"#)
        let a = armar(s)
        await grabar(a)
        a.modelo.mandar()
        await hastaA { await a.cola.pendientes == 1 }
        await a.cola.drenar()
        await hasta { a.modelo.filas.first?.estado == .rechazado(.largo) }
        #expect(a.modelo.filas.first?.estado == .rechazado(.largo))
    }

    @Test func motivoIdVaDirectoAFallidosYReintentarUsaOtroId() async {
        let s = ServidorAudio()
        s.rpc("entregas_app_audio_iniciar", #"{"ok":false,"motivo":"id"}"#)
        s.rpc("mypump_get_cliente_info", #"[{"id":"x"}]"#)
        let a = armar(s)
        await grabar(a)
        a.modelo.mandar()
        await hastaA { await a.cola.pendientes == 1 }
        await a.cola.drenar()
        await hasta { a.modelo.filas.first?.estado == .noSeMando }
        #expect(a.modelo.filas.first?.estado == .noSeMando)
        let fallidos = await a.cola.fallidos
        #expect(fallidos.count == 1 && fallidos.first?.op.tries == 0 && fallidos.first?.motivo == "AUDIO_ID")
        let viejo = a.modelo.filas[0].id
        s.rpc("entregas_app_audio_iniciar", #"{"ok":true,"id":"ID","bucket":"entregas-audio","ruta":"cliente/ID.m4a","mime":"audio/mp4"}"#)
        await a.modelo.reintentar(viejo)
        #expect(a.modelo.filas.count == 1 && a.modelo.filas[0].id != viejo && a.modelo.filas[0].estado == .mandando)
        await a.cola.drenar()
        await hasta { a.modelo.filas.first?.estado == .subido }
        #expect(s.cuerpo(s.pedidos(a: "entregas_app_audio_iniciar").last!)["p_id"] == .texto(a.modelo.filas[0].id))
        #expect(archivos(a).isEmpty)
    }

    @Test func sinElArchivoSeDaPorPerdido() async {
        let s = ServidorAudio()
        let a = armar(s)
        await grabar(a)
        a.modelo.mandar()
        await hastaA { await a.cola.pendientes == 1 }
        for f in archivos(a) { try? FileManager.default.removeItem(at: a.disco.url("audios").appendingPathComponent(f)) }
        await a.cola.drenar()
        await hasta { a.modelo.filas.first?.estado == .rechazado(.noSeMando) }
        #expect(a.modelo.filas.first?.estado == .rechazado(.noSeMando))
        #expect(s.pedidos(a: "entregas_app_audio_iniciar").isEmpty)
    }

    @Test func tokenCaidoEstacionaSinGastar() async {
        let s = ServidorAudio()
        s.rpc("entregas_app_audio_iniciar", #"{"ok":false,"motivo":"token"}"#)
        s.rpc("mypump_get_cliente_info", "[]")
        let a = armar(s)
        await grabar(a)
        a.modelo.mandar()
        await hastaA { await a.cola.pendientes == 1 }
        await a.cola.drenar()
        #expect(await a.cola.operaciones.first?.tries == 0)
        #expect(a.modelo.filas.first?.estado == .mandando)
    }

    @Test func lasListaDelServidorSondeaMientrasHaySubidosYDeduplica() async {
        let s = ServidorAudio()
        s.rpc("entregas_app_audios", #"[{"id":"a1","estado":"subido","en":"2026-11-04T12:00:00Z"}]"#)
        let a = armar(s, sondeo: .milliseconds(30))
        await a.modelo.abrirSeccion()
        #expect(a.modelo.disponible)
        #expect(a.modelo.filas == [FilaAudio(id: "a1", estado: .subido)])
        s.rpc("entregas_app_audios", #"[{"id":"a1","estado":"transcripto","texto":" ¿Puedo entrenar en ayunas? "},{"id":"a2","estado":"error","segundos":14},{"estado":"raro"}]"#)
        await hasta { a.modelo.filas.first?.estado == .transcripto(" ¿Puedo entrenar en ayunas? ") }
        #expect(a.modelo.filas.map(\.estado) == [.transcripto(" ¿Puedo entrenar en ayunas? "), .error])
        #expect(a.modelo.transcriptos == ["¿Puedo entrenar en ayunas?"])
        #expect(a.modelo.servidor.last?.segundos == 14)
        // Sin subidos el sondeo se corta solo.
        let n = s.pedidos(a: "entregas_app_audios").count
        try? await Task.sleep(for: .milliseconds(200))
        #expect(s.pedidos(a: "entregas_app_audios").count == n)
    }

    @Test func elSondeoSeFrenaAlCerrarLaSeccionYALosTresMinutos() async {
        let s = ServidorAudio()
        s.rpc("entregas_app_audios", #"[{"id":"a1","estado":"subido"}]"#)
        let a = armar(s, sondeo: .milliseconds(20))
        await a.modelo.abrirSeccion()
        await hasta { s.pedidos(a: "entregas_app_audios").count >= 3 }
        a.modelo.cerrarSeccion()
        try? await Task.sleep(for: .milliseconds(60))
        let n = s.pedidos(a: "entregas_app_audios").count
        try? await Task.sleep(for: .milliseconds(150))
        #expect(s.pedidos(a: "entregas_app_audios").count == n)
        // Abierta de nuevo: corre hasta que el reloj pasa los 3 minutos.
        await a.modelo.abrirSeccion()
        a.reloj.avanzar(181)
        try? await Task.sleep(for: .milliseconds(100))
        let m = s.pedidos(a: "entregas_app_audios").count
        try? await Task.sleep(for: .milliseconds(150))
        #expect(s.pedidos(a: "entregas_app_audios").count == m)
    }

    @Test func sinLa019ElBotonNoAparece() async {
        let s = ServidorAudio()
        s.rpc("entregas_app_audios", #"{"code":"PGRST202","message":"Could not find the function"}"#, status: 404)
        let a = armar(s)
        await a.modelo.abrirSeccion()
        #expect(!a.modelo.disponible)
        // Con la 019 aplicada aparece y queda anotado (sin red se sigue viendo).
        s.rpc("entregas_app_audios", "[]")
        await a.modelo.consultar()
        #expect(a.modelo.disponible)
        let otra = ModeloAudioDuda(cliente: ClienteRPC(transporte: s), token: token, outbox: nil, disco: a.disco)
        #expect(otra.disponible)
    }

    @Test func alAbrirRetomaLoDeLaColaYBorraLosHuerfanos() async {
        let s = ServidorAudio()
        let a = armar(s)
        await grabar(a)
        a.modelo.mandar()
        await hastaA { await a.cola.pendientes == 1 }
        let carpeta = a.disco.url("audios")
        FileManager.default.createFile(atPath: carpeta.appendingPathComponent("huerfano.m4a").path, contents: Data([1]))
        // Otra apertura (la app se cerró): un modelo nuevo con la misma cola.
        let cliente = ClienteRPC(transporte: s)
        let otro = ModeloAudioDuda(cliente: cliente, token: token, outbox: a.cola, disco: a.disco)
        await otro.abrirSeccion()
        #expect(otro.filas.map(\.estado) == [.mandando])
        #expect(archivos(a).count == 1 && !archivos(a).contains("huerfano.m4a"))
    }

    @Test func demoGrabaPeroNoManda() async {
        let m = ModeloAudioDuda(muestra: ())
        let g = GrabadorDoble()
        m.grabador = g
        m.tocarGrabar()
        await hasta { m.maquina.grabando }
        try? await Task.sleep(for: .milliseconds(2100))
        m.terminar()
        #expect({ if case .revisando = m.fase { true } else { false } }())
        m.mandar()
        #expect(m.aviso == .vistaPrevia)
        #expect(m.vistaPrevia && m.disponible)
        m.borrar()
        #expect(m.fase == .reposo)
        #expect(g.archivo.map { FileManager.default.fileExists(atPath: $0.path) } == false)
    }

    @Test func permisoSinPreguntarSePideAlTocarGrabar() async {
        let s = ServidorAudio()
        let a = armar(s)
        a.grabador.permiso = .sinPreguntar
        #expect(a.modelo.faltaPermiso)
        a.grabador.respuestaPermiso = false
        a.modelo.tocarGrabar()
        await hasta { a.modelo.aviso == .permisoNegado }
        #expect(a.grabador.pedidos == 1 && a.modelo.fase == .reposo && !a.modelo.faltaPermiso)
    }

    @Test func unaInterrupcionDelSistemaPasaARevisar() async {
        let s = ServidorAudio()
        let a = armar(s)
        a.modelo.tocarGrabar()
        await hasta { a.modelo.maquina.grabando }
        a.reloj.avanzar(8)
        a.grabador.alInterrumpir?()
        #expect(a.modelo.fase == .revisando(segundos: 8))
        #expect(a.grabador.terminados == 1)
    }

    @Test func elTicCortaALosCincoMinutos() async {
        let s = ServidorAudio()
        let a = armar(s)
        a.modelo.tocarGrabar()
        await hasta { a.modelo.maquina.grabando }
        a.reloj.avanzar(271)
        a.modelo.tic()
        #expect(a.modelo.aviso == .quedan30)
        #expect(a.modelo.segundos == 271)
        a.reloj.avanzar(30)
        a.modelo.tic()
        #expect(a.modelo.fase == .revisando(segundos: 300))
    }
}
