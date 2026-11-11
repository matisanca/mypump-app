#if DEBUG
import Foundation
import MyPumpModelos
import MyPumpReglas

/// El servidor de mentira de la cola B (Tu recorrido, Dónde comprarlo y Entreno en casa): sigue los SQL de
/// `supabase/propuestas/` en memoria. Lo usan las pruebas del kit y, con `-colaBDePrueba <escenario>`, las de interfaz.
/// Lo de Mi gimnasio lo contesta un `DobleGimnasio` adentro, porque casa es la misma carga. Nunca toca la red.
public final class DobleColaB: Transporte, @unchecked Sendable {
    private let lock = NSLock()
    public let gimnasio = DobleGimnasio()
    public var palancas: [String: Bool] = ["fin_plan": true, "compras_pais": true, "casa": true, "gimnasio_fotos": true, "novedades_plan": false]
    public var sinFuncion = false
    public var sinRed = false
    public var llamadas: [String] = []

    // Tu recorrido
    public var recorridoVisible = false
    public var recorridoEstado = "publicado"
    public var recorridoResumen: JSONValue = DobleColaB.resumenDeEjemplo
    public var recorridoRespuestas: [String: JSONValue] = [:]
    public var agenda = "mati"
    public var pedidos: [(id: String, respuestas: JSONValue)] = []
    public var vistos = 0
    /// El próximo `pedir` falla así: "red", "no_disponible" o "500".
    public var proximoPedir: String?

    // Dónde comprarlo
    public var compras: JSONValue = .objeto(["habilitado": .bool(true), "items": .lista([])])
    public var suplementacion: JSONValue?

    // Entreno en casa
    public var casaHabilitada = true
    public var ultimoEnviarCasa: JSONValue?
    public var proximoCasa: String?

    public init() {}

    public var llamadasNuevas: [String] {
        lock.withLock { llamadas.filter { $0.hasPrefix("mypump_fin_plan") || $0.hasPrefix("mypump_compras") || $0.hasPrefix("mypump_casa") } }
    }
    public func cuantas(_ nombre: String) -> Int { lock.withLock { llamadas.filter { $0 == nombre }.count } }

    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let f = ruta.components(separatedBy: "/").last ?? ""
        if ruta.contains("/gimnasio/") || f.hasPrefix("mypump_gimnasio") {
            if lock.withLock({ sinRed }) { throw URLError(.notConnectedToInternet) }
            return try await gimnasio.enviar(pedido)
        }
        let (status, cuerpo) = try lock.withLock { () throws -> (Int, String) in
            llamadas.append(f)
            if sinRed { throw URLError(.notConnectedToInternet) }
            return try atender(f, pedido)
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func json(_ v: JSONValue) -> String { String(decoding: (try? JSONEncoder().encode(v)) ?? Data(), as: UTF8.self) }
    private func cuerpo(_ p: URLRequest) -> JSONValue { p.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null }
    private func no(_ error: String) -> (Int, String) { (200, #"{"ok":false,"error":"\#(error)"}"#) }

    private func atender(_ nombre: String, _ p: URLRequest) throws -> (Int, String) {
        let nueva = nombre.hasPrefix("mypump_fin_plan") || nombre.hasPrefix("mypump_compras") || nombre.hasPrefix("mypump_casa")
        if nueva && sinFuncion { return (404, #"{"code":"PGRST202","message":"no existe"}"#) }
        switch nombre {
        case "mypump_get_app_config":
            return (200, json(.objeto(palancas.mapValues(JSONValue.bool))))
        case "mypump_suplementacion":
            return (200, suplementacion.map { json(.lista([$0])) } ?? "[]")

        case "mypump_fin_plan_get":
            guard palancas["fin_plan"] == true else { return (200, #"{"habilitado":false}"#) }
            guard recorridoVisible else { return (200, #"{"habilitado":true,"visible":false}"#) }
            return (200, json(.objeto(["habilitado": .bool(true), "visible": .bool(true), "estado": .texto(recorridoEstado), "resumen": recorridoResumen,
                                       "respuestas": .objeto(recorridoRespuestas), "agenda": .texto(agenda)])))
        case "mypump_fin_plan_visto":
            vistos += 1
            return (200, #"{"ok":true}"#)
        case "mypump_fin_plan_pedir":
            if let f = proximoPedir {
                proximoPedir = nil
                if f == "red" { throw URLError(.networkConnectionLost) }
                if f == "500" { return (500, #"{"message":"falla"}"#) }
                return no(f)
            }
            guard palancas["fin_plan"] == true else { return no("apagado") }
            guard recorridoVisible else { return no("no_disponible") }
            let j = cuerpo(p)
            guard let id = j["p_id"]?.comoTexto else { return (400, #"{"code":"22023","message":"pedido mal formado"}"#) }
            if recorridoEstado == "agendado" { return (200, #"{"ok":true,"ya":true,"estado":"agendado"}"#) }
            let ya = recorridoEstado == "pedido"
            if !ya {
                pedidos.append((id, j["p_respuestas"] ?? .null))
                recorridoEstado = "pedido"
                if case .objeto(let o)? = j["p_respuestas"] { recorridoRespuestas = o }
            }
            return (200, #"{"ok":true,"ya":\#(ya),"estado":"pedido"}"#)

        case "mypump_compras_get":
            guard palancas["compras_pais"] == true else { return (200, #"{"habilitado":false}"#) }
            return (200, json(compras))

        case "mypump_casa_get":
            guard habilitadaCasa else { return (200, #"{"habilitado":false}"#) }
            return (200, json(.objeto(["habilitado": .bool(true), "tipos": Self.tiposDeEjemplo, "abierta": vistaCasa(gimnasio.abierta), "vigente": vistaCasa(gimnasio.vigente)])))
        case "mypump_casa_elegir":
            if let f = proximoCasa { proximoCasa = nil; if f == "red" { throw URLError(.networkConnectionLost) }; return no(f) }
            guard habilitadaCasa else { return no("no_habilitado") }
            let casa = cuerpo(p)["p_casa"] == .bool(true)
            let lugar = casa ? "casa" : "gimnasio"
            if var a = gimnasio.abierta {
                if (a["lugar"]?.comoTexto ?? "gimnasio") == lugar { return (200, #"{"ok":true,"ya":true}"#) }
                guard a["estado"]?.comoTexto == "borrador" else { return no("en_curso") }
                a["lugar"] = .texto(lugar)
                if casa { a["modo"] = .texto("completa") }
                gimnasio.abierta = a
                return (200, #"{"ok":true,"ya":false}"#)
            }
            guard casa else { return (200, #"{"ok":true,"ya":true}"#) }
            gimnasio.abierta = ["id": .texto(UUID().uuidString.lowercased()), "estado": .texto("borrador"), "modo": .texto("completa"), "lugar": .texto("casa")]
            return (200, #"{"ok":true,"ya":false}"#)
        case "mypump_casa_enviar":
            if let f = proximoCasa { proximoCasa = nil; if f == "red" { throw URLError(.networkConnectionLost) }; return no(f) }
            let j = cuerpo(p)
            guard var a = gimnasio.abierta, a["id"] == j["p_id"] else { return no("no_encontrado") }
            guard a["lugar"]?.comoTexto == "casa" else { return no("no_es_casa") }
            guard a["estado"]?.comoTexto == "borrador" else { return (200, #"{"ok":true,"ya":true,"estado":"a_revisar"}"#) }
            guard habilitadaCasa else { return no("no_habilitado") }
            var equipos: [JSONValue] = []
            if case .lista(let l)? = j["p_equipos"] { equipos = l }
            let sin = j["p_sin_equipo"] == .bool(true)
            if equipos.isEmpty && !sin { return no("sin_datos") }
            if !equipos.isEmpty && sin { return no("contradiccion") }
            ultimoEnviarCasa = j
            a["estado"] = .texto("a_revisar")
            a["equipos_casa"] = .lista(equipos)
            a["sin_equipo"] = .bool(sin)
            if let n = j["p_nota"], n != .null { a["nota_casa"] = n }
            gimnasio.abierta = a
            return (200, #"{"ok":true,"ya":false,"estado":"a_revisar"}"#)
        default:
            return (200, "[]")
        }
    }

    private var habilitadaCasa: Bool { palancas["casa"] == true && palancas["gimnasio_fotos"] == true && casaHabilitada && gimnasio.habilitado }

    private func vistaCasa(_ c: [String: JSONValue]?) -> JSONValue {
        guard let c else { return .null }
        var o: [String: JSONValue] = ["id": c["id"] ?? .null, "estado": c["estado"] ?? .null, "lugar": c["lugar"] ?? .texto("gimnasio"),
                                      "equipos": c["equipos_casa"] ?? .lista([]), "sin_equipo": c["sin_equipo"] ?? .bool(false)]
        if let n = c["nota_casa"] { o["nota"] = n }
        return .objeto(o)
    }

    /// Mati aprobó la carga abierta: pasa a ser la vigente (lo que hace `mypump_gimnasio_cerrar`).
    public func aprobarAbierta() {
        lock.withLock {
            guard var a = gimnasio.abierta else { return }
            a["estado"] = .texto("listo"); a["resultado"] = .texto("adaptada")
            gimnasio.vigente = a; gimnasio.abierta = nil
        }
    }

    // MARK: Datos de ejemplo (inventados, sin nombres reales)

    static func valor(_ s: String) -> JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null }

    public static let resumenDeEjemplo = valor(#"""
    {"titulo":"Tu recorrido","mensaje":"Arrancaste con dudas y terminaste entrenando cuatro veces por semana. Esto es lo que hiciste.",
     "logros":[{"titulo":"Entrenamientos","valor":"58","detalle":"Casi no faltaste"},{"titulo":"Peso","valor":"-6,2 kg","detalle":"De 88,4 a 82,2 kg"},
               {"titulo":"Sentadilla","valor":"+25 kg","detalle":"De 60 a 85 kg"},{"titulo":"Pasos por día","valor":"9.400","detalle":"Antes eran 5.100"}]}
    """#)

    public static let tiposDeEjemplo = valor(#"""
    [{"tipo":"mancuernas","nombre":"Mancuernas","kg":true},{"tipo":"mancuernas_regulables","nombre":"Mancuernas regulables","kg":true},
     {"tipo":"barra_olimpica","nombre":"Barra","kg":false},{"tipo":"discos","nombre":"Discos","kg":true},{"tipo":"barra_z","nombre":"Barra Z","kg":false},
     {"tipo":"kettlebells","nombre":"Pesas rusas","kg":true},{"tipo":"banco_plano","nombre":"Banco plano","kg":false},
     {"tipo":"banco_regulable","nombre":"Banco regulable","kg":false},{"tipo":"rack_sentadilla","nombre":"Soporte para sentadilla","kg":false},
     {"tipo":"barra_dominadas","nombre":"Barra de dominadas","kg":false},{"tipo":"paralelas","nombre":"Paralelas","kg":false},
     {"tipo":"bandas_elasticas","nombre":"Bandas elásticas","kg":false},{"tipo":"trx","nombre":"Correas de suspensión","kg":false},
     {"tipo":"polea_ajustable","nombre":"Polea","kg":false},{"tipo":"cinta","nombre":"Cinta para caminar o correr","kg":false},
     {"tipo":"bici_fija","nombre":"Bicicleta fija","kg":false}]
    """#)

    public static let suplementacionDeEjemplo = valor(#"""
    {"suplementacion":{"titulo":"Tu suplementación","dia":[{"id":"desayuno","titulo":"Desayuno"},{"id":"dormir","titulo":"Antes de dormir"}],
      "items":[{"nombre":"Creatina monohidrato","cantidad":"5 g","momento":"desayuno","estado":"sigue"},
               {"nombre":"Omega 3","cantidad":"2 cápsulas","momento":"desayuno","estado":"sigue"},
               {"nombre":"Magnesio","cantidad":"400 mg","momento":"dormir","estado":"nuevo"}]},
     "fase":"final","actualizado":"2026-11-09T10:00:00+00:00","esquema":1}
    """#)

    /// Tiendas inventadas, con dominios que no existen.
    public static let comprasDeEjemplo = valor(#"""
    {"habilitado":true,"pais":"AR","items":[
      {"nombre":"Creatina monohidrato","opciones":[
        {"producto":"Creatina de prueba 300 g","tienda":"Tienda Ejemplo","url":"https://tienda-ejemplo.invalid/creatina","nota":"Sin sabor"},
        {"producto":"Creatina genérica 500 g","tienda":"Farmacia de Muestra"}]},
      {"nombre":"Magnesio","opciones":[{"producto":"Magnesio de prueba 60 cápsulas","tienda":"Dietética Inventada","url":"https://dietetica-inventada.invalid/magnesio"}]}]}
    """#)

    /// El estado de partida de cada escenario de las pruebas de interfaz.
    public static func escenario(_ nombre: String) -> DobleColaB {
        let d = DobleColaB()
        d.suplementacion = suplementacionDeEjemplo
        d.compras = comprasDeEjemplo
        d.recorridoVisible = true
        let id = "22222222-2222-4222-8222-222222222222"
        switch nombre {
        case "apagado":
            d.palancas = ["fin_plan": false, "compras_pais": false, "casa": false, "gimnasio_fotos": true]
        case "sinServidor": d.sinFuncion = true
        case "pedido": d.recorridoEstado = "pedido"
        case "agendado": d.recorridoEstado = "agendado"
        case "agendaApp": d.agenda = "app"
        case "falla": d.proximoPedir = "red"
        case "casaBorrador":
            d.gimnasio.abierta = ["id": .texto(id), "estado": .texto("borrador"), "modo": .texto("completa"), "lugar": .texto("casa")]
        case "casaRecibido":
            d.gimnasio.abierta = ["id": .texto(id), "estado": .texto("a_revisar"), "modo": .texto("completa"), "lugar": .texto("casa"),
                                  "equipos_casa": valor(#"[{"tipo":"mancuernas","kg":20}]"#)]
        case "casaVigente":
            d.gimnasio.vigente = ["id": .texto(id), "estado": .texto("listo"), "modo": .texto("completa"), "lugar": .texto("casa"), "resultado": .texto("adaptada"),
                                  "equipos_casa": valor(#"[{"tipo":"mancuernas","kg":20},{"tipo":"banco_plano"},{"tipo":"bandas_elasticas"}]"#), "equipos": .lista([])]
        case "gimnasioListo":
            d.gimnasio.vigente = DobleGimnasio.escenario("listo").vigente
        case "gimnasioEnProceso":
            d.gimnasio.abierta = ["id": .texto(id), "estado": .texto("procesando"), "modo": .texto("completa")]
        default: break   // "todo": recorrido publicado, compras, y Mi gimnasio vacío con el interruptor apagado
        }
        // En los escenarios de casa y de gimnasio el recorrido ya está pedido: así su hoja no se abre sola encima.
        if nombre.hasPrefix("casa") || nombre.hasPrefix("gimnasio") { d.recorridoEstado = "pedido" }
        return d
    }
}
#endif
