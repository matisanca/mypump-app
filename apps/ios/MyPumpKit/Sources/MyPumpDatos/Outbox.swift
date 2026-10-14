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

    public init(id: String, kind: String, payload: JSONValue, dedupeKey: String?, tries: Int = 0, ts: Double) {
        self.id = id; self.kind = kind; self.payload = payload; self.dedupeKey = dedupeKey; self.tries = tries; self.ts = ts
    }

    enum CodingKeys: String, CodingKey { case id = "_id", kind, payload, dedupeKey, tries, ts }
}

/// El aviso de guardado que ve el cliente (el toast de la web, `showSaveState`).
public enum EstadoGuardado: Sendable, Equatable {
    case quieto
    case guardando          // solo si el envío tarda más de 900 ms
    case guardado           // solo después de un problema: reasegura
    case sinConexion        // "se reintenta solo"
    case perdido            // algo se abandonó: "revisá y cargalo de nuevo" (9 s)
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
    private var rachaSinRed = 0
    private var secuencia = 0
    private var alCambiar: (@Sendable (EstadoGuardado) -> Void)?
    private var alAbandonar: (@Sendable ([Operacion]) -> Void)?
    /// En los tests se apaga el reintento automático para forzar las pasadas a mano, como `await Outbox.flush()`.
    private let reintentoAutomatico: Bool

    public init(archivo: URL?, maxIntentos: Int = 8, reintentoAutomatico: Bool = true, ejecutor: @escaping Ejecutor) {
        self.archivo = archivo
        self.maxIntentos = maxIntentos
        self.ejecutor = ejecutor
        self.reintentoAutomatico = reintentoAutomatico
        if let archivo, let d = try? Data(contentsOf: archivo), let p = try? JSONDecoder().decode(Persistido.self, from: d) {
            estado = p
        }
    }

    public func observar(estado: @escaping @Sendable (EstadoGuardado) -> Void, abandonadas: @escaping @Sendable ([Operacion]) -> Void) {
        alCambiar = estado
        alAbandonar = abandonadas
    }

    public func cambiarEjecutor(_ e: @escaping Ejecutor) { ejecutor = e }

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
        let op = Operacion(id: "\(Int64(ahora))_\(secuencia)", kind: kind, payload: payload, dedupeKey: dedupeKey, ts: ahora)
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

    /// Una pasada. Si ya hay una en curso, espera a ESA.
    public func drenar() async {
        if let t = enVuelo { await t.value; return }
        let t = Task { await self.pasada() }
        enVuelo = t
        await t.value
        enVuelo = nil
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
        guard !estado.ops.isEmpty else { return }
        let tanda = estado.ops
        var resueltas = Set<String>()
        var abandonadas: [Operacion] = []
        var algunaFallo = false
        // "Guardando…" solo si tarda. Ojo: `try? await Task.sleep` se traga la cancelación y sigue de largo; sin el
        // chequeo, el aviso salía DESPUÉS de terminar y pisaba al de "perdido" (lo encontró el test).
        let lenta = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await self?.avisar(.guardando)
        }

        for op in tanda {
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

        if !abandonadas.isEmpty {
            alAbandonar?(abandonadas)
            huboProblema = false
            avisar(.perdido)
        }
        if algunaFallo {
            huboProblema = true
            if abandonadas.isEmpty { avisar(.sinConexion) }
            let base = max(1, estado.ops.first?.tries ?? 1, rachaSinRed)
            programar(en: .milliseconds(min(30_000, 2_000 * base)))
        } else if huboProblema {
            huboProblema = false
            avisar(.guardado)
        } else if abandonadas.isEmpty {
            avisar(.quieto)
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
            try JSONEncoder().encode(estado).write(to: archivo, options: [.atomic])
        } catch {
            // Sin disco no hay mucho que hacer; la op sigue en memoria y se reintenta.
        }
    }

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
