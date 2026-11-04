import Foundation
import MyPumpModelos

/// La pestaña Suplementación (2.1.0, `mypump_suplementacion`). La agrupación por momento es la de «Tu guía»
/// (`VistaSuplementacion`): así la guía y la pestaña muestran el mismo día. Acá va solo lo que la pestaña suma: la
/// etiqueta de estado, los días y la dosis anterior.
public enum ReglasSuplementacion {
    /// Los estados del contrato (sección 10). Se comparan exactos, como «sale» en la guía y en la web.
    public enum Estado: String, Sendable, CaseIterable {
        case nuevo, sigue, cambia, sube, baja, vuelve, sale

        public var texto: String {
            switch self {
            case .nuevo: "Nuevo"
            case .sigue: "Sigue igual"
            case .cambia: "Cambia"
            case .sube: "Sube"
            case .baja: "Baja"
            case .vuelve: "Vuelve"
            case .sale: "Dejás de tomar"
            }
        }

        /// «sigue» va discreta: lo que pide atención es lo que cambia.
        public var destacada: Bool { self != .sigue }
    }

    /// El estado de un ítem: si falta, `nuevo` (contrato). Uno que no se conoce (de un esquema más nuevo) va sin etiqueta.
    public static func estado(_ e: String?) -> Estado? {
        guard let e, !e.isEmpty else { return .nuevo }
        return Estado(rawValue: e)
    }

    /// `dias` para el cliente: nil = todos los días (`"todos"`, ausente o vacío). `"gym"` = «Días de entreno»,
    /// `"descanso"` = «Días de descanso», y los días de la semana por su nombre («Lunes, miércoles y viernes»). Lo que no
    /// se reconoce se muestra tal cual.
    public static func textoDias(_ dias: [String]) -> String? {
        let partes = dias.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !partes.isEmpty, !partes.contains(where: { clave($0) == "todos" }) else { return nil }
        var textos: [String] = []
        for p in partes {
            let t: String
            switch clave(p) {
            case "gym", "entreno", "entrenamiento": t = "días de entreno"
            case "descanso": t = "días de descanso"
            default: t = diaDeLaSemana(p) ?? p
            }
            if !textos.contains(t) { textos.append(t) }
        }
        let junto = textos.count > 1 ? textos.dropLast().joined(separator: ", ") + " y " + textos.last! : textos[0]
        return junto.prefix(1).uppercased() + junto.dropFirst()
    }

    private static let semana: [(String, [String])] = [
        ("lunes", ["lunes", "lun", "lu"]), ("martes", ["martes", "mar", "ma"]), ("miércoles", ["miercoles", "mie", "mi"]),
        ("jueves", ["jueves", "jue", "ju"]), ("viernes", ["viernes", "vie", "vi"]), ("sábado", ["sabado", "sab", "sa"]),
        ("domingo", ["domingo", "dom", "do"]),
    ]

    static func diaDeLaSemana(_ s: String) -> String? {
        let k = clave(s)
        return semana.first { $0.1.contains(k) }?.0
    }

    /// Minúsculas y sin tildes.
    static func clave(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
    }

    /// La dosis con la anterior, si vino: «200 mg → 400 mg». Sin `cantidad`, nil.
    public static func dosis(_ it: ItemSuplemento) -> String? {
        guard let c = it.cantidad, !c.isEmpty else { return nil }
        if let a = it.antes, !a.isEmpty, a != c { return "\(a) → \(c)" }
        return c
    }

    /// Las tomas del detalle: cada momento con su título, la cantidad y la nota. Un ítem de una sola toma da una, sin
    /// cantidad (el detalle ya la muestra arriba, con `dosis`).
    public struct Toma: Equatable, Sendable, Identifiable {
        public let id: Int
        public let momento: String
        public let cantidad: String?
        public let nota: String?
    }

    public static func tomas(_ it: ItemSuplemento, dia: [MomentoDia]) -> [Toma] {
        if !it.tomas.isEmpty {
            return it.tomas.enumerated().compactMap { i, t in
                guard let m = t.momento, !m.isEmpty else { return nil }
                return Toma(id: i, momento: VistaSuplementacion.titulo(momento: m, dia: dia),
                            cantidad: t.cantidad.flatMap { $0.isEmpty ? nil : $0 }, nota: t.nota.flatMap { $0.isEmpty ? nil : $0 })
            }
        }
        guard let m = it.momento, !m.isEmpty else { return [] }
        return [Toma(id: 0, momento: VistaSuplementacion.titulo(momento: m, dia: dia), cantidad: nil, nota: nil)]
    }

    /// Lo que lee VoiceOver en una fila del día: nombre, cantidad, estado, opcional, días y nota, en ese orden.
    public static func descripcionHablada(_ f: VistaSuplementacion.Fila, item it: ItemSuplemento) -> String {
        var p = [f.nombre]
        if let c = f.cantidad { p.append(c) }
        if let e = estado(it.estado), e != .sigue { p.append(e.texto) }
        if it.opcional { p.append("opcional") }
        if let d = textoDias(it.dias) { p.append(d) }
        if let n = f.nota { p.append(n) }
        return p.joined(separator: ", ")
    }
}
