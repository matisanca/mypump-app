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

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let outbox: Outbox?
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored private var cargaEnCurso: Task<Void, Never>?
    @ObservationIgnored private var resumenEnCurso = false
    /// La muestra de la maqueta: nunca toca la red.
    @ObservationIgnored private var esMuestra = false

    static let archivoGuia = "guia.json"
    static let archivoResumen = "guia_resumen.json"

    public init(cliente: ClienteRPC, token: String, outbox: Outbox?, disco: Disco?) {
        self.cliente = cliente; self.token = token; self.outbox = outbox; self.disco = disco
        let leida = disco?.leer(Guia.self, Self.archivoGuia)
        let copia = leida?.ok == true ? leida : nil
        guia = copia
        resumen = disco?.leer(ResumenGuia.self, Self.archivoResumen)
        estado = copia != nil ? .lista : .cargando
        desdeCache = copia != nil
    }

    // MARK: - Lectura

    /// Hay que mostrar la tarjeta de inicio.
    public var mostrarTarjeta: Bool { resumen?.hayGuia == true }

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
        aplicarResumen(r)
        if !r.ok { ocultar() }
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
            let g = Guia(json: j)
            guard g.ok else { ocultar(); return }
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
                if let v = op.payload["video"]?.comoTexto, let t = op.payload["texto"]?.comoTexto { pend.append(DudaPendiente(id: op.id, video: v, texto: t)) }
            case Self.kindDudaLlamada:
                if let t = op.payload["texto"]?.comoTexto { pend.append(DudaPendiente(id: op.id, video: nil, texto: t)) }
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
        aplicarResumen(ResumenGuia(ok: true, total: a.total, vistos: a.vistos, minutosRestantes: (a.minutosRestantes * 10).rounded() / 10))
    }

    // MARK: - Avance

    /// El avance de un video, por la cola (`entregas_app_avance`). Una sola op por video: gana la última, con el mayor de
    /// los segundos y visto si alguna lo tenía (la base hace lo mismo: toma el mayor y visto nunca vuelve a false).
    public func avance(video: String, segundos: Int, visto: Bool) async {
        guard let outbox else { return }
        let clave = "\(Self.kindAvance)_\(video)"
        var s = min(ReglasGuia.maxSegundos, max(0, segundos))
        var v = visto
        if let previa = await outbox.pendientesPorClave()[clave] {
            s = max(s, Int(previa.payload["segundos"]?.comoNumero ?? 0))
            v = v || previa.payload["visto"] == .bool(true)
        }
        if let c = guia?.clips.first(where: { $0.id == video }), c.visto { v = true }
        aplicarAvanceLocal(video: video, segundos: s, visto: v, guardarCopia: true)
        await outbox.encolar(Self.kindAvance, .objeto(["video": .texto(video), "segundos": .numero(Double(s)), "visto": .bool(v)]), dedupeKey: clave)
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
        let op = await outbox.encolar(Self.kindDuda, .objeto(["video": .texto(video), "texto": .texto(texto)]), dedupeKey: nil)
        if !alGuardarYa(op.id) { pendientes.append(DudaPendiente(id: op.id, video: video, texto: texto)) }
        return true
    }

    /// Una duda para la videollamada (`entregas_app_llamada_duda`). Tope de 30, compartido con la web.
    @discardableResult
    public func enviarDudaLlamada() async -> Bool {
        guard let outbox, puedeSumarDudaLlamada, let texto = ReglasGuia.textoParaMandar(borradores[""] ?? "") else { return false }
        borradores[""] = ""
        envios[""] = .enviando
        let op = await outbox.encolar(Self.kindDudaLlamada, .objeto(["texto": .texto(texto)]), dedupeKey: nil)
        if !alGuardarYa(op.id) { pendientes.append(DudaPendiente(id: op.id, video: nil, texto: texto)) }
        return true
    }

    /// Cuántas dudas para la videollamada hay, contando las que están en la cola.
    public var dudasLlamadaContadas: Int { (guia?.dudasLlamada.count ?? 0) + pendientes.filter { $0.video == nil }.count }
    public var puedeSumarDudaLlamada: Bool { dudasLlamadaContadas < ReglasGuia.maxDudasLlamada }

    /// La op ya volvió de la cola mientras se encolaba (con red, `encolar` dispara la pasada enseguida).
    @ObservationIgnored private var resueltasAntes: Set<String> = []
    private func alGuardarYa(_ id: String) -> Bool { resueltasAntes.remove(id) != nil }

    /// Lo que la cola guardó (lo llama `ModeloApp`). `true` = guardado; `false` = la base no lo aceptó (tope o token):
    /// el texto vuelve a su recuadro con «No se pudo guardar».
    func alGuardar(_ ops: [OpGuardada]) {
        for g in ops where g.op.kind == Self.kindDuda || g.op.kind == Self.kindDudaLlamada {
            let video = g.op.kind == Self.kindDuda ? g.op.payload["video"]?.comoTexto : nil
            let texto = g.op.payload["texto"]?.comoTexto ?? ""
            if pendientes.contains(where: { $0.id == g.op.id }) { pendientes.removeAll { $0.id == g.op.id } } else { resueltasAntes.insert(g.op.id) }
            if g.respuesta == .bool(false) {
                devolver(texto, a: video ?? "")
            } else {
                sumarDuda(texto, video: video)
                envios[video ?? ""] = .listo
            }
        }
    }

    /// Lo que la cola abandonó tras 8 intentos (va a fallidos): el texto vuelve al recuadro.
    func alAbandonar(_ ops: [Operacion]) {
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

    /// Suma la duda guardada a lo que se ve. Siempre: dos dudas iguales son dos dudas (no se compara con la última). Si una
    /// apertura que salió justo después del guardado ya la trajo, se ve dos veces hasta la próxima apertura (solo en
    /// pantalla; en la base está una vez).
    private func sumarDuda(_ texto: String, video: String?) {
        guard var g = guia else { return }
        if let video {
            guard let i = g.clips.firstIndex(where: { $0.id == video }) else { return }
            g.clips[i].duda = g.clips[i].duda.map { $0 + "\n" + texto } ?? texto
        } else {
            g.dudasLlamada.append(DudaLlamada(texto: texto, en: nil))
        }
        guia = g
        disco?.guardar(g, Self.archivoGuia)
    }

    // MARK: - Muestras

    /// La maqueta y las capturas (DEBUG en la app): una guía armada, sin red ni token. Nada sale.
    public init(muestra: Guia) {
        cliente = ClienteRPC()
        token = ""
        outbox = nil
        disco = nil
        guia = muestra
        esMuestra = true
        estado = muestra.ok ? .lista : .oculta
        let a = ReglasGuia.avance(ReglasGuia.deLaLista(muestra))
        resumen = ResumenGuia(ok: muestra.ok, total: a.total, vistos: a.vistos, minutosRestantes: a.minutosRestantes)
    }
}
