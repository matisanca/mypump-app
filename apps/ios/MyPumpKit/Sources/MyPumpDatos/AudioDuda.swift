import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

// Las dudas en audio de «Tu guía» (2.1.0). Contrato por token de `entregas_019`:
// - `entregas_app_audio_iniciar(p_token, p_mime, p_bytes, p_segundos, p_id)` → `{ok, id, bucket, ruta, mime, motivo}`,
//   idempotente por `p_id`.
// - La subida: `POST {SUPABASE_URL}/storage/v1/object/{bucket}/{ruta}` con la anon key, el `mime` exacto y
//   `x-upsert: false`. Un 409 (ya existe) cuenta como subido.
// - `entregas_app_audio_subido(p_token, p_id)`.
// - `entregas_app_audios(p_token)` → `[{id, estado: subido|transcripto|error, en, texto}]`.
// El audio va por la cola (`guia_audio`, una op por audio, nunca se deduplican entre sí) con el archivo en Application
// Support, nunca en preferencias.

/// Qué dejó el sistema con el micrófono.
public enum PermisoMicrofono: Sendable, Equatable { case sinPreguntar, dado, negado }

/// El micrófono, sin AVFoundation: en la app es AVAudioRecorder (AAC en m4a, mono, 64 kbps, 44,1 kHz); en los tests y en
/// las pruebas de interfaz, un doble.
@MainActor
public protocol GrabadorAudio: AnyObject {
    var permiso: PermisoMicrofono { get }
    func pedirPermiso() async -> Bool
    /// Arranca a grabar en ese archivo. nil = grabando; si no, por qué no pudo.
    func empezar(en archivo: URL) -> AvisoAudio?
    /// Frena y cierra el archivo. La sesión de audio vuelve a la de la app.
    func terminar()
    /// El sistema cortó el micrófono (una llamada, Siri): el modelo pasa a revisar con lo grabado.
    var alInterrumpir: (@MainActor () -> Void)? { get set }
}

/// Un audio del servidor (`entregas_app_audios`).
public struct AudioServidor: Codable, Equatable, Sendable, Identifiable {
    public enum Estado: String, Codable, Sendable { case subido, transcripto, error }
    public var id: String
    public var estado: Estado
    public var en: String?
    public var segundos: Double?
    public var texto: String?

    public init(id: String, estado: Estado, en: String? = nil, segundos: Double? = nil, texto: String? = nil) {
        self.id = id; self.estado = estado; self.en = en; self.segundos = segundos; self.texto = texto
    }

    /// Tolerante: sin id o con un estado que no conoce, no entra.
    init?(json: JSONValue) {
        guard let id = json["id"]?.comoTexto, !id.isEmpty, let e = json["estado"]?.comoTexto.flatMap(Estado.init(rawValue:)) else { return nil }
        self.init(id: id, estado: e, en: json["en"]?.comoTexto, segundos: json["segundos"]?.comoNumero, texto: json["texto"]?.comoTexto)
    }
}

/// Lo que se ve de cada audio mandado, del más viejo al más nuevo.
public struct FilaAudio: Equatable, Sendable, Identifiable {
    public enum Estado: Equatable, Sendable {
        case mandando
        /// La cola lo abandonó: «No se pudo mandar.» con «Reintentar».
        case noSeMando
        /// La base dijo que no (tope, largo, formato): no se reintenta.
        case rechazado(AvisoAudio)
        case subido
        case transcripto(String)
        case error
    }
    public let id: String
    public var estado: Estado

    public init(id: String, estado: Estado) { self.id = id; self.estado = estado }
}

@MainActor @Observable
public final class ModeloAudioDuda {
    public nonisolated static let kind = "guia_audio"
    nonisolated static func clave(_ id: String) -> String { "\(kind)_\(id)" }
    static let archivoDisponible = "guia_audio_disponible.json"

    public private(set) var maquina = MaquinaAudio()
    /// Para el contador (se actualiza con cada tic mientras graba).
    public private(set) var segundos: Double = 0
    /// Lo que la cola tiene o abandonó, y lo que el servidor confirmó en esta sesión.
    public private(set) var locales: [FilaAudio] = []
    public private(set) var servidor: [AudioServidor] = []
    /// `entregas_app_audios` respondió alguna vez: la 019 está aplicada. Sin eso el botón no aparece (la app puede salir
    /// antes que la migración). En la demo, siempre.
    public private(set) var disponible: Bool
    /// El último anuncio para VoiceOver (la región viva): cambia `anuncios` aunque el texto se repita.
    public private(set) var anuncio: String = ""
    public private(set) var anuncios = 0
    /// El archivo de lo que se está grabando o revisando.
    public private(set) var archivoActual: URL?

    /// La pantalla lo pone: el AVAudioRecorder (o el doble).
    @ObservationIgnored public var grabador: (any GrabadorAudio)? {
        didSet { grabador?.alInterrumpir = { [weak self] in self?.cortar() } }
    }
    /// Al empezar a grabar: pausar los videos de la guía.
    @ObservationIgnored public var alEmpezar: (@MainActor () -> Void)?

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let outbox: Outbox?
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored let carpeta: URL
    @ObservationIgnored let reloj: @Sendable () -> Double
    @ObservationIgnored let esperaSondeo: Duration
    @ObservationIgnored private var tics: Task<Void, Never>?
    @ObservationIgnored private var sondeo: Task<Void, Never>?
    @ObservationIgnored private var seccionAbierta = false
    @ObservationIgnored private let esMuestra: Bool
    @ObservationIgnored private var consultaEnCurso = false

    /// `carpeta`: donde quedan los audios hasta que se confirman (la de la cuenta, `audios/`).
    public init(cliente: ClienteRPC, token: String, outbox: Outbox?, disco: Disco?, carpeta: URL? = nil,
                reloj: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }, esperaSondeo: Duration = .seconds(ReglasAudioDuda.sondeoCada)) {
        self.cliente = cliente; self.token = token; self.outbox = outbox; self.disco = disco
        self.carpeta = carpeta ?? disco?.url("audios") ?? FileManager.default.temporaryDirectory.appendingPathComponent("audios-guia", isDirectory: true)
        self.reloj = reloj; self.esperaSondeo = esperaSondeo
        esMuestra = false
        disponible = disco?.leer(Bool.self, Self.archivoDisponible) ?? false
    }

    /// La demo y la maqueta: se puede grabar y escuchar; «Mandar» dice «Vista previa». Nada sale.
    public init(muestra: Void = ()) {
        cliente = ClienteRPC(); token = ""; outbox = nil; disco = nil
        carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("audios-guia-demo", isDirectory: true)
        reloj = { Date().timeIntervalSince1970 }; esperaSondeo = .seconds(ReglasAudioDuda.sondeoCada)
        esMuestra = true
        disponible = true
    }

    // MARK: - Lo que se ve

    public var fase: MaquinaAudio.Fase { maquina.fase }
    public var aviso: AvisoAudio? { maquina.aviso }
    public var vistaPrevia: Bool { outbox == nil }
    /// «Te va a pedir permiso…»: solo si todavía no lo dio ni lo negó.
    public var faltaPermiso: Bool { grabador?.permiso == .sinPreguntar }

    /// Lo local primero que lo del servidor con el mismo id; en orden de llegada.
    public var filas: [FilaAudio] {
        var out: [FilaAudio] = servidor.map { a in
            switch a.estado {
            case .subido: FilaAudio(id: a.id, estado: .subido)
            case .error: FilaAudio(id: a.id, estado: .error)
            case .transcripto:
                // Sin texto es raro: se sigue viendo como «lo estoy pasando a texto».
                if let t = a.texto, !ReglasAudioDuda.limpio(t).isEmpty { FilaAudio(id: a.id, estado: .transcripto(t)) }
                else { FilaAudio(id: a.id, estado: .subido) }
            }
        }
        for l in locales where !out.contains(where: { $0.id == l.id }) { out.append(l) }
        return out
    }

    /// Los textos transcriptos: las dudas de la llamada iguales no se pintan dos veces.
    public var transcriptos: Set<String> {
        Set(servidor.compactMap { $0.estado == .transcripto ? $0.texto.map(ReglasAudioDuda.limpio) : nil }.filter { !$0.isEmpty })
    }

    public var haySubidos: Bool { servidor.contains { $0.estado == .subido } || locales.contains { $0.estado == .subido } }

    // MARK: - El grabador

    public func tocarGrabar() { manejar(.tocarGrabar) }
    public func terminar() { manejar(.terminar(ahora: reloj())) }
    public func grabarDeNuevo() { manejar(.grabarDeNuevo) }
    public func borrar() { manejar(.borrar) }
    public func mandar() { manejar(.mandar(vistaPrevia: vistaPrevia)) }
    /// Segundo plano, pantalla bloqueada o una interrupción del sistema: si graba, se frena y se pasa a revisar.
    public func cortar() { manejar(.cortar(ahora: reloj())) }
    /// Lo llama el temporizador (cada medio segundo) y los tests.
    public func tic() {
        manejar(.tic(ahora: reloj()))
        if maquina.grabando { segundos = maquina.segundos(ahora: reloj()) }
    }

    private func manejar(_ e: MaquinaAudio.Evento) {
        let efectos = maquina.manejar(e)
        for ef in efectos { hacer(ef) }
        if case .revisando(let s) = maquina.fase { segundos = s }
        if case .reposo = maquina.fase { segundos = 0 }
    }

    private func hacer(_ ef: MaquinaAudio.Efecto) {
        switch ef {
        case .pedirPermiso:
            guard let g = grabador else { manejar(.noEmpezo(.sinMicrofono)); return }
            switch g.permiso {
            case .dado: manejar(.permiso(true))
            case .negado: manejar(.permiso(false))
            case .sinPreguntar: Task { let ok = await g.pedirPermiso(); self.manejar(.permiso(ok)) }
            }
        case .empezarAGrabar:
            guard let g = grabador else { manejar(.noEmpezo(.sinMicrofono)); return }
            alEmpezar?()
            try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            let url = carpeta.appendingPathComponent("\(UUID().uuidString.lowercased()).m4a")
            archivoActual = url
            if let a = g.empezar(en: url) { manejar(.noEmpezo(a)); return }
            segundos = 0
            manejar(.empezo(ahora: reloj()))
            empezarTics()
        case .pararGrabador:
            tics?.cancel(); tics = nil
            grabador?.terminar()
        case .descartarArchivo:
            if let u = archivoActual { try? FileManager.default.removeItem(at: u) }
            archivoActual = nil
        case .encolar(let s):
            guard let u = archivoActual else { return }
            archivoActual = nil
            Task { await encolar(archivo: u, segundos: s) }
        case .anunciar(let t):
            anuncio = t
            anuncios += 1
        }
    }

    private func empezarTics() {
        tics?.cancel()
        tics = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, self.maquina.grabando else { return }
                self.tic()
            }
        }
    }

    // MARK: - La cola

    private func encolar(archivo: URL, segundos s: Double) async {
        guard let outbox else { return }
        let id = UUID().uuidString.lowercased()
        let bytes = (try? FileManager.default.attributesOfItem(atPath: archivo.path)[.size] as? Int) ?? 0
        // El archivo toma el nombre del `p_id`: el mismo audio es el mismo archivo en cada reintento.
        let destino = carpeta.appendingPathComponent("\(id).m4a")
        let nombre = (try? FileManager.default.moveItem(at: archivo, to: destino)) != nil ? destino.lastPathComponent : archivo.lastPathComponent
        locales.append(FilaAudio(id: id, estado: .mandando))
        await outbox.encolar(Self.kind, .objeto([
            "id": .texto(id), "archivo": .texto(nombre), "mime": .texto(ReglasAudioDuda.mime),
            "bytes": .numero(Double(bytes)), "segundos": .numero(s.rounded()),
        ]), dedupeKey: Self.clave(id))
    }

    /// «Reintentar» de un audio que la cola abandonó: el mismo `p_id` y el mismo archivo.
    public func reintentar(_ id: String) async {
        guard let outbox, let f = await outbox.fallidos.last(where: { $0.op.dedupeKey == Self.clave(id) }) else { return }
        await outbox.olvidarFallidos(clave: Self.clave(id))
        // `id` (ese p_id es de otro cliente): el mismo archivo con un p_id nuevo. Si no, el mismo (idempotente).
        guard f.motivo.contains(Escrituras.codigoAudioId), case .objeto(var o) = f.op.payload else {
            poner(id, .mandando)
            await outbox.encolar(Self.kind, f.op.payload, dedupeKey: Self.clave(id))
            return
        }
        let nuevo = UUID().uuidString.lowercased()
        o["id"] = .texto(nuevo)
        if let i = locales.firstIndex(where: { $0.id == id }) { locales[i] = FilaAudio(id: nuevo, estado: .mandando) } else { poner(nuevo, .mandando) }
        await outbox.encolar(Self.kind, .objeto(o), dedupeKey: Self.clave(nuevo))
    }

    /// Lo que quedó en la cola de antes (otra apertura, la app cerrada): «Mandando» o «No se pudo mandar». Los archivos que
    /// nadie nombra (la app se cerró entre la confirmación y el borrado) se borran.
    public func cargarDeLaCola() async {
        guard let outbox else { return }
        let ops = await outbox.operaciones.filter { $0.kind == Self.kind }
        let fallidos = await outbox.fallidos.map(\.op).filter { $0.kind == Self.kind }
        for op in ops { if let id = op.payload["id"]?.comoTexto { poner(id, .mandando) } }
        for op in fallidos {
            guard let id = op.payload["id"]?.comoTexto, !ops.contains(where: { $0.payload["id"]?.comoTexto == id }) else { continue }
            poner(id, .noSeMando)
        }
        let nombrados = Set((ops + fallidos).compactMap { $0.payload["archivo"]?.comoTexto })
        let actual = archivoActual?.lastPathComponent
        let archivos = (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []
        for a in archivos where !nombrados.contains(a) && a != actual {
            try? FileManager.default.removeItem(at: carpeta.appendingPathComponent(a))
        }
    }

    private func poner(_ id: String, _ e: FilaAudio.Estado) {
        if let i = locales.firstIndex(where: { $0.id == id }) { locales[i].estado = e } else { locales.append(FilaAudio(id: id, estado: e)) }
    }

    /// Lo que la cola guardó: `{ok: true}` = subido (se borra el archivo y se consulta la transcripción); `{ok: false,
    /// motivo}` = la base no lo aceptó.
    public func alGuardar(_ ops: [OpGuardada]) {
        var subio = false
        for g in ops where g.op.kind == Self.kind {
            guard let id = g.op.payload["id"]?.comoTexto else { continue }
            if let a = g.op.payload["archivo"]?.comoTexto { try? FileManager.default.removeItem(at: carpeta.appendingPathComponent(a)) }
            if g.respuesta["ok"] == .bool(true) {
                poner(id, .subido)
                subio = true
            } else {
                let a = ReglasAudioDuda.aviso(motivo: g.respuesta["motivo"]?.comoTexto)
                poner(id, .rechazado(a))
                anuncio = ReglasAudioDuda.texto(a); anuncios += 1
            }
        }
        // La lista se consulta solo con la sección abierta (la cola puede confirmar con la guía cerrada).
        if subio && seccionAbierta { Task { await self.consultar(); self.sondear() } }
    }

    /// Lo que la cola abandonó tras 8 intentos: «No se pudo mandar.» con «Reintentar». El archivo queda.
    public func alAbandonar(_ ops: [Operacion]) {
        for op in ops where op.kind == Self.kind {
            guard let id = op.payload["id"]?.comoTexto else { continue }
            poner(id, .noSeMando)
            anuncio = ReglasAudioDuda.textoNoSeMando; anuncios += 1
        }
    }

    // MARK: - La lista del servidor

    /// Al abrir la sección: lo de la cola, la lista y, si hay alguno pasando a texto, el sondeo.
    public func abrirSeccion() async {
        seccionAbierta = true
        await cargarDeLaCola()
        await consultar()
        sondear()
    }

    /// Al salir de la sección o pasar a segundo plano: nunca se consulta de fondo.
    public func cerrarSeccion() {
        seccionAbierta = false
        sondeo?.cancel(); sondeo = nil
    }

    /// `entregas_app_audios`. Si la función no existe (sin la 019), el botón no aparece.
    public func consultar() async {
        guard !esMuestra, !consultaEnCurso else { return }
        consultaEnCurso = true
        defer { consultaEnCurso = false }
        switch await cliente.llamar("entregas_app_audios", ["p_token": .texto(token)]) {
        case .success(.lista(let a)):
            servidor = a.compactMap(AudioServidor.init(json:))
            // Lo confirmado que ya trae el servidor deja de ser local.
            locales.removeAll { l in l.estado == .subido && servidor.contains { $0.id == l.id } }
            marcarDisponible(true)
        case .success(.null):
            marcarDisponible(true)
        case .success:
            break
        case .failure(let e):
            if e.funcionInexistente { marcarDisponible(false) }
        }
    }

    private func marcarDisponible(_ d: Bool) {
        guard d != disponible else { return }
        disponible = d
        disco?.guardar(d, Self.archivoDisponible)
    }

    /// Cada 15 s mientras haya alguno en `subido`, como mucho 3 minutos y solo con la sección abierta.
    func sondear() {
        guard seccionAbierta, haySubidos, sondeo == nil else { return }
        let inicio = reloj()
        sondeo = Task { [weak self, esperaSondeo] in
            while !Task.isCancelled {
                try? await Task.sleep(for: esperaSondeo)
                guard !Task.isCancelled, let self, self.seccionAbierta else { return }
                if self.reloj() - inicio > ReglasAudioDuda.sondeoMaximo { break }
                await self.consultar()
                if !self.haySubidos { break }
            }
            self?.sondeo = nil
        }
    }

    // MARK: - Pruebas de interfaz y capturas

    /// Para la maqueta: deja la lista del servidor armada (sin red).
    public func ponerServidor(_ a: [AudioServidor]) { servidor = a }
    public func ponerLocal(_ f: FilaAudio) { locales.append(f) }
}

// MARK: - La ejecución en la cola

extension Escrituras {
    /// El código de la falla que manda la op directo a fallidos: `iniciar` dijo `id` (ese `p_id` es de otro cliente). Con
    /// «Reintentar» sale con un `p_id` nuevo.
    static let codigoAudioId = "AUDIO_ID"

    /// `guia_audio`: iniciar, subir y confirmar, con el mismo `p_id` en cada reintento. Cada intento pide el ticket de
    /// nuevo (la base es idempotente por `p_id` y reactiva un ticket vencido con el mismo id). Red o transitorio en
    /// cualquier paso cortan sin gastar intento. Si `subido` contesta `sin_archivo` (hay que subir otra vez) o `vencido`
    /// (pedir el ticket de nuevo), se da una vuelta más dentro del mismo intento.
    func ejecutarAudio(_ p: JSONValue) async -> ResultadoOp {
        guard let id = p["id"]?.comoTexto, UUID(uuidString: id) != nil,
              let nombre = p["archivo"]?.comoTexto, !nombre.isEmpty, !nombre.contains("/"),
              let datos = try? Data(contentsOf: carpetaAudios.appendingPathComponent(nombre)), !datos.isEmpty
        else {
            // Sin el archivo no hay nada que mandar: se da por resuelta con «No se pudo mandar».
            return .respuesta(.success(.objeto(["ok": .bool(false), "motivo": .texto("archivo")])))
        }
        let mime = p["mime"]?.comoTexto ?? ReglasAudioDuda.mime
        let segundos = (p["segundos"]?.comoNumero ?? 0).rounded()
        var ultimo = "sin_archivo"
        for _ in 0..<2 {
            switch await vueltaAudio(id: id, datos: datos, mime: mime, segundos: segundos) {
            case .listo(let r): return r
            case .otraVuelta(let m): ultimo = m
            }
        }
        return .respuesta(.failure(ErrorRPC(clase: .permanente, status: 200, codigo: "AUDIO_\(ultimo.uppercased())", mensaje: ultimo)))
    }

    private enum Vuelta { case listo(ResultadoOp), otraVuelta(String) }

    private func vueltaAudio(id: String, datos: Data, mime: String, segundos: Double) async -> Vuelta {
        let t: JSONValue = .texto(token)
        let ticket: JSONValue
        switch await cliente.llamar("entregas_app_audio_iniciar", [
            "p_token": t, "p_mime": .texto(mime), "p_bytes": .numero(Double(datos.count)), "p_segundos": .numero(segundos), "p_id": .texto(id),
        ]) {
        case .failure(let e): return .listo(.respuesta(.failure(e)))
        case .success(let j): ticket = j
        }
        guard case .objeto = ticket else { return .listo(.respuesta(.success(.null))) }   // vacío: ¿cayó el token?
        guard ticket["ok"] == .bool(true) else { return .listo(Self.motivoAudio(ticket["motivo"]?.comoTexto)) }
        guard let bucket = ticket["bucket"]?.comoTexto, !bucket.isEmpty, let ruta = ticket["ruta"]?.comoTexto, !ruta.isEmpty else {
            return .listo(.respuesta(.failure(ErrorRPC(clase: .permanente, status: 200, codigo: "AUDIO_TICKET", mensaje: "ticket sin bucket o ruta"))))
        }
        // Un 403 o un 409 es «quizás ya subió» (la re-subida de la misma ruta da 403): lo decide `subido`.
        if case .failure(let e) = await cliente.subirObjeto(bucket: bucket, ruta: ruta, datos: datos, mime: ticket["mime"]?.comoTexto ?? mime) {
            return .listo(.respuesta(.failure(e)))
        }
        let r: JSONValue
        switch await cliente.llamar("entregas_app_audio_subido", ["p_token": t, "p_id": .texto(id)]) {
        case .failure(let e): return .listo(.respuesta(.failure(e)))
        case .success(let j): r = j
        }
        guard case .objeto = r else { return .listo(.respuesta(.success(.null))) }
        if r["ok"] == .bool(true) { return .listo(.respuesta(.success(.objeto(["ok": .bool(true), "id": .texto(id)])))) }
        switch r["motivo"]?.comoTexto {
        case "sin_archivo", "vencido", "no_existe": return .otraVuelta(r["motivo"]?.comoTexto ?? "")
        case let m: return .listo(Self.motivoAudio(m))
        }
    }

    /// Un `ok: false` de iniciar o de subido.
    static func motivoAudio(_ m: String?) -> ResultadoOp {
        switch m {
        case "token":
            return .respuesta(.success(.null))
        case "pendientes":
            // Otros audios a medio mandar (hasta 3 a la vez, con la web): más tarde, gastando intento.
            return .respuesta(.failure(ErrorRPC(clase: .permanente, status: 200, codigo: "AUDIO_PENDIENTES", mensaje: "pendientes")))
        case "id":
            // Ese p_id es de otro cliente: permanente, directo a fallidos.
            return .respuesta(.failure(ErrorRPC(clase: .permanente, status: 200, codigo: codigoAudioId, mensaje: "id")))
        case let m:
            return .respuesta(.success(.objeto(["ok": .bool(false), "motivo": m.map(JSONValue.texto) ?? .null])))
        }
    }
}

extension ClienteRPC {
    /// `POST /storage/v1/object/{bucket}/{ruta}` con los bytes tal cual, el `Content-Type` exacto (el bucket lo compara) y
    /// `x-upsert: false` (la política no deja pisar). Un 403, un 409 (o el 400 con `statusCode: "409"` de Storage) es que
    /// quizás ya estaba: cuenta como subido y lo confirma `entregas_app_audio_subido`. Dos minutos de espera: 2,4 MB con poca señal tardan más que una RPC.
    public func subirObjeto(bucket: String, ruta: String, datos: Data, mime: String, espera: TimeInterval = 120) async -> Result<Void, ErrorRPC> {
        var url = config.supabase.appendingPathComponent("storage/v1/object").appendingPathComponent(bucket)
        for parte in ruta.split(separator: "/") { url.appendPathComponent(String(parte)) }
        var pedido = URLRequest(url: url, timeoutInterval: espera)
        pedido.httpMethod = "POST"
        pedido.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        pedido.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        pedido.setValue(mime, forHTTPHeaderField: "Content-Type")
        pedido.setValue("false", forHTTPHeaderField: "x-upsert")
        pedido.httpBody = datos
        let cuerpo: Data, respuesta: URLResponse
        do {
            (cuerpo, respuesta) = try await transporte.enviar(pedido)
        } catch {
            return .failure(ErrorRPC(clase: .red, status: 0, mensaje: "\(error)"))
        }
        let status = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        // 403 y 409: la ruta ya tiene el archivo (la política no deja pisar ni leer). Lo confirma `subido`.
        if (200..<300).contains(status) || status == 409 || status == 403 { return .success(()) }
        let json = try? JSONDecoder().decode(JSONValue.self, from: cuerpo)
        let codigoStorage = json?["statusCode"]?.comoTexto ?? json?["statusCode"]?.comoNumero.map { String(Int($0)) }
        if codigoStorage == "409" || codigoStorage == "403" || json?["error"]?.comoTexto == "Duplicate" { return .success(()) }
        let clase: ErrorRPC.Clase = (status == 429 || status == 408 || status >= 500) ? .transitorio : .permanente
        return .failure(ErrorRPC(clase: clase, status: status, codigo: codigoStorage, mensaje: json?["message"]?.comoTexto ?? "storage \(status)"))
    }
}
