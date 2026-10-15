import Foundation
import MyPumpModelos

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

    public init(id: String, kind: String, payload: JSONValue, dedupeKey: String?, tries: Int = 0, ts: Double, legado: Bool? = nil,
                intentada: Bool? = nil) {
        self.id = id; self.kind = kind; self.payload = payload; self.dedupeKey = dedupeKey; self.tries = tries; self.ts = ts
        self.legado = legado; self.intentada = intentada
    }

    enum CodingKeys: String, CodingKey { case id = "_id", kind, payload, dedupeKey, tries, ts, legado, intentada }
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
    }

    public let maxIntentos: Int
    private let archivo: URL?
    private var ejecutor: Ejecutor
    private var estado = Persistido()
    private var enVuelo: Task<Void, Never>?
    private var temporizador: Task<Void, Never>?
    private var huboProblema = false
    /// La última pasada dejó algo sin guardar (sin red, transitorio, rechazo o token caído).
    private var ultimaFallo = false
    private var rachaSinRed = 0
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
    public init(archivo: URL?, maxIntentos: Int = 8, reintentoAutomatico: Bool = true, retenerLegadas: Bool = false,
                retenerSwaps: Bool = false, ejecutor: @escaping Ejecutor) {
        self.archivo = archivo
        self.maxIntentos = maxIntentos
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
        programar(en: .zero)
        return op
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

    /// Vacía la cola: pasadas hasta que no quede nada o hasta que una falle (sin red, el servidor mal, un rechazo).
    /// Si ya hay una pasada en curso, la espera y sigue con lo que se encoló mientras tanto: así "cerrar el día" espera
    /// el envío de TODO lo anterior.
    public func drenar() async {
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
            if !estado.ops.contains(where: mandable) || ultimaFallo { return }
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
        let tanda = estado.ops.filter(mandable)
        guard !tanda.isEmpty else { return }
        let hayVisibles = tanda.contains { !Self.silenciosas.contains($0.kind) }
        var resueltas = Set<String>()
        var abandonadas: [Operacion] = []
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
                _ = e; algunaFallo = true; rachaSinRed += 1; break           // un throw de red: no gasta intento
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
            case .respuesta(.failure(let e)) where e.codigo == "KIND_DESCONOCIDO":
                abandonadas.append(op)
                resueltas.insert(op.id)
                continue
            case .respuesta(let r):
                let motivo: String
                if case .failure(let e) = r { motivo = "\(e.codigo ?? "\(e.status)"): \(e.mensaje)" } else { motivo = "la base devolvió vacío" }
                if registrarFallo(op, motivo: motivo, resueltas: &resueltas, abandonadas: &abandonadas) { algunaFallo = true }
                continue
            }
            break   // red, transitorio o token caído: no tiene sentido seguir con las demás
        }
        lenta.cancel()

        if !resueltas.isEmpty {
            estado.ops.removeAll { resueltas.contains($0.id) }
            rachaSinRed = 0
        }
        if !abandonadas.isEmpty {
            let ahora = Date().timeIntervalSince1970 * 1000
            estado.fallidos.append(contentsOf: abandonadas.map { Fallido(op: $0, motivo: "abandonada tras \($0.tries) intentos", cuando: ahora) })
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
            let base = max(1, estado.ops.first?.tries ?? 1, rachaSinRed)
            programar(en: .milliseconds(min(30_000, 2_000 * base)))
        }
        // Lo encolado DURANTE esta pasada quedó sin procesar: otra vuelta.
        if !estado.ops.isEmpty && !algunaFallo { programar(en: .zero) }
    }

    /// Suma un intento a la op (en la cola real, no en la copia). Devuelve true si sigue pendiente.
    private func registrarFallo(_ op: Operacion, motivo: String, resueltas: inout Set<String>, abandonadas: inout [Operacion]) -> Bool {
        guard let i = estado.ops.firstIndex(where: { $0.id == op.id }) else { return false }
        estado.ops[i].tries += 1
        if estado.ops[i].tries >= maxIntentos {
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
    public static let silenciosas: Set<String> = [SustitucionesServidor.kindGuardar, SustitucionesServidor.kindBorrar]

    /// Kinds que se anotan como `intentada` antes de salir: el chat, que antes de reintentar mira si ya había llegado.
    public static let anotanIntento: Set<String> = ["chat"]

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
