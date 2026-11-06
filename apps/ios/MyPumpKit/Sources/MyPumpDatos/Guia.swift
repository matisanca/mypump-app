import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// «Tu guía»: los videos de Mati antes de la videollamada, con el avance, las dudas y la suplementación. Contrato de la
/// obra de entregas (`entregas_010_app` y `entregas_011`), ver `docs/NATIVA_GUIA_IOS.md`:
/// - `entregas_app_resumen` (solo lee): la tarjeta de inicio, al cargar la cuenta y al volver a primer plano.
/// - `entregas_app_get` (marca `abierto_en` la primera vez): SOLO cuando el cliente abre la sección.
/// - `entregas_app_avance`, `entregas_app_duda` y `entregas_app_llamada_duda`: por la cola de escrituras.
///
/// Con `{"ok": false}` (token inválido o revocado, o sin página aprobada) la sección desaparece sin mensaje: se borran la
/// tarjeta y la copia guardada.
@MainActor @Observable
public final class ModeloGuia {
    public nonisolated static let kindAvance = "guia_avance"
    public nonisolated static let kindDuda = "guia_duda"
    public nonisolated static let kindDudaLlamada = "guia_duda_llamada"

    /// Qué muestra la sección.
    public enum Estado: Equatable, Sendable {
        /// Todavía no se trajo nunca (ni hay copia): cargando.
        case cargando
        case lista
        /// `ok: false`: no hay guía (la sección no aparece).
        case oculta
        /// Sin red y sin copia guardada.
        case sinRed
    }

    /// Cómo quedó lo último que mandó el cliente en un recuadro de dudas.
    public enum Envio: Equatable, Sendable {
        /// En la cola: sale apenas haya señal (se ve como «enviando»).
        case enviando
        case listo
        /// La base dijo que no (tope o token): el texto vuelve al campo.
        case noSeGuardo
    }

    /// Una duda en la cola que todavía no confirmó el servidor.
    public struct DudaPendiente: Equatable, Sendable, Identifiable {
        public let id: String      // el `_id` de la op
        public let video: String?  // nil = para la videollamada
        public let texto: String
        /// Cuántas iguales había al mandarla (en el servidor y antes en la cola): si el servidor tiene más, ya llegó.
        public var previas: Int = 0
    }

    /// Una duda que el servidor confirmó y todavía puede faltar en un `get` que salió antes de la confirmación.
    private struct Confirmada {
        let video: String?
        let texto: String
        /// Cuántas tiene que haber en el servidor con esta adentro.
        let esperadas: Int
        /// La última carga que había salido al confirmarse: una carga posterior ya la trae.
        let carga: Int
    }

    public private(set) var estado: Estado
    /// La guía que se ve: lo último del servidor (o la copia), con lo pendiente de la cola encima.
    public private(set) var guia: Guia?
    /// Lo que se ve vino de la copia guardada (sin red).
    public private(set) var desdeCache = false
    /// Para la tarjeta de inicio (`entregas_app_resumen`, o la guía abierta, que es más nueva).
    public private(set) var resumen: ResumenGuia?
    public private(set) var pendientes: [DudaPendiente] = []
    /// El último envío de cada recuadro: por video (id) y el de la videollamada (`""`).
    public private(set) var envios: [String: Envio] = [:]
    /// Lo escrito en cada recuadro (por video y `""` para la videollamada). Vive en el modelo para que un «no se pudo
    /// guardar» devuelva el texto aunque el cliente haya cambiado de video.
    public var borradores: [String: String] = [:]
    /// «Quitar de Entreno»: el cliente sacó la tarjeta antes de tiempo. Solo en el teléfono y por cliente (en la carpeta
    /// de su cuenta); en la demo, en memoria.
    public private(set) var quitadaDeEntreno = false
    /// Las dudas en audio del recuadro de la videollamada (`AudioDuda.swift`, entregas_019).
    public private(set) var audios: ModeloAudioDuda
    /// La agenda de la entrega al final de la guía (`Agenda.swift`, entregas_021). Sin la 021, no se ve nada.
    public private(set) var agenda: ModeloAgenda
    /// Cuándo se ocultó la tarjeta (2.2.0): una novedad posterior la hace volver. nil = sin marca, o una de antes de la 2.2.0.
    public private(set) var quitadaEn: Date?

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let outbox: Outbox?
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored private var cargaEnCurso: Task<Void, Never>?
    @ObservationIgnored private var resumenEnCurso = false
    /// La muestra de la maqueta: nunca toca la red.
    @ObservationIgnored private var esMuestra = false
    /// Cuántas cargas (`get`) salieron: para saber si una trae o no una duda recién confirmada.
    @ObservationIgnored private var cargas = 0
    @ObservationIgnored private var confirmadas: [Confirmada] = []

    static let archivoGuia = "guia.json"
    static let archivoResumen = "guia_resumen.json"
    static let archivoQuitada = "guia_quitada.json"
    /// Aparte del de la 2.1.0 (un Bool), así una vuelta atrás a la 2.1.0 lee la marca como siempre.
    static let archivoQuitadaEn = "guia_quitada_en.json"
    static let archivoBienvenida = "guia_bienvenida.json"
    static let archivoTarjetaVista = "guia_tarjeta_vista.json"

    public init(cliente: ClienteRPC, token: String, outbox: Outbox?, disco: Disco?) {
        self.cliente = cliente; self.token = token; self.outbox = outbox; self.disco = disco
        audios = ModeloAudioDuda(cliente: cliente, token: token, outbox: outbox, disco: disco)
        agenda = ModeloAgenda(cliente: cliente, token: token, outbox: outbox, disco: disco)
        let leida = disco?.leer(Guia.self, Self.archivoGuia)
        let copia = leida?.ok == true ? leida : nil
        guia = copia
        resumen = disco?.leer(ResumenGuia.self, Self.archivoResumen)
        estado = copia != nil ? .lista : .cargando
        quitadaDeEntreno = disco?.leer(Bool.self, Self.archivoQuitada) ?? false
        quitadaEn = disco?.leer(Double.self, Self.archivoQuitadaEn).map { Date(timeIntervalSince1970: $0) }
        bienvenidaVista = disco?.leer(Bool.self, Self.archivoBienvenida) ?? false
        let tarjetaVista = disco?.leer(Bool.self, Self.archivoTarjetaVista) ?? false
        primeraSesionTarjeta = !tarjetaVista
        tarjetaVistaGuardada = tarjetaVista
        // «Sin conexión» solo cuando el get falla (`traer`): mientras tanto se ve la copia sin aviso.
        desdeCache = false
    }

    // MARK: - Lectura

    /// Hay que mostrar la tarjeta de inicio: con videos, dentro de las 48 h después de la entrega (`mostrar_tarjeta`) y
    /// sin «Quitar de Entreno». Sale del resumen y de la copia: nunca llama al get.
    public var mostrarTarjeta: Bool { ReglasGuia.tarjetaEnEntreno(resumen, quitada: quitada) }
    /// La fila «Ver mi guía» de Mis datos (la tarjeta no está en Entreno y el resumen dijo `ok: true`).
    public var mostrarFila: Bool { ReglasGuia.filaEnMisDatos(resumen, quitada: quitada) }
    /// «Quitar de Entreno» tiene sentido solo con la tarjeta en Entreno.
    public var puedeQuitarDeEntreno: Bool { mostrarTarjeta }
    /// «Volver a mostrar en Entreno»: la quitó y `mostrar_tarjeta` todavía es true.
    public var puedeVolverAMostrar: Bool { ReglasGuia.puedeVolverAMostrar(resumen, quitada: quitada) }

    /// La marca de «Ocultar» que vale: sin `novedad_en`, la de la 2.1.0 tal cual; con una novedad posterior, la tarjeta vuelve.
    var quitada: Bool { ReglasGuia.quitadaVigente(quitada: quitadaDeEntreno, marca: quitadaEn, novedadEn: novedadEn) }

    // MARK: - Novedad (2.2.0)

    /// La de la última tanda nueva: la del resumen (más nuevo) o la de la copia.
    public var novedadEn: String? { resumen?.novedadEn ?? guia?.novedadEn }
    /// El avance de la tarjeta «NOVEDAD EN TU GUÍA» (solo los nuevos). nil = la tarjeta de la 2.1.0.
    public var avanceNovedad: ReglasGuia.Avance? { ReglasGuia.avanceNovedad(resumen, guia: guia) }

    // MARK: - Agenda (2.2.0)

    /// Los obligatorios que faltan según el teléfono (con lo de la cola encima): el respaldo del `faltan` del servidor.
    public var faltanLocal: Int? { guia.map { ReglasAgenda.faltan($0) } }
    /// Lo que muestra el final de la guía.
    public var vistaAgenda: ReglasAgenda.Vista { agenda.vista(faltanLocal: faltanLocal) }
    /// Cuántos faltan para el contador: el del servidor si lo mandó; si no, el del teléfono.
    public var faltanAgenda: Int { agenda.agenda?.faltan ?? faltanLocal ?? 0 }
    /// La reserva para el «Entrar» de la tarjeta de Entreno: la del resumen o la de la agenda, la que pueda entrar.
    public func reservaParaEntrar(ahora: Date = Date()) -> ReservaAgenda? {
        [agenda.reserva, resumen?.reserva].compactMap { $0 }.first { ReglasAgenda.puedeEntrar($0, ahora: ahora) }
    }

    public func quitarDeEntreno() { guardarQuitada(true) }
    public func volverAMostrarEnEntreno() { guardarQuitada(false) }

    /// El avance de la tarjeta (del resumen; sin resumen, vacío).
    public var avanceTarjeta: ReglasGuia.Avance {
        ReglasGuia.Avance(total: resumen?.total ?? 0, vistos: resumen?.vistos ?? 0, minutosRestantes: resumen?.minutosRestantes ?? 0)
    }
    /// La tarjeta va verde y protagonista (falta ver algo) o compacta (vio todo).
    /// Con novedad sin ver, también destacada (la compacta de «ya viste todo» va solo si vio también lo nuevo).
    public var tarjetaDestacada: Bool {
        mostrarTarjeta && (avanceNovedad != nil || ReglasGuia.estiloTarjeta(avanceTarjeta) == .destacada)
    }

    /// La bienvenida de la primera vez ya salió: una sola vez por cliente, guardado en el teléfono (en la muestra y la
    /// demo, en memoria).
    public private(set) var bienvenidaVista = false
    /// Hay que mostrar la bienvenida (sin ningún video visto, con la tarjeta en Entreno). Nunca llama al get.
    public var mostrarBienvenida: Bool {
        ReglasGuia.mostrarBienvenida(resumen, yaVista: bienvenidaVista, quitada: quitada)
    }
    public func marcarBienvenidaVista() {
        bienvenidaVista = true
        disco?.guardar(true, Self.archivoBienvenida)
    }

    /// Es la primera sesión en que se ve la tarjeta: el pulso suave del ícono va solo en esta. Se fija al arrancar y no
    /// cambia en todo el proceso; `marcarTarjetaVista` deja anotado que ya la vio para el próximo arranque.
    public let primeraSesionTarjeta: Bool
    public func marcarTarjetaVista() {
        guard !tarjetaVistaGuardada else { return }
        tarjetaVistaGuardada = true
        disco?.guardar(true, Self.archivoTarjetaVista)
    }
    @ObservationIgnored private var tarjetaVistaGuardada = false

    /// Ocultar guarda también la fecha (una novedad posterior la hace volver); volver a mostrar borra las dos.
    private func guardarQuitada(_ q: Bool, ahora: Date = Date()) {
        quitadaDeEntreno = q
        quitadaEn = q ? ahora : nil
        if q {
            disco?.guardar(true, Self.archivoQuitada)
            disco?.guardar(ahora.timeIntervalSince1970, Self.archivoQuitadaEn)
        } else {
            disco?.borrar(Self.archivoQuitada)
            disco?.borrar(Self.archivoQuitadaEn)
        }
    }

    /// Para los tests: ocultar con una fecha dada.
    func quitarDeEntreno(ahora: Date) { guardarQuitada(true, ahora: ahora) }

    /// Los clips de la lista, de «Viste X de N» y del reproductor, en el orden en que se muestran («Tu app» primero). Los
    /// que nombra un suplemento no van: se ven con «Ver por qué» (`clipDeSuplemento`).
    public var clips: [ClipGuia] { ReglasGuia.deLaLista(guia) }

    /// El clip del «Ver por qué» de un suplemento (con su avance y sus dudas al día).
    public func clipDeSuplemento(_ videoId: String?) -> ClipGuia? { ReglasGuia.clipDeSuplemento(guia, videoId: videoId) }

    /// `entregas_app_resumen`: solo lee. Al cargar la cuenta y al volver a primer plano (nunca en segundo plano). Sin
    /// red queda lo guardado.
    public func actualizarResumen() async {
        guard !resumenEnCurso, !esMuestra else { return }
        resumenEnCurso = true
        defer { resumenEnCurso = false }
        guard case .success(let j) = await cliente.llamar("entregas_app_resumen", ["p_token": .texto(token)]) else { return }
        let r = ResumenGuia(json: j)
        guard r.ok else { aplicarResumen(r); ocultar(); return }
        // Con avances todavía en la cola, el servidor cuenta menos de lo que el cliente ya vio: la tarjeta no retrocede.
        // Si hay guía guardada, se cuenta con ella (lo de la cola ya está encima); si no, nunca menos vistos que antes.
        let enCola = await outbox?.operaciones.contains { $0.kind == Self.kindAvance && $0.payload["visto"] == .bool(true) } ?? false
        if enCola, guia != nil {
            // La fecha y `mostrar_tarjeta` son del servidor; los conteos, de la guía con lo pendiente encima.
            resumen = Self.conFechas(resumen?.ok == true ? resumen! : r, de: r)
            await superponerPendientes()
        } else if enCola, let antes = resumen, antes.ok, antes.total == r.total, antes.vistos > r.vistos {
            aplicarResumen(Self.conFechas(antes, de: r))
        } else {
            aplicarResumen(r)
        }
        // Una reserva pendiente: al volver a primer plano se consulta la agenda, aunque la guía esté cerrada.
        await agenda.alVolver()
    }

    /// `entregas_app_get`: al abrir la sección. Si ya hay una carga en vuelo, se espera esa.
    public func abrir() async {
        if esMuestra { return }
        if let t = cargaEnCurso { await t.value; return }
        let t = Task { await self.traer() }
        cargaEnCurso = t
        await t.value
        cargaEnCurso = nil
    }

    private func traer() async {
        cargas += 1
        let carga = cargas
        switch await cliente.llamar("entregas_app_get", ["p_token": .texto(token)]) {
        case .failure:
            // Sin red o el servidor caído: lo guardado, si hay.
            if guia != nil {
                desdeCache = true
                estado = .lista
                await superponerPendientes()
            } else {
                estado = .sinRed
            }
        case .success(let j):
            var g = Guia(json: j)
            guard g.ok else { ocultar(); return }
            // Lo confirmado después de que salió este get todavía no viene: se pone encima (si ya viene, no se repite).
            for c in confirmadas where c.carga >= carga { Self.asegurar(c, en: &g) }
            confirmadas.removeAll { $0.carga < carga }
            guia = g
            desdeCache = false
            disco?.guardar(g, Self.archivoGuia)
            await superponerPendientes()
            estado = .lista
        }
    }

    private func ocultar() {
        guia = nil
        estado = .oculta
        desdeCache = false
        aplicarResumen(ResumenGuia(ok: false))
        disco?.borrar(Self.archivoGuia)
    }

    private func aplicarResumen(_ r: ResumenGuia) {
        resumen = r
        disco?.guardar(r, Self.archivoResumen)
    }

    /// Lo pendiente gana sobre lo que trajo el servidor (como en el resto de la app): el avance en la cola marca visto
    /// y suma segundos; las dudas en la cola se ven como «enviando».
    func superponerPendientes() async {
        guard let outbox else { pendientes = []; return }
        let ops = await outbox.operaciones
        var pend: [DudaPendiente] = []
        for op in ops {
            switch op.kind {
            case Self.kindAvance:
                guard let v = op.payload["video"]?.comoTexto else { continue }
                aplicarAvanceLocal(video: v, segundos: Int(op.payload["segundos"]?.comoNumero ?? 0),
                                   visto: op.payload["visto"] == .bool(true), guardarCopia: false)
            case Self.kindDuda:
                if let v = op.payload["video"]?.comoTexto, let t = op.payload["texto"]?.comoTexto {
                    pend.append(DudaPendiente(id: op.id, video: v, texto: t, previas: Int(op.payload["previas"]?.comoNumero ?? 0)))
                }
            case Self.kindDudaLlamada:
                if let t = op.payload["texto"]?.comoTexto {
                    pend.append(DudaPendiente(id: op.id, video: nil, texto: t, previas: Int(op.payload["previas"]?.comoNumero ?? 0)))
                }
            default: continue
            }
        }
        pendientes = pend
        recalcularResumen()
    }

    private func recalcularResumen() {
        guard let g = guia, g.ok else { return }
        // Como `entregas_012`: sin los videos de los suplementos, igual que «Viste X de N».
        let a = ReglasGuia.avance(ReglasGuia.deLaLista(g))
        // La fecha y `mostrar_tarjeta` siguen siendo los del último resumen (si no hubo, la fecha de la guía y la cuenta).
        let base = resumen?.ok == true ? resumen : nil
        // Lo de la 2.2.0 sigue al resumen; el avance de lo nuevo, a la guía si la guía sabe de esa tanda.
        let nuevos = ReglasGuia.deLaLista(g).filter(\.nuevo)
        let alDia = !nuevos.isEmpty && (base?.novedadEn == nil || base?.novedadEn == g.novedadEn)
        aplicarResumen(ResumenGuia(ok: true, total: a.total, vistos: a.vistos, minutosRestantes: (a.minutosRestantes * 10).rounded() / 10,
                                   fechaEntrega: base?.fechaEntrega ?? g.fechaEntrega, mostrarTarjetaServidor: base?.mostrarTarjetaServidor,
                                   novedadEn: base?.novedadEn ?? g.novedadEn, reserva: base?.reserva,
                                   nuevosTotal: alDia && base?.nuevosTotal != nil ? nuevos.count : base?.nuevosTotal,
                                   nuevosVistos: alDia && base?.nuevosTotal != nil ? nuevos.filter(\.visto).count : base?.nuevosVistos))
    }

    /// Los conteos de `conteos` con la fecha y `mostrar_tarjeta` de `r`.
    nonisolated static func conFechas(_ conteos: ResumenGuia, de r: ResumenGuia) -> ResumenGuia {
        var x = conteos
        x.fechaEntrega = r.fechaEntrega
        x.mostrarTarjetaServidor = r.mostrarTarjetaServidor
        x.novedadEn = r.novedadEn
        x.reserva = r.reserva
        // El avance de lo nuevo es un conteo: con avances en la cola, nunca menos vistos que los de `conteos`.
        if let t = r.nuevosTotal, let v = r.nuevosVistos {
            x.nuevosTotal = t
            x.nuevosVistos = conteos.nuevosTotal == t ? max(v, conteos.nuevosVistos ?? 0) : v
        } else {
            x.nuevosTotal = nil; x.nuevosVistos = nil
        }
        return x
    }

    // MARK: - Avance

    /// El avance de un video, por la cola (`entregas_app_avance`). Una sola op por video: gana la última, con el mayor de
    /// los segundos y visto si alguna lo tenía (la base hace lo mismo: toma el mayor y visto nunca vuelve a false).
    public func avance(video: String, segundos: Int, visto: Bool) async {
        guard let outbox else {
            // La demo (y la maqueta): el avance queda en memoria, como las demás escrituras de la demo. Nada sale.
            if esMuestra { aplicarAvanceLocal(video: video, segundos: min(ReglasGuia.maxSegundos, max(0, segundos)), visto: visto, guardarCopia: true) }
            return
        }
        let clave = "\(Self.kindAvance)_\(video)"
        let s = min(ReglasGuia.maxSegundos, max(0, segundos))
        let v = visto || guia?.clips.first(where: { $0.id == video })?.visto == true
        // Lo de la pantalla primero (no espera a la cola); la mezcla con lo pendiente es un solo paso del actor, así dos
        // avances seguidos del mismo video no se pisan.
        let faltabanAntes = faltanLocal ?? 0
        aplicarAvanceLocal(video: video, segundos: s, visto: v, guardarCopia: true)
        // Vio el último obligatorio: la agenda de nuevo (y otra vez cuando el avance llegue al servidor, en `alGuardar`).
        if faltabanAntes > 0, faltanLocal == 0, agenda.disponible { Task { await agenda.consultar() } }
        let op = await outbox.encolar(Self.kindAvance, dedupeKey: clave) { previa in
            Self.mezclarAvance(video: video, segundos: s, visto: v, previa: previa)
        }
        aplicarAvanceLocal(video: video, segundos: Int(op.payload["segundos"]?.comoNumero ?? 0),
                           visto: op.payload["visto"] == .bool(true), guardarCopia: true)
    }

    /// El mayor de los segundos y visto si alguno lo tenía (la base hace lo mismo).
    nonisolated static func mezclarAvance(video: String, segundos: Int, visto: Bool, previa: JSONValue?) -> JSONValue {
        let s = max(segundos, Int(previa?["segundos"]?.comoNumero ?? 0))
        let v = visto || previa?["visto"] == .bool(true)
        return .objeto(["video": .texto(video), "segundos": .numero(Double(s)), "visto": .bool(v)])
    }

    private func aplicarAvanceLocal(video: String, segundos: Int, visto: Bool, guardarCopia: Bool) {
        guard var g = guia, let i = g.clips.firstIndex(where: { $0.id == video }) else { return }
        let antes = g.clips[i]
        g.clips[i].segundos = max(antes.segundos, segundos)
        g.clips[i].visto = antes.visto || visto
        guard g.clips[i] != antes else { return }
        guia = g
        if guardarCopia {
            // La copia guardada sigue lo que el cliente vio: al volver sin red, lo visto sigue visto.
            disco?.guardar(g, Self.archivoGuia)
            if antes.visto != g.clips[i].visto { recalcularResumen() }
        }
    }

    // MARK: - Dudas

    /// La duda de un video (`entregas_app_duda`). Va por la cola y no se deduplica: dos dudas iguales son dos dudas. El
    /// texto sale del borrador de ese video. Devuelve false si no había nada que mandar.
    @discardableResult
    public func enviarDuda(video: String) async -> Bool {
        guard let outbox, let texto = ReglasGuia.textoParaMandar(borradores[video] ?? "") else { return false }
        borradores[video] = ""
        envios[video] = .enviando
        let previas = previasDe(texto, video: video)
        // `id`: el `p_id` de entregas_013, un uuid al azar armado una sola vez: cada reintento manda el mismo.
        let op = await outbox.encolar(Self.kindDuda, .objeto(["video": .texto(video), "texto": .texto(texto), "previas": .numero(Double(previas)),
                                                              "id": .texto(UUID().uuidString.lowercased())]), dedupeKey: nil)
        sumarPendiente(DudaPendiente(id: op.id, video: video, texto: texto, previas: previas))
        return true
    }

    /// Una duda para la videollamada (`entregas_app_llamada_duda`). Tope de 30, compartido con la web.
    @discardableResult
    public func enviarDudaLlamada() async -> Bool {
        guard let outbox, puedeSumarDudaLlamada, let texto = ReglasGuia.textoParaMandar(borradores[""] ?? "") else { return false }
        borradores[""] = ""
        envios[""] = .enviando
        let previas = previasDe(texto, video: nil)
        let op = await outbox.encolar(Self.kindDudaLlamada, .objeto(["texto": .texto(texto), "previas": .numero(Double(previas)),
                                                                     "id": .texto(UUID().uuidString.lowercased())]), dedupeKey: nil)
        sumarPendiente(DudaPendiente(id: op.id, video: nil, texto: texto, previas: previas))
        return true
    }

    /// La op pudo volver de la cola mientras se encolaba, o entrar ya por `superponerPendientes`: no se suma dos veces.
    private func sumarPendiente(_ d: DudaPendiente) {
        guard !alGuardarYa(d.id), !pendientes.contains(where: { $0.id == d.id }) else { return }
        pendientes.append(d)
    }

    /// Cuántas iguales hay en lo que se ve del servidor y en la cola (las de la cola salen antes que esta).
    private func previasDe(_ texto: String, video: String?) -> Int {
        vecesEnGuia(texto, video: video) + pendientes.filter { $0.video == video && $0.texto == texto }.count
    }

    private func vecesEnGuia(_ texto: String, video: String?) -> Int {
        guard let g = guia else { return 0 }
        if let video { return ReglasGuia.veces(texto, en: g.clips.first { $0.id == video }?.duda) }
        return ReglasGuia.veces(texto, en: g.dudasLlamada)
    }

    /// Las dudas de la cola que el servidor todavía no trae: si un get ya la trajo (se perdió la respuesta y está por
    /// reintentarse), no se ve ni se cuenta dos veces.
    public var pendientesSinLlegar: [DudaPendiente] {
        pendientes.filter { vecesEnGuia($0.texto, video: $0.video) <= $0.previas }
    }

    /// Cuántas dudas para la videollamada hay, contando las que están en la cola.
    public var dudasLlamadaContadas: Int { (guia?.dudasLlamada.count ?? 0) + pendientesSinLlegar.filter { $0.video == nil }.count }
    public var puedeSumarDudaLlamada: Bool { dudasLlamadaContadas < ReglasGuia.maxDudasLlamada }

    /// La op ya volvió de la cola mientras se encolaba (con red, `encolar` dispara la pasada enseguida).
    @ObservationIgnored private var resueltasAntes: Set<String> = []
    private func alGuardarYa(_ id: String) -> Bool { resueltasAntes.remove(id) != nil }

    /// Lo que la cola guardó (lo llama `ModeloApp`). `true` = guardado; `false` = la base no lo aceptó (tope o token):
    /// el texto vuelve a su recuadro con «No se pudo guardar».
    func alGuardar(_ ops: [OpGuardada]) {
        audios.alGuardar(ops)
        agenda.alGuardar(ops)
        // El último obligatorio llegó al servidor: ahora sí la agenda se habilita.
        if ops.contains(where: { $0.op.kind == Self.kindAvance && $0.op.payload["visto"] == .bool(true) }), faltanLocal == 0,
           agenda.disponible, agenda.agenda?.habilitada != true || agenda.agenda?.faltan ?? 0 > 0 {
            Task { await agenda.consultar() }
        }
        for g in ops where g.op.kind == Self.kindDuda || g.op.kind == Self.kindDudaLlamada {
            let video = g.op.kind == Self.kindDuda ? g.op.payload["video"]?.comoTexto : nil
            let texto = g.op.payload["texto"]?.comoTexto ?? ""
            if pendientes.contains(where: { $0.id == g.op.id }) { pendientes.removeAll { $0.id == g.op.id } } else { resueltasAntes.insert(g.op.id) }
            if g.respuesta == .bool(false) {
                devolver(texto, a: video ?? "")
            } else {
                let c = Confirmada(video: video, texto: texto, esperadas: Int(g.op.payload["previas"]?.comoNumero ?? 0) + 1, carga: cargas)
                confirmadas.append(c)
                if var gu = guia, Self.asegurar(c, en: &gu) { guia = gu; disco?.guardar(gu, Self.archivoGuia) }
                envios[video ?? ""] = .listo
            }
        }
    }

    /// Lo que la cola abandonó tras 8 intentos (va a fallidos): el texto vuelve al recuadro.
    func alAbandonar(_ ops: [Operacion]) {
        audios.alAbandonar(ops)
        agenda.alAbandonar(ops)
        for op in ops where op.kind == Self.kindDuda || op.kind == Self.kindDudaLlamada {
            if pendientes.contains(where: { $0.id == op.id }) { pendientes.removeAll { $0.id == op.id } } else { resueltasAntes.insert(op.id) }
            devolver(op.payload["texto"]?.comoTexto ?? "", a: op.kind == Self.kindDuda ? op.payload["video"]?.comoTexto ?? "" : "")
        }
    }

    private func devolver(_ texto: String, a clave: String) {
        let actual = borradores[clave] ?? ""
        borradores[clave] = actual.isEmpty ? texto : texto + "\n" + actual
        envios[clave] = .noSeGuardo
    }

    /// Que la duda confirmada se vea: si lo que hay tiene menos copias de las que tiene que haber, se suma (dos dudas iguales
    /// son dos dudas). Si un get ya la trajo, no se repite. Devuelve si cambió algo.
    @discardableResult
    private static func asegurar(_ c: Confirmada, en g: inout Guia) -> Bool {
        // Tope de vueltas: nunca un bucle sin fin con un texto raro.
        guard !c.texto.isEmpty else { return false }
        var vueltas = 0
        if let video = c.video {
            guard let i = g.clips.firstIndex(where: { $0.id == video }) else { return false }
            var cambio = false
            while ReglasGuia.veces(c.texto, en: g.clips[i].duda) < c.esperadas && vueltas < 5 {
                vueltas += 1
                g.clips[i].duda = g.clips[i].duda.map { $0 + "\n" + c.texto } ?? c.texto
                cambio = true
            }
            return cambio
        }
        var cambio = false
        while ReglasGuia.veces(c.texto, en: g.dudasLlamada) < c.esperadas && vueltas < 5 {
            vueltas += 1
            g.dudasLlamada.append(DudaLlamada(texto: c.texto, en: nil))
            cambio = true
        }
        return cambio
    }

    /// Las dudas de la videollamada que se pintan: sin las que ya se ven como transcripción de un audio.
    public var dudasLlamadaVisibles: [String] {
        ReglasAudioDuda.sinTranscriptos(guia?.dudasLlamada.map(\.texto) ?? [], transcriptos: audios.transcriptos)
    }

    /// Las pruebas de interfaz (DEBUG): las dudas en audio con una cola y un servidor de mentira.
    public func usarAudios(_ a: ModeloAudioDuda) { audios = a }

    // MARK: - Muestras

    /// La demo («Ver demo») y la maqueta: una guía armada, sin red ni token. Nada sale; el avance queda en memoria.
    /// `mostrarTarjeta`: el `mostrar_tarjeta` del resumen de muestra (nil = sin el campo, se cuenta con la fecha).
    /// `agenda`: la de la demo (2.2.0), que se habilita sola al ver los obligatorios. nil = sin agenda, como la 2.1.0.
    public init(muestra: Guia, mostrarTarjeta: Bool? = nil, agenda muestraAgenda: AgendaGuia? = nil) {
        cliente = ClienteRPC()
        token = ""
        outbox = nil
        disco = nil
        audios = ModeloAudioDuda(muestra: ())
        agenda = ModeloAgenda(muestra: muestraAgenda)
        guia = muestra
        esMuestra = true
        primeraSesionTarjeta = true
        estado = muestra.ok ? .lista : .oculta
        let a = ReglasGuia.avance(ReglasGuia.deLaLista(muestra))
        resumen = ResumenGuia(ok: muestra.ok, total: a.total, vistos: a.vistos, minutosRestantes: a.minutosRestantes,
                              fechaEntrega: muestra.fechaEntrega, mostrarTarjetaServidor: muestra.ok ? mostrarTarjeta : nil,
                              novedadEn: muestra.ok ? muestra.novedadEn : nil)
        agenda.faltanMuestra = { [weak self] in self?.faltanLocal ?? 0 }
    }
}
