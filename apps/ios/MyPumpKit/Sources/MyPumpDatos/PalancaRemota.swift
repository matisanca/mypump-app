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
    /// false: el reloj no propone las reps (`reloj_contador_reps`). La ausencia de la clave = prendido.
    public var contadorRepsReloj = true
    public var versionMinimaIOS: String?
    public var versionMinimaAndroid: String?
    /// Cuántos días atrás acepta «Comí» / «Salté» el servidor (`dieta_dias_marcar`). Sin la clave, lo de fábrica.
    public var diasMarcarDieta: Int?
    /// Gimnasio por fotos (`gimnasio_fotos`). Sin la clave, apagado: ni se muestra ni se llama a nada nuevo.
    public var gimnasioFotos = false
    /// Técnica por video (`tecnica_video`). Sin la clave, apagada: ni se muestra ni se llama a nada nuevo.
    public var tecnicaVideo = false
    /// «Novedades de tu plan» (`novedades_plan`). Sin la clave, apagada: no se guarda ni se muestra nada.
    public var novedadesPlan = false
    /// Devolución de Mati en Revisión (`devolucion_semanal`). Sin la clave, apagada: ni se muestra ni se llama a nada nuevo.
    public var devolucionSemanal = false
    /// Metas de pasos y ritmo de peso, con el «Pump del día» (`metas_pasos`). Sin la clave, apagadas: no se ve nada nuevo.
    public var metasPasos = false
    /// Fotos y audios en el chat (`chat_adjuntos`). Sin la clave, apagado. Prendida, igual decide el servidor por cliente.
    public var chatAdjuntos = false
    /// «Me duele» por ejercicio (`me_duele`). Sin la clave, apagado: ni se muestra ni se llama a nada nuevo.
    public var meDuele = false
    /// «Lo compré / lo estoy tomando» (`suple_estado`). Sin la clave, apagado.
    public var supleEstado = false
    /// Elegir y cambiar el horario de la videollamada en la pantalla nueva (`elegir_horario`, 2.3.0). Sin la clave,
    /// apagada: la agenda de la guía queda como en la 2.2.0 y no se llama a `entregas_app_cambiar`.
    public var elegirHorario = false

    public init() {}

    public static let deFabrica = PalancaRemota()

    /// El último valor leído de `reloj_contador_reps`: apagado, sigue apagado aunque el iPhone arranque sin red.
    static let claveContadorReps = "mypump-palanca-contador-reps"
    /// El último valor leído de `gimnasio_fotos`: prendida, sin red en el gimnasio se pueden seguir sacando fotos.
    static let claveGimnasioFotos = "mypump-palanca-gimnasio-fotos"
    /// El último valor leído de `tecnica_video`: prendida, un video en la cola sigue subiendo aunque se arranque sin red.
    static let claveTecnicaVideo = "mypump-palanca-tecnica-video"
    /// El último valor leído de `novedades_plan`: lo ya detectado se puede ver sin red.
    static let claveNovedadesPlan = "mypump-palanca-novedades-plan"
    /// El último valor leído de `devolucion_semanal`: prendida, sin red se sigue viendo la última devolución guardada.
    static let claveDevolucion = "mypump-palanca-devolucion-semanal"
    /// El último valor leído de `metas_pasos`: sin red al arrancar, el «Pump del día» no aparece y desaparece.
    static let claveMetasPasos = "mypump-palanca-metas-pasos"
    /// El último valor leído de `chat_adjuntos`: prendida, sin red se puede mandar una foto y sale después.
    static let claveChatAdjuntos = "mypump-palanca-chat-adjuntos"
    /// El último valor leído de `elegir_horario`: apagada, un cambio que quedó en la cola no sale.
    static let claveElegirHorario = "mypump-palanca-elegir-horario"
    public static func arranque(defaults: UserDefaults = .standard) -> PalancaRemota {
        var p = deFabrica
        if defaults.object(forKey: claveContadorReps) as? Bool == false { p.contadorRepsReloj = false }
        if defaults.bool(forKey: claveGimnasioFotos) { p.gimnasioFotos = true }
        if defaults.bool(forKey: claveTecnicaVideo) { p.tecnicaVideo = true }
        if defaults.bool(forKey: claveNovedadesPlan) { p.novedadesPlan = true }
        if defaults.bool(forKey: claveDevolucion) { p.devolucionSemanal = true }
        if defaults.bool(forKey: claveMetasPasos) { p.metasPasos = true }
        if defaults.bool(forKey: claveChatAdjuntos) { p.chatAdjuntos = true }
        if defaults.bool(forKey: claveElegirHorario) { p.elegirHorario = true }
        #if DEBUG
        // Pruebas de interfaz y capturas: `-elegirHorario YES` (lo mismo que mira la pantalla).
        if let v = defaults.string(forKey: "elegirHorario") { p.elegirHorario = v == "YES" }
        #endif
        return p
    }
    public func recordar(defaults: UserDefaults = .standard) {
        defaults.set(contadorRepsReloj, forKey: Self.claveContadorReps)
        defaults.set(gimnasioFotos, forKey: Self.claveGimnasioFotos)
        defaults.set(tecnicaVideo, forKey: Self.claveTecnicaVideo)
        defaults.set(novedadesPlan, forKey: Self.claveNovedadesPlan)
        defaults.set(devolucionSemanal, forKey: Self.claveDevolucion)
        defaults.set(metasPasos, forKey: Self.claveMetasPasos)
        defaults.set(chatAdjuntos, forKey: Self.claveChatAdjuntos)
        defaults.set(elegirHorario, forKey: Self.claveElegirHorario)
    }

    /// Lo que devolvió `mypump_get_app_config`. Un valor que no es del tipo esperado no cuenta: queda el de fábrica.
    public init(_ j: JSONValue) {
        if case .bool(let b)? = j["migracion_ops_legadas"] { opsLegadas = b }
        if case .bool(let b)? = j["migracion_escritura_vuelta"] { escrituraVuelta = b }
        if case .bool(let b)? = j["anclaje_borra_swaps"] { anclajeBorraSwaps = b }
        if case .bool(let b)? = j["reloj_contador_reps"] { contadorRepsReloj = b }
        if case .bool(let b)? = j["gimnasio_fotos"] { gimnasioFotos = b }
        if case .bool(let b)? = j["tecnica_video"] { tecnicaVideo = b }
        if case .bool(let b)? = j["novedades_plan"] { novedadesPlan = b }
        if case .bool(let b)? = j["devolucion_semanal"] { devolucionSemanal = b }
        if case .bool(let b)? = j["metas_pasos"] { metasPasos = b }
        if case .bool(let b)? = j["chat_adjuntos"] { chatAdjuntos = b }
        if case .bool(let b)? = j["me_duele"] { meDuele = b }
        if case .bool(let b)? = j["suple_estado"] { supleEstado = b }
        if case .bool(let b)? = j["elegir_horario"] { elegirHorario = b }
        if case .texto(let s)? = j["version_minima_ios"], !s.isEmpty { versionMinimaIOS = s }
        if case .texto(let s)? = j["version_minima_android"], !s.isEmpty { versionMinimaAndroid = s }
        if case .numero(let n)? = j["dieta_dias_marcar"], n == n.rounded(), n >= 0, n <= 30 { diasMarcarDieta = Int(n) }
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
