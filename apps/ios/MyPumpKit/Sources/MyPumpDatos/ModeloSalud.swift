import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Salud, recuperación y "Mi reloj" del cliente: lo que la web hace con `loadSalud`, `loadRecuperacion`,
/// `loadConexiones` y `window.MyPumpHealth`. Las cards leen de acá (SAL-09 a SAL-13, REV-08).
///
/// - Apple Health: `conectar()` (onboarding y botones), `sincronizar()` (botón "Sincronizar"), `alAbrir()` y
///   `alVolver()` (sincronizan 7 días y retoman el historial si está conectado; la vuelta a primer plano se escucha
///   sola con la notificación del sistema).
/// - Lecturas: `cargar()` trae 60 días de salud, 14 de recuperación y si el cliente quiere ver el score.
/// - Mi reloj: `cargarRelojes()`, `urlConectar(_:)` (se abre en SFSafariViewController), `esperarConexion(_:)` (cada 3 s
///   durante 2 min) y `quitar(_:)`.
///
/// Sin fuente (la demo, una Mac, o un iPhone sin HealthKit) nada de Apple Health hace nada y `disponible` es false.
@MainActor @Observable
public final class ModeloSalud {

    // MARK: Lo que muestran las cards

    /// `get_salud` de hoy − 59 a hoy (todas las fuentes; la vista elige la mejor por día).
    public private(set) var salud: [FilaSalud] = []
    /// `get_recuperacion(14)`: la última es la más nueva.
    public private(set) var recuperacion: [RecuperacionDia] = []
    /// `get_mostrar_recuperacion` (null o un error cuentan como true: el default es que el score exista).
    public private(set) var mostrarRecuperacion = true
    /// `get_conexiones`.
    public private(set) var conexiones: [Conexion] = []
    /// Los relojes que el servidor tiene habilitados (nil = todavía no se preguntó).
    public private(set) var relojesDisponibles: [String]?
    public private(set) var cargado = false
    public private(set) var fecha = FechaLocal.hoy()

    // MARK: Apple Health

    public private(set) var disponible = false
    public private(set) var conectado = false
    public private(set) var sinDatos = false
    public private(set) var ultimaSync: Date?
    /// "Trayendo tu historial… 40/60 días".
    public private(set) var progresoHistorial: ProgresoHistorial?
    public private(set) var sincronizando = false
    public private(set) var conectando = false
    /// El proveedor que se está esperando después de "Conectar" (Oura/WHOOP).
    public private(set) var esperandoReloj: String?

    public struct ProgresoHistorial: Equatable, Sendable { public let hecho: Int; public let total: Int }

    @ObservationIgnored public let sincronizador: SincronizadorSalud?
    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored private var observador: (any NSObjectProtocol)?
    @ObservationIgnored private var sondeo: Task<Bool, Never>?

    /// La fuente del sistema. En el iPhone la pone la app (FuenteHealthKit); si nadie la puso, se busca por nombre una
    /// clase `FuenteHealthKit` de Objective-C que cumpla `FuenteSalud` (así el kit no importa HealthKit).
    public static var fuenteDelSistema: (any FuenteSalud)? {
        get { if let f = _fuente { return f }; return Self.descubrir() }
        set { _fuente = newValue }
    }
    private static var _fuente: (any FuenteSalud)?
    private static func descubrir() -> (any FuenteSalud)? {
        guard let clase = NSClassFromString("FuenteHealthKit") as? NSObject.Type, let f = clase.init() as? any FuenteSalud else { return nil }
        _fuente = f
        return f
    }

    public init(cliente: ClienteRPC, token: String, fuente: (any FuenteSalud)? = ModeloSalud.fuenteDelSistema,
                almacen: any AlmacenSalud = AlmacenSaludDefaults(), ahora: @escaping @Sendable () -> Date = { Date() },
                zona: TimeZone = .current) {
        self.cliente = cliente
        self.token = token
        sincronizador = fuente.map { SincronizadorSalud(fuente: $0, cliente: cliente, token: token, almacen: almacen, ahora: ahora, zona: zona) }
        sincronizador?.alCambiar = { [weak self] in Task { await self?.cargar() } }
        sincronizador?.alProgresar = { [weak self] h, t in self?.progresoHistorial = ProgresoHistorial(hecho: h, total: t) }
        leerEstado()
    }

    // MARK: - Ciclo de vida

    /// Al arrancar la app con la cuenta: las lecturas y, si Salud está conectada, los 7 días y el historial pendiente.
    public func alAbrir() async {
        escucharPrimerPlano()
        if let s = sincronizador {
            disponible = await s.fuente.disponible()
            if s.conectado { s.retomarHistorialSiFalta(); vigilarHistorial() }
        }
        async let lecturas: Void = cargar()
        async let relojes: Void = cargarRelojes()
        if sincronizador?.conectado == true { await sincronizar() }
        _ = await (lecturas, relojes)
    }

    /// Al volver a primer plano (`visibilitychange`): si está conectada, 7 días y retomar el historial.
    public func alVolver() async {
        fecha = FechaLocal.hoy()
        guard let s = sincronizador, s.conectado else { return }
        s.retomarHistorialSiFalta()
        vigilarHistorial()
        await sincronizar()
    }

    /// La vuelta a primer plano se escucha con la notificación del sistema (sin importar UIKit en el kit).
    private func escucharPrimerPlano() {
        guard observador == nil else { return }
        observador = NotificationCenter.default.addObserver(forName: Notification.Name("UIApplicationWillEnterForegroundNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.alVolver() }
        }
    }

    // MARK: - Apple Health

    /// "Conectar Apple Health": permisos en dos tandas, 7 días y el historial de fondo. El aviso de "no llegó nada"
    /// espera al historial (con 7 días vacíos no se puede acusar a nadie de haber denegado).
    @discardableResult
    public func conectar() async -> ResultadoConexion {
        guard let s = sincronizador else {
            return ResultadoConexion(ok: false, motivo: "no_disponible", detalle: nil, preguntados: nil, total: 0, sinDatos: false,
                                     rechazados: [], historial: nil)
        }
        conectando = true
        defer { conectando = false }
        let r = await s.conectar()
        leerEstado()
        if r.ok {
            vigilarHistorial()
            await cargar()
        }
        return r
    }

    /// "Sincronizar" (y al abrir y al volver): los últimos 7 días.
    @discardableResult
    public func sincronizar() async -> ResultadoSync {
        guard let s = sincronizador else { return ResultadoSync(ok: false, motivo: "no_disponible", ingresados: 0, entrenos: 0, errorIngesta: nil) }
        sincronizando = true
        defer { sincronizando = false }
        let r = await s.sincronizar()
        leerEstado()
        return r
    }

    /// Solo local: deja de sincronizar, lo subido queda.
    public func desconectar() {
        sincronizador?.desconectar()
        leerEstado()
    }

    public func estado() async -> EstadoSalud? { await sincronizador?.estado() }
    public func diagnostico() async -> DiagnosticoSalud? { await sincronizador?.diagnostico() }
    public var ultimoIntento: JSONValue? { sincronizador?.ultimoIntento }
    public var ultimoErrorIngesta: String? { sincronizador?.ultimoErrorIngesta }

    /// El texto de "Sincronizar" en Mis datos.
    public static func textoSincronizacion(_ r: ResultadoSync) -> String {
        if let e = r.errorIngesta { return "No se pudieron guardar los datos (\(e)). Probá de nuevo en un rato." }
        return r.ingresados > 0 ? "Listo: \(r.ingresados) datos nuevos." : "Ya estabas al día."
    }

    private func leerEstado() {
        conectado = sincronizador?.conectado ?? false
        sinDatos = sincronizador?.sinDatos ?? false
        ultimaSync = sincronizador?.ultimaSync.flatMap(RelojLocal.desdeISO).map(RelojLocal.fecha)
        progresoHistorial = sincronizador?.progresoHistorial.map { ProgresoHistorial(hecho: $0.hecho, total: $0.total) }
    }

    /// Sigue al historial de fondo para apagar el contador cuando termina.
    private func vigilarHistorial() {
        leerEstado()
        guard let t = sincronizador?.historialEnCurso else { return }
        Task { [weak self] in
            _ = await t.value
            self?.leerEstado()
        }
    }

    // MARK: - Lecturas

    /// `loadSalud` + `loadRecuperacion`.
    public func cargar() async {
        fecha = FechaLocal.hoy()
        let t: JSONValue = .texto(token)
        let desde = DiaCalendario.numero(fecha).map { DiaCalendario.texto($0 - 59) } ?? fecha
        async let s = cliente.filas("mypump_get_salud", ["p_token": t, "p_desde": .texto(desde), "p_hasta": .texto(fecha)], como: FilaSalud.self)
        async let r = cliente.filas("mypump_get_recuperacion", ["p_token": t, "p_dias": .numero(14)], como: RecuperacionDia.self)
        async let m = cliente.llamar("mypump_get_mostrar_recuperacion", ["p_token": t])
        let (rs, rr, rm) = await (s, r, m)
        salud = (try? rs.get()) ?? []
        recuperacion = (try? rr.get()) ?? []
        if case .success(.bool(false)) = rm { mostrarRecuperacion = false } else { mostrarRecuperacion = true }
        cargado = true
        leerEstado()
    }

    /// "Mostrarme el score": optimista (la UI responde ya).
    public func cambiarMostrarRecuperacion(_ mostrar: Bool) async {
        mostrarRecuperacion = mostrar
        _ = await cliente.llamar("mypump_set_mostrar_recuperacion", ["p_token": .texto(token), "p_mostrar": .bool(mostrar)])
    }

    // MARK: - Lo que derivan las cards

    public var cardRecuperacion: SaludVista.CardRecuperacion {
        SaludVista.cardRecuperacion(serie: recuperacion, conectado: conectado, mostrar: mostrarRecuperacion, salud: salud,
                                    historial: progresoHistorial.map { ($0.hecho, $0.total) }, sinDatos: sinDatos, hoy: fecha)
    }

    public var resumenSalud: SaludVista.ResumenSalud? { SaludVista.resumen(salud, hoy: fecha) }
    public func valor(_ tipo: String, fecha: String) -> Double? { SaludVista.valor(salud, tipo: tipo, fecha: fecha) }
    public func serie(_ tipo: String) -> [PuntoSalud] { SaludVista.serie(salud, tipo: tipo) }
    /// Para "Cómo se arma tu recuperación" (la última fila, como la escena de la web).
    public var componentes: [SaludVista.Componente] { SaludVista.componentes(recuperacion.last) }
    public var scoreDeHoy: Int? { recuperacion.last?.score }

    // MARK: - Mi reloj (Oura, WHOOP)

    public struct Reloj: Identifiable, Equatable, Sendable {
        public let id: String
        public let nombre: String
        public let descripcion: String
        public let conectado: Bool
        public let enError: Bool
        public let ultimaSincronizacion: String?
    }

    /// `PROVEEDORES_UI`.
    public static let relojes: [(id: String, nombre: String, descripcion: String)] = [
        ("oura", "Oura", "Anillo · trae sueño, pulso y variabilidad reales"),
        ("whoop", "WHOOP", "Banda · trae sueño, pulso y variabilidad reales"),
    ]

    /// `loadConexiones`: qué ofrece el servidor (una vez) y qué tiene conectado el cliente.
    public func cargarRelojes() async {
        if relojesDisponibles == nil { relojesDisponibles = await cliente.relojesDisponibles() ?? [] }
        if case .success(let filas) = await cliente.filas("mypump_get_conexiones", ["p_token": .texto(token)], como: Conexion.self) {
            conexiones = filas
        }
    }

    /// Se muestra un reloj si el servidor lo habilita O si el cliente ya lo tenía (para que pueda verlo y quitarlo).
    public var relojesVisibles: [Reloj] {
        let disponibles = relojesDisponibles ?? []
        return Self.relojes.compactMap { p in
            let c = conexiones.first { $0.proveedor == p.id }
            guard disponibles.contains(p.id) || c != nil else { return nil }
            let conectada = c?.estado == "conectada"
            return Reloj(id: p.id, nombre: p.nombre, descripcion: p.descripcion, conectado: conectada, enError: c?.estado == "error",
                         ultimaSincronizacion: conectada ? c?.ultimoPullEn.map(Self.fechaCorta) : nil)
        }
    }

    /// "Si usás Oura o WHOOP, conectalo y…".
    public var textoRelojes: String {
        let nombres = relojesVisibles.map(\.nombre).joined(separator: " o ")
        return "Si usás \(nombres), conectalo y tus datos de sueño y recuperación entran solos. Apple Watch no se conecta acá: va por Salud de Apple desde la app de iPhone."
    }

    public func urlConectar(_ proveedor: String) -> URL? { cliente.urlConectarReloj(token: token, proveedor: proveedor) }

    /// Después de abrir la autorización: `get_conexiones` cada 3 s, 40 veces (2 min). El callback no vuelve a la app,
    /// así que la app pregunta. true si quedó conectado (y ya se recargó lo demás).
    @discardableResult
    public func esperarConexion(_ proveedor: String, cada: Duration = .seconds(3), intentos: Int = 40) async -> Bool {
        sondeo?.cancel()
        esperandoReloj = proveedor
        let tarea = Task { [weak self, cliente, token] () -> Bool in
            for _ in 0..<intentos {
                try? await Task.sleep(for: cada)
                if Task.isCancelled { return false }
                if case .success(let cs) = await cliente.filas("mypump_get_conexiones", ["p_token": .texto(token)], como: Conexion.self),
                   cs.contains(where: { $0.proveedor == proveedor && $0.estado == "conectada" }) {
                    self?.conexiones = cs
                    return true
                }
            }
            return false
        }
        sondeo = tarea
        let ok = await tarea.value
        if sondeo == tarea { esperandoReloj = nil; sondeo = nil }
        if ok { await cargar() }
        return ok
    }

    /// Si el cliente cierra la hoja sin terminar, se deja de preguntar.
    public func cancelarEspera() {
        sondeo?.cancel()
        sondeo = nil
        esperandoReloj = nil
    }

    /// "Quitar" (con confirmación en la vista): dejamos de traer sus datos; los que ya están se quedan.
    public func quitar(_ proveedor: String) async {
        _ = await cliente.llamar("mypump_desconectar_wearable", ["p_token": .texto(token), "p_proveedor": .texto(proveedor)])
        await cargarRelojes()
    }

    /// `toLocaleDateString('es-AR', {day: 'numeric', month: 'short'})`.
    static func fechaCorta(_ iso: String) -> String {
        guard let ms = RelojLocal.desdeISO(iso) else { return iso }
        let f = RelojLocal().ymd(ms)
        let p = f.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]
        return "\(p[2]) \(meses[p[1] - 1])"
    }
}
