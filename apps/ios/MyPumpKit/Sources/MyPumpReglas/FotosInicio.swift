import Foundation
import MyPumpModelos

/// Las reglas de «Fotos de inicio» (frente, perfil y espalda, y «el físico que te motiva»), comunes con Android y la web:
/// las fijan los vectores de `apps/shared/vectores/fotos_inicio.json`.
public enum FotosInicio {
    public struct Pose: Equatable, Sendable, Identifiable {
        public let clave: String
        public let nombre: String
        public let instruccion: String
        public var id: String { clave }
    }

    /// Las tres del cuerpo, en el orden en que se piden.
    public static let poses: [Pose] = [
        Pose(clave: "frente", nombre: TextosFotosInicio.poseFrente, instruccion: TextosFotosInicio.instruccionFrente),
        Pose(clave: "perfil", nombre: TextosFotosInicio.posePerfil, instruccion: TextosFotosInicio.instruccionPerfil),
        Pose(clave: "espalda", nombre: TextosFotosInicio.poseEspalda, instruccion: TextosFotosInicio.instruccionEspalda),
    ]
    public static let motivacion = "motivacion"
    public static func pose(_ clave: String) -> Pose? { poses.first { $0.clave == clave } }

    public static let consejos: [String] = [
        TextosFotosInicio.consejoLuz, TextosFotosInicio.consejoDistancia, TextosFotosInicio.consejoAltura, TextosFotosInicio.consejoRopa,
        TextosFotosInicio.consejoFondo, TextosFotosInicio.consejoEspejo, TextosFotosInicio.consejoTemporizador, TextosFotosInicio.consejoPostura,
    ]

    /// El JPEG que sube: lado mayor ≤ 1600 px a 0,85, sin metadatos.
    public static let maxPx = 1600
    public static let calidad = 0.85
    /// Con menos, la lectura del físico se descarta (el servidor tampoco la deja entrar).
    public static let minLado = 1080
    public static let minLadoMotivacion = 320
    public static let maxMotivacion = 4
    public static let maxNota = 300
    public static let brilloMinimo = 45.0
    public static let nitidezMinima = 25.0
    public static let diasVieja = 7
    /// El control mira la foto achicada a bloques, con el lado mayor cerca de este tamaño.
    public static let ladoAnalisis = 640

    // MARK: Control de calidad

    public struct Medida: Equatable, Sendable {
        /// Luz media, de 0 a 255.
        public let brillo: Double
        /// Qué tan marcados están los bordes más marcados, en la dirección en que menos lo están (una foto movida los pierde
        /// en la dirección del movimiento).
        public let nitidez: Double
        public init(brillo: Double, nitidez: Double) { self.brillo = brillo; self.nitidez = nitidez }
    }

    public enum Problema: String, Equatable, Sendable, CaseIterable { case chica, apaisada, oscura, movida, vieja }

    /// La luz de un píxel, de 0 a 255.
    public static func luma(r: Int, g: Int, b: Int) -> Int { (r * 299 + g * 587 + b * 114) / 1000 }

    /// Mide la luz y la nitidez sobre la luma de la foto (una por píxel, por filas). `paso`: el lado del bloque que se promedia
    /// antes de medir; sin indicarlo, el que deja el lado mayor cerca de `ladoAnalisis`. Todo con enteros, para que las tres
    /// plataformas den lo mismo.
    public static func medir(luma: [UInt8], ancho: Int, alto: Int, paso: Int? = nil) -> Medida {
        guard ancho > 0, alto > 0, luma.count >= ancho * alto else { return Medida(brillo: 0, nitidez: 0) }
        let n = max(1, paso ?? (max(ancho, alto) / ladoAnalisis))
        let w = ancho / n, h = alto / n
        guard w > 0, h > 0 else { return Medida(brillo: 0, nitidez: 0) }
        var l = [Int](repeating: 0, count: w * h)
        var total = 0
        luma.withUnsafeBufferPointer { p in
            for y in 0..<h {
                for x in 0..<w {
                    var suma = 0
                    for dy in 0..<n {
                        let fila = (y * n + dy) * ancho + x * n
                        for dx in 0..<n { suma += Int(p[fila + dx]) }
                    }
                    let v = suma / (n * n)
                    l[y * w + x] = v
                    total += v
                }
            }
        }
        let brillo = Double(total) / Double(w * h)
        guard w >= 3, h >= 3 else { return Medida(brillo: brillo, nitidez: 0) }
        var horizontal = [Int](repeating: 0, count: 511), vertical = [Int](repeating: 0, count: 511)
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = 2 * l[y * w + x]
                horizontal[abs(c - l[y * w + x - 1] - l[y * w + x + 1])] += 1
                vertical[abs(c - l[(y - 1) * w + x] - l[(y + 1) * w + x])] += 1
            }
        }
        let k = max(1, ((w - 2) * (h - 2)) / 100)
        return Medida(brillo: brillo, nitidez: min(mediaDeLosMayores(horizontal, k), mediaDeLosMayores(vertical, k)))
    }

    /// La media de los `k` valores más altos de un histograma.
    private static func mediaDeLosMayores(_ histograma: [Int], _ k: Int) -> Double {
        var faltan = k, suma = 0
        for v in stride(from: histograma.count - 1, through: 0, by: -1) where histograma[v] > 0 {
            let tomo = min(faltan, histograma[v])
            suma += tomo * v
            faltan -= tomo
            if faltan == 0 { break }
        }
        return Double(suma) / Double(k)
    }

    /// Qué tiene de malo la foto, en el orden en que se muestra. `dias`: cuántos días hace que se sacó, si se sabe.
    /// En «el físico que te motiva» solo importa que no sea diminuta.
    public static func problemas(pose: String, ancho: Int, alto: Int, medida: Medida, dias: Int? = nil) -> [Problema] {
        let lado = max(ancho, alto)
        if pose == motivacion { return lado < minLadoMotivacion ? [.chica] : [] }
        var lista: [Problema] = []
        if lado < minLado { lista.append(.chica) }
        if ancho > alto { lista.append(.apaisada) }
        // Una foto oscura también mide poca nitidez: se avisa una sola cosa.
        if medida.brillo < brilloMinimo { lista.append(.oscura) } else if medida.nitidez < nitidezMinima { lista.append(.movida) }
        if let dias, dias > diasVieja { lista.append(.vieja) }
        return lista
    }

    /// Con poca resolución no se puede usar: el servidor tampoco la recibe. Lo demás se avisa y el alumno decide.
    public static func bloquea(_ problemas: [Problema]) -> Bool { problemas.contains(.chica) }

    public static func texto(_ p: Problema, dias: Int? = nil) -> String {
        switch p {
        case .chica: TextosFotosInicio.problemaChica
        case .apaisada: TextosFotosInicio.problemaApaisada
        case .oscura: TextosFotosInicio.problemaOscura
        case .movida: TextosFotosInicio.problemaMovida
        case .vieja: TextosFotosInicio.problemaVieja(dias ?? diasVieja + 1)
        }
    }

    /// Días enteros entre que se sacó y ahora (nunca negativo).
    public static func dias(desde tomada: Date, hasta ahora: Date) -> Int {
        max(0, Int(ahora.timeIntervalSince(tomada) / 86_400))
    }

    // MARK: El set

    /// Las poses del cuerpo que faltan, contando las que esperan subir.
    public static func faltan(enServidor: Set<String>, enCola: Set<String>) -> [String] {
        poses.map(\.clave).filter { !enServidor.contains($0) && !enCola.contains($0) }
    }

    /// A qué pose se pasa después de usar una foto: la primera que falte después de esa, y si no la primera que falte.
    public static func siguiente(despuesDe pose: String, faltan: [String]) -> String? {
        let orden = poses.map(\.clave)
        guard let i = orden.firstIndex(of: pose) else { return faltan.first }
        return orden[(i + 1)...].first(where: faltan.contains) ?? faltan.first { $0 != pose }
    }

    public static func puedeAgregarMotivacion(enServidor: Int, enCola: Int, maximo: Int = maxMotivacion) -> Bool {
        enServidor + enCola < maximo
    }

    /// La nota como la guarda el servidor: los caracteres de control son espacios, sin espacios en las puntas y hasta 300
    /// (contados como el servidor, por punto de código).
    public static func notaRecortada(_ s: String) -> String {
        var limpia = String.UnicodeScalarView()
        for u in s.unicodeScalars { limpia.append(u.value < 0x20 || (0x7F...0x9F).contains(u.value) ? " " : u) }
        let sinPuntas = String(limpia).trimmingCharacters(in: CharacterSet(charactersIn: " "))
        return String(String.UnicodeScalarView(sinPuntas.unicodeScalars.prefix(maxNota)))
    }

    // MARK: Subida

    public enum Accion: String, Equatable, Sendable { case ok, descartar, reintentar }
    public enum Aviso: String, Equatable, Sendable { case rechazada, tope }
    public struct Subida: Equatable, Sendable {
        public let accion: Accion
        public var aviso: Aviso?
        public var refrescar = false
    }

    /// Qué hace la cola con la respuesta de `/inicio/upload`. Todo 4xx salvo 429 es definitivo; 5xx y 429, reintentar.
    public static func clasificarSubida(status: Int, ok: Bool) -> Subida {
        switch status {
        case 200..<300: return ok ? Subida(accion: .ok) : Subida(accion: .reintentar)
        case 429: return Subida(accion: .reintentar)
        case 403: return Subida(accion: .descartar, refrescar: true)      // el link ya no sirve, o se cerró la sección
        case 409: return Subida(accion: .descartar)
        case 413: return Subida(accion: .descartar, aviso: .tope)
        case 400..<500: return Subida(accion: .descartar, aviso: .rechazada)
        default: return Subida(accion: .reintentar)
        }
    }
}

// MARK: Lo que contesta el servidor

public struct FotoInicio: Equatable, Sendable, Identifiable {
    public let id: String
    public let pose: String
    public let tomadaEn: String?
    public let ancho: Int
    public let alto: Int

    public init(id: String, pose: String, tomadaEn: String? = nil, ancho: Int = 0, alto: Int = 0) {
        self.id = id; self.pose = pose; self.tomadaEn = tomadaEn; self.ancho = ancho; self.alto = alto
    }

    init?(_ j: JSONValue) {
        guard let id = j["id"]?.comoTexto, let pose = j["pose"]?.comoTexto else { return nil }
        self.id = id; self.pose = pose
        tomadaEn = j["tomada_en"]?.comoTexto
        if case .numero(let n)? = j["ancho"] { ancho = Int(n) } else { ancho = 0 }
        if case .numero(let n)? = j["alto"] { alto = Int(n) } else { alto = 0 }
    }
}

/// `mypump_fotos_inicio_get` con `habilitado: true`. Un campo que no se entiende no rompe nada: queda lo de fábrica.
public struct EstadoFotosInicio: Equatable, Sendable {
    public var fotos: [FotoInicio]
    public var nota: String
    public let completo: Bool
    public let maxMotivacion: Int

    /// nil: no es una respuesta con `habilitado: true`.
    public init?(_ j: JSONValue) {
        guard j["habilitado"] == .bool(true) else { return nil }
        if case .lista(let l)? = j["fotos"] { fotos = l.compactMap(FotoInicio.init) } else { fotos = [] }
        nota = j["nota"]?.comoTexto ?? ""
        completo = j["completo"] == .bool(true)
        if case .numero(let n)? = j["max_motivacion"], n >= 0, n <= 20 { maxMotivacion = Int(n) } else { maxMotivacion = FotosInicio.maxMotivacion }
    }

    /// Las poses del cuerpo que ya están en el servidor.
    public var poses: Set<String> { Set(fotos.map(\.pose).filter { $0 != FotosInicio.motivacion }) }
    public var deMotivacion: [FotoInicio] { fotos.filter { $0.pose == FotosInicio.motivacion } }
    public func foto(pose: String) -> FotoInicio? { fotos.first { $0.pose == pose } }
}
