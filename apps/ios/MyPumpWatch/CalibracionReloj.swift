import Foundation
@preconcurrency import CoreMotion
import Observation
import WatchKit
import MyPumpReglas
import MyPumpReloj

/// Los sensores del reloj durante el entreno: el contador de reps (para todos, salvo que el servidor lo apague) y, solo en
/// el modo calibración, la grabación a archivo.
///
/// - Sensores: `CMMotionManager` (aceleración total y giro). No pide permiso de movimiento. Sigue con la muñeca baja o la
///   pantalla apagada mientras corra la sesión de entreno de HealthKit (`EntrenoSalud`).
/// - La grabación es la del kit (`GrabadoraSerie`, en un actor fuera del hilo principal): grilla de 100 Hz y anillo de
///   5 minutos. Cada segundo corre el contador sobre lo que va de la serie.
/// - Al confirmar, y solo en calibración, la ventana se guarda como un `.mpcal` y pasa al iPhone por `transferFile`.
@MainActor @Observable
final class CalibracionReloj {
    /// Lo que contó el contador en lo que va de la serie (nil = no corre).
    private(set) var contadas: Int?
    /// El último conteo completo (para el flujo final).
    private(set) var conteo: ContadorReps.Resultado?
    /// «Conté 9 · cargaste 10» de la última serie confirmada (en calibración).
    private(set) var ultimaComparacion: String?
    /// Los sensores están corriendo.
    private(set) var grabando = false
    /// Están prendidos y hace rato que no entregan nada.
    private(set) var sinMuestras = false

    @ObservationIgnored private let motor = MotorCalibracion()
    @ObservationIgnored private var tareas: [Task<Void, Never>] = []
    @ObservationIgnored private var movimiento: CMMotionManager?
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private let fuente = "motion"
    /// Cada ventana tiene su número: un conteo de la ventana anterior que llega tarde se descarta.
    @ObservationIgnored private var ventana = 0
    /// Lo que se manda al iPhone: (url, nombre) → la conexión.
    @ObservationIgnored var transferir: ((URL, [String: Any]) -> Void)?
    /// Cada conteo en vivo (para el flujo final, `ConfirmacionReps`).
    @ObservationIgnored var alContar: ((ContadorReps.Resultado) -> Void)?
    /// false: no corre el conteo de este segundo (palanca apagada o en el descanso, donde igual se descarta).
    @ObservationIgnored var debeContar: (() -> Bool)?

    static var carpeta: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("calibracion-pendientes")
    }
    let almacen = AlmacenCalibracion(carpeta: CalibracionReloj.carpeta, tope: AlmacenCalibracion.topeReloj)

    static var ahora: Double { ProcessInfo.processInfo.systemUptime }

    // MARK: - Sensores

    /// Prende o apaga los sensores según haga falta (lo llama `EstadoReloj` cada vez que cambia la sesión). Siempre a
    /// 100 Hz, la frecuencia con la que se midió el contador: el `esfuerzo` necesita ver la vibración arriba de 2,5 Hz.
    func ajustar(prender: Bool) {
        if prender && !grabando { arrancar() } else if !prender && grabando { parar() }
    }

    private func arrancar() {
        grabando = true
        sinMuestras = false
        contadas = nil
        arrancarMovimiento()
        // Una ventana desde ya (si se prendió a mitad de una serie); empezar, elegir o confirmar la reemplazan.
        let t = Self.ahora
        ventana += 1
        let n = ventana
        Task { await motor.abrirVentana(en: t, numero: n) }
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.contarEnVivo()
            }
        }
    }

    /// `CMMotionManager`: aceleración total (gravedad + usuario) y giro.
    private func arrancarMovimiento() {
        let hz = GrabadoraSerie.hz
        let m = CMMotionManager()
        guard m.isDeviceMotionAvailable else { movimiento = nil; return }
        m.deviceMotionUpdateInterval = 1.0 / hz
        movimiento = m
        let motor = self.motor
        let cola = OperationQueue()
        cola.maxConcurrentOperationCount = 1
        let junta = Junta(tope: Int(hz / 4))
        // Un solo consumidor en orden (la grabadora descarta lo que llega tarde).
        let (lotes, entrada) = AsyncStream.makeStream(of: ([MuestraEjes], [MuestraEjes]).self)
        tareas.append(Task.detached {
            for await l in lotes { await motor.agregar(acelerometro: l.0, giroscopio: l.1, llego: Self.ahora) }
        })
        // Corre en `cola`: `@Sendable` para que no herede el MainActor (Swift 6 cortaría la app).
        m.startDeviceMotionUpdates(to: cola) { @Sendable d, _ in
            guard let d else { return }
            let a = MuestraEjes(t: d.timestamp, x: Float(d.gravity.x + d.userAcceleration.x), y: Float(d.gravity.y + d.userAcceleration.y),
                                z: Float(d.gravity.z + d.userAcceleration.z))
            let g = MuestraEjes(t: d.timestamp, x: Float(d.rotationRate.x), y: Float(d.rotationRate.y), z: Float(d.rotationRate.z))
            if let lote = junta.agregar(a, g) { entrada.yield(lote) }
        }
    }

    private func parar() {
        grabando = false
        tareas.forEach { $0.cancel() }
        tareas = []
        movimiento?.stopDeviceMotionUpdates()
        movimiento = nil
        sinMuestras = false
        tick?.cancel()
        tick = nil
        contadas = nil
        conteo = nil
        Task { await motor.reiniciar() }
    }

    // MARK: - La ventana de la serie

    func abrirVentana() {
        guard grabando else { return }
        ventana += 1
        contadas = nil
        conteo = nil
        let t = Self.ahora
        let n = ventana
        Task { await motor.abrirVentana(en: t, numero: n) }
    }

    func finDescanso() {
        guard grabando else { return }
        let t = Self.ahora
        Task { await motor.marcarFinDescanso(en: t) }
    }

    /// Sin una muestra en este tiempo, los sensores no están entregando (permiso, sensor o la app suspendida).
    private static let esperaMuestras: Double = 5

    private func contarEnVivo() async {
        guard grabando, debeContar?() ?? true else { return }
        let v = ventana
        let ahora = Self.ahora
        guard let (vivo, llego, arranco) = await motor.contar(hasta: ahora, ventana: v) else { return }
        guard v == ventana, grabando else { return }   // se confirmó o se abrió otra ventana mientras contaba
        sinMuestras = ahora - (llego ?? arranco) >= Self.esperaMuestras
        conteo = vivo
        contadas = vivo?.reps
        if let vivo { alContar?(vivo) }
    }

    /// Lo de la serie que se confirma: el ejercicio y lo que se cargó.
    struct Etiqueta {
        var sesion: String
        var ejercicio: EjercicioReloj
        var serie: Int
        var reps: Int
        var kg: Double?
        var cuenta: String
        /// Lo que propuso el reloj con la corona y si el alumno lo tocó (la integridad de la etiqueta).
        var propuesta: Int?
        var corregida: Bool?
    }

    /// Al confirmar: cierra la ventana, cuenta sobre ella con la misma regla que la evaluación y, en calibración, la
    /// guarda y la manda al iPhone. Después abre la ventana de la serie siguiente.
    func confirmar(_ e: Etiqueta, guardar: Bool) {
        guard grabando else { return }
        let t = Self.ahora
        let fuente = self.fuente
        let dispositivo = WKInterfaceDevice.current()
        let muneca = dispositivo.wristLocation == .left ? "izquierda" : "derecha"
        let corona = dispositivo.crownOrientation == .left ? "izquierda" : "derecha"
        let almacen = self.almacen
        ventana += 1
        contadas = nil
        conteo = nil
        let numero = ventana
        let orden = guardar ? Self.siguienteOrden(e.sesion) : 0
        let confirmada = Date().timeIntervalSince1970 * 1000
        let motor = self.motor
        Task {
            // El conteo, la compresión y la escritura corren en el actor (fuera del hilo principal).
            guard let (url, nombre, contadas) = await motor.cerrarYGuardar(
                en: t, numero: numero, guardar: guardar, almacen: almacen,
                encabezado: { v, conteo in
                    EncabezadoSerie(sesion: e.sesion, orden: orden, confirmada: confirmada,
                                    ejercicio: ClaveEjercicio.de(e.ejercicio.nombre), nombre: e.ejercicio.nombre,
                                    familia: e.ejercicio.familia, patron: e.ejercicio.patron, equipo: e.ejercicio.equipo,
                                    serie: e.serie, reps: e.reps, kg: e.kg, contadas: conteo.reps, conteo: conteo,
                                    propuesta: e.propuesta, corregida: e.corregida,
                                    inicioConteo: v.inicioConteo, finDescanso: v.finDescanso, recortado: v.recortado,
                                    fuente: fuente, muneca: muneca, corona: corona)
                },
                // La cuenta va en el nombre del archivo del reloj (para reenviarlo con la suya), nunca adentro. Con la
                // hora: si se reinstala la app del reloj y el número vuelve a 1, el iPhone no lo toma por un reenvío.
                nombre: "\(e.cuenta)_\(e.sesion)-\(String(format: "%03d", orden))-\(String(format: "%.0f", confirmada)).\(ArchivoCalibracion.extension_)")
            else { return }
            self.ultimaComparacion = "Conté \(contadas) · cargaste \(e.reps)"
            self.transferir?(url, Self.metadatos(nombre))
        }
    }

    /// Los metadatos de un archivo para el iPhone: el nombre (para no duplicar) y la cuenta (sale del nombre). nil si el
    /// nombre no trae cuenta (no se manda: el iPhone lo descartaría y el reloj lo borraría).
    static func metadatos(_ nombre: String) -> [String: Any] {
        let cuenta = nombre.split(separator: "_", maxSplits: 1).first.map(String.init) ?? ""
        return ["nombre": nombre, "cuenta": cuenta]
    }

    static func cuenta(deArchivo url: URL) -> String? {
        let partes = url.lastPathComponent.split(separator: "_", maxSplits: 1)
        guard partes.count == 2, !partes[0].isEmpty else { return nil }
        return String(partes[0])
    }

    /// Lo que quedó sin pasar al iPhone (se reintenta al activarse).
    func pendientes() -> [URL] { almacen.archivos().map(\.url) }

    /// El iPhone recibió el archivo: se borra del reloj.
    func recibido(_ url: URL) { almacen.borrar(url) }

    static func siguienteOrden(_ sesion: String) -> Int {
        let clave = "mypump-calibracion-orden-\(sesion)"
        let n = UserDefaults.standard.integer(forKey: clave) + 1
        UserDefaults.standard.set(n, forKey: clave)
        return n
    }

    /// La sesión de calibración: la fecha, la semana y un id al azar por día de entreno, guardado en el reloj (nada que
    /// se pueda cruzar con la rutina del servidor ni con la cuenta).
    static func sesion(_ r: RutinaReloj) -> String {
        let clave = "mypump-calibracion-sesion-\(r.fecha)-\(r.semana)-\(r.diaId)"
        let id = UserDefaults.standard.string(forKey: clave) ?? {
            let nuevo = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
            UserDefaults.standard.set(nuevo, forKey: clave)
            return nuevo
        }()
        return "\(r.fecha)-s\(r.semana)-\(id)"
    }
}

/// La grabadora del kit fuera del hilo principal.
actor MotorCalibracion {
    private var g = GrabadoraSerie()
    private var ultimaLlegada: Double?
    private let arranque = ProcessInfo.processInfo.systemUptime
    func agregar(acelerometro a: [MuestraEjes], giroscopio w: [MuestraEjes], llego t: Double) {
        ultimaLlegada = t
        g.agregar(acelerometro: a, giroscopio: w)
    }
    /// La ventana que tiene abierta este actor: un tick pedido con otro número es de antes de cerrar o de abrir.
    private var ventanaAbierta = 0
    func abrirVentana(en t: Double, numero: Int) { g.abrirVentana(en: t); ventanaAbierta = numero }
    func marcarFinDescanso(en t: Double) { g.marcarFinDescanso(en: t) }
    func cerrar(en t: Double) -> GrabadoraSerie.Ventana? { g.cerrar(en: t) }

    /// Cierra la ventana, abre la siguiente y, si `guardar`, cuenta con la misma regla que la evaluación, arma el
    /// registro y lo escribe. Devuelve el archivo, su nombre y lo contado.
    func cerrarYGuardar(en t: Double, numero: Int, guardar: Bool, almacen: AlmacenCalibracion,
                        encabezado: @Sendable (GrabadoraSerie.Ventana, ContadorReps.Resultado) -> EncabezadoSerie,
                        nombre: String) -> (URL, String, Int)? {
        let v = g.cerrar(en: t)
        g.abrirVentana(en: t)
        ventanaAbierta = numero
        guard guardar, let v else { return nil }
        let conteo = v.contar()
        guard let d = try? ArchivoCalibracion.datos(.init(encabezado: encabezado(v, conteo), cuadros: v.cuadros)),
              let url = try? almacen.guardar(d, nombre: nombre) else { return nil }
        return (url, nombre, conteo.reps)
    }
    func reiniciar() { g = GrabadoraSerie(); ultimaLlegada = nil }
    /// El contador sobre lo que va de la serie (nil sin ventana abierta) y cuándo llegó la última muestra.
    func contar(hasta t: Double, ventana v: Int) -> (ContadorReps.Resultado?, Double?, Double)? {
        guard v == ventanaAbierta else { return nil }
        return (g.contarEnVivo(hasta: t), ultimaLlegada, arranque)
    }
}

/// Junta las muestras de `CMMotionManager` (que llegan de a una) en lotes de un cuarto de segundo.
private final class Junta: @unchecked Sendable {
    private var a: [MuestraEjes] = []
    private var g: [MuestraEjes] = []
    private let tope: Int
    private let candado = NSLock()
    init(tope: Int) { self.tope = tope }
    func agregar(_ ma: MuestraEjes, _ mg: MuestraEjes) -> ([MuestraEjes], [MuestraEjes])? {
        candado.lock(); defer { candado.unlock() }
        a.append(ma); g.append(mg)
        guard a.count >= tope else { return nil }
        defer { a = []; g = [] }
        return (a, g)
    }
}
