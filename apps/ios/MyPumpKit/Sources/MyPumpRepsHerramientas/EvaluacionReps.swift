import Foundation
import MyPumpReloj

/// La evaluación del contador sobre lo exportado del modo calibración (tanda 4): por familia, qué porcentaje de series
/// queda a ±1 rep de lo cargado y el error medio. Con eso se decide en qué familias se prende el flujo final
/// (`ConfirmacionReps.habilitadas`): la meta es ±1 en el 90 % de las series, con al menos `minimoSeries`.
///
/// Por defecto vuelve a contar cada serie con el contador de hoy (así un cambio del algoritmo se mide sobre los datos
/// viejos); con `recontar: false` usa lo que contó el reloj en vivo.
public enum EvaluacionReps {
    public static let meta = 0.9
    public static let minimoSeries = 30

    public struct Serie: Equatable, Sendable {
        public var archivo: String
        public var familia: FamiliaMovimiento
        public var ejercicio: String
        public var cargadas: Int
        public var contadas: Int
        public var calidad: Double
        public var error: Int { contadas - cargadas }
        public init(archivo: String, familia: FamiliaMovimiento, ejercicio: String, cargadas: Int, contadas: Int, calidad: Double) {
            self.archivo = archivo; self.familia = familia; self.ejercicio = ejercicio
            self.cargadas = cargadas; self.contadas = contadas; self.calidad = calidad
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
        public var series: [Serie]
        public var filas: [Fila]
        public var total: Fila
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
                let desde = min(max(0, e.inicioConteo), r.cuadros.count)
                conteo = ContadorReps.contar(Array(r.cuadros[desde...]), hz: e.hz)
            } else {
                conteo = e.conteo ?? e.contadas.map { ContadorReps.Resultado(reps: $0, periodo: 0, calidad: 0, senal: .ninguna, desde: 0, hasta: 0, quieto: false) }
            }
            guard let c = conteo else { salteadas += 1; continue }
            salida.append(Serie(archivo: archivo, familia: e.familia, ejercicio: e.ejercicio, cargadas: e.reps, contadas: c.reps, calidad: c.calidad))
        }
        return (salida, salteadas)
    }

    public static func evaluar(_ registros: [(archivo: String, registro: ArchivoCalibracion.Registro)], recontar: Bool = true) -> Informe {
        let (s, salteadas) = series(registros, recontar: recontar)
        return informe(s, salteadas: salteadas)
    }

    public static func informe(_ s: [Serie], salteadas: Int = 0) -> Informe {
        let porFamilia = Dictionary(grouping: s, by: \.familia)
        let filas = FamiliaMovimiento.allCases.compactMap { f in porFamilia[f].map { fila($0, familia: f) } }
        return Informe(series: s, filas: filas, total: fila(s, familia: nil), salteadas: salteadas)
    }

    static func fila(_ s: [Serie], familia: FamiliaMovimiento?) -> Fila {
        let n = s.count
        let errores = s.map(\.error)
        return Fila(familia: familia, series: n, exactas: errores.filter { $0 == 0 }.count,
                    dentroDeUno: errores.filter { abs($0) <= 1 }.count,
                    errorMedio: n == 0 ? 0 : Double(errores.reduce(0, +)) / Double(n),
                    errorAbsolutoMedio: n == 0 ? 0 : Double(errores.map(abs).reduce(0, +)) / Double(n))
    }

    /// La tabla para la terminal.
    public static func texto(_ i: Informe) -> String {
        func pct(_ x: Double) -> String { String(format: "%5.1f %%", x * 100) }
        func num(_ x: Double) -> String { String(format: "%+.2f", x) }
        var l = ["Familia                     Series  Exactas  ±1 rep    Error medio  Error abs.  ¿Prender?"]
        for f in i.filas + [i.total] {
            let nombre = (f.familia?.nombre ?? "TOTAL").padding(toLength: 26, withPad: " ", startingAt: 0)
            let decision = f.familia == nil ? "" : (f.habilitable ? "sí" : (f.series < minimoSeries ? "faltan series" : "no"))
            l.append("\(nombre)  \(String(format: "%6d", f.series))  \(String(format: "%7d", f.exactas))  \(pct(f.porcentajeDentroDeUno))  \(num(f.errorMedio).padding(toLength: 11, withPad: " ", startingAt: 0))  \(String(format: "%10.2f", f.errorAbsolutoMedio))  \(decision)")
        }
        if i.salteadas > 0 { l.append("\(i.salteadas) series sin conteo guardado (se saltearon).") }
        l.append("Meta: ±1 rep en el \(Int(meta * 100)) % de las series, con al menos \(minimoSeries) series por familia.")
        return l.joined(separator: "\n")
    }

    /// Una serie por renglón (para mirar en una planilla).
    public static func csv(_ i: Informe) -> String {
        (["archivo,familia,ejercicio,cargadas,contadas,error,calidad"] + i.series.map {
            "\($0.archivo),\($0.familia.rawValue),\"\($0.ejercicio)\",\($0.cargadas),\($0.contadas),\($0.error),\(String(format: "%.3f", $0.calidad))"
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
