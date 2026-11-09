import Foundation
import MyPumpModelos

/// Qué días se pueden cargar en Dieta y cómo se llaman (pedido de un cliente: «salí a cenar y al día siguiente no pude
/// cargar esa cena»). El servidor mira la fecha de Argentina: `mypump_crear_comida_libre`, `mypump_desmarcar_comida` y
/// `mypump_guardar_ajustes_dieta` aceptan de −7 a +1, pero `mypump_marcar_comida` solo de −2 a 0 (verificado en la base el
/// 9-nov). Por eso «Comí» y «Salté» tienen su propia ventana, que dice la palanca remota (`dieta_dias_marcar`).
public enum DiasDieta {
    public static let diasAtras = 7
    /// Lo que acepta hoy `mypump_marcar_comida`.
    public static let diasMarcarDeFabrica = 2

    public static let zonaServidor = TimeZone(identifier: "America/Argentina/Buenos_Aires") ?? TimeZone(secondsFromGMT: -3 * 3600)!

    public static func hoyServidor(_ ahora: Date = Date()) -> String { FechaLocal.hoy(ahora, zona: zonaServidor) }

    private static var calendario: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private static func fecha(_ iso: String) -> Date? {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendario.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// `iso` más `dias` (negativo: para atrás).
    public static func sumar(_ iso: String, dias: Int) -> String? {
        guard let f = fecha(iso), let r = calendario.date(byAdding: .day, value: dias, to: f) else { return nil }
        let c = calendario.dateComponents([.year, .month, .day], from: r)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Hoy primero y después los días anteriores que el servidor todavía acepta: un teléfono atrasado respecto de Argentina
    /// no ofrece un día que la base rechazaría.
    public static func seleccionables(hoy: String, hoyServidor: String) -> [String] {
        let piso = sumar(hoyServidor, dias: -diasAtras) ?? hoy
        return (0...diasAtras).compactMap { sumar(hoy, dias: -$0) }.filter { $0 == hoy || $0 >= piso }
    }

    /// ¿`mypump_marcar_comida` acepta esa fecha? `dias` es la ventana vigente (la palanca remota).
    public static func permiteMarcar(_ iso: String, hoyServidor: String, dias: Int) -> Bool {
        guard let piso = sumar(hoyServidor, dias: -max(0, min(dias, diasAtras))) else { return false }
        return iso >= piso && iso <= hoyServidor
    }

    private static func partes(_ iso: String) -> (semana: Int, dia: Int, mes: Int)? {
        guard let f = fecha(iso) else { return nil }
        let c = calendario.dateComponents([.weekday, .day, .month], from: f)
        return (c.weekday ?? 1, c.day ?? 1, c.month ?? 1)
    }

    private static let semana = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
    private static let semanaCorta = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]
    private static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
                                "noviembre", "diciembre"]

    /// Lo que dice cada día en el selector: «Hoy», «Ayer», «Sáb 7».
    public static func rotuloCorto(_ iso: String, hoy: String) -> String {
        if iso == hoy { return "Hoy" }
        if iso == sumar(hoy, dias: -1) { return "Ayer" }
        guard let p = partes(iso) else { return iso }
        return "\(semanaCorta[p.semana - 1]) \(p.dia)"
    }

    /// «sábado 7 de noviembre».
    public static func rotuloLargo(_ iso: String) -> String {
        guard let p = partes(iso) else { return iso }
        return "\(semana[p.semana - 1]) \(p.dia) de \(meses[p.mes - 1])"
    }
}

/// Copiar a hoy lo cargado otro día (pedido de un cliente: «así no agrego todas las comidas todos los días, porque comemos
/// casi lo mismo en una semana»). De cada comida se copia lo que representa lo que comió: el ajuste (opción, gramos a mano,
/// kcal y alimentos agregados) y la marca «Comí» con sus tildes. «Salté» y «Hoy no la como» no se copian: dicen que ese día
/// no la comió, no lo que come. Las comidas libres se copian como comidas nuevas.
public enum CopiaDeComidas {
    public enum Estado: Equatable, Sendable {
        /// Hoy no hay nada cargado en esa comida.
        case nueva
        /// Hoy ya está exactamente eso.
        case igual
        /// Hoy hay otra cosa cargada: solo se reemplaza si el cliente lo pide.
        case conflicto
    }

    public struct ItemComida: Equatable, Sendable, Identifiable {
        public let comidaId: String
        public let nombre: String
        public let opcion: Int
        public let nombreOpcion: String
        public let marca: MarcaComida?
        public let ajuste: AjusteComida?
        public let kcal: Double
        public let estado: Estado
        public var id: String { comidaId }
        public var agregados: Int { ajuste?.agregados.count ?? 0 }
        public var conCantidades: Bool { !(ajuste?.cantidades.isEmpty ?? true) || (ajuste?.deltaKcal ?? 0) != 0 }
    }

    public struct ItemLibre: Equatable, Sendable, Identifiable {
        public let libre: ComidaLibre
        public let estado: Estado
        public var id: String { libre.id }
    }

    public struct Plan: Equatable, Sendable {
        public var comidas: [ItemComida] = []
        public var libres: [ItemLibre] = []
        /// El plan de ese día era otro: solo se ofrecen las comidas libres.
        public var otroPlan = false
        public init() {}
        public var vacio: Bool { comidas.isEmpty && libres.isEmpty }
    }

    /// El estado de una comida contra lo que ya hay hoy.
    public static func estado(marca: MarcaComida?, ajuste: AjusteComida?, hoyMarca: MarcaComida?, hoyAjuste: AjusteComida?) -> Estado {
        if hoyMarca == nil && hoyAjuste == nil { return .nueva }
        return hoyMarca == marca && hoyAjuste == ajuste ? .igual : .conflicto
    }

    private static func normalizar(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// La misma descripción y las mismas kcal (redondeadas): copiarla de nuevo la duplicaría.
    public static func mismaLibre(_ a: ComidaLibre, _ b: ComidaLibre) -> Bool {
        normalizar(a.descripcion) == normalizar(b.descripcion) && (a.kcal ?? 0).rounded() == (b.kcal ?? 0).rounded()
    }

    /// Lo que se puede copiar de ese día. `kcal` calcula lo de una comida con su marca y su ajuste.
    public static func plan(comidas: [Comida],
                            origenMarcas: [String: MarcaComida], origenAjustes: [String: AjusteComida], origenLibres: [ComidaLibre],
                            hoyMarcas: [String: MarcaComida], hoyAjustes: [String: AjusteComida], hoyLibres: [ComidaLibre],
                            otroPlan: Bool = false, kcal: (Comida, MarcaComida?, AjusteComida?, Int) -> Double) -> Plan {
        var p = Plan()
        p.otroPlan = otroPlan
        // Por conteo: dos iguales en el origen y una hoy son una que ya está y una nueva.
        var quedan = hoyLibres
        p.libres = origenLibres.map { l in
            guard let i = quedan.firstIndex(where: { mismaLibre($0, l) }) else { return ItemLibre(libre: l, estado: .nueva) }
            quedan.remove(at: i)
            return ItemLibre(libre: l, estado: .igual)
        }
        if otroPlan { return p }
        for c in comidas where !c.opciones.isEmpty {
            let m = origenMarcas[c.id]
            let a = origenAjustes[c.id]
            guard m != nil || a != nil, m?.estado != .saltado, a?.omitida != true else { continue }
            // La opción de la marca tiene que seguir existiendo: `indiceOpcion` caería a la A y copiaría otra comida.
            var o = a?.opcion ?? 0
            if let m {
                guard let nombre = m.opcion, !nombre.isEmpty else { continue }
                let existe = c.opciones.contains { $0.nombre == nombre }
                    || c.opciones.indices.contains { (c.opciones[$0].nombre ?? "").isEmpty && ConsumoDelDia.letra($0) == nombre }
                guard existe else { continue }
                o = ConsumoDelDia.indiceOpcion(c, nombre: nombre)
            }
            guard c.opciones.indices.contains(o), a.map({ c.opciones.indices.contains($0.opcion) }) ?? true else { continue }
            var marca = m
            if let actual = m {
                let tope = c.opciones[o].alimentos.count + (a?.agregados.count ?? 0)
                marca = MarcaComida(opcion: actual.opcion, estado: actual.estado, excluidos: actual.excluidos.filter { $0 < tope })
            }
            p.comidas.append(ItemComida(comidaId: c.id, nombre: c.nombre ?? "", opcion: o, nombreOpcion: ConsumoDelDia.nombreOpcion(c, o),
                                        marca: marca, ajuste: a, kcal: kcal(c, marca, a, o),
                                        estado: estado(marca: marca, ajuste: a, hoyMarca: hoyMarcas[c.id], hoyAjuste: hoyAjustes[c.id])))
        }
        return p
    }
}
