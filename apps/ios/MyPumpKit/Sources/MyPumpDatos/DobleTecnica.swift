#if DEBUG
import Foundation
import MyPumpModelos
import MyPumpReglas

/// El servidor de técnica de mentira: sigue `tecnica/CONTRATO_APP.md` en memoria. Lo usan las pruebas del kit y, con
/// `-tecnicaDePrueba <escenario>`, las de interfaz. Nunca toca la red.
public final class DobleTecnica: Transporte, @unchecked Sendable {
    private let lock = NSLock()
    public var palanca = true
    public var sinFuncion = false
    public var habilitado = true
    public var consentimientoAceptado = false
    public var sinRed = false
    public var tope = false
    /// Estados forzados para las próximas subidas, en orden. 0 = sin red en esa.
    public var proximasSubidas: [Int] = []
    /// Cortes de red forzados en los próximos `nuevo` (después de haber abierto el envío).
    public var cortesEnNuevo = 0
    public var llamadas: [String] = []
    public var envios: [[String: JSONValue]] = []
    public var ultimoNuevo: JSONValue?
    public var cabecerasUltimaSubida: [String: String] = [:]
    public var bytesSubidos: [Int] = []

    public init() {}

    public var llamadasTecnica: [String] { lock.withLock { llamadas.filter { $0.contains("tecnica") } } }
    public var intentosDeSubida: Int { lock.withLock { llamadas.filter { $0 == "tecnica/upload" }.count } }

    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let (status, cuerpo) = try lock.withLock { () throws -> (Int, String) in
            let f = ruta.components(separatedBy: "/").last ?? ""
            let nombre = ruta.contains("/tecnica/") ? "tecnica/\(f)" : f
            llamadas.append(nombre)
            if sinRed { throw URLError(.notConnectedToInternet) }
            return try atender(nombre, pedido)
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func json(_ v: JSONValue) -> String { String(decoding: (try? JSONEncoder().encode(v)) ?? Data(), as: UTF8.self) }
    private func cuerpo(_ p: URLRequest) -> JSONValue { p.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null }

    private func atender(_ nombre: String, _ p: URLRequest) throws -> (Int, String) {
        switch nombre {
        case "mypump_get_app_config":
            return (200, palanca ? #"{"tecnica_video":true}"# : #"{"tecnica_video":false}"#)
        case _ where nombre.hasPrefix("mypump_tecnica") && sinFuncion:
            return (404, #"{"code":"PGRST202","message":"no existe"}"#)
        case "mypump_tecnica_get":
            if !habilitado { return (200, #"{"habilitado":false}"#) }
            return (200, json(.objeto(["habilitado": .bool(true), "consentimiento_version": .texto(Tecnica.consentimientoVigente), "consentimiento_aceptado": .bool(consentimientoAceptado),
                                       "topes": .objeto(["duracion_min_s": .numero(4), "duracion_max_s": .numero(75), "bytes_max": .numero(62_914_560), "por_semana": .numero(3)]),
                                       "envios": .lista(envios.map(JSONValue.objeto))])))
        case "mypump_tecnica_nuevo": return try nuevo(cuerpo(p))
        case "mypump_tecnica_cancelar":
            let id = cuerpo(p)["p_id"]
            envios.removeAll { $0["id"] == id && $0["estado"]?.comoTexto == "borrador" }
            return (200, #"{"ok":true,"borrado":true}"#)
        case "tecnica/upload": return try subida(p)
        case "tecnica/url":
            return (200, #"{"ok":true,"url":"https://ejemplo.invalid/video.mp4","expira_en":3600}"#)
        case "tecnica/borrar":
            let id = cuerpo(p)["id"]
            guard let i = envios.firstIndex(where: { $0["id"] == id }) else { return (200, #"{"ok":true,"ya":true}"#) }
            envios[i]["tiene_video"] = .bool(false)
            return (200, #"{"ok":true}"#)
        default:
            return (200, "[]")
        }
    }

    private func nuevo(_ j: JSONValue) throws -> (Int, String) {
        guard j["p_consentimiento"]?.comoTexto == Tecnica.consentimientoVigente else { return (200, #"{"ok":false,"error":"consentimiento"}"#) }
        if let e = envios.first(where: { ["enviado", "procesando"].contains($0["estado"]?.comoTexto ?? "") }), let id = e["id"]?.comoTexto { return (200, #"{"ok":false,"error":"en_curso","id":"\#(id)"}"#) }
        if tope { return (200, #"{"ok":false,"error":"tope_semanal"}"#) }
        ultimoNuevo = j
        var id: String
        if let i = envios.firstIndex(where: { $0["estado"]?.comoTexto == "borrador" }), let ya = envios[i]["id"]?.comoTexto {
            id = ya
            envios[i]["ejercicio_nombre"] = j["p_ejercicio_nombre"]
        } else {
            id = UUID().uuidString.lowercased()
            envios.insert(["id": .texto(id), "estado": .texto("borrador"), "ejercicio_slug": j["p_ejercicio_slug"] ?? .null, "ejercicio_nombre": j["p_ejercicio_nombre"] ?? .null,
                           "nota_alumno": j["p_nota"] ?? .null, "tiene_video": .bool(false)], at: 0)
        }
        if cortesEnNuevo > 0 { cortesEnNuevo -= 1; throw URLError(.networkConnectionLost) }
        return (200, #"{"ok":true,"ya":false,"id":"\#(id)","estado":"borrador"}"#)
    }

    private func subida(_ p: URLRequest) throws -> (Int, String) {
        if !proximasSubidas.isEmpty {
            let s = proximasSubidas.removeFirst()
            if s == 0 { throw URLError(.networkConnectionLost) }
            if s == 400 { return (400, #"{"ok":false,"error":"video muy corto"}"#) }
            if s == 413 { return (413, #"{"ok":false,"error":"video muy pesado"}"#) }
            if s != 200 { return (s, #"{"ok":false,"error":"forzado"}"#) }
        }
        let h = p.allHTTPHeaderFields ?? [:]
        cabecerasUltimaSubida = h
        guard let i = envios.firstIndex(where: { $0["id"]?.comoTexto == h["x-tecnica-id"] }) else { return (404, #"{"ok":false,"error":"envío no encontrado"}"#) }
        if envios[i]["estado"]?.comoTexto != "borrador" { return (200, #"{"ok":true,"ya":true}"#) }
        bytesSubidos.append(p.httpBody?.count ?? 0)
        envios[i]["estado"] = .texto("enviado")
        envios[i]["tiene_video"] = .bool(true)
        consentimientoAceptado = true
        return (200, #"{"ok":true}"#)
    }

    // MARK: Datos de ejemplo (sin nombres reales)

    public static let devolucionDeEjemplo: JSONValue = {
        let s = #"""
        {"credito":"Lo revisó Mati","ejercicio":"Sentadilla","bien":["Bajás con la espalda firme","La profundidad es buena"],
         "correcciones":[{"prioridad":1,"titulo":"Las rodillas se van para adentro","que_se_ve":"Al subir, las dos rodillas se cierran","por_que":"Cargás de más la cara interna de la rodilla","como_corregir":"Empujá el piso hacia afuera con los pies","momento_s":3.5}],
         "no_evaluable":[{"que":"El agarre","motivo":"No se llega a ver desde este ángulo"}],"pedir_otro_video":{"necesario":true,"como":"Grabá de costado y con todo el cuerpo adentro"}}
        """#
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null
    }()

    public static let devolucionSinCorrecciones: JSONValue = {
        let s = #"{"credito":"Lo revisó Mati","ejercicio":"Sentadilla","bien":["Serie muy prolija"],"correcciones":[],"no_evaluable":[],"pedir_otro_video":{"necesario":false,"como":""}}"#
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null
    }()

    /// El estado de partida de cada escenario de las pruebas de interfaz.
    public static func escenario(_ nombre: String) -> DobleTecnica {
        let d = DobleTecnica()
        let id = "22222222-2222-4222-8222-222222222222"
        func envio(_ estado: String, extra: [String: JSONValue] = [:]) -> [String: JSONValue] {
            ["id": .texto(id), "estado": .texto(estado), "ejercicio_slug": .texto("sentadilla"), "ejercicio_nombre": .texto("Sentadilla"), "enviado_en": .texto("2026-11-10T15:00:00+00:00"), "tiene_video": .bool(true)].merging(extra) { _, b in b }
        }
        switch nombre {
        case "apagado": d.palanca = false
        case "sinServidor": d.sinFuncion = true
        case "corte": d.consentimientoAceptado = true; d.proximasSubidas = [0]
        case "rechazo": d.consentimientoAceptado = true; d.proximasSubidas = [400]
        case "reintento": d.consentimientoAceptado = true; d.proximasSubidas = [503, 429]
        case "tope": d.consentimientoAceptado = true; d.tope = true
        case "enRevision": d.consentimientoAceptado = true; d.envios = [envio("enviado")]
        case "publicado": d.consentimientoAceptado = true; d.envios = [envio("publicado", extra: ["publicado_en": .texto("2026-11-12T15:00:00+00:00"), "devolucion": devolucionDeEjemplo])]
        case "publicadoSinCorrecciones": d.consentimientoAceptado = true; d.envios = [envio("publicado", extra: ["publicado_en": .texto("2026-11-12T15:00:00+00:00"), "devolucion": devolucionSinCorrecciones])]
        case "rechazado": d.consentimientoAceptado = true; d.envios = [envio("rechazado", extra: ["rechazo_texto": .texto(TextosTecnica.rechazoIlegible), "tiene_video": .bool(false)])]
        default: break    // "vacio": habilitado, sin nada
        }
        return d
    }
}
#endif
