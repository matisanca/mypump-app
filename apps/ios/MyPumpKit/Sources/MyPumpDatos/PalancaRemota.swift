import Foundation
import MyPumpModelos
import MyPumpReglas

/// La palanca remota (`mypump_app_config`, G2: `nativa_001`): lo que se puede pausar desde el servidor sin publicar una
/// versión nueva. Sin la tabla (PGRST202) vale lo de fábrica, que es lo que la app hace hoy: todo prendido y sin versión
/// mínima. Se lee sin token, junto con la rutina y la dieta.
public struct PalancaRemota: Equatable, Sendable {
    /// false: las ops importadas de la Capacitor no se mandan; quedan guardadas para cuando se vuelva a prender.
    public var opsLegadas = true
    /// false: no se borra nada del almacenamiento viejo de la Capacitor.
    public var escrituraVuelta = true
    /// false: un swap de comida anclado que ya no coincide con la dieta se oculta, pero no se borra del servidor.
    public var anclajeBorraSwaps = true
    public var versionMinimaIOS: String?
    public var versionMinimaAndroid: String?

    public init() {}

    public static let deFabrica = PalancaRemota()

    /// Lo que devolvió `mypump_get_app_config`. Un valor que no es del tipo esperado no cuenta: queda el de fábrica.
    public init(_ j: JSONValue) {
        if case .bool(let b)? = j["migracion_ops_legadas"] { opsLegadas = b }
        if case .bool(let b)? = j["migracion_escritura_vuelta"] { escrituraVuelta = b }
        if case .bool(let b)? = j["anclaje_borra_swaps"] { anclajeBorraSwaps = b }
        if case .texto(let s)? = j["version_minima_ios"], !s.isEmpty { versionMinimaIOS = s }
        if case .texto(let s)? = j["version_minima_android"], !s.isEmpty { versionMinimaAndroid = s }
    }

    /// nil = no se pudo preguntar (red o servicio caído): quien llama decide si espera.
    public static func leer(_ cliente: ClienteRPC) async -> PalancaRemota? {
        switch await cliente.llamar("mypump_get_app_config", [:]) {
        case .success(let j): return PalancaRemota(j)
        case .failure(let e) where e.clase == .permanente: return .deFabrica   // PGRST202: la 001 todavía no está
        case .failure: return nil
        }
    }

    /// ¿La versión instalada está por debajo de la mínima? Número por número: "2.0.10" es mayor que "2.0.9".
    public static func debajo(_ version: String?, de minima: String?) -> Bool {
        guard let version, let minima else { return false }
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = minima.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}
