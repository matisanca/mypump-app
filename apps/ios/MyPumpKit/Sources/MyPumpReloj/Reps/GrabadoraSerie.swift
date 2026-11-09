import Foundation

/// Un cuadro de los sensores del reloj en la grilla fija (`GrabadoraSerie.hz`): la aceleración total en g (con la
/// gravedad, en los ejes del reloj) y la velocidad de giro en rad/s.
public struct CuadroSensor: Equatable, Sendable {
    public var ax: Float, ay: Float, az: Float
    public var gx: Float, gy: Float, gz: Float
    public init(ax: Float, ay: Float, az: Float, gx: Float, gy: Float, gz: Float) {
        self.ax = ax; self.ay = ay; self.az = az; self.gx = gx; self.gy = gy; self.gz = gz
    }
    public static let cero = CuadroSensor(ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0)
}

/// Una muestra cruda de un sensor (tres ejes) con su hora en segundos (la del sensor: `CMLogItem.timestamp`, desde el
/// arranque del reloj; la misma base que `ProcessInfo.systemUptime`).
public struct MuestraEjes: Equatable, Sendable {
    public var t: Double
    public var x: Float, y: Float, z: Float
    public init(t: Double, x: Float, y: Float, z: Float) { self.t = t; self.x = x; self.y = y; self.z = z }
}

/// La grabación de las series en el modo calibración (tanda 4), pura: el reloj le pasa las muestras del acelerómetro y
/// del giroscopio a la frecuencia que den (800 y 200 Hz con `CMBatchedSensorManager`, 100 con `CMMotionManager`) y la
/// grabadora las promedia en una grilla fija de 100 Hz (`hz`), que alcanza de sobra para movimientos de menos de 3 Hz.
/// Guarda los últimos `topeSegundos` (un anillo), así una serie larga o un descanso eterno no llenan la memoria.
///
/// La ventana de una serie va desde que se abre (`abrirVentana`: al empezar, al elegir otro ejercicio o al confirmar la
/// serie anterior) hasta que se confirma (`cerrar`). Incluye el descanso a propósito: el reloj no sabe cuándo arranca
/// la serie (no hay botón de «empiezo») y el contador tiene que encontrarla solo. El conteo mira los últimos
/// `topeConteoSegundos` de la ventana, sin importar el descanso: en la grabación real una serie terminada antes de
/// cerrar el descanso quedaba afuera. El fin del descanso se guarda con la ventana, como dato para la evaluación.
public struct GrabadoraSerie: Sendable {
    public static let hz: Double = 100
    public static let topeSegundos: Double = 300
    public static let topeConteoSegundos: Double = 120
    /// Un tramo sin ninguna muestra de al menos esto (s) es un hueco: la app estuvo suspendida o se cortó la sesión.
    public static let huecoMinimo: Double = 2

    /// La hora (s) del cuadro 0 de la grilla.
    public private(set) var t0: Double?
    /// El índice de la grilla del primer cuadro del anillo.
    public private(set) var primero = 0
    public private(set) var cuadros: [CuadroSensor] = []
    private var acel: [MuestraEjes] = []
    private var giro: [MuestraEjes] = []
    private var ultimoAcel: (Float, Float, Float) = (0, 0, -1)
    private var ultimoGiro: (Float, Float, Float) = (0, 0, 0)
    public private(set) var inicioVentana: Double?
    public private(set) var finDescanso: Double?
    /// El último hueco (horas del sensor). La grilla lo rellena repitiendo el último valor, que parece quietud.
    public private(set) var ultimoHueco: (desde: Double, hasta: Double)?
    private var cuadrosSinMuestra = 0

    public init() {}

    public var capacidad: Int { Int(Self.topeSegundos * Self.hz) }
    /// La hora (s) que corresponde al final de lo grabado.
    public var hasta: Double? { t0.map { $0 + Double(primero + cuadros.count) / Self.hz } }

    // MARK: - Muestras

    public mutating func agregar(acelerometro m: [MuestraEjes]) { acel.append(contentsOf: m); drenar() }
    public mutating func agregar(giroscopio m: [MuestraEjes]) { giro.append(contentsOf: m); drenar() }
    /// Las dos cosas juntas (`CMDeviceMotion`: la misma hora para las dos).
    public mutating func agregar(acelerometro a: [MuestraEjes], giroscopio g: [MuestraEjes]) {
        acel.append(contentsOf: a); giro.append(contentsOf: g); drenar()
    }

    /// Pasa a la grilla lo que ya está completo en los dos sensores: cada cuadro es el promedio de las muestras que caen
    /// en su centésima; si un sensor no tiene ninguna, repite la última (un hueco corto no rompe la señal).
    private mutating func drenar() {
        guard let ta = acel.last?.t, let tg = giro.last?.t else { return }
        if t0 == nil, let a = acel.first?.t, let g = giro.first?.t { t0 = max(a, g) }
        guard let t0 else { return }
        let limite = min(ta, tg)   // hasta acá llegaron los dos
        let fin = Int(((limite - t0) * Self.hz).rounded(.down))   // el cuadro `fin` todavía puede recibir muestras
        var siguiente = primero + cuadros.count
        guard fin > siguiente else { return }
        var ia = 0, ig = 0
        // Lo anterior al cuadro siguiente ya no entra (llegó tarde).
        while ia < acel.count, cuadro(acel[ia].t, t0) < siguiente { ia += 1 }
        while ig < giro.count, cuadro(giro[ig].t, t0) < siguiente { ig += 1 }
        while siguiente < fin {
            var sa = (0.0, 0.0, 0.0), na = 0
            while ia < acel.count, cuadro(acel[ia].t, t0) == siguiente {
                sa.0 += Double(acel[ia].x); sa.1 += Double(acel[ia].y); sa.2 += Double(acel[ia].z); na += 1; ia += 1
            }
            var sg = (0.0, 0.0, 0.0), ng = 0
            while ig < giro.count, cuadro(giro[ig].t, t0) == siguiente {
                sg.0 += Double(giro[ig].x); sg.1 += Double(giro[ig].y); sg.2 += Double(giro[ig].z); ng += 1; ig += 1
            }
            if na == 0 && ng == 0 {
                cuadrosSinMuestra += 1
            } else {
                if Double(cuadrosSinMuestra) >= Self.huecoMinimo * Self.hz {
                    ultimoHueco = (t0 + Double(siguiente - cuadrosSinMuestra) / Self.hz, t0 + Double(siguiente) / Self.hz)
                }
                cuadrosSinMuestra = 0
            }
            if na > 0 { ultimoAcel = (Float(sa.0 / Double(na)), Float(sa.1 / Double(na)), Float(sa.2 / Double(na))) }
            if ng > 0 { ultimoGiro = (Float(sg.0 / Double(ng)), Float(sg.1 / Double(ng)), Float(sg.2 / Double(ng))) }
            cuadros.append(CuadroSensor(ax: ultimoAcel.0, ay: ultimoAcel.1, az: ultimoAcel.2,
                                        gx: ultimoGiro.0, gy: ultimoGiro.1, gz: ultimoGiro.2))
            siguiente += 1
        }
        acel.removeFirst(ia)
        giro.removeFirst(ig)
        // El anillo: se recorta de a bloques (no en cada cuadro).
        if cuadros.count > capacidad + 1_000 {
            let sobra = cuadros.count - capacidad
            cuadros.removeFirst(sobra)
            primero += sobra
        }
    }

    private func cuadro(_ t: Double, _ t0: Double) -> Int { Int(((t - t0) * Self.hz).rounded(.down)) }

    /// El índice de la grilla de una hora.
    public func indice(_ t: Double) -> Int? { t0.map { cuadro(t, $0) } }

    // MARK: - La ventana de la serie

    /// Empieza la ventana de una serie nueva (al empezar, al elegir un ejercicio, al confirmar la anterior).
    public mutating func abrirVentana(en t: Double) {
        inicioVentana = t
        finDescanso = nil
    }

    /// Terminó (o se saltó) el descanso de esta ventana.
    public mutating func marcarFinDescanso(en t: Double) {
        guard inicioVentana != nil else { return }
        finDescanso = t
    }

    /// Lo que se mira para contar: desde la apertura, como mucho los últimos `topeConteoSegundos`, hasta `t`. La misma
    /// regla que usa la evaluación sobre lo exportado.
    public static func inicioConteo(inicioVentana: Double, hasta t: Double) -> Double {
        max(inicioVentana, t - topeConteoSegundos)
    }

    /// Los cuadros entre dos horas (lo que quede en el anillo).
    public func cuadros(desde a: Double, hasta b: Double) -> (inicio: Int, cuadros: [CuadroSensor]) {
        guard let ia = indice(a), let ib = indice(b) else { return (0, []) }
        let desde = max(ia, primero), hasta = min(ib, primero + cuadros.count)
        guard hasta > desde else { return (desde, []) }
        return (desde, Array(cuadros[(desde - primero)..<(hasta - primero)]))
    }

    /// Lo que va de la serie, para el contador en vivo.
    public func paraContar(hasta t: Double) -> [CuadroSensor] {
        guard let iv = inicioVentana else { return [] }
        return cuadros(desde: Self.inicioConteo(inicioVentana: iv, hasta: t), hasta: t).cuadros
    }

    /// El conteo en vivo. Si un hueco cae dentro de la serie o justo al
    /// final, lo que parece «terminó» puede ser que el reloj dejó de ver: no se da por terminada.
    public func contarEnVivo(hasta t: Double) -> ContadorReps.Resultado? {
        guard let iv = inicioVentana else { return nil }
        let (desde, cs) = cuadros(desde: Self.inicioConteo(inicioVentana: iv, hasta: t), hasta: t)
        var r = ContadorReps.contar(cs)
        let cero = (t0 ?? 0) + Double(desde) / Self.hz
        let inicio = cero + r.desde
        if let h = ultimoHueco, r.reps > 0,
           h.desde >= inicio, h.desde <= cero + r.hasta + ContadorReps.esperaFinal(periodo: r.periodo) {
            r.quieto = false
        }
        return r
    }

    /// La ventana grabada de una serie.
    public struct Ventana: Equatable, Sendable {
        public var cuadros: [CuadroSensor]
        /// Desde qué cuadro cuenta el contador (la misma regla en vivo y en la evaluación).
        public var inicioConteo: Int
        /// El cuadro en que terminó el descanso, si terminó dentro de la ventana.
        public var finDescanso: Int?
        /// Segundos que no quedaron en el anillo (la ventana era más larga que `topeSegundos`).
        public var recortado: Double
    }

    /// Cierra la ventana al confirmar la serie: devuelve lo grabado (nil si no hay nada) y deja la ventana cerrada.
    public mutating func cerrar(en t: Double) -> Ventana? {
        guard let iv = inicioVentana else { return nil }
        defer { inicioVentana = nil; finDescanso = nil }
        let (inicio, cs) = cuadros(desde: iv, hasta: t)
        guard !cs.isEmpty, let i0 = indice(iv) else { return nil }
        let ic = indice(Self.inicioConteo(inicioVentana: iv, hasta: t)) ?? inicio
        let fd = finDescanso.flatMap(indice).map { $0 - inicio }
        return Ventana(cuadros: cs, inicioConteo: max(0, ic - inicio), finDescanso: fd.flatMap { $0 >= 0 && $0 <= cs.count ? $0 : nil },
                       recortado: Double(max(0, inicio - max(i0, 0))) / Self.hz)
    }
}
