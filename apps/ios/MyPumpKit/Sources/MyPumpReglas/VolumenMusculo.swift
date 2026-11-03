import Foundation

/// Volumen por músculo (2.1, S2): las series efectivas de cada músculo en la semana (de lunes a domingo, como el check),
/// con la semana pasada al lado y lo de hoy aparte (el cierre del día). Todos los números y las listas viven acá (y en
/// el gemelo de Android, VolumenMusculo.kt); lo verifican los vectores de `apps/shared/vectores/volumen.json`.
///
/// - Cuenta cada serie registrada (una fila del historial o una serie confirmada hoy). Las de preparación nunca se
///   registran, así que no cuentan; tampoco el cardio ni el calentamiento (`tiposQueNoCuentan`).
/// - El músculo es el principal del catálogo del ejercicio que se hizo, con la misma cadena que la preparación (E1): el
///   del sustituto si el catálogo lo tiene y si no `CatalogoEjercicios.resolver` (catalogo_slug → matched → reglas y
///   nombre). Sin músculo, o uno que no está en `orden`, va a «Sin músculo asignado» (el respaldo conservador: no se
///   inventa un músculo) y queda al final.
/// - Una misma serie (lugar + fecha + número) cuenta una sola vez. Si se pasa lo de hoy en vivo (`hoyEnVivo`), lo del
///   historial con fecha de hoy no se usa: lo de hoy sale de lo confirmado en el teléfono. Una fecha que no sea
///   YYYY-MM-DD exacto no cuenta.
/// - Orden: más series esta semana, después más la semana pasada, después el orden del catálogo (`orden`).
public enum VolumenMusculo {
    /// No son series efectivas de un músculo.
    public static let tiposQueNoCuentan: Set<String> = ["cardio", "calentamiento"]
    /// Los músculos del catálogo, en el orden que desempata (el de `SustitucionEjercicios.musculo`).
    public static let orden = ["quadriceps", "shoulders", "abdominals", "chest", "hamstrings", "triceps", "biceps", "lats",
                               "middle back", "calves", "lower back", "forearms", "glutes", "traps", "adductors", "neck", "abductors"]
    public static let sinMusculo = "Sin músculo asignado"

    /// Una serie registrada.
    public struct Registro: Equatable, Sendable {
        /// El músculo principal del catálogo (nil = el catálogo no lo tiene).
        public var musculo: String?
        public var tipo: String?
        /// Fecha local, YYYY-MM-DD.
        public var fecha: String
        /// El lugar del plan (o la clave si no se sabe): con `serie`, identifica la serie.
        public var lugar: String
        public var serie: Int?
        public init(musculo: String?, tipo: String?, fecha: String, lugar: String, serie: Int?) {
            self.musculo = musculo; self.tipo = tipo; self.fecha = fecha; self.lugar = lugar; self.serie = serie
        }
    }

    public struct Fila: Equatable, Sendable, Identifiable {
        /// El del catálogo, normalizado; nil = sin músculo asignado.
        public let musculo: String?
        public let nombre: String
        public let semana: Int
        public let anterior: Int
        public let hoy: Int
        public var id: String { musculo ?? "-" }
        public init(musculo: String?, nombre: String, semana: Int, anterior: Int, hoy: Int) {
            self.musculo = musculo; self.nombre = nombre; self.semana = semana; self.anterior = anterior; self.hoy = hoy
        }

        /// «Pecho, 12 series esta semana, 10 la semana pasada».
        public var textoAccesible: String {
            "\(nombre), \(VolumenMusculo.series(semana)) esta semana, \(anterior) la semana pasada"
        }
    }

    public struct Resumen: Equatable, Sendable {
        /// El lunes de esta semana.
        public let semana: String
        public let filas: [Fila]
        public let total: Int
        public let totalAnterior: Int
        public let totalHoy: Int

        /// Lo de hoy (el cierre del día): los músculos con series hoy, más series primero.
        public var filasDeHoy: [Fila] {
            filas.filter { $0.hoy > 0 }.enumerated().sorted { a, b in
                a.element.hoy != b.element.hoy ? a.element.hoy > b.element.hoy : a.offset < b.offset
            }.map(\.element)
        }
        /// El máximo de series de un músculo en las dos semanas (la escala de las barras).
        public var tope: Int { filas.map { max($0.semana, $0.anterior) }.max() ?? 0 }
    }

    /// «1 serie», «12 series».
    public static func series(_ n: Int) -> String { n == 1 ? "1 serie" : "\(n) series" }

    /// El músculo normalizado si es uno del catálogo; nil si no.
    public static func normalizar(_ m: String?) -> String? {
        guard let m = m?.trimmingCharacters(in: .whitespaces).lowercased(), orden.contains(m) else { return nil }
        return m
    }

    /// «Pecho», «Espalda media»; sin músculo, «Sin músculo asignado».
    public static func nombre(_ m: String?) -> String {
        guard let n = SustitucionEjercicios.musculo(normalizar(m)) else { return sinMusculo }
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    public static func calcular(historial: [Registro], hoyEnVivo: [Registro]? = nil, hoy: String) -> Resumen {
        let lunes = FotosProgreso.lunes(hoy)
        let anterior = DiaCalendario.numero(lunes).map { DiaCalendario.texto($0 - 7) } ?? ""
        var regs = historial
        if let vivo = hoyEnVivo {
            regs = historial.filter { $0.fecha != hoy } + vivo.map { var r = $0; r.fecha = hoy; return r }
        }
        var vistos = Set<String>()
        var cuenta: [String: (semana: Int, anterior: Int, hoy: Int)] = [:]
        for r in regs {
            if let t = r.tipo, tiposQueNoCuentan.contains(t) { continue }
            guard r.fecha.count == 10, DiaCalendario.numero(r.fecha) != nil else { continue }
            if let s = r.serie, !vistos.insert("\(r.lugar)|\(r.fecha)|\(s)").inserted { continue }
            let semanaDe = FotosProgreso.lunes(r.fecha)
            let clave = normalizar(r.musculo) ?? ""
            var c = cuenta[clave] ?? (0, 0, 0)
            if semanaDe == lunes {
                c.semana += 1
                if r.fecha == hoy { c.hoy += 1 }
            } else if semanaDe == anterior {
                c.anterior += 1
            } else { continue }
            cuenta[clave] = c
        }
        func rango(_ m: String) -> Int { m.isEmpty ? orden.count : orden.firstIndex(of: m) ?? orden.count }
        let filas = cuenta.sorted { a, b in
            if a.value.semana != b.value.semana { return a.value.semana > b.value.semana }
            if a.value.anterior != b.value.anterior { return a.value.anterior > b.value.anterior }
            return rango(a.key) < rango(b.key)
        }.map { k, v in
            Fila(musculo: k.isEmpty ? nil : k, nombre: nombre(k.isEmpty ? nil : k), semana: v.semana, anterior: v.anterior, hoy: v.hoy)
        }
        // Sin músculo, siempre al final.
        let ordenadas = filas.filter { $0.musculo != nil } + filas.filter { $0.musculo == nil }
        return Resumen(semana: lunes, filas: ordenadas, total: ordenadas.map(\.semana).reduce(0, +),
                       totalAnterior: ordenadas.map(\.anterior).reduce(0, +), totalHoy: ordenadas.map(\.hoy).reduce(0, +))
    }
}
