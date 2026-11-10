import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// El video que espera subir. Uno por vez: el contrato no deja abrir otro mientras haya uno en curso.
public struct PendienteTecnica: Codable, Equatable, Sendable {
    public let id: String
    /// El envío del servidor, una vez abierto. Con esto un reintento no duplica.
    public var envioId: String?
    public let slug: String
    public let nombre: String
    public let nota: String
    public let consentimiento: String
    public static let carpeta = "tecnica-videos"
}

/// Lo que vive en disco: el aviso aceptado y el video en camino, juntos en un archivo que se escribe de una vez.
struct ColaTecnica: Codable, Equatable {
    var avisoVersion: String?
    var pendiente: PendienteTecnica?
    static let archivo = "tecnica-cola.json"
}

/// Técnica por video. Mismo criterio de cola que `ModeloGimnasio`: en disco, sobrevive a cerrar la app y a quedarse sin señal, un
/// 5xx o 429 no gasta el video y lo demás de 4xx es definitivo. El video se sube desde su archivo, nunca entero en memoria. Con la
/// palanca `tecnica_video` apagada `ModeloApp` no llama a nada de esto: `estado` queda en nil y no se ve ni se pide nada.
@MainActor @Observable
public final class ModeloTecnica {
    public enum Resultado: Equatable, Sendable { case ok, sinSenal, ocupado, error }
    public enum Encolar: Equatable, Sendable { case guardado, ocupado, noSeGuardo }
    public enum Aviso: Equatable, Sendable { case rechazo(Tecnica.Rechazo), enCurso, topeSemanal, error }

    /// nil: apagado, sin el servidor nuevo, o sin red y sin nada guardado. No se muestra nada.
    public private(set) var estado: EstadoTecnica?
    /// Hay un pedido en vuelo con este video (abrir el envío o subirlo).
    public private(set) var subiendo = false
    public private(set) var aviso: Aviso?
    private var local = ColaTecnica()

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored private let esperar: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private var drenando = false
    @ObservationIgnored private var reintentoProgramado = false
    @ObservationIgnored private var reintentosDeFondo = 0

    static let archivoEstado = "tecnica-estado.json"
    static let maxIntentosSeguidos = 3
    static let maxReintentosDeFondo = 5
    /// El servidor corta el cuerpo a los 240 s: un poco más y el corte lo dice él.
    static let esperaSubida: TimeInterval = 300

    public init(cliente: ClienteRPC, token: String, disco: Disco?,
                esperar: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.cliente = cliente; self.token = token; self.disco = disco; self.esperar = esperar
        local = disco?.leer(ColaTecnica.self, ColaTecnica.archivo) ?? ColaTecnica()
        barrerHuerfanos()
    }

    /// Un cierre entre el archivo y el índice deja un video que nadie sube ni borra.
    private func barrerHuerfanos() {
        guard let disco else { return }
        let carpeta = disco.url(PendienteTecnica.carpeta)
        let vivo = local.pendiente.map { "\($0.id).mp4" }
        for f in (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? [] where f != vivo {
            try? FileManager.default.removeItem(at: carpeta.appendingPathComponent(f))
        }
    }

    // MARK: Lo que lee la pantalla

    public var pendiente: PendienteTecnica? { local.pendiente }
    public var habilitado: Bool { estado != nil }
    public var envios: [EnvioTecnica] { estado?.visibles ?? [] }
    public var topes: TopesTecnica { estado?.topes ?? TopesTecnica() }
    /// El aviso de terceros, una sola vez: si el servidor no lo tiene aceptado y en este teléfono no se aceptó esta versión.
    public var necesitaAviso: Bool {
        guard let e = estado else { return false }
        // El texto del aviso es el de esta versión de la app: lo que se registra es esa, no la que dicte el servidor.
        return !(e.consentimientoAceptado && e.consentimientoVersion == Tecnica.consentimientoVigente) && local.avisoVersion != Tecnica.consentimientoVigente
    }
    /// Se puede mandar otro: nada en camino y nada esperando la devolución.
    public var puedeMandar: Bool { estado != nil && local.pendiente == nil && estado?.enRevision == nil }

    // MARK: Servidor

    public func refrescar() async {
        switch await cliente.llamar("mypump_tecnica_get", ["p_token": .texto(token)]) {
        case .success(.null):
            estado = nil
        case .success(let j):
            guard let e = EstadoTecnica(j) else { apagar(); disco?.borrar(Self.archivoEstado); return }
            estado = e
            disco?.guardar(j, Self.archivoEstado)
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            apagar()
            disco?.borrar(Self.archivoEstado)
        case .failure:
            // Sin red, lo último que se supo: la devolución se puede releer en el gimnasio y la cola sigue viva.
            if estado == nil, let j = disco?.leer(JSONValue.self, Self.archivoEstado), let e = EstadoTecnica(j) { estado = e }
        }
    }

    public func apagar() { estado = nil }

    public func aceptarAviso() {
        guard let e = estado else { return }
        local.avisoVersion = Tecnica.consentimientoVigente
        guardar()
    }

    public func limpiarAviso() { aviso = nil }

    // MARK: Cola

    /// Mueve el video ya preparado a la cola. Después hay que drenar.
    public func encolar(archivo: URL, slug: String, nombre: String, nota: String) -> Encolar {
        guard let e = estado, local.pendiente == nil, estado?.enRevision == nil, !necesitaAviso else { return .ocupado }
        guard let disco else { return .noSeGuardo }
        let id = UUID().uuidString.lowercased()
        var carpeta = disco.url(PendienteTecnica.carpeta)
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            var valores = URLResourceValues()
            valores.isExcludedFromBackup = true   // vive hasta que sube: no va a la copia de iCloud
            try? carpeta.setResourceValues(valores)
            try FileManager.default.moveItem(at: archivo, to: carpeta.appendingPathComponent("\(id).mp4"))
        } catch { return .noSeGuardo }
        local.pendiente = PendienteTecnica(id: id, envioId: nil, slug: String(slug.prefix(Tecnica.maxNombre)), nombre: String(nombre.prefix(Tecnica.maxNombre)),
                                           nota: Tecnica.nota(nota), consentimiento: Tecnica.consentimientoVigente)
        guard guardar() else {
            local.pendiente = nil
            disco.borrar("\(PendienteTecnica.carpeta)/\(id).mp4")
            return .noSeGuardo
        }
        aviso = nil
        return .guardado
    }

    public func drenarEnFondo() { Task { await drenar() } }

    private enum Paso { case seguir, fin, reintentar, red }

    /// Una pasada a la vez. Red: corta y queda para después. 5xx o 429: espera y reintenta, y a la tercera seguida deja de insistir
    /// por un rato. Un rechazo definitivo se avisa y saca el video.
    public func drenar() async {
        guard !drenando, estado != nil else { return }
        drenando = true
        defer { drenando = false }
        var seguidas = 0
        pasada: while let p = local.pendiente, estado != nil {
            subiendo = true
            let r: Paso
            if p.envioId == nil {
                r = await abrir(p)
            } else {
                r = await subir(p)
            }
            subiendo = false
            switch r {
            case .seguir: seguidas = 0
            case .fin: break pasada
            case .red: programarReintento(); break pasada
            case .reintentar:
                seguidas += 1
                if seguidas >= Self.maxIntentosSeguidos { programarReintento(); break pasada }
                await esperar(pow(2, Double(seguidas)))
            }
        }
    }

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

    /// `nuevo`: si ya había un borrador devuelve ese, así que repetirlo después de un corte no duplica.
    private func abrir(_ p: PendienteTecnica) async -> Paso {
        let r = await cliente.llamar("mypump_tecnica_nuevo", [
            "p_token": .texto(token), "p_ejercicio_slug": .texto(p.slug), "p_ejercicio_nombre": .texto(p.nombre),
            "p_nota": .texto(p.nota), "p_consentimiento": .texto(p.consentimiento),
        ])
        switch r {
        case .success(.null):
            return .fin   // token caído: queda guardado para el link nuevo
        case .success(let j):
            if j["ok"] == .bool(true), let id = j["id"]?.comoTexto, !id.isEmpty {
                local.pendiente?.envioId = id
                guardar()
                return .seguir
            }
            switch j["error"]?.comoTexto {
            case "reintentar": return .reintentar
            case "no_habilitado": apagar(); return .fin
            case "en_curso": await soltar(p, aviso: .enCurso); return .fin
            case "tope_semanal": await soltar(p, aviso: .topeSemanal); return .fin
            case "consentimiento":
                local.avisoVersion = nil
                await soltar(p, aviso: .error)
                return .fin
            default: await soltar(p, aviso: .error); return .fin
            }
        case .failure(let e):
            if e.funcionInexistente { apagar(); return .fin }
            if e.clase == .permanente { await soltar(p, aviso: .error); return .fin }
            return e.clase == .red ? .red : .reintentar
        }
    }

    private func subir(_ p: PendienteTecnica) async -> Paso {
        let archivo = url(p.id)
        guard let id = p.envioId, let bytes = (try? FileManager.default.attributesOfItem(atPath: archivo.path))?[.size] as? NSNumber, bytes.int64Value > 0 else {
            await soltar(p, aviso: .error)
            return .fin
        }
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent("tecnica/upload"), timeoutInterval: Self.esperaSubida)
        pedido.httpMethod = "POST"
        pedido.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        pedido.setValue(token, forHTTPHeaderField: "x-tecnica-token")
        pedido.setValue(id, forHTTPHeaderField: "x-tecnica-id")
        pedido.setValue(String(bytes.int64Value), forHTTPHeaderField: "Content-Length")
        let fondo = pedirTiempoDeFondo()
        defer { soltarTiempoDeFondo(fondo) }
        guard let (cuerpo, resp) = try? await cliente.transporte.subir(pedido, archivo: archivo) else { return .red }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let j = try? JSONDecoder().decode(JSONValue.self, from: cuerpo)
        let s = Tecnica.clasificarSubida(status: status, ok: j?["ok"] == .bool(true), error: j?["error"]?.comoTexto)
        switch s.accion {
        case .ok:
            quitarLocal(p)
            reintentosDeFondo = 0
            marcarEnviado(id: id, p)
            await refrescar()
            return .fin
        case .reintentar:
            return .reintentar
        case .guardar:
            return .fin
        case .descartar:
            await soltar(p, aviso: .rechazo(s.rechazo ?? .otro))
            return .fin
        }
    }

    /// Hasta que llegue el `get`, para que la lista ya lo muestre recibido.
    private func marcarEnviado(id: String, _ p: PendienteTecnica) {
        guard var e = estado else { return }
        if let i = e.envios.firstIndex(where: { $0.id == id }) { e.envios[i].estado = .enviado; e.envios[i].tieneVideo = true }
        else { e.envios.insert(EnvioTecnica(id: id, estado: .enviado, slug: p.slug, nombre: p.nombre, nota: p.nota.isEmpty ? nil : p.nota, tieneVideo: true), at: 0) }
        estado = e
    }

    private func quitarLocal(_ p: PendienteTecnica) {
        local.pendiente = nil
        guardar()
        disco?.borrar("\(PendienteTecnica.carpeta)/\(p.id).mp4")
    }

    /// Definitivo: se avisa, se saca el video y se cierra el borrador del servidor si llegó a abrirse.
    private func soltar(_ p: PendienteTecnica, aviso a: Aviso) async {
        quitarLocal(p)
        aviso = a
        if let id = p.envioId { _ = await cliente.llamar("mypump_tecnica_cancelar", ["p_token": .texto(token), "p_id": .texto(id)]) }
        await refrescar()
    }

    /// El alumno se arrepiente antes de que suba. Mientras hay un pedido en vuelo no se puede.
    @discardableResult
    public func cancelarPendiente() async -> Bool {
        guard !subiendo, let p = local.pendiente else { return false }
        quitarLocal(p)
        aviso = nil
        if let id = p.envioId { _ = await cliente.llamar("mypump_tecnica_cancelar", ["p_token": .texto(token), "p_id": .texto(id)]) }
        return true
    }

    // MARK: El video ya subido

    /// La URL firmada de su propio video. nil: no se pudo.
    public func urlVideo(id: String) async -> URL? {
        guard let r = await postVision("tecnica/url", ["token": .texto(token), "id": .texto(id)]), r.json?["ok"] == .bool(true) else { return nil }
        return r.json?["url"]?.comoTexto.flatMap(URL.init(string:))
    }

    public func sacarVideo(id: String) async -> Resultado {
        guard let r = await postVision("tecnica/borrar", ["token": .texto(token), "id": .texto(id)]) else { return .sinSenal }
        if r.status == 409 { return .ocupado }
        guard (200..<300).contains(r.status), r.json?["ok"] == .bool(true) else { return .error }
        if var e = estado, let i = e.envios.firstIndex(where: { $0.id == id }) { e.envios[i].tieneVideo = false; estado = e }
        await refrescar()
        return .ok
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

    func url(_ id: String) -> URL {
        (disco?.url(PendienteTecnica.carpeta) ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("\(id).mp4")
    }

    @discardableResult private func guardar() -> Bool {
        guard let disco else { return false }
        return disco.guardar(local, ColaTecnica.archivo)
    }

    /// El video que quedó en la carpeta de otro link de la misma persona (`CuentasDelTelefono.adoptarTecnica`). El envío sigue siendo suyo.
    func adoptar(_ otra: PendienteTecnica, desde disco2: Disco) -> Bool {
        guard let disco, local.pendiente == nil else { return false }
        var carpeta = disco.url(PendienteTecnica.carpeta)
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            var valores = URLResourceValues()
            valores.isExcludedFromBackup = true
            try? carpeta.setResourceValues(valores)
            try FileManager.default.moveItem(at: disco2.url("\(PendienteTecnica.carpeta)/\(otra.id).mp4"), to: carpeta.appendingPathComponent("\(otra.id).mp4"))
        } catch { return false }
        local.pendiente = otra
        return guardar()
    }

    // MARK: Tiempo de fondo

    #if canImport(UIKit) && !os(watchOS)
    /// Lo que el sistema preste si el alumno guarda el teléfono justo después de mandar; si no alcanza, sigue la cola.
    private func pedirTiempoDeFondo() -> UIBackgroundTaskIdentifier {
        // Sin cerrar la tarea cuando vence, el sistema mata la app. La subida sigue sola o se reintenta al volver.
        nonisolated(unsafe) var t = UIBackgroundTaskIdentifier.invalid
        t = UIApplication.shared.beginBackgroundTask(withName: "tecnica-subida") {
            UIApplication.shared.endBackgroundTask(t)
            t = .invalid
        }
        return t
    }
    private func soltarTiempoDeFondo(_ t: UIBackgroundTaskIdentifier) { if t != .invalid { UIApplication.shared.endBackgroundTask(t) } }
    #else
    private func pedirTiempoDeFondo() -> Int { 0 }
    private func soltarTiempoDeFondo(_ t: Int) {}
    #endif
}
