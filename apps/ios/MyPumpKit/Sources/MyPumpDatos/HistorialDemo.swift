import Foundation
import MyPumpModelos
import MyPumpReglas

/// El historial INVENTADO de la demo sin cuenta («Ver demo», la que mira la revisión de las tiendas): ocho semanas de un
/// alumno que no existe, de `apps/shared/demo/historial.json` (lo genera `scripts/nativa/generar-demo-historial.py`), que
/// la app trae empaquetado. Los `dia` son relativos a hoy (0 = hoy, -1 = ayer): acá se convierten a fechas locales, así el
/// historial nunca queda viejo. Nada de esto viaja ni se escribe, y nunca se mezcla con una cuenta: solo con `esDemo`.
public struct HistorialDemo: Sendable {
    /// Las series por la clave del ejercicio, de la más nueva a la más vieja (como las da `get_historico_por_clave`).
    public let porClave: [String: [RegistroHistorico]]
    /// El peso (`peso_kg`) y los pasos por día, con la forma de `mypump_get_salud`.
    public let salud: [FilaSalud]
    /// El chat con Mati (`autor: coach` = Mati), del más viejo al más nuevo.
    public let chat: [MensajeChat]
    /// Las metas del plan de la demo (pasos por día y ritmo de peso).
    public let metas: MetasPlan?
    /// Las devoluciones de Mati (`semanas_atras: 1` = el lunes de la semana pasada).
    public let devoluciones: EstadoDevolucion?
    /// La respuesta de `mypump_lista_previa` de la demo, tal cual.
    public let listaPrevia: JSONValue?

    /// Todas las series, sin agrupar.
    public var historial: [RegistroHistorico] { porClave.values.flatMap { $0 } }

    public init?(json: Data, ahora: Date = Date(), zona: TimeZone = .current) {
        guard let raiz = try? JSONDecoder().decode(JSONValue.self, from: json), case .objeto = raiz else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let hoy = cal.startOfDay(for: ahora)
        func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { return l }; return [] }
        func entero(_ j: JSONValue?) -> Int? {
            guard case .numero(let n)? = j, n.isFinite, n == n.rounded(), abs(n) < 100_000 else { return nil }
            return Int(n)
        }
        /// El día relativo como fecha local (al mediodía, para que un cambio de hora no lo corra).
        func fecha(_ dia: Int) -> Date? { cal.date(byAdding: .day, value: dia, to: hoy) }
        func ymd(_ dia: Int) -> String? { fecha(dia).map { FechaLocal.hoy($0.addingTimeInterval(12 * 3600), zona: zona) } }
        /// El instante de un día relativo a una hora «HH:MM» local (más unos minutos), en ISO con la zona del teléfono.
        func instante(_ dia: Int, _ hora: String?, masMinutos: Int = 0) -> String? {
            let p = (hora ?? "12:00").split(separator: ":").compactMap { Int($0) }
            guard let base = fecha(dia), p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]),
                  let d = cal.date(bySettingHour: p[0], minute: p[1], second: 0, of: base)?.addingTimeInterval(Double(masMinutos) * 60) else { return nil }
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
            let seg = zona.secondsFromGMT(for: d)
            return String(format: "%04d-%02d-%02dT%02d:%02d:%02d%@%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0,
                          c.minute ?? 0, c.second ?? 0, seg < 0 ? "-" : "+", abs(seg) / 3600, abs(seg) % 3600 / 60)
        }
        func decodificar<T: Decodable>(_ filas: [JSONValue], _ tipo: T.Type) -> [T] {
            (try? JSONDecoder().decode([T].self, from: JSONEncoder().encode(JSONValue.lista(filas)))) ?? []
        }

        // Entreno: una fila por serie.
        var porClave: [String: [JSONValue]] = [:]
        for e in lista(raiz["entreno"]) {
            guard let nombre = e["nombre"]?.comoTexto else { continue }
            let clave = ClaveEjercicio.de(nombre)
            guard !clave.isEmpty else { continue }
            for s in lista(e["sesiones"]) {
                guard let dia = entero(s["dia"]), dia < 0 else { continue }   // hoy no hay sesión: lo de hoy lo carga quien mira
                for (i, serie) in lista(s["series"]).enumerated() {
                    guard let kg = serie["kg"]?.comoNumero, let reps = entero(serie["reps"]),
                          let cuando = instante(dia, s["hora"]?.comoTexto, masMinutos: 3 * i) else { continue }
                    var fila: [String: JSONValue] = ["clave": .texto(clave), "registrado_en": .texto(cuando), "peso_kg": .numero(kg),
                                                     "reps_realizadas": .numero(Double(reps)), "serie_numero": .numero(Double(i + 1)),
                                                     "ejercicio_nombre": .texto(nombre)]
                    if let id = e["ejercicio_id"]?.comoTexto { fila["ejercicio_id"] = .texto(id) }
                    porClave[clave, default: []].append(.objeto(fila))
                }
            }
        }
        self.porClave = porClave.mapValues { filas in
            // De la más nueva a la más vieja; dentro del día, en el orden de las series.
            decodificar(filas, RegistroHistorico.self).sorted {
                let (a, b) = (String($0.registradoEn.prefix(10)), String($1.registradoEn.prefix(10)))
                return a != b ? a > b : ($0.serie ?? 0) < ($1.serie ?? 0)
            }
        }

        // Salud: peso y pasos por día.
        var filasSalud: [JSONValue] = []
        for p in lista(raiz["peso"]) {
            guard let dia = entero(p["dia"]), dia <= 0, let f = ymd(dia), let kg = p["kg"]?.comoNumero else { continue }
            filasSalud.append(.objeto(["fecha": .texto(f), "tipo": .texto("peso_kg"), "valor": .numero(kg), "fuente": .texto("manual")]))
        }
        for p in lista(raiz["pasos"]) {
            guard let dia = entero(p["dia"]), dia <= 0, let f = ymd(dia), let n = p["pasos"]?.comoNumero else { continue }
            filasSalud.append(.objeto(["fecha": .texto(f), "tipo": .texto("pasos"), "valor": .numero(n), "fuente": .texto("apple_health")]))
        }
        salud = decodificar(filasSalud, FilaSalud.self)

        // Chat.
        var mensajes: [JSONValue] = []
        for (i, m) in lista(raiz["chat"]).enumerated() {
            guard let dia = entero(m["dia"]), dia <= 0, let texto = m["texto"]?.comoTexto, let autor = m["autor"]?.comoTexto,
                  autor == "coach" || autor == "cliente", let cuando = instante(dia, m["hora"]?.comoTexto) else { continue }
            mensajes.append(.objeto(["id": .texto("demo-\(i + 1)"), "autor": .texto(autor), "contenido": .texto(texto),
                                     "leido_por_cliente": .bool(true), "created_at": .texto(cuando)]))
        }
        chat = decodificar(mensajes, MensajeChat.self).sorted { (FechaJS.leer($0.createdAt) ?? .distantPast) < (FechaJS.leer($1.createdAt) ?? .distantPast) }

        // Metas del plan.
        let pasos = entero(raiz["metas"]?["meta_pasos_dia"])
        let m = MetasPlan(metaPasos: pasos, ritmoKgSemana: raiz["metas"]?["ritmo_peso_kg_semana"]?.comoNumero)
        metas = m.vacio ? nil : m

        // Devoluciones: la semana que comenta y el lunes siguiente como día de publicación.
        let diasDesdeLunes = (cal.component(.weekday, from: hoy) + 5) % 7
        var devs: [JSONValue] = []
        for (i, d) in lista(raiz["devoluciones"]).enumerated() {
            guard let atras = entero(d["semanas_atras"]), atras >= 1, let texto = d["texto"]?.comoTexto,
                  let lunes = ymd(-diasDesdeLunes - 7 * atras), let publicada = ymd(-diasDesdeLunes - 7 * (atras - 1)) else { continue }
            devs.append(.objeto(["id": .texto("demo-\(i + 1)"), "semana_lunes": .texto(lunes), "texto": .texto(texto),
                                 "publicado_en": .texto(publicada + "T14:00:00Z")]))
        }
        devoluciones = devs.isEmpty ? nil : EstadoDevolucion(.objeto(["habilitado": .bool(true), "devoluciones": .lista(devs)]))

        listaPrevia = raiz["lista_previa"]
    }
}
