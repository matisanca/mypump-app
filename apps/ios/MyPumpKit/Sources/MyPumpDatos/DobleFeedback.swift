#if DEBUG
import Foundation
import MyPumpModelos
import MyPumpReglas

/// El servidor de feedback de mentira: sigue `supabase/propuestas/nativa_feedback_alumno.sql` en memoria. Lo usan las pruebas
/// del kit y, con `-feedbackDePrueba <escenario>`, las de interfaz. Nunca toca la red.
public final class DobleFeedback: Transporte, @unchecked Sendable {
    private let lock = NSLock()
    public var meDuele = true
    public var supleEstado = true
    public var sinFuncion = false
    public var sinRed = false
    public var tope = false
    /// Falla la próxima marca de suplemento con un 500.
    public var fallaMarcar = false
    public var llamadas: [String] = []
    public var molestias: [[String: JSONValue]] = []
    public var marcas: [String: String] = [:]
    /// Los ítems que la suplementación del alumno tiene, por clave → es protector.
    public var items: [String: Bool] = ["creatina monohidrato": false, "omega 3": false, "cafeina": false, "magnesio glicinato": false, "telmisartan": true]
    public var ultimoRegistro: JSONValue?

    public init() {}

    /// `vacio`, `avisada` (una molestia abierta en cada ejercicio de `ejercicios`), `resuelta`, `marcado`, `apagado`.
    public static func escenario(_ nombre: String, ejercicios: [String] = []) -> DobleFeedback {
        let d = DobleFeedback()
        switch nombre {
        case "apagado": d.meDuele = false; d.supleEstado = false
        case "avisada", "resuelta":
            d.molestias = ejercicios.enumerated().map { n, id in
                ["id": .texto(String(format: "11111111-1111-4111-8111-%012d", n)), "ejercicio_id": .texto(id), "ejercicio_nombre": .texto("Ejercicio"),
                 "zona": .texto("hombro"), "lado": .texto("derecho"), "desde": .texto("esta_semana"), "cuando": .texto("al_subir"), "tipo": .texto("sordo"),
                 "intensidad": .numero(5), "nota": .null, "estado": .texto(nombre)]
            }
        case "marcado": d.marcas = ["creatina monohidrato": "tomando", "omega 3": "comprado"]
        default: break
        }
        return d
    }

    public var llamadasFeedback: [String] { lock.withLock { llamadas.filter { $0.contains("feedback") || $0.contains("molestia") || $0.contains("suple_marcar") } } }

    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let (status, cuerpo) = try lock.withLock { () throws -> (Int, String) in
            let nombre = ruta.components(separatedBy: "/").last ?? ""
            llamadas.append(nombre)
            if sinRed { throw URLError(.notConnectedToInternet) }
            return atender(nombre, pedido)
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func json(_ v: JSONValue) -> String { String(decoding: (try? JSONEncoder().encode(v)) ?? Data(), as: UTF8.self) }
    private func cuerpo(_ p: URLRequest) -> JSONValue { p.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null }

    private func atender(_ nombre: String, _ p: URLRequest) -> (Int, String) {
        let propias = ["mypump_feedback_get", "mypump_molestia_registrar", "mypump_suple_marcar"]
        switch nombre {
        case "mypump_get_app_config":
            return (200, json(.objeto(["me_duele": .bool(meDuele), "suple_estado": .bool(supleEstado)])))
        case _ where propias.contains(nombre) && sinFuncion:
            return (404, #"{"code":"PGRST202","message":"no existe"}"#)
        case "mypump_feedback_get":
            return (200, json(.objeto([
                "me_duele": .objeto(["habilitado": .bool(meDuele), "molestias": .lista(meDuele ? molestias.map(JSONValue.objeto) : [])]),
                "suple_estado": .objeto(["habilitado": .bool(supleEstado), "items": .lista(supleEstado ? marcas.sorted { $0.key < $1.key }.map {
                    .objeto(["item": .texto($0.key), "estado": .texto($0.value), "nota": .null])
                } : [])]),
            ])))
        case "mypump_molestia_registrar":
            let j = cuerpo(p)
            ultimoRegistro = j
            if !meDuele { return (200, #"{"ok":false,"error":"apagado"}"#) }
            if tope { return (200, #"{"ok":false,"error":"tope"}"#) }
            guard let id = j["p_id"]?.comoTexto, let ej = j["p_ejercicio_id"]?.comoTexto, !ej.isEmpty, let zona = j["p_zona"]?.comoTexto, ReglasMolestia.zonaValida(zona),
                  let n = j["p_intensidad"]?.comoNumero, (0...10).contains(n) else { return (200, #"{"ok":false,"error":"datos"}"#) }
            var m: [String: JSONValue] = ["id": .texto(id), "ejercicio_id": .texto(ej), "ejercicio_nombre": j["p_ejercicio_nombre"] ?? .null, "zona": .texto(zona),
                                         "lado": j["p_lado"] ?? .null, "desde": j["p_desde"] ?? .null, "cuando": j["p_cuando"] ?? .null, "tipo": j["p_tipo"] ?? .null,
                                         "intensidad": .numero(n), "nota": j["p_nota"] ?? .null, "estado": .texto("avisada")]
            var ya = false
            if let i = molestias.firstIndex(where: { $0["id"]?.comoTexto == id || ($0["ejercicio_id"]?.comoTexto == ej && $0["estado"]?.comoTexto == "avisada") }) {
                ya = true
                m["id"] = molestias[i]["id"]
                molestias[i] = m
            } else {
                molestias.insert(m, at: 0)
            }
            return (200, json(.objeto(["ok": .bool(true), "ya": .bool(ya), "molestia": .objeto(m)])))
        case "mypump_suple_marcar":
            let j = cuerpo(p)
            if fallaMarcar { fallaMarcar = false; return (500, #"{"message":"caído"}"#) }
            if !supleEstado { return (200, #"{"ok":false,"error":"apagado"}"#) }
            let k = ReglasSupleEstado.clave(j["p_item"]?.comoTexto ?? "")
            guard let e = j["p_estado"]?.comoTexto, ReglasSupleEstado.Estado(rawValue: e) != nil else { return (200, #"{"ok":false,"error":"datos"}"#) }
            guard items[k] == false else { return (200, #"{"ok":false,"error":"item"}"#) }
            let ya = marcas[k] == e
            marcas[k] = e
            return (200, json(.objeto(["ok": .bool(true), "ya": .bool(ya), "item": .texto(k), "estado": .texto(e)])))
        default:
            return (200, "[]")
        }
    }
}
#endif
