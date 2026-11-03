import Foundation
@preconcurrency import CoreMotion
import Observation
import WatchKit
import MyPumpReglas
import MyPumpReloj

/// El modo calibración en el reloj (tanda 4). Solo corre si el iPhone lo mandó prendido con la rutina
/// (`RutinaReloj.calibracion`) o si el ejercicio es de una familia con el flujo final habilitado (lista vacía: nunca).
/// Apagado, no toca los sensores ni pide el permiso de movimiento.
///
/// - Sensores: `CMBatchedSensorManager` (800 Hz de aceleración y 200 de giro; necesita la sesión de entreno de
///   HealthKit abierta). Si no está o falla (sin la sesión, sin permiso de Salud), `CMMotionManager` a 100 Hz.
/// - La grabación es la del kit (`GrabadoraSerie`, en un actor fuera del hilo principal): grilla de 100 Hz y anillo de
///   5 minutos. Cada segundo corre el contador sobre lo que va de la serie («Conté N»).
/// - Al confirmar la serie, la ventana se guarda como un `.mpcal` (`ArchivoCalibracion`) con las reps confirmadas, el
///   ejercicio, la familia, el equipo y lo que contó el contador, en una carpeta con tope (`AlmacenCalibracion`), y pasa
///   al iPhone por `transferFile`. Se borra del reloj cuando el iPhone lo recibió. Nada va a ningún servidor.
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

    @ObservationIgnored private let motor = MotorCalibracion()
    @ObservationIgnored private var batched: CMBatchedSensorManager?
    @ObservationIgnored private var tareas: [Task<Void, Never>] = []
    @ObservationIgnored private var movimiento: CMMotionManager?
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private(set) var fuente = "batched"
    /// Lo que se manda al iPhone: (url, nombre) → la conexión.
    @ObservationIgnored var transferir: ((URL, [String: Any]) -> Void)?
    /// Cada conteo en vivo (para el flujo final, `ConfirmacionReps`).
    @ObservationIgnored var alContar: ((ContadorReps.Resultado?) -> Void)?

    static var carpeta: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("calibracion-pendientes")
    }
    let almacen = AlmacenCalibracion(carpeta: CalibracionReloj.carpeta, tope: AlmacenCalibracion.topeReloj)

    static var ahora: Double { ProcessInfo.processInfo.systemUptime }

    // MARK: - Sensores

    /// Prende o apaga los sensores según haga falta (lo llama `EstadoReloj` cada vez que cambia la sesión).
    func ajustar(prender: Bool) {
        if prender && !grabando { arrancar() } else if !prender && grabando { parar() }
    }

    private func arrancar() {
        grabando = true
        contadas = nil
        if CMBatchedSensorManager.isAccelerometerSupported && CMBatchedSensorManager.isDeviceMotionSupported {
            arrancarBatched()
        } else {
            arrancarMovimiento()
        }
        // Una ventana desde ya (si se prendió a mitad de una serie); empezar, elegir o confirmar la reemplazan.
        let t = Self.ahora
        Task { await motor.abrirVentana(en: t) }
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.contarEnVivo()
            }
        }
    }

    private func arrancarBatched() {
        fuente = "batched"
        let m = CMBatchedSensorManager()
        batched = m
        let motor = self.motor
        // Si cualquiera de los dos se corta con un error (sin la sesión de entreno), se pasa a CMMotionManager.
        tareas.append(Task.detached { [weak self] in
            do {
                for try await lote in m.accelerometerUpdates() {
                    await motor.agregar(acelerometro: lote.map { MuestraEjes(t: $0.timestamp, x: Float($0.acceleration.x), y: Float($0.acceleration.y), z: Float($0.acceleration.z)) })
                }
            } catch {
                await self?.pasarAMovimiento()
            }
        })
        tareas.append(Task.detached { [weak self] in
            do {
                for try await lote in m.deviceMotionUpdates() {
                    await motor.agregar(giroscopio: lote.map { MuestraEjes(t: $0.timestamp, x: Float($0.rotationRate.x), y: Float($0.rotationRate.y), z: Float($0.rotationRate.z)) })
                }
            } catch {
                await self?.pasarAMovimiento()
            }
        })
    }

    private func pasarAMovimiento() {
        guard grabando, movimiento == nil else { return }
        tareas.forEach { $0.cancel() }
        tareas = []
        batched = nil
        arrancarMovimiento()
    }

    /// `CMMotionManager` a la frecuencia más alta que dé el reloj (100 Hz): aceleración total (gravedad + usuario) y giro.
    private func arrancarMovimiento() {
        fuente = "motion"
        let m = CMMotionManager()
        guard m.isDeviceMotionAvailable else { return }
        m.deviceMotionUpdateInterval = 1.0 / 100
        movimiento = m
        let motor = self.motor
        let cola = OperationQueue()
        cola.maxConcurrentOperationCount = 1
        let junta = Junta()
        // Un solo consumidor en orden (la grabadora descarta lo que llega tarde).
        let (lotes, entrada) = AsyncStream.makeStream(of: ([MuestraEjes], [MuestraEjes]).self)
        tareas.append(Task.detached {
            for await l in lotes { await motor.agregar(acelerometro: l.0, giroscopio: l.1) }
        })
        m.startDeviceMotionUpdates(to: cola) { d, _ in
            guard let d else { return }
            let a = MuestraEjes(t: d.timestamp, x: Float(d.gravity.x + d.userAcceleration.x), y: Float(d.gravity.y + d.userAcceleration.y),
                                z: Float(d.gravity.z + d.userAcceleration.z))
            let g = MuestraEjes(t: d.timestamp, x: Float(d.rotationRate.x), y: Float(d.rotationRate.y), z: Float(d.rotationRate.z))
            // De a 25 muestras (un cuarto de segundo) al actor.
            if let lote = junta.agregar(a, g) { entrada.yield(lote) }
        }
    }

    private func parar() {
        grabando = false
        tareas.forEach { $0.cancel() }
        tareas = []
        batched = nil
        movimiento?.stopDeviceMotionUpdates()
        movimiento = nil
        tick?.cancel()
        tick = nil
        contadas = nil
        conteo = nil
        Task { await motor.reiniciar() }
    }

    // MARK: - La ventana de la serie

    func abrirVentana() {
        guard grabando else { return }
        contadas = nil
        conteo = nil
        let t = Self.ahora
        Task { await motor.abrirVentana(en: t) }
    }

    func finDescanso() {
        guard grabando else { return }
        let t = Self.ahora
        Task { await motor.marcarFinDescanso(en: t) }
    }

    private func contarEnVivo() async {
        guard grabando else { return }
        let r = await motor.contar(hasta: Self.ahora)
        conteo = r
        contadas = r?.reps
        alContar?(r)
    }

    /// Lo de la serie que se confirma: el ejercicio y lo que se cargó.
    struct Etiqueta {
        var sesion: String
        var ejercicio: EjercicioReloj
        var serie: Int
        var reps: Int
        var kg: Double?
        var cuenta: String
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
        contadas = nil
        conteo = nil
        Task {
            guard let v = await motor.cerrar(en: t) else { return }
            await motor.abrirVentana(en: t)
            guard guardar else { return }
            let conteo = ContadorReps.contar(Array(v.cuadros[min(v.inicioConteo, v.cuadros.count)...]))
            let orden = Self.siguienteOrden(e.sesion)
            let enc = EncabezadoSerie(sesion: e.sesion, orden: orden, confirmada: Date().timeIntervalSince1970 * 1000,
                                      ejercicio: ClaveEjercicio.de(e.ejercicio.nombre), nombre: e.ejercicio.nombre,
                                      familia: e.ejercicio.familia, patron: e.ejercicio.patron, equipo: e.ejercicio.equipo,
                                      serie: e.serie, reps: e.reps, kg: e.kg, contadas: conteo.reps, conteo: conteo,
                                      inicioConteo: v.inicioConteo, finDescanso: v.finDescanso, recortado: v.recortado,
                                      fuente: fuente, muneca: muneca, corona: corona)
            self.ultimaComparacion = "Conté \(conteo.reps) · cargaste \(e.reps)"
            let nombre = "\(e.sesion)-\(String(format: "%03d", orden)).\(ArchivoCalibracion.extension_)"
            guard let d = try? ArchivoCalibracion.datos(.init(encabezado: enc, cuadros: v.cuadros)),
                  let url = try? almacen.guardar(d, nombre: nombre) else { return }
            self.transferir?(url, ["mpcal": e.sesion, "nombre": nombre, "cuenta": e.cuenta])
        }
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

    /// La sesión de calibración: el día de entreno (fecha, semana y día de la rutina), sin nada de la cuenta.
    static func sesion(_ r: RutinaReloj) -> String {
        let dia = r.diaId.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(12)
        return "\(r.fecha)-s\(r.semana)-\(String(String.UnicodeScalarView(dia)))"
    }
}

/// La grabadora del kit fuera del hilo principal.
actor MotorCalibracion {
    private var g = GrabadoraSerie()
    func agregar(acelerometro a: [MuestraEjes]) { g.agregar(acelerometro: a) }
    func agregar(giroscopio w: [MuestraEjes]) { g.agregar(giroscopio: w) }
    func agregar(acelerometro a: [MuestraEjes], giroscopio w: [MuestraEjes]) { g.agregar(acelerometro: a, giroscopio: w) }
    func abrirVentana(en t: Double) { g.abrirVentana(en: t) }
    func marcarFinDescanso(en t: Double) { g.marcarFinDescanso(en: t) }
    func cerrar(en t: Double) -> GrabadoraSerie.Ventana? { g.cerrar(en: t) }
    func reiniciar() { g = GrabadoraSerie() }
    /// El contador sobre lo que va de la serie (nil sin ventana abierta).
    func contar(hasta t: Double) -> ContadorReps.Resultado? {
        guard g.inicioVentana != nil else { return nil }
        return ContadorReps.contar(g.paraContar(hasta: t))
    }
}

/// Junta las muestras de `CMMotionManager` (que llegan de a una) en lotes de un cuarto de segundo.
private final class Junta: @unchecked Sendable {
    private var a: [MuestraEjes] = []
    private var g: [MuestraEjes] = []
    private let candado = NSLock()
    func agregar(_ ma: MuestraEjes, _ mg: MuestraEjes) -> ([MuestraEjes], [MuestraEjes])? {
        candado.lock(); defer { candado.unlock() }
        a.append(ma); g.append(mg)
        guard a.count >= 25 else { return nil }
        defer { a = []; g = [] }
        return (a, g)
    }
}
