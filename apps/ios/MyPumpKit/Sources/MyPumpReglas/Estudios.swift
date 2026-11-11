import Foundation
import MyPumpModelos

/// «Estudios y órdenes»: la lógica pura que comparten iOS y Android (`apps/shared/vectores/estudios.json`). El contrato está en
/// `estudios/CONTRATO_APP.md`; el servidor, en `supabase/propuestas/nativa_estudios.sql`. Acá no hay valores, rangos ni
/// interpretación: documentos, fechas y estados.
public enum Estudios {
    public static let maxPx = 2400
    public static let calidad = 0.8
    public static let topeArchivos = 20
    public static let topeMB = 20

    // MARK: Fechas

    /// Un día de calendario (`2026-11-19`), sin hora ni zona: así llega del servidor y así se compara.
    public struct Dia: Equatable, Comparable, Hashable, Sendable {
        public let anio: Int, mes: Int, dia: Int

        /// Acepta `AAAA-MM-DD` y lo que venga pegado detrás (una hora). nil si no es una fecha que exista.
        public init?(_ texto: String?) {
            guard let texto else { return nil }
            let p = texto.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
            guard texto.count >= 10, p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
                  let a = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
                  a >= 1900, a <= 9999, (1...12).contains(m), d >= 1, d <= Dia.diasDelMes(a, m) else { return nil }
            anio = a; mes = m; dia = d
        }

        /// El día de un instante (`recibido_en`, `enviado_en`) en la zona del teléfono.
        public init?(instante texto: String?, zona: TimeZone = .current) {
            guard let texto, let f = Dia.instante(texto) else { return nil }
            var c = Calendar(identifier: .gregorian)
            c.timeZone = zona
            let k = c.dateComponents([.year, .month, .day], from: f)
            guard let a = k.year, let m = k.month, let d = k.day else { return nil }
            anio = a; mes = m; dia = d
        }

        private static func instante(_ s: String) -> Date? {
            let conFraccion = ISO8601DateFormatter()
            conFraccion.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let f = conFraccion.date(from: s) { return f }
            let sin = ISO8601DateFormatter()
            sin.formatOptions = [.withInternetDateTime]
            return sin.date(from: s)
        }

        static func diasDelMes(_ a: Int, _ m: Int) -> Int {
            switch m {
            case 2: return (a % 4 == 0 && a % 100 != 0) || a % 400 == 0 ? 29 : 28
            case 4, 6, 9, 11: return 30
            default: return 31
            }
        }

        /// Días desde el 1/1/1970 (calendario gregoriano), para restar fechas.
        public var numero: Int {
            let a = mes <= 2 ? anio - 1 : anio
            let era = (a >= 0 ? a : a - 399) / 400
            let yoe = a - era * 400
            let doy = (153 * (mes + (mes > 2 ? -3 : 9)) + 2) / 5 + dia - 1
            let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            return era * 146097 + doe - 719468
        }

        /// 0 = domingo … 6 = sábado.
        public var diaSemana: Int { ((numero % 7) + 11) % 7 }

        public static func < (a: Dia, b: Dia) -> Bool { (a.anio, a.mes, a.dia) < (b.anio, b.mes, b.dia) }

        public var iso: String { String(format: "%04d-%02d-%02d", anio, mes, dia) }
        /// «19/11»: sin ceros y sin año.
        public var corta: String { "\(dia)/\(mes)" }
        /// «jueves 19/11».
        public var conDia: String { "\(Dia.nombres[diaSemana]) \(corta)" }

        static let nombres = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
    }

    public struct TextoFecha: Equatable, Sendable {
        public let texto: String
        /// La fecha ya pasó: va en ámbar, nunca en rojo ni con tono de alarma.
        public let pasada: Bool
    }

    /// Cuándo hay que hacer un pendiente. Sin fecha límite no se dice nada.
    public static func fechaPendiente(desde: Dia?, hasta: Dia?, hoy: Dia?) -> TextoFecha? {
        guard let hasta else { return nil }
        if let hoy, hasta < hoy { return TextoFecha(texto: "Era para el \(hasta.conDia)", pasada: true) }
        if let desde, desde < hasta { return TextoFecha(texto: "Entre el \(desde.conDia) y el \(hasta.conDia)", pasada: false) }
        return TextoFecha(texto: "Antes del \(hasta.conDia)", pasada: false)
    }

    /// Cuándo es el próximo control: una semana se dice por su primer día; más largo, de punta a punta.
    public static func fechaControl(desde: Dia?, hasta: Dia?) -> String? {
        switch (desde, hasta) {
        case (let d?, let h?): return h.numero - d.numero <= 7 ? "Semana del \(d.corta)" : "Entre el \(d.conDia) y el \(h.conDia)"
        case (let d?, nil): return "Semana del \(d.corta)"
        case (nil, let h?): return "Antes del \(h.conDia)"
        default: return nil
        }
    }

    public static func hecho(_ fecha: Dia?) -> String {
        fecha.map { "Hecho el \($0.corta). Falta subir el resultado." } ?? "Hecho. Falta subir el resultado."
    }

    public static func emitida(_ d: Dia?) -> String? { d.map { "Emitida el \($0.corta)" } }
    public static func valeHasta(_ d: Dia?) -> String? { d.map { "Vale hasta el \($0.corta)" } }
    /// «Emitida el 3/11 · Vale hasta el 2/1», con lo que haya.
    public static func detalleOrden(_ o: OrdenEstudio) -> String {
        [emitida(o.emitida), valeHasta(o.vence)].compactMap { $0 }.joined(separator: " · ")
    }

    public static func hojas(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return n == 1 ? "1 hoja" : "\(n) hojas"
    }
    public static func archivos(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return n == 1 ? "1 archivo" : "\(n) archivos"
    }

    /// «3/11 · 4 hojas», «Sin fecha · 1 hoja».
    public static func detalleEstudio(_ e: EstudioRecibido) -> String {
        [e.fecha?.corta ?? TextosEstudios.sinFecha, hojas(e.hojas)].compactMap { $0 }.joined(separator: " · ")
    }

    /// «Envío del 10/11».
    public static func tituloEnvio(_ e: EnvioRecibido) -> String { e.enviado.map { "Envío del \($0.corta)" } ?? "Envío" }
    /// Lo que lee VoiceOver de un envío: «Envío del 10/11 · 3 archivos · Recibido».
    public static func lineaEnvio(_ e: EnvioRecibido) -> String {
        [tituloEnvio(e), archivos(e.archivos), TextosEstudios.recibido].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Qué se muestra

    public struct Bloques: Equatable, Sendable {
        public let proximoControl, pendientes, ordenes, estudios: Bool
        /// Nada de nada: va el texto de bienvenida (el botón de subir está siempre).
        public var vacio: Bool { !proximoControl && !pendientes && !ordenes && !estudios }
    }

    public static func bloques(_ e: EstadoEstudios) -> Bloques {
        Bloques(proximoControl: e.proximoControl != nil, pendientes: !e.pendientes.isEmpty, ordenes: !e.ordenes.isEmpty,
                estudios: !e.estudios.isEmpty || !e.enviosVisibles.isEmpty)
    }

    // MARK: Novedades

    /// El `destino` del aviso al teléfono y la escena del link (`?scene=estudios`).
    public static let destino = "estudios"

    /// La tarjeta a la que hay que llevar al alumno dentro de Estudios.
    public enum Ancla: Equatable, Hashable, Sendable {
        case pendiente(String), orden(String)

        public var id: String {
            switch self {
            case .pendiente(let i), .orden(let i): i
            }
        }
    }

    /// La novedad de Estudios para una lista de novedades del plan: el texto y a dónde lleva.
    public struct Novedad: Equatable, Sendable {
        public let titulo: String
        public let destino: String
    }

    /// La tarjeta de arriba de la primera pestaña.
    public struct TarjetaInicio: Equatable, Sendable {
        public let titulo: String
        public let boton: String
        /// Hay algo sin ver (`novedades > 0`); si no, es el recordatorio de lo que falta hacer.
        public let nueva: Bool
    }

    /// El punto de la pestaña y de la fila de Mis datos: mientras el servidor diga que hay algo sin ver.
    public static func hayNovedad(_ e: EstadoEstudios) -> Bool { e.novedades > 0 }

    /// Los ids (pedidos y órdenes, mezclados) que el alumno todavía no vio: lo único que se manda a marcar.
    public static func nuevas(_ e: EstadoEstudios) -> [String] {
        e.pendientes.filter(\.nuevo).map(\.id) + e.ordenes.filter(\.nuevo).map(\.id)
    }

    /// Con algo sin ver: «Tenés un estudio nuevo para hacer» si hay un pedido nuevo y «Tenés una orden nueva» si lo nuevo
    /// son solo órdenes. Ninguno dice qué estudio ni por qué. Si el servidor cuenta novedades y no marca ninguna fila, se
    /// decide por lo que hay: con pedidos, el estudio; sin pedidos, la orden.
    public static func novedad(_ e: EstadoEstudios) -> Novedad? {
        guard hayNovedad(e) else { return nil }
        let pedido = e.pendientes.contains(where: \.nuevo) || (!e.ordenes.contains(where: \.nuevo) && !e.pendientes.isEmpty)
        return Novedad(titulo: pedido ? TextosEstudios.estudioNuevo : TextosEstudios.ordenNueva, destino: destino)
    }

    /// Con novedad, su texto y «Ver». Sin novedad y con algo por hacer, «Tenés un estudio para hacer» y «Subir resultado».
    /// Sin ninguna de las dos cosas no hay tarjeta.
    public static func tarjetaInicio(_ e: EstadoEstudios) -> TarjetaInicio? {
        if let n = novedad(e) { return TarjetaInicio(titulo: n.titulo, boton: TextosEstudios.ver, nueva: true) }
        guard !e.pendientes.isEmpty else { return nil }
        return TarjetaInicio(titulo: TextosEstudios.estudioParaHacer, boton: TextosEstudios.subirResultado, nueva: false)
    }

    /// A qué tarjeta se lleva al llegar desde un aviso o desde la tarjeta de arriba: la primera nueva en el orden de la
    /// pantalla (los pedidos van antes que las órdenes); sin nada nuevo, el primer pedido. nil: no hay a dónde.
    public static func ancla(_ e: EstadoEstudios) -> Ancla? {
        if let p = e.pendientes.first(where: \.nuevo) { return .pendiente(p.id) }
        if let o = e.ordenes.first(where: \.nuevo) { return .orden(o.id) }
        return e.pendientes.first.map { .pendiente($0.id) }
    }

    // MARK: Preparación y dónde

    static let cardio: Set<String> = ["ecocardiograma", "electrocardiograma", "ergometria", "eco_estres", "mapa"]

    /// «Cómo prepararte», por tipo. Textos fijos (no salen de la orden): lo propio del tipo, el aviso de los estudios del
    /// corazón y, siempre al final, las dos frases de Mati.
    public static func preparacion(tipo: String?) -> [String] {
        var l: [String]
        switch tipo {
        case "laboratorio":
            l = ["Ayuno de 8 a 12 horas. Podés tomar agua, y andá bien hidratado.",
                 "Extracción entre las 7 y las 10 de la mañana.",
                 "48 horas antes: sin entrenar y sin alcohol.",
                 "3 días antes: sin biotina (viene en suplementos para pelo y uñas y en algunos multivitamínicos).",
                 "Si te piden orina, la primera de la mañana.",
                 "Si estás enfermo o pasaste la noche sin dormir, mejor pasalo a otro día."]
        case "ecografia":
            l = ["Si es abdominal, ayuno de 6 a 8 horas.", "Para otras ecografías, seguí lo que te indique el centro al sacar el turno."]
        case "ecocardiograma", "electrocardiograma":
            l = ["No necesita preparación."]
        case "ergometria", "eco_estres":
            l = ["Comida liviana 2 horas antes.", "Ese día, sin café, mate ni tabaco.", "Llevá ropa y zapatillas para hacer ejercicio."]
        case "mapa":
            l = ["Elegí un día común de semana.", "En cada toma, dejá el brazo quieto y relajado.",
                 "Anotá lo que vas haciendo: comidas, entreno y sueño.", "Con el aparato puesto no te podés duchar."]
        default:
            l = ["Seguí lo que te indique el centro al sacar el turno."]
        }
        if let tipo, cardio.contains(tipo) { l.append("Si tenés dolor de pecho, falta de aire o palpitaciones, avisale a Mati antes de hacerlo.") }
        l.append("Si Mati te dio una indicación propia, vale esa.")
        l.append("No dejes ninguna medicación sin que Mati te lo diga.")
        return l
    }

    public static func donde(tipo: String?) -> [String] {
        if tipo == "laboratorio" {
            return ["En cualquier laboratorio de análisis clínicos. Si tenés obra social o prepaga, en uno de tu cartilla: llevá la orden, tu credencial y tu DNI.",
                    "Si podés, siempre en el mismo laboratorio: así los resultados se comparan mejor."]
        }
        return ["En un centro de diagnóstico o de cardiología, con turno. Si tenés obra social o prepaga, en uno de tu cartilla: llevá la orden, tu credencial y tu DNI."]
    }

    // MARK: Subida

    public enum Formato: String, Codable, Sendable {
        case pdf, jpeg
        public var mime: String { self == .pdf ? "application/pdf" : "image/jpeg" }
        public var extensionArchivo: String { self == .pdf ? "pdf" : "jpg" }
    }

    /// Lo único que acepta el servidor: un PDF (`%PDF-`) o un JPEG. nil = otra cosa.
    public static func formato(_ datos: Data) -> Formato? {
        if datos.starts(with: [0x25, 0x50, 0x44, 0x46, 0x2D]) { return .pdf }
        if datos.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        return nil
    }

    public enum Agregado: Equatable, Sendable { case ok, tope, muyGrande, ilegible, noSeGuardo }

    /// ¿Entra este archivo en el envío que se está armando?
    public static func puedeAgregar(bytes: Int, formato: Formato?, yaHay: Int, topeArchivos: Int = topeArchivos, topeMB: Int = topeMB) -> Agregado {
        if yaHay >= topeArchivos { return .tope }
        guard formato != nil, bytes > 0 else { return .ilegible }
        if bytes > topeMB * 1024 * 1024 { return .muyGrande }
        return .ok
    }

    public enum Subida: Equatable, Sendable { case ok, descartar, reintentar }

    /// Qué hace la cola con la respuesta de `/estudios/upload`: 200 con `ok` es hecho (también con `ya`); 429 y 5xx, más tarde;
    /// cualquier otro 4xx es definitivo para ese archivo.
    public static func clasificarSubida(status: Int, ok: Bool) -> Subida {
        switch status {
        case 200..<300: return ok ? .ok : .reintentar
        case 429: return .reintentar
        case 400..<500: return .descartar
        default: return .reintentar
        }
    }

    /// «Subiendo 2 de 5»: el que está subiendo ahora, sin pasarse del total.
    public static func progreso(subidos: Int, total: Int) -> String {
        TextosEstudios.subiendo(min(max(subidos + 1, 1), max(total, 1)), de: max(total, 1))
    }
}

// MARK: - Lo que devuelve `mypump_estudios_get`

/// Todo campo es opcional y un `tipo` o `estado` que no se conoce no rompe: el título viene del servidor y el estado
/// desconocido cae en el más prudente («pedido», «Recibido», «enviado»).
public struct EstadoEstudios: Equatable, Sendable {
    public let hoy: Estudios.Dia?
    public let topeArchivos: Int
    public let topeMB: Int
    /// El de `proximo_control` o, con `controles_app`, el control de salud (`conControl`).
    public private(set) var proximoControl: ProximoControl?
    public let pendientes: [PendienteEstudio]
    public let ordenes: [OrdenEstudio]
    public let estudios: [EstudioRecibido]
    public let envios: [EnvioRecibido]
    /// Pedidos a la vista y órdenes vigentes que el alumno todavía no vio. Sin el campo (servidor viejo), 0.
    public let novedades: Int

    /// nil: no es una respuesta con `habilitado: true`.
    public init?(_ j: JSONValue, zona: TimeZone = .current) {
        guard j["habilitado"] == .bool(true) else { return nil }
        hoy = Estudios.Dia(j["hoy"]?.comoTexto)
        topeArchivos = j["topes"]?["archivos_por_envio"]?.enteroEstudios.flatMap { $0 > 0 ? $0 : nil } ?? Estudios.topeArchivos
        topeMB = j["topes"]?["mb_por_archivo"]?.enteroEstudios.flatMap { $0 > 0 ? $0 : nil } ?? Estudios.topeMB
        proximoControl = ProximoControl(j["proximo_control"])
        pendientes = j["pendientes"].listaEstudios.compactMap(PendienteEstudio.init)
        ordenes = j["ordenes"].listaEstudios.compactMap(OrdenEstudio.init)
        estudios = j["estudios"].listaEstudios.enumerated().compactMap { EstudioRecibido($1, indice: $0) }
        envios = j["envios"].listaEstudios.enumerated().compactMap { EnvioRecibido($1, indice: $0, zona: zona) }
        novedades = max(0, j["novedades"]?.enteroEstudios ?? 0)
    }

    /// El control de salud (`mypump_controles_get`) alimenta el mismo bloque «Próximo control» y gana sobre el del pedido:
    /// un solo lugar, con el mismo texto neutro. nil deja lo que vino en `proximo_control`.
    public func conControl(_ c: ProximoControl?) -> EstadoEstudios {
        guard let c else { return self }
        var e = self
        e.proximoControl = c
        return e
    }

    /// Los `borrador` son restos de una subida a medias: no se muestran.
    public var enviosVisibles: [EnvioRecibido] { envios.filter { !$0.borrador } }
}

public struct ProximoControl: Equatable, Sendable {
    public let tipo: String?
    public let titulo: String
    public let desde: Estudios.Dia?
    public let hasta: Estudios.Dia?
    /// Con un control de salud: «El lunes 16/11» (ya armado) y la nota de abajo. nil en el del pedido.
    public let cuandoFijo: String?
    public let nota: String?

    init?(_ j: JSONValue?) {
        guard case .objeto? = j, let j else { return nil }
        tipo = j["tipo"]?.comoTexto
        titulo = j["titulo"]?.comoTexto.noVacio ?? "Estudio"
        desde = Estudios.Dia(j["desde"]?.comoTexto)
        hasta = Estudios.Dia(j["hasta"]?.comoTexto)
        cuandoFijo = nil
        nota = nil
    }

    /// El de un control de salud (`Controles.proximoParaEstudios`).
    init(titulo: String, cuando: String, nota: String?) {
        tipo = nil; self.titulo = titulo; desde = nil; hasta = nil; cuandoFijo = cuando; self.nota = nota
    }

    /// Lo que dice el bloque debajo del título.
    public var cuando: String? { cuandoFijo ?? Estudios.fechaControl(desde: desde, hasta: hasta) }
}

public struct PendienteEstudio: Equatable, Sendable, Identifiable {
    public let id: String
    public let tipo: String?
    public let titulo: String
    public let detalle: String?
    public let desde: Estudios.Dia?
    public let hasta: Estudios.Dia?
    /// «Ya me lo hice» marcado: falta subir el resultado.
    public let hecho: Bool
    public let hechoFecha: Estudios.Dia?
    public let ordenId: String?
    /// El alumno todavía no lo vio. Solo con el `true` del servidor.
    public let nuevo: Bool

    /// Sin `id` no se puede hacer nada con él: no se muestra.
    init?(_ j: JSONValue) {
        guard let i = j["id"]?.comoTexto.noVacio else { return nil }
        id = i
        tipo = j["tipo"]?.comoTexto
        titulo = j["titulo"]?.comoTexto.noVacio ?? "Estudio"
        detalle = j["detalle"]?.comoTexto.noVacio
        desde = Estudios.Dia(j["desde"]?.comoTexto)
        hasta = Estudios.Dia(j["hasta"]?.comoTexto)
        hecho = j["estado"]?.comoTexto == "hecho"
        hechoFecha = Estudios.Dia(j["hecho_fecha"]?.comoTexto)
        ordenId = j["orden_id"]?.comoTexto.noVacio
        nuevo = j["nuevo"] == .bool(true)
    }
}

public struct OrdenEstudio: Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let tipo: String?
    public let titulo: String
    public let emitida: Estudios.Dia?
    public let vence: Estudios.Dia?
    /// false = vencida: se lista 30 días más, sin abrir. Solo un `false` explícito la cierra.
    public let vigente: Bool
    /// El alumno todavía no la vio. Solo con el `true` del servidor.
    public let nuevo: Bool

    init?(_ j: JSONValue) {
        guard let i = j["id"]?.comoTexto.noVacio else { return nil }
        id = i
        tipo = j["tipo"]?.comoTexto
        titulo = j["titulo"]?.comoTexto.noVacio ?? "Estudio"
        emitida = Estudios.Dia(j["emitida"]?.comoTexto)
        vence = Estudios.Dia(j["vence"]?.comoTexto)
        vigente = j["vigente"] != .bool(false)
        nuevo = j["nuevo"] == .bool(true)
    }
}

public struct EstudioRecibido: Equatable, Sendable, Identifiable {
    public let id: String
    public let tipo: String?
    public let titulo: String
    public let fecha: Estudios.Dia?
    public let hojas: Int?
    /// «Mati lo vio». Cualquier otro estado, conocido o no, es «Recibido».
    public let visto: Bool
    /// Solo con el `true` del servidor y un id de verdad.
    public let sePuedeAbrir: Bool

    init?(_ j: JSONValue, indice: Int) {
        guard case .objeto = j else { return nil }
        let i = j["id"]?.comoTexto.noVacio
        id = i ?? "sin-id-\(indice)"
        tipo = j["tipo"]?.comoTexto
        titulo = j["titulo"]?.comoTexto.noVacio ?? "Estudio"
        fecha = Estudios.Dia(j["fecha"]?.comoTexto)
        hojas = j["hojas"]?.enteroEstudios
        visto = j["estado"]?.comoTexto == "visto"
        sePuedeAbrir = i != nil && j["se_puede_abrir"] == .bool(true)
    }
}

public struct EnvioRecibido: Equatable, Sendable, Identifiable {
    public let id: String
    public let borrador: Bool
    public let archivos: Int?
    public let pedidoId: String?
    public let enviado: Estudios.Dia?

    init?(_ j: JSONValue, indice: Int, zona: TimeZone) {
        guard case .objeto = j else { return nil }
        id = j["id"]?.comoTexto.noVacio ?? "sin-id-\(indice)"
        borrador = j["estado"]?.comoTexto == "borrador"
        archivos = j["archivos"]?.enteroEstudios
        pedidoId = j["pedido_id"]?.comoTexto.noVacio
        enviado = Estudios.Dia(instante: j["enviado_en"]?.comoTexto, zona: zona)
    }
}

extension JSONValue {
    var enteroEstudios: Int? {
        if case .numero(let n) = self, n.isFinite, n == n.rounded(), abs(n) < 1_000_000 { return Int(n) }
        return nil
    }
}

extension Optional where Wrapped == JSONValue {
    var listaEstudios: [JSONValue] { if case .lista(let l)? = self { l } else { [] } }
}

extension Optional where Wrapped == String {
    var noVacio: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
