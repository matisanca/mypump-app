import Foundation

/// Fotos y audios en el chat con Mati (2.3.0, `nativa_chat_adjuntos`). Las reglas puras: topes, cómo se lee lo que
/// contesta mini-vision y los textos. Lo que se hace con cada adjunto del lado de la Mini no se nombra nunca en la app.
public enum ReglasChatAdjuntos {
    /// Grabar manteniendo apretado: a los 2 minutos se corta solo y se manda.
    public static let audioMaximo: Double = 120
    /// Menos de esto es un toque sin querer: no se manda.
    public static let audioMinimo: Double = 1
    /// «Te quedan 10 segundos.»
    public static let audioAviso: Double = 110
    /// Arrastrar el dedo a la izquierda más que esto mientras graba = cancelar.
    public static let deslizarParaCancelar: Double = 90
    /// La foto se redibuja (eso descarta EXIF y GPS) con el lado mayor en 1600 px, como las de progreso.
    public static let fotoLadoMaximo = 1600
    public static let fotoCalidad = 0.75
    /// Lo que acepta mini-vision por archivo (`MAX_CHAT_FOTO_B`, `MAX_CHAT_AUDIO_B`).
    public static let bytesMaximos = 3 * 1024 * 1024
    public static let mimeFoto = "image/jpeg"
    public static let mimeAudio = "audio/mp4"
    /// Las URLs firmadas duran 1 h: se usan 50 minutos.
    public static let firmaVigente: TimeInterval = 50 * 60
    /// Lo que se pide firmar de una vez (`/chat/urls` acepta hasta 60).
    public static let firmasPorPedido = 60
    /// Los archivos del teléfono (lo mandado, lo bajado) se guardan esta cantidad de días y después se limpian.
    public static let diasEnElTelefono: Double = 14

    // MARK: - Lo que contesta mini-vision

    public enum Subida: Equatable, Sendable {
        case ok
        /// 403 por el token: lo decide la verificación del token de la cola.
        case token
        /// Sin red, 5xx, 408: se reintenta solo sin gastar intento.
        case reintentar
        /// Llegó al tope del día: «no salió» con su texto, y se puede reintentar más tarde.
        case tope
        /// No va a entrar nunca así (muy grande, formato, apagado): «no salió».
        case rechazo
        /// El id es de otro mensaje: se reintenta con uno nuevo.
        case idRepetido
    }

    /// `POST /chat/adjunto`. Un 429 NO se reintenta solo: cada intento volvería a mandar el archivo entero por datos
    /// móviles para escuchar otra vez que no.
    public static func subida(status: Int, ok: Bool, error: String?) -> Subida {
        if (200..<300).contains(status) { return ok ? .ok : .reintentar }
        let e = (error ?? "").lowercased()
        switch status {
        case 0, 408, 500...: return .reintentar
        case 429: return .tope
        case 409: return .idRepetido
        case 401, 403 where e.contains("token"): return .token
        default: return .rechazo
        }
    }

    // MARK: - Textos (voz de Mati, sin «:», sin guiones, sin emojis)

    /// Lo que dice la fila del mensaje (igual que el `contenido` que guarda el servidor): «Audio de 0:42».
    public static func textoAudio(segundos: Double?) -> String { "Audio de \(duracion(segundos ?? 0))" }
    public static let textoFoto = "Foto"

    /// 0:07, 1:42, 2:00. Redondea al segundo, nunca negativo.
    public static func duracion(_ s: Double) -> String {
        let t = max(0, Int(s.isFinite ? s.rounded() : 0))
        return "\(t / 60):\(String(format: "%02d", t % 60))"
    }

    public static let textoAdjuntar = "Mandar una foto"
    public static let textoSacarFoto = "Sacar una foto"
    public static let textoElegirFoto = "Elegir de tus fotos"
    public static let textoMantenerParaGrabar = "Mantené apretado para grabar"
    /// VoiceOver: el botón del micrófono se toca una vez para empezar y otra para mandar.
    public static let textoGrabarAccesible = "Grabar un audio"
    public static let ayudaGrabarAccesible = "Tocá dos veces para empezar a grabar y otra vez para mandarlo."
    public static let textoMandarAudioAccesible = "Mandar el audio"
    public static let textoDeslizarParaCancelar = "Deslizá para cancelar"
    public static let textoCancelar = "Cancelar"
    public static let textoQuedanDiez = "Te quedan 10 segundos"
    public static let textoMuyCorto = "Mantené apretado mientras hablás."
    public static let textoEnviando = "Enviando…"
    public static let textoNoSalio = "No salió."
    public static let textoReintentar = "Reintentar"
    public static let textoTope = "Por hoy llegaste al máximo de fotos y audios. Probá mañana."
    public static let textoSinArchivo = "Este archivo ya no está en el teléfono."
    public static let textoNoDisponible = "Ya no está disponible."
    public static let textoCargando = "Cargando…"
    public static let textoNoCarga = "No se pudo cargar. Tocá para probar de nuevo."
    public static let textoReproducir = "Escuchar"
    public static let textoPausar = "Pausar"
    public static let textoCerrar = "Cerrar"
    public static let textoFotoAccesible = "Foto"
    public static func textoAudioAccesible(segundos: Double?) -> String { "Audio de \(duracionHablada(segundos ?? 0))" }
    public static let textoSinMicrofono = "Para mandarme audios, permití el micrófono en Ajustes."
    public static let textoSinCamara = "Para sacar la foto desde acá, permití la cámara en Ajustes."
    public static let textoAbrirAjustes = "Abrir ajustes"
    public static let textoFotoIlegible = "Esa foto no se pudo abrir. Probá con otra."
    /// Un audio grabado desde la web en un navegador que graba en otro formato: el iPhone no lo reproduce.
    public static let textoNoSeEscucha = "Este audio no se puede escuchar en el teléfono."
    public static let textoBorrar = "Borrar"

    /// «42 segundos», «1 minuto 5 segundos»: lo que lee VoiceOver.
    public static func duracionHablada(_ s: Double) -> String {
        let t = max(0, Int(s.isFinite ? s.rounded() : 0))
        let m = t / 60, r = t % 60
        let seg = r == 1 ? "1 segundo" : "\(r) segundos"
        guard m > 0 else { return seg }
        let min = m == 1 ? "1 minuto" : "\(m) minutos"
        return r == 0 ? min : "\(min) \(seg)"
    }

    /// El texto de una burbuja que no salió, según el motivo con que la cola la dejó.
    public static func textoFallo(motivo: String?) -> String {
        switch motivo {
        case codigoTope?: return textoTope
        case codigoSinArchivo?: return textoSinArchivo
        default: return textoNoSalio
        }
    }

    /// ¿Tiene sentido ofrecer «Reintentar»? Sin el archivo, no.
    public static func sePuedeReintentar(motivo: String?) -> Bool { motivo != codigoSinArchivo }

    // MARK: - Códigos de la cola (van directo a «no salió», sin gastar los 8 intentos)

    public static let codigoTope = "ADJUNTO_TOPE"
    public static let codigoRechazo = "ADJUNTO_RECHAZO"
    public static let codigoSinArchivo = "ADJUNTO_SIN_ARCHIVO"
    public static let codigoId = "ADJUNTO_ID"
    public static let codigosDirectos: Set<String> = [codigoTope, codigoRechazo, codigoSinArchivo, codigoId]
}
