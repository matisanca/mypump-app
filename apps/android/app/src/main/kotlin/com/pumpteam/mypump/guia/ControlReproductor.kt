package com.pumpteam.mypump.guia

import android.content.Context
import androidx.annotation.OptIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.pumpteam.mypump.datos.ModeloGuia
import com.pumpteam.mypump.modelos.ClipGuia
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.reglas.ReglasGuia
import com.pumpteam.mypump.reglas.ReglasReproductor
import com.pumpteam.mypump.reglas.SeguimientoAvance
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * El reproductor de «Tu guía» (Media3), gemelo del de iOS (AVPlayer). Vive en el ViewModel: la Activity se vuelve a crear
 * al girar el teléfono y el video no se puede cortar por eso. Lo que decide (desde dónde retoma, siguiente y anterior,
 * cuándo guarda el avance) está en `ReglasReproductor` y `SeguimientoAvance`, probados en la JVM; acá solo se ejecuta.
 *
 * - **Placa** al pasar de video con «Anterior», «Siguiente» o al terminar uno (como la web; tocar una fila arranca
 *   directo): 2,6 s, se cierra sola o al tocarla, y mientras está el video no corre.
 * - **Avance**: cada medio segundo, mientras corre, le pasa la posición a [SeguimientoAvance], y lo que decide va a
 *   [ModeloGuia.guardarAvance] (la cola). Al terminar, el fin con visto, y pasa solo al siguiente.
 * - **Sin red**: el error del reproductor se muestra como «Necesitás conexión para ver el video», con «Reintentar».
 *
 * El estado es de Compose (`mutableStateOf`): la pantalla lo lee directo. Se usa desde el hilo principal.
 */
@OptIn(UnstableApi::class)
class ControlReproductor(
    private val contexto: Context,
    private val alcance: CoroutineScope,
    private val fabrica: (Context) -> ExoPlayer = { ExoPlayer.Builder(it).build() },
) {
    /** Lo que muestra la placa de «Otro tema». */
    data class Placa(val indice: Int, val total: Int, val bloque: String?, val titulo: String)

    /** Estado de Compose: la vista del video se compone antes de que exista el reproductor y tiene que enterarse. */
    var player: ExoPlayer? by mutableStateOf(null)
        private set

    private var modelo: ModeloGuia? = null

    /**
     * Los clips en el orden en que se muestran ([ReglasNovedad.ordenDeLaLista] de [Guia.clipsDeLaLista]) y, al final, los que solo
     * se ven con «Ver por qué» de su suplemento ([Guia.clipsDeSuplementos]): esos no entran en «Anterior», «Siguiente», el
     * paso solo al terminar ni el número «Video N de M».
     */
    var clips: List<ClipGuia> by mutableStateOf(emptyList())
        private set

    /** Cuántos de [clips] son de la lista (los primeros). */
    var deLaLista by mutableStateOf(0)
        private set

    private val lista: List<ClipGuia> get() = clips.take(deLaLista)

    /** El video cargado es de un suplemento (fuera de la lista). */
    val esDeSuplemento: Boolean get() = actual >= deLaLista

    /** El índice (en [clips]) del video cargado; -1 si ninguno. */
    var actual by mutableStateOf(-1)
        private set

    var placa by mutableStateOf<Placa?>(null)
        private set

    var velocidad by mutableStateOf(1f)
        private set

    var pantallaCompleta by mutableStateOf(false)

    /** La pantalla completa la puso el giro del teléfono (al volver a vertical se saca sola). Sobrevive al giro. */
    var porGiro by mutableStateOf(false)

    /** Si el video no carga: sin red o, con red, después de los reintentos solos ([RecuperacionVideo]). */
    private val recuperacion = RecuperacionVideo(contexto, alcance) { recargar() }

    val falla: FallaVideo? get() = recuperacion.falla

    /** Hay algo que mostrar en lugar del video (sin red o no cargó). */
    val sinConexion: Boolean get() = recuperacion.falla != null

    var reproduciendo by mutableStateOf(false)
        private set

    /** Cambia cada vez que se elige un video (la pantalla desplaza la lista hasta el reproductor con esto). */
    var elegido by mutableStateOf(0)
        private set

    /** Cambia cada vez que aparece la placa (otro video por «Anterior», «Siguiente» o al terminar): la pantalla trae el
     *  reproductor a la vista si había quedado arriba, para que la placa se vea. */
    var pasado by mutableStateOf(0)
        private set

    private var seguimiento: SeguimientoAvance? = null
    private var retomarPendiente = false
    private var lectura: Job? = null
    private var temporizadorPlaca: Job? = null

    val clipActual: ClipGuia? get() = clips.getOrNull(actual)

    private val escucha = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            reproduciendo = isPlaying
            if (isPlaying) {
                enPausaExterna = false
                porQuePlayer?.pause()
                leer()
            } else {
                lectura?.cancel()
                cortar()
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            val p = player ?: return
            when (playbackState) {
                Player.STATE_READY -> {
                    recuperacion.reiniciar()
                    if (retomarPendiente) {
                        retomarPendiente = false
                        val c = clipActual ?: return
                        val dur = p.duration.takeIf { it != C.TIME_UNSET }?.div(1000.0) ?: 0.0
                        val desde = ReglasReproductor.retomarDesde(c, dur)
                        if (desde > 0) p.seekTo((desde * 1000).toLong())
                    }
                }
                Player.STATE_ENDED -> alTerminar()
                else -> {}
            }
        }

        override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
            if (reason == Player.DISCONTINUITY_REASON_SEEK || reason == Player.DISCONTINUITY_REASON_SEEK_ADJUSTMENT) seguimiento?.alInterrumpir()
        }

        override fun onPlayerError(error: PlaybackException) {
            reproduciendo = false
            recuperacion.alFallar(error)
        }
    }

    /**
     * La guía que se muestra (al abrirla o cuando cambia). Con otra cuenta (otro [ModeloGuia]) o sin video cargado, carga
     * el inicial sin reproducir; con la misma, solo actualiza la lista (lo visto, las dudas) sin cortar lo que suena.
     */
    fun usar(m: ModeloGuia, guia: Guia) {
        // Los nuevos arriba (2.2.0, «Novedad»): el mismo orden que la lista, así «Video N de M» y «Siguiente» coinciden.
        val deLista = com.pumpteam.mypump.reglas.ReglasNovedad.ordenDeLaLista(guia)
        val nuevos = deLista + guia.clipsDeSuplementos
        val otraCuenta = m !== modelo
        if (otraCuenta) {
            // Lo que faltaba guardar va a la cuenta de antes, no a la nueva.
            cerrarPorQue()
            cortar()
            seguimiento = null
        }
        modelo = m
        val idActual = clipActual?.id
        clips = nuevos
        deLaLista = deLista.size
        if (otraCuenta || idActual == null) {
            cerrarPorQue()
            detener()
            val i = ReglasReproductor.indiceInicial(deLista)
            if (i >= 0) cargar(i, reproducir = false, conPlaca = false)
            return
        }
        // El mismo video pudo haber cambiado de lugar (no pasa: el orden es del servidor), o desaparecer.
        val i = nuevos.indexOfFirst { it.id == idActual }
        if (i >= 0) actual = i else {
            detener()
            ReglasReproductor.indiceInicial(deLista).takeIf { it >= 0 }?.let { cargar(it, reproducir = false, conPlaca = false) }
        }
    }

    /** Tocar una fila: arranca directo, sin placa (como la web). */
    fun reproducir(indice: Int) {
        if (clips.getOrNull(indice)?.sePuedeVer != true) return
        enPausaExterna = false
        if (indice == actual && placa == null && !sinConexion) {
            // El que terminó vuelve a empezar (si no, play() no hace nada).
            player?.let { if (it.playbackState == Player.STATE_ENDED) it.seekToDefaultPosition() }
            player?.play()
            elegido++
            return
        }
        cargar(indice, reproducir = true, conPlaca = false)
        elegido++
    }


    val haySiguiente: Boolean get() = proximo() != null
    val hayAnterior: Boolean get() = previo() != null

    private fun proximo(): Int? = if (actual in 0 until deLaLista) ReglasReproductor.siguiente(lista, actual) else null
    private fun previo(): Int? = if (actual in 0 until deLaLista) ReglasReproductor.anterior(lista, actual) else null

    fun siguiente() {
        proximo()?.let { cargar(it, reproducir = true, conPlaca = true) }
    }

    fun anterior() {
        previo()?.let { cargar(it, reproducir = true, conPlaca = true) }
    }

    /** 1x → 1,25x → 1,5x → 1x. */
    fun cambiarVelocidad() {
        velocidad = ReglasReproductor.velocidadSiguiente(velocidad)
        player?.setPlaybackSpeed(velocidad)
        porQuePlayer?.setPlaybackSpeed(velocidad)
    }

    /** El cliente tocó la placa: arranca el video. */
    fun cerrarPlaca() {
        enPausaExterna = false
        cerrarPlacaSola()
    }

    /** Pasaron los 2,6 s (o la tocó): se va la placa y arranca, salvo que la app o la guía se hayan ido ([pausar]). */
    private fun cerrarPlacaSola() {
        if (placa == null) return
        temporizadorPlaca?.cancel()
        placa = null
        if (!enPausaExterna) player?.play()
    }

    /** El cliente tocó «Reintentar»: se carga de nuevo donde estaba. */
    fun reintentar() {
        enPausaExterna = false
        recuperacion.reiniciar()
        recargar()
    }

    /** Vuelve a pedir el video donde estaba (después de un error queda parado). Suena solo si nada lo pausó de afuera. */
    private fun recargar() {
        val p = player ?: return
        p.prepare()
        if (placa == null && !enPausaExterna) p.play()
    }

    /**
     * Se pausó de afuera (la app se fue atrás, se salió de la guía): nada vuelve a sonar solo. Se corta el temporizador de
     * la placa (queda a la vista; tocarla arranca) y un reintento o la vuelta de la red solo vuelven a cargar, sin play(),
     * hasta que el cliente toque algo ([enPausaExterna]).
     */
    fun pausar() {
        enPausaExterna = true
        temporizadorPlaca?.cancel()
        player?.pause()
        porQuePlayer?.pause()
    }

    /** Lo pausó la app o la guía (no el cliente): bloquea los play() automáticos. Lo apaga cualquier play del cliente. */
    private var enPausaExterna = false

    /** El video dejó de correr: el tramo que faltaba guardar ([SeguimientoAvance.alCortar]). */
    private fun cortar() {
        val p = player ?: return
        seguimiento?.alCortar(p.currentPosition / 1000.0)?.let(::guardar)
    }

    /** El ViewModel se va: se suelta el reproductor. */
    fun liberar() {
        cerrarPorQue()
        detener()
        player?.removeListener(escucha)
        player?.release()
        player = null
        modelo = null
        clips = emptyList()
        deLaLista = 0
        actual = -1
    }

    // ── «Ver por qué»: el reproductor chico debajo del suplemento (como pack.html desde el 4/11, A5) ──
    //
    // Un solo video de suplemento abierto a la vez, con su propio reproductor: arranca solo, retoma como el de arriba
    // (espec 4.6), guarda el avance igual (cada 10 s, al 80 % con visto y al terminar, por guia_avance) y al terminar no
    // pasa a otro. Mientras suena, el de arriba se pausa (y al revés), para que no suenen dos.

    /** El id del clip abierto con «Ver por qué», o null. */
    var porQue by mutableStateOf<String?>(null)
        private set

    var porQuePlayer: ExoPlayer? by mutableStateOf(null)
        private set

    private val recuperacionPorQue = RecuperacionVideo(contexto, alcance) {
        porQuePlayer?.let {
            it.prepare()
            if (!enPausaExterna) it.play()
        }
    }

    val fallaPorQue: FallaVideo? get() = recuperacionPorQue.falla

    private var seguimientoPorQue: SeguimientoAvance? = null
    private var retomarPorQue = false
    private var lecturaPorQue: Job? = null

    private val escuchaPorQue = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (isPlaying) {
                enPausaExterna = false
                player?.pause()
                leerPorQue()
            } else {
                lecturaPorQue?.cancel()
                cortarPorQue()
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            val p = porQuePlayer ?: return
            when (playbackState) {
                Player.STATE_READY -> {
                    recuperacionPorQue.reiniciar()
                    if (retomarPorQue) {
                        retomarPorQue = false
                        val c = clips.firstOrNull { it.id == porQue } ?: return
                        val dur = p.duration.takeIf { it != C.TIME_UNSET }?.div(1000.0) ?: 0.0
                        val desde = ReglasReproductor.retomarDesde(c, dur)
                        if (desde > 0) p.seekTo((desde * 1000).toLong())
                    }
                }
                Player.STATE_ENDED -> {
                    lecturaPorQue?.cancel()
                    val s = seguimientoPorQue ?: return
                    val dur = p.duration.takeIf { it != C.TIME_UNSET && it > 0 }?.div(1000.0) ?: (p.currentPosition / 1000.0)
                    guardar(s.alTerminar(dur))
                }
                else -> {}
            }
        }

        override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
            if (reason == Player.DISCONTINUITY_REASON_SEEK || reason == Player.DISCONTINUITY_REASON_SEEK_ADJUSTMENT) seguimientoPorQue?.alInterrumpir()
        }

        override fun onPlayerError(error: PlaybackException) = recuperacionPorQue.alFallar(error)
    }

    /** El botón «Ver por qué» / «Cerrar el video» del suplemento: abre ese video debajo, o lo cierra si ya estaba abierto. */
    fun alternarPorQue(id: String) {
        if (porQue == id) {
            cerrarPorQue()
            return
        }
        val c = clips.firstOrNull { it.id == id } ?: return
        val url = c.url ?: return
        cerrarPorQue()
        enPausaExterna = false
        player?.pause()
        val p = fabrica(contexto).also {
            it.addListener(escuchaPorQue)
            it.setPlaybackSpeed(velocidad)
        }
        porQue = id
        porQuePlayer = p
        seguimientoPorQue = SeguimientoAvance(c)
        retomarPorQue = true
        recuperacionPorQue.reiniciar()
        p.setMediaItem(MediaItem.Builder().setUri(url).setMediaId(c.id).build())
        p.prepare()
        p.playWhenReady = true
    }

    /** Guarda el tramo que faltaba ([SeguimientoAvance.alCortar]) y suelta el reproductor chico. */
    fun cerrarPorQue() {
        val p = porQuePlayer ?: return
        lecturaPorQue?.cancel()
        cortarPorQue()
        p.pause()
        p.removeListener(escuchaPorQue)
        p.release()
        porQuePlayer = null
        porQue = null
        seguimientoPorQue = null
        recuperacionPorQue.soltar()
    }

    private fun cortarPorQue() {
        val p = porQuePlayer ?: return
        seguimientoPorQue?.alCortar(p.currentPosition / 1000.0)?.let(::guardar)
    }

    fun reintentarPorQue() {
        enPausaExterna = false
        recuperacionPorQue.reiniciar()
        porQuePlayer?.let { it.prepare(); it.play() }
    }

    private fun leerPorQue() {
        lecturaPorQue?.cancel()
        lecturaPorQue = alcance.launch {
            while (isActive) {
                val p = porQuePlayer ?: break
                val s = seguimientoPorQue ?: break
                val dur = p.duration.takeIf { it != C.TIME_UNSET && it > 0 }?.div(1000.0) ?: 0.0
                s.alAvanzar(p.currentPosition / 1000.0, dur)?.let { g -> guardar(g) }
                delay(500)
            }
        }
    }

    private fun asegurarPlayer(): ExoPlayer = player ?: fabrica(contexto).also {
        it.addListener(escucha)
        it.setPlaybackSpeed(velocidad)
        player = it
    }

    private fun detener() {
        lectura?.cancel()
        temporizadorPlaca?.cancel()
        placa = null
        recuperacion.reiniciar()
        player?.stop()
        player?.clearMediaItems()
        seguimiento = null
        actual = -1
    }

    private fun cargar(indice: Int, reproducir: Boolean, conPlaca: Boolean) {
        val c = clips.getOrNull(indice) ?: return
        val url = c.url ?: return
        val p = asegurarPlayer()
        lectura?.cancel()
        temporizadorPlaca?.cancel()
        // Lo del video que se deja: el tramo que faltaba guardar, antes de cambiar de video.
        cortar()
        if (reproducir) enPausaExterna = false
        actual = indice
        seguimiento = SeguimientoAvance(c)
        retomarPendiente = true
        recuperacion.reiniciar()
        p.setMediaItem(MediaItem.Builder().setUri(url).setMediaId(c.id).build())
        p.setPlaybackSpeed(velocidad)
        p.prepare()
        if (reproducir && conPlaca) {
            placa = Placa(indice, deLaLista, c.bloque, c.titulo)
            pasado++
            p.playWhenReady = false
            temporizadorPlaca = alcance.launch {
                delay(ReglasReproductor.PLACA_MS)
                cerrarPlacaSola()
            }
        } else {
            placa = null
            p.playWhenReady = reproducir
        }
    }

    /** Mientras corre: la posición cada medio segundo a [SeguimientoAvance]. */
    private fun leer() {
        lectura?.cancel()
        lectura = alcance.launch {
            while (isActive) {
                val p = player ?: break
                val s = seguimiento ?: break
                val dur = p.duration.takeIf { it != C.TIME_UNSET && it > 0 }?.div(1000.0) ?: 0.0
                s.alAvanzar(p.currentPosition / 1000.0, dur)?.let { g -> guardar(g) }
                delay(500)
            }
        }
    }

    private fun alTerminar() {
        val p = player ?: return
        val s = seguimiento ?: return
        lectura?.cancel()
        val dur = p.duration.takeIf { it != C.TIME_UNSET && it > 0 }?.div(1000.0) ?: (p.currentPosition / 1000.0)
        guardar(s.alTerminar(dur))
        // Pasa solo al siguiente, con su placa. Si era el último (o uno de un suplemento), queda en el final.
        proximo()?.let { cargar(it, reproducir = true, conPlaca = true) }
    }

    private fun guardar(g: SeguimientoAvance.Guardado) {
        val m = modelo ?: return
        alcance.launch { m.guardarAvance(g) }
    }
}
