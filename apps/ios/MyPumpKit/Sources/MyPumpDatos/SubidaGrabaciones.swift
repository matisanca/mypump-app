import Foundation
import CryptoKit
import MyPumpModelos

/// Lo que dice el servidor sobre subir las grabaciones del contador de reps. La cuenta `automatica` se habilita por
/// cuenta en la base; los demás alumnos, solo con su consentimiento (`acepta`). Sin la RPC aplicada no hay estado (nil):
/// la app no sube y no muestra nada nuevo.
public struct EstadoSubidaReps: Equatable, Sendable {
    public var automatica: Bool
    /// nil = nunca se le preguntó.
    public var acepta: Bool?
    /// Puede tomar los archivos viejos, sin marca de cuenta (el servidor lo pone a mano para una cuenta que grabó sola).
    public var adoptarSinMarca = false
    public var puedeSubir: Bool { automatica || acepta == true }

    public init(automatica: Bool = false, acepta: Bool? = nil, adoptarSinMarca: Bool = false) {
        self.automatica = automatica; self.acepta = acepta; self.adoptarSinMarca = adoptarSinMarca
    }

    /// nil si la respuesta no es la esperada (token caído: la base contesta null).
    public init?(_ j: JSONValue) {
        guard case .bool(let a)? = j["automatica"] else { return nil }
        automatica = a
        if case .bool(let b)? = j["acepta"] { acepta = b }
        if case .bool(let b)? = j["adoptar_sin_marca"] { adoptarSinMarca = b }
    }
}

public enum ResultadoSubida: Equatable, Sendable {
    /// Quedó en el servidor (recién subida o ya estaba).
    case hecho
    /// El servidor dijo que esta cuenta no está habilitada: no se insiste.
    case noHabilitada
    /// El servidor rechazó ese archivo (formato o tamaño): se saltea y los demás siguen.
    case rechazada
    /// Sin red, servicio caído o tope del día: el archivo sigue guardado y se reintenta la próxima vez.
    case reintentar
}

extension ClienteRPC {
    /// Solo con el token del alumno: el servidor deduce la cuenta. nil = sin la RPC, sin red o token caído.
    public func estadoSubidaReps(token: String) async -> EstadoSubidaReps? {
        guard case .success(let j) = await llamar("mypump_reps_estado", ["p_token": .texto(token)]) else { return nil }
        return EstadoSubidaReps(j)
    }

    private func postVision(_ ruta: String, cuerpo: [String: JSONValue], espera: TimeInterval) async -> (status: Int, json: JSONValue?)? {
        var pedido = URLRequest(url: config.vision.appendingPathComponent(ruta), timeoutInterval: espera)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.httpBody = try? JSONEncoder().encode(JSONValue.objeto(cuerpo))
        guard let (datos, respuesta) = try? await transporte.enviar(pedido) else { return nil }
        return ((respuesta as? HTTPURLResponse)?.statusCode ?? 0, try? JSONDecoder().decode(JSONValue.self, from: datos))
    }

    /// `POST <vision>/reps/subir`: el archivo crudo y el token en una cabecera, para que el servidor valide antes de leerlo.
    /// Idempotente del lado del servidor (cuenta, sesión y hash).
    public func subirGrabacion(token: String, sesion: String, sha256: String, datos: Data) async -> ResultadoSubida {
        var pedido = URLRequest(url: config.vision.appendingPathComponent("reps/subir"), timeoutInterval: 120)
        pedido.httpMethod = "POST"
        pedido.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        pedido.setValue(token, forHTTPHeaderField: "x-reps-token")
        pedido.setValue(sesion, forHTTPHeaderField: "x-reps-sesion")
        pedido.setValue(sha256, forHTTPHeaderField: "x-reps-sha256")
        pedido.setValue(String(datos.count), forHTTPHeaderField: "Content-Length")
        pedido.httpBody = datos
        guard let (cuerpo, respuesta) = try? await transporte.enviar(pedido) else { return .reintentar }
        let status = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status), (try? JSONDecoder().decode(JSONValue.self, from: cuerpo))?["ok"] == .bool(true) { return .hecho }
        if status == 403 { return .noHabilitada }
        return status == 400 || status == 413 ? .rechazada : .reintentar
    }

    /// `POST <vision>/reps/consentimiento`. Con `acepta: false` el servidor borra además lo ya subido. true = guardado.
    public func guardarConsentimientoReps(token: String, acepta: Bool, plataforma: String, app: String?) async -> Bool {
        var cuerpo: [String: JSONValue] = ["token": .texto(token), "acepta": .bool(acepta), "plataforma": .texto(plataforma)]
        if let app { cuerpo["app"] = .texto(app) }
        guard let r = await postVision("reps/consentimiento", cuerpo: cuerpo, espera: 30) else { return false }
        return (200..<300).contains(r.status) && r.json?["ok"] == .bool(true)
    }
}

/// Sube las grabaciones que falten. Corre fuera del hilo principal, de a una por vez, y nunca sin que el servidor la
/// habilite. Lo que no se pudo subir sigue en el iPhone (hasta el tope de la carpeta) y se reintenta la próxima vez.
public actor SubidaGrabaciones {
    /// Las ya subidas («sesión#hash»): si la sesión creció, el hash cambia y se vuelve a mandar.
    static let claveSubidas = "mypump-reps-subidas"
    static let topeRecuerdos = 1_000

    private let cliente: ClienteRPC
    private let defaults: UserDefaults
    private var corriendo = false
    /// Sube al revocar: lo que viaja en ese momento no se recuerda como subido.
    private var generacion = 0
    /// El archivo más grande que acepta el servidor (20 MB).
    public static let topeBytes = 20 * 1_024 * 1_024

    public init(cliente: ClienteRPC, defaults: UserDefaults = .standard) {
        self.cliente = cliente
        self.defaults = defaults
    }

    public static func sha256(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// El link caído al que todavía se le debe una revocación. nil si no hay, o si es el activo y anda: de ese se ocupa la vuelta normal.
    public static func linkCaidoARevocar(caido: String?, activo: String?, activoListo: Bool, pendiente: (String) -> Bool) -> String? {
        guard let caido, !caido.isEmpty, !(caido == activo && activoListo), pendiente(caido) else { return nil }
        return caido
    }

    /// Los archivos de esta cuenta. `marcas` dice de quién es cada archivo recibido. Los viejos, sin marca, solo los toma
    /// la cuenta que el servidor habilitó para eso, y solo si es la única con el modo prendido en este iPhone (`prendidas`).
    public static func deLaCuenta(_ urls: [URL], cuenta: String, marcas: [String: String], prendidas: [String], estado: EstadoSubidaReps) -> [URL] {
        urls.filter { u in
            if let c = marcas[u.lastPathComponent] { return c == cuenta }
            return estado.automatica && estado.adoptarSinMarca && prendidas == [cuenta]
        }
    }

    /// «calibracion-2026-11-07-s6-c7ae9e.mpcal» → «2026-11-07-s6-c7ae9e». nil si el nombre no es de una sesión.
    public static func sesion(deArchivo u: URL) -> String? {
        let base = u.deletingPathExtension().lastPathComponent
        guard base.hasPrefix("calibracion-") else { return nil }
        let s = String(base.dropFirst("calibracion-".count))
        guard !s.isEmpty, s.count <= 80, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return s
    }

    /// Lo subido se olvida al revocar: si vuelve a aceptar, el servidor ya no lo tiene y hay que mandarlo de nuevo.
    public func olvidarSubidas() {
        generacion += 1
        defaults.removeObject(forKey: Self.claveSubidas)
    }

    /// Cuántas subió. `alHabilitar` se llama con el estado cuando la cuenta puede subir (para prender la grabación).
    /// `archivos` elige según el estado: nunca archivos de otra cuenta del mismo iPhone.
    @discardableResult
    public func subirPendientes(token: String, archivos: @Sendable (EstadoSubidaReps) -> [URL],
                                alHabilitar: (@Sendable (EstadoSubidaReps) async -> Void)? = nil) async -> Int {
        guard !corriendo else { return 0 }
        corriendo = true
        defer { corriendo = false }
        guard let estado = await cliente.estadoSubidaReps(token: token) else { return 0 }
        guard estado.puedeSubir else {
            if estado.acepta == false { olvidarSubidas() }   // revocó (quizá desde otro iPhone): si vuelve, se manda de nuevo
            return 0
        }
        await alHabilitar?(estado)
        let vuelta = generacion
        var cuenta = 0
        for u in archivos(estado) {
            guard vuelta == generacion else { return cuenta }
            guard let sesion = Self.sesion(deArchivo: u), let datos = try? Data(contentsOf: u), !datos.isEmpty, datos.count <= Self.topeBytes else { continue }
            let hash = Self.sha256(datos)
            let clave = "\(sesion)#\(hash)"
            guard !(defaults.stringArray(forKey: Self.claveSubidas) ?? []).contains(clave) else { continue }
            switch await cliente.subirGrabacion(token: token, sesion: sesion, sha256: hash, datos: datos) {
            case .hecho:
                guard vuelta == generacion else { return cuenta }
                let subidas = (defaults.stringArray(forKey: Self.claveSubidas) ?? []) + [clave]
                defaults.set(Array(subidas.suffix(Self.topeRecuerdos)), forKey: Self.claveSubidas)
                cuenta += 1
            case .rechazada:
                continue
            case .noHabilitada, .reintentar:
                return cuenta
            }
        }
        return cuenta
    }
}
