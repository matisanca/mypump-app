package com.pumpteam.mypump.reglas

import kotlin.math.roundToInt

/**
 * Fotos y audios en el chat con Mati (2.3.0, `nativa_chat_adjuntos`). Las reglas puras: topes, cómo se lee lo que contesta
 * mini-vision y los textos. Lo que se hace con cada adjunto del lado de la Mini no se nombra nunca en la app. Gemelo de
 * `ReglasChatAdjuntos` de iOS.
 */
object ReglasChatAdjuntos {
    /** Grabar manteniendo apretado: a los 2 minutos se corta solo y se manda. */
    const val AUDIO_MAXIMO = 120.0

    /** Menos de esto es un toque sin querer: no se manda. */
    const val AUDIO_MINIMO = 1.0

    /** «Te quedan 10 segundos.» */
    const val AUDIO_AVISO = 110.0

    /** Arrastrar el dedo a la izquierda más que esto (dp) mientras graba = cancelar. */
    const val DESLIZAR_PARA_CANCELAR_DP = 90f

    /** La foto se redibuja (eso descarta EXIF y GPS) con el lado mayor en 1600 px, como las de progreso. */
    const val FOTO_LADO_MAXIMO = 1600
    const val FOTO_CALIDAD = 75

    /** Lo que acepta mini-vision por archivo (`MAX_CHAT_FOTO_B`, `MAX_CHAT_AUDIO_B`). */
    const val BYTES_MAXIMOS = 3 * 1024 * 1024
    const val MIME_FOTO = "image/jpeg"
    const val MIME_AUDIO = "audio/mp4"

    /** Las URLs firmadas duran 1 h: se usan 50 minutos. */
    const val FIRMA_VIGENTE_MS = 50 * 60_000L

    /** Lo que se pide firmar de una vez (`/chat/urls` acepta hasta 60). */
    const val FIRMAS_POR_PEDIDO = 60

    /** Los archivos del teléfono (lo mandado, lo bajado) se guardan esta cantidad de días y después se limpian. */
    const val DIAS_EN_EL_TELEFONO = 14L

    enum class Subida {
        OK,

        /** 403 por el token: lo decide la verificación del token de la cola. */
        TOKEN,

        /** Sin red, 5xx, 408: se reintenta solo sin gastar intento. */
        REINTENTAR,

        /** Llegó al tope del día: «no salió» con su texto, y se puede reintentar más tarde. */
        TOPE,

        /** No va a entrar nunca así (muy grande, formato, apagado): «no salió». */
        RECHAZO,

        /** El id es de otro mensaje: se reintenta con uno nuevo. */
        ID_REPETIDO,
    }

    /**
     * `POST /chat/adjunto`. Un 429 NO se reintenta solo: cada intento volvería a mandar el archivo entero por datos móviles
     * para escuchar otra vez que no.
     */
    fun subida(status: Int, ok: Boolean, error: String?): Subida {
        if (status in 200..299) return if (ok) Subida.OK else Subida.REINTENTAR
        val e = (error ?: "").lowercase()
        return when {
            status == 0 || status == 408 || status >= 500 -> Subida.REINTENTAR
            status == 429 -> Subida.TOPE
            status == 409 -> Subida.ID_REPETIDO
            (status == 401 || status == 403) && "token" in e -> Subida.TOKEN
            else -> Subida.RECHAZO
        }
    }

    // Textos (voz de Mati, sin «:», sin guiones, sin emojis)

    /** Lo que dice la fila del mensaje (igual que el `contenido` que guarda el servidor): «Audio de 0:42». */
    fun textoAudio(segundos: Double?): String = "Audio de ${duracion(segundos ?: 0.0)}"
    const val TEXTO_FOTO = "Foto"

    /** 0:07, 1:42, 2:00. Redondea al segundo, nunca negativo. */
    fun duracion(s: Double): String {
        val t = if (s.isFinite()) maxOf(0, s.roundToInt()) else 0
        return "${t / 60}:${(t % 60).toString().padStart(2, '0')}"
    }

    /** «42 segundos», «1 minuto 5 segundos»: lo que lee TalkBack. */
    fun duracionHablada(s: Double): String {
        val t = if (s.isFinite()) maxOf(0, s.roundToInt()) else 0
        val m = t / 60
        val r = t % 60
        val seg = if (r == 1) "1 segundo" else "$r segundos"
        if (m == 0) return seg
        val min = if (m == 1) "1 minuto" else "$m minutos"
        return if (r == 0) min else "$min $seg"
    }

    const val TEXTO_ADJUNTAR = "Mandar una foto"
    const val TEXTO_SACAR_FOTO = "Sacar una foto"
    const val TEXTO_ELEGIR_FOTO = "Elegir de tus fotos"
    const val TEXTO_MANTENER_PARA_GRABAR = "Mantené apretado para grabar"
    const val TEXTO_GRABAR_ACCESIBLE = "Grabar un audio"
    const val AYUDA_GRABAR_ACCESIBLE = "Tocá dos veces para empezar a grabar y otra vez para mandarlo."
    const val TEXTO_MANDAR_AUDIO_ACCESIBLE = "Mandar el audio"
    const val TEXTO_DESLIZAR_PARA_CANCELAR = "Deslizá para cancelar"
    const val TEXTO_CANCELAR = "Cancelar"
    const val TEXTO_QUEDAN_DIEZ = "Te quedan 10 segundos"
    const val TEXTO_MUY_CORTO = "Mantené apretado mientras hablás."
    const val TEXTO_NO_SALIO = "No salió."
    const val TEXTO_REINTENTAR = "Reintentar"
    const val TEXTO_BORRAR = "Borrar"
    const val TEXTO_TOPE = "Por hoy llegaste al máximo de fotos y audios. Probá mañana."
    const val TEXTO_SIN_ARCHIVO = "Este archivo ya no está en el teléfono."
    const val TEXTO_NO_DISPONIBLE = "Ya no está disponible."
    const val TEXTO_NO_CARGA = "No se pudo cargar. Tocá para probar de nuevo."
    const val TEXTO_REPRODUCIR = "Escuchar"
    const val TEXTO_PAUSAR = "Pausar"
    const val TEXTO_CERRAR = "Cerrar"
    const val TEXTO_FOTO_ACCESIBLE = "Foto"
    const val TEXTO_SIN_MICROFONO = "Para mandarme audios, permití el micrófono en Ajustes."
    const val TEXTO_ABRIR_AJUSTES = "Abrir ajustes"
    const val TEXTO_FOTO_ILEGIBLE = "Esa foto no se pudo abrir. Probá con otra."

    /** Un audio grabado desde la web en un navegador que graba en otro formato: el teléfono no lo reproduce. */
    const val TEXTO_NO_SE_ESCUCHA = "Este audio no se puede escuchar en el teléfono."

    fun textoAudioAccesible(segundos: Double?): String = "Audio de ${duracionHablada(segundos ?: 0.0)}"

    /** El texto de una burbuja que no salió, según el motivo con que la cola la dejó. */
    fun textoFallo(motivo: String?): String = when (motivo) {
        CODIGO_TOPE -> TEXTO_TOPE
        CODIGO_SIN_ARCHIVO -> TEXTO_SIN_ARCHIVO
        else -> TEXTO_NO_SALIO
    }

    /** ¿Tiene sentido ofrecer «Reintentar»? Sin el archivo, no. */
    fun sePuedeReintentar(motivo: String?): Boolean = motivo != CODIGO_SIN_ARCHIVO

    // Códigos de la cola (van directo a «no salió», sin gastar los 8 intentos)

    const val CODIGO_TOPE = "ADJUNTO_TOPE"
    const val CODIGO_RECHAZO = "ADJUNTO_RECHAZO"
    const val CODIGO_SIN_ARCHIVO = "ADJUNTO_SIN_ARCHIVO"
    const val CODIGO_ID = "ADJUNTO_ID"
    val CODIGOS_DIRECTOS: Set<String> = setOf(CODIGO_TOPE, CODIGO_RECHAZO, CODIGO_SIN_ARCHIVO, CODIGO_ID)

    /** Todos los textos de la pantalla (para el test que mira que no nombren nada interno). */
    val TEXTOS: List<String> = listOf(
        TEXTO_ADJUNTAR, TEXTO_SACAR_FOTO, TEXTO_ELEGIR_FOTO, TEXTO_MANTENER_PARA_GRABAR, TEXTO_GRABAR_ACCESIBLE, AYUDA_GRABAR_ACCESIBLE,
        TEXTO_MANDAR_AUDIO_ACCESIBLE, TEXTO_DESLIZAR_PARA_CANCELAR, TEXTO_CANCELAR, TEXTO_QUEDAN_DIEZ, TEXTO_MUY_CORTO, TEXTO_NO_SALIO,
        TEXTO_REINTENTAR, TEXTO_BORRAR, TEXTO_TOPE, TEXTO_SIN_ARCHIVO, TEXTO_NO_DISPONIBLE, TEXTO_NO_CARGA, TEXTO_REPRODUCIR,
        TEXTO_PAUSAR, TEXTO_CERRAR, TEXTO_FOTO_ACCESIBLE, TEXTO_SIN_MICROFONO, TEXTO_ABRIR_AJUSTES, TEXTO_FOTO_ILEGIBLE,
        TEXTO_NO_SE_ESCUCHA,
    )
}
