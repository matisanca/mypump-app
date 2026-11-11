import Foundation
import MyPumpModelos

/// Las metas del plan (2.3.0, propuesta 8): `meta_pasos_dia` y `ritmo_peso_kg_semana` en la raíz de
/// `mypump_dietas.estructura`. Las escribe EDITOR al publicar, con el OK de Mati. La app nunca inventa una meta: un valor
/// que falta, que no es del tipo o que está fuera de rango, no está. Vectores: apps/shared/vectores/metas_pasos.json
/// (los mismos que leen MetasTest.kt y la web).
public struct MetasPlan: Equatable, Sendable {
    public let metaPasos: Int?
    /// Kilos por semana, con signo: negativo para bajar, 0 para mantener, positivo para subir.
    public let ritmoKgSemana: Double?

    /// El mismo rango que controla pumplib al publicar (EDITOR, 10/11).
    public static let rangoPasos = 3_000...25_000
    public static let rangoRitmo = -1.0...0.5

    public init(metaPasos: Int?, ritmoKgSemana: Double?) {
        self.metaPasos = metaPasos.flatMap { Self.rangoPasos.contains($0) ? $0 : nil }
        self.ritmoKgSemana = ritmoKgSemana.flatMap { $0.isFinite && Self.rangoRitmo.contains($0) ? $0 : nil }
    }

    public init(_ e: EstructuraDieta) {
        // Pasos enteros: 10000 o 10000.0 sirven; 10000.5 no.
        let pasos = e.metaPasosDia.flatMap { $0.isFinite && $0 == $0.rounded() && abs($0) < 1e9 ? Int($0) : nil }
        self.init(metaPasos: pasos, ritmoKgSemana: e.ritmoPesoKgSemana)
    }

    public var vacio: Bool { metaPasos == nil && ritmoKgSemana == nil }
}

/// «Pump del día»: el indicador propio de la marca para la meta de pasos. El torso del logo se llena con los pasos de hoy;
/// al llegar, «Pump lleno», una sola vez por día.
public enum PumpDelDia {
    public static let nombre = "Pump del día"
    public static let lleno = "Pump lleno"

    public enum EstadoDia: String, Sendable, Equatable {
        /// Llegó a la meta.
        case cumplido
        /// Un día pasado con pasos, abajo de la meta.
        case no
        /// Un día pasado sin dato de pasos.
        case sinDato = "sin_dato"
        /// Hoy, todavía abajo de la meta.
        case hoy
        /// Lo que queda de la semana.
        case futuro
    }

    public struct Dia: Sendable, Equatable {
        public let fecha: String
        /// L, M, M, J, V, S, D.
        public let inicial: String
        public let estado: EstadoDia
    }

    public struct Vista: Sendable, Equatable {
        public let meta: Int
        public let pasosHoy: Int
        /// De 0 a 1 (tope 1).
        public let fraccion: Double
        public let falta: Int
        public let cumplido: Bool
        /// Días seguidos con la meta, terminando hoy si ya llegó (si no, ayer: hoy todavía está en juego).
        public let racha: Int
        /// De lunes a domingo, la semana de hoy.
        public let semana: [Dia]
        /// El promedio de los últimos 7 días completos con dato (sin hoy), como `mypump_pasos_salud`. nil sin días.
        public let promedio7: Int?
    }

    private static let iniciales = ["L", "M", "M", "J", "V", "S", "D"]

    /// Los pasos por día (la mejor fuente de cada día: `SaludVista.serie(filas, tipo: "pasos")`).
    public static func pasosPorDia(_ filas: [FilaSalud]) -> [String: Double] {
        Dictionary(SaludVista.serie(filas, tipo: "pasos").map { ($0.fecha, $0.valor) }, uniquingKeysWith: { a, _ in a })
    }

    public static func vista(pasosPorDia p: [String: Double], meta: Int, hoy: String) -> Vista? {
        guard meta > 0, let nHoy = DiaCalendario.numero(hoy) else { return nil }
        let m = Double(meta)
        let pasosHoy = max(0, (p[hoy] ?? 0).jsEntero)
        let cumplido = Double(pasosHoy) >= m
        func llego(_ n: Int) -> Bool { (p[DiaCalendario.texto(n)] ?? -1).jsEntero >= meta }

        var racha = 0
        var d = cumplido ? nHoy : nHoy - 1
        while llego(d) && racha < 400 { racha += 1; d -= 1 }

        let lunes = DiaCalendario.numero(FotosProgreso.lunes(hoy)) ?? nHoy
        let semana = (0..<7).map { i -> Dia in
            let n = lunes + i
            let f = DiaCalendario.texto(n)
            let estado: EstadoDia
            if n > nHoy { estado = .futuro }
            else if n == nHoy { estado = cumplido ? .cumplido : .hoy }
            else if let v = p[f] { estado = v.jsEntero >= meta ? .cumplido : .no }
            else { estado = .sinDato }
            return Dia(fecha: f, inicial: iniciales[i], estado: estado)
        }

        let previos = (1...7).compactMap { p[DiaCalendario.texto(nHoy - $0)] }
        let promedio = previos.isEmpty ? nil : (previos.reduce(0, +) / Double(previos.count)).jsEntero

        return Vista(meta: meta, pasosHoy: pasosHoy, fraccion: min(1, Double(pasosHoy) / m),
                     falta: max(0, meta - pasosHoy), cumplido: cumplido, racha: racha, semana: semana, promedio7: promedio)
    }

    // MARK: - Una sola celebración por día

    /// Lo que se guarda en el teléfono, por cuenta: las fechas ya celebradas (las últimas 60, en orden).
    public struct Registro: Codable, Sendable, Equatable {
        public var celebrados: [String]
        public init(celebrados: [String] = []) { self.celebrados = celebrados }
    }

    /// ¿Hay que celebrar ahora? Solo hoy, con la meta cumplida, si hoy no se celebró y hoy no es anterior a la última
    /// fecha celebrada (un viaje hacia el oeste vuelve a «ayer»: no se festeja dos veces el mismo esfuerzo).
    public static func debeCelebrar(_ r: Registro, hoy: String, pasosHoy: Int, meta: Int) -> Bool {
        guard meta > 0, pasosHoy >= meta, DiaCalendario.numero(hoy) != nil else { return false }
        guard !r.celebrados.contains(hoy) else { return false }
        if let ultima = r.celebrados.max(), ultima >= hoy { return false }
        return true
    }

    public static func marcar(_ r: Registro, hoy: String) -> Registro {
        var c = r.celebrados.filter { $0 != hoy }
        c.append(hoy)
        c.sort()
        return Registro(celebrados: Array(c.suffix(60)))
    }

    // MARK: - Textos (TEXTOS_PARA_OK, sección Metas)

    public static func numeroPasos(_ n: Int) -> String { SaludVista.miles(Double(n)) }
    public static func deMeta(_ v: Vista) -> String { "de \(numeroPasos(v.meta)) pasos" }
    public static func estado(_ v: Vista) -> String {
        v.cumplido ? "Llegaste a tus pasos de hoy" : "Te faltan \(numeroPasos(v.falta)) pasos"
    }
    public static func racha(_ n: Int) -> String? { n >= 2 ? "\(n) días seguidos" : nil }
    public static func sinSalud(meta: Int) -> String { "Tu meta es de \(numeroPasos(meta)) pasos por día" }
    public static let conectar = "Conectá Salud y vas a ver cómo venís"
    public static func celebracion(meta: Int) -> String { "Llegaste a tus \(numeroPasos(meta)) pasos de hoy" }
    public static func celebracionRacha(_ n: Int) -> String? { n >= 2 ? "Van \(n) días seguidos" : nil }
    public static let seguir = "Seguir"
    public static func lineaSalud(meta: Int, promedio: Int?) -> String {
        guard let promedio else { return "Meta \(numeroPasos(meta)) pasos por día" }
        return "Meta \(numeroPasos(meta)) pasos por día, tu promedio \(numeroPasos(promedio))"
    }
    public static func accesible(_ v: Vista) -> String {
        var s = "\(nombre), \(numeroPasos(v.pasosHoy)) de \(numeroPasos(v.meta)) pasos. \(estado(v))."
        if let r = racha(v.racha) { s += " \(r)." }
        return s
    }
}

/// El ritmo de peso que buscamos, junto a la media de 7 días que ya muestra la tarjeta de peso. Nunca un juicio negativo:
/// la tendencia se cuenta tal cual y, si va al ritmo, se dice.
public enum RitmoPeso {
    public struct Resumen: Sendable, Equatable {
        public let meta: String
        /// nil con menos de 4 pesos en los últimos 7 días o sin la semana anterior.
        public let tendencia: String?
        public let enRitmo: Bool
    }

    /// «medio kilo», «300 g», «un kilo», «1,2 kg».
    public static func cantidad(kg: Double) -> String {
        // De a 100 g, con 100 g de piso: «unos 380 g» no lo dice nadie.
        let decimas = max(1, jsRound(abs(kg) * 10))
        if decimas == 5 { return "medio kilo" }
        if decimas < 10 { return "\(Int(decimas) * 100) g" }
        if decimas == 10 { return "un kilo" }
        let t = NumeroJS.toFixed(decimas / 10, 1).replacingOccurrences(of: ".", with: ",")
        return (t.hasSuffix(",0") ? String(t.dropLast(2)) : t) + " kg"
    }

    public static func textoMeta(_ ritmo: Double) -> String {
        if abs(ritmo) < 0.001 { return "Buscamos mantener tu peso" }
        // «unos 300 g», «unos 1,2 kg»; «medio kilo» y «un kilo» van solos.
        let c = cantidad(kg: ritmo)
        let unos = c.hasSuffix(" g") || c.contains(",") ? "unos " : ""
        return "Buscamos \(ritmo < 0 ? "bajar" : "subir") \(unos)\(c) por semana"
    }

    public static func resumen(ritmo: Double, serie: [PesoCorporal.Punto], hoy: String) -> Resumen {
        let meta = textoMeta(ritmo)
        guard let nHoy = DiaCalendario.numero(hoy) else { return Resumen(meta: meta, tendencia: nil, enRitmo: false) }
        let ultimos = serie.filter { p in DiaCalendario.numero(p.fecha).map { $0 > nHoy - 7 && $0 <= nHoy } ?? false }
        guard ultimos.count >= 4, let g = PesoCorporal.deltaSemanal(serie, hoy: hoy) else {
            return Resumen(meta: meta, tendencia: nil, enRitmo: false)
        }
        let tendencia: String
        if abs(g) < 100 { tendencia = "Venís estable" }
        else { tendencia = "Venís \(g < 0 ? "bajando" : "subiendo") \(cantidad(kg: Double(g) / 1000)) por semana" }
        let objetivo = ritmo * 1000
        let enRitmo: Bool
        if abs(ritmo) < 0.001 { enRitmo = abs(g) <= 150 }
        else { enRitmo = (g < 0) == (objetivo < 0) && Double(abs(g)) >= 0.75 * abs(objetivo) && Double(abs(g)) <= 1.5 * abs(objetivo) }
        return Resumen(meta: meta, tendencia: tendencia, enRitmo: enRitmo)
    }

    public static let enRitmoTexto = "Vas justo al ritmo que buscamos"
}
