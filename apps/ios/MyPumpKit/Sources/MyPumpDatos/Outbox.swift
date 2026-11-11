import Foundation
import MyPumpModelos
import MyPumpReglas

/// Una escritura pendiente. Mismo formato que la cola de la web (`mypump_outbox_<TOKEN>`), así las ops que trae la
/// migración del almacenamiento viejo entran tal cual.
public struct Operacion: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public var payload: JSONValue
    public let dedupeKey: String?
    public var tries: Int
    public let ts: Double   // ms desde 1970, como Date.now()
    /// Vino de la cola de la Capacitor (la migración). Con la palanca remota `migracion_ops_legadas` apagada no se manda:
    /// queda en la cola hasta que se vuelva a prender (revisión del 15-oct, hallazgo 2). nil en las nativas.
    public var legado: Bool?
    /// Ya salió una vez (`Outbox.anotanIntento`): pudo haber llegado aunque no volvió la respuesta. nil si nunca salió.
    public var intentada: Bool?
    /// Un audio de «Tu guía» que espera a que se terminen de mandar otros (`pendientes`): desde cuándo (ms). Con más de 2 h
    /// esperando va a fallidos. nil si nunca esperó.
    public var esperaDesde: Double?
    /// F5 (auditoría 10/11): cuándo la rechazó el servidor por primera vez (ms). Se abandona recién pasada la ventana de
    /// `Outbox.ventanaAbandono`, no al minuto. nil si nunca la rechazó.
    public var primerRechazo: Double?

    public init(id: String, kind: String, payload: JSONValue, dedupeKey: String?, tries: Int = 0, ts: Double, legado: Bool? = nil,
                intentada: Bool? = nil, esperaDesde: Double? = nil, primerRechazo: Double? = nil) {
        self.id = id; self.kind = kind; self.payload = payload; self.dedupeKey = dedupeKey; self.tries = tries; self.ts = ts
        self.legado = legado; self.intentada = intentada; self.esperaDesde = esperaDesde; self.primerRechazo = primerRechazo
    }

    enum CodingKeys: String, CodingKey { case id = "_id", kind, payload, dedupeKey, tries, ts, legado, intentada, esperaDesde, primerRechazo }
}

/// El aviso de guardado que ve el cliente (el toast de la web, `showSaveState`).
public enum EstadoGuardado: Sendable, Equatable {
    case quieto
    case guardando          // solo si el envío tarda más de 900 ms
    case guardado           // solo después de un problema: reasegura
    case sinConexion        // "se reintenta solo"
    case perdido            // algo se abandonó: "revisá y cargalo de nuevo" (9 s)
}

extension Operacion {
    /// La misma op con los números no finitos de su payload como null (ver `JSONValue.sinNoFinitos`).
    var sinNoFinitos: Operacion {
        var o = self
        o.payload = payload.sinNoFinitos
        return o
    }
}

extension JSONValue {
    /// Lo que no tiene JSON (NaN, infinito) como null, como hace `JSON.stringify` de la web. `JSONEncoder` tira con eso:
    /// ni la cola se podía guardar ni la RPC armar su pedido.
    var sinNoFinitos: JSONValue {
        switch self {
        case .numero(let d) where !d.isFinite: return .null
        case .lista(let a): return .lista(a.map(\.sinNoFinitos))
        case .objeto(let o): return .objeto(o.mapValues(\.sinNoFinitos))
        default: return self
        }
    }
}

/// Una op que el servidor guardó, con lo que contestó (para el chat, el id de la fila: `agregar_comentario`).
public struct OpGuardada: Sendable {
    public let op: Operacion
    public let respuesta: JSONValue
}

/// Qué pasó al ejecutar una op. El ejecutor (la app) llama a la RPC y devuelve la respuesta cruda.
public enum ResultadoOp: Sendable {
    case respuesta(Result<JSONValue, ErrorRPC>)
    /// El token del cliente cayó: la op se estaciona sin gastar intentos (arreglo nativo #3 de la paridad).
    case tokenCaido
}

/// La cola de escrituras: la misma semántica que el Outbox de la web (cliente.html:2687-2968), con cuatro arreglos a
/// propósito: el dedupe con semana lo arma quien encola; un kind desconocido o una op abandonada van a FALLIDOS (no se
/// pierden); un token caído estaciona; el chat lo maneja la app con "en vuelo".
///
/// Reglas que se conservan tal cual:
/// - Encolar borra las pendientes con el mismo `dedupeKey` (gana la última) y agrega al final.
/// - Se procesa una COPIA de la cola: lo encolado durante el vuelo no se pierde.
/// - `null`, `0` y `[]` cuentan como NO guardado (la base rechaza devolviendo vacío).
/// - Red y transitorio cortan la pasada sin gastar intento; cualquier otro fallo suma uno; con 8, se abandona.
/// - Backoff `min(30 s, 2 s × max(1, intentos de la primera, racha sin red))`.
/// - `drenar()` comparte la pasada en curso: esperarla es esperar el envío de verdad (cerrar el día depende de eso).
///
/// Los audios de «Tu guía» (`guia_audio`) van por un carril aparte (`pasadaAudios`): una subida lenta, sin red o que espera
/// a otros audios no corta la pasada de las demás ni la hace esperar («cerrar el día» no espera a los audios). Red,
/// transitorio y `pendientes` no gastan intento y tienen su propio backoff de hasta 30 s; `pendientes`, con un tope de 2 h
/// (revisión adversarial del 4-nov, puntos 1 y 16).
public actor Outbox {
    public typealias Ejecutor = @Sendable (Operacion) async throws -> ResultadoOp

    struct Persistido: Codable {
        var ops: [Operacion] = []
        var fallidos: [Fallido] = []
    }

    public struct Fallido: Codable, Sendable, Equatable {
        public let op: Operacion
        public let motivo: String
        public let cuando: Double
        /// F5: la abandonó la cola tras sus intentos (se puede volver a mandar con «Reintentar»). nil en las que se
        /// archivan a propósito (de la migración, de un tipo que esta versión no conoce).
        public var reintentable: Bool?
    }

    public let maxIntentos: Int
    /// F5 (auditoría 10/11): lo mínimo que se sigue intentando una op rechazada antes de abandonarla (ms). Antes eran los
    /// 8 intentos, más o menos un minuto: un mal rato del servidor o una versión publicada con un cambio la perdía.
    public let ventanaAbandono: Double
    private let archivo: URL?
    private var ejecutor: Ejecutor
    private var estado = Persistido()
    private var enVuelo: Task<Void, Never>?
    private var temporizador: Task<Void, Never>?
    private var huboProblema = false
    /// La última pasada dejó algo sin guardar (sin red, transitorio, rechazo o token caído).
    private var ultimaFallo = false
    /// La última pasada se cortó (sin red, transitorio o token caído): lo que venía detrás ni se intentó.
    private var ultimaCorte = false
    /// Los ids que intentó la última pasada (su copia de la cola). Lo encolado durante el vuelo no está acá.
    private var ultimaTanda: Set<String> = []
    private var rachaSinRed = 0
    /// El carril de los audios: su pasada en curso, su temporizador y su racha (el backoff).
    private var enVueloAudios: Task<Void, Never>?
    private var temporizadorAudios: Task<Void, Never>?
    private var rachaAudios = 0
    /// Los audios cuyo último intento falló por red o transitorio (en memoria): la pantalla muestra «No se pudo mandar.»
    /// aunque la cola lo siga reintentando sola.
    public private(set) var audiosSinRed: Set<String> = []
    private var alEsperarAudio: (@Sendable ([Operacion]) -> Void)?
    /// ms desde 1970 (los tests lo mueven para el tope de 2 h de `pendientes`).
    private let reloj: @Sendable () -> Double
    private var secuencia = 0
    private var alCambiar: (@Sendable (EstadoGuardado) -> Void)?
    private var alAbandonar: (@Sendable ([Operacion]) -> Void)?
    private var alGuardar: (@Sendable ([OpGuardada]) -> Void)?
    /// En los tests se apaga el reintento automático para forzar las pasadas a mano, como `await Outbox.flush()`.
    private let reintentoAutomatico: Bool
    /// Las ops de la migración (`legado`) no salen: la palanca remota está apagada o todavía no se leyó. Las nativas
    /// salen igual.
    private var retenerLegadas: Bool
    /// Los `swap` y `swap_del` esperan a que se decida qué reemplazos de comida del teléfono nunca llegaron al servidor
    /// (`soltarSwaps`). Si salía uno antes, viejo o nativo, el servidor «ya tenía algo», ganaba la mezcla y se perdían los
    /// que estaban solo en el teléfono (sim-migracion.sh y la revisión adversarial del 15-oct). Se arma solo si hay un mapa
    /// de reemplazos sin la marca de migrados: a quien ya migró no lo demora.
    private var retenerSwaps: Bool

    /// `retenerLegadas`: la app arranca reteniendo las ops de la migración hasta leer la palanca (`usarPalanca`), así un
    /// toque antes de la primera carga no las manda con la palanca apagada.
    public init(archivo: URL?, maxIntentos: Int = 8, ventanaAbandono: Double = 0, reintentoAutomatico: Bool = true, retenerLegadas: Bool = false,
                retenerSwaps: Bool = false, reloj: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 * 1000 },
                ejecutor: @escaping Ejecutor) {
        self.archivo = archivo
        self.reloj = reloj
        self.maxIntentos = maxIntentos
        self.ventanaAbandono = ventanaAbandono
        self.ejecutor = ejecutor
        self.reintentoAutomatico = reintentoAutomatico
        self.retenerLegadas = retenerLegadas
        self.retenerSwaps = retenerSwaps
        if let archivo, let d = try? Data(contentsOf: archivo), let p = try? JSONDecoder().decode(Persistido.self, from: d) {
            estado = p
        }
    }

    /// `guardadas`: lo que el servidor guardó en cada pasada, con su respuesta (el chat saca con eso la burbuja "enviando…"
    /// de un mensaje que el servidor deduplicó; hallazgo 7).
    public func observar(estado: @escaping @Sendable (EstadoGuardado) -> Void, abandonadas: @escaping @Sendable ([Operacion]) -> Void,
                         guardadas: (@Sendable ([OpGuardada]) -> Void)? = nil) {
        alCambiar = estado
        alAbandonar = abandonadas
        alGuardar = guardadas
    }

    public func cambiarEjecutor(_ e: @escaping Ejecutor) { ejecutor = e }

    /// Los audios que fallaron por red o transitorio (siguen en la cola): para «No se pudo mandar.» con «Reintentar».
    public func observarAudios(sinRed: @escaping @Sendable ([Operacion]) -> Void) { alEsperarAudio = sinRed }

    /// El carril propio (`pasadaAudios`): los audios de la guía y la reserva de la entrega (2.2.0), que tampoco tiene que
    /// frenar ni esperar a las demás.
    static func esAudio(_ op: Operacion) -> Bool {
        op.kind == ModeloAudioDuda.kind || op.kind == ModeloAgenda.kind || op.kind == ModeloChat.kindAdjunto
    }

    /// Lo que dijo la palanca remota (`migracion_ops_legadas`): con false, las ops de la migración quedan en la cola sin
    /// mandarse; al volver a true salen en la próxima pasada.
    public func usarPalanca(opsLegadas: Bool) {
        let antes = retenerLegadas
        retenerLegadas = !opsLegadas
        if antes, opsLegadas, estado.ops.contains(where: { $0.legado == true }) { programar(en: .zero) }
    }

    /// Ya se decidió qué reemplazos de comida del teléfono hay que subir (`hidratarDieta` o la Fase R): los `swap` y
    /// `swap_del` pueden salir.
    public func soltarSwaps() {
        guard retenerSwaps else { return }
        retenerSwaps = false
        if estado.ops.contains(where: { Self.esSwap($0.kind) && mandable($0) }) { programar(en: .zero) }
    }

    /// Llegó un mapa de reemplazos sin decidir después de crear la cola (los de otra carpeta de la misma persona).
    public func retenerSwapsHastaDecidir() { retenerSwaps = true }

    private static func esSwap(_ kind: String) -> Bool { kind == "swap" || kind == "swap_del" }

    private func mandable(_ op: Operacion) -> Bool {
        if retenerSwaps && Self.esSwap(op.kind) { return false }
        return !(retenerLegadas && op.legado == true)
    }

    public var pendientes: Int { estado.ops.count }
    public var operaciones: [Operacion] { estado.ops }
    public var fallidos: [Fallido] { estado.fallidos }

    /// Lo pendiente con su payload, por `dedupeKey`: lo que se pinta encima de lo que trae el servidor.
    public func pendientesPorClave() -> [String: Operacion] {
        var m: [String: Operacion] = [:]
        for op in estado.ops { if let k = op.dedupeKey { m[k] = op } }
        return m
    }

    @discardableResult
    public func encolar(_ kind: String, _ payload: JSONValue, dedupeKey: String?) -> Operacion {
        if let k = dedupeKey { estado.ops.removeAll { $0.dedupeKey == k } }
        secuencia += 1
        let ahora = Date().timeIntervalSince1970 * 1000
        let op = Operacion(id: "\(Int64(ahora))_\(secuencia)", kind: kind, payload: payload.sinNoFinitos, dedupeKey: dedupeKey, ts: ahora)
        estado.ops.append(op)
        guardar()
        if Self.esAudio(op) { reintentarAudiosAhora() } else { programar(en: .zero) }
        return op
    }

    /// `encolar` con la op pendiente de la misma clave a la vista, en un solo paso del actor: leer lo previo, mezclar y
    /// reemplazar no se puede intercalar con otro `encolar` de la misma clave (el avance de «Tu guía», que sale cada 10 s).
    @discardableResult
    public func encolar(_ kind: String, dedupeKey: String, mezclando mezcla: @Sendable (JSONValue?) -> JSONValue) -> Operacion {
        let previa = estado.ops.last { $0.dedupeKey == dedupeKey }?.payload
        return encolar(kind, mezcla(previa), dedupeKey: dedupeKey)
    }

    /// Mete ops que ya existían (la migración del almacenamiento viejo), sin ejecutar, respetando el orden.
    public func importar(_ ops: [Operacion]) {
        for op in ops where !estado.ops.contains(where: { $0.id == op.id }) {
            if let k = op.dedupeKey { estado.ops.removeAll { $0.dedupeKey == k } }
            estado.ops.append(op)
        }
        guardar()
    }

    /// `importar` para la migración del almacenamiento viejo, con una regla más: lo pendiente MÁS NUEVO gana. Una op
    /// vieja no pisa a una nativa posterior con la misma `dedupeKey` (pasa si el cliente usó la nativa, volvió a la
    /// Capacitor y vuelve). Devuelve las que entraron, en orden.
    @discardableResult
    public func importarSinPisar(_ ops: [Operacion]) -> [Operacion] {
        let entraron = estado.importarSinPisar(ops)
        guardar()
        return entraron
    }

    /// Lo que quedó en la cola de otra carpeta de la MISMA persona (un link que Mati regeneró; revisión del 15-oct,
    /// hallazgo 4). Las pendientes entran con la regla de `importarSinPisar` (sin repetir ids; lo pendiente más nuevo
    /// gana) y conservan su marca: no son de la migración. Los fallidos siguen siendo fallidos: no se mandan (algunos
    /// están "para revisar"), pero tampoco se pierden. No dispara una pasada: salen con el `drenar()` de la carga, después
    /// de que quien adopta anota lo que se llevó. Devuelve las pendientes que quedaron en la cola.
    @discardableResult
    public func adoptar(_ ops: [Operacion], fallidos: [Fallido]) -> [Operacion] {
        let entraron = estado.importarSinPisar(ops, deLaMigracion: false)
        for f in fallidos where !estado.fallidos.contains(where: { $0.op.id == f.op.id }) { estado.fallidos.append(f) }
        guardar()
        return entraron
    }

    /// Ops que no se mandan pero tampoco se pueden perder: quedan en fallidos con su motivo, como una abandonada. La
    /// migración manda acá las ops viejas sin sesión que no pasan la validación contra la rutina activa ("para revisar").
    public func archivarEnFallidos(_ ops: [Operacion], motivo: String) {
        let ahora = Date().timeIntervalSince1970 * 1000
        for op in ops where !estado.fallidos.contains(where: { $0.op.id == op.id }) {
            estado.ops.removeAll { $0.id == op.id }
            estado.fallidos.append(Fallido(op: op, motivo: motivo, cuando: ahora))
        }
        guardar()
    }

    /// F5: lo que la cola abandonó y el cliente puede volver a mandar (sin las silenciosas, los audios ni el chat, que tienen
    /// su propio «Reintentar» en su pantalla).
    public var perdidos: [Fallido] {
        estado.fallidos.filter { $0.reintentable == true && !Self.silenciosas.contains($0.op.kind) && !Self.esAudio($0.op) && $0.op.kind != "chat" }
    }

    /// F5: «Reintentar» de «No se pudo guardar»: lo perdido vuelve a la cola con los intentos en cero (si ya hay una más
    /// nueva con la misma clave, gana esa y la vieja se descarta). Devuelve cuántas volvieron.
    @discardableResult
    public func reintentarPerdidos() -> Int {
        let lista = perdidos
        guard !lista.isEmpty else { return 0 }
        let ids = Set(lista.map(\.op.id))
        estado.fallidos.removeAll { ids.contains($0.op.id) }
        var vueltas = 0
        for f in lista.sorted(by: { $0.op.ts < $1.op.ts }) {
            if let k = f.op.dedupeKey, estado.ops.contains(where: { $0.dedupeKey == k }) { continue }
            var op = f.op
            op.tries = 0
            op.primerRechazo = nil
            estado.ops.append(op)
            vueltas += 1
        }
        guardar()
        if vueltas > 0 { programar(en: .zero) }
        return vueltas
    }

    /// Olvida los fallidos con esa clave (una op posterior con la misma clave se guardó: ya no hay nada que se perdió).
    public func olvidarFallidos(clave: String) {
        let antes = estado.fallidos.count
        estado.fallidos.removeAll { $0.op.dedupeKey == clave }
        if estado.fallidos.count != antes { guardar() }
    }

    /// Vacía la cola: pasadas hasta que no quede nada o hasta que una falle (sin red, el servidor mal, un rechazo).
    /// Si ya hay una pasada en curso, la espera y sigue con lo que se encoló mientras tanto: así "cerrar el día" espera
    /// el envío de TODO lo anterior.
    public func drenar() async {
        // Los audios salen por su carril, sin que esto los espere.
        if temporizadorAudios == nil, enVueloAudios == nil, estado.ops.contains(where: { Self.esAudio($0) && mandable($0) }) {
            programarAudios(en: .zero)
        }
        for _ in 0..<6 {
            if let t = enVuelo {
                await t.value
            } else {
                // `enVuelo` lo suelta la misma pasada al terminar, ANTES de programar la siguiente: si lo soltara quien
                // la creó (después de `await`), el temporizador podía encontrarla "en vuelo" ya terminada, esperarla y
                // volver sin pasada, con lo encolado durante el vuelo trabado (lo encontró la revisión: 15 de 200).
                let t = Task { await self.pasada(); self.enVuelo = nil }
                enVuelo = t
                await t.value
            }
            // Un rechazo en la pasada no frena lo que se encoló mientras volaba: esa pasada ni lo vio (con una sustitución
            // rechazada en vuelo, «cerrar el día» cerraba la sesión sin la última serie; «hoy no la como» dejaba la marca en
            // el servidor hasta el reintento). Un corte (sin red) sí frena todo: la próxima pasada también se cortaría.
            let quedan = estado.ops.filter { mandable($0) && !Self.esAudio($0) }
            if quedan.isEmpty { return }
            if ultimaFallo && (ultimaCorte || quedan.allSatisfy({ ultimaTanda.contains($0.id) })) { return }
        }
    }

    private func programar(en demora: Duration) {
        guard reintentoAutomatico else { return }
        if temporizador != nil { return }
        temporizador = Task { [weak self] in
            try? await Task.sleep(for: demora)
            guard !Task.isCancelled else { return }
            await self?.dispararTemporizador()
        }
    }

    private func dispararTemporizador() async {
        temporizador = nil
        await drenar()
    }

    private func pasada() async {
        ultimaFallo = false
        ultimaCorte = false
        let tanda = estado.ops.filter { mandable($0) && !Self.esAudio($0) }
        ultimaTanda = Set(tanda.map(\.id))
        guard !tanda.isEmpty else { return }
        let hayVisibles = tanda.contains { !Self.silenciosas.contains($0.kind) }
        var resueltas = Set<String>()
        var abandonadas: [Operacion] = []
        /// El motivo de las que van directo a fallidos sin gastar intentos (un kind desconocido, un audio con `id`).
        var motivoDirecto: [String: String] = [:]
        var guardadas: [OpGuardada] = []
        var algunaFallo = false
        // "Guardando…" solo si tarda. Ojo: `try? await Task.sleep` se traga la cancelación y sigue de largo; sin el
        // chequeo, el aviso salía DESPUÉS de terminar y pisaba al de "perdido" (lo encontró el test).
        let lenta = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, hayVisibles else { return }
            await self?.avisar(.guardando)
        }

        for op in tanda {
            // Un mensaje del chat que sale puede llegar aunque la respuesta se pierda: se anota ANTES de mandarlo (también
            // vale si la app se cierra con el pedido en vuelo). La op que se ejecuta es la copia de antes: la primera vez
            // sale directo y solo un reintento mira si ya había llegado (`Escrituras.yaLlego`; hallazgo 7).
            if Self.anotanIntento.contains(op.kind), op.intentada != true, let i = estado.ops.firstIndex(where: { $0.id == op.id }) {
                estado.ops[i].intentada = true
                guardar()
            }
            let resultado: ResultadoOp
            do {
                resultado = try await ejecutor(op)
            } catch let e as URLError {
                _ = e; algunaFallo = true; ultimaCorte = true; rachaSinRed += 1; break           // un throw de red: no gasta intento
            } catch {
                // Un bug nuestro no es un corte de red: gasta intento y no congela a las de atrás.
                if registrarFallo(op, motivo: "excepción: \(error)", resueltas: &resueltas, abandonadas: &abandonadas) { algunaFallo = true }
                continue
            }
            switch resultado {
            case .tokenCaido:
                algunaFallo = true
                rachaSinRed += 1
            case .respuesta(.success(let json)) where Self.seGuardo(json):
                resueltas.insert(op.id)
                guardadas.append(OpGuardada(op: op, respuesta: json))
                continue
            case .respuesta(.failure(let e)) where e.clase != .permanente:
                algunaFallo = true
                rachaSinRed += 1
            case .respuesta(.failure(let e)) where e.codigo == "KIND_DESCONOCIDO" || e.codigo == Escrituras.codigoAudioId
                || ReglasChatAdjuntos.codigosDirectos.contains(e.codigo ?? ""):
                // Lo que no va a entrar nunca así (y el tope del día de los adjuntos del chat): directo a «no salió».
                abandonadas.append(op)
                motivoDirecto[op.id] = e.codigo
                resueltas.insert(op.id)
                continue
            case .respuesta(let r):
                let motivo: String
                if case .failure(let e) = r { motivo = "\(e.codigo ?? "\(e.status)"): \(e.mensaje)" } else { motivo = "la base devolvió vacío" }
                if registrarFallo(op, motivo: motivo, resueltas: &resueltas, abandonadas: &abandonadas) { algunaFallo = true }
                continue
            }
            ultimaCorte = true
            break   // red, transitorio o token caído: no tiene sentido seguir con las demás
        }
        lenta.cancel()

        if !resueltas.isEmpty {
            estado.ops.removeAll { resueltas.contains($0.id) }
            rachaSinRed = 0
        }
        if !abandonadas.isEmpty {
            let ahora = Date().timeIntervalSince1970 * 1000
            estado.fallidos.append(contentsOf: abandonadas.map {
                Fallido(op: $0, motivo: motivoDirecto[$0.id] ?? "abandonada tras \($0.tries) intentos", cuando: ahora,
                        reintentable: motivoDirecto[$0.id] == nil ? true : nil)
            })
        }
        guardar()

        if !guardadas.isEmpty { alGuardar?(guardadas) }
        // Las silenciosas (SER-14) no avisan: lo que el cliente hizo ya quedó en el teléfono.
        let abandonadasVisibles = abandonadas.filter { !Self.silenciosas.contains($0.kind) }
        if !abandonadas.isEmpty { alAbandonar?(abandonadas) }
        if !abandonadasVisibles.isEmpty {
            huboProblema = false
            avisar(.perdido)
        }
        ultimaFallo = algunaFallo
        // Si lo que falló fue solo silencioso, para el cliente la pasada salió bien: se cierra el "Guardando…" que haya.
        if algunaFallo && estado.ops.contains(where: { !Self.silenciosas.contains($0.kind) }) {
            huboProblema = true
            if abandonadasVisibles.isEmpty { avisar(.sinConexion) }
        } else if huboProblema {
            huboProblema = false
            avisar(.guardado)
        } else if abandonadasVisibles.isEmpty {
            avisar(.quieto)
        }
        if algunaFallo {
            let base = max(1, estado.ops.first(where: { !Self.esAudio($0) })?.tries ?? 1, rachaSinRed)
            programar(en: .milliseconds(min(30_000, 2_000 * base)))
        }
        // Lo encolado DURANTE esta pasada quedó sin procesar: otra vuelta.
        if estado.ops.contains(where: { !Self.esAudio($0) }) && !algunaFallo { programar(en: .zero) }
    }

    // MARK: - El carril de los audios

    /// El tope de `pendientes`: pasado esto, el audio va a fallidos («No se pudo mandar» con «Reintentar»).
    public static let topeEsperaAudio: Double = 2 * 3600 * 1000

    /// Una pasada del carril de los audios, compartiendo la que esté en curso (los tests la fuerzan a mano).
    public func drenarAudios() async {
        if let t = enVueloAudios { await t.value; return }
        let t = Task { await self.pasadaAudios(); self.enVueloAudios = nil }
        enVueloAudios = t
        await t.value
    }

    /// `drenar()` y el carril de los audios: lo usan los tests.
    public func drenarTodo() async {
        await drenar()
        await drenarAudios()
    }

    /// «Reintentar» de un audio que sigue en la cola (falló por red): sin esperar el backoff.
    public func reintentarAudiosAhora() {
        temporizadorAudios?.cancel(); temporizadorAudios = nil
        programarAudios(en: .zero)
    }

    private func programarAudios(en demora: Duration) {
        guard reintentoAutomatico, temporizadorAudios == nil else { return }
        temporizadorAudios = Task { [weak self] in
            try? await Task.sleep(for: demora)
            guard !Task.isCancelled else { return }
            await self?.dispararAudios()
        }
    }

    private func dispararAudios() async {
        temporizadorAudios = nil
        await drenarAudios()
    }

    private func pasadaAudios() async {
        let tanda = estado.ops.filter { mandable($0) && Self.esAudio($0) }
        guard !tanda.isEmpty else { return }
        var resueltas = Set<String>()
        var abandonadas: [Operacion] = []
        var motivoDirecto: [String: String] = [:]
        var guardadas: [OpGuardada] = []
        var sinRed: [Operacion] = []
        var espera = false
        for op in tanda {
            // Ya salió una vez: en un reintento, un 403 o 409 de Storage es «quizás ya subió» (punto 15).
            if Self.anotanIntento.contains(op.kind), op.intentada != true, let i = estado.ops.firstIndex(where: { $0.id == op.id }) {
                estado.ops[i].intentada = true
                guardar()
            }
            let resultado: ResultadoOp
            do {
                resultado = try await ejecutor(op)
            } catch is URLError {
                espera = true; sinRed.append(op); audiosSinRed.insert(op.id); continue
            } catch {
                if registrarFallo(op, motivo: "excepción: \(error)", resueltas: &resueltas, abandonadas: &abandonadas) { espera = true }
                continue
            }
            switch resultado {
            case .tokenCaido:
                espera = true
            case .respuesta(.success(let json)) where Self.seGuardo(json):
                resueltas.insert(op.id)
                guardadas.append(OpGuardada(op: op, respuesta: json))
                audiosSinRed.remove(op.id)
                continue
            case .respuesta(.failure(let e)) where e.codigo == Escrituras.codigoAudioPendientes:
                // Espera a que se terminen de mandar otros audios: sin gastar intento, con un tope de 2 h desde la primera vez.
                audiosSinRed.remove(op.id)
                guard let i = estado.ops.firstIndex(where: { $0.id == op.id }) else { continue }
                let desde = estado.ops[i].esperaDesde ?? reloj()
                if estado.ops[i].esperaDesde == nil { estado.ops[i].esperaDesde = desde }
                if reloj() - desde > Self.topeEsperaAudio {
                    abandonadas.append(estado.ops[i])
                    motivoDirecto[op.id] = Escrituras.codigoAudioPendientes
                    resueltas.insert(op.id)
                } else {
                    espera = true
                }
                continue
            case .respuesta(.failure(let e)) where e.clase != .permanente:
                // Red, transitorio o tiempo de espera: sin gastar intento, y los demás audios siguen.
                espera = true; sinRed.append(op); audiosSinRed.insert(op.id)
                continue
            case .respuesta(.failure(let e)) where e.codigo == "KIND_DESCONOCIDO" || e.codigo == Escrituras.codigoAudioId
                || ReglasChatAdjuntos.codigosDirectos.contains(e.codigo ?? ""):
                // Lo que no va a entrar nunca así (y el tope del día de los adjuntos del chat): directo a «no salió».
                abandonadas.append(op)
                motivoDirecto[op.id] = e.codigo
                resueltas.insert(op.id)
                continue
            case .respuesta(let r):
                let motivo: String
                if case .failure(let e) = r { motivo = "\(e.codigo ?? "\(e.status)"): \(e.mensaje)" } else { motivo = "la base devolvió vacío" }
                if registrarFallo(op, motivo: motivo, resueltas: &resueltas, abandonadas: &abandonadas) { espera = true }
                continue
            }
            break   // token caído: los demás audios también fallarían
        }
        estado.ops.removeAll { resueltas.contains($0.id) }
        for id in resueltas { audiosSinRed.remove(id) }
        if !abandonadas.isEmpty {
            let ahora = Date().timeIntervalSince1970 * 1000
            estado.fallidos.append(contentsOf: abandonadas.map { Fallido(op: $0, motivo: motivoDirecto[$0.id] ?? "abandonada tras \($0.tries) intentos", cuando: ahora) })
        }
        guardar()
        if !guardadas.isEmpty { alGuardar?(guardadas) }
        if !abandonadas.isEmpty { alAbandonar?(abandonadas) }
        if !sinRed.isEmpty { alEsperarAudio?(sinRed) }
        // Silenciosas: el carril nunca avisa «guardando» ni «sin conexión»; la fila del audio lo dice.
        if espera {
            rachaAudios += 1
            programarAudios(en: .milliseconds(min(30_000, 2_000 * max(1, rachaAudios))))
        } else {
            rachaAudios = 0
            if estado.ops.contains(where: { Self.esAudio($0) && mandable($0) }) { programarAudios(en: .zero) }
        }
    }

    /// Suma un intento a la op (en la cola real, no en la copia). Devuelve true si sigue pendiente.
    /// Un dato que la base no acepta (SQLSTATE 22 y 23, o un `raise` de la función) no se arregla reintentando media hora:
    /// se deja de intentar a los `maxIntentos` y queda en «No se pudo guardar». Lo vacío, los 5xx y una función que no
    /// existe (una versión a medio publicar) sí esperan la ventana.
    static func esRechazoDeDatos(_ motivo: String) -> Bool {
        let codigo = motivo.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        return codigo == "P0001" || (codigo.count == 5 && (codigo.hasPrefix("22") || codigo.hasPrefix("23")))
    }

    private func registrarFallo(_ op: Operacion, motivo: String, resueltas: inout Set<String>, abandonadas: inout [Operacion]) -> Bool {
        guard let i = estado.ops.firstIndex(where: { $0.id == op.id }) else { return false }
        estado.ops[i].tries += 1
        let ahora = reloj()
        if estado.ops[i].primerRechazo == nil { estado.ops[i].primerRechazo = ahora }
        let ventana = Self.esRechazoDeDatos(motivo) ? 0 : ventanaAbandono
        if estado.ops[i].tries >= maxIntentos, ahora - (estado.ops[i].primerRechazo ?? ahora) >= ventana {
            resueltas.insert(op.id)
            abandonadas.append(estado.ops[i])
            return false
        }
        return true
    }

    private func avisar(_ e: EstadoGuardado) { alCambiar?(e) }

    private func guardar() {
        guard let archivo else { return }
        do {
            try FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            let datos: Data
            if let d = try? JSONEncoder().encode(estado) {
                datos = d
            } else {
                // Un número no finito (NaN, infinito) no tiene JSON y `JSONEncoder` tira: con uno solo, la cola dejaba de
                // guardarse para siempre, en silencio, también desde fallidos (sospecha de la revisión del 15-oct,
                // confirmada). Como JSON.stringify de la web: null. `encolar` ya lo hace; esto ataja cualquier otro camino.
                estado.ops = estado.ops.map(\.sinNoFinitos)
                estado.fallidos = estado.fallidos.map { Fallido(op: $0.op.sinNoFinitos, motivo: $0.motivo, cuando: $0.cuando.isFinite ? $0.cuando : 0) }
                datos = try JSONEncoder().encode(estado)
            }
            try datos.write(to: archivo, options: [.atomic])
        } catch {
            // Sin disco no hay mucho que hacer; la op sigue en memoria y se reintenta.
        }
    }

    /// Kinds que no muestran avisos ("guardando", "sin conexión", "no se guardó"): las sustituciones de ejercicio
    /// (SER-14) ya quedaron en el teléfono y el servidor solo las respalda. Antes no tocaban la red: que sigan sin avisar.
    /// Los ajustes de porciones tampoco: valen en el teléfono aunque no hayan subido (son para que Mati los vea). Ni el avance
    /// de «Tu guía», que sale cada 10 s mientras corre un video: lo visto ya quedó en el teléfono.
    /// Los audios de la guía tampoco: su fila dice «Mandando» o «No se pudo mandar». Ni las fotos y audios del chat: su
    /// burbuja dice «Enviando…» o «No salió».
    public static let silenciosas: Set<String> = [SustitucionesServidor.kindGuardar, SustitucionesServidor.kindBorrar, ModeloApp.kindAjustes,
                                                    ModeloGuia.kindAvance, ModeloAudioDuda.kind, ModeloAgenda.kind,
                                                    ModeloChat.kindAdjunto]

    /// Kinds que se anotan como `intentada` antes de salir: el chat, que antes de reintentar mira si ya había llegado, y el
    /// audio, que solo en un reintento toma un 403 o 409 de Storage como «quizás ya subió».
    public static let anotanIntento: Set<String> = ["chat", ModeloAudioDuda.kind]

    /// `seGuardo` de la web: null, 0 y [] son "no se guardó". `false` SÍ cuenta (desmarcar algo que no estaba).
    public static func seGuardo(_ v: JSONValue) -> Bool {
        switch v {
        case .null: return false
        case .numero(let d): return d != 0
        case .lista(let a): return !a.isEmpty
        default: return true
        }
    }
}
