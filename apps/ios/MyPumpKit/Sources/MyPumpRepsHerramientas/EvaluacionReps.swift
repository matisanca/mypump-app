import Foundation
import MyPumpReloj

/// La evaluación del contador sobre lo exportado del modo calibración (tanda 4): por familia, qué porcentaje de series
/// queda a ±1 rep de lo cargado y el error medio. Con eso se decide en qué familias se prende el flujo final
/// (`ConfirmacionReps.habilitadas`): la meta es ±1 en el 90 % de las series, con al menos `minimoSeries`.
///
/// Por defecto vuelve a contar cada serie con el contador de hoy (así un cambio del algoritmo se mide sobre los datos
/// viejos); con `recontar: false` usa lo que contó el reloj en vivo.
///
/// Desde el 3-nov el reloj propone las reps en calibración: una serie con la propuesta aceptada sin tocar puede tener
/// la etiqueta del reloj y no la real. Esas van aparte (`aceptadas`) y NO deciden: las filas y el total que deciden
/// son solo las de etiqueta independiente (sin propuesta o corregidas a mano). Es una cuenta conservadora: si el alumno
/// solo corrige cuando el reloj se equivoca, las corregidas sobrerrepresentan los errores.
public enum EvaluacionReps {
    public static let meta = 0.9
    public static let minimoSeries = 30

    /// De dónde sale la etiqueta de una serie.
    public enum Origen: String, Sendable {
        /// El reloj no propuso (o el archivo es de antes): la etiqueta es del alumno.
        case sinPropuesta = "sin_propuesta"
        /// El reloj propuso y se confirmó otro número.
        case corregida
        /// El reloj propuso y se confirmó sin tocar: la etiqueta puede ser la del reloj.
        case aceptada

        /// La etiqueta no depende de lo que propuso el reloj.
        public var independiente: Bool { self != .aceptada }

        /// Una propuesta sin el dato de si se tocó cuenta como aceptada (del lado seguro).
        public static func de(_ e: EncabezadoSerie) -> Origen {
            guard e.propuesta != nil else { return .sinPropuesta }
            return e.corregida == true ? .corregida : .aceptada
        }
    }

    public struct Serie: Equatable, Sendable {
        public var archivo: String
        public var familia: FamiliaMovimiento
        public var ejercicio: String
        public var cargadas: Int
        public var contadas: Int
        public var calidad: Double
        /// Lo que propuso el reloj con la corona y de dónde sale la etiqueta.
        public var propuesta: Int?
        public var origen: Origen
        public var error: Int { contadas - cargadas }
        public init(archivo: String, familia: FamiliaMovimiento, ejercicio: String, cargadas: Int, contadas: Int, calidad: Double,
                    propuesta: Int? = nil, origen: Origen = .sinPropuesta) {
            self.archivo = archivo; self.familia = familia; self.ejercicio = ejercicio
            self.cargadas = cargadas; self.contadas = contadas; self.calidad = calidad
            self.propuesta = propuesta; self.origen = origen
        }
    }

    public struct Fila: Equatable, Sendable {
        public var familia: FamiliaMovimiento?
        public var series: Int
        public var exactas: Int
        public var dentroDeUno: Int
        /// Contadas − cargadas, en promedio (con signo: negativo = cuenta de menos).
        public var errorMedio: Double
        public var errorAbsolutoMedio: Double
        public var porcentajeDentroDeUno: Double { series == 0 ? 0 : Double(dentroDeUno) / Double(series) }
        /// Alcanza la meta con suficientes series.
        public var habilitable: Bool { series >= EvaluacionReps.minimoSeries && porcentajeDentroDeUno >= EvaluacionReps.meta }
    }

    public struct Informe: Equatable, Sendable {
        /// Todas las series (también las aceptadas).
        public var series: [Serie]
        /// Por familia y en total, solo las de etiqueta independiente: son las que deciden.
        public var filas: [Fila]
        public var total: Fila
        /// Las de propuesta aceptada sin tocar, por familia y en total: se muestran, no deciden.
        public var filasAceptadas: [Fila]
        public var aceptadas: Fila
        /// Cuántas series tuvieron propuesta y el alumno la corrigió.
        public var corregidas: Int
        /// Series que no se pudieron evaluar (sin conteo guardado con `recontar: false`).
        public var salteadas: Int
    }

    public static func series(_ registros: [(archivo: String, registro: ArchivoCalibracion.Registro)], recontar: Bool = true) -> (series: [Serie], salteadas: Int) {
        var salida: [Serie] = []
        var salteadas = 0
        for (archivo, r) in registros {
            let e = r.encabezado
            let conteo: ContadorReps.Resultado?
            if recontar {
                // La regla de hoy: los últimos `topeConteoSegundos` de la ventana (lo guardado en archivos viejos era otra).
                let desde = max(0, r.cuadros.count - Int(GrabadoraSerie.topeConteoSegundos * e.hz))
                conteo = ContadorReps.contar(Array(r.cuadros[desde...]), hz: e.hz)
            } else {
                conteo = e.conteo ?? e.contadas.map { ContadorReps.Resultado(reps: $0, periodo: 0, calidad: 0, senal: .ninguna, desde: 0, hasta: 0, quieto: false) }
            }
            guard let c = conteo else { salteadas += 1; continue }
            salida.append(Serie(archivo: archivo, familia: e.familia, ejercicio: e.ejercicio, cargadas: e.reps, contadas: c.reps,
                                calidad: c.calidad, propuesta: e.propuesta, origen: Origen.de(e)))
        }
        return (salida, salteadas)
    }

    public static func evaluar(_ registros: [(archivo: String, registro: ArchivoCalibracion.Registro)], recontar: Bool = true) -> Informe {
        let (s, salteadas) = series(registros, recontar: recontar)
        return informe(s, salteadas: salteadas)
    }

    public static func informe(_ s: [Serie], salteadas: Int = 0) -> Informe {
        func porFamilia(_ s: [Serie]) -> [Fila] {
            let g = Dictionary(grouping: s, by: \.familia)
            return FamiliaMovimiento.allCases.compactMap { f in g[f].map { fila($0, familia: f) } }
        }
        let independientes = s.filter(\.origen.independiente)
        let aceptadas = s.filter { !$0.origen.independiente }
        return Informe(series: s, filas: porFamilia(independientes), total: fila(independientes, familia: nil),
                       filasAceptadas: porFamilia(aceptadas), aceptadas: fila(aceptadas, familia: nil),
                       corregidas: s.filter { $0.origen == .corregida }.count, salteadas: salteadas)
    }

    static func fila(_ s: [Serie], familia: FamiliaMovimiento?) -> Fila {
        let n = s.count
        let errores = s.map(\.error)
        return Fila(familia: familia, series: n, exactas: errores.filter { $0 == 0 }.count,
                    dentroDeUno: errores.filter { abs($0) <= 1 }.count,
                    errorMedio: n == 0 ? 0 : Double(errores.reduce(0, +)) / Double(n),
                    errorAbsolutoMedio: n == 0 ? 0 : Double(errores.map(abs).reduce(0, +)) / Double(n))
    }

    /// Repite una serie grabada segundo a segundo, por el mismo camino que en vivo: qué propone y cuándo.
    public static func repetirEnVivo(_ r: ArchivoCalibracion.Registro) -> (propuesta: Int?, segundosAntesDelFin: Double?, propuestasDescartadas: Int) {
        var g = GrabadoraSerie()
        var p = PropuestaSerie()
        let base = 5_000.0, hz = r.encabezado.hz
        g.abrirVentana(en: base)
        var i = 0, prop: Int?, cuando: Double?, cambios = 0
        let finDescanso = r.encabezado.finDescanso.map { Double($0) / hz }
        var ultimoTick = 0
        while i < r.cuadros.count {
            let j = min(r.cuadros.count, i + 25)
            var ac: [MuestraEjes] = [], gi: [MuestraEjes] = []
            for k in i..<j {
                let c = r.cuadros[k], ts = base + (Double(k) + 0.5) / hz
                ac.append(MuestraEjes(t: ts, x: c.ax, y: c.ay, z: c.az))
                gi.append(MuestraEjes(t: ts, x: c.gx, y: c.gy, z: c.gz))
            }
            g.agregar(acelerometro: ac, giroscopio: gi)
            i = j
            let t = Double(i) / hz
            if Int(t) > ultimoTick {
                ultimoTick = Int(t)
                let descansando = finDescanso.map { t < $0 } ?? false
                if !descansando, let v = g.contarEnVivo(hasta: base + t), let n = p.proponer(v) {
                    if prop != nil { cambios += 1 }
                    prop = n; cuando = Double(r.cuadros.count) / hz - t
                    if ProcessInfo.processInfo.environment["DETALLE"] != nil { print(String(format: "   t=%.0f n=%d q=%.2f P=%.1f tramo %.0f-%.0f", t, n, v.calidad, v.periodo, v.desde, v.hasta)) }
                }
            }
        }
        return (prop, cuando, cambios)
    }

    /// La tabla para la terminal.
    public static func texto(_ i: Informe) -> String {
        func pct(_ x: Double) -> String { String(format: "%5.1f %%", x * 100) }
        func num(_ x: Double) -> String { String(format: "%+.2f", x) }
        func renglon(_ f: Fila, decide: Bool) -> String {
            let nombre = (f.familia?.nombre ?? "TOTAL").padding(toLength: 26, withPad: " ", startingAt: 0)
            let decision = !decide || f.familia == nil ? "" : (f.habilitable ? "sí" : (f.series < minimoSeries ? "faltan series" : "no"))
            return "\(nombre)  \(String(format: "%6d", f.series))  \(String(format: "%7d", f.exactas))  \(pct(f.porcentajeDentroDeUno))  \(num(f.errorMedio).padding(toLength: 11, withPad: " ", startingAt: 0))  \(String(format: "%10.2f", f.errorAbsolutoMedio))  \(decision)"
        }
        let cabecera = "Familia                     Series  Exactas  ±1 rep    Error medio  Error abs.  ¿Prender?"
        var l = ["Etiqueta independiente (sin propuesta del reloj o corregida a mano): DECIDEN", cabecera]
        for f in i.filas + [i.total] { l.append(renglon(f, decide: true)) }
        if i.aceptadas.series > 0 {
            l.append("")
            l.append("Propuesta del reloj aceptada sin tocar: NO deciden (la etiqueta puede ser la del reloj)")
            l.append(cabecera)
            for f in i.filasAceptadas + [i.aceptadas] { l.append(renglon(f, decide: false)) }
        }
        let conPropuesta = i.aceptadas.series + i.corregidas
        if conPropuesta > 0 {
            l.append("\(conPropuesta) series con propuesta: \(i.aceptadas.series) aceptadas sin tocar, \(i.corregidas) corregidas.")
        }
        if i.salteadas > 0 { l.append("\(i.salteadas) series sin conteo guardado (se saltearon).") }
        l.append("Meta: ±1 rep en el \(Int(meta * 100)) % de las series, con al menos \(minimoSeries) series por familia.")
        return l.joined(separator: "\n")
    }

    /// Una serie por renglón (para mirar en una planilla).
    public static func csv(_ i: Informe) -> String {
        (["archivo,familia,ejercicio,cargadas,contadas,error,calidad,propuesta,origen"] + i.series.map {
            "\($0.archivo),\($0.familia.rawValue),\"\($0.ejercicio)\",\($0.cargadas),\($0.contadas),\($0.error),\(String(format: "%.3f", $0.calidad)),\($0.propuesta.map(String.init) ?? ""),\($0.origen.rawValue)"
        }).joined(separator: "\n")
    }

    /// Los registros de unos archivos o carpetas (las carpetas, recorridas enteras).
    public static func leer(_ rutas: [URL]) -> (registros: [(archivo: String, registro: ArchivoCalibracion.Registro)], fallas: [String]) {
        var registros: [(String, ArchivoCalibracion.Registro)] = []
        var fallas: [String] = []
        let fm = FileManager.default
        var archivos: [URL] = []
        for r in rutas {
            var esCarpeta: ObjCBool = false
            guard fm.fileExists(atPath: r.path, isDirectory: &esCarpeta) else { fallas.append("\(r.path): no existe"); continue }
            if esCarpeta.boolValue {
                let e = fm.enumerator(at: r, includingPropertiesForKeys: nil)
                while let u = e?.nextObject() as? URL { if u.pathExtension == ArchivoCalibracion.extension_ { archivos.append(u) } }
            } else {
                archivos.append(r)
            }
        }
        for u in archivos.sorted(by: { $0.path < $1.path }) {
            do {
                let d = try Data(contentsOf: u)
                for r in try ArchivoCalibracion.leer(d) { registros.append((u.lastPathComponent, r)) }
            } catch {
                fallas.append("\(u.lastPathComponent): \(error)")
            }
        }
        return (registros, fallas)
    }

    /// Archivos de ejemplo con las señales sintéticas (uno por caso), para probar la herramienta sin un reloj.
    public static func escribirSinteticos(en carpeta: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        var salida: [URL] = []
        for (i, c) in SenalSintetica.casos.enumerated() {
            let conteo = ContadorReps.contar(c.cuadros)
            let enc = EncabezadoSerie(sesion: "sintetica", orden: i + 1, confirmada: 0, ejercicio: c.nombre, nombre: c.nombre,
                                      familia: c.familia, serie: 1, reps: c.reps, contadas: conteo.reps, conteo: conteo, fuente: "sintetica")
            let u = carpeta.appendingPathComponent("sintetica-\(i + 1).\(ArchivoCalibracion.extension_)")
            try ArchivoCalibracion.datos(.init(encabezado: enc, cuadros: c.cuadros)).write(to: u)
            salida.append(u)
        }
        return salida
    }
}
