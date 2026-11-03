import Foundation

/// Lo que hace el alumno en el reloj y el iPhone tiene que pasar a su cola. Lleva el día y la semana: el iPhone no lo
/// aplica sobre otro día (lo acusa como descartado).
public enum EventoReloj: Equatable, Sendable {
    /// «Empezar» en el reloj: arranca la sesión en el teléfono (como «▶ Empezar entrenamiento»).
    case iniciar(diaId: String, semana: Int)
    /// Una serie confirmada con la corona. `indice` es 0-based (la serie 1 es 0). `kg` nil = sin kg (peso corporal).
    case serie(diaId: String, semana: Int, lugar: String, indice: Int, reps: Int, kg: Double?)
    /// «Terminar» en el reloj: cierra la sesión de hoy en el teléfono (como «Cerrar sesión de hoy», sin notas).
    case terminar(diaId: String, semana: Int)

    public var diaId: String {
        switch self {
        case .iniciar(let d, _), .serie(let d, _, _, _, _, _), .terminar(let d, _): d
        }
    }

    public var semana: Int {
        switch self {
        case .iniciar(_, let s), .serie(_, let s, _, _, _, _), .terminar(_, let s): s
        }
    }
}

extension EventoReloj: Codable {
    private enum Claves: String, CodingKey { case tipo, diaId, semana, lugar, indice, reps, kg }
    private enum Tipo: String, Codable { case iniciar, serie, terminar }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        let dia = try c.decode(String.self, forKey: .diaId), semana = try c.decode(Int.self, forKey: .semana)
        switch try c.decode(Tipo.self, forKey: .tipo) {
        case .iniciar: self = .iniciar(diaId: dia, semana: semana)
        case .terminar: self = .terminar(diaId: dia, semana: semana)
        case .serie:
            self = .serie(diaId: dia, semana: semana, lugar: try c.decode(String.self, forKey: .lugar),
                          indice: try c.decode(Int.self, forKey: .indice), reps: try c.decode(Int.self, forKey: .reps),
                          kg: try c.decodeIfPresent(Double.self, forKey: .kg))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Claves.self)
        try c.encode(diaId, forKey: .diaId)
        try c.encode(semana, forKey: .semana)
        switch self {
        case .iniciar: try c.encode(Tipo.iniciar, forKey: .tipo)
        case .terminar: try c.encode(Tipo.terminar, forKey: .tipo)
        case .serie(_, _, let lugar, let indice, let reps, let kg):
            try c.encode(Tipo.serie, forKey: .tipo)
            try c.encode(lugar, forKey: .lugar)
            try c.encode(indice, forKey: .indice)
            try c.encode(reps, forKey: .reps)
            try c.encodeIfPresent(kg, forKey: .kg)
        }
    }
}

/// Un evento en la cola del reloj: con su id (para no aplicarlo dos veces) y cuándo pasó (ms).
public struct EventoEnCola: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var creado: Double
    public var evento: EventoReloj
    public init(_ evento: EventoReloj, id: UUID = UUID(), creado: Double) { self.id = id; self.creado = creado; self.evento = evento }
}

/// La cola propia del reloj: lo que se hizo sin el teléfono (o antes de que el teléfono acuse) queda acá, en disco, en
/// orden, hasta que el iPhone lo acusa. Se reenvía entero al volver la conexión y, mientras no haya acuse, cada
/// `reintento` ms; el iPhone descarta los repetidos por id, así reenviar de más nunca duplica.
///
/// Una serie corregida antes de llegar al teléfono (misma serie, otro valor) reemplaza a la vieja en su lugar: el
/// teléfono recibe una sola, la última.
public struct ColaReloj: Codable, Equatable, Sendable {
    public static let reintento: Double = 20_000
    /// Tope de seguridad: con más, se tiran los más viejos que no sean series (las series no se pierden nunca).
    public static let tope = 1_000

    public private(set) var pendientes: [EventoEnCola] = []
    /// ms del último envío de cada id (no se guarda: al reabrir la app se reenvía todo).
    private var enviados: [UUID: Double] = [:]

    public init(pendientes: [EventoEnCola] = []) { self.pendientes = pendientes }

    private enum CodingKeys: String, CodingKey { case pendientes }

    public var vacia: Bool { pendientes.isEmpty }

    /// Agrega un evento al final. Una serie que ya estaba sin acusar (mismo día, semana, lugar e índice) se reemplaza
    /// en su lugar con un id nuevo.
    public mutating func encolar(_ e: EventoEnCola) {
        if case .serie(let d, let s, let l, let i, _, _) = e.evento,
           let k = pendientes.firstIndex(where: {
               if case .serie(d, s, l, i, _, _) = $0.evento { return true }
               return false
           }) {
            enviados[pendientes[k].id] = nil
            pendientes[k] = e
            return
        }
        // Dos «iniciar» o dos «terminar» seguidos del mismo día son uno solo.
        if let ultimo = pendientes.last, ultimo.evento == e.evento, !esSerie(e.evento) { return }
        pendientes.append(e)
        podar()
    }

    /// Lo que hay que mandar ahora: todo si `forzar` (volvió la conexión, se abrió la app), si no lo que nunca se mandó o
    /// se mandó hace más de `reintento`. Los marca como enviados en `ahora`.
    public mutating func paraEnviar(ahora: Double, forzar: Bool = false) -> [EventoEnCola] {
        let lote = pendientes.filter { forzar || (enviados[$0.id].map { ahora - $0 >= Self.reintento } ?? true) }
        for e in lote { enviados[e.id] = ahora }
        return lote
    }

    /// El envío falló (sin conexión): se vuelven a mandar en la próxima.
    public mutating func fallo(_ ids: [UUID]) { for id in ids { enviados[id] = nil } }

    /// El iPhone acusó: salen de la cola (aplicados, repetidos o descartados). Devuelve los que salieron.
    @discardableResult
    public mutating func acusar(_ acuses: [AcuseEvento]) -> [EventoEnCola] {
        let ids = Set(acuses.map(\.id))
        let salen = pendientes.filter { ids.contains($0.id) }
        pendientes.removeAll { ids.contains($0.id) }
        for id in ids { enviados[id] = nil }
        return salen
    }

    private func esSerie(_ e: EventoReloj) -> Bool { if case .serie = e { return true } else { return false } }

    private mutating func podar() {
        while pendientes.count > Self.tope, let k = pendientes.firstIndex(where: { !esSerie($0.evento) }) {
            enviados[pendientes[k].id] = nil
            pendientes.remove(at: k)
        }
    }

    // MARK: - Disco

    /// Lee la cola guardada (vacía si no hay o no se entiende: un archivo roto no puede trabar el reloj).
    public static func leer(_ url: URL) -> ColaReloj {
        guard let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(ColaReloj.self, from: d) else { return ColaReloj() }
        return c
    }

    /// Guarda la cola de forma atómica.
    public func guardar(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// Del lado del iPhone: los ids de eventos del reloj que ya se aplicaron, para que un reenvío no duplique. Guarda los
/// últimos `tope` (el reloj nunca reenvía algo más viejo que su cola, y su cola no pasa de `ColaReloj.tope`).
public struct AplicadosReloj: Codable, Equatable, Sendable {
    public static let tope = 2_000
    public private(set) var ids: [UUID] = []
    private var conjunto: Set<UUID> = []

    public init(ids: [UUID] = []) {
        self.ids = Array(ids.suffix(Self.tope))
        conjunto = Set(self.ids)
    }

    private enum CodingKeys: String, CodingKey { case ids }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(ids: try c.decode([UUID].self, forKey: .ids))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ids, forKey: .ids)
    }

    public func contiene(_ id: UUID) -> Bool { conjunto.contains(id) }

    /// Anota un id. false si ya estaba (un repetido).
    @discardableResult
    public mutating func anotar(_ id: UUID) -> Bool {
        guard !conjunto.contains(id) else { return false }
        ids.append(id)
        conjunto.insert(id)
        if ids.count > Self.tope {
            let sobran = ids.count - Self.tope
            for viejo in ids.prefix(sobran) { conjunto.remove(viejo) }
            ids.removeFirst(sobran)
        }
        return true
    }
}
