package com.pumpteam.mypump.reglas

/**
 * Las dudas en audio de «Tu guía» (2.1.0, pedido de Mati del 4-nov): los textos, los topes y la máquina de estados del
 * grabador, sin Android. La fuente es la especificación de la web (`AUDIO-DUDAS-UI.md` de la obra de entregas); lo que
 * cambia en la app está en `AUDIO_APP.md` de la evidencia de la guía. El contrato es el de `entregas_019` (por token).
 *
 * El grabador de verdad (MediaRecorder) y el permiso del micrófono son de la app: acá entra lo que pasó (tocó, empezó a
 * grabar, pasó el tiempo, la app se fue a segundo plano) y sale el estado nuevo con lo que hay que hacer ([Efecto]).
 */
object ReglasAudioDuda {
    /** El tope de un audio: a los 5 minutos corta solo y pasa a revisar. */
    const val TOPE_S = 300

    /** A los 4 min 30 s, el aviso. */
    const val AVISO_S = 270

    /** Menos de 2 s no se manda. */
    const val MINIMO_S = 2

    /** El formato de las dos apps: AAC en MPEG-4 (`.m4a`). La subida usa el `mime` que devuelve `iniciar`. */
    const val MIME = "audio/mp4"

    /** Lo que se le pregunta a `entregas_app_audios` mientras alguno está en `subido`: cada 15 s y hasta 3 minutos. */
    const val CONSULTA_CADA_MS = 15_000L
    const val CONSULTA_HASTA_MS = 180_000L

    /** Un ticket de subida vale 30 minutos. */
    const val TICKET_MS = 30 * 60_000L

    // ── Textos (voz de Mati, sin «:», sin guiones, sin emojis; los de la web tal cual salvo lo que es del navegador) ──

    // Mati, 4-nov 18:40: el cliente NO se entera de que el audio se pasa a texto (como pack.html, cerebro 1a9c5e6).
    const val INVITACION = "¿Te es más fácil hablarlo? Mandame un audio, como por WhatsApp. Hasta 5 minutos cada uno."
    const val GRABAR = "Grabar un audio"
    const val TERMINAR = "Terminar"
    const val TERMINAR_ACCESIBLE = "Terminar de grabar"
    const val ANTES_DEL_PERMISO = "Te va a pedir permiso para usar el micrófono, aceptalo así te escucho."
    const val QUEDAN_30 = "Te quedan 30 segundos."
    const val MANDAR = "Mandar"
    const val GRABAR_DE_NUEVO = "Grabar de nuevo"
    const val BORRAR = "Borrar"
    const val MANDANDO = "Mandando tu audio…"
    const val NO_SE_PUDO = "No se pudo mandar."
    const val REINTENTAR = "Reintentar"
    /** Subido o transcripto se ve igual: la transcripción nunca aparece en pantalla. */
    const val SUBIDO = "Listo, me llegó tu audio, lo escucho antes de la videollamada."
    const val SUBIDO_DESPUES = "Listo, me llegó tu audio, te contesto por WhatsApp."
    const val ERROR_AUDIO = "No pude escuchar bien este audio, ¿me lo mandás de nuevo o lo escribís?"
    const val MUY_CORTO = "No se escuchó nada, probá de nuevo."
    const val VISTA_PREVIA = "Vista previa: el audio no se manda."

    /** El modo silencio de iOS no existe igual en Android: lo que apaga la revisión es el volumen multimedia. */
    const val SIN_SONIDO = "Si no lo escuchás, fijate que el volumen del celu no esté en cero."

    /** `NotAllowedError` de la web, adaptado a la app: en Android el permiso está en los ajustes de la app. */
    const val PERMISO_NEGADO = "Tu celu no me dio permiso para el micrófono. Tocá «Abrir ajustes», entrá en Permisos, Micrófono y ponelo en Permitir. O escribime la duda acá arriba."
    const val ABRIR_AJUSTES = "Abrir ajustes"
    const val SIN_MICROFONO = "No encontré un micrófono en este dispositivo. Escribime la duda acá arriba."
    const val MICROFONO_OCUPADO = "El micrófono lo está usando otra app. Cerrala y probá de nuevo."

    /** Lo que ve el cliente cuando `iniciar` dice que no ([motivo] de la RPC). null: el motivo no tiene texto propio. */
    fun textoMotivo(motivo: String?): String? = when (motivo) {
        "tope" -> "Ya me mandaste 10 audios. Lo que te falte escribímelo o lo vemos en la llamada."
        "pendientes" -> "Esperá un toque que se terminen de mandar los otros audios."
        "tamano", "largo" -> "Es muy largo, mandámelo en audios de hasta 5 minutos."
        // La app siempre graba en audio/mp4: si el servidor no lo acepta, es de la app, no del navegador.
        "formato" -> "Este audio está en un formato que no puedo recibir. Escribime la duda acá arriba."
        // `error`: ese audio ya falló del lado del servidor. Si graba otro, va con un id nuevo.
        "error" -> ERROR_AUDIO
        else -> null
    }

    /**
     * Un rechazo sin motivo (o `pendientes`, que igual no llega acá: la cola lo trata como transitorio): el audio queda y
     * se puede reintentar con el mismo id. `id` (ese p_id es de otro cliente) también conserva el archivo, pero
     * «Reintentar» sale con un id nuevo ([pideIdNuevo]), como iOS (revisión del 4-nov, hallazgo 17). Los demás (`tope`,
     * `tamano`, `largo`, `formato`, `error`, el archivo perdido) no van a entrar nunca así.
     */
    fun motivoReintentable(motivo: String?): Boolean = motivo == null || motivo == "pendientes" || motivo == "id"

    /** `id`: el p_id es de otro cliente. El mismo audio se reintenta con un p_id nuevo. */
    fun pideIdNuevo(motivo: String?): Boolean = motivo == "id"

    /** El contador, como número aparte: `0:42`, `4:30`. */
    fun contador(segundos: Int): String {
        val s = segundos.coerceAtLeast(0)
        return "${s / 60}:" + (s % 60).toString().padStart(2, '0')
    }

    /** Lo que anuncia TalkBack al terminar (no cada segundo). */
    fun anuncioDuracion(segundos: Int): String = "Grabaste " + contador(segundos)

    /**
     * La deduplicación de la web: la transcripción entra después como una duda más de la videollamada; al pintarlas se
     * saltean los textos iguales a un `texto` transcripto de la lista de audios (comparados sin los espacios de las puntas).
     * Así el cliente nunca ve la transcripción.
     */
    fun sinTranscriptas(dudas: List<String>, transcriptos: Collection<String>): List<String> {
        if (transcriptos.isEmpty()) return dudas
        val t = transcriptos.mapTo(HashSet()) { it.trim() }
        return dudas.filterNot { it.trim() in t }
    }

    /**
     * Si toca preguntar de nuevo por la lista: hay alguno en `subido` y no pasaron 3 minutos desde que se empezó a seguir
     * ([desdeMs], la última vez que se mandó un audio o se abrió la sección).
     */
    fun seguirConsultando(hayEnSubido: Boolean, desdeMs: Long, ahoraMs: Long): Boolean =
        hayEnSubido && ahoraMs - desdeMs < CONSULTA_HASTA_MS
}

/**
 * La máquina de estados del grabador. Cada evento devuelve el estado nuevo y lo que la app tiene que hacer. El tiempo lo
 * pone quien llama (milisegundos de un reloj que no salta, `SystemClock.elapsedRealtime` en Android), así se prueba sin
 * esperar.
 */
object MaquinaAudioDuda {
    sealed interface Estado {
        data object Reposo : Estado

        /** Se le pidió el permiso al sistema y todavía no contestó. */
        data object PidiendoPermiso : Estado

        data class Grabando(val desdeMs: Long, val avisado: Boolean = false) : Estado {
            fun segundos(ahoraMs: Long): Int = ((ahoraMs - desdeMs) / 1000).toInt().coerceIn(0, ReglasAudioDuda.TOPE_S)
        }

        data class Revisando(val segundos: Int) : Estado
    }

    /** Un aviso para la región viva. [error] lo pinta en rojo; [ajustes] suma «Abrir ajustes». */
    data class Aviso(val texto: String, val error: Boolean = false, val ajustes: Boolean = false)

    enum class Permiso { CONCEDIDO, SIN_PEDIR, NEGADO }

    enum class Fallo { SIN_MICROFONO, OCUPADO }

    sealed interface Efecto {
        data object PedirPermiso : Efecto

        /** Pausar el video de la guía, sacar el foco del campo y arrancar el grabador. */
        data object Empezar : Efecto

        /** Frenar el grabador (el archivo queda para revisar). */
        data object Detener : Efecto

        /** Frenar si está grabando y borrar el archivo. */
        data object Descartar : Efecto

        /** Mandarlo por la cola ([segundos] es lo que se le pasa a `iniciar`). */
        data class Encolar(val segundos: Int) : Efecto
    }

    data class Paso(val estado: Estado, val aviso: Aviso?, val efectos: List<Efecto> = emptyList())

    /** Tocó «Grabar un audio» (o «Grabar de nuevo»). */
    fun grabar(estado: Estado, permiso: Permiso): Paso {
        val descartar = if (estado is Estado.Revisando) listOf(Efecto.Descartar) else emptyList()
        return when (permiso) {
            Permiso.CONCEDIDO -> Paso(Estado.Reposo, null, descartar + Efecto.Empezar)
            Permiso.SIN_PEDIR -> Paso(Estado.PidiendoPermiso, null, descartar + Efecto.PedirPermiso)
            // Ya lo negó para siempre: el cartel no vuelve solo, va la explicación con «Abrir ajustes».
            Permiso.NEGADO -> Paso(Estado.Reposo, negado(), descartar)
        }
    }

    /** Lo que contestó el cartel del permiso. */
    fun permiso(concedido: Boolean): Paso =
        if (concedido) Paso(Estado.Reposo, null, listOf(Efecto.Empezar)) else Paso(Estado.Reposo, negado())

    private fun negado() = Aviso(ReglasAudioDuda.PERMISO_NEGADO, error = true, ajustes = true)

    /** El grabador arrancó de verdad. */
    fun empezo(ahoraMs: Long): Paso = Paso(Estado.Grabando(ahoraMs), null)

    /** El grabador no pudo arrancar. */
    fun noEmpezo(f: Fallo): Paso = Paso(
        Estado.Reposo,
        Aviso(if (f == Fallo.SIN_MICROFONO) ReglasAudioDuda.SIN_MICROFONO else ReglasAudioDuda.MICROFONO_OCUPADO, error = true),
        listOf(Efecto.Descartar),
    )

    /** Pasó el tiempo: a los 270 s el aviso, a los 300 s corta solo. Fuera de la grabación no hace nada. */
    fun tic(estado: Estado, ahoraMs: Long): Paso? {
        if (estado !is Estado.Grabando) return null
        val s = ((ahoraMs - estado.desdeMs) / 1000).toInt()
        if (s >= ReglasAudioDuda.TOPE_S) return terminar(estado, ahoraMs)
        if (s >= ReglasAudioDuda.AVISO_S && !estado.avisado) return Paso(estado.copy(avisado = true), Aviso(ReglasAudioDuda.QUEDAN_30))
        return null
    }

    /**
     * Tocó «Terminar», llegó al tope o la app se fue a segundo plano (pantalla bloqueada, otra app, salió de la guía): se
     * frena y pasa a revisar con lo grabado. Menos de 2 s no se manda: se borra y avisa.
     */
    fun terminar(estado: Estado, ahoraMs: Long): Paso {
        if (estado !is Estado.Grabando) return Paso(estado, null)
        val s = estado.segundos(ahoraMs)
        if (s < ReglasAudioDuda.MINIMO_S) return Paso(Estado.Reposo, Aviso(ReglasAudioDuda.MUY_CORTO, error = true), listOf(Efecto.Descartar))
        return Paso(Estado.Revisando(s), Aviso(ReglasAudioDuda.anuncioDuracion(s)), listOf(Efecto.Detener))
    }

    /** El grabador se cortó solo (un error del sistema a mitad de camino): lo que haya quedado se descarta. */
    fun seCorto(): Paso = Paso(Estado.Reposo, Aviso(ReglasAudioDuda.MICROFONO_OCUPADO, error = true), listOf(Efecto.Descartar))

    fun borrar(estado: Estado): Paso = Paso(Estado.Reposo, null, if (estado is Estado.Revisando || estado is Estado.Grabando) listOf(Efecto.Descartar) else emptyList())

    /** Tocó «Mandar». En la demo (vista previa) no sale nada: queda para escuchar, con el aviso. */
    fun mandar(estado: Estado, vistaPrevia: Boolean): Paso {
        if (estado !is Estado.Revisando) return Paso(estado, null)
        if (vistaPrevia) return Paso(estado, Aviso(ReglasAudioDuda.VISTA_PREVIA))
        return Paso(Estado.Reposo, null, listOf(Efecto.Encolar(estado.segundos)))
    }
}
