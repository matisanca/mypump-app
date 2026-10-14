import Foundation
import MyPumpModelos

public struct ConfigBackend: Sendable {
    public let supabase: URL
    public let anonKey: String
    public let vision: URL
    public let app: URL

    public init(supabase: URL, anonKey: String, vision: URL, app: URL) {
        self.supabase = supabase; self.anonKey = anonKey; self.vision = vision; self.app = app
    }
}

/// Un error de una llamada al backend, clasificado como `clasificarError` de la web (supabase-client.js:41-48).
/// La clase decide qué hace la cola: la red y lo transitorio NO gastan intentos; lo permanente sí.
public struct ErrorRPC: Error, Sendable, Equatable {
    public enum Clase: Sendable, Equatable {
        /// No hubo respuesta: sin señal, timeout, host, o un 200 que no es JSON (portal cautivo).
        case red
        /// El servidor respondió que está ocupado: 5xx, 429, 408.
        case transitorio
        /// El servidor dijo que no: 4xx con código de PostgREST (P0001, 22P02, PGRST202…).
        case permanente
    }

    public let clase: Clase
    public let status: Int
    public let codigo: String?
    public let mensaje: String

    public init(clase: Clase, status: Int, codigo: String? = nil, mensaje: String) {
        self.clase = clase; self.status = status; self.codigo = codigo; self.mensaje = mensaje
    }

    /// `mypump_get_historico_por_clave` no existe en la base: la única caída legítima al camino viejo.
    public var funcionInexistente: Bool { codigo == "PGRST202" }
}

/// Lo que manda los bytes. En la app es URLSession; en los tests, un doble que contesta lo que contestó la API real.
public protocol Transporte: Sendable {
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: Transporte {
    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) { try await data(for: pedido) }
}

/// Cliente propio y fino de PostgREST: `POST /rest/v1/rpc/<fn>` con la anon key, igual que la web. Devuelve el JSON
/// tal cual (un `null`, un `[]`, un `0` o un `false` son respuestas válidas: con un token revocado la base contesta
/// 200 vacío, no un error) o un `ErrorRPC` clasificado.
public final class ClienteRPC: Sendable {
    public let config: ConfigBackend
    private let transporte: any Transporte
    private let espera: TimeInterval

    public init(config: ConfigBackend = .produccion, transporte: any Transporte = URLSession.shared, espera: TimeInterval = 20) {
        self.config = config; self.transporte = transporte; self.espera = espera
    }

    public func llamar(_ funcion: String, _ parametros: [String: JSONValue]) async -> Result<JSONValue, ErrorRPC> {
        var pedido = URLRequest(url: config.supabase.appendingPathComponent("rest/v1/rpc/\(funcion)"), timeoutInterval: espera)
        pedido.httpMethod = "POST"
        pedido.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        pedido.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            pedido.httpBody = try JSONEncoder().encode(JSONValue.objeto(parametros))
        } catch {
            return .failure(ErrorRPC(clase: .permanente, status: 0, codigo: "ENCODE", mensaje: "\(error)"))
        }
        return await enviar(pedido)
    }

    /// Lectura directa de una tabla pública (el catálogo de ejercicios).
    public func tabla(_ nombre: String, columnas: String) async -> Result<JSONValue, ErrorRPC> {
        var c = URLComponents(url: config.supabase.appendingPathComponent("rest/v1/\(nombre)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "select", value: columnas)]
        var pedido = URLRequest(url: c.url!, timeoutInterval: espera)
        pedido.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        pedido.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        return await enviar(pedido)
    }

    func enviar(_ pedido: URLRequest) async -> Result<JSONValue, ErrorRPC> {
        let datos: Data, respuesta: URLResponse
        do {
            (datos, respuesta) = try await transporte.enviar(pedido)
        } catch {
            return .failure(ErrorRPC(clase: .red, status: 0, mensaje: "\(error)"))
        }
        let status = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
            if datos.isEmpty { return .success(.null) }
            guard let json = try? JSONDecoder().decode(JSONValue.self, from: datos) else {
                // Un 200 con HTML es un portal cautivo (el wifi del gym): para la cola es falta de red.
                return .failure(ErrorRPC(clase: .red, status: status, mensaje: "respuesta que no es JSON"))
            }
            return .success(json)
        }
        let cuerpo = try? JSONDecoder().decode(JSONValue.self, from: datos)
        let codigo = cuerpo?["code"]?.comoTexto
        let mensaje = cuerpo?["message"]?.comoTexto ?? String(decoding: datos.prefix(300), as: UTF8.self)
        let clase: ErrorRPC.Clase = (status == 429 || status == 408 || status >= 500) ? .transitorio : .permanente
        return .failure(ErrorRPC(clase: clase, status: status, codigo: codigo, mensaje: mensaje))
    }
}

extension ClienteRPC {
    /// Decodifica una respuesta de filas. Una forma inesperada es un error permanente (no se reintenta a ciegas).
    public func filas<T: Decodable>(_ funcion: String, _ parametros: [String: JSONValue], como: T.Type = T.self) async -> Result<[T], ErrorRPC> {
        switch await llamar(funcion, parametros) {
        case .failure(let e): return .failure(e)
        case .success(.null): return .success([])
        case .success(let json):
            do { return .success(try JSONDecoder().decode([T].self, from: JSONEncoder().encode(json))) }
            catch { return .failure(ErrorRPC(clase: .permanente, status: 200, codigo: "DECODE", mensaje: "\(funcion): \(error)")) }
        }
    }
}
