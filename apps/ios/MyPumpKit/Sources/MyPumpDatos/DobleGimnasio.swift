#if DEBUG
import Foundation
import MyPumpModelos
import MyPumpReglas

/// El servidor del gimnasio de mentira: sigue `gimnasio/CONTRATO_APP.md` en memoria (RPC y endpoints). Lo usan las pruebas
/// del kit y, con `-gimnasioDePrueba <escenario>`, las de interfaz. Nunca toca la red.
public final class DobleGimnasio: Transporte, @unchecked Sendable {
    public struct Foto: Equatable { public let id, zona: String; public let bytes: Data; public let ronda: Int }

    private let lock = NSLock()
    public var palanca = true
    public var sinFuncion = false
    public var habilitado = true
    public var sinRed = false
    /// Estados forzados para las próximas subidas, en orden (503, 429, 400…). 0 = sin red en esa.
    public var proximasSubidas: [Int] = []
    public var llamadas: [String] = []
    public var abierta: [String: JSONValue]?
    public var vigente: [String: JSONValue]?
    public var fotos: [Foto] = []
    public var ultimoEnviar: [String: JSONValue]?
    public var ultimoResponder: JSONValue?
    public var cabecerasUltimaSubida: [String: String] = [:]

    public init() {}

    public var llamadasGimnasio: [String] { lock.withLock { llamadas.filter { $0.contains("gimnasio") } } }
    public var intentosDeSubida: Int { lock.withLock { llamadas.filter { $0 == "gimnasio/upload" }.count } }

    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let (status, cuerpo) = try lock.withLock { () throws -> (Int, String) in
            let f = ruta.components(separatedBy: "/").last ?? ""
            let nombre = ruta.contains("/gimnasio/") ? "gimnasio/\(f)" : f
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
            return (200, palanca ? #"{"gimnasio_fotos":true}"# : #"{"gimnasio_fotos":false}"#)
        case _ where nombre.hasPrefix("mypump_gimnasio") && sinFuncion:
            return (404, #"{"code":"PGRST202","message":"no existe"}"#)
        case "mypump_gimnasio_get":
            if !habilitado { return (200, #"{"habilitado":false}"#) }
            return (200, json(vista()))
        case "mypump_gimnasio_nuevo":
            let j = cuerpo(p)
            if j["p_modo"]?.comoTexto == "parcial" && vigente == nil { return (200, #"{"ok":false,"error":"sin_gimnasio_vigente"}"#) }
            if let a = abierta { return (200, json(.objeto(["ok": .bool(true), "ya": .bool(true), "id": a["id"]!, "estado": a["estado"]!]))) }
            let id = UUID().uuidString.lowercased()
            abierta = ["id": .texto(id), "estado": .texto("borrador"), "modo": j["p_modo"] ?? .texto("completa"), "version": .numero(1)]
            return (200, json(.objeto(["ok": .bool(true), "ya": .bool(false), "id": .texto(id), "estado": .texto("borrador")])))
        case "mypump_gimnasio_enviar":
            return (200, enviarCarga(cuerpo(p)))
        case "mypump_gimnasio_responder":
            return (200, responderCarga(cuerpo(p)))
        case "gimnasio/upload":
            return try subida(p)
        case "gimnasio/urls":
            let filas = fotos.map { JSONValue.objeto(["id": .texto($0.id), "zona": .texto($0.zona), "url": .texto("https://ejemplo.invalid/\($0.id).jpg")]) }
            return (200, json(.objeto(["ok": .bool(true), "fotos": .lista(filas), "expira_en": .numero(3600)])))
        case "gimnasio/borrar":
            guard abierta?["estado"]?.comoTexto == "borrador" else { return (409, #"{"ok":false,"error":"esta carga ya no recibe fotos"}"#) }
            let id = cuerpo(p)["foto_id"]?.comoTexto
            fotos.removeAll { $0.id == id }
            return (200, #"{"ok":true}"#)
        default:
            return (200, "[]")
        }
    }

    private func subida(_ p: URLRequest) throws -> (Int, String) {
        if !proximasSubidas.isEmpty {
            let s = proximasSubidas.removeFirst()
            if s == 0 { throw URLError(.networkConnectionLost) }
            if s != 200 { return (s, #"{"ok":false,"error":"forzado"}"#) }
        }
        let h = p.allHTTPHeaderFields ?? [:]
        cabecerasUltimaSubida = h
        guard let id = h["x-gimnasio-foto"], let zona = h["x-gimnasio-zona"], h["x-gimnasio-id"] == abierta?["id"]?.comoTexto else { return (404, #"{"ok":false}"#) }
        guard abierta?["estado"]?.comoTexto == "borrador" || abierta?["estado"]?.comoTexto == "a_confirmar" else { return (409, #"{"ok":false}"#) }
        if fotos.contains(where: { $0.id == id }) { return (200, #"{"ok":true,"ya":true}"#) }
        if fotos.count >= Gimnasio.topeFotos { return (413, #"{"ok":false,"error":"llegaste al máximo de fotos"}"#) }
        fotos.append(Foto(id: id, zona: zona, bytes: p.httpBody ?? Data(), ronda: abierta?["estado"]?.comoTexto == "borrador" ? 0 : 1))
        return (200, #"{"ok":true}"#)
    }

    private func enviarCarga(_ j: JSONValue) -> String {
        guard var a = abierta, a["id"] == j["p_id"] else { return #"{"ok":false,"error":"no_encontrado"}"# }
        guard a["estado"]?.comoTexto == "borrador" else { return #"{"ok":true,"ya":true,"estado":"enviado"}"# }
        ultimoEnviar = { if case .objeto(let o) = j { o } else { nil } }()
        var noHay = Set<String>(); if case .lista(let l)? = j["p_no_hay"] { noHay = Set(l.compactMap(\.comoTexto)) }
        let con = Set(fotos.map(\.zona))
        if a["modo"]?.comoTexto == "completa" {
            let faltan = Gimnasio.zonasFaltantes(conFotos: con, noHay: noHay)
            if !faltan.isEmpty { return json(.objeto(["ok": .bool(false), "error": .texto("faltan_zonas"), "faltan": .lista(faltan.map(JSONValue.texto))])) }
        } else if con.isEmpty, case .lista(let q)? = j["p_quitar"], q.isEmpty {
            return #"{"ok":false,"error":"sin_novedad"}"#
        }
        a["estado"] = .texto("enviado")
        abierta = a
        return #"{"ok":true,"ya":false,"estado":"enviado"}"#
    }

    private func responderCarga(_ j: JSONValue) -> String {
        guard var a = abierta, a["id"] == j["p_id"] else { return #"{"ok":false,"error":"no_encontrado"}"# }
        guard a["estado"]?.comoTexto == "a_confirmar" else { return #"{"ok":true,"ya":true,"estado":"respondido"}"# }
        ultimoResponder = j["p_respuestas"]
        a["estado"] = .texto("respondido")
        a["preguntas"] = .lista([])
        abierta = a
        return #"{"ok":true,"ya":false,"estado":"respondido"}"#
    }

    private func vista() -> JSONValue {
        func carga(_ c: [String: JSONValue]?) -> JSONValue {
            guard var c else { return .null }
            if c["estado"]?.comoTexto != "listo" {
                c["fotos"] = .lista(fotos.map { .objeto(["id": .texto($0.id), "zona": .texto($0.zona), "ronda": .numero(Double($0.ronda))]) })
                c["zonas_faltantes"] = .lista(Gimnasio.zonasFaltantes(conFotos: Set(fotos.map(\.zona)), noHay: []).map(JSONValue.texto))
            }
            return .objeto(c)
        }
        return .objeto(["habilitado": .bool(true), "abierta": carga(abierta), "vigente": carga(vigente)])
    }

    // MARK: Datos de ejemplo (sin nombres reales)

    public static let preguntasDeEjemplo: JSONValue = {
        let s = #"""
        [{"id":"remo","clase":"elegir","multiple":true,"zona":"tiron","texto":"¿Cuál de estas tenés en tu gimnasio?","fotos":[],"opciones":[{"valor":"remo_t","texto":"Remo T"},{"valor":"remo_pecho_apoyado","texto":"Remo con pecho apoyado"}]},
        {"id":"accesorios","clase":"elegir","multiple":true,"zona":"accesorios_polea","texto":"¿Cuáles de estos agarres para polea hay en tu gimnasio?","fotos":[],"opciones":[{"valor":"soga","texto":"Soga"},{"valor":"barra_v","texto":"Barra V"},{"valor":"barra_recta","texto":"Barra recta"}]},
        {"id":"peso_discos","clase":"elegir","multiple":false,"zona":"discos","texto":"¿Cuál es el disco más chico que hay?","fotos":[],"opciones":[{"valor":"1.25","texto":"1,25 kg"},{"valor":"2.5","texto":"2,5 kg"},{"valor":"5","texto":"5 kg"}]},
        {"id":"peso_mancuernas","clase":"numero","zona":"mancuernas","texto":"¿Hasta cuántos kilos llegan las mancuernas?","unidad":"kg","fotos":[]},
        {"id":"confirmar_empuje","clase":"confirmar","zona":"empuje","texto":"Confirmanos qué de esto hay en tu gimnasio","fotos":[],"items":[{"tipo":"pec_deck","texto":"Pec deck","fotos":[]},{"tipo":"press_inclinado","texto":"Press inclinado","fotos":[]}]},
        {"id":"foto_1","clase":"foto","zona":"bancos","texto":"Necesitamos otra foto de esta zona, sin gente y con el equipo entero","fotos":[]}]
        """#
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .lista([])
    }()

    public static let equiposDeEjemplo: JSONValue = {
        let s = #"""
        [{"tipo":"polea_doble","nombre":"Cruce de poleas","zona":"poleas","cantidad":2},{"tipo":"prensa_45","nombre":"Prensa 45°","zona":"piernas","cantidad":1},
         {"tipo":"banco_regulable","nombre":"Banco regulable","zona":"bancos","cantidad":3},{"tipo":"mancuernas","nombre":"Mancuernas hasta 50 kg","zona":"mancuernas","cantidad":1}]
        """#
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .lista([])
    }()

    /// El estado de partida de cada escenario de las pruebas de interfaz.
    public static func escenario(_ nombre: String) -> DobleGimnasio {
        let d = DobleGimnasio()
        let id = "11111111-1111-4111-8111-111111111111"
        switch nombre {
        case "apagado": d.palanca = false
        case "sinServidor": d.sinFuncion = true
        case "borrador", "corte", "rechazo", "reintento":
            d.abierta = ["id": .texto(id), "estado": .texto("borrador"), "modo": .texto("completa")]
            if nombre == "corte" { d.proximasSubidas = [200, 0] }
            if nombre == "rechazo" { d.proximasSubidas = [400] }
            if nombre == "reintento" { d.proximasSubidas = [503] }
        case "enProceso":
            d.abierta = ["id": .texto(id), "estado": .texto("procesando"), "modo": .texto("completa")]
        case "preguntas":
            d.abierta = ["id": .texto(id), "estado": .texto("a_confirmar"), "modo": .texto("completa"), "preguntas": preguntasDeEjemplo]
        case "listo", "listoSinCambios":
            d.vigente = ["id": .texto(id), "estado": .texto("listo"), "modo": .texto("completa"), "resultado": .texto(nombre == "listo" ? "adaptada" : "sin_cambios"),
                         "publicado_en": .texto("2026-11-12T15:00:00+00:00"), "equipos": equiposDeEjemplo]
        default: break    // "vacio": habilitado, sin nada
        }
        return d
    }
}
#endif
