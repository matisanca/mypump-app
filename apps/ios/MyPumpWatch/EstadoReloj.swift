import Foundation
import Observation
import WatchKit
import WidgetKit
import Accessibility
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
    /// Los sensores: el contador de reps y, en el modo calibración, la grabación.
    let calibracion = CalibracionReloj()
    /// Las reps que el reloj propuso con la corona en esta serie («¿10 reps?») y si el alumno las tocó.
    private(set) var propuestaSerie = PropuestaSerie()
    var propuesta: Int? { propuestaSerie.reps }
    /// Sube cada vez que hay que entrar al día (llegó el día elegido o se tocó el que ya estaba): la raíz navega.
    private(set) var abrirDia = 0
    /// La sesión de entreno corre (sin ella, con la muñeca baja los sensores se duermen).
    private(set) var entrenoVivo = false

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
            // Un pedido de día guardado de antes de cerrarse la app: su espera murió con ella. Vencido, se avisa; si no,
            // se vuelve a esperar (sin esto la lista quedaba trabada esperando para siempre).
            if !sesion.vencerPedido(ahora: Self.ahoraMs), sesion.diaPedido != nil { esperarDia() }
        }
        conexion.alRecibir = { [weak self] m, v in self?.recibir(m, version: v) }
        conexion.alCambiarAlcance = { [weak self] alcanzable in
            self?.conectado = alcanzable
            if alcanzable { self?.sincronizar(forzar: true) }
        }
        conexion.alFallarVersion = { [weak self] v in self?.cambiar(enviar: false) { $0.marcarIncompatible(version: v) } }
        entreno.alMedir = { [weak self] s in self?.salud = s }
        entreno.alCambiarViva = { [weak self] viva in self?.entrenoVivo = viva }
        calibracion.transferir = { [weak self] url, metadatos in self?.conexion.transferirArchivo(url, metadatos: metadatos) }
        calibracion.alContar = { [weak self] r in self?.proponer(r) }
        calibracion.debeContar = { [weak self] in self.map { $0.contadorPrendido && $0.sesion.descanso == nil } ?? false }
        restaurarPropuesta()
        conexion.alTransferirArchivo = { [weak self] url in self?.calibracion.recibido(url) }
        if !args.contains("-demo") { conexion.activar() }
        actualizarComplicacion()
        ajustarSensores()
    }

    // MARK: - El contador de reps y el modo calibración

    /// El iPhone mandó el modo calibración (grabar las series a archivo) prendido para esta cuenta.
    var calibrando: Bool {
        guard let r = sesion.rutina else { return false }
        if r.demo && ProcessInfo.processInfo.arguments.contains("-calibracion") { return true }
        return r.calibracion == true
    }

    /// El contador está prendido para todos; solo el servidor lo apaga (`reloj_contador_reps`).
    var contadorPrendido: Bool { sesion.rutina?.contadorReps != false }

    /// Lo que dice la pantalla del ejercicio sobre el conteo.
    var avisoConteo: AvisoConteo {
        guard let e = sesion.actual else { return .ninguno }
        return AvisoConteo.de(prendido: contadorPrendido, iniciada: sesion.iniciada && !sesion.terminada, enDescanso: sesion.descanso != nil,
                              conPropuesta: propuestaSerie.enLaCorona(sesion.reps), muestras: calibracion.grabando && !calibracion.sinMuestras,
                              sesionViva: entrenoVivo || !conSalud, conteo: calibracion.conteo, familia: e.familia)
    }

    /// Los sensores corren con la sesión empezada y abierta, si cuenta o si graba.
    private func ajustarSensores() {
        let inactivo = Self.ahoraMs - ultimaActividad > Self.toleranciaInactivoMs
        calibracion.ajustar(prender: sesion.iniciada && !sesion.terminada && !sesion.todoHecho && !inactivo && (contadorPrendido || calibrando))
    }

    /// 20 min sin tocar el reloj ni confirmar: un entreno olvidado no deja los sensores a 100 Hz.
    private static let toleranciaInactivoMs: Double = 20 * 60 * 1_000
    @ObservationIgnored private var ultimaActividad = EstadoReloj.ahoraMs
    @ObservationIgnored private var vigiaInactividad: Task<Void, Never>?

    /// El alumno tocó, giró o miró el reloj.
    func actividad() {
        ultimaActividad = Self.ahoraMs
        ajustarSensores()
        vigiaInactividad?.cancel()
        vigiaInactividad = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(Self.toleranciaInactivoMs) + 1_000))
            guard !Task.isCancelled else { return }
            self?.ajustarSensores()
        }
    }

    // La propuesta sobrevive a un relanzamiento: si no, se perdería que el alumno giró (y se le pisaría) o que el número
    // de la corona lo puso el reloj. Atada a la serie en la corona.
    private static let clavePropuesta = "mypump-reloj-propuesta"
    private struct PropuestaGuardada: Codable { var serie: String; var propuesta: PropuestaSerie }
    @ObservationIgnored private var propuestaEscrita: PropuestaSerie?

    private func restaurarPropuesta() {
        guard let d = UserDefaults.standard.data(forKey: Self.clavePropuesta),
              let g = try? JSONDecoder().decode(PropuestaGuardada.self, from: d), g.serie == sesion.claveCorona else { return }
        propuestaSerie = g.propuesta
        propuestaEscrita = g.propuesta
    }

    private func guardarPropuesta() {
        guard propuestaSerie != propuestaEscrita else { return }
        propuestaEscrita = propuestaSerie
        guard let serie = sesion.claveCorona, let d = try? JSONEncoder().encode(PropuestaGuardada(serie: serie, propuesta: propuestaSerie)) else {
            UserDefaults.standard.removeObject(forKey: Self.clavePropuesta)
            return
        }
        UserDefaults.standard.set(d, forKey: Self.clavePropuesta)
    }

    /// Cuándo cambió por última vez el número en la corona (un toque justo después no confirma lo que no vio).
    @ObservationIgnored private var cambioPropuesta = 0.0
    private static let graciaConfirmarMs: Double = 700

    /// Con la serie terminada y clara, la corona va a lo que contó el reloj y se pregunta «¿N reps?». Nunca encima de lo
    /// que el alumno giró ni durante el descanso (`PropuestaSerie`): la serie sigue en la ventana cuando el descanso cierra.
    private func proponer(_ r: ContadorReps.Resultado) {
        guard contadorPrendido, sesion.descanso == nil, let e = sesion.actual, e.proximaSerie != nil else { return }
        var p = propuestaSerie
        guard let n = p.proponer(r) else { return }
        propuestaSerie = p
        cambioPropuesta = Self.ahoraMs
        cambiar(enviar: false) { $0.girarReps(n - $0.reps) }
        // Que se note que la corona se movió sola, cada vez (también con VoiceOver).
        WKInterfaceDevice.current().play(.click)
        AccessibilityNotification.Announcement(ConfirmacionReps.textoAccesible(n)).post()
    }

    /// La serie que está en la corona (ejercicio y número).
    private var serieEnCurso: String? { sesion.claveCorona }

    /// La serie en la corona cambió sin confirmar ni elegir en el reloj (llegó la rutina con la serie hecha en el
    /// iPhone, otro día u otro ejercicio): la propuesta y la ventana eran de la anterior y no pasan a esta.
    private func serieCambiada(desde antes: String?) {
        guard serieEnCurso != antes else { return }
        propuestaSerie.reiniciar()
        calibracion.abrirVentana()
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
            var llego = false
            let antes = serieEnCurso
            cambiar { llego = $0.recibir(r) }
            serieCambiada(desde: antes)
            if llego { abrirDia += 1 }
        case .acuse(let a):
            cambiar { $0.acusar(a, ahora: Self.ahoraMs) }
        case .incompatible(let v):
            cambiar(enviar: false) { $0.marcarIncompatible(version: v) }
        case .sinRutina(let motivo):
            sinRutina = motivo
        case .pedirRutina, .pedirDia, .eventos:
            break
        }
    }

    // MARK: - Elegir el día

    @ObservationIgnored private var esperaDia: Task<Void, Never>?

    /// El alumno tocó un día de la lista. El que ya está en el reloj se abre; otro se le pide al iPhone (que lo abre
    /// también en Entreno y contesta con su rutina). Sin el iPhone cerca, con el entreno empezado o sin respuesta, queda
    /// el aviso en la lista y se sigue con el día que hay. En la demo (`-demo`) los días salen de la semana de muestra.
    func elegirDia(_ id: String, demoSinIPhone: Bool = false) {
        let ahora = Self.ahoraMs
        let demo = ProcessInfo.processInfo.arguments.contains("-demo")
        var eleccion = SesionReloj.EleccionDia.entrar
        cambiar(enviar: false) { eleccion = $0.elegirDia(id, conIPhone: demo ? !demoSinIPhone : conectado, ahora: ahora) }
        switch eleccion {
        case .entrar:
            abrirDia += 1
        case .no:
            WKInterfaceDevice.current().play(.failure)
        case .pedir where demo:
            let r = RutinaReloj.demo(fecha: FechaJS.ymd(Date(), zona: .current), generada: ahora, dia: id)
            var llego = false
            let antes = serieEnCurso
            cambiar(enviar: false) { llego = $0.recibir(r) }
            serieCambiada(desde: antes)
            if llego { abrirDia += 1 }
        case .pedir:
            conexion.enviar(.pedirDia(diaId: id)) { [weak self] ok in
                if !ok { self?.cambiar(enviar: false) { $0.pedidoFallido(SesionReloj.textoSinIPhone, dia: id) } }
            }
            esperarDia()
        }
    }

    /// Un iPhone que no conoce `pedirDia` no contesta: pasado `esperaDia` se deja de esperar y se avisa.
    private func esperarDia() {
        esperaDia?.cancel()
        esperaDia = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(SesionReloj.esperaDia) + 200))
            guard !Task.isCancelled, let self else { return }
            if self.sesion.diaPedido != nil { self.cambiar(enviar: false) { _ = $0.vencerPedido(ahora: Self.ahoraMs) } }
        }
    }

    func leerAvisoDia() { cambiar(enviar: false) { $0.leerAvisoDia() } }

    // MARK: - Acciones

    func elegir(_ lugar: String) {
        actividad()
        let otro = lugar != sesion.lugar
        cambiar { $0.elegir(lugar) }
        if otro { propuestaSerie.reiniciar(); calibracion.abrirVentana() }
        // Con el entreno en curso (empezado en el iPhone o tras un cierre) la sesión de entreno mantiene vivos los sensores.
        if conSalud, sesion.iniciada, !sesion.terminada { entreno.empezar() }
    }
    /// El alumno giró las reps con la corona (la propuesta del reloj no pasa por acá).
    func girarReps(_ n: Int) {
        ultimaActividad = Self.ahoraMs
        propuestaSerie.girar()
        cambiar(enviar: false) { $0.girarReps(n) }
    }
    func girarKg(_ n: Int) {
        ultimaActividad = Self.ahoraMs
        cambiar(enviar: false) { $0.girarKg(n) }
    }

    func empezar() {
        actividad()
        cambiar { $0.iniciar(ahora: Self.ahoraMs) }
        if conSalud { entreno.empezar() }
        calibracion.abrirVentana()
    }

    func confirmar() {
        let ahora = Self.ahoraMs
        guard ahora - cambioPropuesta >= Self.graciaConfirmarMs else { return }
        actividad()
        // Lo que se confirma, para la etiqueta de la grabación (antes de que la sesión pase a la serie siguiente).
        let etiqueta: CalibracionReloj.Etiqueta? = {
            guard calibrando, let r = sesion.rutina, r.cuenta != "demo", let e = sesion.actual, let i = e.proximaSerie else { return nil }
            return .init(sesion: CalibracionReloj.sesion(r), ejercicio: e, serie: i + 1, reps: sesion.reps,
                         kg: e.sinKg ? nil : (sesion.kg ?? 0), cuenta: r.cuenta,
                         propuesta: propuestaSerie.reps, corregida: propuestaSerie.corregida(confirmadas: sesion.reps))
        }()
        let estabaGrabando = calibracion.grabando
        var c: SesionReloj.Confirmacion?
        cambiar { c = $0.confirmar(ahora: ahora) }
        guard let c else { return }
        propuestaSerie.reiniciar()
        // La primera serie confirmada sin «Empezar» arranca la sesión (y los sensores): esa serie no tiene ventana.
        if estabaGrabando, let etiqueta { calibracion.confirmar(etiqueta, guardar: true) } else { calibracion.abrirVentana() }
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
        guardarPropuesta()
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
        reintentarMientrasHaya()
    }

    @ObservationIgnored private var reintento: Task<Void, Never>?

    /// Con la cola sin acusar se vuelve a mandar cada `ColaReloj.reintento`, sin esperar a que el alumno toque algo (si
    /// el iPhone tardó en tener la cuenta lista, lo pendiente quedaba hasta volver a abrir el reloj).
    private func reintentarMientrasHaya() {
        guard reintento == nil, !sesion.cola.vacia else { return }
        reintento = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(ColaReloj.reintento) + 500))
                guard let self else { return }
                if self.sesion.cola.vacia { self.reintento = nil; return }
                // Sin el iPhone no se reescribe la sesión cada 20 s: `alCambiarAlcance` fuerza el envío cuando vuelve.
                if self.conectado { self.sincronizar() }
            }
        }
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
