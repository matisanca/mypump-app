import Foundation
import MyPumpReloj

/// Señales sintéticas del reloj para probar el contador y la evaluación sin un reloj (tanda 4). Deterministas: misma
/// semilla, mismos números. No es un modelo fino del brazo: alcanza para que haya una serie con su período, su ruido,
/// sus pausas y su repetición a medias, y para que la prueba diga si el contador las encuentra.
public enum SenalSintetica {
    public enum Movimiento: String, Sendable, CaseIterable {
        /// La muñeca gira ~115° por repetición (la gravedad cambia de eje): curl.
        case curl
        /// El reloj sube y baja sin girar (casi solo aceleración vertical, chica): sentadilla con barra.
        case sentadilla
        /// Empuje horizontal: aceleración a lo largo del antebrazo y un poco de giro.
        case press
    }

    /// Una repetición: cuánto dura el ida y vuelta, qué fracción del recorrido hace (1 = completa), cuánto se queda
    /// arriba y cuánto descansa abajo después.
    public struct Rep: Sendable {
        public var duracion: Double
        public var recorrido: Double
        public var arriba: Double
        public var despues: Double
        public init(duracion: Double, recorrido: Double = 1, arriba: Double = 0, despues: Double = 0) {
            self.duracion = duracion; self.recorrido = recorrido; self.arriba = arriba; self.despues = despues
        }
    }

    public struct Caso: Sendable {
        public var nombre: String
        public var movimiento: Movimiento
        public var familia: FamiliaMovimiento
        /// Las reps que un humano cargaría (las completas).
        public var reps: Int
        public var cuadros: [CuadroSensor]
    }

    // MARK: - Los casos de las pruebas

    /// 10 curls limpios de 2,5 s, con 6 s quieto antes y después.
    public static func curlLimpio(semilla: UInt64 = 1) -> Caso {
        var g = Azar(semilla)
        let reps = (0..<10).map { _ in Rep(duracion: 2.5 * g.uniforme(0.92, 1.08)) }
        return Caso(nombre: "curl limpio", movimiento: .curl, familia: .curl, reps: 10,
                    cuadros: serie(.curl, reps: reps, antes: 6, despues: 6, ruidoAcel: 0.02, ruidoGiro: 0.05, semilla: semilla))
    }

    /// 8 sentadillas lentas de ~4,5 s (la última más lenta, por la fatiga), con poco movimiento del reloj.
    public static func sentadillaLenta(semilla: UInt64 = 2) -> Caso {
        var g = Azar(semilla)
        let reps = (0..<8).map { i in Rep(duracion: (4.3 + 0.25 * Double(i)) * g.uniforme(0.95, 1.05)) }
        return Caso(nombre: "sentadilla lenta", movimiento: .sentadilla, familia: .sentadilla, reps: 8,
                    cuadros: serie(.sentadilla, reps: reps, antes: 6, despues: 6, ruidoAcel: 0.01, ruidoGiro: 0.03, semilla: semilla))
    }

    /// Nada de series: 60 s de ruido, deriva lenta y algunos golpes sueltos (acomodarse, tomar la botella).
    public static func soloRuido(semilla: UInt64 = 3) -> Caso {
        Caso(nombre: "ruido", movimiento: .curl, familia: .otra, reps: 0,
             cuadros: serie(.curl, reps: [], antes: 30, despues: 30, ruidoAcel: 0.03, ruidoGiro: 0.08, semilla: semilla, golpes: 6))
    }

    /// 12 presses con un segundo arriba en cada uno y una pausa de 6 s después de la sexta (rest-pause).
    public static func conPausas(semilla: UInt64 = 4) -> Caso {
        var g = Azar(semilla)
        let reps = (0..<12).map { i in Rep(duracion: 2.0 * g.uniforme(0.9, 1.1), arriba: g.uniforme(0.6, 1.2), despues: i == 5 ? 6 : g.uniforme(0, 0.4)) }
        return Caso(nombre: "pausas", movimiento: .press, familia: .empujeHorizontal, reps: 12,
                    cuadros: serie(.press, reps: reps, antes: 5, despues: 5, ruidoAcel: 0.02, ruidoGiro: 0.05, semilla: semilla))
    }

    /// 7 curls y un octavo que queda a un tercio del recorrido (al fallo): se cargan 7.
    public static func serieCortada(semilla: UInt64 = 5) -> Caso {
        var g = Azar(semilla)
        var reps = (0..<7).map { i in Rep(duracion: (2.4 + 0.12 * Double(i)) * g.uniforme(0.95, 1.05)) }
        reps.append(Rep(duracion: 2.6, recorrido: 0.3))
        return Caso(nombre: "serie cortada", movimiento: .curl, familia: .curl, reps: 7,
                    cuadros: serie(.curl, reps: reps, antes: 6, despues: 6, ruidoAcel: 0.02, ruidoGiro: 0.05, semilla: semilla))
    }

    public static var casos: [Caso] { [curlLimpio(), sentadillaLenta(), soloRuido(), conPausas(), serieCortada()] }

    // MARK: - El generador

    /// Arma la serie a `hz`: quieto `antes`, las repeticiones, quieto `despues`. El reloj nunca está del todo quieto:
    /// hay ruido blanco, una deriva lenta de la orientación y, si se piden, golpes sueltos.
    public static func serie(_ m: Movimiento, reps: [Rep], antes: Double, despues: Double, ruidoAcel: Double, ruidoGiro: Double,
                             semilla: UInt64, golpes: Int = 0, hz: Double = GrabadoraSerie.hz) -> [CuadroSensor] {
        var g = Azar(semilla &* 7919 &+ 17)
        // El recorrido (0 a 1) cuadro a cuadro.
        var s: [Double] = Array(repeating: 0, count: Int(antes * hz))
        for r in reps {
            let mitad = Int(r.duracion / 2 * hz)
            for i in 0..<mitad { s.append(r.recorrido * (1 - cos(Double.pi * Double(i) / Double(mitad))) / 2) }
            s += Array(repeating: r.recorrido, count: Int(r.arriba * hz))
            for i in 0..<mitad { s.append(r.recorrido * (1 + cos(Double.pi * Double(i) / Double(mitad))) / 2) }
            s += Array(repeating: 0, count: Int(r.despues * hz))
        }
        s += Array(repeating: 0, count: Int(despues * hz))
        let n = s.count
        // Deriva lenta de la orientación (radianes) y golpes sueltos.
        var deriva = [Double](repeating: 0, count: n)
        var d = 0.0
        for i in 0..<n { d = 0.999 * d + g.normal() * 0.002; deriva[i] = d }
        var golpe = [Double](repeating: 0, count: n)
        for _ in 0..<golpes {
            let c = Int(g.uniforme(0, Double(n))), ancho = g.uniforme(0.15, 0.4) * hz, alto = g.uniforme(0.15, 0.4) * (g.uniforme(0, 1) < 0.5 ? -1 : 1)
            for i in max(0, c - Int(3 * ancho))..<min(n, c + Int(3 * ancho)) { golpe[i] += alto * exp(-pow(Double(i - c) / ancho, 2)) }
        }
        // Ángulo de la muñeca (alrededor de y) y desplazamiento lineal (m) según el movimiento.
        var angulo = [Double](repeating: 0, count: n)
        var desplazamiento = [Double](repeating: 0, count: n)
        for i in 0..<n {
            switch m {
            case .curl: angulo[i] = 2.0 * s[i]
            case .sentadilla: desplazamiento[i] = -0.4 * s[i]; angulo[i] = 0.04 * s[i]
            case .press: desplazamiento[i] = 0.45 * s[i]; angulo[i] = 0.18 * s[i]
            }
            angulo[i] += deriva[i]
        }
        // Segunda derivada del desplazamiento (m/s²) y derivada del ángulo (rad/s).
        func derivada(_ x: [Double]) -> [Double] { (0..<n).map { i in (x[min(n - 1, i + 1)] - x[max(0, i - 1)]) * hz / Double(min(n - 1, i + 1) - max(0, i - 1)) } }
        let aceleracion = derivada(derivada(desplazamiento))
        let giro = derivada(angulo)
        // La gravedad en el reloj quieto (algo inclinado) y el eje del movimiento lineal.
        let base = normalizar((0.25, -0.15, -0.95))
        let ejeLineal: (Double, Double, Double) = m == .press ? (1, 0, 0) : (-base.0, -base.1, -base.2)
        var cuadros: [CuadroSensor] = []
        cuadros.reserveCapacity(n)
        for i in 0..<n {
            let (c, sn) = (cos(angulo[i]), sin(angulo[i]))
            // La gravedad rotada alrededor de y por el ángulo de la muñeca.
            let gx = c * base.0 + sn * base.2, gy = base.1, gz = -sn * base.0 + c * base.2
            let lineal = aceleracion[i] / 9.81
            let ax = gx + lineal * ejeLineal.0 + g.normal() * ruidoAcel + golpe[i]
            let ay = gy + lineal * ejeLineal.1 + g.normal() * ruidoAcel + 0.5 * golpe[i]
            let az = gz + lineal * ejeLineal.2 + g.normal() * ruidoAcel
            cuadros.append(CuadroSensor(ax: Float(ax), ay: Float(ay), az: Float(az),
                                        gx: Float(g.normal() * ruidoGiro + 3 * golpe[i]), gy: Float(giro[i] + g.normal() * ruidoGiro),
                                        gz: Float(g.normal() * ruidoGiro)))
        }
        return cuadros
    }

    static func normalizar(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
        let n = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
        return (v.0 / n, v.1 / n, v.2 / n)
    }
}

/// SplitMix64 con normales por Box-Muller: el mismo resultado en cualquier máquina.
public struct Azar: Sendable {
    private var estado: UInt64
    public init(_ semilla: UInt64) { estado = semilla &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func siguiente() -> UInt64 {
        estado &+= 0x9E37_79B9_7F4A_7C15
        var z = estado
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func uniforme(_ a: Double, _ b: Double) -> Double { a + (b - a) * Double(siguiente() >> 11) / Double(1 << 53) }
    public mutating func normal() -> Double {
        let u = max(1e-12, uniforme(0, 1)), v = uniforme(0, 1)
        return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
    }
}
