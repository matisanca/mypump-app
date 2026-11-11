import Foundation
import MyPumpModelos

/// Todo lo que lee el alumno de sus controles de salud, en un solo lugar (gemelo de Android y de la web; los vectores de
/// `apps/shared/vectores/controles.json` hacen fallar las pruebas si difieren). Nunca el ciclo, fármacos ni «IA»: solo
/// «Mati» y «control de salud».
public enum TextosControles {
    public static let cejaInicio = "Control de salud"
    public static let tituloInicio = "Tu próximo control de salud"
    public static let verMisEstudios = "Ver mis estudios"
    public static let notaProgramado = "Te vamos a mandar las órdenes unos días antes."
    public static let notaOrdenes = "Ya te mandamos las órdenes. Están más abajo, en Tus órdenes."
    /// Con las órdenes mandadas por fuera de la app: no hay «Tus órdenes» a la que mandarlo.
    public static let notaOrdenesSinLista = "Ya te mandamos las órdenes."
    public static let tituloPorDefecto = "Control de salud"
    public static let hitosTitulo = "Tus controles de salud"
    public static let hitoProximo = "Próximo"
    public static let hitoRecibido = "Recibido"
    public static let hitoVisto = "Mati lo vio"
}

/// «Tu próximo control de salud» (pedido de Mati, 11/11; palanca `controles_app`): la lógica pura de lo que devuelve
/// `mypump_controles_get` (`supabase/propuestas/nativa_controles_salud.sql`). La app solo lee: no escribe nada.
public enum Controles {
    public static let tituloMax = 60

    public enum Estado: Equatable, Sendable {
        case programado, ordenesEnviadas, resultadoSubido, revisado
        /// Un estado que esta versión no conoce: el control se muestra en Estudios, sin nota y nunca arriba.
        case otro

        init(_ texto: String?) {
            switch texto {
            // Sin el campo: lo más común y lo que el servidor pone por defecto.
            case nil, "programado": self = .programado
            case "ordenes_enviadas": self = .ordenesEnviadas
            case "resultado_subido": self = .resultadoSubido
            case "revisado": self = .revisado
            default: self = .otro
            }
        }

        var cerrado: Bool { self == .resultadoSubido || self == .revisado }
    }

    public struct Control: Equatable, Sendable {
        public let titulo: String
        public let fecha: Estudios.Dia
        public let avisarDesde: Estudios.Dia?
        public let estado: Estado

        init?(_ j: JSONValue) {
            guard case .objeto = j, let f = Estudios.Dia(j["fecha_objetivo"]?.comoTexto) else { return nil }
            titulo = Controles.titulo(j["titulo_alumno"]?.comoTexto)
            fecha = f
            avisarDesde = Estudios.Dia(j["avisar_desde"]?.comoTexto)
            estado = Estado(j["estado"]?.comoTexto)
        }
    }

    // MARK: Título

    static let prohibidas: Set<String> = ["ciclo", "ciclos", "posciclo", "posciclos", "postciclo", "postciclos", "pct", "trt", "blast",
                                          "cruise", "nandrolona", "trembolona", "oxandrolona", "estanozolol", "primobolan", "boldenona",
                                          "masteron", "sarm", "sarms", "peptido", "peptidos", "dosis", "mg", "ml", "ui", "ia"]
    static let prefijos = ["farmac", "testo", "esteroid", "anabolic", "androgen", "hormona"]

    /// El título del servidor, si es corto y no nombra nada del ciclo (el servidor ya lo controla: esto es la segunda llave).
    /// Si no, «Control de salud».
    public static func titulo(_ s: String?) -> String {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t.unicodeScalars.count <= tituloMax else { return TextosControles.tituloPorDefecto }
        let plano = t.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es"))
        let palabras = plano.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        let malo = palabras.contains { p in prohibidas.contains(p) || prefijos.contains(where: p.hasPrefix) }
            || plano.contains("inteligencia artificial")
        return malo ? TextosControles.tituloPorDefecto : t
    }

    // MARK: Fechas

    /// «lunes 16/11», con el año si no es el de hoy: «lunes 4/1/2027».
    public static func conDia(_ d: Estudios.Dia, hoy: Estudios.Dia?) -> String {
        hoy.map { $0.anio != d.anio } == true ? "\(d.conDia)/\(d.anio)" : d.conDia
    }

    /// «El lunes 16/11» o, si ya pasó, «Era para el lunes 9/11» (sin tono de alarma).
    public static func cuando(_ d: Estudios.Dia, hoy: Estudios.Dia?) -> String {
        if let hoy, d < hoy { return "Era para el \(conDia(d, hoy: hoy))" }
        return "El \(conDia(d, hoy: hoy))"
    }

    static func nota(_ e: Estado, hayOrdenes: Bool) -> String? {
        switch e {
        case .programado: TextosControles.notaProgramado
        case .ordenesEnviadas: hayOrdenes ? TextosControles.notaOrdenes : TextosControles.notaOrdenesSinLista
        default: nil
        }
    }

    // MARK: Lo que muestra la app

    /// El bloque «Próximo control» de Estudios, alimentado por el control. nil sin próximo. `hayOrdenes`: si Estudios muestra
    /// «Tus órdenes» (si no, la nota no manda a buscarlas ahí).
    public static func proximoParaEstudios(_ e: EstadoControles, hayOrdenes: Bool = true) -> ProximoControl? {
        guard let c = e.proximo else { return nil }
        return ProximoControl(titulo: c.titulo, cuando: cuando(c.fecha, hoy: e.hoy), nota: nota(c.estado, hayOrdenes: hayOrdenes))
    }

    public struct TarjetaInicio: Equatable, Sendable {
        public let titulo: String
        public let cuando: String
        public let nota: String
        public let boton: String

        public init(titulo: String, cuando: String, nota: String, boton: String) {
            self.titulo = titulo; self.cuando = cuando; self.nota = nota; self.boton = boton
        }
    }

    /// La tarjeta de arriba de la primera pestaña: desde `avisar_desde` y mientras siga `programado`. `hoyTelefono` cuenta
    /// solo si el servidor no mandó `hoy`; sin ninguno de los dos, no se muestra (mejor nada que antes de tiempo).
    public static func tarjetaInicio(_ e: EstadoControles, hoyTelefono: Estudios.Dia?) -> TarjetaInicio? {
        guard let c = e.proximo, c.estado == .programado, let desde = c.avisarDesde, let hoy = e.hoy ?? hoyTelefono, desde <= hoy else { return nil }
        return TarjetaInicio(titulo: TextosControles.tituloInicio, cuando: cuando(c.fecha, hoy: hoy), nota: TextosControles.notaProgramado,
                             boton: TextosControles.verMisEstudios)
    }

    public struct Hito: Equatable, Sendable {
        public let titulo: String
        public let cuando: String
        public let estado: String
    }

    /// «Tu recorrido»: el próximo y los últimos, cada uno con su fecha.
    public static func hitos(_ e: EstadoControles) -> [Hito] {
        let proximo = e.proximo.map { Hito(titulo: $0.titulo, cuando: conDia($0.fecha, hoy: e.hoy), estado: TextosControles.hitoProximo) }
        let pasados = e.ultimos.map {
            Hito(titulo: $0.titulo, cuando: conDia($0.fecha, hoy: e.hoy), estado: $0.estado == .revisado ? TextosControles.hitoVisto : TextosControles.hitoRecibido)
        }
        return (proximo.map { [$0] } ?? []) + pasados
    }

    /// La fecha de hoy en el teléfono (solo si el servidor no la manda).
    public static func hoyDelTelefono(_ ahora: Date = Date(), zona: TimeZone = .current) -> Estudios.Dia? {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        let k = c.dateComponents([.year, .month, .day], from: ahora)
        guard let a = k.year, let m = k.month, let d = k.day else { return nil }
        return Estudios.Dia(String(format: "%04d-%02d-%02d", a, m, d))
    }
}

/// Lo que devuelve `mypump_controles_get` con `habilitado: true`. Todo campo es opcional; lo que no se entiende se descarta.
public struct EstadoControles: Equatable, Sendable {
    public let hoy: Estudios.Dia?
    /// El próximo: programado u órdenes enviadas (o un estado nuevo). Uno ya cerrado no es próximo.
    public let proximo: Controles.Control?
    /// Hasta 3, resultado subido o revisado, en el orden del servidor (del más nuevo al más viejo).
    public let ultimos: [Controles.Control]

    /// nil: token caído, palanca apagada en el servidor o una respuesta que no es la esperada.
    public init?(_ j: JSONValue) {
        guard j["habilitado"] == .bool(true) else { return nil }
        hoy = Estudios.Dia(j["hoy"]?.comoTexto)
        proximo = j["proximo"].flatMap(Controles.Control.init).flatMap { $0.estado.cerrado ? nil : $0 }
        let lista: [JSONValue] = if case .lista(let l)? = j["ultimos"] { l } else { [] }
        ultimos = Array(lista.compactMap(Controles.Control.init).filter(\.estado.cerrado).prefix(3))
    }
}
