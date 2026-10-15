import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Una foto que espera subir. Mismo formato que la cola de la web (`mypump_fotoq_<TOKEN>`): así la migración del
/// almacenamiento viejo la deja tal cual en `fotos-pendientes.json`.
public struct FotoPendiente: Codable, Equatable, Sendable {
    public var pose: String
    public var fecha: String
    /// `data:image/jpeg;base64,…` (900 px, calidad 0,7, sin EXIF).
    public var dataUrl: String
    /// Solo cuentan los errores del servidor; con 8 se descarta.
    public var intentos: Int

    public static let archivo = "fotos-pendientes.json"

    public init(pose: String, fecha: String, dataUrl: String, intentos: Int = 0) {
        self.pose = pose; self.fecha = fecha; self.dataUrl = dataUrl; self.intentos = intentos
    }
}

/// Fotos de progreso: subida por pose al servicio de la Mini (bucket privado), con una cola propia en disco que
/// sobrevive a cerrar la app y a quedarse sin señal, URLs firmadas que se cachean 50 minutos, y la lista de lo subido.
@MainActor @Observable
public final class ModeloFotos {
    public enum Resultado: Equatable, Sendable {
        case guardada                 // "Listo, guardada ✓"
        case sinConexion              // "Sin conexión: queda guardada y se sube sola."
        case rechazada(String)        // "No se pudo guardar: <motivo>" (no va a entrar nunca)
        case colaLlena                // "Hay fotos esperando subir. Probá cuando tengas señal."
        case muyPesada                // "Esa foto es demasiado pesada. Probá sacarla con la cámara."
        case noSeGuardo               // no se pudo ni guardar en el teléfono
        case tokenCaido               // el link ya no sirve: queda guardada para cuando entre con el nuevo

        public var texto: String {
            switch self {
            case .guardada: "Listo, guardada ✓"
            case .sinConexion: "Sin conexión: queda guardada y se sube sola."
            case .rechazada(let m): "No se pudo guardar: \(m)"
            case .colaLlena: "Hay fotos esperando subir. Probá cuando tengas señal."
            case .muyPesada: "Esa foto es demasiado pesada. Probá sacarla con la cámara."
            case .noSeGuardo: "No se pudo guardar. Probá de nuevo con señal."
            case .tokenCaido: "Quedó guardada en el teléfono. Se sube cuando vuelvas a entrar con tu link."
            }
        }
    }

    public private(set) var fotos: [FotoProgreso] = []
    /// "<lunes>|<pose>" → la foto que espera subir.
    public private(set) var pendientes: [String: FotoPendiente] = [:]
    /// "<lunes>|<pose>" → URL firmada (1 h).
    public private(set) var urls: [String: URL] = [:]
    public private(set) var subiendo: Set<String> = []

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored private var drenando = false
    @ObservationIgnored private var urlsVencen: Date?

    static let archivo = FotoPendiente.archivo

    public init(cliente: ClienteRPC, token: String, disco: Disco?) {
        self.cliente = cliente; self.token = token; self.disco = disco
        pendientes = disco?.leer([String: FotoPendiente].self, Self.archivo) ?? [:]
    }

    /// Las fotos que quedaron en la carpeta de otro link de la misma persona. Una de esta cuenta para la misma pose y
    /// semana es más nueva y queda. Devuelve si quedaron guardadas en el disco de esta cuenta.
    func adoptar(_ otras: [String: FotoPendiente]) -> Bool {
        for (clave, f) in otras where pendientes[clave] == nil { pendientes[clave] = f }
        return guardarCola()
    }

    public var semanaActual: String { FotosProgreso.lunes(FechaLocal.hoy()) }

    public var posesDeLaSemana: Set<String> {
        FotosProgreso.posesDeLaSemana(fotos, pendientes: pendientes.values.map { ($0.pose, $0.fecha) }, semana: semanaActual)
    }

    /// `loadFotos`: lo que ya está subido. Sin red queda lo de antes.
    public func cargar() async {
        if case .success(let filas) = await cliente.filas("mypump_get_fotos_progreso", ["p_token": .texto(token), "p_desde": .null],
                                                          como: FotoProgreso.self) {
            fotos = filas
        }
    }

    /// `_tomarFoto`: el JPEG ya reducido (900 px, 0,7, sin metadatos) se encola y se sube enseguida.
    public func subir(pose: String, jpeg: Data) async -> Resultado {
        let dataUrl = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        let fecha = FechaLocal.hoy()
        let clave = "\(FotosProgreso.lunes(fecha))|\(pose)"
        if pendientes.count >= FotosProgreso.maxPendientes && pendientes[clave] == nil { return .colaLlena }
        if dataUrl.count > FotosProgreso.maxCaracteres { return .muyPesada }
        pendientes[clave] = FotoPendiente(pose: pose, fecha: fecha, dataUrl: dataUrl)
        let guardo = guardarCola()
        subiendo.insert(clave)
        defer { subiendo.remove(clave) }
        switch await enviar(pendientes[clave]!) {
        case .ok:
            pendientes[clave] = nil
            _ = guardarCola()
            await alSubir()
            return .guardada
        case .fatal(let motivo):
            pendientes[clave] = nil
            _ = guardarCola()
            return .rechazada(motivo)
        case .reintentar, .red:
            return guardo ? .sinConexion : .noSeGuardo
        case .tokenCaido:
            return guardo ? .tokenCaido : .noSeGuardo
        }
    }

    /// `flushFotos`: una pasada a la vez. Un rechazo (4xx salvo 429) se descarta para no trabar la cola; la red no
    /// gasta intentos; 8 errores del servidor y se deja.
    public func drenar() async {
        guard !drenando, !pendientes.isEmpty else { return }
        drenando = true
        defer { drenando = false }
        var subioAlgo = false
        for clave in pendientes.keys.sorted() {
            guard var item = pendientes[clave] else { continue }
            subiendo.insert(clave)
            let r = await enviar(item)
            subiendo.remove(clave)
            switch r {
            case .ok:
                pendientes[clave] = nil
                _ = guardarCola()
                subioAlgo = true
                continue
            case .fatal:
                pendientes[clave] = nil
            case .red, .tokenCaido:
                break
            case .reintentar:
                item.intentos += 1
                pendientes[clave] = item.intentos >= FotosProgreso.maxIntentos ? nil : item
            }
            _ = guardarCola()
            if case .red = r { break }
            if case .tokenCaido = r { break }        // con este token no entra ninguna: las adopta la cuenta del link nuevo
            if pendientes[clave] != nil { break }   // el servidor está mal: se reintenta después
        }
        if subioAlgo { await alSubir() }
    }

    /// Con una foto guardada: la lista de lo subido y las URLs firmadas de nuevo. Al REEMPLAZAR la foto de una pose de la
    /// semana no cambia cuántas hay y la pantalla no volvía a firmar: la miniatura seguía con la vieja (lo encontró el
    /// agente de Revisión de Android contra la base real, 15-oct). Cada firma es otra URL, así que tampoco sale la vieja
    /// del caché de imágenes.
    private func alSubir() async {
        urlsVencen = nil   // si esta firma no sale, la próxima de la pantalla no se saltea
        async let lista: Void = cargar()
        async let firmas = firmar(forzar: true)
        _ = await (lista, firmas)
    }

    /// `cargarFotosFirmadas`: las URLs (duran 1 h) se piden una vez y se guardan 50 minutos.
    @discardableResult
    public func firmar(forzar: Bool = false) async -> Bool {
        if !forzar, let v = urlsVencen, v > Date() { return true }
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent("progreso/urls"), timeoutInterval: 30)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.httpBody = try? JSONEncoder().encode(JSONValue.objeto(["token": .texto(token)]))
        guard let (datos, resp) = try? await cliente.transporte.enviar(pedido),
              ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 300,
              let j = try? JSONDecoder().decode(JSONValue.self, from: datos), j["ok"] == .bool(true),
              case .lista(let filas)? = j["fotos"] else { return !urls.isEmpty }
        var mapa: [String: URL] = [:]
        for f in filas {
            if let s = f["semana_lunes"]?.comoTexto, let p = f["pose"]?.comoTexto, let u = f["url"]?.comoTexto.flatMap(URL.init(string:)) {
                mapa["\(s)|\(p)"] = u
            }
        }
        guard !mapa.isEmpty else { return !urls.isEmpty }
        urls = mapa
        urlsVencen = Date().addingTimeInterval(50 * 60)
        return true
    }

    // MARK: - Envío

    enum Envio { case ok, fatal(String), reintentar, red, tokenCaido }

    /// `_subirFoto`: 4xx salvo 429 = no va a entrar nunca; 5xx/429 = el servidor, se reintenta; sin respuesta = red.
    /// Desvío a propósito: un 401/403 por el token NO borra la foto (la web la perdía). Queda guardada, sin gastar intento,
    /// y la adopta la cuenta del link nuevo de la misma persona (`CuentasDelTelefono.adoptarFotos`; revisión del 15-oct).
    func enviar(_ f: FotoPendiente) async -> Envio {
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent("progreso/upload"), timeoutInterval: 90)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.httpBody = try? JSONEncoder().encode(JSONValue.objeto([
            "token": .texto(token), "pose": .texto(f.pose), "fecha": .texto(f.fecha), "imagen_base64": .texto(f.dataUrl),
        ]))
        guard let (datos, resp) = try? await cliente.transporte.enviar(pedido) else { return .red }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let j = try? JSONDecoder().decode(JSONValue.self, from: datos)
        if (200..<300).contains(status), j?["ok"] == .bool(true) { return .ok }
        if status == 401 || status == 403, (j?["error"]?.comoTexto ?? "").lowercased().contains("token") { return .tokenCaido }
        if status >= 400 && status < 500 && status != 429 { return .fatal(j?["error"]?.comoTexto ?? "HTTP \(status)") }
        return .reintentar
    }

    private func guardarCola() -> Bool {
        guard let disco else { return false }
        if pendientes.isEmpty { disco.borrar(Self.archivo); return true }
        disco.guardar(pendientes, Self.archivo)
        return disco.leer([String: FotoPendiente].self, Self.archivo) != nil
    }
}
