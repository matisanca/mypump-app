import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Una foto de inicio que espera subir. El JPEG va en su propio archivo (`fotos-inicio/<id>.jpg`) y acá solo el índice.
public struct PendienteFotoInicio: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let pose: String
    /// ISO 8601 con zona: cuándo se sacó.
    public let tomadaEn: String
    public var brillo: Double?
    public var nitidez: Double?

    public static let archivo = "fotos-inicio-cola.json"
    public static let carpeta = "fotos-inicio"
}

/// La nota que no se pudo mandar (sin red): sale con la cola.
struct BorradorFotosInicio: Codable, Equatable {
    var nota: String
    static let archivo = "fotos-inicio-borrador.json"
}

/// Fotos de inicio (contrato, sección 13): frente, perfil y espalda, y «el físico que te motiva». La cola es la de Gimnasio:
/// en disco, sobrevive a cerrar la app y a quedarse sin señal, se sube de a una en el orden en que se encolaron, un error del
/// servidor (5xx o 429) no gasta la foto, y todo otro 4xx es definitivo (`FotosInicio.clasificarSubida`). Con la palanca
/// `fotos_inicio` apagada `ModeloApp` no llama a nada de esto: `estado` queda en nil y no se ve ni se pide nada.
@MainActor @Observable
public final class ModeloFotosInicio {
    public enum Salida: Equatable, Sendable { case ok, sinSenal, error, tokenCaido }
    public enum Foto: Equatable, Sendable { case guardada, tope, noSeGuardo }
    public enum EstadoPose: Equatable, Sendable { case falta, subiendo, esperando, lista }

    /// Lo que se ve de una foto: la del teléfono mientras espera subir, o la del servidor (con su miniatura firmada).
    public struct VistaFoto: Identifiable, Equatable, Sendable {
        public let id: String
        public let pose: String
        public let archivoLocal: URL?
        public let subiendo: Bool
        public let esperando: Bool
    }

    /// nil: apagado, sin el servidor nuevo, token caído, o sin red y sin nada guardado. No se muestra nada.
    public private(set) var estado: EstadoFotosInicio?
    public private(set) var cola: [PendienteFotoInicio] = []
    public private(set) var subiendo: String?
    public private(set) var urls: [String: URL] = [:]
    /// Lo último que pasó con una foto («no se pudo usar», «hasta 4 fotos»).
    public private(set) var aviso: FotosInicio.Aviso?
    /// La nota que el alumno guardó sin red: se manda sola con la cola.
    public private(set) var notaPendiente: String?
    /// El servidor contestó null: el link ya no sirve (la app lleva a pedir el nuevo).
    public private(set) var tokenCaido = false

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    /// Espera entre reintentos (en las pruebas, nada).
    @ObservationIgnored private let esperar: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private let ahora: @Sendable () -> Date
    @ObservationIgnored private var drenando = false
    @ObservationIgnored private var mandandoNota = false
    @ObservationIgnored private var conError: Set<String> = []
    @ObservationIgnored private var borrarAlSubir: Set<String> = []
    @ObservationIgnored private var urlsVencen: Date?
    @ObservationIgnored private var reintentoProgramado = false
    @ObservationIgnored private var reintentosDeFondo = 0

    static let archivoEstado = "fotos-inicio-estado.json"
    static let maxIntentosSeguidos = 3
    static let maxReintentosDeFondo = 5

    public init(cliente: ClienteRPC, token: String, disco: Disco?,
                esperar: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
                ahora: @escaping @Sendable () -> Date = { Date() }) {
        self.cliente = cliente; self.token = token; self.disco = disco; self.esperar = esperar; self.ahora = ahora
        cola = disco?.leer([PendienteFotoInicio].self, PendienteFotoInicio.archivo) ?? []
        notaPendiente = disco?.leer(BorradorFotosInicio.self, BorradorFotosInicio.archivo)?.nota
        barrerHuerfanos()
    }

    /// Un cierre entre el JPEG y el índice deja un archivo que nadie sube ni borra.
    private func barrerHuerfanos() {
        guard let disco else { return }
        let carpeta = disco.url(PendienteFotoInicio.carpeta)
        let vivos = Set(cola.map { "\($0.id).jpg" })
        for f in (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? [] where !vivos.contains(f) {
            try? FileManager.default.removeItem(at: carpeta.appendingPathComponent(f))
        }
    }

    // MARK: Lo que lee la pantalla

    /// La tarjeta de Revisión y la fila de Mis datos: solo con `habilitado: true`.
    public var visible: Bool { estado != nil }
    private var posesEnCola: Set<String> { Set(cola.map(\.pose).filter { $0 != FotosInicio.motivacion }) }
    /// Las poses del cuerpo que faltan, contando las que esperan subir.
    public var faltan: [String] { FotosInicio.faltan(enServidor: estado?.poses ?? [], enCola: posesEnCola) }
    /// Cuántas de las tres ya están (en el servidor o esperando subir).
    public var hechas: Int { FotosInicio.poses.count - faltan.count }
    /// Las tres en el servidor: Mati ya las tiene.
    public var listas: Bool { Set(FotosInicio.poses.map(\.clave)).isSubset(of: estado?.poses ?? []) }

    public func estadoPose(_ pose: String) -> EstadoPose {
        if let enCola = cola.last(where: { $0.pose == pose }) { return subiendo == enCola.id ? .subiendo : .esperando }
        return estado?.foto(pose: pose) != nil ? .lista : .falta
    }

    /// La foto que se muestra de una pose del cuerpo: la que espera subir (es la más nueva) o la del servidor.
    public func foto(_ pose: String) -> VistaFoto? {
        if let p = cola.last(where: { $0.pose == pose }) {
            return VistaFoto(id: p.id, pose: pose, archivoLocal: archivo(p.id), subiendo: subiendo == p.id, esperando: subiendo != p.id)
        }
        return estado?.foto(pose: pose).map { VistaFoto(id: $0.id, pose: pose, archivoLocal: nil, subiendo: false, esperando: false) }
    }

    /// «El físico que te motiva»: las del servidor y después las que esperan subir.
    public var motivacion: [VistaFoto] {
        let enServidor = (estado?.deMotivacion ?? []).map { VistaFoto(id: $0.id, pose: $0.pose, archivoLocal: nil, subiendo: false, esperando: false) }
        let ids = Set(enServidor.map(\.id))
        return enServidor + cola.filter { $0.pose == FotosInicio.motivacion && !ids.contains($0.id) && !borrarAlSubir.contains($0.id) }
            .map { VistaFoto(id: $0.id, pose: $0.pose, archivoLocal: archivo($0.id), subiendo: subiendo == $0.id, esperando: subiendo != $0.id) }
    }

    public var maxMotivacion: Int { estado?.maxMotivacion ?? FotosInicio.maxMotivacion }
    public var puedeAgregarMotivacion: Bool {
        let enServidor = estado?.deMotivacion ?? []
        let ids = Set(enServidor.map(\.id))
        let enCola = cola.filter { $0.pose == FotosInicio.motivacion && !ids.contains($0.id) }.count
        return FotosInicio.puedeAgregarMotivacion(enServidor: enServidor.count, enCola: enCola, maximo: maxMotivacion)
    }

    // MARK: Servidor

    /// `get`. null es token caído; `habilitado:false`, sin el servidor nuevo (PGRST202, 404) o un rechazo: apagado. Sin red, lo
    /// último que se supo.
    public func refrescar() async {
        switch await cliente.llamar("mypump_fotos_inicio_get", ["p_token": .texto(token)]) {
        case .success(.null):
            estado = nil
            tokenCaido = true
        case .success(let j):
            tokenCaido = false
            guard let e = EstadoFotosInicio(j) else { apagar(); disco?.borrar(Self.archivoEstado); return }
            estado = e
            disco?.guardar(j, Self.archivoEstado)
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            apagar()
            disco?.borrar(Self.archivoEstado)
        case .failure:
            if estado == nil, !tokenCaido, let j = disco?.leer(JSONValue.self, Self.archivoEstado), let e = EstadoFotosInicio(j) { estado = e }
        }
    }

    public func apagar() { estado = nil }

    // MARK: Fotos

    /// Encola el JPEG ya preparado (1600 px, 0,85, derecho y sin metadatos). Una pose del cuerpo saca de la cola a la anterior
    /// de esa pose que todavía no empezó a subir. Después hay que drenar.
    public func encolar(pose: String, jpeg: Data, tomadaEn: Date, medida: FotosInicio.Medida? = nil) -> Foto {
        guard estado != nil, let disco else { return .noSeGuardo }
        let esMotivacion = pose == FotosInicio.motivacion
        guard esMotivacion || FotosInicio.pose(pose) != nil else { return .noSeGuardo }
        if esMotivacion && !puedeAgregarMotivacion { aviso = .tope; return .tope }
        let id = UUID().uuidString.lowercased()
        guard guardarJPEG(jpeg, id: id, en: disco) else { return .noSeGuardo }
        let item = PendienteFotoInicio(id: id, pose: pose, tomadaEn: Self.iso(tomadaEn), brillo: medida?.brillo, nitidez: medida?.nitidez)
        let anterior = cola
        let reemplazadas = esMotivacion ? [] : anterior.filter { $0.pose == pose && $0.id != subiendo }
        cola = anterior.filter { !reemplazadas.contains($0) } + [item]
        guard guardarCola() else {
            cola = anterior
            disco.borrar("\(PendienteFotoInicio.carpeta)/\(id).jpg")
            return .noSeGuardo
        }
        for r in reemplazadas {
            conError.remove(r.id)
            disco.borrar("\(PendienteFotoInicio.carpeta)/\(r.id).jpg")
        }
        aviso = nil
        return .guardada
    }

    /// Solo las de motivación: las del cuerpo se reemplazan subiendo otra de la misma pose.
    public func borrarMotivacion(id: String) async -> Salida {
        if subiendo == id { borrarAlSubir.insert(id); return .ok }
        if cola.contains(where: { $0.id == id }) { sacarDeLaCola(id); return .ok }
        guard estado?.deMotivacion.contains(where: { $0.id == id }) == true else { return .error }
        guard let r = await postVision("inicio/borrar", ["token": .texto(token), "foto_id": .texto(id)]) else { return .sinSenal }
        guard (200..<300).contains(r.status), r.json?["ok"] == .bool(true) else { await refrescar(); return .error }
        actualizarEstado { $0.fotos.removeAll { $0.id == id } }
        return .ok
    }

    private func sacarDeLaCola(_ id: String) {
        cola.removeAll { $0.id == id }
        _ = guardarCola()
        disco?.borrar("\(PendienteFotoInicio.carpeta)/\(id).jpg")
        conError.remove(id)
    }

    public func limpiarAviso() { aviso = nil }

    // MARK: La nota

    /// «Guardar nota». Sin red queda guardada en el teléfono (`notaPendiente`) y sale con la cola. El texto se recorta como lo
    /// guarda el servidor (`FotosInicio.notaRecortada`).
    public func guardarNota(_ texto: String) async -> Salida {
        guard estado != nil else { return .error }
        guardarBorradorNota(FotosInicio.notaRecortada(texto))
        return await mandarNota() ?? .sinSenal
    }

    /// nil: se está mandando (otra pasada), o no hay nada que mandar.
    private func mandarNota() async -> Salida? {
        guard let n = notaPendiente, !mandandoNota else { return nil }
        mandandoNota = true
        defer { mandandoNota = false }
        switch await cliente.llamar("mypump_fotos_inicio_nota", ["p_token": .texto(token), "p_nota": .texto(n)]) {
        case .success(.null):
            tokenCaido = true
            return .tokenCaido   // queda guardada para el link nuevo
        case .success(let j):
            if j["ok"] == .bool(true) {
                let guardada = j["nota"]?.comoTexto ?? n
                // Si mientras tanto escribió otra, esa sigue pendiente.
                if notaPendiente == n { guardarBorradorNota(nil) }
                actualizarEstado { $0.nota = guardada }
                return .ok
            }
            guardarBorradorNota(nil)
            if j["error"]?.comoTexto == "no_habilitado" { apagar() }
            return .error
        case .failure(let f):
            if f.clase == .permanente { guardarBorradorNota(nil); return .error }
            return .sinSenal
        }
    }

    private func guardarBorradorNota(_ n: String?) {
        notaPendiente = n
        if let n { disco?.guardar(BorradorFotosInicio(nota: n), BorradorFotosInicio.archivo) } else { disco?.borrar(BorradorFotosInicio.archivo) }
    }

    // MARK: Cola

    enum Envio { case ok, perdida, descartar(FotosInicio.Subida), reintentar, red }

    /// Una pasada a la vez. Sin red corta y espera a que vuelva. 5xx o 429: espera y reintenta, y a la tercera seguida corta la
    /// pasada y vuelve a probar al minuto. Todo otro 4xx es definitivo. Al vaciarse la cola se refresca el estado y sale la nota
    /// que había quedado guardada.
    public func drenar() async {
        guard !drenando, estado != nil else { return }
        drenando = true
        defer { drenando = false }
        var refrescarAlFinal = false, subioAlguna = false
        var seguidas = 0
        pasada: while true {
            sacarReemplazadas()
            guard let item = cola.first(where: { !conError.contains($0.id) }) ?? cola.first else { break }
            subiendo = item.id
            let r = await subir(item)
            subiendo = nil
            // La borró mientras subía y no llegó a entrar: ya no se sube.
            if case .ok = r {} else if borrarAlSubir.remove(item.id) != nil {
                sacarDeLaCola(item.id)
                if case .red = r { break pasada }
                continue pasada
            }
            switch r {
            case .ok:
                await sacarSubida(item)
                subioAlguna = true
                seguidas = 0
                reintentosDeFondo = 0
            case .perdida:
                sacarDeLaCola(item.id)
            case .descartar(let s):
                // 403: el link ya no sirve o se cerró la sección. Lo demás tampoco va a entrar, y la foto NO se borra: si es
                // el link, sale con el nuevo (`CuentasDelTelefono.adoptarFotosInicio`).
                if s.refrescar { refrescarAlFinal = true; break pasada }
                if let a = s.aviso { aviso = a }
                sacarDeLaCola(item.id)
            case .reintentar:
                conError.insert(item.id)
                seguidas += 1
                if seguidas >= Self.maxIntentosSeguidos { programarReintento(); break pasada }
                await esperar(pow(2, Double(seguidas)))
            case .red:
                break pasada
            }
        }
        if refrescarAlFinal || (subioAlguna && cola.isEmpty) { await refrescar() }
        if estado != nil, await mandarNota() == .sinSenal { programarReintento() }
    }

    /// Una foto del cuerpo que tiene otra más nueva de su pose en la cola ya no se sube (quedó de cuando la nueva se encoló
    /// mientras esta subía): si se reintentara después, pisaría en el servidor a la que el alumno eligió.
    private func sacarReemplazadas() {
        var ultima: [String: String] = [:]
        for p in cola where p.pose != FotosInicio.motivacion { ultima[p.pose] = p.id }
        for p in cola where p.pose != FotosInicio.motivacion && ultima[p.pose] != p.id { sacarDeLaCola(p.id) }
    }

    /// Una pasada sin esperarla: cambiar de pantalla no corta la subida.
    public func drenarEnFondo() { Task { await drenar() } }

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

    private func subir(_ p: PendienteFotoInicio) async -> Envio {
        guard let datos = try? Data(contentsOf: archivo(p.id)) else { return .perdida }
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent("inicio/upload"), timeoutInterval: 90)
        pedido.httpMethod = "POST"
        pedido.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        pedido.setValue(token, forHTTPHeaderField: "x-inicio-token")
        pedido.setValue(p.id, forHTTPHeaderField: "x-inicio-foto")
        pedido.setValue(p.pose, forHTTPHeaderField: "x-inicio-pose")
        pedido.setValue(p.tomadaEn, forHTTPHeaderField: "x-inicio-tomada")
        if let b = p.brillo { pedido.setValue(Self.numero(b), forHTTPHeaderField: "x-inicio-brillo") }
        if let n = p.nitidez { pedido.setValue(Self.numero(n), forHTTPHeaderField: "x-inicio-nitidez") }
        pedido.httpBody = datos
        guard let (cuerpo, resp) = try? await cliente.transporte.enviar(pedido) else { return .red }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let j = try? JSONDecoder().decode(JSONValue.self, from: cuerpo)
        let s = FotosInicio.clasificarSubida(status: status, ok: j?["ok"] == .bool(true))
        switch s.accion {
        case .ok: return .ok
        case .descartar: return .descartar(s)
        case .reintentar: return .reintentar
        }
    }

    /// Subió: el estado ya la muestra (reemplaza la de esa pose) sin esperar al servidor.
    private func sacarSubida(_ item: PendienteFotoInicio) async {
        sacarDeLaCola(item.id)
        let nueva = FotoInicio(id: item.id, pose: item.pose, tomadaEn: item.tomadaEn)
        if borrarAlSubir.remove(item.id) != nil {
            // La borró mientras subía: ahora que está en el servidor se borra ahí.
            actualizarEstado { $0.fotos.append(nueva) }
            _ = await borrarMotivacion(id: item.id)
            return
        }
        actualizarEstado { e in
            if item.pose == FotosInicio.motivacion { e.fotos.removeAll { $0.id == item.id } } else { e.fotos.removeAll { $0.pose == item.pose } }
            e.fotos.append(nueva)
        }
        urlsVencen = nil
    }

    private func actualizarEstado(_ cambio: (inout EstadoFotosInicio) -> Void) {
        guard var e = estado else { return }
        cambio(&e)
        estado = e
        disco?.guardar(Self.aJSON(e), Self.archivoEstado)
    }

    // MARK: Miniaturas

    /// URLs firmadas por 1 h: se piden de nuevo a los 50 min, o si aparece una foto que no estaba.
    public func firmar(forzar: Bool = false) async {
        guard let e = estado, !e.fotos.isEmpty else { return }
        if !forzar, e.fotos.allSatisfy({ urls[$0.id] != nil }), let v = urlsVencen, v > ahora() { return }
        guard let r = await postVision("inicio/urls", ["token": .texto(token)]), r.json?["ok"] == .bool(true),
              case .lista(let filas)? = r.json?["fotos"] else { return }
        var mapa: [String: URL] = [:]
        for f in filas { if let i = f["id"]?.comoTexto, let u = f["url"]?.comoTexto.flatMap(URL.init(string:)) { mapa[i] = u } }
        urls = mapa
        urlsVencen = ahora().addingTimeInterval(50 * 60)
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

    public func archivo(_ id: String) -> URL {
        (disco?.url(PendienteFotoInicio.carpeta) ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("\(id).jpg")
    }

    private func guardarJPEG(_ jpeg: Data, id: String, en disco: Disco) -> Bool {
        var carpeta = disco.url(PendienteFotoInicio.carpeta)
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            var valores = URLResourceValues()
            valores.isExcludedFromBackup = true   // viven hasta que suben: no van a la copia de iCloud
            try? carpeta.setResourceValues(valores)
            try jpeg.write(to: carpeta.appendingPathComponent("\(id).jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }

    private func guardarCola() -> Bool {
        guard let disco else { return false }
        if cola.isEmpty { disco.borrar(PendienteFotoInicio.archivo); return true }
        return disco.guardar(cola, PendienteFotoInicio.archivo)
    }

    /// Las fotos (y la nota) que quedaron en la carpeta de otro link de la misma persona (`CuentasDelTelefono.adoptarFotosInicio`).
    func adoptar(_ otras: [PendienteFotoInicio], desde otra: Disco) -> Bool {
        guard let disco else { return false }
        var todas = true
        for p in otras where !cola.contains(where: { $0.id == p.id }) {
            guard let datos = try? Data(contentsOf: otra.url("\(PendienteFotoInicio.carpeta)/\(p.id).jpg")), guardarJPEG(datos, id: p.id, en: disco) else { todas = false; continue }
            cola.append(p)
        }
        if notaPendiente == nil, let n = otra.leer(BorradorFotosInicio.self, BorradorFotosInicio.archivo)?.nota { guardarBorradorNota(n) }
        return guardarCola() && todas
    }

    // MARK: Formatos

    /// ISO 8601 con la zona del teléfono, como lo pide `x-inicio-tomada`.
    static func iso(_ fecha: Date, zona: TimeZone = .current) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = zona
        return f.string(from: fecha)
    }

    static func numero(_ d: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), d) }

    /// El estado como lo devuelve el servidor, para guardarlo (el teléfono lo actualiza al subir sin esperar).
    static func aJSON(_ e: EstadoFotosInicio) -> JSONValue {
        .objeto([
            "habilitado": .bool(true), "completo": .bool(e.completo), "nota": .texto(e.nota), "max_motivacion": .numero(Double(e.maxMotivacion)),
            "fotos": .lista(e.fotos.map { f in
                var o: [String: JSONValue] = ["id": .texto(f.id), "pose": .texto(f.pose), "ancho": .numero(Double(f.ancho)), "alto": .numero(Double(f.alto))]
                if let t = f.tomadaEn { o["tomada_en"] = .texto(t) }
                return .objeto(o)
            }),
        ])
    }
}
