#if DEBUG
import Foundation
import MyPumpModelos
import MyPumpReglas

/// El servidor de la devolución de mentira: contesta `mypump_devolucion_get` y la palanca. Lo usan las pruebas del kit y,
/// con `-devolucionDePrueba <escenario>`, las de interfaz y las capturas. Nunca toca la red. Textos inventados.
public final class DobleDevolucion: Transporte, @unchecked Sendable {
    private let lock = NSLock()
    public var palanca = true
    public var habilitado = true
    public var sinFuncion = false
    public var tokenCaido = false
    public var sinRed = false
    public var devoluciones: [JSONValue] = []
    public private(set) var llamadas: [String] = []

    public init() {}

    public var llamadasDevolucion: [String] { lock.withLock { llamadas.filter { $0.hasPrefix("mypump_devolucion") } } }

    public static let textoUltima = """
    las 4 sesiones hechas, de lujo
    sentadilla 2kg arriba con las mismas repes
    y el peso 500g abajo
    esta semana enfocate en llegar a los pasos todos los días
    """
    public static let textoAnterior = """
    entrenaste las 5 veces, muy bien
    la dieta casi entera
    para esta sumale una fruta a la merienda
    """
    public static let textoVieja = """
    bien que volviste después de la semana floja
    el press inclinado una repe más en cada serie
    como venis durmiendo?
    """

    /// `dos` (la última y dos anteriores), `una`, `vacio`, `apagado` (palanca), `noHabilitado`, `sinServidor` (PGRST202), `sinRed`.
    public static func escenario(_ nombre: String, hoy: Date = Date()) -> DobleDevolucion {
        let d = DobleDevolucion()
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        func lunes(_ semanasAtras: Int) -> String {
            let f = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: hoy) + 5) % 7) - 7 * semanasAtras, to: hoy)!
            return FechaLocal.hoy(f)
        }
        func fila(_ id: String, _ atras: Int, _ texto: String) -> JSONValue {
            .objeto(["id": .texto(id), "semana_lunes": .texto(lunes(atras)), "texto": .texto(texto),
                     "publicado_en": .texto(atras == 0 ? FechaLocal.hoy(hoy) + "T14:00:00Z" : lunes(atras - 1) + "T14:00:00Z")])
        }
        switch nombre {
        case "una": d.devoluciones = [fila("d1", 0, textoUltima)]
        case "vacio": break
        case "apagado": d.palanca = false
        case "noHabilitado": d.habilitado = false
        case "sinServidor": d.sinFuncion = true
        case "sinRed": d.sinRed = true
        default: d.devoluciones = [fila("d1", 0, textoUltima), fila("d2", 1, textoAnterior), fila("d3", 2, textoVieja)]
        }
        return d
    }

    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let f = pedido.url?.lastPathComponent ?? ""
        let (status, cuerpo) = try lock.withLock { () throws -> (Int, String) in
            llamadas.append(f)
            if sinRed { throw URLError(.notConnectedToInternet) }
            switch f {
            case "mypump_get_cliente_info":
                return (200, #"[{"cliente_id":"c-prueba","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_app_config":
                return (200, #"{"devolucion_semanal": \#(palanca)}"#)
            case "mypump_devolucion_get":
                if sinFuncion { return (404, #"{"code":"PGRST202","message":"Could not find the function"}"#) }
                if tokenCaido { return (200, "null") }
                if !habilitado || !palanca { return (200, #"{"habilitado": false}"#) }
                let datos = (try? JSONEncoder().encode(JSONValue.objeto(["habilitado": .bool(true), "devoluciones": .lista(devoluciones)]))) ?? Data()
                return (200, String(decoding: datos, as: UTF8.self))
            default:
                return (200, "[]")
            }
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
