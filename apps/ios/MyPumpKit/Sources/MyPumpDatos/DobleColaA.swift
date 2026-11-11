#if DEBUG
import Foundation
import MyPumpModelos
import MyPumpReglas

/// El servidor de mentira de la cola A (2.3.0): contesta las palancas, «Récords y logros» (`mypump_wins_*`) y la lista previa
/// (`mypump_lista_previa`) como la propuesta `nativa_wins_lista_previa.sql`. Lo usan las pruebas del kit y, con
/// `-colaADePrueba <escenario>`, las de interfaz y las capturas. Nunca toca la red.
public final class DobleColaA: Transporte, @unchecked Sendable {
    public struct Registro: Equatable, Sendable {
        public let id: String
        public let tipo: String
        public let clave: String
        public let dia: String
        public let datos: JSONValue
    }

    private let lock = NSLock()
    public var palancaWins = true
    public var palancaLista = true
    /// El permiso vigente del alumno en el servidor.
    public var permiso = false
    /// Las funciones no existen (PGRST202).
    public var sinFuncion = false
    public var sinRed = false
    /// Solo dar o sacar el permiso falla por la red (lo demás contesta).
    public var sinRedPermiso = false
    /// `mypump_wins_registrar` contesta 503.
    public var registrarCaido = false
    /// `mypump_wins_registrar` contesta `{ok: false, motivo: 'datos'}`.
    public var registrarRechaza = false
    public var tokenCaido = false
    /// Lo que contesta `mypump_lista_previa` (por defecto, la lista de la demo).
    public var lista: JSONValue = DobleColaA.listaDemo
    public private(set) var llamadas: [String] = []
    public private(set) var registrados: [Registro] = []
    /// Los `p_otorga` que llegaron a `mypump_wins_permiso`.
    public private(set) var permisosPedidos: [Bool] = []

    public init() {}

    public var llamadasWins: [String] { lock.withLock { llamadas.filter { $0.hasPrefix("mypump_wins") } } }
    public var llamadasLista: [String] { lock.withLock { llamadas.filter { $0 == "mypump_lista_previa" } } }

    public static let listaDemo: JSONValue = .objeto(["ok": .bool(true), "activa": .bool(true), "items": .lista([
        .objeto(["clave": .texto("guia"), "estado": .texto("falta"), "faltan": .numero(2)]),
        .objeto(["clave": .texto("dudas"), "estado": .texto("falta"), "opcional": .bool(true)]),
        .objeto(["clave": .texto("formulario"), "estado": .texto("hecho")]),
        .objeto(["clave": .texto("fotos"), "estado": .texto("falta")]),
    ])])
    public static let listaLista: JSONValue = .objeto(["ok": .bool(true), "activa": .bool(true), "items": .lista([
        .objeto(["clave": .texto("guia"), "estado": .texto("hecho"), "faltan": .numero(0)]),
        .objeto(["clave": .texto("dudas"), "estado": .texto("falta"), "opcional": .bool(true)]),
        .objeto(["clave": .texto("fotos"), "estado": .texto("hecho")]),
    ])])

    /// `sinPermiso` (palancas prendidas, sin permiso), `conPermiso`, `sinRedPermiso` (dar el permiso falla), `apagado`
    /// (palancas apagadas), `apagadoConPermiso` (palanca apagada y el permiso dado), `sinServidor` (PGRST202), `sinRed`,
    /// `listaLista` (la lista con todo hecho), `listaInactiva`.
    public static func escenario(_ nombre: String) -> DobleColaA {
        let d = DobleColaA()
        switch nombre {
        case "conPermiso": d.permiso = true
        case "sinRedPermiso": d.sinRedPermiso = true
        case "apagado": d.palancaWins = false; d.palancaLista = false
        case "apagadoConPermiso": d.palancaWins = false; d.palancaLista = false; d.permiso = true
        case "sinServidor": d.sinFuncion = true
        case "sinRed": d.sinRed = true
        case "listaLista": d.lista = listaLista
        case "listaInactiva": d.lista = .objeto(["ok": .bool(true), "activa": .bool(false), "items": .lista([])])
        default: break
        }
        return d
    }

    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let f = pedido.url?.lastPathComponent ?? ""
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let (status, texto) = try lock.withLock { () throws -> (Int, String) in
            llamadas.append(f)
            if sinRed { throw URLError(.notConnectedToInternet) }
            let noExiste = (404, #"{"code":"PGRST202","message":"Could not find the function"}"#)
            switch f {
            case "mypump_get_cliente_info":
                return (200, #"[{"cliente_id":"c-prueba","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_app_config":
                return (200, #"{"wins_app": \#(palancaWins), "lista_previa": \#(palancaLista)}"#)
            case "mypump_wins_estado":
                if sinFuncion { return noExiste }
                if tokenCaido { return (200, #"{"ok": false, "motivo": "token"}"#) }
                return (200, #"{"ok": true, "activa": \#(palancaWins), "permiso": \#(permiso)}"#)
            case "mypump_wins_permiso":
                if sinFuncion { return noExiste }
                if sinRedPermiso { throw URLError(.notConnectedToInternet) }
                guard case .bool(let otorga)? = cuerpo?["p_otorga"] else { return (200, #"{"ok": false, "motivo": "datos"}"#) }
                permisosPedidos.append(otorga)
                if otorga {
                    if !palancaWins { return (200, #"{"ok": false, "motivo": "apagada"}"#) }
                    permiso = true
                    return (200, #"{"ok": true, "permiso": true}"#)
                }
                permiso = false
                return (200, #"{"ok": true, "permiso": false, "retirados": 0}"#)
            case "mypump_wins_registrar":
                if sinFuncion { return noExiste }
                if registrarCaido { return (503, #"{"message":"caído"}"#) }
                if tokenCaido { return (200, #"{"ok": false, "motivo": "token"}"#) }
                if !palancaWins { return (200, #"{"ok": true, "guardado": false, "motivo": "apagada"}"#) }
                if !permiso { return (200, #"{"ok": true, "guardado": false, "motivo": "sin_permiso"}"#) }
                if registrarRechaza { return (200, #"{"ok": false, "motivo": "datos"}"#) }
                let id = cuerpo?["p_id"]?.comoTexto ?? ""
                if registrados.contains(where: { $0.id == id }) { return (200, #"{"ok": true, "guardado": true, "ya": true}"#) }
                registrados.append(Registro(id: id, tipo: cuerpo?["p_tipo"]?.comoTexto ?? "", clave: cuerpo?["p_clave"]?.comoTexto ?? "",
                                            dia: cuerpo?["p_dia"]?.comoTexto ?? "", datos: cuerpo?["p_datos"] ?? .null))
                return (200, #"{"ok": true, "guardado": true, "ya": false}"#)
            case "mypump_lista_previa":
                if sinFuncion { return noExiste }
                if tokenCaido { return (200, #"{"ok": false, "motivo": "token"}"#) }
                if !palancaLista { return (200, #"{"ok": true, "activa": false, "items": []}"#) }
                let datos = (try? JSONEncoder().encode(lista)) ?? Data()
                return (200, String(decoding: datos, as: UTF8.self))
            default:
                return (200, "[]")
            }
        }
        return (Data(texto.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
