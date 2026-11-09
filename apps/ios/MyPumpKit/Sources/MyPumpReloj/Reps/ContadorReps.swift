import Foundation

/// El contador de repeticiones del reloj: puro y determinista. El reloj lo corre en vivo sobre lo que va de la serie y
/// la evaluación lo vuelve a correr sobre lo exportado. NUNCA registra nada: lo que cuenta es una propuesta en la corona.
///
/// Se rehízo con la primera grabación real (10 series, 7-nov): en un gimnasio el descanso se mueve tanto como la serie,
/// así que el «tramo de más energía» y la autocorrelación de ese tramo daban calidad de 0,2 a 0,4 y 0 reps. En cambio la
/// serie sí se ve en la gravedad: una postura fija y, sobre ella, un pico parecido por repetición.
///
/// Cómo cuenta:
/// 1. Baja a `hzAnalisis` y filtra la aceleración con un pasa bajo de fase cero (`corteAlto`), SIN sacar la gravedad: un
///    cambio de postura (agarrar el peso, soltarlo) es un salto enorme que corta la serie, y no se disfraza de ciclo.
/// 2. En cada eje y con cada signo busca máximos a varias escalas de prominencia (`picos`).
/// 3. Una serie es una racha de al menos `repsMinimas` picos parecidos: prominencia entre `amplitudBaja` y `amplitudAlta`
///    de la típica, a la misma altura (`nivel`), y separados de `periodoMinimo` a `intervaloMaximo` (hasta `pausasMaximas`
///    pausas de hasta `pausaMaxima`). Una repetición a medias no llega a la prominencia y no cuenta.
/// 4. Las rachas que se pisan en el tiempo son la misma serie: gana la de mejor puntaje. De las series del tramo gana la
///    última que sea comparable a la mejor (`recencia`), porque una aproximación o una caminata pueden venir antes.
/// 5. Las reps son los picos de la racha, y `calidad` dice qué tan parejos fueron (0 a 1).
/// 6. `esfuerzo` es la vibración de la aceleración arriba de 2,5 Hz durante la racha (g): en la grabación real, 0,10 a 0,18
///    en las series (carga en la mano y cable en tensión) y 0,03 a 0,055 en las rachas falsas del descanso. Por debajo de
///    `esfuerzoMinimo` no se propone. Con una sola persona y solo poleas: es un umbral a confirmar con más datos.
/// 7. Tampoco se propone si la racha va al ritmo de los pasos (`ritmoPasosMaximo`: caminar; en lo real, 0,08 a 0,16 en las
///    series) ni si los picos no se separan de la vibración (`relacionMinima`, amplitud / esfuerzo).
public enum ContadorReps {
    public static let hzAnalisis: Double = 25
    public static let corteAlto: Double = 2.0
    /// Segundos entre dos repeticiones. Menos de 1,3 es el braceo de caminar (en la grabación real, 1,0 s).
    public static let periodoMinimo: Double = 1.3
    public static let periodoMaximo: Double = 7.5
    public static let intervaloMaximo: Double = 9
    public static let pausaMaxima: Double = 16
    public static let pausasMaximas = 2
    /// Menos repeticiones que estas no se distinguen de acomodarse o de tomar agua.
    public static let repsMinimas = 5
    public static let calidadMinima: Double = 0.45
    public static let amplitudBaja: Double = 0.6
    public static let amplitudAlta: Double = 1.6
    public static let nivel: Double = 0.4
    public static let recencia: Double = 0.6
    public static let esfuerzoMinimo: Double = 0.075
    public static let ritmoPasosMaximo: Double = 0.3
    /// La prominencia de los picos sobre la vibración. Por debajo los picos pueden ser la vibración misma (máquina con la muñeca quieta).
    public static let relacionMinima: Double = 1.5
    static let corteEsfuerzo: Double = 2.5
    /// La prominencia mínima de un pico (g): por debajo es ruido del sensor, el pulso o la respiración.
    public static let pisoAcel: Double = 0.05
    /// Desde esta prominencia (g) la señal ya alcanza y no suma puntos.
    public static let amplitudPlena: Double = 0.25
    static let pasoEscala: Double = 1.35
    /// La racha más corta (s): cinco picos en menos que esto son un temblor o un gesto.
    static let duracionMinima: Double = 6

    public enum Senal: String, Codable, Sendable { case acel, giro, magnitud, ninguna }

    public struct Resultado: Codable, Equatable, Sendable {
        public var reps: Int
        /// Segundos por repetición (0 si no hubo serie).
        public var periodo: Double
        /// Qué tan parejas fueron (0 a 1), en prominencia y en tiempo.
        public var calidad: Double
        public var senal: Senal
        /// La racha: del primer al último pico, en segundos desde el primer cuadro.
        public var desde: Double
        public var hasta: Double
        /// Después del último pico pasó tiempo suficiente sin otro parecido: la serie terminó.
        public var quieto: Bool
        /// La vibración durante la racha (g). nil en archivos viejos o sin serie.
        public var esfuerzo: Double?
        /// La prominencia típica de los picos (g). nil en archivos viejos o sin serie.
        public var amplitud: Double?
        public init(reps: Int, periodo: Double, calidad: Double, senal: Senal, desde: Double, hasta: Double, quieto: Bool,
                    esfuerzo: Double? = nil, amplitud: Double? = nil) {
            self.reps = reps; self.periodo = periodo; self.calidad = calidad; self.senal = senal
            self.desde = desde; self.hasta = hasta; self.quieto = quieto; self.esfuerzo = esfuerzo; self.amplitud = amplitud
        }
        public static let vacio = Resultado(reps: 0, periodo: 0, calidad: 0, senal: .ninguna, desde: 0, hasta: 0, quieto: false)
    }

    /// Lo que se espera sin un pico nuevo para dar la serie por terminada (s).
    public static func esperaFinal(periodo: Double) -> Double { max(3, 1.3 * periodo) }

    public static func contar(_ cuadros: [CuadroSensor], hz: Double = GrabadoraSerie.hz) -> Resultado {
        let fs = hzAnalisis
        let factor = max(1, Int((hz / fs).rounded()))
        let n = cuadros.count / factor
        guard n >= Int(3 * fs) else { return .vacio }
        var ejes = [[Double]](repeating: [Double](repeating: 0, count: n), count: 3)
        for i in 0..<n {
            var s = (0.0, 0.0, 0.0)
            for j in 0..<factor {
                let c = cuadros[i * factor + j]
                s.0 += Double(c.ax); s.1 += Double(c.ay); s.2 += Double(c.az)
            }
            ejes[0][i] = s.0 / Double(factor); ejes[1][i] = s.1 / Double(factor); ejes[2][i] = s.2 / Double(factor)
        }
        let filtro = Filtro.biquad(true, fs: fs, corte: corteAlto)
        var rachas: [Racha] = []
        for eje in ejes { rachas += buscar(Filtro.filtfilt(filtro, eje, relleno: Int(3 * fs)), fs: fs) }
        guard let (r, e) = elegir(rachas, esfuerzo: { esfuerzoSinCaminar(cuadros, desde: $0.desde, hasta: $0.hasta, hz: hz) }) else { return .vacio }
        let duracion = Double(n) / fs
        return Resultado(reps: r.picos, periodo: r.periodo, calidad: r.calidad, senal: .acel, desde: r.desde, hasta: r.hasta,
                         quieto: duracion - r.hasta >= esperaFinal(periodo: r.periodo), esfuerzo: e, amplitud: r.amplitud)
    }

    /// El desvío de la aceleración total arriba de `corteEsfuerzo` entre dos momentos (s).
    static func esfuerzo(_ cuadros: [CuadroSensor], desde: Double, hasta: Double, hz: Double) -> Double {
        let i = max(0, Int(desde * hz)), j = min(cuadros.count, Int(hasta * hz))
        guard j > i + 10 else { return 0 }
        let m = cuadros[i..<j].map { (Double($0.ax) * Double($0.ax) + Double($0.ay) * Double($0.ay) + Double($0.az) * Double($0.az)).squareRoot() }
        let y = Filtro.filtfilt(Filtro.biquad(false, fs: hz, corte: corteEsfuerzo), m, relleno: Int(hz / 2))
        let media = y.reduce(0, +) / Double(y.count)
        return (y.reduce(0) { $0 + ($1 - media) * ($1 - media) } / Double(y.count)).squareRoot()
    }

    /// El esfuerzo que cuenta para proponer: 0 si la racha va al ritmo de los pasos.
    static func esfuerzoSinCaminar(_ cuadros: [CuadroSensor], desde: Double, hasta: Double, hz: Double) -> Double {
        ritmoDePasos(cuadros, desde: desde, hasta: hasta, hz: hz) >= ritmoPasosMaximo ? 0 : esfuerzo(cuadros, desde: desde, hasta: hasta, hz: hz)
    }

    /// Qué tan periódica es la aceleración total al ritmo de los pasos (0,4 a 0,75 s entre pisadas), de 0 a 1.
    static func ritmoDePasos(_ cuadros: [CuadroSensor], desde: Double, hasta: Double, hz: Double) -> Double {
        let salto = max(1, Int((hz / 50).rounded()))
        let fs = hz / Double(salto)
        let i = max(0, Int(desde * hz)), j = min(cuadros.count, Int(hasta * hz))
        guard j - i > Int(3 * hz) else { return 0 }
        let m = stride(from: i, to: j, by: salto).map { k -> Double in
            let c = cuadros[k]
            return (Double(c.ax) * Double(c.ax) + Double(c.ay) * Double(c.ay) + Double(c.az) * Double(c.az)).squareRoot()
        }
        let y = Filtro.filtfilt(Filtro.biquad(false, fs: fs, corte: 1.3), m, relleno: Int(fs / 2))
        let energia = y.reduce(0) { $0 + $1 * $1 }
        guard energia > 1e-9 else { return 0 }
        var mejor = 0.0
        for l in Int(0.4 * fs)...Int(0.75 * fs) where l < y.count {
            var r = 0.0
            for t in 0..<(y.count - l) { r += y[t] * y[t + l] }
            mejor = max(mejor, r / energia)
        }
        return mejor
    }

    // MARK: - Los picos

    /// Un máximo: su muestra, su altura y su prominencia.
    struct Pico { var i: Int; var v: Double; var prominencia: Double }

    struct Racha {
        var picos: Int
        var desde: Double, hasta: Double
        var amplitud: Double, periodo: Double, calidad: Double
        var puntaje: Double { Double(picos) * calidad * calidad * calidad * min(1, amplitud / ContadorReps.amplitudPlena) }
    }

    /// Los extremos alternados con un retroceso de al menos `d` (los índices de máximos y mínimos, en orden).
    static func extremos(_ x: [Double], retroceso d: Double) -> [Int] {
        var salida: [Int] = []
        var iMin = 0, iMax = 0, direccion = 0
        for i in 1..<x.count {
            if x[i] > x[iMax] { iMax = i }
            if x[i] < x[iMin] { iMin = i }
            if direccion >= 0, x[iMax] - x[i] >= d {
                if direccion == 0, iMin < iMax { salida.append(iMin) }
                salida.append(iMax); direccion = -1; iMin = i
            } else if direccion <= 0, x[i] - x[iMin] >= d {
                if direccion == 0, iMax < iMin { salida.append(iMax) }
                salida.append(iMin); direccion = 1; iMax = i
            }
        }
        return salida
    }

    /// Los máximos de `x` entre sus extremos, con su prominencia (lo que baja hasta el menor de los dos lados).
    static func picos(_ x: [Double], extremos e: [Int]) -> [Pico] {
        var salida: [Pico] = []
        for (j, i) in e.enumerated() {
            let izquierda = j > 0 ? x[e[j - 1]] : nil, derecha = j + 1 < e.count ? x[e[j + 1]] : nil
            if let v = izquierda, v > x[i] { continue }
            if let v = derecha, v > x[i] { continue }
            let lados = [izquierda, derecha].compactMap { $0 }.map { x[i] - $0 }
            if let p = lados.min() { salida.append(Pico(i: i, v: x[i], prominencia: p)) }
        }
        return salida
    }

    /// Todas las rachas de un eje, con los dos signos y a todas las escalas.
    static func buscar(_ x: [Double], fs: Double) -> [Racha] {
        guard let lo = x.min(), let hi = x.max(), hi - lo >= pisoAcel else { return [] }
        var salida: [Racha] = []
        var d = pisoAcel
        let negado = x.map { -$0 }
        while d < (hi - lo) * 0.8 {
            let e = extremos(x, retroceso: d)
            if e.count >= 7, e.count <= 500 {
                salida += rachas(picos(x, extremos: e), fs: fs)
                salida += rachas(picos(negado, extremos: e), fs: fs)
            }
            d *= pasoEscala
        }
        return salida
    }

    /// La mediana «alta» (la del medio; con cantidad par, la de arriba).
    static func mediana(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }

    static func rachas(_ p: [Pico], fs: Double) -> [Racha] {
        var salida: [Racha] = []
        var i = 0
        /// Hasta dónde sigue la racha que arranca en `i`.
        func extender(amplitud a: Double, altura: Double?) -> Int {
            var j = i, pausas = 0
            while j + 1 < p.count {
                let q = p[j + 1], dt = Double(q.i - p[j].i) / fs
                guard q.prominencia >= amplitudBaja * a, q.prominencia <= amplitudAlta * a, dt >= periodoMinimo else { break }
                if dt > intervaloMaximo {
                    guard dt <= pausaMaxima, pausas < pausasMaximas else { break }
                    pausas += 1
                }
                if let altura, abs(q.v - altura) > nivel * a { break }
                j += 1
            }
            return j
        }
        while i + 3 < p.count {
            var j = extender(amplitud: p[i].prominencia, altura: nil)
            if j - i >= 2 {
                let s = p[i...j]
                j = extender(amplitud: mediana(s.map(\.prominencia)), altura: mediana(s.map(\.v)))
            }
            guard j - i + 1 >= repsMinimas else { i += 1; continue }
            let s = Array(p[i...j])
            let a = mediana(s.map(\.prominencia))
            let tiempos = (1..<s.count).map { Double(s[$0].i - s[$0 - 1].i) / fs }
            let c = mediana(tiempos)
            let calidad = max(0, 1 - mediana(s.map { abs($0.prominencia - a) }) / a - mediana(tiempos.map { abs($0 - c) }) / c)
            salida.append(Racha(picos: s.count, desde: Double(s[0].i) / fs, hasta: Double(s[s.count - 1].i) / fs,
                                amplitud: a, periodo: c, calidad: calidad))
            i = j + 1
        }
        return salida
    }

    /// Las rachas que se pisan son la misma serie (gana la de mejor puntaje entre las de duración parecida). Si alguna
    /// serie tiene esfuerzo, las que no lo tienen se descartan. De las que quedan, la última comparable a la mejor.
    static func elegir(_ todas: [Racha], esfuerzo medir: (Racha) -> Double) -> (Racha, Double)? {
        let validas = todas.filter {
            $0.periodo >= periodoMinimo && $0.periodo <= periodoMaximo && $0.calidad >= calidadMinima && $0.hasta - $0.desde >= duracionMinima
        }.sorted { $0.desde < $1.desde }
        var grupos: [(miembros: [Racha], fin: Double)] = []
        for r in validas {
            if let u = grupos.last, r.desde < u.fin - 1 {
                grupos[grupos.count - 1].miembros.append(r)
                grupos[grupos.count - 1].fin = max(u.fin, r.hasta)
            } else {
                grupos.append(([r], r.hasta))
            }
        }
        let mejores: [(Racha, Double)] = grupos.compactMap { g in
            let larga = g.miembros.map { $0.hasta - $0.desde }.max() ?? 0
            guard let r = g.miembros.filter({ $0.hasta - $0.desde >= 0.65 * larga }).max(by: { $0.puntaje < $1.puntaje }) else { return nil }
            return (r, medir(r))
        }
        let conEsfuerzo = mejores.filter { $0.1 >= esfuerzoMinimo && $0.0.amplitud >= relacionMinima * $0.1 }
        let candidatas = conEsfuerzo.isEmpty ? mejores : conEsfuerzo
        guard let tope = candidatas.map(\.0.puntaje).max() else { return nil }
        return candidatas.last { $0.0.puntaje >= recencia * tope }
    }
}

/// Filtros de señal, de fase cero (para el contador).
enum Filtro {
    struct Biquad { var b0, b1, b2, a1, a2: Double }

    /// Butterworth de segundo orden (fórmulas del «Audio EQ Cookbook», Q = 1/√2).
    static func biquad(_ tipo: Bool, fs: Double, corte: Double) -> Biquad {
        let w0 = 2 * Double.pi * corte / fs
        let alfa = sin(w0) / (2 * 0.5.squareRoot())
        let c = cos(w0)
        let a0 = 1 + alfa
        if tipo {   // pasa bajo
            return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alfa) / a0)
        }
        return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alfa) / a0)
    }

    static func aplicar(_ f: Biquad, _ x: [Double]) -> [Double] {
        var y = [Double](repeating: 0, count: x.count)
        var x1 = x.first ?? 0, x2 = x1
        // Arranca en régimen con el primer valor (pasa bajo) o en cero (pasa alto).
        let ganancia = (f.b0 + f.b1 + f.b2) / (1 + f.a1 + f.a2)
        var y1 = (x.first ?? 0) * ganancia, y2 = y1
        for i in x.indices {
            let v = f.b0 * x[i] + f.b1 * x1 + f.b2 * x2 - f.a1 * y1 - f.a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = v
            y[i] = v
        }
        return y
    }

    /// Ida y vuelta (fase cero), con la señal reflejada en los bordes para que el arranque no invente un pico.
    static func filtfilt(_ f: Biquad, _ x: [Double], relleno: Int) -> [Double] {
        guard x.count > 2 else { return x }
        let p = min(relleno, x.count - 1)
        let a = x[0], b = x[x.count - 1]
        let izq = (1...p).reversed().map { 2 * a - x[$0] }
        let der = (1...p).map { 2 * b - x[x.count - 1 - $0] }
        var y = aplicar(f, izq + x + der)
        y = aplicar(f, y.reversed()).reversed()
        return Array(y[p..<(p + x.count)])
    }
}
