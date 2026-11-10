import Foundation
import MyPumpReloj

/// Una serie de gimnasio de punta a punta, SINTÉTICA: el descanso con sus caminatas y el celular, agarrar el peso, la
/// serie, dejar el peso, mirar el reloj y confirmar. Sirve para probar el camino entero (grabadora, ventana, contador y
/// propuesta) con cuadros inyectados, porque el simulador no tiene sensores. NO es una medición real: los movimientos
/// salen de un modelo del brazo, y un número de acá no dice cuánto acierta el reloj en una muñeca de verdad.
public enum EscenarioGimnasio {
    /// Cómo se mueve la muñeca en cada familia: el giro por repetición (rad), el recorrido lineal (m) y si es a lo largo
    /// del antebrazo o vertical, y cuánto dura una repetición típica (s).
    public struct Perfil: Sendable {
        public var angulo: Double
        public var desplazamiento: Double
        public var alAntebrazo: Bool
        public var duracion: Double
        public init(angulo: Double, desplazamiento: Double, alAntebrazo: Bool, duracion: Double) {
            self.angulo = angulo; self.desplazamiento = desplazamiento; self.alAntebrazo = alAntebrazo; self.duracion = duracion
        }
    }

    public static func perfil(_ f: FamiliaMovimiento) -> Perfil {
        switch f {
        case .empujeHorizontal: Perfil(angulo: 0.15, desplazamiento: 0.40, alAntebrazo: true, duracion: 2.8)
        case .empujeVertical: Perfil(angulo: 0.35, desplazamiento: 0.40, alAntebrazo: true, duracion: 2.8)
        case .tironHorizontal: Perfil(angulo: 0.50, desplazamiento: 0.35, alAntebrazo: true, duracion: 2.8)
        case .tironVertical: Perfil(angulo: 0.60, desplazamiento: 0.45, alAntebrazo: false, duracion: 3.0)
        case .curl: Perfil(angulo: 2.00, desplazamiento: 0, alAntebrazo: false, duracion: 2.8)
        case .extensionCodo: Perfil(angulo: 1.50, desplazamiento: 0, alAntebrazo: false, duracion: 2.6)
        case .sentadilla: Perfil(angulo: 0.05, desplazamiento: 0.40, alAntebrazo: false, duracion: 3.8)
        case .bisagra: Perfil(angulo: 0.20, desplazamiento: 0.35, alAntebrazo: false, duracion: 3.5)
        case .zancada: Perfil(angulo: 0.10, desplazamiento: 0.35, alAntebrazo: false, duracion: 3.5)
        case .elevacionLateral: Perfil(angulo: 1.30, desplazamiento: 0, alAntebrazo: false, duracion: 2.8)
        case .aperturaPectoral: Perfil(angulo: 1.10, desplazamiento: 0.10, alAntebrazo: false, duracion: 3.0)
        case .encogimiento: Perfil(angulo: 0.04, desplazamiento: 0.07, alAntebrazo: false, duracion: 2.6)
        case .gemelo: Perfil(angulo: 0.03, desplazamiento: 0.08, alAntebrazo: false, duracion: 2.6)
        case .core: Perfil(angulo: 0.50, desplazamiento: 0.20, alAntebrazo: false, duracion: 3.0)
        // Las manos agarradas a la máquina: casi nada llega a la muñeca (lo que se mueve es el cuerpo al empujar).
        case .maquinaMunecaQuieta: Perfil(angulo: 0.06, desplazamiento: 0.02, alAntebrazo: false, duracion: 3.4)
        case .otra: Perfil(angulo: 0.60, desplazamiento: 0.15, alAntebrazo: false, duracion: 3.0)
        }
    }

    public enum Caso: String, Sendable, CaseIterable {
        case normal
        /// Al fallo: la velocidad cae fuerte (hasta triple) y la última queda a medias.
        case lentaAlFallo
        /// Pausa de 6 a 9 s a mitad de serie (rest-pause).
        case pausaMedia
        /// Baja el peso y sigue a los 12 s: las dos partes son la misma serie.
        case drop
        /// Arranca 25 s antes de que termine el descanso.
        case arrancaEnDescanso
        /// Máquina con la muñeca del todo quieta: la señal no se distingue del ruido.
        case munecaInmovil
        /// No hizo ninguna serie: descanso, caminatas y celular, y confirma.
        case sinSerie
        /// Sin serie: carga discos en la barra (levantadas con carga, sin ritmo parejo).
        case cargaDiscos
        /// Sin serie: estira los hombros en ciclos parejos y sin carga.
        case estira
        /// Sin serie: camina despacio, con los pasos más largos que el mínimo de una repetición.
        case caminaLento
        /// Hace una aproximación liviana en pleno descanso y después la serie de verdad.
        case aproximacion
    }

    public struct Linea: Sendable {
        public var cuadros: [CuadroSensor]
        public var familia: FamiliaMovimiento
        /// Las reps completas que hizo (0 = no hizo ninguna serie).
        public var reps: Int
        public var inicioSerie: Double
        public var finSerie: Double
        public var finDescanso: Double
        public var confirma: Double
    }

    private static let hz = GrabadoraSerie.hz

    // MARK: - El armado

    /// Las corridas sin serie: lo que se proponga en ellas es inventado.
    public static let casosSinSerie: [Caso] = [.sinSerie, .cargaDiscos, .estira, .caminaLento]

    /// Otra persona y otro reloj para los datos de validación: otra orientación de la muñeca, otro recorrido, otro tempo,
    /// otra vibración y un poco de movimiento fino en el descanso. Con `otroCuerpo == nil` no cambia nada.
    struct OtroCuerpo {
        var base: (x: Double, y: Double, z: Double)
        var recorrido: Double, tempo: Double, subida: Double, vibracion: Double, finoDescanso: Double
        init(_ r: inout Azar) {
            let (a, b) = (r.uniforme(-.pi, .pi), r.uniforme(-0.9, 0.9))
            base = (cos(a) * cos(b), sin(a) * cos(b), sin(b))
            recorrido = r.uniforme(0.7, 1.3); tempo = r.uniforme(0.75, 1.4); subida = r.uniforme(0.3, 0.6)
            vibracion = r.uniforme(0.07, 0.20); finoDescanso = r.uniforme(0.015, 0.05)
        }
    }

    /// `otroCuerpo`: los datos de validación, con un modelo que el contador no vio al ajustarse.
    public static func armar(_ familia: FamiliaMovimiento, caso: Caso = .normal, reps pedidas: Int = 10, semilla: UInt64, otroCuerpo: Bool = false) -> Linea {
        let indiceFamilia = UInt64(FamiliaMovimiento.allCases.firstIndex(of: familia) ?? 0)
        var g = Azar(semilla &* 104_729 &+ (otroCuerpo ? 1_000 &+ indiceFamilia : UInt64(familia.rawValue.count)))
        var azarCuerpo = Azar(semilla &* 7_919 &+ 13 &+ indiceFamilia)
        let cuerpo = otroCuerpo ? OtroCuerpo(&azarCuerpo) : nil
        var p = perfil(familia)
        if let cuerpo {
            p.angulo *= cuerpo.recorrido; p.desplazamiento *= cuerpo.recorrido; p.duracion *= cuerpo.tempo
        }
        let fraccionSubida = cuerpo?.subida ?? 0.4
        let sinSerie = casosSinSerie.contains(caso)
        let descanso = g.uniforme(70, 130)
        let total = descanso + (otroCuerpo ? 260 : 120)
        let n = Int(total * hz)
        var angulo = [Double](repeating: 0, count: n)      // alrededor de y
        var alabeo = [Double](repeating: 0, count: n)      // alrededor de x
        var lineal = [Double](repeating: 0, count: n)
        var impactos = [Double](repeating: 0, count: n)    // g, de pisar al caminar

        // Un cambio de postura suave de `a` rad que queda (o vuelve, con `vuelve`).
        func gesto(_ x: inout [Double], en t: Double, dura: Double, a: Double, vuelve: Bool = false) {
            let i0 = max(0, Int(t * hz)), m = max(1, Int(dura * hz))
            guard i0 < n else { return }
            for i in i0..<n {
                let u = Double(i - i0) / Double(m)
                if u >= 1 {
                    if !vuelve { x[i] += a } else { break }
                } else {
                    x[i] += vuelve ? a * sin(.pi * u) : a * (1 - cos(.pi * u)) / 2
                }
            }
        }

        // Caminar: el brazo pendula, una vuelta por paso doble, y cada pisada golpea.
        func caminar(desde t: Double, dura: Double, periodo fijo: Double? = nil) {
            let periodo = fijo ?? g.uniforme(1.0, 1.25), amp = g.uniforme(0.25, 0.45)
            let i0 = Int(t * hz), i1 = min(n, Int((t + dura) * hz))
            guard i1 > i0 else { return }
            for i in i0..<i1 {
                let u = Double(i - i0) / hz
                let envolvente = min(1, min(u, Double(i1 - i) / hz))
                alabeo[i] += envolvente * amp * sin(2 * .pi * u / periodo)
                let fase = (u / (periodo / 2)).truncatingRemainder(dividingBy: 1)
                impactos[i] += envolvente * 0.3 * exp(-pow((fase - 0.1) / 0.05, 2))
            }
        }

        // El descanso: caminatas, el celular y tomar agua.
        var t = g.uniforme(3, 10)
        while t < descanso - 12 {
            switch g.uniforme(0, 1) {
            case ..<0.35:
                let d = g.uniforme(5, 18)
                caminar(desde: t, dura: d)
                t += d
            case ..<0.7:
                // El celular en la mano: toquecitos sin ritmo.
                let fin = t + g.uniforme(10, 25)
                while t < fin {
                    gesto(&angulo, en: t, dura: g.uniforme(0.3, 0.9), a: g.uniforme(-0.25, 0.25), vuelve: true)
                    t += g.uniforme(0.8, 4)
                }
            default:
                // Tomar agua: sube y baja el brazo.
                let a = g.uniforme(1.0, 1.6)
                gesto(&angulo, en: t, dura: 1.2, a: a)
                gesto(&angulo, en: t + g.uniforme(3, 6), dura: 1.2, a: -a)
                t += 8
            }
            t += g.uniforme(2, 12)
        }

        // Vibración extra: lo que levanta con carga fuera de la serie.
        var cargas: [(rango: Range<Int>, g: Double)] = []
        func marcarCarga(_ a: Double, _ b: Double, _ v: Double) {
            let i0 = max(0, min(n, Int(a * hz))), i1 = max(i0, min(n, Int(b * hz)))
            cargas.append((i0..<i1, v))
        }
        // Una serie de reps cosenoidales que se suma a la señal (la aproximación del descanso y los estiramientos).
        func tanda(desde t0: Double, reps m: Int, duracion: Double, a: Double, d: Double) -> Double {
            var u = t0
            for _ in 0..<m {
                let dur = duracion * g.uniforme(0.92, 1.08)
                let i0 = Int(u * hz), i1 = Int((u + dur) * hz)
                guard i1 < n else { break }
                for i in i0..<i1 {
                    let s = (1 - cos(2 * .pi * Double(i - i0) / Double(i1 - i0))) / 2
                    angulo[i] += a * s; lineal[i] += d * s
                }
                u += dur + g.uniforme(0, 0.3)
            }
            return u
        }

        if caso == .aproximacion {
            // A mitad del descanso: pocas reps, con poco peso, y sigue descansando.
            let d0 = max(8, descanso * g.uniforme(0.25, 0.45))
            let fin = tanda(desde: d0, reps: Int(g.uniforme(6, 9)), duracion: p.duracion * 0.85, a: p.angulo * 0.9, d: p.desplazamiento * 0.9)
            marcarCarga(d0, fin, g.uniforme(0.08, 0.13))
        }

        // La serie.
        var inicio = descanso + g.uniforme(4, 12)
        if caso == .arrancaEnDescanso { inicio = descanso - 25 }
        var cuantas = pedidas
        var finSerie = inicio
        if !sinSerie {
            // Agarrar el peso, acomodarse.
            gesto(&angulo, en: max(0, inicio - 4), dura: 1.3, a: g.uniforme(-0.9, 0.9))
            gesto(&alabeo, en: max(0, inicio - 2.5), dura: 0.9, a: g.uniforme(-0.5, 0.5))
            if caso == .normal, g.uniforme(0, 1) < 0.5 { caminar(desde: max(0, inicio - 14), dura: 8) }
            var filas: [(dur: Double, rec: Double, despues: Double)] = []
            for i in 0..<pedidas {
                var d = p.duracion * g.uniforme(0.88, 1.12)
                var despues = g.uniforme(0, 0.35)
                if caso == .lentaAlFallo { d *= 1 + 2.0 * pow(Double(i) / Double(max(1, pedidas - 1)), 2) }
                if caso == .pausaMedia, i == pedidas / 2 - 1 { despues = g.uniforme(6, 9) }
                if caso == .drop, i == pedidas / 2 - 1 { despues = 12 }
                filas.append((d, g.uniforme(0.85, 1.12) * (caso == .lentaAlFallo ? 1 - 0.2 * Double(i) / Double(pedidas) : 1), despues))
            }
            if caso == .lentaAlFallo { filas.append((p.duracion * 2.5, 0.3, 0)) }
            let escala = caso == .munecaInmovil ? 0.08 : 1.0
            var u = inicio
            for f in filas {
                let up = f.dur * fraccionSubida, down = f.dur * (1 - fraccionSubida)
                let i0 = Int(u * hz), i1 = Int((u + up) * hz), i2 = Int((u + up + down) * hz)
                guard i2 < n else { break }
                for i in i0..<i1 {
                    let s = f.rec * (1 - cos(.pi * Double(i - i0) / Double(i1 - i0))) / 2
                    angulo[i] += escala * p.angulo * s
                    lineal[i] += escala * p.desplazamiento * s
                }
                for i in i1..<i2 {
                    let s = f.rec * (1 + cos(.pi * Double(i - i1) / Double(i2 - i1))) / 2
                    angulo[i] += escala * p.angulo * s
                    lineal[i] += escala * p.desplazamiento * s
                }
                u += f.dur + f.despues
                finSerie = u
            }
            cuantas = pedidas
            // Dejar el peso y soltar los brazos.
            gesto(&angulo, en: finSerie + g.uniforme(0.5, 1.5), dura: 1.2, a: g.uniforme(-1.0, 1.0))
            gesto(&alabeo, en: finSerie + g.uniforme(1.5, 3), dura: 0.9, a: g.uniforme(-0.6, 0.6))
        } else {
            cuantas = 0
            switch caso {
            case .cargaDiscos:
                // Levanta discos: gestos con carga, a destiempo.
                var u = descanso + 3
                for _ in 0..<Int(g.uniforme(4, 9)) {
                    let d = g.uniforme(1.0, 2.2), a = g.uniforme(-1.1, 1.1)
                    gesto(&angulo, en: u, dura: d, a: a, vuelve: true)
                    gesto(&alabeo, en: u + 0.2, dura: d * 0.7, a: g.uniforme(-0.5, 0.5), vuelve: true)
                    marcarCarga(u, u + d, g.uniforme(0.09, 0.17))
                    u += d + g.uniforme(1.5, 7)
                }
                finSerie = u
            case .estira:
                let fin = tanda(desde: descanso + 4, reps: Int(g.uniforme(6, 13)), duracion: g.uniforme(2.0, 4.5), a: g.uniforme(0.8, 1.6), d: 0)
                finSerie = fin
            case .caminaLento:
                caminar(desde: descanso + 5, dura: 25, periodo: g.uniforme(1.35, 1.7))
                finSerie = descanso + 32
            default:
                caminar(desde: descanso + 5, dura: 20)
                finSerie = descanso + 30
            }
        }
        // Mira el reloj y confirma.
        let confirma = min(total - 1, finSerie + g.uniforme(10, 28))
        gesto(&angulo, en: confirma - g.uniforme(4, 8), dura: 0.9, a: 1.1)
        if g.uniforme(0, 1) < 0.4 { caminar(desde: finSerie + 4, dura: max(1, confirma - finSerie - 10)) }

        // La física: gravedad rotada, aceleración lineal y ruido del sensor (y el temblor cuando hay carga).
        var ruido = Azar(semilla &+ 31)
        var deriva = 0.0
        let base = cuerpo?.base ?? (x: 0.25, y: -0.15, z: -0.95)
        let norma = (base.x * base.x + base.y * base.y + base.z * base.z).squareRoot()
        let (b0, b1, b2) = (base.x / norma, base.y / norma, base.z / norma)
        func derivada(_ x: [Double]) -> [Double] {
            (0..<n).map { i in let a = max(0, i - 1), b = min(n - 1, i + 1); return (x[b] - x[a]) * hz / Double(b - a) }
        }
        let giroY = derivada(angulo), giroX = derivada(alabeo)
        let acel = derivada(derivada(lineal))
        var cuadros: [CuadroSensor] = []
        cuadros.reserveCapacity(n)
        let enSerie = Int(inicio * hz)..<max(Int(inicio * hz) + 1, Int(finSerie * hz))
        let sorteo = Double(ruido.siguiente() >> 11) / Double(1 << 53)
        let vibracion = cuerpo?.vibracion ?? (0.10 + 0.08 * sorteo)
        var cargaPorCuadro = [Double](repeating: cuerpo?.finoDescanso ?? 0, count: n)
        for c in cargas { for i in c.rango { cargaPorCuadro[i] = c.g } }
        for i in 0..<n {
            deriva = 0.9995 * deriva + ruido.normal() * 0.0012
            let (c, s) = (cos(angulo[i] + deriva), sin(angulo[i] + deriva))
            let (ca, sa) = (cos(alabeo[i]), sin(alabeo[i]))
            let gx = c * b0 + s * b2, gy0 = b1, gz0 = -s * b0 + c * b2
            let gy = ca * gy0 - sa * gz0, gz = sa * gy0 + ca * gz0
            let extra = acel[i] / 9.81
            // La vibración de hacer fuerza: en la grabación real, 0,10 a 0,18 g de desvío en la aceleración total.
            let v = (!sinSerie || caso == .sinSerie) && enSerie.contains(i) ? vibracion : cargaPorCuadro[i]
            let (tx, ty, tz) = v > 0 ? (ruido.normal() * v, ruido.normal() * v, ruido.normal() * v) : (0, 0, 0)
            let (lx, lz): (Double, Double) = p.alAntebrazo ? (extra, 0) : (-b0 * extra, -b2 * extra)
            cuadros.append(CuadroSensor(
                ax: Float(gx + lx + tx + ruido.normal() * 0.004),
                ay: Float(gy + (p.alAntebrazo ? 0 : -b1 * extra) + ty + ruido.normal() * 0.004),
                az: Float(gz + lz + impactos[i] + tz + ruido.normal() * 0.004),
                gx: Float(giroX[i] + ruido.normal() * 0.015),
                gy: Float(giroY[i] + ruido.normal() * 0.015),
                gz: Float(ruido.normal() * 0.015)))
        }
        return Linea(cuadros: cuadros, familia: familia, reps: cuantas, inicioSerie: inicio, finSerie: finSerie,
                     finDescanso: descanso, confirma: confirma)
    }
}

// MARK: - La corrida en vivo

extension EscenarioGimnasio {
    /// Qué le pasa a los sensores durante la corrida.
    public enum Sensores: String, Sendable, CaseIterable {
        /// Muestras cada cuarto de segundo y conteo cada segundo.
        case vivo
        /// Muñeca baja o pantalla apagada con la sesión de entreno: las muestras llegan en lotes de 1 s y el conteo corre igual.
        case munecaBaja
        /// Sin sesión de entreno, el sistema suspende la app desde el comienzo de la serie hasta que mira el reloj.
        case suspendida
        /// La sesión se corta a mitad de serie y vuelve al rato.
        case sesionCortada
        /// Sin ninguna muestra (permiso negado o sensor apagado).
        case sinMuestras
    }

    public struct Vivo: Sendable {
        /// Lo que quedó propuesto en la corona al confirmar (nil = no propuso nada).
        public var propuesta: Int?
        /// Segundos desde el fin de la serie hasta la propuesta (nil = no propuso).
        public var demora: Double?
        /// Propuso algo durante el descanso, antes de la serie.
        public var propusoAntes: Bool
        /// Lo último que contó en vivo.
        public var ultimoConteo: ContadorReps.Resultado?
    }

    /// Corre la serie como en el reloj: grabadora, ventana desde la confirmación anterior, conteo cada segundo y propuesta.
    /// `proponer` es el paso de la app: recibe si sigue el descanso y el conteo; devuelve las reps si propone.
    public static func enVivo(_ l: Linea, sensores: Sensores = .vivo, tick: Double = 1,
                              proponer: (_ enDescanso: Bool, _ conteo: ContadorReps.Resultado) -> Int?) -> Vivo {
        var g = GrabadoraSerie()
        let base = 5_000.0      // las horas del reloj no arrancan en 0
        g.abrirVentana(en: base)
        let lote = sensores == .munecaBaja ? 1.0 : 0.25
        let porLote = Int(lote * hz)
        var i = 0
        var proximoTick = tick
        var finMarcado = false
        var salida = Vivo(propuesta: nil, demora: nil, propusoAntes: false, ultimoConteo: nil)
        let tope = min(l.cuadros.count, Int(l.confirma * hz))
        while i < tope {
            let j = min(tope, i + porLote)
            let tLote = Double(j) / hz
            let (a, b) = (Double(i) / hz, tLote)
            let corte: Bool
            switch sensores {
            case .vivo, .munecaBaja: corte = false
            case .suspendida: corte = a >= l.inicioSerie && b <= max(l.inicioSerie + 1, l.confirma - 5)
            case .sesionCortada: corte = a >= (l.inicioSerie + l.finSerie) / 2 && b <= (l.inicioSerie + l.finSerie) / 2 + 10
            case .sinMuestras: corte = true
            }
            if !corte {
                var ac: [MuestraEjes] = [], gi: [MuestraEjes] = []
                ac.reserveCapacity(j - i); gi.reserveCapacity(j - i)
                for k in i..<j {
                    let c = l.cuadros[k], ts = base + (Double(k) + 0.5) / hz
                    ac.append(MuestraEjes(t: ts, x: c.ax, y: c.ay, z: c.az))
                    gi.append(MuestraEjes(t: ts, x: c.gx, y: c.gy, z: c.gz))
                }
                g.agregar(acelerometro: ac, giroscopio: gi)
            }
            i = j
            if !finMarcado, tLote >= l.finDescanso { g.marcarFinDescanso(en: base + l.finDescanso); finMarcado = true }
            let suspendido = sensores == .suspendida && corte
            while proximoTick <= tLote {
                defer { proximoTick += tick }
                guard !suspendido else { continue }
                guard let conteo = g.contarEnVivo(hasta: base + proximoTick) else { continue }
                salida.ultimoConteo = conteo
                if let n = proponer(proximoTick < l.finDescanso, conteo) {
                    if proximoTick < l.inicioSerie { salida.propusoAntes = true }
                    salida.propuesta = n
                    salida.demora = proximoTick - l.finSerie
                }
            }
        }
        return salida
    }

    /// El resumen de un grupo de corridas.
    public struct Marcador: Sendable {
        public var corridas = 0, propuestas = 0, exactas = 0, dentroDeUno = 0, conError = 0
        /// Propuestas cuando no había serie o antes de la serie.
        public var falsas = 0
        public var demoras: [Double] = []
        public init() {}
        public mutating func sumar(reales: Int, _ v: Vivo) {
            corridas += 1
            // Una corrida con un número inventado cuenta una sola vez, aunque el número haya cambiado.
            if v.propusoAntes || (reales == 0 && v.propuesta != nil) { falsas += 1 }
            guard let p = v.propuesta else { return }
            guard reales > 0 else { return }
            propuestas += 1
            if p == reales { exactas += 1 }
            if abs(p - reales) <= 1 { dentroDeUno += 1 } else { conError += 1 }
            if let d = v.demora { demoras.append(d) }
        }
        public var cobertura: Double { corridas == 0 ? 0 : Double(propuestas) / Double(corridas) }
        public var precision: Double { propuestas == 0 ? 0 : Double(dentroDeUno) / Double(propuestas) }
        public var texto: String {
            let dem = demoras.sorted()
            let mediana = dem.isEmpty ? "—" : String(format: "%.1f s", dem[dem.count / 2])
            return "\(corridas) corridas · propuso \(propuestas) (\(String(format: "%.0f", cobertura * 100)) %) · exactas \(exactas) · ±1 \(dentroDeUno) (\(String(format: "%.0f", precision * 100)) % de las propuestas) · erradas \(conError) · falsas \(falsas) · demora \(mediana)"
        }
    }
}
