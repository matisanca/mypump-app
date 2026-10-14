import Foundation
import MyPumpModelos

extension ClienteRPC {
    public enum TipoVision: String, Sendable { case etiqueta, plato }

    /// `visionDesdeFoto` de la web: `POST <vision>/vision` con `{token, tipo, imagen_base64}` (el token va en el body,
    /// no hay header de auth). Devuelve `data` o un error con el texto que mandó el servicio (`error`), para el aviso
    /// "No pudimos leer la foto (…)". La IA tarda ~30 s: se espera hasta 150.
    public func vision(token: String, tipo: TipoVision, jpeg: Data) async -> Result<JSONValue, ErrorRPC> {
        var pedido = URLRequest(url: config.vision.appendingPathComponent("vision"), timeoutInterval: 150)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let cuerpo: JSONValue = .objeto([
            "token": .texto(token), "tipo": .texto(tipo.rawValue),
            "imagen_base64": .texto("data:image/jpeg;base64," + jpeg.base64EncodedString()),
        ])
        pedido.httpBody = try? JSONEncoder().encode(cuerpo)
        let datos: Data, respuesta: URLResponse
        do {
            (datos, respuesta) = try await transporte.enviar(pedido)
        } catch {
            return .failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin conexión"))
        }
        let status = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        let j = try? JSONDecoder().decode(JSONValue.self, from: datos)
        if (200..<300).contains(status), j?["ok"] == .bool(true), let data = j?["data"] {
            return .success(data)
        }
        let clase: ErrorRPC.Clase = (status == 429 || status == 408 || status >= 500) ? .transitorio : (j == nil ? .red : .permanente)
        return .failure(ErrorRPC(clase: clase, status: status, mensaje: j?["error"]?.comoTexto ?? "servicio no disponible"))
    }
}
