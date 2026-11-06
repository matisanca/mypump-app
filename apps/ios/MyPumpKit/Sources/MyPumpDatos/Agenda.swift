import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// La agenda de la entrega al final de «Tu guía» (2.2.0, `entregas_021_agenda`):
/// - `entregas_app_agenda` al abrir la guía, al ver el último obligatorio y al volver a primer plano con la guía abierta o
///   con una reserva pendiente. Nunca en segundo plano.
/// - `entregas_app_reservar` por la cola, en el carril propio de los audios (`guia_reserva`), con un `p_id` fijo: sin red
///   no se gasta el intento y un reintento devuelve la misma reserva.
///
/// Sin el servidor nuevo (PGRST202 u `ok: false`) no se muestra nada y no hay errores: la guía queda como en la 2.1.0.
@MainActor @Observable
public final class ModeloAgenda {
    public nonisolated static let kind = "guia_reserva"
    /// Una sola reserva a la vez: dos toques seguidos son la misma op (gana la última, que es la misma franja).
    nonisolated static let clave = "guia_reserva"
    static let archivo = "guia_agenda.json"

    /// Lo último que dijo el servidor (o la copia guardada, sin red).
    public private(set) var agenda: AgendaGuia?
    /// Lo que se ve vino de la copia (la última consulta falló por red).
    public private(set) var desdeCache = false
    /// La franja que está saliendo por la cola (todavía sin respuesta).
    public private(set) var enCola: FranjaAgenda?
    /// Lo último que dijo `reservar` (tomada, vencida, error) o la demo.
    public private(set) var aviso: ReglasAgenda.Aviso?
    /// Para la región viva de VoiceOver: cambia aunque el texto se repita.
    public private(set) var anuncio = ""
    public private(set) var anuncios = 0

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let outbox: Outbox?
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored let esperaSondeo: Duration
    @ObservationIgnored let reloj: @Sendable () -> Double
    @ObservationIgnored private var consultaEnCurso: Task<Void, Never>?
    @ObservationIgnored private var sondeo: Task<Void, Never>?
    @ObservationIgnored private var marcaSondeo = 0
    /// La demo («Ver demo») y la maqueta: la agenda empaquetada, sin red. Reservar confirma enseguida, sin videollamada.
    @ObservationIgnored private let esMuestra: Bool
    /// En la muestra, la guía cuenta los obligatorios (no hay servidor que lo haga).
    @ObservationIgnored var faltanMuestra: () -> Int = { 0 }

    public init(cliente: ClienteRPC, token: String, outbox: Outbox?, disco: Disco?, esperaSondeo: Duration = .seconds(ReglasAgenda.sondeoCada),
                reloj: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.cliente = cliente; self.token = token; self.outbox = outbox; self.disco = disco
        self.esperaSondeo = esperaSondeo; self.reloj = reloj
        esMuestra = false
        let copia = disco?.leer(AgendaGuia.self, Self.archivo)
        agenda = copia?.ok == true ? copia : nil
    }

    /// La demo y la maqueta: `agenda` es la empaquetada (con las franjas ya corridas a fechas futuras).
    public init(muestra agenda: AgendaGuia?) {
        cliente = ClienteRPC(); token = ""; outbox = nil; disco = nil
        esperaSondeo = .seconds(ReglasAgenda.sondeoCada); reloj = { Date().timeIntervalSince1970 }
        esMuestra = true
        self.agenda = agenda?.ok == true ? agenda : nil
    }

    // MARK: - Lo que se ve

    /// `faltanLocal`: lo que cuenta la guía en el teléfono (respaldo si el servidor no manda `faltan`).
    public func vista(faltanLocal: Int?) -> ReglasAgenda.Vista {
        ReglasAgenda.vista(agendaVista(faltanLocal: faltanLocal), faltanLocal: faltanLocal, enCola: enCola != nil, aviso: aviso)
    }

    /// La agenda funciona en este servidor: con eso se muestran el contador y la etiqueta de los obligatorios.
    public var disponible: Bool { agenda?.ok == true }

    /// En la muestra la agenda se habilita sola al ver el último obligatorio (no hay servidor).
    private func agendaVista(faltanLocal: Int?) -> AgendaGuia? {
        guard esMuestra, var a = agenda else { return agenda }
        let f = faltanLocal ?? faltanMuestra()
        a.faltan = f
        if a.reserva?.vigente != true { a.habilitada = a.autorizada && f == 0 }
        if !a.habilitada { a.franjas = [] }
        return a
    }

    /// La reserva que se ve, para la tarjeta de Entreno (el «Entrar»).
    public var reserva: ReservaAgenda? { agenda?.reserva }

    // MARK: - Consultas

    /// `entregas_app_agenda`. Si ya hay una en vuelo, se espera esa.
    public func consultar() async {
        if esMuestra { return }
        if let t = consultaEnCurso { await t.value; return }
        let t = Task { await self.traer() }
        consultaEnCurso = t
        await t.value
        consultaEnCurso = nil
    }

    private func traer() async {
        switch await cliente.llamar("entregas_app_agenda", ["p_token": .texto(token)]) {
        case .failure(let e) where e.clase == .permanente:
            // PGRST202 (sin la 021) o cualquier rechazo: no hay agenda, como en la 2.1.0. Sin mensajes.
            olvidar()
        case .failure:
            // Sin red o el servidor ocupado: lo guardado, con «Sin conexión».
            desdeCache = agenda != nil
        case .success(let j):
            let a = AgendaGuia(json: j)
            guard a.ok else { olvidar(); return }
            let antes = agenda?.reserva?.estado
            agenda = a
            desdeCache = false
            disco?.guardar(a, Self.archivo)
            // Lo último que dijo `reservar` deja de valer cuando la reserva cambia de estado o ya no hay.
            if a.reserva?.estado == .fallo || a.reserva?.vigente == true { aviso = nil }
            if let r = a.reserva, r.estado != antes { anunciar(r) }
            if a.reserva?.estado == .pendiente { sondear() }
        }
    }

    private func olvidar() {
        agenda = nil
        desdeCache = false
        disco?.borrar(Self.archivo)
    }

    private func anunciar(_ r: ReservaAgenda) {
        switch r.estado {
        case .confirmada: anuncio = ReglasAgenda.textoConfirmada(r) ?? "Tu entrega quedó confirmada"
        case .fallo: anuncio = r.motivo == "tomada" ? ReglasAgenda.Aviso.tomada.texto : ReglasAgenda.Aviso.error.texto
        case .pendiente: anuncio = ReglasAgenda.textoReservando
        }
        anuncios += 1
    }

    /// Una reserva pendiente: cada 5 s durante 60 s (después, al volver a primer plano). Uno solo a la vez.
    func sondear() {
        guard !esMuestra, sondeo == nil, agenda?.reserva?.estado == .pendiente || enCola != nil else { return }
        let inicio = reloj()
        marcaSondeo += 1
        let marca = marcaSondeo
        sondeo = Task { [weak self, esperaSondeo] in
            while !Task.isCancelled {
                try? await Task.sleep(for: esperaSondeo)
                guard !Task.isCancelled, let self else { break }
                if self.reloj() - inicio > ReglasAgenda.sondeoMaximo { break }
                // Mientras la reserva sigue en la cola no hay nada que consultar: espera su respuesta.
                if self.enCola == nil { await self.consultar() }
                if self.agenda?.reserva?.estado != .pendiente && self.enCola == nil { break }
            }
            if let self, self.marcaSondeo == marca { self.sondeo = nil }
        }
    }

    /// Segundo plano: nunca se consulta de fondo.
    public func pararSondeo() {
        sondeo?.cancel(); sondeo = nil
        marcaSondeo += 1
    }

    /// De vuelta a primer plano con una reserva pendiente (aunque la guía esté cerrada): una consulta y otra ventana de 60 s.
    public func alVolver() async {
        guard agenda?.reserva?.estado == .pendiente else { return }
        await consultar()
        sondear()
    }

    /// Hay una reserva pendiente (la de la tarjeta de Entreno o la de la cola).
    public var pendiente: Bool { enCola != nil || agenda?.reserva?.estado == .pendiente }

    // MARK: - Reservar

    /// La franja elegida en la hoja de confirmación. Por la cola, con un `p_id` armado una sola vez: cada reintento manda
    /// el mismo. Si ya hay una saliendo (dos toques, o una que quedó de antes en la cola), no se encola otra.
    public func reservar(_ f: FranjaAgenda) async {
        guard enCola == nil, agenda?.reserva?.vigente != true else { return }
        aviso = nil
        if esMuestra {
            // La demo: confirmada enseguida, sin videollamada y con el aviso.
            agenda?.reserva = ReservaAgenda(id: UUID().uuidString.lowercased(), inicio: f.inicio, fin: f.fin, estado: .confirmada)
            agenda?.franjas = []
            aviso = .demo
            if let r = agenda?.reserva { anunciar(r) }
            return
        }
        guard let outbox else { return }
        enCola = f
        if await outbox.operaciones.contains(where: { $0.kind == Self.kind }) { return }
        await outbox.encolar(Self.kind, .objeto([
            "id": .texto(UUID().uuidString.lowercased()), "franja": .texto(f.id), "inicio": .texto(f.inicio), "fin": .texto(f.fin),
        ]), dedupeKey: Self.clave)
        sondear()
    }

    /// Lo que quedó en la cola de otra apertura (la app se cerró con la reserva saliendo): «Estamos reservando…».
    public func cargarDeLaCola() async {
        guard let outbox, enCola == nil,
              let op = await outbox.operaciones.first(where: { $0.kind == Self.kind }),
              let id = op.payload["franja"]?.comoTexto else { return }
        enCola = FranjaAgenda(id: id, inicio: op.payload["inicio"]?.comoTexto ?? "", fin: op.payload["fin"]?.comoTexto ?? "")
    }

    /// Lo que la cola guardó: la respuesta de `entregas_app_reservar`.
    public func alGuardar(_ ops: [OpGuardada]) {
        for g in ops where g.op.kind == Self.kind {
            enCola = nil
            let r = g.respuesta
            let reserva = r["reserva"].flatMap(Self.reserva(_:))
            if r["ok"] == .bool(true) || r["motivo"]?.comoTexto == "ya_tiene", let reserva {
                // Bien, o ya tenía una (la vigente): esa es la que se ve.
                agenda?.reserva = reserva
                agenda?.franjas = []
                if let a = agenda { disco?.guardar(a, Self.archivo) }
                anunciar(reserva)
            } else if r["ok"] == .bool(true) {
                aviso = nil   // salió sin la reserva en la respuesta: la trae la agenda
            } else {
                switch r["motivo"]?.comoTexto {
                case "tomada": aviso = .tomada
                case "franja": aviso = .vencida
                case "obligatorios", "autorizada", "ya_tiene": aviso = nil   // la agenda de nuevo dice qué pasa
                default: aviso = .error
                }
                if let a = aviso { anuncio = a.texto; anuncios += 1 }
            }
            Task { await self.consultar(); self.sondear() }
        }
    }

    /// Lo que la cola abandonó (8 rechazos): se elige otra.
    public func alAbandonar(_ ops: [Operacion]) {
        guard ops.contains(where: { $0.kind == Self.kind }) else { return }
        enCola = nil
        aviso = .error
        anuncio = ReglasAgenda.Aviso.error.texto; anuncios += 1
        Task { await self.consultar() }
    }

    nonisolated static func reserva(_ j: JSONValue) -> ReservaAgenda? {
        guard case .objeto = j, let d = try? JSONEncoder().encode(j) else { return nil }
        return try? JSONDecoder().decode(ReservaAgenda.self, from: d)
    }

    // MARK: - Pruebas

    var sondeando: Bool { sondeo != nil }
}

// MARK: - La ejecución en la cola

extension Escrituras {
    /// `guia_reserva`: `entregas_app_reservar(p_token, p_franja, p_id)`. Red o transitorio: la cola reintenta con el mismo
    /// `p_id` sin gastar intento. `motivo: token` o una respuesta vacía: se mira si cayó el token. Sin la función (PGRST202)
    /// no hay agenda: se da por resuelta con `error` (la pantalla deja elegir otra).
    func ejecutarReserva(_ p: JSONValue) async -> ResultadoOp {
        guard let id = p["id"]?.comoTexto, UUID(uuidString: id) != nil, let franja = p["franja"]?.comoTexto, !franja.isEmpty else {
            return .respuesta(.success(.objeto(["ok": .bool(false), "motivo": .texto("error")])))
        }
        let r = await cliente.llamar("entregas_app_reservar", ["p_token": .texto(token), "p_franja": .texto(franja), "p_id": .texto(id)])
        switch r {
        case .failure(let e) where e.funcionInexistente:
            return .respuesta(.success(.objeto(["ok": .bool(false), "motivo": .texto("error")])))
        case .failure:
            return .respuesta(r)
        case .success(let j):
            guard case .objeto = j, j["motivo"]?.comoTexto != "token" else { return .respuesta(.success(.null)) }
            return .respuesta(.success(j))
        }
    }
}
