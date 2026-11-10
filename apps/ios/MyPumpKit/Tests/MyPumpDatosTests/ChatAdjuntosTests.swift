import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// Fotos y audios en el chat (2.3.0): la burbuja al instante, la cola, lo que contesta mini-vision y ver lo que llegó.
/// Todo contra un transporte de mentira: nada sale a la red.
final class TransporteAdjuntos: Transporte, @unchecked Sendable {
    typealias Regla = @Sendable (_ pedido: URLRequest) async throws -> (Int, Data)
    private let lock = NSLock()
    private var _pedidos: [URLRequest] = []
    var pedidos: [URLRequest] { lock.withLock { _pedidos } }
    var regla: Regla
    init(_ regla: @escaping Regla) { self.regla = regla }
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _pedidos.append(pedido) }
        let (status, datos) = try await regla(pedido)
        return (datos, HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func subir(_ pedido: URLRequest, archivo: URL) async throws -> (Data, URLResponse) {
        var p = pedido
        p.httpBody = try Data(contentsOf: archivo)
        return try await enviar(p)
    }
    func de(_ ruta: String) -> [URLRequest] { pedidos.filter { $0.url?.path.hasSuffix(ruta) == true } }
}

private let tok = "AAAAAAAAAAAAAAAAAAAA"
private let info = #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#

private func json(_ s: String) -> Data { Data(s.utf8) }

/// Un JPEG de 2400×1800 con EXIF y GPS (lo que saca una cámara): la foto que se manda tiene que salir sin nada de eso.
func fotoConGPS(ancho: Int = 2400, alto: Int = 1800) -> Data {
    let ctx = CGContext(data: nil, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))
    let img = ctx.makeImage()!
    let salida = NSMutableData()
    let dest = CGImageDestinationCreateWithData(salida as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)!
    let props: [CFString: Any] = [
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: -34.6, kCGImagePropertyGPSLatitudeRef: "S",
                                        kCGImagePropertyGPSLongitude: 58.4, kCGImagePropertyGPSLongitudeRef: "W"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "dato de prueba"],
    ]
    CGImageDestinationAddImage(dest, img, props as CFDictionary)
    CGImageDestinationFinalize(dest)
    return salida as Data
}

@Suite("Fotos y audios del chat", .serialized)
@MainActor
struct ChatAdjuntosTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("chat-adj-\(UUID().uuidString)")

    struct Armado {
        let modelo: ModeloChat
        let cola: Outbox
        let transporte: TransporteAdjuntos
        let carpeta: URL
    }

    /// El modelo, la cola y las escrituras como los arma `ModeloApp.prepararCuenta`, con la palanca y el servidor que dicen que sí.
    func armar(adjunto: @escaping @Sendable (URLRequest) -> (Int, String) = { _ in (200, #"{"ok":true,"ya":false,"comentario_id":"c-1","created_at":"2026-11-10T15:00:00.123456+00:00"}"#) },
               activo: Bool = true) async -> Armado {
        let t = TransporteAdjuntos { p in
            let ruta = p.url!.path
            if ruta.hasSuffix("/chat/adjunto") { let (s, b) = adjunto(p); return (s, json(b)) }
            if ruta.hasSuffix("mypump_chat_adjuntos_estado") { return (200, json(#"{"habilitado":true,"audio_max_s":120}"#)) }
            if ruta.hasSuffix("mypump_get_cliente_info") { return (200, json(info)) }
            if ruta.hasSuffix("mypump_chat_nuevos") || ruta.hasSuffix("mypump_get_chat") { return (200, json("[]")) }
            return (404, json("{}"))
        }
        let cliente = ClienteRPC(transporte: t)
        let disco = Disco(raiz: raiz, token: tok)
        let escrituras = Escrituras(cliente: cliente, token: tok, carpetaAudios: disco.url("audios"))
        let cola = Outbox(archivo: disco.url("outbox.json"), reintentoAutomatico: false) { await escrituras.ejecutar($0) }
        let carpeta = disco.url(ModeloChat.carpetaAdjuntosNombre)
        let m = ModeloChat(cliente: cliente, token: tok, outbox: cola, carpetaAdjuntos: carpeta)
        await cola.observar(estado: { _ in }, abandonadas: { ops in Task { @MainActor in await m.alAbandonarAdjuntos(ops) } },
                            guardadas: { ops in Task { @MainActor in m.alGuardarAdjuntos(ops) } })
        if activo { await m.consultarAdjuntos(palanca: true) }
        return Armado(modelo: m, cola: cola, transporte: t, carpeta: carpeta)
    }

    func esperar() async { try? await Task.sleep(for: .milliseconds(150)) }

    @Test func laFotoSaleSinGPSYLaBurbujaPasaASerLaFila() async throws {
        let a = await armar()
        #expect(a.modelo.adjuntosActivos)
        #expect(await a.modelo.enviarFoto(fotoConGPS()))
        // La burbuja aparece ya, «Enviando…», con el texto que va a guardar el servidor.
        let b = try #require(a.modelo.hilo.mensajes.last)
        #expect(b.pendiente && !b.fallo && b.contenido == "Foto" && b.adjunto?.tipo == .foto)
        let id = try #require(b.adjunto?.id)

        await a.cola.drenarTodo()
        await esperar()
        let p = try #require(a.transporte.de("/chat/adjunto").first)
        #expect(p.httpMethod == "POST")
        #expect(p.value(forHTTPHeaderField: "x-chat-token") == tok)
        #expect(p.value(forHTTPHeaderField: "x-chat-id") == id)
        #expect(p.value(forHTTPHeaderField: "x-chat-tipo") == "foto")
        #expect(p.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(p.value(forHTTPHeaderField: "x-chat-duracion") == nil)
        // El cuerpo es la foto reducida (lado mayor 1600) y sin GPS ni EXIF de la original.
        let cuerpo = try #require(p.httpBody)
        let fuente = try #require(CGImageSourceCreateWithData(cuerpo as CFData, nil))
        let props = (CGImageSourceCopyPropertiesAtIndex(fuente, 0, nil) as? [CFString: Any]) ?? [:]
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect(((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment]) == nil)
        #expect(max(props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0) == 1600)

        // Guardada: la burbuja ya es la fila del servidor (con su hora), y el archivo queda para verla sin bajarla.
        #expect(await a.cola.pendientes == 0)
        let real = try #require(a.modelo.hilo.mensajes.first { $0.adjunto?.id == id })
        #expect(!real.pendiente && real.id == "c-1" && real.createdAt.hasPrefix("2026-11-10T15:00"))
        #expect(a.modelo.archivos[id].map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(await a.modelo.archivo(de: try #require(real.adjunto)) == a.modelo.archivos[id])
        #expect(a.transporte.de("/chat/urls").isEmpty)   // no hizo falta firmar nada

        // El sondeo trae la misma fila: no se duplica.
        a.modelo.hilo.mezclar([try fila(id: "c-1", contenido: "Foto", adjunto: #"{"id":"\#(id)","tipo":"foto"}"#)])
        #expect(a.modelo.hilo.mensajes.filter { $0.adjunto?.id == id }.count == 1)
    }

    @Test func elAudioLlevaLaDuracionYElTextoDelServidor() async throws {
        let a = await armar()
        let tmp = raiz.appendingPathComponent("grabando.m4a")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4000).write(to: tmp)
        #expect(await a.modelo.enviarAudio(archivo: tmp, segundos: 42.4))
        #expect(!FileManager.default.fileExists(atPath: tmp.path))   // se movió a la carpeta de la cuenta
        let b = try #require(a.modelo.hilo.mensajes.last)
        #expect(b.contenido == "Audio de 0:42" && b.adjunto?.duracion == 42)
        await a.cola.drenarTodo()
        let p = try #require(a.transporte.de("/chat/adjunto").first)
        #expect(p.value(forHTTPHeaderField: "x-chat-tipo") == "audio")
        #expect(p.value(forHTTPHeaderField: "x-chat-duracion") == "42")
        #expect(p.value(forHTTPHeaderField: "Content-Type") == "audio/mp4")
    }

    @Test func unToqueSinQuererNoSale() async throws {
        let a = await armar()
        let tmp = raiz.appendingPathComponent("corto.m4a")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 100).write(to: tmp)
        #expect(!(await a.modelo.enviarAudio(archivo: tmp, segundos: 0.4)))
        #expect(a.modelo.hilo.mensajes.isEmpty)
        #expect(a.modelo.anuncio == ReglasChatAdjuntos.textoMuyCorto)
        #expect(!FileManager.default.fileExists(atPath: tmp.path))
    }

    @Test func conLaPalancaApagadaNoSeMuestraNiSeLlama() async throws {
        let a = await armar(activo: false)
        await a.modelo.consultarAdjuntos(palanca: false)
        #expect(!a.modelo.adjuntosActivos)
        #expect(a.transporte.de("mypump_chat_adjuntos_estado").isEmpty)
        #expect(!(await a.modelo.enviarFoto(fotoConGPS())))
        #expect(a.modelo.hilo.mensajes.isEmpty)
    }

    @Test func sinRedQuedaLoUltimoQueSeSupo() async throws {
        let a = await armar()
        #expect(a.modelo.adjuntosActivos)
        // Otro modelo de la misma cuenta, sin red: recuerda que estaba prendido.
        let sinRed = TransporteAdjuntos { _ in throw URLError(.notConnectedToInternet) }
        let m2 = ModeloChat(cliente: ClienteRPC(transporte: sinRed), token: tok, outbox: a.cola, carpetaAdjuntos: a.carpeta)
        await m2.consultarAdjuntos(palanca: true)
        #expect(m2.adjuntosActivos)
    }

    @Test func sinSenalEsperaSinGastarIntentosYNoSePierde() async throws {
        let a = await armar(adjunto: { _ in (503, #"{"ok":false,"error":"no se pudo subir, probá en un rato"}"#) })
        #expect(await a.modelo.enviarFoto(fotoConGPS()))
        await a.cola.drenarAudios()
        await a.cola.drenarAudios()
        #expect(await a.cola.pendientes == 1)
        #expect(await a.cola.operaciones.first?.tries == 0)
        #expect(await a.cola.fallidos.isEmpty)
        let b = try #require(a.modelo.hilo.mensajes.last)
        #expect(b.pendiente && !b.fallo)

        // La app se cierra: al volver, la burbuja «Enviando…» vuelve desde la cola.
        let m2 = ModeloChat(cliente: ClienteRPC(transporte: a.transporte), token: tok, outbox: a.cola, carpetaAdjuntos: a.carpeta)
        await m2.cargarAdjuntosDeLaCola()
        let r = try #require(m2.hilo.mensajes.first)
        #expect(r.pendiente && !r.fallo && r.adjunto?.id == b.adjunto?.id && r.contenido == "Foto")
        #expect(m2.archivos[r.adjunto!.id] != nil)
    }

    @Test func elTopeDelDiaVaDirectoANoSalioYSePuedeReintentar() async throws {
        let a = await armar(adjunto: { _ in (429, #"{"ok":false,"error":"muchos adjuntos por hoy, probá mañana"}"#) })
        #expect(await a.modelo.enviarFoto(fotoConGPS()))
        await a.cola.drenarAudios()
        await esperar()
        #expect(a.transporte.de("/chat/adjunto").count == 1)   // no se reintenta solo: sería el archivo entero otra vez
        #expect(await a.cola.pendientes == 0)
        let f = try #require(await a.cola.fallidos.first)
        #expect(f.motivo == ReglasChatAdjuntos.codigoTope)
        let b = try #require(a.modelo.hilo.mensajes.last)
        #expect(b.fallo && b.motivoFallo == ReglasChatAdjuntos.codigoTope)
        #expect(a.modelo.anuncio == ReglasChatAdjuntos.textoTope)

        // «Reintentar»: vuelve a la cola con el mismo id y el mismo archivo.
        let id = try #require(b.adjunto?.id)
        await a.modelo.reintentarAdjunto(id)
        #expect(await a.cola.fallidos.isEmpty)
        #expect(await a.cola.operaciones.first?.payload["id"]?.comoTexto == id)
        #expect(a.modelo.hilo.mensajes.last.map { $0.pendiente && !$0.fallo } == true)
    }

    @Test func unRechazoNoGastaLosOchoIntentos() async throws {
        let a = await armar(adjunto: { _ in (413, #"{"ok":false,"error":"archivo muy grande"}"#) })
        #expect(await a.modelo.enviarFoto(fotoConGPS()))
        await a.cola.drenarAudios()
        await esperar()
        #expect(a.transporte.de("/chat/adjunto").count == 1)
        #expect(await a.cola.fallidos.first?.motivo == ReglasChatAdjuntos.codigoRechazo)
        #expect(a.modelo.hilo.mensajes.last?.fallo == true)
    }

    @Test func unIdDeOtroMensajeSaleSoloConOtro() async throws {
        let a = await armar(adjunto: { _ in (409, #"{"ok":false,"error":"id repetido"}"#) })
        #expect(await a.modelo.enviarFoto(fotoConGPS()))
        let viejo = try #require(a.modelo.hilo.mensajes.last?.adjunto?.id)
        await a.cola.drenarAudios()
        await esperar()
        // Sin tocar nada: vuelve a la cola con un id nuevo y la burbuja sigue «enviando…», nunca «no salió».
        #expect(a.modelo.hilo.mensajes.last?.fallo == false)
        let op = try #require(await a.cola.operaciones.first)
        let nuevo = try #require(op.payload["id"]?.comoTexto)
        #expect(nuevo != viejo)
        #expect(op.payload["archivo"]?.comoTexto == "\(nuevo).jpg")
        #expect(FileManager.default.fileExists(atPath: a.carpeta.appendingPathComponent("\(nuevo).jpg").path))
        #expect(a.modelo.hilo.mensajes.count == 1 && a.modelo.hilo.mensajes.last?.adjunto?.id == nuevo)
    }

    @Test func sinElArchivoNoSeOfreceReintentarYSePuedeBorrar() async throws {
        let a = await armar()
        #expect(await a.modelo.enviarFoto(fotoConGPS()))
        let id = try #require(a.modelo.hilo.mensajes.last?.adjunto?.id)
        try FileManager.default.removeItem(at: a.carpeta.appendingPathComponent("\(id).jpg"))
        await a.cola.drenarAudios()
        await esperar()
        #expect(a.transporte.de("/chat/adjunto").isEmpty)
        let b = try #require(a.modelo.hilo.mensajes.last)
        #expect(b.fallo && !ReglasChatAdjuntos.sePuedeReintentar(motivo: b.motivoFallo))
        await a.modelo.descartarAdjunto(id)
        #expect(a.modelo.hilo.mensajes.isEmpty)
        #expect(await a.cola.fallidos.isEmpty)
    }

    @Test func unTokenCaidoEstacionaSinGastarIntento() async throws {
        let t = TransporteAdjuntos { p in
            if p.url!.path.hasSuffix("/chat/adjunto") { return (403, json(#"{"ok":false,"error":"token inválido"}"#)) }
            if p.url!.path.hasSuffix("mypump_get_cliente_info") { return (200, json("[]")) }   // el token cayó
            if p.url!.path.hasSuffix("mypump_chat_adjuntos_estado") { return (200, json(#"{"habilitado":true}"#)) }
            return (200, json("[]"))
        }
        let cliente = ClienteRPC(transporte: t)
        let disco = Disco(raiz: raiz, token: tok)
        let escrituras = Escrituras(cliente: cliente, token: tok, carpetaAudios: disco.url("audios"))
        let cola = Outbox(archivo: disco.url("outbox.json"), reintentoAutomatico: false) { await escrituras.ejecutar($0) }
        let m = ModeloChat(cliente: cliente, token: tok, outbox: cola, carpetaAdjuntos: disco.url(ModeloChat.carpetaAdjuntosNombre))
        await m.consultarAdjuntos(palanca: true)
        #expect(await m.enviarFoto(fotoConGPS()))
        await cola.drenarAudios()
        #expect(await cola.pendientes == 1)
        #expect(await cola.operaciones.first?.tries == 0)
        #expect(await cola.fallidos.isEmpty)
    }

    @Test func loQueLlegoSeBajaConUnaFirmaParaVariosALaVez() async throws {
        let ids = (0..<3).map { _ in UUID().uuidString.lowercased() }
        let t = TransporteAdjuntos { p in
            let ruta = p.url!.path
            if ruta.hasSuffix("/chat/urls") {
                let cuerpo = try JSONDecoder().decode(JSONValue.self, from: p.httpBody ?? Data())
                guard case .lista(let pedidos)? = cuerpo["ids"] else { return (400, json("{}")) }
                let filas = pedidos.compactMap(\.comoTexto).map { #"{"id":"\#($0)","tipo":"foto","mime":"image/jpeg","url":"https://ejemplo.invalid/firmada/\#($0)"}"# }
                return (200, json(#"{"ok":true,"adjuntos":[\#(filas.joined(separator: ","))],"expira_en":3600}"#))
            }
            if ruta.hasPrefix("/firmada/") { return (200, Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])) }
            return (200, json("[]"))
        }
        let disco = Disco(raiz: raiz, token: tok)
        let m = ModeloChat(cliente: ClienteRPC(transporte: t), token: tok, outbox: nil, carpetaAdjuntos: disco.url(ModeloChat.carpetaAdjuntosNombre))
        m.hilo.mezclar(try ids.enumerated().map { i, id in
            try fila(id: "m\(i)", contenido: "Foto", adjunto: #"{"id":"\#(id)","tipo":"foto"}"#, hora: "2026-11-10T1\(i):00:00+00:00")
        })
        let u = try #require(await m.archivo(de: AdjuntoChat(id: ids[0], tipo: .foto)))
        #expect(u.lastPathComponent == "\(ids[0]).jpg")
        #expect(try Data(contentsOf: u).prefix(2) == Data([0xFF, 0xD8]))
        // Una sola firma trajo las tres: las otras se bajan sin volver a firmar.
        #expect(await m.archivo(de: AdjuntoChat(id: ids[2], tipo: .foto)) != nil)
        #expect(t.de("/chat/urls").count == 1)
        // Ya en el teléfono: ni firma ni descarga.
        let antes = t.pedidos.count
        #expect(await m.archivo(de: AdjuntoChat(id: ids[0], tipo: .foto)) == u)
        #expect(t.pedidos.count == antes)
        // Uno que la retención borró no se pide.
        #expect(await m.archivo(de: AdjuntoChat(id: UUID().uuidString, tipo: .foto, borrado: true)) == nil)
        #expect(t.pedidos.count == antes)
    }

    @Test func sinRedLaBurbujaOfreceProbarDeNuevo() async throws {
        let t = TransporteAdjuntos { _ in throw URLError(.notConnectedToInternet) }
        let disco = Disco(raiz: raiz, token: tok)
        let m = ModeloChat(cliente: ClienteRPC(transporte: t), token: tok, outbox: nil, carpetaAdjuntos: disco.url(ModeloChat.carpetaAdjuntosNombre))
        let a = AdjuntoChat(id: UUID().uuidString, tipo: .audio, duracion: 5)
        #expect(await m.archivo(de: a) == nil)
        #expect(m.sinBajar.contains(a.id))
    }
}

func fila(id: String, autor: String = "cliente", contenido: String, adjunto: String? = nil, hora: String = "2026-11-10T15:00:00+00:00") throws -> MensajeChat {
    let adj = adjunto.map { #","adjunto":\#($0)"# } ?? ""
    return try JSONDecoder().decode(MensajeChat.self, from: Data(#"{"id":"\#(id)","autor":"\#(autor)","contenido":"\#(contenido)","created_at":"\#(hora)"\#(adj)}"#.utf8))
}

@Suite("El hilo con fotos y audios")
struct HiloAdjuntosTests {
    func pendiente(_ id: String, _ tipo: AdjuntoChat.Tipo = .foto, hora: String = "2026-11-10T15:00:00.000+00:00") -> BurbujaChat {
        ModeloChat.burbujaPendiente(id: id, tipo: tipo, segundos: tipo == .audio ? 5 : nil, creado: hora)
    }

    @Test func dosFotosSeguidasSonDosMensajes() throws {
        var h = HiloChat()
        h.agregarPendiente(pendiente("a"))
        h.agregarPendiente(pendiente("b"))
        // Llega la fila de la primera: solo sale su optimista (por el id del adjunto, no por el texto «Foto»).
        h.mezclar([try fila(id: "c1", contenido: "Foto", adjunto: #"{"id":"a","tipo":"foto"}"#)])
        #expect(h.mensajes.map(\.id).sorted() == ["adj_b", "c1"])
    }

    @Test func unTextoFotoNoSeComeLaFotoNiAlReves() throws {
        var h = HiloChat()
        h.agregarPendiente(pendiente("a"))
        h.agregarPendiente(BurbujaChat(id: "tmp_1", autor: "cliente", contenido: "Foto", leidoPorCliente: nil,
                                       createdAt: "2026-11-10T15:00:01.000+00:00", pendiente: true))
        h.mezclar([try fila(id: "t1", contenido: "Foto")])          // el texto «Foto» que escribió
        #expect(h.mensajes.contains { $0.id == "adj_a" })
        #expect(!h.mensajes.contains { $0.id == "tmp_1" })
        h.agregarPendiente(BurbujaChat(id: "tmp_2", autor: "cliente", contenido: "Foto", leidoPorCliente: nil,
                                       createdAt: "2026-11-10T15:00:02.000+00:00", pendiente: true))
        h.mezclar([try fila(id: "c1", contenido: "Foto", adjunto: #"{"id":"a","tipo":"foto"}"#)])
        #expect(h.mensajes.contains { $0.id == "tmp_2" })
        // Y confirmar o marcar fallido un texto no toca la foto.
        h.marcarFallido(contenido: "Foto")
        #expect(h.mensajes.first { $0.adjunto != nil }?.fallo == false)
    }

    @Test func confirmarConLaFilaQueYaLlegoSoloSacaLaOptimista() throws {
        var h = HiloChat()
        h.agregarPendiente(pendiente("a", .audio))
        h.mezclar([try fila(id: "c1", contenido: "Audio de 0:05", adjunto: #"{"id":"a","tipo":"audio","duracion_s":5}"#)])
        h.confirmarAdjunto(id: "a", comentarioId: "c1", createdAt: nil)
        #expect(h.mensajes.map(\.id) == ["c1"])
        #expect(h.mensajes.first?.adjunto?.duracion == 5)
    }

    @Test func laConfirmadaNoMueveElCursorHastaQueLlegaLaFila() throws {
        var h = HiloChat()
        h.mezclar([try fila(id: "m1", autor: "coach", contenido: "hola", hora: "2026-11-10T14:00:00+00:00")])
        h.agregarPendiente(pendiente("a"))
        h.confirmarAdjunto(id: "a", comentarioId: "c1", createdAt: "2026-11-10T15:00:00+00:00")
        h.mezclar([])
        #expect(h.cursor == "2026-11-10T14:00:00+00:00")
        h.mezclar([try fila(id: "c1", contenido: "Foto", adjunto: #"{"id":"a","tipo":"foto"}"#, hora: "2026-11-10T15:00:00+00:00")])
        #expect(h.cursor == "2026-11-10T15:00:00+00:00")
        #expect(h.mensajes.allSatisfy { !$0.confirmado })
    }

    @Test func laRetencionBorroElArchivoYLaBurbujaLoDice() throws {
        var h = HiloChat()
        h.mezclar([try fila(id: "c1", contenido: "Foto", adjunto: #"{"id":"a","tipo":"foto"}"#)])
        #expect(h.adjuntosReales.count == 1)
        h.mezclar([try fila(id: "c1", contenido: "Foto", adjunto: #"{"id":"a","tipo":"foto","borrado":true}"#)])
        #expect(h.mensajes.first?.adjunto?.borrado == true)
        #expect(h.adjuntosReales.isEmpty)
    }

    @Test func elMensajeSinAdjuntoOConUnTipoNuevoSigueSiendoTexto() throws {
        #expect(try fila(id: "x", contenido: "hola").adjunto == nil)
        #expect(try fila(id: "x", contenido: "Video", adjunto: #"{"id":"a","tipo":"video"}"#).adjunto == nil)
        #expect(try fila(id: "x", contenido: "Foto", adjunto: "null").adjunto == nil)
        let a = try #require(try fila(id: "x", contenido: "Audio", adjunto: #"{"id":"A-B","tipo":"audio","duracion_s":"12.5"}"#).adjunto)
        #expect(a.id == "a-b" && a.duracion == 12.5 && !a.borrado)
    }
}

@Suite("Reglas de fotos y audios del chat")
struct ReglasChatAdjuntosTests {
    @Test func loQueContestaMiniVision() {
        typealias R = ReglasChatAdjuntos
        #expect(R.subida(status: 200, ok: true, error: nil) == .ok)
        #expect(R.subida(status: 200, ok: false, error: nil) == .reintentar)
        #expect(R.subida(status: 0, ok: false, error: nil) == .reintentar)
        #expect(R.subida(status: 503, ok: false, error: "no se pudo subir") == .reintentar)
        #expect(R.subida(status: 502, ok: false, error: nil) == .reintentar)
        #expect(R.subida(status: 408, ok: false, error: nil) == .reintentar)
        #expect(R.subida(status: 429, ok: false, error: nil) == .tope)
        #expect(R.subida(status: 409, ok: false, error: "id repetido") == .idRepetido)
        #expect(R.subida(status: 403, ok: false, error: "token inválido") == .token)
        #expect(R.subida(status: 403, ok: false, error: "no habilitado") == .rechazo)
        #expect(R.subida(status: 413, ok: false, error: "archivo muy grande") == .rechazo)
        #expect(R.subida(status: 400, ok: false, error: "la imagen debe ser JPEG") == .rechazo)
    }

    @Test func duraciones() {
        #expect(ReglasChatAdjuntos.duracion(7) == "0:07")
        #expect(ReglasChatAdjuntos.duracion(42.4) == "0:42")
        #expect(ReglasChatAdjuntos.duracion(120) == "2:00")
        #expect(ReglasChatAdjuntos.duracion(-3) == "0:00")
        #expect(ReglasChatAdjuntos.duracion(.nan) == "0:00")
        #expect(ReglasChatAdjuntos.textoAudio(segundos: 65) == "Audio de 1:05")
        #expect(ReglasChatAdjuntos.duracionHablada(1) == "1 segundo")
        #expect(ReglasChatAdjuntos.duracionHablada(65) == "1 minuto 5 segundos")
        #expect(ReglasChatAdjuntos.duracionHablada(120) == "2 minutos")
    }

    /// Ningún texto de la pantalla nombra a la IA, la transcripción ni a «tu entrenador»; sin «:» ni guiones ni emojis.
    @Test func losTextosNoNombranNadaInterno() {
        let R = ReglasChatAdjuntos.self
        let textos = [R.textoAdjuntar, R.textoSacarFoto, R.textoElegirFoto, R.textoMantenerParaGrabar, R.textoGrabarAccesible,
                      R.ayudaGrabarAccesible, R.textoMandarAudioAccesible, R.textoDeslizarParaCancelar, R.textoCancelar, R.textoQuedanDiez,
                      R.textoMuyCorto, R.textoEnviando, R.textoNoSalio, R.textoReintentar, R.textoTope, R.textoSinArchivo,
                      R.textoNoDisponible, R.textoCargando, R.textoNoCarga, R.textoReproducir, R.textoPausar, R.textoCerrar,
                      R.textoSinMicrofono, R.textoSinCamara, R.textoAbrirAjustes, R.textoFotoIlegible, R.textoNoSeEscucha, R.textoBorrar]
        for t in textos {
            let l = t.lowercased()
            for prohibido in ["ia", "inteligencia", "transcrib", "texto", "entrenador", "coach", "automátic", "robot"] {
                #expect(!l.split(whereSeparator: { !$0.isLetter }).contains { $0.hasPrefix(prohibido) }, "«\(t)» dice \(prohibido)")
            }
            #expect(!t.contains(":") && !t.contains(" - ") && !t.contains("—"), "«\(t)»")
        }
    }
}
