import Foundation

/// El contador experimental de repeticiones (tanda 4): picos más autocorrelación sobre la señal del reloj. Es puro y
/// determinista: el reloj lo corre en vivo sobre lo que va de la serie («Conté N») y la evaluación lo vuelve a correr
/// sobre lo exportado. NUNCA cambia las reps cargadas: en el modo calibración solo se muestra y se guarda al lado.
///
/// Cómo cuenta:
/// 1. Baja la señal a `hzAnalisis` (promedio por bloques, que además filtra el ruido).
/// 2. Filtra cada eje con un pasabanda de fase cero (pasa alto `corteBajo`, pasa bajo `corteAlto`; biquads Butterworth
///    ida y vuelta): queda el movimiento de las repeticiones, sin la gravedad quieta ni el temblor.
/// 3. Arma tres candidatas: el eje dominante de la aceleración (componente principal), el eje dominante del giro y la
///    magnitud de la aceleración. El eje dominante sigue al movimiento aunque el reloj esté rotado en la muñeca.
/// 4. En cada candidata busca el tramo activo (energía por ventanas de `ventanaEnergia` sobre un umbral relativo al
///    máximo y a un piso de ruido; huecos de hasta `huecoMaximo` se unen, así una pausa a mitad de serie no la corta) y
///    en ese tramo la autocorrelación da el período de una repetición (de `periodoMinimo` a `periodoMaximo`; si un
///    submúltiplo explica casi igual, gana el más corto, para no contar de a dos).
/// 5. Gana la candidata más periódica. Si ninguna pasa `calidadMinima`, no hay serie: 0.
/// 6. Cuenta los ciclos completos del tramo con histéresis (`contarCiclos`): cada repetición es un ida y vuelta que
///    cruza los dos umbrales; una repetición a medias no los cruza. La autocorrelación decide si hay serie y con qué
///    señal; los cruces, cuántas repeticiones.
public enum ContadorReps {
    public static let hzAnalisis: Double = 25
    public static let corteBajo: Double = 0.1
    public static let corteAlto: Double = 2.0
    public static let periodoMinimo: Double = 0.6
    public static let periodoMaximo: Double = 7
    public static let ventanaEnergia: Double = 2
    public static let huecoMaximo: Double = 8
    public static let calidadMinima: Double = 0.5
    /// El umbral de los cruces, como fracción de la amplitud típica.
    public static let histeresis: Double = 0.5
    /// El piso de ruido (RMS después del filtro) para la aceleración en g y para el giro en rad/s.
    public static let pisoAcel: Double = 0.006
    public static let pisoGiro: Double = 0.06

    public enum Senal: String, Codable, Sendable { case acel, giro, magnitud, ninguna }

    public struct Resultado: Codable, Equatable, Sendable {
        public var reps: Int
        /// Segundos por repetición (0 si no hubo serie).
        public var periodo: Double
        /// La autocorrelación en el período (0 a 1): qué tan pareja fue.
        public var calidad: Double
        public var senal: Senal
        /// El tramo activo, en segundos desde el primer cuadro.
        public var desde: Double
        public var hasta: Double
        /// Después del tramo activo hay al menos un par de períodos quietos: la serie terminó.
        public var quieto: Bool
        public init(reps: Int, periodo: Double, calidad: Double, senal: Senal, desde: Double, hasta: Double, quieto: Bool) {
            self.reps = reps; self.periodo = periodo; self.calidad = calidad; self.senal = senal
            self.desde = desde; self.hasta = hasta; self.quieto = quieto
        }
        public static let vacio = Resultado(reps: 0, periodo: 0, calidad: 0, senal: .ninguna, desde: 0, hasta: 0, quieto: false)
    }

    public static func contar(_ cuadros: [CuadroSensor], hz: Double = GrabadoraSerie.hz) -> Resultado {
        let fs = hzAnalisis
        let factor = max(1, Int((hz / fs).rounded()))
        let n = cuadros.count / factor
        guard n >= Int(3 * fs) else { return .vacio }
        var canales = [[Double]](repeating: [Double](repeating: 0, count: n), count: 6)
        var magnitud = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var s = [Double](repeating: 0, count: 6)
            var m = 0.0
            for j in 0..<factor {
                let c = cuadros[i * factor + j]
                s[0] += Double(c.ax); s[1] += Double(c.ay); s[2] += Double(c.az)
                s[3] += Double(c.gx); s[4] += Double(c.gy); s[5] += Double(c.gz)
                m += (Double(c.ax) * Double(c.ax) + Double(c.ay) * Double(c.ay) + Double(c.az) * Double(c.az)).squareRoot()
            }
            for k in 0..<6 { canales[k][i] = s[k] / Double(factor) }
            magnitud[i] = m / Double(factor)
        }
        let filtrados = canales.map { Filtro.pasabanda($0, fs: fs, bajo: corteBajo, alto: corteAlto) }
        let candidatas: [(Senal, [Double], Double, Double)] = [
            (.acel, Filtro.componentePrincipal(Array(filtrados[0..<3])), pisoAcel, 1.0),
            (.giro, Filtro.componentePrincipal(Array(filtrados[3..<6])), pisoGiro, 1.0),
            (.magnitud, Filtro.pasabanda(magnitud, fs: fs, bajo: corteBajo, alto: corteAlto), pisoAcel, 0.9),
        ]
        var mejor: (Senal, [Double], Tramo, Double, Double)?   // señal, datos, tramo, período (muestras), calidad
        var mejorPuntaje = 0.0
        for (senal, x, piso, peso) in candidatas {
            guard let tramo = tramoActivo(x, fs: fs, piso: piso) else { continue }
            guard let (lag, q) = periodo(Array(x[tramo.desde..<tramo.hasta]), fs: fs) else { continue }
            if q * peso > mejorPuntaje { mejorPuntaje = q * peso; mejor = (senal, x, tramo, lag, q) }
        }
        guard let (senal, x, tramo, lag, q) = mejor, q >= calidadMinima else {
            return Resultado(reps: 0, periodo: 0, calidad: mejor?.4 ?? 0, senal: .ninguna, desde: 0, hasta: 0, quieto: false)
        }
        let reps = contarCiclos(Array(x[tramo.desde..<tramo.hasta]), periodo: lag)
        let finQuieto = Double(n - tramo.hasta) / fs
        return Resultado(reps: reps, periodo: lag / fs, calidad: q, senal: senal, desde: Double(tramo.desde) / fs,
                         hasta: Double(tramo.hasta) / fs, quieto: finQuieto >= max(2.5, lag / fs))
    }

    // MARK: - El tramo activo

    struct Tramo { var desde: Int; var hasta: Int }

    /// El tramo con movimiento: RMS por ventanas sobre el umbral (un 25 % del máximo, y más que el piso de ruido),
    /// uniendo huecos cortos, y de todos el de más energía. Se le suma medio segundo de cada lado.
    static func tramoActivo(_ x: [Double], fs: Double, piso: Double) -> Tramo? {
        let n = x.count
        let w = max(1, Int(ventanaEnergia * fs))
        var acumulado = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { acumulado[i + 1] = acumulado[i] + x[i] * x[i] }
        var rms = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = max(0, i - w / 2), b = min(n, i + w / 2 + 1)
            rms[i] = ((acumulado[b] - acumulado[a]) / Double(b - a)).squareRoot()
        }
        guard let maximo = rms.max(), maximo > piso else { return nil }
        let umbral = max(piso, 0.25 * maximo)
        var tramos: [Tramo] = []
        var i = 0
        while i < n {
            guard rms[i] > umbral else { i += 1; continue }
            var j = i
            while j < n, rms[j] > umbral { j += 1 }
            if let u = tramos.last, Double(i - u.hasta) / fs <= huecoMaximo { tramos[tramos.count - 1].hasta = j } else { tramos.append(Tramo(desde: i, hasta: j)) }
            i = j
        }
        let margen = Int(0.5 * fs)
        let elegido = tramos.max { (acumulado[$0.hasta] - acumulado[$0.desde]) < (acumulado[$1.hasta] - acumulado[$1.desde]) }
        guard let t = elegido else { return nil }
        let tramo = Tramo(desde: max(0, t.desde - margen), hasta: min(n, t.hasta + margen))
        return tramo.hasta - tramo.desde >= Int(2 * periodoMinimo * fs) ? tramo : nil
    }

    // MARK: - El período

    /// El período (en muestras) y su autocorrelación. Autocorrelación normalizada e insesgada; de los máximos locales
    /// gana el más alto, salvo que uno en la mitad o el tercio explique casi igual (≥ 85 %): ahí gana el más corto.
    static func periodo(_ x: [Double], fs: Double) -> (Double, Double)? {
        let n = x.count
        let media = x.reduce(0, +) / Double(n)
        let y = x.map { $0 - media }
        let energia = y.reduce(0) { $0 + $1 * $1 }
        guard energia > 0 else { return nil }
        let minLag = Int(periodoMinimo * fs)
        let maxLag = min(Int(periodoMaximo * fs), n / 2)
        guard maxLag > minLag + 2 else { return nil }
        var r = [Double](repeating: 0, count: maxLag + 2)
        for k in max(1, minLag - 1)...(maxLag + 1) where k < n {
            var s = 0.0
            for i in 0..<(n - k) { s += y[i] * y[i + k] }
            r[k] = (s / Double(n - k)) / (energia / Double(n))
        }
        var picos: [(Int, Double)] = []
        for k in minLag...maxLag where r[k] > 0 && r[k] >= r[k - 1] && r[k] > r[k + 1] { picos.append((k, r[k])) }
        guard let maximo = picos.max(by: { $0.1 < $1.1 }) else { return nil }
        var elegido = maximo
        for divisor in [3, 2] {
            let objetivo = Double(maximo.0) / Double(divisor)
            if let p = picos.first(where: { abs(Double($0.0) - objetivo) <= max(2, 0.15 * objetivo) && $0.1 >= 0.85 * maximo.1 }) {
                elegido = p
                break
            }
        }
        // Afina el pico con una parábola (el período no es un número entero de muestras).
        let k = elegido.0
        let a = r[k - 1], b = r[k], c = r[k + 1]
        let d = a - 2 * b + c
        let ajuste = d != 0 ? 0.5 * (a - c) / d : 0
        return (Double(k) + max(-0.5, min(0.5, ajuste)), min(1, b))
    }

    // MARK: - Los ciclos

    /// Las repeticiones como ciclos completos con histéresis: la señal (centrada en su mediana) tiene que pasar de
    /// +umbral a −umbral y volver; cada dos cruces, una repetición. El umbral es `histeresis` de la amplitud típica
    /// (la mitad de p95 − p5), así una repetición a medias, el temblor o el rebote del filtro no cruzan. Los medios
    /// picos de los bordes (el arranque y el final de una sentadilla) suman un cruce cada uno y el redondeo hacia abajo
    /// los absorbe. La distancia mínima entre dos cruces iguales es de 0,3 períodos.
    static func contarCiclos(_ x: [Double], periodo: Double) -> Int {
        let ordenada = x.sorted()
        let n = ordenada.count
        guard n > 4 else { return 0 }
        let mediana = ordenada[n / 2]
        let amplitud = (ordenada[min(n - 1, Int(0.95 * Double(n)))] - ordenada[Int(0.05 * Double(n))]) / 2
        guard amplitud > 0 else { return 0 }
        let umbral = histeresis * amplitud
        var estado = 0   // 0 = todavía en el medio, 1 = arriba, −1 = abajo
        var cruces = 0
        var ultimo = -Int.max / 2
        let separacion = Int(0.3 * periodo)
        for (i, v) in x.enumerated() {
            let y = v - mediana
            let nuevo = y > umbral ? 1 : (y < -umbral ? -1 : estado)
            if nuevo != estado && nuevo != 0 {
                if i - ultimo >= separacion || estado == 0 { cruces += 1; ultimo = i }
                estado = nuevo
            }
        }
        return cruces / 2
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

    static func pasabanda(_ x: [Double], fs: Double, bajo: Double, alto: Double) -> [Double] {
        let relleno = Int(3 * fs)
        let sinLento = filtfilt(biquad(false, fs: fs, corte: bajo), x, relleno: relleno)
        return filtfilt(biquad(true, fs: fs, corte: alto), sinLento, relleno: relleno)
    }

    /// La proyección sobre el eje de más varianza (iteración de potencia sobre la covarianza 3×3). El signo es el de
    /// la componente más grande del eje, así es estable entre corridas.
    static func componentePrincipal(_ ejes: [[Double]]) -> [Double] {
        let n = ejes.first?.count ?? 0
        guard n > 0 else { return [] }
        let medias = ejes.map { $0.reduce(0, +) / Double(n) }
        var cov = [[Double]](repeating: [0, 0, 0], count: 3)
        for i in 0..<3 {
            for j in i..<3 {
                var s = 0.0
                for k in 0..<n { s += (ejes[i][k] - medias[i]) * (ejes[j][k] - medias[j]) }
                cov[i][j] = s / Double(n); cov[j][i] = cov[i][j]
            }
        }
        var v = [1.0, 0.7, 0.4]
        for _ in 0..<60 {
            var w = [0.0, 0.0, 0.0]
            for i in 0..<3 { for j in 0..<3 { w[i] += cov[i][j] * v[j] } }
            let norma = (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]).squareRoot()
            guard norma > 0 else { break }
            v = w.map { $0 / norma }
        }
        if let m = v.indices.max(by: { abs(v[$0]) < abs(v[$1]) }), v[m] < 0 { v = v.map { -$0 } }
        return (0..<n).map { k in (0..<3).reduce(0) { $0 + (ejes[$1][k] - medias[$1]) * v[$1] } }
    }
}
