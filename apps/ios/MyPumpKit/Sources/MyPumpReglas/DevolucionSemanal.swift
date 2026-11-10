import Foundation
import MyPumpModelos

/// Una devolución publicada de Mati: 3 a 5 líneas sobre la semana. Solo llega lo publicado (`mypump_devolucion_get`).
public struct DevolucionSemanal: Equatable, Sendable, Identifiable {
    public let id: String
    /// AAAA-MM-DD, el lunes de la semana que comenta.
    public let semanaLunes: String
    public let lineas: [String]
    /// AAAA-MM-DD de cuando salió (UTC, tal como lo manda el servidor); nil si no vino.
    public let publicadaDia: String?

    public init?(_ j: JSONValue) {
        guard let id = j["id"]?.comoTexto, !id.isEmpty,
              let semana = j["semana_lunes"]?.comoTexto, ReglasDevolucion.fecha(semana) != nil,
              let texto = j["texto"]?.comoTexto else { return nil }
        let lineas = texto.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lineas.isEmpty else { return nil }
        self.id = id; semanaLunes = semana; self.lineas = lineas
        publicadaDia = j["publicado_en"]?.comoTexto.map { String($0.prefix(10)) }.flatMap { ReglasDevolucion.fecha($0) != nil ? $0 : nil }
    }

    public var etiqueta: String { ReglasDevolucion.etiqueta(semanaLunes) }
}

/// Lo que muestra Revisión: la última arriba y las anteriores debajo. nil (apagada, sin token o sin habilitar): no se
/// muestra nada. Habilitada y sin ninguna: tampoco se muestra nada, pero la sección existe.
public struct EstadoDevolucion: Equatable, Sendable {
    public let devoluciones: [DevolucionSemanal]

    public static let maximo = 12

    public init(devoluciones: [DevolucionSemanal]) { self.devoluciones = devoluciones }

    public init?(_ j: JSONValue) {
        guard j["habilitado"] == .bool(true) else { return nil }
        var vistas = Set<String>()
        var lista: [DevolucionSemanal] = []
        if case .lista(let l)? = j["devoluciones"] {
            // Orden estable por semana, de la más nueva a la más vieja; una sola por semana (la primera que vino).
            let validas = l.compactMap(DevolucionSemanal.init).enumerated()
                .sorted { $0.element.semanaLunes != $1.element.semanaLunes ? $0.element.semanaLunes > $1.element.semanaLunes : $0.offset < $1.offset }
            for (_, d) in validas where vistas.insert(d.semanaLunes).inserted { lista.append(d) }
        }
        devoluciones = Array(lista.prefix(Self.maximo))
    }

    public var ultima: DevolucionSemanal? { devoluciones.first }
    public var anteriores: [DevolucionSemanal] { Array(devoluciones.dropFirst()) }
}

public enum ReglasDevolucion {
    private static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
                                "noviembre", "diciembre"]

    /// (año, mes, día) de un AAAA-MM-DD que existe; nil si no.
    static func fecha(_ s: String) -> (Int, Int, Int)? {
        let p = s.split(separator: "-")
        guard s.count == 10, p.count == 3, let a = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return nil }
        var c = DateComponents(); c.year = a; c.month = m; c.day = d
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let f = cal.date(from: c), cal.component(.day, from: f) == d, cal.component(.month, from: f) == m else { return nil }
        return (a, m, d)
    }

    /// «Semana del 9 de noviembre»; con el año si no es el de hoy.
    public static func etiqueta(_ semana: String, hoy: String = FechaLocal.hoy()) -> String {
        guard let (a, m, d) = fecha(semana) else { return "Tu semana" }
        let anioHoy = fecha(hoy)?.0 ?? a
        return "Semana del \(d) de \(meses[m - 1])" + (a == anioHoy ? "" : " de \(a)")
    }

    /// Recién llegada: publicada hoy o en los dos días anteriores.
    public static func esNueva(_ d: DevolucionSemanal, hoy: String = FechaLocal.hoy()) -> Bool {
        guard let p = d.publicadaDia, let dias = diasEntre(p, hoy) else { return false }
        return (0...2).contains(dias)
    }

    static func diasEntre(_ desde: String, _ hasta: String) -> Int? {
        guard let a = fecha(desde), let b = fecha(hasta) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func f(_ x: (Int, Int, Int)) -> Date? { var c = DateComponents(); c.year = x.0; c.month = x.1; c.day = x.2; return cal.date(from: c) }
        guard let fa = f(a), let fb = f(b) else { return nil }
        return cal.dateComponents([.day], from: fa, to: fb).day
    }
}
