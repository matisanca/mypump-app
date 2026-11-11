#if DEBUG
import Foundation
import MyPumpModelos
import MyPumpReglas

/// El servidor de estudios de mentira: sigue `estudios/CONTRATO_APP.md` en memoria (RPC y endpoints). Lo usan las pruebas del
/// kit y, con `-estudiosDePrueba <escenario>`, las de interfaz. Nunca toca la red y no tiene datos de nadie.
public final class DobleEstudios: Transporte, @unchecked Sendable {
    public struct Envio: Equatable {
        public var id: String
        public var pedidoId: String?
        public var estado = "borrador"
        public var archivos: [String: Data] = [:]
    }

    private let lock = NSLock()
    public var palanca = true
    public var sinFuncion = false
    public var habilitado = true
    public var tokenCaido = false
    public var sinRed = false
    /// Estados forzados para las próximas subidas, en orden (503, 429, 400…). 0 = sin red en esa.
    public var proximasSubidas: [Int] = []
    /// Respuestas forzadas para los próximos `enviar` («faltan_archivos»…).
    public var proximosEnviar: [String] = []
    public var topeDia = false
    /// Corre después de atender cada subida (para probar lo que pasa en medio de una pasada).
    public var alSubir: (@Sendable () async -> Void)?
    /// Corre antes de contestar `mypump_controles_get` (para apagar la palanca mientras la respuesta viaja).
    public var antesDeControles: (@Sendable () async -> Void)?
    public var llamadas: [String] = []
    public var hoy = "2026-11-10"
    public var proximoControl: JSONValue = .null
    public var pendientes: [[String: JSONValue]] = []
    public var ordenes: [[String: JSONValue]] = []
    public var estudios: [[String: JSONValue]] = []
    public var envios: [Envio] = []
    public var cabecerasUltimaSubida: [String: String] = [:]
    public var ultimoEnviar: JSONValue?
    public var ultimoHecho: JSONValue?
    public var urlsPedidas: [JSONValue] = []
    /// Los `p_ids` de cada `novedades_vistas`, en orden.
    public var vistasPedidas: [[String]] = []
    /// `controles_app` en la config. Sin prender, la app no llama a `mypump_controles_get`.
    public var palancaControles = false
    /// `mypump_controles_get` no existe (PGRST202).
    public var controlesSinFuncion = false
    /// Lo que contesta `mypump_controles_get` (sin próximo ni últimos, de entrada).
    public var controles: JSONValue = .objeto(["habilitado": .bool(true), "hoy": .texto("2026-11-10"), "proximo": .null, "ultimos": .lista([])])

    public init() {}

    public var llamadasEstudios: [String] { lock.withLock { llamadas.filter { $0.contains("estudios") } } }
    public var intentosDeSubida: Int { lock.withLock { llamadas.filter { $0 == "estudios/upload" }.count } }

    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let (status, cuerpo) = try lock.withLock { () throws -> (Int, Data) in
            let f = ruta.components(separatedBy: "/").last ?? ""
            let nombre = pedido.url?.host == Self.hostArchivos ? "archivo" : ruta.contains("/estudios/") ? "estudios/\(f)" : f
            llamadas.append(nombre)
            if sinRed { throw URLError(.notConnectedToInternet) }
            return try atender(nombre, pedido)
        }
        if ruta.hasSuffix("/estudios/upload") { await alSubir?() }
        if ruta.hasSuffix("/mypump_controles_get") { await antesDeControles?() }
        return (cuerpo, HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    static let hostArchivos = "archivos.ejemplo.invalid"

    private func json(_ v: JSONValue) -> Data { (try? JSONEncoder().encode(v)) ?? Data() }
    private func cuerpo(_ p: URLRequest) -> JSONValue { p.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null }

    private func atender(_ nombre: String, _ p: URLRequest) throws -> (Int, Data) {
        func t(_ s: String) -> Data { Data(s.utf8) }
        switch nombre {
        case "mypump_get_app_config":
            if !palanca { return (200, t(#"{"gimnasio_fotos":false}"#)) }
            return (200, t(palancaControles ? #"{"estudios_app":true,"controles_app":true}"# : #"{"estudios_app":true,"controles_app":false}"#))
        case "mypump_controles_get":
            if controlesSinFuncion { return (404, t(#"{"code":"PGRST202","message":"no existe"}"#)) }
            if tokenCaido { return (200, t("null")) }
            return (200, json(palancaControles ? controles : .objeto(["habilitado": .bool(false)])))
        case "mypump_get_cliente_info":   // una cuenta inventada, para las pruebas que arman `ModeloApp` entero
            return (200, t(#"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#))
        case _ where nombre.hasPrefix("mypump_estudios") && sinFuncion:
            return (404, t(#"{"code":"PGRST202","message":"no existe"}"#))
        case _ where nombre.hasPrefix("mypump_estudios") && tokenCaido:
            return (200, t("null"))
        case "mypump_estudios_get":
            if !habilitado { return (200, t(#"{"habilitado":false}"#)) }
            return (200, json(vista()))
        case "mypump_estudios_envio_nuevo":
            if !habilitado { return (200, t(#"{"ok":false,"error":"no_habilitado"}"#)) }
            let j = cuerpo(p)
            guard let id = j["p_id"]?.comoTexto else { return (400, t(#"{"code":"22023"}"#)) }
            if let e = envios.first(where: { $0.id == id }) {
                return (200, json(.objeto(["ok": .bool(true), "ya": .bool(true), "id": .texto(id), "estado": .texto(e.estado)])))
            }
            if topeDia { return (200, t(#"{"ok":false,"error":"tope_dia"}"#)) }
            envios.append(Envio(id: id, pedidoId: j["p_pedido_id"]?.comoTexto))
            return (200, json(.objeto(["ok": .bool(true), "ya": .bool(false), "id": .texto(id), "estado": .texto("borrador")])))
        case "mypump_estudios_enviar":
            let j = cuerpo(p)
            ultimoEnviar = j
            if !proximosEnviar.isEmpty { return (200, json(.objeto(["ok": .bool(false), "error": .texto(proximosEnviar.removeFirst())]))) }
            guard let i = envios.firstIndex(where: { $0.id == j["p_id"]?.comoTexto }) else { return (200, t(#"{"ok":false,"error":"no_encontrado"}"#)) }
            if envios[i].estado != "borrador" { return (200, t(#"{"ok":true,"ya":true,"estado":"enviado"}"#)) }
            if envios[i].archivos.isEmpty { return (200, t(#"{"ok":false,"error":"sin_archivos"}"#)) }
            if case .numero(let n)? = j["p_archivos"], envios[i].archivos.count < Int(n) { return (200, t(#"{"ok":false,"error":"faltan_archivos"}"#)) }
            envios[i].estado = "enviado"
            return (200, t(#"{"ok":true,"ya":false,"estado":"enviado"}"#))
        case "mypump_estudios_hecho":
            let j = cuerpo(p)
            ultimoHecho = j
            guard let i = pendientes.firstIndex(where: { $0["id"] == j["p_pedido_id"] }) else { return (200, t(#"{"ok":false,"error":"no_encontrado"}"#)) }
            guard let f = j["p_fecha"]?.comoTexto else {
                pendientes[i]["estado"] = .texto("pedido"); pendientes[i]["hecho_fecha"] = .null
                return (200, t(#"{"ok":true,"estado":"pedido"}"#))
            }
            guard let d = Estudios.Dia(f), let h = Estudios.Dia(hoy), d.numero <= h.numero + 1, d.numero >= h.numero - 120 else { return (200, t(#"{"ok":false,"error":"fecha"}"#)) }
            pendientes[i]["estado"] = .texto("hecho"); pendientes[i]["hecho_fecha"] = .texto(f)
            return (200, t(#"{"ok":true,"estado":"hecho"}"#))
        case "mypump_estudios_novedades_vistas":
            if !habilitado { return (200, t(#"{"ok":false,"error":"no_habilitado"}"#)) }
            guard case .lista(let l)? = cuerpo(p)["p_ids"] else { return (400, t(#"{"code":"22023"}"#)) }
            let ids = l.compactMap(\.comoTexto)
            vistasPedidas.append(ids)
            // Solo lo propio y lo que seguía sin ver; lo demás se ignora.
            var marcadas = 0
            for i in pendientes.indices where pendientes[i]["nuevo"] == .bool(true) && ids.contains(pendientes[i]["id"]?.comoTexto ?? "") { pendientes[i]["nuevo"] = .bool(false); marcadas += 1 }
            for i in ordenes.indices where ordenes[i]["nuevo"] == .bool(true) && ids.contains(ordenes[i]["id"]?.comoTexto ?? "") { ordenes[i]["nuevo"] = .bool(false); marcadas += 1 }
            return (200, json(.objeto(["ok": .bool(true), "marcadas": .numero(Double(marcadas))])))
        case "estudios/upload":
            return try subida(p)
        case "estudios/urls":
            let j = cuerpo(p)
            urlsPedidas.append(j)
            let id = j["id"]?.comoTexto ?? ""
            switch j["clase"]?.comoTexto {
            case "orden":
                guard ordenes.contains(where: { $0["id"]?.comoTexto == id && $0["vigente"] != .bool(false) }) else { return (404, t(#"{"ok":false}"#)) }
            case "estudio":
                guard let e = estudios.first(where: { $0["id"]?.comoTexto == id }) else { return (404, t(#"{"ok":false}"#)) }
                guard e["se_puede_abrir"] == .bool(true) else { return (409, t(#"{"ok":false,"error":"todavia_no"}"#)) }
            default: return (400, t(#"{"ok":false}"#))
            }
            let fila = JSONValue.objeto(["url": .texto("https://\(Self.hostArchivos)/\(id).pdf"), "mime": .texto("application/pdf")])
            return (200, json(.objeto(["ok": .bool(true), "archivos": .lista([fila]), "expira_en": .numero(600)])))
        case "archivo":
            return (200, Self.pdfDeEjemplo)
        default:
            return (200, t("[]"))
        }
    }

    private func subida(_ p: URLRequest) throws -> (Int, Data) {
        func t(_ s: String) -> (Int, Data) { (Int(s.prefix(3)) ?? 500, Data(s.dropFirst(4).utf8)) }
        if !proximasSubidas.isEmpty {
            let s = proximasSubidas.removeFirst()
            if s == 0 { throw URLError(.networkConnectionLost) }
            if s != 200 { return (s, Data(#"{"ok":false,"error":"forzado"}"#.utf8)) }
        }
        let h = p.allHTTPHeaderFields ?? [:]
        cabecerasUltimaSubida = h
        let datos = p.httpBody ?? Data()
        guard let id = h["x-estudios-archivo"], UUID(uuidString: id) != nil, let formato = Estudios.formato(datos), formato.mime == h["Content-Type"] else { return t(#"400 {"ok":false}"#) }
        guard let i = envios.firstIndex(where: { $0.id == h["x-estudios-envio"] }) else { return t(#"404 {"ok":false}"#) }
        guard envios[i].estado == "borrador" else { return t(#"409 {"ok":false}"#) }
        if datos.count > Estudios.topeMB * 1024 * 1024 { return t(#"413 {"ok":false}"#) }
        if envios[i].archivos[id] != nil || envios[i].archivos.values.contains(datos) { return t(#"200 {"ok":true,"ya":true}"#) }
        if envios[i].archivos.count >= Estudios.topeArchivos { return t(#"413 {"ok":false}"#) }
        envios[i].archivos[id] = datos
        return t(#"200 {"ok":true}"#)
    }

    private func vista() -> JSONValue {
        let filas = envios.map { e in
            JSONValue.objeto(["id": .texto(e.id), "estado": .texto(e.estado), "archivos": .numero(Double(e.archivos.count)),
                              "pedido_id": e.pedidoId.map(JSONValue.texto) ?? .null,
                              "enviado_en": e.estado == "borrador" ? .null : .texto("\(hoy)T15:00:00Z")])
        }
        // Como el servidor: pedidos a la vista (no los ya hechos) y órdenes vigentes que todavía no se vieron.
        let novedades = pendientes.filter { $0["nuevo"] == .bool(true) && $0["estado"] != .texto("hecho") }.count
            + ordenes.filter { $0["nuevo"] == .bool(true) && $0["vigente"] != .bool(false) }.count
        return .objeto([
            "habilitado": .bool(true), "hoy": .texto(hoy), "novedades": .numero(Double(novedades)),
            "topes": .objeto(["archivos_por_envio": .numero(20), "mb_por_archivo": .numero(20)]),
            "proximo_control": proximoControl,
            "pendientes": .lista(pendientes.map(JSONValue.objeto)), "ordenes": .lista(ordenes.map(JSONValue.objeto)),
            "estudios": .lista(estudios.map(JSONValue.objeto)), "envios": .lista(filas.reversed()),
        ])
    }

    // MARK: Datos de ejemplo (inventados: sin nombres ni resultados de nadie)

    /// Un PDF de una hoja en blanco con un renglón, armado a mano: es lo que «se baja» al tocar «Ver».
    public static let pdfDeEjemplo: Data = {
        let contenido = "BT /F1 20 Tf 72 720 Td (Orden de ejemplo) Tj ET"
        let objetos = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Length \(contenido.utf8.count) >>\nstream\n\(contenido)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ]
        var s = "%PDF-1.4\n"
        var posiciones: [Int] = []
        for (i, o) in objetos.enumerated() {
            posiciones.append(s.utf8.count)
            s += "\(i + 1) 0 obj\n\(o)\nendobj\n"
        }
        let xref = s.utf8.count
        s += "xref\n0 \(objetos.count + 1)\n0000000000 65535 f \n"
        for p in posiciones { s += String(format: "%010d 00000 n \n", p) }
        s += "trailer\n<< /Size \(objetos.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(s.utf8)
    }()

    static func id(_ n: Int) -> String { String(format: "%08d-0000-4000-8000-000000000000", n) }

    /// El estado de partida de cada escenario de las pruebas de interfaz.
    public static func escenario(_ nombre: String) -> DobleEstudios {
        let d = DobleEstudios()
        func pendiente(_ n: Int, _ tipo: String, _ titulo: String, desde: String? = nil, hasta: String, orden: Int? = nil, hecho: String? = nil, detalle: String? = nil) -> [String: JSONValue] {
            ["id": .texto(id(n)), "tipo": .texto(tipo), "titulo": .texto(titulo), "detalle": detalle.map(JSONValue.texto) ?? .null,
             "desde": desde.map(JSONValue.texto) ?? .null, "hasta": .texto(hasta), "estado": .texto(hecho == nil ? "pedido" : "hecho"),
             "hecho_fecha": hecho.map(JSONValue.texto) ?? .null, "orden_id": orden.map { .texto(id($0)) } ?? .null]
        }
        func orden(_ n: Int, _ tipo: String, _ titulo: String, emitida: String, vence: String, vigente: Bool = true) -> [String: JSONValue] {
            ["id": .texto(id(n)), "tipo": .texto(tipo), "titulo": .texto(titulo), "emitida": .texto(emitida), "vence": .texto(vence), "vigente": .bool(vigente)]
        }
        func estudio(_ n: Int, _ tipo: String, _ titulo: String, fecha: String?, hojas: Int, visto: Bool, abre: Bool) -> [String: JSONValue] {
            ["id": .texto(id(n)), "tipo": .texto(tipo), "titulo": .texto(titulo), "fecha": fecha.map(JSONValue.texto) ?? .null, "hojas": .numero(Double(hojas)),
             "estado": .texto(visto ? "visto" : "recibido"), "recibido_en": .texto("2026-11-04T13:02:11Z"), "se_puede_abrir": .bool(abre)]
        }
        switch nombre {
        case "apagado": d.palanca = false
        case "sinServidor": d.sinFuncion = true
        case "noHabilitado": d.habilitado = false
        case "vacio": break
        default:   // "completo" y sus variantes de subida
            d.proximoControl = .objeto(["tipo": .texto("laboratorio"), "titulo": .texto("Análisis de laboratorio"), "desde": .texto("2026-11-23"), "hasta": .texto("2026-11-29")])
            d.pendientes = [
                pendiente(1, "ecocardiograma", "Ecocardiograma", hasta: "2026-11-05"),
                pendiente(2, "laboratorio", "Análisis de laboratorio", desde: "2026-11-16", hasta: "2026-11-19", orden: 11),
                pendiente(3, "ergometria", "Ergometría", hasta: "2026-11-27", hecho: "2026-11-09"),
            ]
            d.ordenes = [
                orden(11, "laboratorio", "Análisis de laboratorio", emitida: "2026-11-03", vence: "2027-01-02"),
                orden(12, "ecocardiograma", "Ecocardiograma", emitida: "2026-10-20", vence: "2026-12-19"),
                orden(13, "ecografia", "Ecografía", emitida: "2026-08-20", vence: "2026-10-19", vigente: false),
            ]
            d.estudios = [
                estudio(21, "laboratorio", "Análisis de laboratorio", fecha: "2026-11-03", hojas: 4, visto: false, abre: false),
                estudio(22, "electrocardiograma", "Electrocardiograma", fecha: "2026-09-12", hojas: 1, visto: true, abre: true),
                estudio(23, "estudio_nuevo", "Estudio", fecha: nil, hojas: 2, visto: false, abre: false),
            ]
            var previo = Envio(id: id(31), estado: "enviado")
            previo.archivos = ["a": Data([1]), "b": Data([2]), "c": Data([3])]
            d.envios = [previo]
            if nombre == "topeDia" { d.topeDia = true }
            if nombre == "rechazo" { d.proximasSubidas = [400] }
            if nombre == "sinSenalAlSubir" { d.proximasSubidas = [0] }
            // Un pedido y su orden sin ver: la tarjeta de arriba dice «estudio nuevo», y adentro las dos llevan «Nuevo».
            if nombre == "novedad" { d.pendientes[1]["nuevo"] = .bool(true); d.ordenes[0]["nuevo"] = .bool(true) }
            // Solo una orden sin ver.
            if nombre == "ordenNueva" { d.ordenes[1]["nuevo"] = .bool(true) }
            // Solo una orden sin ver y nada por hacer.
            if nombre == "soloOrdenNueva" { d.pendientes = []; d.ordenes[1]["nuevo"] = .bool(true) }
            // Controles de salud (`controles_app`): apagada con un control cargado, prendida sin control, uno lejano, uno
            // dentro de la ventana de aviso y uno con las órdenes ya enviadas. Fechas inventadas, con hoy = 10/11.
            func control(_ fecha: String, _ avisar: String, _ estado: String) -> JSONValue {
                .objeto(["titulo_alumno": .texto("Control de salud"), "fecha_objetivo": .texto(fecha), "avisar_desde": .texto(avisar), "estado": .texto(estado)])
            }
            func controles(_ proximo: JSONValue) {
                d.controles = .objeto(["habilitado": .bool(true), "hoy": .texto(d.hoy), "proximo": proximo,
                                       "ultimos": .lista([control("2026-10-01", "2026-09-24", "revisado")])])
            }
            switch nombre {
            case "controlesApagado": controles(control("2026-11-16", "2026-11-09", "programado"))
            case "sinControl": d.palancaControles = true
            case "controlLejano": d.palancaControles = true; controles(control("2026-12-30", "2026-12-23", "programado"))
            case "controlEnVentana": d.palancaControles = true; controles(control("2026-11-16", "2026-11-09", "programado"))
            case "controlOrdenes": d.palancaControles = true; controles(control("2026-11-16", "2026-11-09", "ordenes_enviadas"))
            default: break
            }
        }
        return d
    }
}
#endif
