import Foundation
import MyPumpModelos

// Lo que muestran las cards de Salud y Recuperación y la escena "Mis datos" (cliente.html:6363-7328), sin la vista:
// qué valor gana cada día, qué caso de la card toca, las frases y los números ya formateados como en la web.

/// Un día de una serie de salud, con la mejor fuente de ese día.
public struct PuntoSalud: Sendable, Equatable {
    public let fecha: String
    public let valor: Double
    public let detalle: JSONValue?
    public init(fecha: String, valor: Double, detalle: JSONValue? = nil) { self.fecha = fecha; self.valor = valor; self.detalle = detalle }
}

public enum SaludVista {

    // MARK: - Prioridad de fuentes (SAL-12)

    /// `_PREF_FUENTE`: el MISMO orden que el motor de recuperación (043:100-104). Los relojes por API directa dan rMSSD
    /// real; Apple Health y Health Connect retransmiten; el agregador después; lo tipeado a mano al final.
    public static func rangoFuente(_ f: String?) -> Int? {
        switch f {
        case "whoop", "oura", "withings", "polar": 0
        case "apple_health", "health_connect": 1
        case "rook": 2
        case "manual": 3
        default: nil
        }
    }

    /// `_saludValor(tipo, fecha)`: el valor de la mejor fuente (en HRV, un rMSSD gana antes de mirar la fuente).
    public static func valor(_ filas: [FilaSalud], tipo: String, fecha: String) -> Double? {
        func esRmssd(_ r: FilaSalud) -> Int { tipo == "hrv_ms" && r.detalle?["metrica"]?.comoTexto == "rmssd" ? 0 : 1 }
        let candidatas = filas.enumerated().filter { $0.element.tipo == tipo && $0.element.fecha == fecha }
        let mejor = candidatas.min { a, b in
            let ka = (esRmssd(a.element), rangoFuente(a.element.fuente) ?? 4, a.offset)
            let kb = (esRmssd(b.element), rangoFuente(b.element.fuente) ?? 4, b.offset)
            return ka < kb
        }
        // `Number(rows[0].valor)`: un valor nulo cuenta como 0.
        return mejor.map { $0.element.valor ?? 0 }
    }

    /// `_serieSalud(tipo)`: un punto por fecha con la mejor fuente (en empate, la primera), ordenado por fecha.
    public static func serie(_ filas: [FilaSalud], tipo: String) -> [PuntoSalud] {
        var porFecha: [String: (p: Int, punto: PuntoSalud)] = [:]
        for r in filas where r.tipo == tipo {
            let p = rangoFuente(r.fuente) ?? 9
            if let actual = porFecha[r.fecha], p >= actual.p { continue }
            porFecha[r.fecha] = (p, PuntoSalud(fecha: r.fecha, valor: r.valor ?? 0, detalle: r.detalle))
        }
        return porFecha.keys.sorted().compactMap { porFecha[$0]?.punto }
    }

    /// `_saludTieneReciente(tipos, dias)`: ¿llegó alguno de estos tipos desde hace `dias` días? (Como la web,
    /// `dias || 7`: 0 cuenta como 7.)
    public static func tieneReciente(_ filas: [FilaSalud], tipos: [String], dias: Int, hoy: String) -> Bool {
        guard let nHoy = DiaCalendario.numero(hoy) else { return false }
        let d = dias == 0 ? 7 : dias
        return filas.contains { r in
            guard tipos.contains(r.tipo), r.valor != nil, let n = DiaCalendario.numero(r.fecha) else { return false }
            return n >= nHoy - d
        }
    }

    // MARK: - Card Salud (SAL-10)

    public struct ResumenSalud: Sendable, Equatable {
        public let pasosHoy: Double?
        public let minutosActivosHoy: Double?
        public let suenoAnoche: Double?
        public let hrv: Double?
        /// "Promedio N días": los últimos 7 con pasos.
        public let diasPromedio: Int
        public let promedioPasos: Int
    }

    /// `renderMydaySalud` con datos: nil si no hay ni pasos ni minutos activos (la card no muestra números).
    public static func resumen(_ filas: [FilaSalud], hoy: String) -> ResumenSalud? {
        let pasos = filas.filter { $0.tipo == "pasos" }
        guard !pasos.isEmpty || filas.contains(where: { $0.tipo == "actividad_min" }) else { return nil }
        let fechas = Array(Set(pasos.map(\.fecha))).sorted().suffix(7)
        let vals = fechas.compactMap { valor(filas, tipo: "pasos", fecha: $0) }
        let prom = vals.isEmpty ? 0 : (vals.reduce(0, +) / Double(vals.count)).jsEntero
        let ayer = DiaCalendario.numero(hoy).map { DiaCalendario.texto($0 - 1) } ?? hoy
        return ResumenSalud(
            pasosHoy: valor(filas, tipo: "pasos", fecha: hoy),
            minutosActivosHoy: valor(filas, tipo: "actividad_min", fecha: hoy),
            suenoAnoche: valor(filas, tipo: "sueno_min", fecha: hoy) ?? valor(filas, tipo: "sueno_min", fecha: ayer),
            hrv: valor(filas, tipo: "hrv_ms", fecha: hoy) ?? valor(filas, tipo: "hrv_ms", fecha: ayer),
            diasPromedio: vals.count,
            promedioPasos: prom)
    }

    // MARK: - Card Recuperación (SAL-09)

    public struct Motivo: Sendable, Equatable {
        public let sube: Bool
        public let antes: String
        public let negrita: String
        public let despues: String
        public var texto: String { antes + negrita + despues }
    }

    public enum CardRecuperacion: Sendable, Equatable {
        /// Sin score y sin Salud conectada: explicación + "Conectar Apple Health".
        case sinConectar
        /// Conectado pero sin score: qué falta (trayendo historial, faltan datos de la noche, solo pasos, no llega nada,
        /// esperando).
        case conectadoSinScore(SinScore)
        /// Aprendiendo la normal del cliente: n de 14 días.
        case calibrando(dias: Int, porcentaje: Int, yaSe: String)
        /// El cliente apagó el número.
        case oculto
        case conScore(ConScore)
    }

    public enum SinScore: Sendable, Equatable {
        case trayendoHistorial(hecho: Int, total: Int)
        case faltanDatosDeLaNoche
        case soloPasos
        case noLlegaNada
        case esperando

        public var frase: String {
            switch self {
            case .trayendoHistorial(let h, let t): "Trayendo tu historial de Salud… \(h)/\(t) días"
            case .faltanDatosDeLaNoche: "Estos días no están llegando los datos de la noche."
            case .soloPasos: "Este iPhone ya está mandando pasos y actividad. 👌"
            case .noLlegaNada: "Salud está conectada pero no llegó ningún dato."
            case .esperando: "Conectado. Esperando los primeros datos de tu iPhone…"
            }
        }

        public var nota: String {
            switch self {
            case .trayendoHistorial: "Puede tardar un rato la primera vez. Podés seguir usando la app."
            case .faltanDatosDeLaNoche: "Fijate que el reloj esté sincronizando con la app Salud del iPhone."
            case .soloPasos: "Para el score de recuperación hace falta lo que se mide durmiendo — pulso en reposo, sueño y variabilidad — y eso lo da un reloj o un anillo (Apple Watch, Oura, Garmin…). En cuanto uses uno, esto se arma solo."
            case .noLlegaNada: "Fijate que esté todo activado en Ajustes → Privacidad y seguridad → Salud → MyPump."
            case .esperando: "Si tenés reloj o anillo, con eso el score arranca mucho más rápido."
            }
        }
    }

    public struct ConScore: Sendable, Equatable {
        public let fila: RecuperacionDia
        /// alta | media | baja
        public let banda: String
        /// "Recuperado" | "Medio" | "Poco recuperado"
        public let bandaTexto: String
        public let frase: String?
        public let motivos: [Motivo]
        /// "Score de lunes: la de anoche todavía no llegó." cuando se muestra uno de los 3 días anteriores.
        public let notaVieja: String?
        public let provisoria: Bool
        /// El gráfico de 14 días (los puntos con score; hacen falta 3).
        public let grafico: [(fecha: String, score: Int)]

        public static func == (a: ConScore, b: ConScore) -> Bool {
            a.fila == b.fila && a.banda == b.banda && a.frase == b.frase && a.motivos == b.motivos && a.notaVieja == b.notaVieja
                && a.provisoria == b.provisoria && a.grafico.map(\.fecha) == b.grafico.map(\.fecha) && a.grafico.map(\.score) == b.grafico.map(\.score)
        }
    }

    public static let textoBanda = ["alta": "Recuperado", "media": "Medio", "baja": "Poco recuperado"]

    /// `renderMydayRecuperacion`: qué caso de la card toca. La serie viene densa (una fila por día) y la última es hoy
    /// en hora argentina: se muestra el último score REAL de los últimos 3 días.
    public static func cardRecuperacion(serie: [RecuperacionDia], conectado: Bool, mostrar: Bool, salud: [FilaSalud],
                                        historial: (hecho: Int, total: Int)?, sinDatos: Bool, hoy: String) -> CardRecuperacion {
        let ultima = serie.last
        let conScore = serie.suffix(3).reversed().first { $0.score != nil }
        guard let fila = conScore ?? ultima, fila.estado != "insuficiente" else {
            guard conectado else { return .sinConectar }
            return .conectadoSinScore(sinScore(salud: salud, historial: historial, sinDatos: sinDatos, hoy: hoy))
        }
        if fila.estado == "calibrando" || fila.score == nil {
            let n = fila.diasDatos ?? 0
            let pct = min(100, (Double(n) / 14 * 100).jsEntero)   // con `Int()`, un dias_datos absurdo cerraba la app
            var ya = ""
            if let s = numero(fila.cobertura?["sueno_min"]), s != 0 { ya = "Ya sé que dormís cerca de \(horasSinEspacio(s))." }
            else if let f = numero(fila.cobertura?["fc_reposo"]), f != 0 { ya = "Ya sé que tu pulso en reposo ronda los \(enteroJS(f))." }
            return .calibrando(dias: n, porcentaje: pct, yaSe: ya)
        }
        if !mostrar { return .oculto }

        let banda = fila.banda ?? "media"
        let motivos = self.motivos(fila)
        let frase: String?
        if fila.discordancia == true { frase = "Los números dicen una cosa y vos me dijiste otra. Le creo a lo que sentís." }
        else if fila.estadoAutonomico == "maladaptacion" { frase = "Tu cuerpo viene peleando con la carga. Hoy conviene aflojar." }
        else if fila.estadoAutonomico == "fatiga_acumulada" { frase = "Venís con fatiga acumulada de varios días." }
        else if motivos.isEmpty {
            frase = banda == "alta" ? "Venís bien. Aprovechalo." : banda == "baja" ? "Hoy tu cuerpo pide más descanso." : "Estás en tu rango normal."
        } else { frase = nil }
        let vieja = conScore != nil && ultima != nil && conScore != ultima
        let puntos = serie.compactMap { r in r.score.map { (fecha: r.fecha, score: $0) } }
        return .conScore(ConScore(
            fila: fila, banda: banda, bandaTexto: textoBanda[banda] ?? "", frase: frase, motivos: motivos,
            notaVieja: vieja ? "Score de \(diaDeLaSemana(fila.fecha)): la de anoche todavía no llegó." : nil,
            provisoria: fila.bandaProvisoria == true,
            grafico: puntos.count >= 3 ? puntos : []))
    }

    /// `_recupSinScoreConectado`: lo que separa los casos es qué está llegando, no cuánto falta.
    public static func sinScore(salud: [FilaSalud], historial: (hecho: Int, total: Int)?, sinDatos: Bool, hoy: String) -> SinScore {
        if let h = historial { return .trayendoHistorial(hecho: h.hecho, total: h.total) }
        let nocturnos = ["fc_reposo", "hrv_ms", "sueno_min"]
        let nocheReciente = tieneReciente(salud, tipos: nocturnos, dias: 7, hoy: hoy)
        let nocheAlguna = tieneReciente(salud, tipos: nocturnos, dias: 60, hoy: hoy)
        let diaReciente = tieneReciente(salud, tipos: ["pasos", "actividad_min", "kcal_activas"], dias: 7, hoy: hoy)
        if !nocheReciente && nocheAlguna { return .faltanDatosDeLaNoche }
        if diaReciente { return .soloPasos }
        if sinDatos { return .noLlegaNada }
        return .esperando
    }

    /// `_recDrivers`: hasta 3 motivos, del hecho a castellano. Los tipos que no se conocen se saltean.
    public static func motivos(_ fila: RecuperacionDia) -> [Motivo] {
        guard case .lista(let ms) = fila.motivos else { return [] }
        return ms.prefix(3).compactMap { m in
            // Como `_recDrivers`: `Number(m.valor)` (null es 0 y da "0h00"; ausente, NaN) y `m.baseline ?` por la verdad
            // de JS (un "0" de texto cuenta, un 0 no).
            let sube = (AnclajeSwaps.numero(m["dir"]) ?? .nan) > 0
            let v = AnclajeSwaps.numero(m["valor"]) ?? .nan
            let conBase = m["baseline"].map(AnclajeSwaps.esVerdadero) ?? false
            let base = AnclajeSwaps.numero(m["baseline"]) ?? .nan
            switch m["tipo"]?.comoTexto {
            case "sueno":
                return Motivo(sube: sube, antes: "Dormiste ", negrita: horasSinEspacio(v), despues: conBase ? " · venís de \(horasSinEspacio(base))" : "")
            case "fc_reposo":
                let d = conBase ? jsRound(abs(v - base)) : 0
                let conD = d != 0 && !d.isNaN
                return Motivo(sube: sube, antes: "Pulso en reposo ", negrita: enteroJS(v), despues: conD ? " · \(enteroJS(d)) más que tu normal" : "")
            case "hrv":
                return Motivo(sube: sube, antes: "Variabilidad ", negrita: "\(enteroJS(v)) ms", despues: conBase ? " · tu normal es \(enteroJS(base))" : "")
            case "carga":
                return Motivo(sube: sube, antes: "Entrenaste fuerte: ", negrita: textoJS(m["agudo"]), despues: " series duras en 3 días")
            case "regularidad":
                return Motivo(sube: sube, antes: "Horarios de sueño irregulares esta semana", negrita: "", despues: "")
            default:
                return nil
            }
        }
    }

    // MARK: - Mis datos (SAL-11)

    public struct Componente: Sendable, Equatable {
        public let clave: String
        public let nombre: String
        public let score: Int
        /// Lo que pesa en el score, sobre el total de los componentes presentes.
        public let aporte: Int
    }

    public static let nombresComponentes: [(clave: String, nombre: String)] = [
        ("autonomico", "Corazón (pulso + variabilidad)"), ("sueno", "Sueño"), ("carga", "Carga del gimnasio"),
        ("subjetivo", "Cómo te sentís"), ("otros", "Respiración, oxígeno, temperatura"),
    ]

    /// "Cómo se arma tu recuperación": los pesos del motor vienen sin normalizar (45/25/20/12/8) y se reparten sobre los
    /// presentes, que es el aporte real.
    public static func componentes(_ fila: RecuperacionDia?) -> [Componente] {
        guard let fila, fila.score != nil, let comp = fila.componentes else { return [] }
        let presentes = nombresComponentes.filter { k in comp[k.clave].flatMap { numero($0["score"]) } != nil }
        let wTot = presentes.reduce(0.0) { $0 + (numero(comp[$1.clave]?["peso"]) ?? 0) }
        let total = wTot == 0 ? 1 : wTot
        return presentes.map { k in
            let c = comp[k.clave]
            return Componente(clave: k.clave, nombre: k.nombre, score: (numero(c?["score"]) ?? 0).jsEntero,
                              aporte: ((numero(c?["peso"]) ?? 0) / total * 100).jsEntero)
        }
    }

    /// Una fila de métrica de "Mis datos" (`_filaSalud`): el valor del último día, el promedio de 7 y de 30 y la
    /// flecha contra el de 30 si se aparta más de un 3 %.
    public struct FilaMetrica: Sendable, Equatable {
        public let tipo: String
        public let valor: String
        public let delta: String?
        public let deltaEsBueno: Bool
        public let promedio7: String
        public let promedio30: String?
        public let diasConDato: Int
        public let serie: [PuntoSalud]
    }

    public static func fila(_ filas: [FilaSalud], tipo: String, mejorSube: Bool = true, formato: (Double) -> String = entero) -> FilaMetrica? {
        let s = serie(filas, tipo: tipo)
        guard let ultimo = s.last else { return nil }
        let p7 = promedio(s.suffix(7).map(\.valor))
        let p30 = promedio(s.suffix(30).map(\.valor))
        var delta: String?
        var bueno = true
        if let p30, abs(ultimo.valor - p30) / (p30 == 0 ? 1 : p30) > 0.03 {
            let sube = ultimo.valor > p30
            bueno = mejorSube ? sube : !sube
            delta = "\(sube ? "↑" : "↓") \(formato(abs(ultimo.valor - p30)))"
        }
        return FilaMetrica(tipo: tipo, valor: formato(ultimo.valor), delta: delta, deltaEsBueno: bueno,
                           promedio7: p7.map(formato) ?? "", promedio30: s.count > 7 ? p30.map(formato) : nil,
                           diasConDato: s.count, serie: s)
    }

    /// Regularidad del sueño: hora promedio de dormirse (punto medio − 3 h 30) y variación, con 4 noches o más.
    public static func regularidad(_ filas: [FilaSalud]) -> (horaDormirse: String, variacion: Int, texto: String)? {
        let s = serie(filas, tipo: "sueno_medio_min")
        guard s.count >= 4 else { return nil }
        let (m, sd) = promedioCircular(s.suffix(7).map(\.valor))
        let texto = sd <= 30 ? "Muy regular — eso ayuda tanto como dormir más."
            : sd >= 90 ? "Bastante irregular: acostarte a horarios parecidos mueve la aguja." : "Razonablemente regular."
        return (horaReloj(m - 210), Int(jsRound(sd)), texto)
    }

    /// "Anoche" / "Anteanoche" / "Noche del 12 oct" para la última noche con dato.
    public static func rotuloNoche(_ fecha: String, hoy: String) -> String {
        guard let n = DiaCalendario.numero(fecha), let h = DiaCalendario.numero(hoy) else { return "Anoche" }
        if n == h { return "Anoche" }
        if n == h - 1 { return "Anteanoche" }
        guard let corta = fechaCorta(fecha) else { return "Última noche con dato" }
        return "Noche del \(corta)"
    }

    /// `toLocaleDateString('es-AR', {day: 'numeric', month: 'short'})` de una fecha "YYYY-MM-DD": "12 oct".
    public static func fechaCorta(_ fecha: String) -> String? {
        let partes = fecha.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard partes.count == 3, (1...12).contains(partes[1]) else { return nil }
        return "\(partes[2]) \(meses[partes[1] - 1])"
    }

    // MARK: - Formatos (como los de la web)

    static let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]
    static let diasSemana = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]

    /// `toLocaleDateString('es-AR', {weekday: 'long'})` de una fecha "YYYY-MM-DD".
    public static func diaDeLaSemana(_ fecha: String) -> String {
        guard let n = DiaCalendario.numero(fecha) else { return "la última noche con datos" }
        return diasSemana[((n + 4) % 7 + 7) % 7]   // 1970-01-01 fue jueves
    }

    /// `_fmtHs`: "7h05" (la card de recuperación).
    public static func horasSinEspacio(_ m: Double) -> String {
        "\(enteroJS((m / 60).rounded(.down)))h\(dosCifras(jsRound(m.truncatingRemainder(dividingBy: 60))))"
    }

    /// `fmtSueno` / `hs`: "7h 05" (Salud y Mis datos).
    public static func horas(_ m: Double) -> String {
        "\(enteroJS((m / 60).rounded(.down)))h \(dosCifras(jsRound(m.truncatingRemainder(dividingBy: 60))))"
    }

    /// `String(Math.round(x))`, sin romperse con NaN o infinito (JS escribe "NaN").
    public static func enteroJS(_ x: Double) -> String {
        guard x.isFinite else { return x.isNaN ? "NaN" : (x > 0 ? "Infinity" : "-Infinity") }
        return JS.texto(jsRound(x))   // 1e21 sale "1e+21", como en JS (`Int()` cerraba la app)
    }

    /// `Math.round(v).toLocaleString('es-AR')`: "8.548". Con los bordes de ICU: "∞", "-0" (de un -0,4) y los dígitos
    /// más cortos completados con ceros (1e23 es "100.000.000.000.000.000.000.000", no los del binario).
    public static func miles(_ v: Double) -> String {
        if v.isNaN { return "NaN" }
        if v.isInfinite { return v > 0 ? "∞" : "-∞" }
        let r = jsRound(v)
        let s = digitosDeEntero(abs(r))
        var out = ""
        for (i, c) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(".") }
            out.append(c)
        }
        // `Math.round` de un negativo hasta −0,5 es −0, y ICU lo escribe "-0" (`jsRound` devuelve el 0 sin signo).
        return (r < 0 || (r == 0 && v.sign == .minus) ? "-" : "") + String(out.reversed())
    }

    /// Los dígitos de un entero no negativo como los da `toLocaleString`: los de `String(x)` de JS, y si viene con
    /// exponente ("1e+23"), la mantisa completada con ceros. Nunca pasa por `Int` (con uno que no entra, cerraba la app).
    private static func digitosDeEntero(_ x: Double) -> String {
        let t = JS.texto(x)
        guard let e = t.range(of: "e+") else { return t }
        let mantisa = t[..<e.lowerBound]
        let decimales = mantisa.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        let ceros = max(0, (Int(t[e.upperBound...]) ?? 0) - decimales)
        return mantisa.replacingOccurrences(of: ".", with: "") + String(repeating: "0", count: ceros)
    }

    public static let entero: @Sendable (Double) -> String = { enteroJS($0) }
    /// `v.toFixed(1)` (el punto queda: así se ve en la web).
    public static let unDecimal: @Sendable (Double) -> String = { PesoCorporal.toFixed1($0) }

    /// `_hhmmReloj`: minutos (puede ser negativo o pasar de 1440) → "HH:MM".
    public static func horaReloj(_ mm: Double) -> String {
        guard mm.isFinite else { return "NaN:NaN" }
        // `%` de JS es el resto exacto del double: primero el resto, después el entero (que así siempre entra).
        let r = Int(jsRound(mm).truncatingRemainder(dividingBy: 1440))
        let x = ((r % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", x / 60, x % 60)
    }

    /// `_promCircularMin`: promedio circular de minutos del día y desvío plegado a ±720.
    public static func promedioCircular(_ vals: [Double]) -> (media: Double, desvio: Double) {
        let v = vals.filter(\.isFinite)
        guard !v.isEmpty else { return (0, 0) }
        let ang = v.map { $0 / 1440 * 2 * Double.pi }
        let cx = ang.reduce(0) { $0 + cos($1) } / Double(ang.count)
        let cy = ang.reduce(0) { $0 + sin($1) } / Double(ang.count)
        var a = atan2(cy, cx)
        if a < 0 { a += 2 * Double.pi }
        let m = a / (2 * Double.pi) * 1440
        let dev = v.map { x -> Double in
            var d = (x - m).truncatingRemainder(dividingBy: 1440)
            if d > 720 { d -= 1440 }
            if d < -720 { d += 1440 }
            return d
        }
        return (m, (dev.reduce(0) { $0 + $1 * $1 } / Double(dev.count)).squareRoot())
    }

    static func promedio(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
    static func dosCifras(_ x: Double) -> String {
        guard x.isFinite else { return "NaN" }
        return x < 10 && x >= 0 ? "0\(Int(x))" : JS.texto(x)
    }

    static func numero(_ j: JSONValue?) -> Double? {
        switch j {
        case .numero(let d): return d
        case .texto(let s): return Double(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    /// Cómo pinta JS un valor dentro de un template (`${m.agudo}`).
    static func textoJS(_ j: JSONValue?) -> String {
        switch j {
        case .numero(let d): return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .texto(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        default: return "undefined"
        }
    }
}
