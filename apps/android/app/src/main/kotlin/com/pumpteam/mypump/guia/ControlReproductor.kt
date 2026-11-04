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

    var player: ExoPlayer? = null
        private set

    private var modelo: ModeloGuia? = null

    /** Los clips en el orden en que se muestran ([ReglasGuia.ordenados]). */
    var clips: List<ClipGuia> by mutableStateOf(emptyList())
        private set

    /** El índice (en [clips]) del video cargado; -1 si ninguno. */
    var actual by mutableStateOf(-1)
        private set

    var placa by mutableStateOf<Placa?>(null)
        private set

    var velocidad by mutableStateOf(1f)
        private set

    var pantallaCompleta by mutableStateOf(false)

    /** El último error de carga (sin red): la vista muestra «Necesitás conexión para ver el video». */
    var sinConexion by mutableStateOf(false)
        private set

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
            if (isPlaying) leer() else {
                lectura?.cancel()
                seguimiento?.alInterrumpir()
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            val p = player ?: return
            when (playbackState) {
                Player.STATE_READY -> {
                    sinConexion = false
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
            sinConexion = true
            reproduciendo = false
        }
    }

    /**
     * La guía que se muestra (al abrirla o cuando cambia). Con otra cuenta (otro [ModeloGuia]) o sin video cargado, carga
     * el inicial sin reproducir; con la misma, solo actualiza la lista (lo visto, las dudas) sin cortar lo que suena.
     */
    fun usar(m: ModeloGuia, todos: List<ClipGuia>) {
        val nuevos = ReglasGuia.ordenados(todos)
        val otraCuenta = m !== modelo
        modelo = m
        val idActual = clipActual?.id
        clips = nuevos
        if (otraCuenta || idActual == null) {
            detener()
            val i = ReglasReproductor.indiceInicial(nuevos)
            if (i >= 0) cargar(i, reproducir = false, conPlaca = false)
            return
        }
        // El mismo video pudo haber cambiado de lugar (no pasa: el orden es del servidor), o desaparecer.
        val i = nuevos.indexOfFirst { it.id == idActual }
        if (i >= 0) actual = i else {
            detener()
            ReglasReproductor.indiceInicial(nuevos).takeIf { it >= 0 }?.let { cargar(it, reproducir = false, conPlaca = false) }
        }
    }

    /** Tocar una fila: arranca directo, sin placa (como la web). */
    fun reproducir(indice: Int) {
        if (clips.getOrNull(indice)?.sePuedeVer != true) return
        if (indice == actual && placa == null && !sinConexion) {
            player?.play()
            elegido++
            return
        }
        cargar(indice, reproducir = true, conPlaca = false)
        elegido++
    }

    /** «Ver por qué» de la suplementación: el clip por su id. */
    fun reproducirPorId(id: String) {
        val i = clips.indexOfFirst { it.id == id }
        if (i >= 0) reproducir(i)
    }

    val haySiguiente: Boolean get() = actual >= 0 && ReglasReproductor.siguiente(clips, actual) != null
    val hayAnterior: Boolean get() = actual >= 0 && ReglasReproductor.anterior(clips, actual) != null

    fun siguiente() {
        ReglasReproductor.siguiente(clips, actual)?.let { cargar(it, reproducir = true, conPlaca = true) }
    }

    fun anterior() {
        ReglasReproductor.anterior(clips, actual)?.let { cargar(it, reproducir = true, conPlaca = true) }
    }

    /** 1x → 1,25x → 1,5x → 1x. */
    fun cambiarVelocidad() {
        velocidad = ReglasReproductor.velocidadSiguiente(velocidad)
        player?.setPlaybackSpeed(velocidad)
    }

    /** Tocar la placa (o que pasen los 2,6 s): arranca el video. */
    fun cerrarPlaca() {
        if (placa == null) return
        temporizadorPlaca?.cancel()
        placa = null
        player?.play()
    }

    /** Volvió la conexión (o el cliente tocó «Reintentar»): se carga de nuevo donde estaba. */
    fun reintentar() {
        val p = player ?: return
        sinConexion = false
        p.prepare()
        p.play()
    }

    /** La app se fue atrás o se salió de la guía: el video se frena (no sigue sonando). */
    fun pausar() {
        player?.pause()
    }

    /** El ViewModel se va: se suelta el reproductor. */
    fun liberar() {
        detener()
        player?.removeListener(escucha)
        player?.release()
        player = null
        modelo = null
        clips = emptyList()
        actual = -1
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
        sinConexion = false
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
        // Lo del video que se deja: si estaba corriendo, el último tramo se guarda (un salto no pierde los segundos).
        actual = indice
        seguimiento = SeguimientoAvance(c)
        retomarPendiente = true
        sinConexion = false
        p.setMediaItem(MediaItem.Builder().setUri(url).setMediaId(c.id).build())
        p.setPlaybackSpeed(velocidad)
        p.prepare()
        if (reproducir && conPlaca) {
            placa = Placa(indice, clips.size, c.bloque, c.titulo)
            pasado++
            p.playWhenReady = false
            temporizadorPlaca = alcance.launch {
                delay(ReglasReproductor.PLACA_MS)
                cerrarPlaca()
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
        // Pasa solo al siguiente, con su placa. Si era el último, queda en el final.
        ReglasReproductor.siguiente(clips, actual)?.let { cargar(it, reproducir = true, conPlaca = true) }
    }

    private fun guardar(g: SeguimientoAvance.Guardado) {
        val m = modelo ?: return
        alcance.launch { m.guardarAvance(g) }
    }
}
