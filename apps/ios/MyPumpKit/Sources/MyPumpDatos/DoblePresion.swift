#if DEBUG
import Foundation
import MyPumpModelos
import MyPumpReglas

/// El servidor de presión de mentira: sigue `presion/CONTRATO_APP.md` en memoria. Lo usan las pruebas del kit y, con
/// `-presionDePrueba <escenario>`, las de interfaz. Nunca toca la red. Todos los datos son inventados.
public final class DoblePresion: Transporte, @unchecked Sendable {
    private let lock = NSLock()
    public var palanca = true
    public var sinFuncion = false
    public var habilitado = true
    public var sinRed = false
    public var tokenCaido = false
    /// Estados forzados para las próximas escrituras de sesión o de síntoma, en orden. 0 = sin red en esa.
    public var proximas: [Int] = []
    /// La próxima escritura contesta `{"ok": false, "error": …}`.
    public var proximoError: String?
    public var llamadas: [String] = []

    public var hoy = FechaLocal.hoy()
    public var fotos = false
    public var aparato: [String: JSONValue]?
    public var circunferencia: Double?
    public var serie: [String: JSONValue]?
    /// Las sesiones guardadas, la más nueva primero, con la forma de `p_sesion` más `fecha`.
    public var sesiones: [[String: JSONValue]] = []
    public var sintomas: [[String: JSONValue]] = []
    public var tensiometros: JSONValue = .null
    /// Cada `p_sesion` recibido, tal cual.
    public var recibidas: [JSONValue] = []

    public init() {}

    public var llamadasPresion: [String] { lock.withLock { llamadas.filter { $0.contains("presion") } } }
    public func cuantas(_ nombre: String) -> Int { lock.withLock { llamadas.filter { $0 == nombre }.count } }

    public func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let nombre = pedido.url?.path.components(separatedBy: "/").last ?? ""
        let (status, cuerpo) = try lock.withLock { () throws -> (Int, String) in
            llamadas.append(nombre)
            if sinRed { throw URLError(.notConnectedToInternet) }
            return try atender(nombre, pedido)
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func json(_ v: JSONValue) -> String { String(decoding: (try? JSONEncoder().encode(v)) ?? Data(), as: UTF8.self) }
    private func cuerpo(_ p: URLRequest) -> JSONValue { p.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null }
    private func n(_ i: Int) -> JSONValue { .numero(Double(i)) }

    private func atender(_ nombre: String, _ p: URLRequest) throws -> (Int, String) {
        switch nombre {
        case "mypump_get_app_config":
            return (200, palanca ? #"{"presion_app":true}"# : #"{"presion_app":false}"#)
        case _ where nombre.hasPrefix("mypump_presion") && sinFuncion:
            return (404, #"{"code":"PGRST202","message":"no existe"}"#)
        case _ where nombre.hasPrefix("mypump_presion") && tokenCaido:
            return (200, "null")
        case "mypump_presion_get":
            return (200, json(estado()))
        case "mypump_presion_aparato":
            let a = cuerpo(p)["p_aparato"]
            guard let tipo = a?["tipo"]?.comoTexto, ["brazo", "muneca", "reloj_anillo_otro"].contains(tipo) else { return (200, #"{"ok":false,"error":"datos"}"#) }
            aparato = ["id": .texto(UUID().uuidString.lowercased()), "tipo": .texto(tipo), "marca": a?["marca"] ?? .null, "modelo": a?["modelo"] ?? .null,
                       "modelo_codigo": a?["modelo_codigo"] ?? .null, "manguito_min_cm": a?["manguito_min_cm"] ?? .null, "manguito_max_cm": a?["manguito_max_cm"] ?? .null,
                       "manguito_validado_min_cm": .null, "manguito_validado_max_cm": .null, "validado": .texto("sin_revisar")]
            return (200, json(.objeto(["ok": .bool(true), "estado": estado()])))
        case "mypump_presion_medida":
            guard let cm = cuerpo(p)["p_cm"]?.comoNumero, cm >= 20, cm <= 70 else { return (200, #"{"ok":false,"error":"datos"}"#) }
            circunferencia = cm
            serie?["medida_pedida"] = .bool(false)
            return (200, json(.objeto(["ok": .bool(true), "estado": estado()])))
        case "mypump_presion_sesion":
            if let f = try forzada() { return f }
            return guardarSesion(cuerpo(p)["p_sesion"] ?? .null)
        case "mypump_presion_sintoma":
            if let f = try forzada() { return f }
            guard let s = cuerpo(p)["p_sintoma"], case .objeto(let o) = s, let id = s["id"]?.comoTexto, !id.isEmpty else { return (200, #"{"ok":false,"error":"datos"}"#) }
            if !sintomas.contains(where: { $0["id"]?.comoTexto == id }) { sintomas.append(o) }
            return (200, #"{"ok":true}"#)
        default:
            return (200, "[]")
        }
    }

    private func forzada() throws -> (Int, String)? {
        if !proximas.isEmpty {
            let s = proximas.removeFirst()
            if s == 0 { throw URLError(.networkConnectionLost) }
            if s != 200 { return (s, #"{"message":"forzado"}"#) }
        }
        if let e = proximoError { proximoError = nil; return (200, #"{"ok":false,"error":"\#(e)"}"#) }
        return nil
    }

    /// Idempotente por `id`; las tomas ya guardadas (por `orden`) no se pisan.
    private func guardarSesion(_ s: JSONValue) -> (Int, String) {
        recibidas.append(s)
        guard case .objeto(var nueva) = s, let id = s["id"]?.comoTexto, !id.isEmpty, case .lista(let tomas)? = s["tomas"], !tomas.isEmpty else { return (200, #"{"ok":false,"error":"datos"}"#) }
        guard let a = aparato, a["tipo"]?.comoTexto != "reloj_anillo_otro" else { return (200, #"{"ok":false,"error":"aparato"}"#) }
        for t in tomas where Presion.validarToma(sis: t["sis"]?.comoNumero, dia: t["dia"]?.comoNumero, pulso: t["pulso"]?.comoNumero) == .imposible {
            return (200, #"{"ok":false,"error":"imposible"}"#)
        }
        if let sid = s["serie_id"]?.comoTexto, sid != serie?["id"]?.comoTexto { return (200, #"{"ok":false,"error":"serie"}"#) }
        if let i = sesiones.firstIndex(where: { $0["id"]?.comoTexto == id }) {
            var juntas: [JSONValue] = []
            if case .lista(let viejas)? = sesiones[i]["tomas"] { juntas = viejas }
            for t in tomas where !juntas.contains(where: { $0["orden"] == t["orden"] }) { juntas.append(t) }
            nueva["tomas"] = .lista(juntas)
            nueva["fecha"] = sesiones[i]["fecha"] ?? .texto(hoy)
            sesiones[i] = nueva
        } else {
            nueva["fecha"] = .texto(hoy)
            sesiones.insert(nueva, at: 0)
        }
        recalcular()
        return (200, json(.objeto(["ok": .bool(true), "estado": estado()])))
    }

    private func deLaSerie() -> [Presion.Sesion] {
        guard let sid = serie?["id"]?.comoTexto else { return [] }
        return sesiones.filter { $0["serie_id"]?.comoTexto == sid }.map { Presion.Sesion(.objeto($0)) }
    }

    /// El avance de la serie, con la misma regla que el teléfono.
    private func recalcular() {
        guard var s = serie else { return }
        let r = Presion.resumenSerie(Presion.EntradaSerie(tipo: s["tipo"]?.comoTexto, tomasObjetivo: s["tomas_objetivo"]?.comoNumero.map { Int($0) },
                                                          fechaInicio: s["fecha_inicio"]?.comoTexto, sesiones: deLaSerie()))
        s["dias"] = .lista(r.dias.map(JSONValue.texto))
        s["faltan"] = n(r.faltan)
        s["estado"] = .texto(r.dias.isEmpty ? "pendiente" : "en_curso")
        // Hechas en una sesión de la serie, ya no faltan.
        if sesiones.contains(where: { $0["tipo"]?.comoTexto == "ortostatica" }) { s["ortostatica"] = .null }
        if sesiones.contains(where: { $0["tipo"]?.comoTexto == "comparacion_brazos" }) { s["comparar_brazos"] = .bool(false) }
        serie = s
    }

    private func estado() -> JSONValue {
        guard habilitado else { return .objeto(["habilitado": .bool(false)]) }
        var pendiente = JSONValue.null
        for s in sesiones where s["fecha"]?.comoTexto == hoy {
            let ev = Presion.evaluarSesion(Presion.Sesion(.objeto(s)))
            if ev.paso == .repetir || ev.paso == .repetirConLista {
                pendiente = .objeto(["sesion_id": s["id"] ?? .null, "nivel": .texto(ev.paso == .repetirConLista ? "urgencia" : "alta"), "desde": s["inicio"] ?? .null])
                break
            }
        }
        let lista: [JSONValue] = sesiones.prefix(30).map { s in
            let ev = Presion.evaluarSesion(Presion.Sesion(.objeto(s)))
            var tomas: [JSONValue] = []
            if case .lista(let l)? = s["tomas"] {
                tomas = l.map { t in .objeto(["orden": t["orden"] ?? .null, "posicion": t["posicion"] ?? .null, "sis": t["sis"] ?? .null, "dia": t["dia"] ?? .null,
                                              "pulso": t["pulso"] ?? .null, "latido_irregular": t["latido_irregular"] ?? .bool(false)]) }
            }
            return .objeto(["id": s["id"] ?? .null, "serie_id": s["serie_id"] ?? .null, "fecha": s["fecha"] ?? .null, "tipo": s["tipo"] ?? .null,
                            "cuenta": .bool(ev.cuenta), "tomas": .lista(tomas)])
        }
        return .objeto(["habilitado": .bool(true), "fotos": .bool(fotos), "hoy": .texto(hoy), "aparato": aparato.map(JSONValue.objeto) ?? .null,
                        "circunferencia_brazo_cm": circunferencia.map(JSONValue.numero) ?? .null, "serie": serie.map(JSONValue.objeto) ?? .null,
                        "sesiones": .lista(lista), "pendiente": pendiente, "tensiometros": tensiometros])
    }

    // MARK: Datos de ejemplo (inventados, sin nombres reales)

    public static let idSerie = "33333333-3333-4333-8333-333333333333"

    private static func dia(_ atras: Int) -> String { DiaCalendario.texto((DiaCalendario.numero(FechaLocal.hoy()) ?? 0) - atras) }

    private func ponerAparato(_ tipo: String = "brazo", validado: String = "si") {
        aparato = ["id": .texto("44444444-4444-4444-8444-444444444444"), "tipo": .texto(tipo), "marca": .texto("Marca de ejemplo"), "modelo": .texto("Modelo A"),
                   "modelo_codigo": .texto("AB-1234-XY"), "manguito_min_cm": .numero(22), "manguito_max_cm": .numero(42),
                   "manguito_validado_min_cm": validado == "si" ? .numero(22) : .null, "manguito_validado_max_cm": validado == "si" ? .numero(42) : .null,
                   "validado": .texto(validado)]
        circunferencia = 35
    }

    private func ponerSerie(_ tipo: String = "estandar", inicioHace: Int = 0) {
        serie = ["id": .texto(Self.idSerie), "motivo": .texto("inicio"), "tipo": .texto(tipo), "estado": .texto("pendiente"), "tomas_objetivo": n(3),
                 "fecha_inicio": .texto(Self.dia(inicioHace)), "fecha_limite": .texto(Self.dia(inicioHace - 6)), "brazo": .texto("izq"), "ortostatica": .null,
                 "comparar_brazos": .bool(false), "medida_pedida": .bool(false), "dias": .lista([]), "faltan": n(3)]
    }

    private func ponerSesion(hace: Int, tipo: String = "estandar", enSerie: Bool = true, _ tomas: [(Int, Int, Int)]) {
        let id = UUID().uuidString.lowercased()
        let l: [JSONValue] = tomas.enumerated().map { i, t in
            .objeto(["orden": n(i + 1), "posicion": .texto("sentado"), "brazo": .texto("izq"), "sis": n(t.0), "dia": n(t.1), "pulso": n(t.2), "latido_irregular": .bool(false)])
        }
        sesiones.insert(["id": .texto(id), "serie_id": enSerie ? .texto(Self.idSerie) : .null, "tipo": .texto(tipo), "fecha": .texto(Self.dia(hace)),
                         "inicio": .texto("\(Self.dia(hace))T11:02:00Z"),
                         "previo": .objeto(["cafeina": .bool(false), "fumo": .bool(false), "comida": .bool(false), "ejercicio": .bool(false)]),
                         "reposo_cumplido": .bool(true), "temporizador_salteado": .bool(false), "entreno_entre_dosis_y_toma": tipo == "bajo_efecto" ? .bool(false) : .null,
                         "sintomas": .lista([]), "lista_espera": .null, "tomas": .lista(l)], at: 0)
        recalcular()
    }

    /// El estado de partida de cada escenario de las pruebas de interfaz.
    public static func escenario(_ nombre: String) -> DoblePresion {
        let d = DoblePresion()
        switch nombre {
        case "apagado": d.palanca = false
        case "sinServidor": d.sinFuncion = true
        case "sinSerie": d.ponerAparato()
        case "serie0": d.ponerAparato(); d.ponerSerie()
        case "serie2":
            d.ponerAparato(); d.ponerSerie(inicioHace: 2)
            d.ponerSesion(hace: 2, [(124, 78, 62)]); d.ponerSesion(hace: 1, [(128, 80, 64)])
        case "pendienteUrgencia":
            d.ponerAparato(); d.ponerSerie(inicioHace: 1)
            d.ponerSesion(hace: 1, [(126, 79, 60)]); d.ponerSesion(hace: 0, [(184, 121, 88)])
        case "hoyListo":
            d.ponerAparato(); d.ponerSerie(inicioHace: 1)
            d.ponerSesion(hace: 1, [(126, 79, 60)]); d.ponerSesion(hace: 0, [(124, 78, 62)])
        case "pendienteAlta":
            d.ponerAparato(); d.ponerSerie(inicioHace: 1)
            d.ponerSesion(hace: 1, [(126, 79, 60)]); d.ponerSesion(hace: 0, [(164, 98, 70)])
        case "completa":
            d.ponerAparato(); d.ponerSerie(inicioHace: 3)
            d.ponerSesion(hace: 3, [(124, 78, 62)]); d.ponerSesion(hace: 2, [(128, 80, 64)]); d.ponerSesion(hace: 1, [(122, 76, 60)])
        case "muneca": d.ponerAparato("muneca"); d.ponerSerie()
        case "noValidado": d.ponerAparato(validado: "no"); d.ponerSerie()
        case "reloj": d.ponerAparato("reloj_anillo_otro", validado: "no")
        case "bajoEfecto": d.ponerAparato(); d.ponerSerie("bajo_efecto")
        case "ortostatica": d.ponerAparato(); d.ponerSerie(); d.serie?["ortostatica"] = .texto("acostado_parado")
        case "brazos": d.ponerAparato(); d.ponerSerie(); d.serie?["comparar_brazos"] = .bool(true)
        case "medirDeNuevo": d.ponerAparato(); d.ponerSerie(); d.serie?["medida_pedida"] = .bool(true)
        case "conLista":
            d.ponerAparato(); d.ponerSerie()
            d.tensiometros = .objeto(["version": .texto("ejemplo"), "tramos": .objeto([
                "estandar": .lista([.objeto(["nombre": .texto("Marca de ejemplo Modelo A"), "codigo": .texto("AB-1234-XY"), "pais": .texto("AR"), "nota": .null])]),
                "grande": .lista([.objeto(["nombre": .texto("Marca de ejemplo Modelo B"), "codigo": .texto("CD-5678-ZW"), "pais": .texto("AR"), "nota": .texto("Manguito de 22 a 42 cm")])]),
                "extra_grande": .lista([]), "mas_52": .lista([]),
            ])])
        default: break    // "vacio": habilitado, sin aparato ni medida
        }
        return d
    }
}
#endif
