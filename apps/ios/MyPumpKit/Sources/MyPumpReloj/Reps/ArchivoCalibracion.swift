import Foundation

/// Las series grabadas en el modo calibración (tanda 4), en un formato compacto y concatenable: un archivo `.mpcal` es
/// una sucesión de registros, uno por serie, y pegar dos archivos da un archivo válido (así el iPhone junta las series
/// que le llegan del reloj de a una en un archivo por sesión).
///
/// Un registro:
/// - `MPC1` (4 bytes)
/// - largo del encabezado (UInt32, little endian) + el encabezado en JSON (`EncabezadoSerie`)
/// - largo de los datos (UInt32, little endian) + los datos: los cuadros a 100 Hz como Int16 little endian intercalados
///   (`ax ay az gx gy gz`), con la escala del encabezado (0,5 mg y 1 mrad/s por unidad), comprimidos con zlib (deflate
///   crudo: en Python, `zlib.decompress(datos, -15)`).
///
/// Lo que NO va: el token, la cuenta ni el nombre del alumno. Va el ejercicio (nombre y clave), las reps y el kg
/// cargados, lo que contó el contador, lo que propuso con la corona (y si el alumno lo tocó) y la fecha.
public enum ArchivoCalibracion {
    public static let magia = Data("MPC1".utf8)
    public static let extension_ = "mpcal"
    public static let escalaAcel: Double = 0.0005
    public static let escalaGiro: Double = 0.001

    public enum Fallo: Error, Equatable { case corto, magia, encabezado, datos }

    public struct Registro: Equatable, Sendable {
        public var encabezado: EncabezadoSerie
        public var cuadros: [CuadroSensor]
        public init(encabezado: EncabezadoSerie, cuadros: [CuadroSensor]) { self.encabezado = encabezado; self.cuadros = cuadros }
    }

    /// Un registro listo para escribir.
    public static func datos(_ r: Registro) throws -> Data {
        var enc = r.encabezado
        enc.muestras = r.cuadros.count
        enc.escalaAcel = escalaAcel
        enc.escalaGiro = escalaGiro
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.sortedKeys]
        let json = try codificador.encode(enc)
        var crudo = Data(capacity: r.cuadros.count * 12)
        func poner(_ v: Float, _ escala: Double) {
            let q = Int16(clamping: Int((Double(v) / escala).rounded()))
            withUnsafeBytes(of: q.littleEndian) { crudo.append(contentsOf: $0) }
        }
        for c in r.cuadros {
            poner(c.ax, escalaAcel); poner(c.ay, escalaAcel); poner(c.az, escalaAcel)
            poner(c.gx, escalaGiro); poner(c.gy, escalaGiro); poner(c.gz, escalaGiro)
        }
        let comprimido = try (crudo as NSData).compressed(using: .zlib) as Data
        var d = magia
        anexar(UInt32(json.count), a: &d); d.append(json)
        anexar(UInt32(comprimido.count), a: &d); d.append(comprimido)
        return d
    }

    /// Todos los registros de un archivo. Un registro roto al final (una escritura cortada) corta la lectura ahí: se
    /// devuelven los anteriores.
    public static func leer(_ d: Data) throws(Fallo) -> [Registro] {
        var registros: [Registro] = []
        var i = d.startIndex
        while i < d.endIndex {
            do throws(Fallo) {
                let (r, siguiente) = try registro(d, desde: i)
                registros.append(r)
                i = siguiente
            } catch {
                if registros.isEmpty { throw error }
                break
            }
        }
        return registros
    }

    /// Solo los encabezados (para listar sin descomprimir).
    public static func encabezados(_ d: Data) -> [EncabezadoSerie] {
        var salida: [EncabezadoSerie] = []
        var i = d.startIndex
        while i < d.endIndex, let (e, _, siguiente) = try? partes(d, desde: i) {
            salida.append(e)
            i = siguiente
        }
        return salida
    }

    static func registro(_ d: Data, desde i: Data.Index) throws(Fallo) -> (Registro, Data.Index) {
        let (enc, datos, siguiente) = try partes(d, desde: i)
        guard let crudo = try? (datos as NSData).decompressed(using: .zlib) as Data, crudo.count == enc.muestras * 12 else { throw .datos }
        let ea = enc.escalaAcel ?? escalaAcel, eg = enc.escalaGiro ?? escalaGiro
        var cuadros: [CuadroSensor] = []
        cuadros.reserveCapacity(enc.muestras)
        crudo.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            func v(_ k: Int) -> Double { Double(Int16(littleEndian: p.loadUnaligned(fromByteOffset: k * 2, as: Int16.self))) }
            for m in 0..<enc.muestras {
                let b = m * 6
                cuadros.append(CuadroSensor(ax: Float(v(b) * ea), ay: Float(v(b + 1) * ea), az: Float(v(b + 2) * ea),
                                            gx: Float(v(b + 3) * eg), gy: Float(v(b + 4) * eg), gz: Float(v(b + 5) * eg)))
            }
        }
        return (Registro(encabezado: enc, cuadros: cuadros), siguiente)
    }

    static func partes(_ d: Data, desde i: Data.Index) throws(Fallo) -> (EncabezadoSerie, Data, Data.Index) {
        guard d.endIndex - i >= 8 else { throw .corto }
        guard d[i..<(i + 4)] == magia else { throw .magia }
        var j = i + 4
        let lj = Int(leerU32(d, j)); j += 4
        guard d.endIndex - j >= lj + 4 else { throw .corto }
        guard let enc = try? JSONDecoder().decode(EncabezadoSerie.self, from: d[j..<(j + lj)]) else { throw .encabezado }
        j += lj
        let ld = Int(leerU32(d, j)); j += 4
        guard d.endIndex - j >= ld else { throw .corto }
        return (enc, Data(d[j..<(j + ld)]), j + ld)
    }

    static func anexar(_ v: UInt32, a d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    static func leerU32(_ d: Data, _ i: Data.Index) -> UInt32 {
        UInt32(d[i]) | UInt32(d[i + 1]) << 8 | UInt32(d[i + 2]) << 16 | UInt32(d[i + 3]) << 24
    }
}

/// Lo que se sabe de una serie grabada.
public struct EncabezadoSerie: Codable, Equatable, Sendable {
    /// Versión del formato.
    public var v: Int = 1
    /// La sesión: fecha, semana y un id corto al azar por día de entreno, guardado en el reloj.
    public var sesion: String
    /// El número de serie dentro de la sesión (1, 2, 3…).
    public var orden: Int
    /// ms desde 1970: cuándo se confirmó.
    public var confirmada: Double
    /// La clave del ejercicio (`ClaveEjercicio.de`), el nombre como se ve, la familia y el equipo.
    public var ejercicio: String
    public var nombre: String
    public var familia: FamiliaMovimiento
    public var patron: String?
    public var equipo: String?
    /// El número de serie del ejercicio (1 = la primera efectiva).
    public var serie: Int
    /// Las reps confirmadas (la etiqueta) y el kg.
    public var reps: Int
    public var kg: Double?
    /// Lo que contó el contador en vivo al confirmar (nil si no corrió).
    public var contadas: Int?
    public var conteo: ContadorReps.Resultado?
    /// Lo que propuso el reloj con la corona en esta serie (nil = no propuso; los archivos de antes del 3-nov no lo traen)
    /// y si lo confirmado difiere de lo propuesto (nil sin propuesta). Con `propuesta` y `corregida == false`, la etiqueta
    /// puede ser la del reloj: `evaluar-reps` la cuenta aparte.
    public var propuesta: Int?
    public var corregida: Bool?
    /// La grilla de los cuadros.
    public var hz: Double = GrabadoraSerie.hz
    public var muestras: Int = 0
    public var escalaAcel: Double?
    public var escalaGiro: Double?
    /// Desde qué cuadro cuenta el contador y en qué cuadro terminó el descanso (si terminó en la ventana).
    public var inicioConteo: Int
    public var finDescanso: Int?
    /// Segundos del principio de la ventana que no entraron en el anillo.
    public var recortado: Double = 0
    /// "batched" (`CMBatchedSensorManager`: 800 Hz de aceleración y 200 de giro, promediados a 100) o "motion"
    /// (`CMMotionManager` a 100 Hz).
    public var fuente: String
    /// La muñeca y el lado de la corona (`WKInterfaceDevice`): "izquierda"/"derecha".
    public var muneca: String?
    public var corona: String?

    public init(sesion: String, orden: Int, confirmada: Double, ejercicio: String, nombre: String, familia: FamiliaMovimiento,
                patron: String? = nil, equipo: String? = nil, serie: Int, reps: Int, kg: Double? = nil, contadas: Int? = nil,
                conteo: ContadorReps.Resultado? = nil, propuesta: Int? = nil, corregida: Bool? = nil, inicioConteo: Int = 0, finDescanso: Int? = nil, recortado: Double = 0,
                fuente: String, muneca: String? = nil, corona: String? = nil) {
        self.sesion = sesion; self.orden = orden; self.confirmada = confirmada; self.ejercicio = ejercicio; self.nombre = nombre
        self.familia = familia; self.patron = patron; self.equipo = equipo; self.serie = serie; self.reps = reps; self.kg = kg
        self.contadas = contadas; self.conteo = conteo; self.propuesta = propuesta; self.corregida = corregida
        self.inicioConteo = inicioConteo; self.finDescanso = finDescanso
        self.recortado = recortado; self.fuente = fuente; self.muneca = muneca; self.corona = corona
    }
}
