import Foundation

/// Las dudas en audio de «Tu guía» (pedido de Mati del 4-nov, 2.1.0): los topes, los textos y la máquina de estados del
/// grabador. Copia la especificación de la web (`pump-entregas/pruebas/AUDIO-DUDAS-UI.md`); lo que cambia en la app está
/// en `nativa-evidencia/guia/AUDIO_APP.md`. Contrato por token: `entregas_019` (`entregas_app_audio_*`).
public enum ReglasAudioDuda {
    /// Corta solo a los 5 minutos y pasa a revisar.
    public static let topeSegundos: Double = 300
    /// «Te quedan 30 segundos.»
    public static let avisoSegundos: Double = 270
    /// Menos de esto no se manda: «No se escuchó nada».
    public static let minimoSegundos: Double = 2
    /// AAC en m4a: lo que la RPC espera y el `Content-Type` exacto de la subida.
    public static let mime = "audio/mp4"
    public static let bitrate = 64_000
    public static let frecuencia: Double = 44_100
    /// Mientras haya alguno en `subido`: cada 15 s, como mucho 3 minutos, solo con la sección abierta.
    public static let sondeoCada: Double = 15
    public static let sondeoMaximo: Double = 180

    // MARK: - Textos (voz de Mati, sin «:», sin guiones, sin emojis)

    /// El cliente no se entera de que el audio se pasa a texto (Mati, 4-nov 18:40; como pack.html en cerebro 1a9c5e6).
    public static let textoInvitacion = "¿Te es más fácil hablarlo? Mandame un audio, como por WhatsApp. Hasta 5 minutos cada uno."
    public static let textoGrabar = "Grabar un audio"
    public static let textoTerminar = "Terminar"
    /// VoiceOver del botón mientras graba.
    public static let textoTerminarAccesible = "Terminar de grabar"
    public static let textoAntesDelPermiso = "Te va a pedir permiso para usar el micrófono, aceptalo así te escucho."
    public static let textoMandar = "Mandar"
    public static let textoGrabarDeNuevo = "Grabar de nuevo"
    public static let textoBorrar = "Borrar"
    public static let textoMandando = "Mandando tu audio…"
    public static let textoNoSeMando = "No se pudo mandar."
    public static let textoReintentar = "Reintentar"
    public static let textoAbrirAjustes = "Abrir ajustes"
    public static let textoErrorTranscripcion = "No pude escuchar bien este audio, ¿me lo mandás de nuevo o lo escribís?"

    /// Subido o transcripto se ve igual: nunca se muestra la transcripción.
    public static func textoSubido(despues: Bool) -> String {
        despues ? "Listo, me llegó tu audio, te contesto por WhatsApp." : "Listo, me llegó tu audio, lo escucho antes de la videollamada."
    }

    /// Lo que se anuncia al terminar de grabar (el contador no se anuncia cada segundo).
    public static func textoGrabaste(_ segundos: Double) -> String { "Grabaste \(contador(segundos))" }

    /// El contador, como número aparte: `0:42`, `4:30`, `5:00`.
    public static func contador(_ segundos: Double) -> String {
        let s = max(0, Int(segundos.isFinite ? segundos : 0))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    public static func texto(_ a: AvisoAudio) -> String {
        switch a {
        case .permisoNegado:
            "Tu celu no me dio permiso para el micrófono. En Ajustes, MyPump, Micrófono, activalo. O escribime la duda acá arriba."
        case .sinMicrofono: "No encontré un micrófono en este dispositivo. Escribime la duda acá arriba."
        case .ocupado: "El micrófono lo está usando otra app. Cerrala y probá de nuevo."
        case .muyCorto: "No se escuchó nada, probá de nuevo."
        case .quedan30: "Te quedan 30 segundos."
        case .tope: "Ya me mandaste 10 audios. Lo que te falte escribímelo o lo vemos en la llamada."
        case .pendientes: "Esperá un toque que se terminen de mandar los otros audios."
        case .largo: "Es muy largo, mandámelo en audios de hasta 5 minutos."
        case .formato: "Tu navegador graba en un formato que no puedo recibir. Probá desde Safari o Chrome, o escribime la duda."
        case .noSeMando: textoNoSeMando
        case .vistaPrevia: "Vista previa: el audio no se manda."
        case .yaFallo: textoErrorTranscripcion
        }
    }

    /// El `motivo` de `entregas_app_audio_iniciar` con `ok: false`. `token` no llega acá: la cola lo estaciona. `error` es
    /// que ese audio ya falló en el servidor (hay que grabar otro); `id` (el `p_id` es de otro cliente) cae en «No se pudo
    /// mandar».
    public static func aviso(motivo: String?) -> AvisoAudio {
        switch motivo {
        case "tope": .tope
        case "pendientes": .pendientes
        case "tamano", "largo": .largo
        case "formato": .formato
        case "error": .yaFallo
        default: .noSeMando
        }
    }

    /// Deduplicación: al pintar las dudas de la llamada se saltean los textos iguales a un `texto` transcripto (si no, el
    /// cliente vería la transcripción, que entra después como una duda más). Se compara sin los espacios de los bordes.
    public static func sinTranscriptos(_ dudas: [String], transcriptos: Set<String>) -> [String] {
        guard !transcriptos.isEmpty else { return dudas }
        return dudas.filter { !transcriptos.contains(limpio($0)) }
    }

    public static func limpio(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Los avisos de la línea viva debajo del botón.
public enum AvisoAudio: String, Equatable, Sendable, Codable {
    case permisoNegado, sinMicrofono, ocupado, muyCorto, quedan30
    case tope, pendientes, largo, formato, noSeMando, vistaPrevia, yaFallo
}

/// El grabador, sin AVFoundation: qué se ve y qué hay que hacer ante cada evento. El reloj lo pone quien la usa (segundos
/// desde cualquier origen), así la duración es un contador propio y no la del archivo.
public struct MaquinaAudio: Equatable, Sendable {
    public enum Fase: Equatable, Sendable {
        case reposo
        /// Tocó «Grabar»: se está pidiendo el permiso o arrancando el micrófono.
        case pidiendoPermiso
        case grabando(inicio: Double)
        /// Revisar: reproducir, Mandar, Grabar de nuevo, Borrar.
        case revisando(segundos: Double)
    }

    public enum Evento: Equatable, Sendable {
        case tocarGrabar
        case permiso(Bool)
        case empezo(ahora: Double)
        case noEmpezo(AvisoAudio)
        case tic(ahora: Double)
        case terminar(ahora: Double)
        /// La app pasó a segundo plano o el sistema cortó el micrófono (una llamada): se frena y se pasa a revisar.
        case cortar(ahora: Double)
        case grabarDeNuevo
        case borrar
        /// `vistaPrevia`: la demo o la maqueta, donde nada sale.
        case mandar(vistaPrevia: Bool)
    }

    public enum Efecto: Equatable, Sendable {
        case pedirPermiso
        case empezarAGrabar
        case pararGrabador
        case descartarArchivo
        case encolar(segundos: Double)
        case anunciar(String)
    }

    public private(set) var fase: Fase = .reposo
    public private(set) var aviso: AvisoAudio?
    private var avisoDado = false

    public init() {}

    public var grabando: Bool { if case .grabando = fase { true } else { false } }

    /// Los segundos que lleva grabando (o los de lo grabado, al revisar).
    public func segundos(ahora: Double) -> Double {
        switch fase {
        case .grabando(let i): min(ReglasAudioDuda.topeSegundos, max(0, ahora - i))
        case .revisando(let s): s
        default: 0
        }
    }

    public mutating func manejar(_ e: Evento) -> [Efecto] {
        switch (fase, e) {
        case (.reposo, .tocarGrabar):
            aviso = nil
            fase = .pidiendoPermiso
            return [.pedirPermiso]
        case (.revisando, .grabarDeNuevo):
            aviso = nil
            fase = .pidiendoPermiso
            return [.descartarArchivo, .pedirPermiso]
        case (.pidiendoPermiso, .permiso(true)):
            return [.empezarAGrabar]
        case (.pidiendoPermiso, .permiso(false)):
            fase = .reposo
            aviso = .permisoNegado
            return [.anunciar(ReglasAudioDuda.texto(.permisoNegado))]
        case (.pidiendoPermiso, .noEmpezo(let a)):
            fase = .reposo
            aviso = a
            return [.descartarArchivo, .anunciar(ReglasAudioDuda.texto(a))]
        case (.pidiendoPermiso, .empezo(let ahora)):
            fase = .grabando(inicio: ahora)
            avisoDado = false
            return []
        case (.grabando(let i), .tic(let ahora)):
            let s = ahora - i
            if s >= ReglasAudioDuda.topeSegundos { return parar(ahora: ahora, inicio: i) }
            if s >= ReglasAudioDuda.avisoSegundos && !avisoDado {
                avisoDado = true
                aviso = .quedan30
                return [.anunciar(ReglasAudioDuda.texto(.quedan30))]
            }
            return []
        case (.grabando(let i), .terminar(let ahora)), (.grabando(let i), .cortar(let ahora)):
            return parar(ahora: ahora, inicio: i)
        case (.pidiendoPermiso, .cortar):
            // Se fue a segundo plano con el cartel del permiso o antes de arrancar: nada que revisar.
            fase = .reposo
            return [.pararGrabador, .descartarArchivo]
        case (.revisando, .borrar):
            fase = .reposo
            aviso = nil
            return [.descartarArchivo]
        case (.revisando, .mandar(true)):
            aviso = .vistaPrevia
            return [.anunciar(ReglasAudioDuda.texto(.vistaPrevia))]
        case (.revisando(let s), .mandar(false)):
            fase = .reposo
            aviso = nil
            return [.encolar(segundos: s)]
        default:
            return []
        }
    }

    private mutating func parar(ahora: Double, inicio: Double) -> [Efecto] {
        let s = min(ReglasAudioDuda.topeSegundos, max(0, ahora - inicio))
        if s < ReglasAudioDuda.minimoSegundos {
            fase = .reposo
            aviso = .muyCorto
            return [.pararGrabador, .descartarArchivo, .anunciar(ReglasAudioDuda.texto(.muyCorto))]
        }
        fase = .revisando(segundos: s)
        if aviso == .quedan30 { aviso = nil }
        return [.pararGrabador, .anunciar(ReglasAudioDuda.textoGrabaste(s))]
    }
}
