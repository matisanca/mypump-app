import Foundation
import Observation
import MyPumpModelos

/// Una burbuja del hilo con Mati: la fila del servidor o una optimista que todavía no salió ("enviando…").
public struct BurbujaChat: Identifiable, Equatable, Sendable {
    public let id: String
    public let autor: String
    public let contenido: String
    public var leidoPorCliente: Bool?
    /// ISO, como lo manda el servidor (o la hora del teléfono para una optimista).
    public let createdAt: String
    /// `_tmp`: escrita en el teléfono, todavía sin fila en el servidor.
    public var pendiente: Bool
    /// `_fallo`: la cola se rindió con este mensaje; se ofrece reintentar (el texto nunca se pierde).
    public var fallo: Bool

    public var esDelCoach: Bool { autor == "coach" }

    public init(id: String, autor: String, contenido: String, leidoPorCliente: Bool?, createdAt: String, pendiente: Bool = false, fallo: Bool = false) {
        self.id = id; self.autor = autor; self.contenido = contenido; self.leidoPorCliente = leidoPorCliente
        self.createdAt = createdAt; self.pendiente = pendiente; self.fallo = fallo
    }

    init(_ m: MensajeChat) {
        self.init(id: m.id, autor: m.autor, contenido: m.contenido, leidoPorCliente: m.leidoPorCliente, createdAt: m.createdAt)
    }
}

/// El hilo en memoria y `chatMerge` de la web (cliente.html:2268): sin repetir filas (el sondeo y la paginación se
/// solapan), ordenado por fecha, y cuando llega la fila real de un mensaje del cliente se van TODAS las optimistas con
/// ese texto (el servidor deduplica el mismo mensaje dentro de 2 minutos, mig 075, y una sobrante quedaría "enviando…"
/// para siempre).
public struct HiloChat: Equatable, Sendable {
    public private(set) var mensajes: [BurbujaChat] = []
    /// El `created_at` del último mensaje real: desde ahí pregunta el sondeo.
    public private(set) var cursor: String?
    public var hayMas = true

    public init() {}

    /// Devuelve cuántas filas entraron.
    @discardableResult
    public mutating func mezclar(_ filas: [MensajeChat]) -> Int {
        var vistos = Set(mensajes.map(\.id))
        var entraron = 0
        // Una fila que ya estaba puede venir con su "leído" (get_chat lo trae; chat_nuevos no): se actualiza, si no al
        // recargar el badge quedaba en 0 con el mensaje sin leer.
        for f in filas where vistos.contains(f.id) {
            if let l = f.leidoPorCliente, let i = mensajes.firstIndex(where: { $0.id == f.id }) { mensajes[i].leidoPorCliente = l }
        }
        for f in filas where !vistos.contains(f.id) {
            if f.autor == "cliente" {
                mensajes.removeAll { $0.pendiente && $0.autor == "cliente" && $0.contenido == f.contenido }
            }
            vistos.insert(f.id)
            mensajes.append(BurbujaChat(f))
            entraron += 1
        }
        ordenar()
        if let ultimo = mensajes.last(where: { !$0.pendiente }) { cursor = ultimo.createdAt }
        return entraron
    }

    public mutating func agregarPendiente(_ b: BurbujaChat) {
        mensajes.append(b)
        ordenar()
    }

    public mutating func marcarFallido(contenido: String) {
        if let i = mensajes.firstIndex(where: { $0.pendiente && !$0.fallo && $0.contenido == contenido }) { mensajes[i].fallo = true }
    }

    public mutating func desmarcarFallido(id: String) -> BurbujaChat? {
        guard let i = mensajes.firstIndex(where: { $0.id == id }) else { return nil }
        mensajes[i].fallo = false
        return mensajes[i]
    }

    /// Todo lo del coach queda leído; devuelve si había algo sin leer.
    public mutating func marcarLeidos() -> Bool {
        var habia = false
        for i in mensajes.indices where mensajes[i].esDelCoach {
            if mensajes[i].leidoPorCliente == false { habia = true }
            mensajes[i].leidoPorCliente = true
        }
        return habia
    }

    public var sinLeer: Int { mensajes.filter { $0.esDelCoach && $0.leidoPorCliente == false }.count }
    public var primeroReal: BurbujaChat? { mensajes.first { !$0.pendiente } }

    /// `sort((a, b) => new Date(a.created_at) - new Date(b.created_at))`: estable, como el de JS.
    private mutating func ordenar() {
        mensajes = mensajes.enumerated()
            .sorted { a, b in
                let fa = FechaISO.ms(a.element.createdAt), fb = FechaISO.ms(b.element.createdAt)
                return fa != fb ? fa < fb : a.offset < b.offset
            }
            .map(\.element)
    }
}

/// Fechas ISO del servidor (`timestamptz` con microsegundos y zona) a milisegundos, como `new Date(iso)` de JS: lo
/// ilegible vale 0 (`new Date(undefined || 0)`).
public enum FechaISO {
    public static func ms(_ iso: String) -> Double {
        fecha(iso).map { $0.timeIntervalSince1970 * 1000 } ?? 0
    }

    public static func fecha(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        // ISO8601DateFormatter no lee más de 3 decimales: se recortan los microsegundos.
        var s = iso.replacingOccurrences(of: " ", with: "T")
        if let punto = s.firstIndex(of: "."), let fin = s[punto...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let decimales = s[s.index(after: punto)..<fin]
            s.replaceSubrange(s.index(after: punto)..<fin, with: String(decimales.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0))
        }
        if s.hasSuffix("+00") || s.range(of: #"[+-]\d\d$"#, options: .regularExpression) != nil { s += ":00" }
        let conDecimales = ISO8601DateFormatter()
        conDecimales.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = conDecimales.date(from: s) { return d }
        let sinDecimales = ISO8601DateFormatter()
        sinDecimales.formatOptions = [.withInternetDateTime]
        return sinDecimales.date(from: s)
    }

    public static func texto(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}

/// El chat con Mati (`ambito='general'`): páginas de 30 hacia atrás, sondeo con un cursor, envío por la cola con la
/// burbuja al instante, "no salió → Reintentar" si la cola se rinde, y marcar leído al abrir. Es sondeo y no Realtime a
/// propósito: la anon key es la misma para todos los clientes (CHA-06).
@MainActor @Observable
public final class ModeloChat {
    public static let pagina = 30

    public private(set) var hilo = HiloChat()
    /// Badge del tab: lo del coach que llegó con el chat cerrado.
    public private(set) var noLeidos = 0
    public private(set) var cargando = false
    /// Con el chat a la vista el sondeo va cada 15 s y marca leído lo nuevo; si no, cada 45 s y suma al badge.
    public var abierto = false

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let outbox: Outbox?
    @ObservationIgnored private var sondeo: Task<Void, Never>?

    public init(cliente: ClienteRPC, token: String, outbox: Outbox?) {
        self.cliente = cliente; self.token = token; self.outbox = outbox
    }

    /// `loadChat`: la última página, o una más hacia atrás. Sin red no toca nada.
    public func cargar(masViejos: Bool = false) async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        let antes: JSONValue = masViejos ? (hilo.primeroReal.map { .texto($0.createdAt) } ?? .null) : .null
        guard case .success(let filas) = await cliente.filas("mypump_get_chat", ["p_token": .texto(token), "p_antes": antes,
                                                                                 "p_limite": .numero(Double(Self.pagina))], como: MensajeChat.self)
        else { return }
        if filas.count < Self.pagina { hilo.hayMas = false }
        hilo.mezclar(filas)
        recontar()
        if abierto && !masViejos && noLeidos > 0 { await marcarLeido() }
    }

    /// `chatPollTick`: lo nuevo desde el cursor. Lo que llega del coach por acá todavía no lo leyó (la RPC no trae el
    /// campo).
    public func sondear() async {
        guard let desde = hilo.cursor else { await cargar(); return }
        guard case .success(let filas) = await cliente.filas("mypump_chat_nuevos", ["p_token": .texto(token), "p_desde": .texto(desde)],
                                                             como: MensajeChat.self), !filas.isEmpty else { return }
        guard hilo.mezclar(filas) > 0 else { return }
        let delCoach = filas.filter(\.esDelCoach).count
        if delCoach > 0 {
            if abierto { await marcarLeido() } else { noLeidos += delCoach }
        }
    }

    /// Recalcula el badge sin bajarlo por debajo de lo que llegó por el sondeo (eso solo lo baja `marcarLeido`).
    private func recontar() {
        noLeidos = max(noLeidos, hilo.sinLeer)
    }

    /// `enviarChatMsg`: la burbuja aparece ya y el mensaje sale por la cola (sobrevive a cerrar la app sin señal).
    public func enviar(_ texto: String) async {
        let contenido = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contenido.isEmpty else { return }
        let ahora = Date()
        hilo.agregarPendiente(BurbujaChat(id: "tmp_\(Int(ahora.timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(5))",
                                          autor: "cliente", contenido: contenido, leidoPorCliente: nil,
                                          createdAt: FechaISO.texto(ahora), pendiente: true))
        await encolar(contenido)
        traerDespuesDeMandar()
    }

    /// La burbuja deja de decir "enviando…" apenas sale (como la web, que sondea 250 ms después de un envío): esperar al
    /// sondeo de 15-45 s hacía que el cliente creyera que no salió y lo mandara de nuevo.
    private func traerDespuesDeMandar() {
        Task { [weak self] in
            guard let self else { return }
            await self.outbox?.drenar()
            try? await Task.sleep(for: .milliseconds(250))
            await self.sondear()
        }
    }

    public func reintentar(_ id: String) async {
        guard let b = hilo.desmarcarFallido(id: id) else { return }
        await encolar(b.contenido)
        traerDespuesDeMandar()
    }

    /// La cola se rindió con un mensaje del chat.
    public func marcarFallido(contenido: String) {
        hilo.marcarFallido(contenido: contenido)
    }

    /// `marcarChatLeido`: se decide por los mensajes (con el chat abierto el contador puede dar 0 y Mati los seguiría
    /// viendo "sin leer").
    public func marcarLeido() async {
        let habia = hilo.marcarLeidos()
        guard habia || noLeidos > 0 else { return }
        noLeidos = 0
        _ = await cliente.llamar("mypump_marcar_leidos_cliente", ["p_token": .texto(token), "p_ambito": .texto("general"), "p_referencia_id": .null])
    }

    /// Sondeo en cadena (nunca dos a la vez): 15 s abierto, 45 s cerrado. Se corta con la app en segundo plano.
    public func empezarSondeo() {
        sondeo?.cancel()
        sondeo = Task { [weak self] in
            while !Task.isCancelled {
                guard let abierto = self?.abierto else { return }   // el modelo ya no existe
                let espera: Double = abierto ? 15 : 45
                try? await Task.sleep(for: .seconds(espera))
                if Task.isCancelled { return }
                await self?.sondear()
            }
        }
    }

    public func pararSondeo() {
        sondeo?.cancel()
        sondeo = nil
    }

    private func encolar(_ contenido: String) async {
        // La clave lleva el texto: dos mensajes distintos son dos ops; el mismo reencolado por un doble toque, una.
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        _ = await outbox?.encolar("chat", .objeto(["contenido": .texto(contenido)]), dedupeKey: "chat_\(ms)_\(String(contenido.prefix(40)))")
    }
}
