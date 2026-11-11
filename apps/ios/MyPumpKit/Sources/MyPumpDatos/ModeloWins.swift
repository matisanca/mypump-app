import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// «Récords y logros» (2.3.0, palanca `wins_app`): el permiso del alumno para que Mati se entere de sus logros y la cola
/// local de los que faltan dejar en el servidor. Contrato: `supabase/propuestas/nativa_wins_lista_previa.sql`.
///
/// - Con la palanca apagada `ModeloApp` no llama a nada de esto: queda lo último que se supo del permiso (para que el
///   interruptor de Mis datos se siga viendo y se pueda apagar) y nada más.
/// - Un logro solo se encola con la palanca prendida y el último permiso conocido en true.
/// - La app nunca publica ni manda mensajes: deja filas `pendiente` con `mypump_wins_registrar`. No usa el Outbox general.
@MainActor @Observable
public final class ModeloWins {
    /// Un logro en la cola local.
    public struct Logro: Codable, Equatable, Sendable, Identifiable {
        /// UUID propio: un reintento no duplica.
        public let id: String
        public let tipo: ReglasWins.Tipo
        public let clave: String
        /// Fecha local YYYY-MM-DD.
        public let dia: String
        public let datos: JSONValue
    }

    /// Lo que queda en el teléfono, por cuenta.
    struct Guardado: Codable {
        var permiso: Bool
        var cola: [Logro]
        /// Lo último que dijo `mypump_wins_estado` (opcional: los archivos de antes no lo traen).
        var activa: Bool?
        /// Cuántas veces el servidor contestó algo que no se entiende, por id (opcional: los archivos de antes no lo traen).
        var intentos: [String: Int]?
    }

    /// El servidor dijo que la función está prendida (`activa` de `mypump_wins_estado`). Se recuerda: sin red en el
    /// gimnasio vale lo último que se supo. Sin haberlo sabido nunca, apagada.
    public private(set) var activa = false
    /// El último permiso conocido (se recuerda en disco para decidir sin red).
    public private(set) var permiso = false
    public private(set) var cola: [Logro] = []

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    /// La palanca `wins_app`, como la leyó `ModeloApp`. Arranca con lo recordado en el teléfono: cerrar la sesión con mala
    /// señal, antes de que termine la carga, festeja igual.
    private var palanca: Bool
    @ObservationIgnored private var vaciando = false
    /// Respuestas que no se entendieron, por logro: al tercer intento se saca.
    @ObservationIgnored private var intentos: [String: Int] = [:]
    /// Lo que ya salió en esta sesión de la app: lo mismo no se vuelve a encolar.
    @ObservationIgnored private var enviados: [Logro] = []

    static let archivo = "wins.json"
    public static let topeCola = 50
    public static let plataforma = "ios"
    /// Intentos fallidos (respuesta rara, token) antes de sacar un logro de la cola.
    public static let intentosMaximos = 3

    public init(cliente: ClienteRPC, token: String, disco: Disco?, palanca: Bool = false) {
        self.cliente = cliente; self.token = token; self.disco = disco; self.palanca = palanca
        if let g = disco?.leer(Guardado.self, Self.archivo) {
            permiso = g.permiso
            cola = g.cola
            activa = g.activa ?? false
            intentos = g.intentos ?? [:]
        }
    }

    /// Lo que decide la pantalla (el festejo y el interruptor): la palanca y que el servidor haya dicho que está activa. Con
    /// la función inexistente (PGRST202) o sin haber podido preguntar nunca, no se muestra nada.
    public var prendida: Bool { palanca && activa }
    /// El interruptor de Mis datos: prendida, o apagada si el permiso quedó dado (para poder sacarlo).
    public var visibleEnMisDatos: Bool { prendida || permiso }

    // MARK: - Estado

    /// Al abrir y al volver al frente, con la palanca prendida.
    public func refrescar() async {
        palanca = true
        switch await cliente.llamar("mypump_wins_estado", ["p_token": .texto(token)]) {
        case .success(let j):
            guard j["ok"] == .bool(true) else { return }   // token caído: no se toca nada
            activa = j["activa"] == .bool(true)
            fijarPermiso(j["permiso"] == .bool(true))
        case .failure(let e) where e.funcionInexistente:
            // El servidor todavía no tiene la función: nada que mostrar ni que mandar.
            activa = false
            fijarPermiso(false)
        case .failure:
            break   // sin red: vale lo último que se supo
        }
    }

    /// La palanca se apagó: no se llama a nada. El permiso recordado queda (el interruptor sigue para poder apagarlo).
    public func apagar() {
        palanca = false
    }

    private func fijarPermiso(_ nuevo: Bool) {
        if !nuevo { cola = [] }
        permiso = nuevo
        guardar()
    }

    private func guardar() {
        intentos = intentos.filter { id, _ in cola.contains { $0.id == id } }
        disco?.guardar(Guardado(permiso: permiso, cola: cola, activa: activa, intentos: intentos.isEmpty ? nil : intentos), Self.archivo)
    }

    // MARK: - Permiso

    /// «Sí, compartir». true si el servidor lo dejó dado; ahí los récords del festejo entran a la cola. Sin red o con un
    /// error no queda dado.
    public func darPermiso(records: [ReglasWins.Record] = [], dia: String = FechaLocal.hoy()) async -> Bool {
        guard prendida else { return false }
        let r = await cliente.llamar("mypump_wins_permiso", [
            "p_token": .texto(token), "p_otorga": .bool(true), "p_version": .numero(Double(ReglasWins.permisoVersion)),
            "p_plataforma": .texto(Self.plataforma),
        ])
        guard case .success(let j) = r, j["ok"] == .bool(true), j["permiso"] == .bool(true) else { return false }
        permiso = true
        guardar()
        encolar(records, dia: dia)
        return true
    }

    /// Apagar el interruptor. true si el servidor lo sacó: la cola local se vacía. Anda también con la palanca apagada.
    public func revocar() async -> Bool {
        let r = await cliente.llamar("mypump_wins_permiso", ["p_token": .texto(token), "p_otorga": .bool(false)])
        guard case .success(let j) = r, j["ok"] == .bool(true) else { return false }
        fijarPermiso(false)
        return true
    }

    // MARK: - Cola

    /// Los récords de un festejo. No encola nada sin la palanca o sin el permiso. Devuelve si quedaron en la cola.
    @discardableResult
    public func encolar(_ records: [ReglasWins.Record], dia: String = FechaLocal.hoy()) -> Bool {
        guard prendida, permiso, !records.isEmpty else { return false }
        for r in records { agregar(tipo: r.tipo, clave: r.clave, dia: dia, datos: r.datos) }
        guardar()
        Task { await vaciar() }
        return true
    }

    /// La racha de pasos, si es un hito y hay permiso. Devuelve si quedó en la cola (la celebración suma su línea).
    @discardableResult
    public func encolarRacha(dias: Int, meta: Int, dia: String = FechaLocal.hoy()) -> Bool {
        guard prendida, permiso, ReglasWins.esHito(dias) else { return false }
        agregar(tipo: .rachaPasos, clave: "pasos", dia: dia, datos: ReglasWins.datosRacha(dias: dias, meta: meta))
        guardar()
        Task { await vaciar() }
        return true
    }

    /// Uno por tipo, clave y día (como el servidor). El mismo logro con los mismos datos, en la cola o ya enviado en esta
    /// sesión, no se encola otra vez (reabrir el festejo o girar la pantalla no genera ids nuevos). Con datos distintos
    /// (mejoró la marca) reemplaza al que todavía no salió, con id nuevo.
    private func agregar(tipo: ReglasWins.Tipo, clave: String, dia: String, datos: JSONValue) {
        func igual(_ l: Logro) -> Bool { l.tipo == tipo && l.clave == clave && l.dia == dia && l.datos == datos }
        guard !cola.contains(where: igual), !enviados.contains(where: igual) else { return }
        cola.removeAll { $0.tipo == tipo && $0.clave == clave && $0.dia == dia }
        cola.append(Logro(id: UUID().uuidString.lowercased(), tipo: tipo, clave: clave, dia: dia, datos: datos))
        // Tope: lo más viejo se descarta.
        if cola.count > Self.topeCola { cola.removeFirst(cola.count - Self.topeCola) }
    }

    /// Manda lo que haya: al encolar, al abrir la app y al volver al frente. Lo que el servidor contesta (guardado o no) sale
    /// de la cola; un corte o un 5xx lo deja para después.
    public func vaciar() async {
        guard prendida, !vaciando else { return }
        vaciando = true
        defer { vaciando = false }
        while let l = cola.first {
            let r = await cliente.llamar("mypump_wins_registrar", [
                "p_token": .texto(token), "p_id": .texto(l.id), "p_tipo": .texto(l.tipo.rawValue), "p_clave": .texto(l.clave),
                "p_dia": .texto(l.dia), "p_datos": l.datos,
            ])
            switch r {
            case .success(let j):
                if j["motivo"]?.comoTexto == "sin_permiso" { fijarPermiso(false); return }
                if j["ok"] == .bool(true) {
                    enviados.append(l)
                    if enviados.count > Self.topeCola { enviados.removeFirst(enviados.count - Self.topeCola) }
                    quitar(l)
                } else if j["motivo"]?.comoTexto == "datos" {
                    quitar(l)
                } else if !contarIntento(l) {
                    return   // token caído u otra respuesta: se reintenta en la próxima (hasta tres veces)
                }
            case .failure(let e) where e.funcionInexistente:
                // El servidor no tiene la función: nada que mandar ni que mostrar.
                activa = false
                fijarPermiso(false)
                return
            case .failure(let e) where e.clase == .permanente:
                if !contarIntento(l) { return }   // una respuesta que no se entiende: como la de arriba
            case .failure:
                return   // red caída o 5xx: queda, sin contar intentos
            }
        }
    }

    /// Un intento fallido más de este logro. true si ya fueron tres y se sacó (se sigue con el próximo).
    private func contarIntento(_ l: Logro) -> Bool {
        let n = (intentos[l.id] ?? 0) + 1
        if n >= Self.intentosMaximos { quitar(l); return true }
        intentos[l.id] = n
        guardar()
        return false
    }

    private func quitar(_ l: Logro) {
        cola.removeAll { $0.id == l.id }
        guardar()
    }
}
