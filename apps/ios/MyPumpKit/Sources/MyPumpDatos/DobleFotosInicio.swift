#if DEBUG
import Foundation
import MyPumpModelos
import MyPumpReglas

/// El servidor de las fotos de inicio de mentira: sigue `docs/NATIVA_CONTRATO.md` (sección 13) en memoria. Lo usan las pruebas
/// del kit y, con `-fotosInicioDePrueba <escenario>`, las de interfaz. Nunca toca la red.
public final class DobleFotosInicio: Transporte, @unchecked Sendable {
    public struct Foto: Equatable {
        public let id, pose: String
        public let bytes: Data
        public let tomada: String?
        public let ancho, alto: Int
    }

    private let lock = NSLock()
    public var palanca = true
    public var sinFuncion = false
    public var habilitado = true
    public var tokenCaido = false
    public var sinRed = false
    public var nota = ""
    public var maxMotivacion = FotosInicio.maxMotivacion
    /// Estados forzados para las próximas subidas, en orden (503, 429, 400…). 0 = sin red en esa.
    public var proximasSubidas: [Int] = []
    /// Al registrar la próxima foto la sección se cierra (lo que pasa si Mati cierra el pedido mientras sube).
    public var cerrarAlSubir = false
    public var llamadas: [String] = []
    public var fotos: [Foto] = []
    public var notasRecibidas: [String] = []
    public var cabecerasUltimaSubida: [String: String] = [:]

    public init() {}

    public var llamadasFotosInicio: [String] { lock.withLock { llamadas.filter { $0.contains("inicio") } } }
    public var intentosDeSubida: Int { lock.withLock { llamadas.filter { $0 == "inicio/upload" }.count } }
    public func dePose(_ p: String) -> [Foto] { lock.withLock { fotos.filter { $0.pose == p } } }

    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let (status, cuerpo) = try lock.withLock { () throws -> (Int, String) in
            let f = ruta.components(separatedBy: "/").last ?? ""
            let nombre = ruta.contains("/inicio/") ? "inicio/\(f)" : f
            llamadas.append(nombre)
            if sinRed { throw URLError(.notConnectedToInternet) }
            return try atender(nombre, pedido)
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func json(_ v: JSONValue) -> String { String(decoding: (try? JSONEncoder().encode(v)) ?? Data(), as: UTF8.self) }
    private func cuerpo(_ p: URLRequest) -> JSONValue { p.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null }
    private func tokenValido(_ t: String?) -> Bool { !(t ?? "").isEmpty && !tokenCaido && habilitado }

    private func atender(_ nombre: String, _ p: URLRequest) throws -> (Int, String) {
        if nombre == "mypump_get_app_config" { return (200, #"{"fotos_inicio":\#(palanca)}"#) }
        if nombre.hasPrefix("mypump_fotos_inicio") && sinFuncion { return (404, #"{"code":"PGRST202","message":"no existe"}"#) }
        if nombre.hasPrefix("inicio/") && sinFuncion { return (404, #"{"ok":false}"#) }
        switch nombre {
        case "mypump_fotos_inicio_get":
            if tokenCaido { return (200, "null") }
            if !habilitado { return (200, #"{"habilitado":false}"#) }
            return (200, json(vista()))
        case "mypump_fotos_inicio_nota":
            let n = cuerpo(p)["p_nota"]?.comoTexto ?? ""
            notasRecibidas.append(n)
            if tokenCaido { return (200, "null") }
            if !habilitado { return (200, #"{"ok":false,"error":"no_habilitado"}"#) }
            nota = FotosInicio.notaRecortada(n)
            return (200, json(.objeto(["ok": .bool(true), "nota": .texto(nota)])))
        case "inicio/upload":
            return try subida(p)
        case "inicio/urls":
            guard tokenValido(cuerpo(p)["token"]?.comoTexto) else { return (403, #"{"ok":false}"#) }
            let filas = fotos.map { JSONValue.objeto(["id": .texto($0.id), "pose": .texto($0.pose), "url": .texto("https://ejemplo.invalid/inicio/\($0.id).jpg")]) }
            return (200, json(.objeto(["ok": .bool(true), "fotos": .lista(filas)])))
        case "inicio/borrar":
            let c = cuerpo(p)
            guard tokenValido(c["token"]?.comoTexto) else { return (403, #"{"ok":false}"#) }
            guard let f = fotos.first(where: { $0.id == c["foto_id"]?.comoTexto }) else { return (404, #"{"ok":false}"#) }
            guard f.pose == FotosInicio.motivacion else { return (400, #"{"ok":false,"error":"solo_motivacion"}"#) }
            fotos.removeAll { $0.id == f.id }
            return (200, #"{"ok":true}"#)
        case "mypump_get_cliente_info":
            return (200, #"[{"cliente_id":"c-fotos","nombre":"Cliente","perfil":"natural"}]"#)
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
        guard tokenValido(h["x-inicio-token"]) else { return (403, #"{"ok":false}"#) }
        guard let id = h["x-inicio-foto"], let pose = h["x-inicio-pose"], pose == FotosInicio.motivacion || FotosInicio.pose(pose) != nil else { return (400, #"{"ok":false}"#) }
        let bytes = p.httpBody ?? Data()
        if let ya = fotos.first(where: { $0.id == id }) { return ya.pose == pose ? (200, #"{"ok":true,"ya":true}"#) : (409, #"{"ok":false}"#) }
        guard Self.jpegEntero(bytes) else { return (400, #"{"ok":false,"error":"no_jpeg"}"#) }
        if bytes.count > 4 * 1024 * 1024 { return (413, #"{"ok":false,"error":"pesada"}"#) }
        let (ancho, alto) = Self.medidas(bytes)
        let lado = max(ancho, alto)
        if lado > 0 && lado < (pose == FotosInicio.motivacion ? FotosInicio.minLadoMotivacion : FotosInicio.minLado) { return (422, #"{"ok":false}"#) }
        if pose == FotosInicio.motivacion {
            if fotos.filter({ $0.pose == pose }).count >= maxMotivacion { return (413, #"{"ok":false,"error":"tope"}"#) }
        } else {
            fotos.removeAll { $0.pose == pose }   // la del cuerpo reemplaza a la de esa pose
        }
        fotos.append(Foto(id: id, pose: pose, bytes: bytes, tomada: h["x-inicio-tomada"], ancho: ancho, alto: alto))
        if cerrarAlSubir { cerrarAlSubir = false; habilitado = false }
        return (200, #"{"ok":true}"#)
    }

    private func vista() -> JSONValue {
        let completo = FotosInicio.poses.allSatisfy { p in fotos.contains { $0.pose == p.clave } }
        return .objeto([
            "habilitado": .bool(true), "completo": .bool(completo),
            "completado_en": completo ? .texto("2026-11-10T17:00:00+00:00") : .null,
            "nota": .texto(nota), "max_motivacion": .numero(Double(maxMotivacion)), "campo_del_futuro": .texto("no rompe"),
            "fotos": .lista(fotos.map {
                .objeto(["id": .texto($0.id), "pose": .texto($0.pose), "tomada_en": $0.tomada.map(JSONValue.texto) ?? .null,
                         "ancho": .numero(Double($0.ancho)), "alto": .numero(Double($0.alto))])
            }),
        ])
    }

    /// Empieza con FF D8 y termina con FF D9: lo mínimo de un JPEG entero.
    public static func jpegEntero(_ b: Data) -> Bool {
        let a = [UInt8](b)
        return a.count >= 4 && a[0] == 0xFF && a[1] == 0xD8 && a[a.count - 2] == 0xFF && a[a.count - 1] == 0xD9
    }

    /// Ancho y alto del primer SOF (0 y 0 si no se encuentra): como mide el servidor.
    public static func medidas(_ d: Data) -> (Int, Int) {
        let b = [UInt8](d)
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { return (0, 0) }
            let marca = b[i + 1]
            let largo = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if (0xC0...0xCF).contains(marca) && marca != 0xC4 && marca != 0xC8 && marca != 0xCC {
                return (Int(b[i + 7]) << 8 | Int(b[i + 8]), Int(b[i + 5]) << 8 | Int(b[i + 6]))
            }
            i += 2 + largo
        }
        return (0, 0)
    }

    /// Un JPEG de mentira que solo tiene la cabecera con el tamaño: alcanza para lo que mira el doble (y el servidor).
    public static func jpegDePrueba(ancho: Int = 1200, alto: Int = 1600, relleno: UInt8 = 7) -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08, UInt8(alto >> 8), UInt8(alto & 0xFF), UInt8(ancho >> 8), UInt8(ancho & 0xFF), 0x01, 0x01, 0x11, 0x00,
              relleno, 0xFF, 0xD9])
    }

    static let idFrente = "11111111-1111-4111-8111-111111111111"
    static let idPerfil = "22222222-2222-4222-8222-222222222222"
    static let idEspalda = "33333333-3333-4333-8333-333333333333"

    /// El estado de partida de cada escenario de las pruebas de interfaz.
    public static func escenario(_ nombre: String) -> DobleFotosInicio {
        let d = DobleFotosInicio()
        func foto(_ id: String, _ pose: String) -> Foto { Foto(id: id, pose: pose, bytes: Data(), tomada: "2026-11-09T10:00:00-03:00", ancho: 1200, alto: 1600) }
        switch nombre {
        case "apagado": d.palanca = false
        case "sinServidor": d.sinFuncion = true
        case "noHabilitado": d.habilitado = false
        case "tokenCaido": d.tokenCaido = true
        case "dos": d.fotos = [foto(idFrente, "frente"), foto(idPerfil, "perfil")]
        case "completo":
            d.fotos = [foto(idFrente, "frente"), foto(idPerfil, "perfil"), foto(idEspalda, "espalda")]
            d.nota = "Los hombros"
        case "topeMotivacion":
            d.fotos = (0..<FotosInicio.maxMotivacion).map { foto("4444444\($0)-4444-4444-8444-444444444444", FotosInicio.motivacion) }
        case "corte": d.proximasSubidas = [200, 0]
        case "rechazo": d.proximasSubidas = [400]
        case "reintento": d.proximasSubidas = [503]
        default: break    // "vacio": habilitado, sin nada
        }
        return d
    }
}
#endif
