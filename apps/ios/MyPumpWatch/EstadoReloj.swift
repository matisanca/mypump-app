import Foundation
import Observation
import WatchKit
import WidgetKit
import MyPumpReglas
import MyPumpReloj

/// El reloj visto desde las pantallas: la sesión (`SesionReloj`, pura, del kit) guardada en disco, la conexión con el
/// iPhone, la sesión de entreno de HealthKit y las complicaciones. Todo lo que cambia la sesión pasa por `cambiar`, que
/// guarda, actualiza las complicaciones y manda la cola.
@MainActor @Observable
final class EstadoReloj {
    /// Uno solo: lo usan la app y el delegado (la recuperación del entreno tras un cierre).
    static let compartido = EstadoReloj()
    static let grupo = "group.com.pumpteam.mypump.reloj"

    private(set) var sesion = SesionReloj()
    /// El iPhone dijo que no hay rutina (sin cuenta, sin rutina activa).
    private(set) var sinRutina: String?
    /// El iPhone tiene otra versión del protocolo: qué actualizar (no se le reenvía nada hasta entonces).
    var incompatible: String? { sesion.incompatible }
    /// El aviso de récord de la última serie.
    var avisoRecord: String?
    /// El resumen al terminar.
    var resumen: ResumenReloj?
    /// FC y calorías en vivo.
    private(set) var salud = SaludEntreno()
    /// Se ve el iPhone ahora (WatchConnectivity alcanzable).
    var conectado = false
    /// Tanda 4: el modo calibración y el contador experimental.
    let calibracion = CalibracionReloj()
    /// Flujo final (apagado: `ConfirmacionReps.habilitadas` está vacía): las reps que el reloj propuso con la corona en
    /// esta serie («¿10 reps?»).
    private(set) var propuesta: Int?

    @ObservationIgnored private let conexion = ConexionReloj()
    @ObservationIgnored private let entreno = EntrenoSalud()
    /// En la demo no se pide permiso de Salud (las capturas), salvo con `-salud`.
    @ObservationIgnored private let conSalud = !ProcessInfo.processInfo.arguments.contains("-demo") || ProcessInfo.processInfo.arguments.contains("-salud")
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var ultimaComplicacion: EstadoComplicacion?

    static var ahoraMs: Double { Date().timeIntervalSince1970 * 1000 }

    /// Donde se guarda: el contenedor del App Group (lo lee la extensión de complicaciones); si no hay (sin la
    /// capability), Application Support.
    static var carpeta: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grupo)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    static var archivoSesion: URL { carpeta.appendingPathComponent("sesion-reloj.json") }
    static var archivoComplicacion: URL { carpeta.appendingPathComponent(EstadoComplicacion.archivo) }

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo") {
            sesion.recibir(.demo(fecha: FechaJS.ymd(Date(), zona: .current), generada: Self.ahoraMs))
        } else if let d = try? Data(contentsOf: Self.archivoSesion), let s = try? JSONDecoder().decode(SesionReloj.self, from: d) {
            sesion = s
        }
        conexion.alRecibir = { [weak self] m, v in self?.recibir(m, version: v) }
        conexion.alCambiarAlcance = { [weak self] alcanzable in
            self?.conectado = alcanzable
            if alcanzable { self?.sincronizar(forzar: true) }
        }
        conexion.alFallarVersion = { [weak self] v in self?.cambiar(enviar: false) { $0.marcarIncompatible(version: v) } }
        entreno.alMedir = { [weak self] s in self?.salud = s }
        entreno.alAbrir = { [weak self] in self?.calibracion.sesionDeEntrenoAbierta() }
        calibracion.transferir = { [weak self] url, metadatos in self?.conexion.transferirArchivo(url, metadatos: metadatos) }
        calibracion.alContar = { [weak self] r in self?.proponer(r) }
        conexion.alTransferirArchivo = { [weak self] url in self?.calibracion.recibido(url) }
        if !args.contains("-demo") { conexion.activar() }
        actualizarComplicacion()
        ajustarSensores()
    }

    // MARK: - Modo calibración (tanda 4)

    /// El iPhone mandó el modo prendido para esta cuenta (en la demo, solo con `-calibracion`, para las capturas).
    var calibrando: Bool {
        guard let r = sesion.rutina else { return false }
        if r.demo { return ProcessInfo.processInfo.arguments.contains("-calibracion") }
        return r.calibracion == true
    }

    /// Los sensores corren con la sesión empezada y abierta, en calibración o si algún ejercicio del día es de una
    /// familia con el flujo final habilitado (ninguna por ahora). Si no, no se tocan.
    private func ajustarSensores() {
        let familias = sesion.rutina?.ejercicios.contains { ConfirmacionReps.cuenta($0.familia) } ?? false
        calibracion.ajustar(prender: sesion.iniciada && !sesion.terminada && (calibrando || familias))
    }

    /// Flujo final: con la serie terminada y una familia habilitada, la corona va a lo que contó el reloj y se pregunta
    /// «¿N reps?». Nunca en calibración (`ConfirmacionReps.propuesta` lo descarta) y una sola vez por serie.
    private func proponer(_ r: ContadorReps.Resultado?) {
        guard propuesta == nil, let r, let e = sesion.actual, e.proximaSerie != nil,
              let n = ConfirmacionReps.propuesta(e.familia, conteo: r, calibrando: calibrando) else { return }
        cambiar(enviar: false) { $0.girarReps(n - $0.reps) }
        propuesta = n
    }

    /// Los archivos de calibración que quedaron sin pasar al iPhone.
    private func reenviarCalibracion() {
        // Cada archivo con la cuenta con la que se grabó (va en el nombre); uno sin cuenta no se manda.
        for url in calibracion.pendientes() where CalibracionReloj.cuenta(deArchivo: url) != nil {
            conexion.transferirArchivo(url, metadatos: CalibracionReloj.metadatos(url.lastPathComponent))
        }
    }

    // MARK: - Lo que llega del iPhone

    private func recibir(_ m: MensajeReloj, version: Int) {
        if version != ProtocoloReloj.version || sesion.incompatible != nil { cambiar(enviar: false) { $0.revisarVersion(version) } }
        switch m {
        case .rutina(let r):
            sinRutina = nil
            cambiar { $0.recibir(r) }
        case .acuse(let a):
            cambiar { $0.acusar(a, ahora: Self.ahoraMs) }
        case .incompatible(let v):
            cambiar(enviar: false) { $0.marcarIncompatible(version: v) }
        case .sinRutina(let motivo):
            sinRutina = motivo
        case .pedirRutina, .eventos:
            break
        }
    }

    // MARK: - Acciones

    func elegir(_ lugar: String) {
        let otro = lugar != sesion.lugar
        cambiar { $0.elegir(lugar) }
        if otro { propuesta = nil; calibracion.abrirVentana() }
    }
    func girarReps(_ n: Int) { cambiar(enviar: false) { $0.girarReps(n) } }
    func girarKg(_ n: Int) { cambiar(enviar: false) { $0.girarKg(n) } }

    func empezar() {
        cambiar { $0.iniciar(ahora: Self.ahoraMs) }
        if conSalud { entreno.empezar() }
        calibracion.abrirVentana()
    }

    func confirmar() {
        let ahora = Self.ahoraMs
        // Lo que se confirma, para la etiqueta de la grabación (antes de que la sesión pase a la serie siguiente).
        let etiqueta: CalibracionReloj.Etiqueta? = {
            guard let r = sesion.rutina, let e = sesion.actual, let i = e.proximaSerie else { return nil }
            return .init(sesion: CalibracionReloj.sesion(r), ejercicio: e, serie: i + 1, reps: sesion.reps,
                         kg: e.sinKg ? nil : (sesion.kg ?? 0), cuenta: r.cuenta)
        }()
        let estabaGrabando = calibracion.grabando
        var c: SesionReloj.Confirmacion?
        cambiar { c = $0.confirmar(ahora: ahora) }
        guard let c else { return }
        propuesta = nil
        // La primera serie confirmada sin «Empezar» arranca la sesión (y los sensores): esa serie no tiene ventana.
        if estabaGrabando, let etiqueta { calibracion.confirmar(etiqueta, guardar: calibrando) } else { calibracion.abrirVentana() }
        if conSalud { entreno.empezar() }
        WKInterfaceDevice.current().play(c.record != nil ? .success : .click)
        avisoRecord = c.record
        if c.descanso { correrDescanso() }
    }

    func terminar() {
        let s = salud
        var r: ResumenReloj?
        cambiar { r = $0.terminar(ahora: Self.ahoraMs, salud: s) }
        entreno.terminar()
        resumen = r
        WKInterfaceDevice.current().play(.stop)
    }

    /// El alumno leyó lo que el iPhone no pudo guardar.
    func leerRechazos() { cambiar(enviar: false) { $0.leerRechazos() } }

    /// El sistema relanzó la app con un entreno de HealthKit abierto (se cerró o se colgó a mitad): si el día sigue en
    /// curso se retoma la medición; si ya terminó (o no empezó), se cierra y se descarta.
    func recuperarEntreno() {
        entreno.recuperar(seguir: conSalud && sesion.iniciada && !sesion.terminada)
    }

    func ajustarDescanso(_ s: Double) { cambiar(enviar: false) { $0.ajustarDescanso(s, ahora: Self.ahoraMs) } }
    func saltarDescanso() {
        cambiar(enviar: false) { $0.saltarDescanso() }
        calibracion.finDescanso()
    }

    // MARK: - Descanso

    /// El tick del descanso (4 por segundo mientras corre): la háptica al terminar.
    func correrDescanso() {
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled, let self, self.sesion.descanso != nil {
                var termino = false
                self.sesion = { var s = self.sesion; termino = s.tickDescanso(ahora: Self.ahoraMs); return s }()
                if termino {
                    self.calibracion.finDescanso()
                    WKInterfaceDevice.current().play(.notification)
                    self.guardar()
                    self.actualizarComplicacion()
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            self?.guardar()
            self?.actualizarComplicacion()
        }
    }

    /// Al volver a primer plano: el descanso contra el reloj y la cola al iPhone.
    func alActivarse() {
        if sesion.descanso != nil { correrDescanso() }
        sincronizar(forzar: true)
        reenviarCalibracion()
    }

    // MARK: - Interno

    private func cambiar(enviar: Bool = true, _ f: (inout SesionReloj) -> Void) {
        var s = sesion
        f(&s)
        sesion = s
        // El día se cerró (en el reloj o en el iPhone) o no hay nada empezado: el entreno de HealthKit no queda abierto.
        if s.terminada || !s.iniciada { entreno.terminar() }
        ajustarSensores()
        guardar()
        actualizarComplicacion()
        if enviar { sincronizar() }
    }

    private func guardar() {
        guard !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        try? FileManager.default.createDirectory(at: Self.carpeta, withIntermediateDirectories: true)
        try? JSONEncoder().encode(sesion).write(to: Self.archivoSesion, options: .atomic)
    }

    /// Manda la cola al iPhone (o pide la rutina si no hay).
    func sincronizar(forzar: Bool = false) {
        var s = sesion
        let lote = s.paraEnviar(ahora: Self.ahoraMs, forzar: forzar)
        sesion = s
        if !lote.isEmpty {
            conexion.enviar(.eventos(lote)) { [weak self] ok in
                if !ok { self?.cambiar(enviar: false) { $0.fallo(lote.map(\.id)) } }
            }
        }
        if forzar || sesion.rutina == nil { conexion.enviar(.pedirRutina, alTerminar: nil) }
    }

    private func actualizarComplicacion() {
        let c = EstadoComplicacion.de(sesion, ahora: Self.ahoraMs)
        var comparable = c
        comparable.actualizado = ultimaComplicacion?.actualizado ?? 0
        guard comparable != ultimaComplicacion else { return }
        ultimaComplicacion = c
        try? c.guardar(Self.archivoComplicacion)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
