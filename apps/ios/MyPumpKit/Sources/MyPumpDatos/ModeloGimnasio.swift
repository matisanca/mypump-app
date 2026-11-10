import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Una foto del gimnasio que espera subir. El JPEG va en su propio archivo (`gimnasio-fotos/<id>.jpg`) y acá solo el índice:
/// la cola de fotos de progreso guarda todo en un solo JSON en base64, que con 80 fotos de 1600 px no entra.
public struct PendienteGimnasio: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let gimnasioId: String
    public let zona: String
    /// La pregunta `foto` que contesta, si es de la ronda de preguntas.
    public var pregunta: String?

    public static let archivo = "gimnasio-cola.json"
    public static let carpeta = "gimnasio-fotos"
}

/// Lo que el alumno ya mandó y sale cuando termine de subir la cola, aunque cierre la app.
public struct EnvioGimnasio: Codable, Equatable, Sendable {
    public enum Tipo: String, Codable, Sendable { case enviar, responder }
    public var tipo: Tipo
    public var gimnasioId: String
    public var noHay: [String] = []
    public var nota: String = ""
    public var consentimiento: String = ""
    public var quitar: [String] = []
}

/// Lo que el alumno lleva hecho en el teléfono y todavía no le dijo al servidor.
struct BorradorGimnasio: Codable, Equatable {
    var gimnasioId: String?
    var noHay: [String] = []
    var nota = ""
    var quitar: [String] = []
    var respuestas: [String: JSONValue] = [:]
    var avisoVersion: String?
    var envio: EnvioGimnasio?
    static let archivo = "gimnasio-borrador.json"
}

/// Gimnasio por fotos. Mismo criterio de cola que `ModeloFotos`: en disco, sobrevive a cerrar la app y a quedarse sin señal,
/// un error del servidor (5xx o 429) no gasta la foto, y todo 4xx es definitivo. Con la palanca apagada `ModeloApp` no llama
/// a nada de esto: `estado` queda en nil y no se ve ni se pide nada.
@MainActor @Observable
public final class ModeloGimnasio {
    public enum Resultado: Equatable, Sendable { case ok, sinSenal, error, tokenCaido }
    public enum Foto: Equatable, Sendable { case guardada, tope, noSeGuardo }
    public enum AvisoEnvio: Equatable, Sendable { case faltan([String]), sinConsentimiento, sinNovedad, error }

    public struct VistaFoto: Identifiable, Equatable, Sendable {
        public let id: String
        public let archivoLocal: URL?
        public let subiendo: Bool
        public let esperando: Bool
    }

    /// nil: apagado, sin el servidor nuevo, o sin red la primera vez. No se muestra nada.
    public private(set) var estado: EstadoGimnasio?
    public private(set) var cola: [PendienteGimnasio] = []
    public private(set) var subiendo: String?
    public private(set) var urls: [String: URL] = [:]
    /// Lo último que pasó con una foto («no se pudo usar», «llegaste al máximo»).
    public private(set) var avisoFoto: Gimnasio.AvisoFoto?
    public private(set) var avisoEnvio: AvisoEnvio?
    /// Cuántas fotos de esta tanda ya subieron, para «Subiendo tus fotos: 12 de 40».
    public private(set) var subidasEnvio = 0
    public private(set) var totalEnvio = 0
    private var borrador = BorradorGimnasio()

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    /// Espera entre reintentos (en las pruebas, nada).
    @ObservationIgnored private let esperar: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private var drenando = false
    @ObservationIgnored private var conError: Set<String> = []
    @ObservationIgnored private var borrarAlSubir: Set<String> = []
    @ObservationIgnored private var urlsVencen: Date?
    @ObservationIgnored private var reintentoProgramado = false
    @ObservationIgnored private var reintentosDeFondo = 0
    @ObservationIgnored private var mandandoEnvio = false

    static let archivoEstado = "gimnasio-estado.json"
    static let maxIntentosSeguidos = 3
    static let maxReintentosDeFondo = 5

    public init(cliente: ClienteRPC, token: String, disco: Disco?,
                esperar: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.cliente = cliente; self.token = token; self.disco = disco; self.esperar = esperar
        cola = disco?.leer([PendienteGimnasio].self, PendienteGimnasio.archivo) ?? []
        borrador = disco?.leer(BorradorGimnasio.self, BorradorGimnasio.archivo) ?? BorradorGimnasio()
        barrerHuerfanos()
    }

    /// Un cierre entre el JPEG y el índice deja un archivo que nadie sube ni borra.
    private func barrerHuerfanos() {
        guard let disco else { return }
        let carpeta = disco.url(PendienteGimnasio.carpeta)
        let vivos = Set(cola.map { "\($0.id).jpg" })
        for f in (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? [] where !vivos.contains(f) {
            try? FileManager.default.removeItem(at: carpeta.appendingPathComponent(f))
        }
    }

    // MARK: Lo que lee la pantalla

    public var abierta: CargaGimnasio? { estado?.abierta }
    public var vigente: CargaGimnasio? { estado?.vigente }
    public var envio: EnvioGimnasio? { borrador.envio }
    public var nota: String { borrador.nota }
    public var noHay: Set<String> { Set(borrador.noHay) }
    public var quitar: Set<String> { Set(borrador.quitar) }
    public var respuestas: [String: JSONValue] { borrador.respuestas }

    public var tarjetaVisible: Bool {
        Gimnasio.tarjetaVisible(habilitado: estado != nil, abierta: abierta?.estado, hayVigente: vigente != nil)
    }
    public var entradaVisible: Bool { Gimnasio.entradaVisible(habilitado: estado != nil, hayVigente: vigente != nil) }
    public var pantalla: Gimnasio.Pantalla { Gimnasio.pantalla(abierta: abierta?.estado, hayVigente: vigente != nil) }

    /// El aviso de terceros, una sola vez: si el servidor no lo tiene aceptado y en este teléfono no se aceptó esta versión.
    public var necesitaAviso: Bool {
        guard let e = estado else { return false }
        return !e.consentimientoAceptado && borrador.avisoVersion != e.consentimientoVersion
    }

    private var colaDeLaCarga: [PendienteGimnasio] {
        guard let id = abierta?.id else { return [] }
        let enServidor = Set(abierta?.fotos.map(\.id) ?? [])
        return cola.filter { $0.gimnasioId == id && !enServidor.contains($0.id) }
    }

    public var zonasConFotos: Set<String> {
        Set((abierta?.fotos.map(\.zona) ?? []) + colaDeLaCarga.map(\.zona))
    }
    public var faltantes: [String] {
        guard let a = abierta else { return [] }
        return Gimnasio.zonasFaltantes(conFotos: zonasConFotos, noHay: noHay, modo: a.modo)
    }
    public var puedeEnviar: Bool {
        guard let a = abierta else { return false }
        return Gimnasio.puedeEnviar(modo: a.modo, conFotos: zonasConFotos, noHay: noHay, quitar: quitar)
    }
    public var puedeAgregar: Bool {
        Gimnasio.puedeAgregar(enServidor: abierta?.fotos.count ?? 0, enCola: colaDeLaCarga.count)
    }
    public var totalFotos: Int { (abierta?.fotos.count ?? 0) + colaDeLaCarga.count }

    public func fotos(zona: String) -> [VistaFoto] {
        let aqui = colaDeLaCarga.filter { $0.zona == zona }.map {
            VistaFoto(id: $0.id, archivoLocal: archivo($0.id), subiendo: subiendo == $0.id, esperando: subiendo != $0.id)
        }
        let enServidor = (abierta?.fotos ?? []).filter { $0.zona == zona }.map { VistaFoto(id: $0.id, archivoLocal: nil, subiendo: false, esperando: false) }
        return enServidor + aqui
    }

    // MARK: Servidor

    /// `get`. Sin el servidor nuevo o apagado para esta cuenta: nada se muestra. Sin red, lo último que se supo (con señal
    /// pobre en el gimnasio se pueden seguir sacando fotos); si nunca se supo nada, tampoco se muestra.
    public func refrescar() async {
        switch await cliente.llamar("mypump_gimnasio_get", ["p_token": .texto(token)]) {
        case .success(.null):
            estado = nil
        case .success(let j):
            guard let e = EstadoGimnasio(j) else { apagar(); disco?.borrar(Self.archivoEstado); return }
            aplicar(e)
            disco?.guardar(j, Self.archivoEstado)
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            apagar()
            disco?.borrar(Self.archivoEstado)
        case .failure:
            // Solo para seguir una carga a medio hacer: lo demás, sin señal, no se muestra (contrato, sección 1).
            if estado == nil, let j = disco?.leer(JSONValue.self, Self.archivoEstado), let e = EstadoGimnasio(j),
               e.abierta?.estado == "borrador" || e.abierta?.estado == "a_confirmar" { aplicar(e) }
        }
    }

    public func apagar() { estado = nil }

    private func aplicar(_ e: EstadoGimnasio) {
        estado = e
        var b = borrador
        let id = e.abierta?.id
        if b.gimnasioId != id {
            b = BorradorGimnasio(gimnasioId: id, avisoVersion: b.avisoVersion, envio: b.envio?.gimnasioId == id ? b.envio : nil)
        }
        // Lo que el servidor ya tomó deja de estar pendiente (un reintento devuelve `ya`).
        if let en = b.envio, let a = e.abierta, (en.tipo == .enviar && a.estado != "borrador") || (en.tipo == .responder && a.estado != "a_confirmar") {
            b.envio = nil
        }
        if b != borrador { borrador = b; guardarBorrador() }
    }

    /// Abre una carga. `parcial` sin gimnasio vigente cae a la completa.
    @discardableResult
    public func empezar(modo: String = "completa") async -> Resultado {
        return await nuevo(modo: modo, reintentos: 1)
    }

    /// El aviso de terceros quedó aceptado en este teléfono (`enviar` lleva la versión al servidor).
    public func aceptarAviso() {
        guard let e = estado else { return }
        borrador.avisoVersion = e.consentimientoVersion
        guardarBorrador()
    }

    private func nuevo(modo: String, reintentos: Int) async -> Resultado {
        switch await cliente.llamar("mypump_gimnasio_nuevo", ["p_token": .texto(token), "p_modo": .texto(modo)]) {
        case .success(.null): return .tokenCaido
        case .success(let j):
            if j["ok"] == .bool(true) { await refrescar(); return .ok }
            switch j["error"]?.comoTexto {
            case "sin_gimnasio_vigente": return await nuevo(modo: "completa", reintentos: reintentos)
            case "no_habilitado": apagar(); return .error
            case "reintentar" where reintentos > 0: return await nuevo(modo: modo, reintentos: reintentos - 1)
            default: return .error
            }
        case .failure(let e): return e.clase == .permanente ? .error : .sinSenal
        }
    }

    // MARK: Fotos

    /// Encola el JPEG ya reducido (1600 px, 0,8, sin EXIF). Después hay que drenar.
    public func agregar(zona: String, jpeg: Data, pregunta: String? = nil) -> Foto {
        guard let a = abierta, let disco else { return .noSeGuardo }
        // Las de una pregunta tienen su propio cupo en el servidor: el tope de 80 es el de la carga.
        guard pregunta != nil || puedeAgregar else { avisoFoto = .tope; return .tope }
        let id = UUID().uuidString.lowercased()
        guard guardarJPEG(jpeg, id: id, en: disco) else { return .noSeGuardo }
        cola.append(PendienteGimnasio(id: id, gimnasioId: a.id, zona: zona, pregunta: pregunta))
        guard guardarCola() else {
            cola.removeLast()
            disco.borrar("\(PendienteGimnasio.carpeta)/\(id).jpg")
            return .noSeGuardo
        }
        avisoFoto = nil
        if noHay.contains(zona) { borrador.noHay.removeAll { $0 == zona }; guardarBorrador() }
        if let pregunta { borrador.respuestas[pregunta] = .texto("subida"); guardarBorrador() }
        return .guardada
    }

    public func drenarEnFondo() { Task { await drenar() } }

    public func borrarFoto(id: String) async -> Resultado {
        if subiendo == id { borrarAlSubir.insert(id); sacarDeLaCola(id); return .ok }
        if cola.contains(where: { $0.id == id }) { sacarDeLaCola(id); return .ok }
        guard let r = await postVision("gimnasio/borrar", ["token": .texto(token), "foto_id": .texto(id)]) else { return .sinSenal }
        if r.status == 409 || !(200..<300).contains(r.status) || r.json?["ok"] != .bool(true) { await refrescar(); return .error }
        estado?.abierta?.fotos.removeAll { $0.id == id }
        return .ok
    }

    private func sacarDeLaCola(_ id: String) {
        let quitada = cola.first { $0.id == id }
        cola.removeAll { $0.id == id }
        _ = guardarCola()
        disco?.borrar("\(PendienteGimnasio.carpeta)/\(id).jpg")
        if let p = quitada?.pregunta, !cola.contains(where: { $0.pregunta == p }), borrador.respuestas[p] != nil {
            borrador.respuestas[p] = nil
            guardarBorrador()
        }
    }

    public func marcarNoHay(_ zona: String, _ no: Bool) {
        var s = noHay
        if no { s.insert(zona) } else { s.remove(zona) }
        borrador.noHay = Gimnasio.zonas.map(\.clave).filter(s.contains)
        guardarBorrador()
    }

    public func fijarNota(_ s: String) {
        let n = Gimnasio.notaRecortada(s)
        guard n != borrador.nota else { return }
        borrador.nota = n
        guardarBorrador()
    }

    public func alternarQuitar(_ tipo: String) {
        if let i = borrador.quitar.firstIndex(of: tipo) { borrador.quitar.remove(at: i) } else { borrador.quitar.append(tipo) }
        guardarBorrador()
    }

    public func responder(_ id: String, _ valor: JSONValue?) {
        borrador.respuestas[id] = valor
        guardarBorrador()
    }

    public func limpiarAvisoFoto() { avisoFoto = nil }

    // MARK: Cola

    /// Una pasada a la vez. Red: corta y espera a que vuelva. 5xx o 429: espera y reintenta, y a la tercera seguida deja esa
    /// foto para el final y corta la pasada (una que el servidor no puede guardar no traba a las demás). Todo 4xx es definitivo.
    /// Al vaciarse la cola de la carga sale lo que el alumno haya mandado.
    public func drenar() async {
        guard !drenando, estado != nil else { return }
        drenando = true
        defer { drenando = false }
        var refrescarAlFinal = false
        var seguidas = 0
        pasada: while let item = cola.sorted(by: orden).first(where: { !borrarAlSubir.contains($0.id) }) {
            subiendo = item.id
            let r = await subir(item)
            subiendo = nil
            switch r {
            case .ok:
                sacarSubida(item)
                seguidas = 0
                reintentosDeFondo = 0
                subidasEnvio += 1
            case .perdida:
                sacarDeLaCola(item.id)
            case .descartar(let s):
                refrescarAlFinal = refrescarAlFinal || s.refrescar
                if let a = s.aviso { avisoFoto = a }
                descartar(item)
            case .reintentar:
                conError.insert(item.id)
                seguidas += 1
                if seguidas >= Self.maxIntentosSeguidos { programarReintento(); break pasada }
                await esperar(pow(2, Double(seguidas)))
            case .red:
                break pasada
            }
        }
        borrarAlSubir.removeAll()
        if refrescarAlFinal { await refrescar() }
        await mandarEnvio()
    }

    /// Después de una tanda de errores, una pasada más sola, con la app abierta.
    private func programarReintento() {
        guard !reintentoProgramado, reintentosDeFondo < Self.maxReintentosDeFondo else { return }
        reintentoProgramado = true
        reintentosDeFondo += 1
        Task { [weak self, esperar] in
            await esperar(60)
            self?.reintentoProgramado = false
            await self?.drenar()
        }
    }

    private var orden: (PendienteGimnasio, PendienteGimnasio) -> Bool {
        { [conError] a, b in (conError.contains(a.id) ? 1 : 0) < (conError.contains(b.id) ? 1 : 0) }
    }

    enum EnvioFoto { case ok, perdida, descartar(Gimnasio.Subida), reintentar, red }

    private func subir(_ p: PendienteGimnasio) async -> EnvioFoto {
        guard let datos = try? Data(contentsOf: archivo(p.id)) else { return .perdida }
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent("gimnasio/upload"), timeoutInterval: 150)
        pedido.httpMethod = "POST"
        pedido.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        pedido.setValue(token, forHTTPHeaderField: "x-gimnasio-token")
        pedido.setValue(p.gimnasioId, forHTTPHeaderField: "x-gimnasio-id")
        pedido.setValue(p.id, forHTTPHeaderField: "x-gimnasio-foto")
        pedido.setValue(p.zona, forHTTPHeaderField: "x-gimnasio-zona")
        pedido.httpBody = datos
        guard let (cuerpo, resp) = try? await cliente.transporte.enviar(pedido) else { return .red }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let j = try? JSONDecoder().decode(JSONValue.self, from: cuerpo)
        let s = Gimnasio.clasificarSubida(status: status, ok: j?["ok"] == .bool(true))
        switch s.accion {
        case .ok: return .ok
        case .descartar: return .descartar(s)
        case .reintentar: return .reintentar
        }
    }

    /// Subió bien. Si la borraron mientras subía se saca también del servidor.
    private func sacarSubida(_ item: PendienteGimnasio) {
        conError.remove(item.id)
        cola.removeAll { $0.id == item.id }
        _ = guardarCola()
        disco?.borrar("\(PendienteGimnasio.carpeta)/\(item.id).jpg")
        if borrarAlSubir.remove(item.id) != nil {
            Task { _ = await borrarFoto(id: item.id) }
        } else if !(estado?.abierta?.fotos.contains { $0.id == item.id } ?? true), item.gimnasioId == abierta?.id {
            let ronda = abierta?.estado == "borrador" ? 0 : 1
            estado?.abierta?.fotos.append(FotoGimnasio(id: item.id, zona: item.zona, ronda: ronda))
            urlsVencen = nil
        }
    }

    /// No va a entrar nunca. Si era para una pregunta, se le pide que la saque de nuevo.
    private func descartar(_ item: PendienteGimnasio) {
        sacarDeLaCola(item.id)
        conError.remove(item.id)
        if item.pregunta != nil, borrador.envio?.tipo == .responder {
            borrador.envio = nil
            guardarBorrador()
        }
    }

    // MARK: Enviar

    /// «Enviar a Mati»: queda anotado en disco y sale al vaciarse la cola; si no hay red, cuando vuelva.
    public func enviarCarga() async {
        guard let a = abierta, let e = estado else { return }
        guard !necesitaAviso else { avisoEnvio = .sinConsentimiento; return }   // la raíz muestra el aviso antes de seguir
        avisoEnvio = nil
        totalEnvio = totalFotos
        subidasEnvio = abierta?.fotos.count ?? 0
        borrador.envio = EnvioGimnasio(tipo: .enviar, gimnasioId: a.id, noHay: borrador.noHay, nota: borrador.nota,
                                       consentimiento: e.consentimientoVersion, quitar: a.modo == "parcial" ? borrador.quitar : [])
        guardarBorrador()
        await drenar()
    }

    /// Las respuestas de la ronda: salen después de las fotos que se pidieron.
    public func enviarRespuestas() async {
        guard let a = abierta else { return }
        avisoEnvio = nil
        borrador.envio = EnvioGimnasio(tipo: .responder, gimnasioId: a.id)
        guardarBorrador()
        await drenar()
    }

    /// Volver a editar: lo que estaba en la cola sigue subiendo, pero la carga no se manda hasta que la vuelva a enviar.
    public func cancelarEnvio() {
        borrador.envio = nil
        guardarBorrador()
    }

    private func mandarEnvio() async {
        guard let e = borrador.envio, !mandandoEnvio, !cola.contains(where: { $0.gimnasioId == e.gimnasioId }) else { return }
        mandandoEnvio = true
        defer { mandandoEnvio = false }
        let r: Result<JSONValue, ErrorRPC>
        switch e.tipo {
        case .enviar:
            r = await cliente.llamar("mypump_gimnasio_enviar", [
                "p_token": .texto(token), "p_id": .texto(e.gimnasioId), "p_no_hay": .lista(e.noHay.map(JSONValue.texto)),
                "p_nota": .texto(e.nota), "p_consentimiento": .texto(e.consentimiento), "p_quitar": .lista(e.quitar.map(JSONValue.texto)),
            ])
        case .responder:
            let preguntas = abierta?.preguntas ?? []
            r = await cliente.llamar("mypump_gimnasio_responder", [
                "p_token": .texto(token), "p_id": .texto(e.gimnasioId),
                "p_respuestas": .objeto(Gimnasio.respuestasParaEnviar(preguntas, borrador.respuestas)),
            ])
        }
        switch r {
        case .success(.null):
            return   // token caído: queda guardado para el link nuevo
        case .success(let j):
            if j["ok"] == .bool(true) {
                borrador.envio = nil
                if e.tipo == .responder { borrador.respuestas = [:] }
                guardarBorrador()
                await refrescar()
                return
            }
            borrador.envio = nil
            guardarBorrador()
            switch j["error"]?.comoTexto {
            case "faltan_zonas": avisoEnvio = .faltan((j["faltan"]?.listaGim ?? []).compactMap(\.comoTexto))
            case "sin_consentimiento":
                borrador.avisoVersion = nil
                guardarBorrador()
                avisoEnvio = .sinConsentimiento
                await refrescar()
            case "sin_novedad": avisoEnvio = .sinNovedad
            case "no_encontrado", "estado_invalido": await refrescar()
            case "no_habilitado": apagar()
            default: avisoEnvio = .error
            }
        case .failure(let f):
            if f.clase == .permanente {   // 22023: error de programación, no se reintenta
                borrador.envio = nil
                guardarBorrador()
                avisoEnvio = .error
            } else {
                programarReintento()
            }
        }
    }

    // MARK: Miniaturas

    /// URLs firmadas de las fotos de la carga (1 h: se piden de nuevo a los 50 min o si aparece una que no estaba).
    public func firmar(gimnasioId: String, ids: [String], forzar: Bool = false) async {
        let faltaAlguna = ids.contains { urls[$0] == nil }
        if !forzar, !faltaAlguna, let v = urlsVencen, v > Date() { return }
        guard let r = await postVision("gimnasio/urls", ["token": .texto(token), "gimnasio_id": .texto(gimnasioId)]),
              r.json?["ok"] == .bool(true), let filas = r.json?["fotos"]?.listaGim else { return }
        var mapa = urls
        for f in filas { if let i = f["id"]?.comoTexto, let u = f["url"]?.comoTexto.flatMap(URL.init(string:)) { mapa[i] = u } }
        urls = mapa
        urlsVencen = Date().addingTimeInterval(50 * 60)
    }

    private func postVision(_ ruta: String, _ cuerpo: [String: JSONValue]) async -> (status: Int, json: JSONValue?)? {
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent(ruta), timeoutInterval: 30)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.httpBody = try? JSONEncoder().encode(JSONValue.objeto(cuerpo))
        guard let (datos, resp) = try? await cliente.transporte.enviar(pedido) else { return nil }
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, try? JSONDecoder().decode(JSONValue.self, from: datos))
    }

    // MARK: Disco

    func archivo(_ id: String) -> URL {
        (disco?.url(PendienteGimnasio.carpeta) ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("\(id).jpg")
    }

    private func guardarJPEG(_ jpeg: Data, id: String, en disco: Disco) -> Bool {
        var carpeta = disco.url(PendienteGimnasio.carpeta)
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            var valores = URLResourceValues()
            valores.isExcludedFromBackup = true   // viven hasta que suben: no van a la copia de iCloud
            try? carpeta.setResourceValues(valores)
            try jpeg.write(to: carpeta.appendingPathComponent("\(id).jpg"), options: [.atomic])
            return true
        } catch { return false }
    }

    private func guardarCola() -> Bool {
        guard let disco else { return false }
        if cola.isEmpty { disco.borrar(PendienteGimnasio.archivo); return true }
        return disco.guardar(cola, PendienteGimnasio.archivo)
    }

    private func guardarBorrador() { disco?.guardar(borrador, BorradorGimnasio.archivo) }

    /// Las fotos que quedaron en la carpeta de otro link de la misma persona (`CuentasDelTelefono.adoptarGimnasio`).
    func adoptar(_ otras: [PendienteGimnasio], desde otra: Disco) -> Bool {
        guard let disco else { return false }
        var todas = true
        for p in otras where !cola.contains(where: { $0.id == p.id }) {
            guard let datos = try? Data(contentsOf: otra.url("\(PendienteGimnasio.carpeta)/\(p.id).jpg")), guardarJPEG(datos, id: p.id, en: disco) else { todas = false; continue }
            cola.append(p)
        }
        if let viejo = otra.leer(BorradorGimnasio.self, BorradorGimnasio.archivo), borrador.envio == nil, borrador.noHay.isEmpty, borrador.nota.isEmpty, borrador.respuestas.isEmpty,
           borrador.gimnasioId == nil || borrador.gimnasioId == viejo.gimnasioId {
            borrador = viejo
            guardarBorrador()
        }
        return guardarCola() && todas
    }
}

extension JSONValue {
    var listaGim: [JSONValue]? { if case .lista(let l) = self { l } else { nil } }
}
