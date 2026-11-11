import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Una novedad guardada: lo que cambió en una publicación de Mati y si el alumno ya la vio.
public struct NovedadPlan: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// Cuándo la detectó el teléfono (ms desde 1970), que es cuando el alumno la pudo ver por primera vez.
    public var fecha: Double
    public var titular: String
    public var resumen: String
    public var partes: [ParteNovedad]
    public var vista: Bool

    public init(id: String, fecha: Double, resumen r: ResumenNovedad, vista: Bool = false) {
        self.id = id; self.fecha = fecha; titular = r.titular; resumen = r.resumen; partes = r.partes; self.vista = vista
    }

    public var dia: Date { Date(timeIntervalSince1970: fecha / 1000) }
}

/// «Novedades de tu plan» (2.3.0, palanca `novedades_plan`): el plan que el alumno ya vio queda guardado en su carpeta
/// (`novedades_base.json`); cuando llega otro, `NovedadesPlan.calcular` dice qué cambió y se guarda en
/// `novedades.json` (las últimas 12). La base no está en el servidor: desde la 013 publicar pisa la versión anterior.
///
/// - Sin base guardada (primera vez con la palanca prendida): la base es la copia offline que había antes de esta carga
///   y la suplementación guardada. Sin nada de eso, se guarda lo que llegó y no se muestra nada.
/// - Un área que no llegó (red) no se compara ni se pisa en la base.
@MainActor @Observable
public final class ModeloNovedades {
    static let archivoBase = "novedades_base.json"
    static let archivoLista = "novedades.json"
    public static let maximo = 12
    /// Cuántos días se ve la tarjeta de la última novedad en Entreno.
    public static let diasTarjeta: Double = 7

    /// La más nueva primero.
    public private(set) var lista: [NovedadPlan] = []

    @ObservationIgnored let disco: Disco?
    @ObservationIgnored let ahora: () -> Date

    public init(disco: Disco?, ahora: @escaping () -> Date = Date.init) {
        self.disco = disco
        self.ahora = ahora
        lista = disco?.leer([NovedadPlan].self, Self.archivoLista) ?? []
    }

    /// La demo y las capturas: una lista armada, sin disco.
    public init(muestra: [NovedadPlan]) {
        disco = nil
        ahora = Date.init
        lista = muestra
    }

    /// La que se muestra sola al abrir: la más nueva sin ver.
    public var pendiente: NovedadPlan? { lista.first { !$0.vista } }

    /// La tarjeta de Entreno: la última, durante `diasTarjeta` días.
    public var reciente: NovedadPlan? {
        guard let n = lista.first, ahora().timeIntervalSince(n.dia) < Self.diasTarjeta * 86_400 else { return nil }
        return n
    }

    public func marcarVista(_ id: String) {
        guard let i = lista.firstIndex(where: { $0.id == id }), !lista[i].vista else { return }
        lista[i].vista = true
        disco?.guardar(lista, Self.archivoLista)
    }

    /// Con la palanca apagada el plan «ya visto» no sirve más: si se quedara, al volver a prenderla se compararía contra
    /// una base de hace semanas y saldría un resumen enorme. Sin base, la próxima vez se parte de la copia de la última
    /// carga. Las novedades ya guardadas no se tocan.
    public func olvidarBase() {
        disco?.borrar(Self.archivoBase)
    }

    // MARK: - Base

    /// Un área como se guarda: `hay` false = el servidor dijo que no hay; sin la clave = no se sabe.
    struct AreaGuardada: Codable, Equatable {
        var hay: Bool
        var valor: JSONValue?
    }

    struct Base: Codable, Equatable {
        var rutina: AreaGuardada?
        var dieta: AreaGuardada?
        var suplementacion: AreaGuardada?
    }

    /// Lo que llegó en esta carga, por área.
    public enum Entrada: Sendable, Equatable {
        case noLlego
        case ninguna
        case hay(JSONValue)

        var guardada: AreaGuardada? {
            switch self {
            case .noLlego: nil
            case .ninguna: AreaGuardada(hay: false, valor: nil)
            case .hay(let v): AreaGuardada(hay: true, valor: v)
            }
        }
    }

    /// Compara lo que llegó con lo que ya se vio, guarda la base nueva y, si cambió algo, la novedad.
    /// `semilla`: lo que había en el teléfono antes de esta carga, por si todavía no hay base.
    @discardableResult
    public func observar(rutina: Entrada, dieta: Entrada, suplementacion: Entrada,
                         semilla: (rutina: Entrada, dieta: Entrada, suplementacion: Entrada) = (.noLlego, .noLlego, .noLlego),
                         soloConBase: Bool = false) -> NovedadPlan? {
        guard let disco else { return nil }
        let guardada = disco.leer(Base.self, Self.archivoBase)
        if soloConBase && guardada == nil { return nil }
        let antes = guardada ?? Base(rutina: semilla.rutina.guardada, dieta: semilla.dieta.guardada,
                                     suplementacion: semilla.suplementacion.guardada)
        var nueva = antes
        if let r = rutina.guardada { nueva.rutina = r }
        if let d = dieta.guardada { nueva.dieta = d }
        if let s = suplementacion.guardada { nueva.suplementacion = s }
        if nueva != guardada { disco.guardar(nueva, Self.archivoBase) }

        let fotoAntes = FotoPlan(rutina: Self.area(antes.rutina, RutinaActiva.self),
                                 dieta: Self.area(antes.dieta, DietaActiva.self),
                                 suplementacion: Self.suplementacion(antes.suplementacion))
        let fotoDespues = FotoPlan(rutina: Self.area(rutina.guardada, RutinaActiva.self),
                                   dieta: Self.area(dieta.guardada, DietaActiva.self),
                                   suplementacion: Self.suplementacion(suplementacion.guardada))
        guard let r = NovedadesPlan.calcular(antes: fotoAntes, despues: fotoDespues) else { return nil }
        let n = NovedadPlan(id: UUID().uuidString, fecha: ahora().timeIntervalSince1970 * 1000, resumen: r)
        // Las anteriores quedan vistas: se muestra la de esta publicación, nunca una vieja que no se llegó a abrir.
        lista = Array(([n] + lista.map { var x = $0; x.vista = true; return x }).prefix(Self.maximo))
        disco.guardar(lista, Self.archivoLista)
        return n
    }

    /// Un valor del kit como JSON, para guardarlo en la base.
    static func json<T: Encodable>(_ v: T) -> JSONValue? {
        guard let d = try? JSONEncoder().encode(v) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: d)
    }

    static func area<T: Decodable>(_ a: AreaGuardada?, _ t: T.Type) -> AreaPlan<T> {
        guard let a else { return .desconocida }
        guard a.hay else { return .ninguna }
        guard let v = a.valor, let d = try? JSONEncoder().encode(v), let x = try? JSONDecoder().decode(T.self, from: d) else {
            return .desconocida
        }
        return .hay(x)
    }

    static func suplementacion(_ a: AreaGuardada?) -> AreaPlan<SuplementacionGuia> {
        switch area(a, RespuestaSuplementacion.self) {
        case .desconocida: .desconocida
        case .ninguna: .ninguna
        case .hay(let r): r.hay ? r.suplementacion.map { .hay($0) } ?? .ninguna : .ninguna
        }
    }
}
