package com.pumpteam.mypump.guia

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.view.View
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.ui.PlayerView
import com.pumpteam.mypump.reglas.ReglasVideo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * La última proporción conocida de cada clip, por id (para que la caja no salte mientras carga). En memoria y en las
 * preferencias de la app: son números, sin nada del cliente.
 */
internal object ProporcionesVideo {
    private const val ARCHIVO = "guia-video-proporciones"
    private val memoria = HashMap<String, Float>()

    @Synchronized
    fun de(contexto: Context, id: String): Float? = memoria[id] ?: contexto.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE)
        .getFloat(id, Float.NaN).takeIf { it.isFinite() && it > 0f }?.also { memoria[id] = it }

    /** Para las pruebas: sin nada guardado. */
    @Synchronized
    fun olvidar(contexto: Context) {
        memoria.clear()
        contexto.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Synchronized
    fun guardar(contexto: Context, id: String, p: Float) {
        if (memoria[id] == p) return
        memoria[id] = p
        contexto.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE).edit().putFloat(id, p).apply()
    }
}

/**
 * La proporción del clip [id] que muestra [player]: la del `VideoSize` apenas Media3 la conoce (atada al `mediaId` del
 * item, para no darle a un clip el tamaño del anterior) y, mientras tanto, la guardada o 16:9.
 */
@Composable
internal fun proporcionDe(player: Player?, id: String?): Float {
    val contexto = LocalContext.current.applicationContext
    var p by remember(id) { mutableFloatStateOf(id?.let { ProporcionesVideo.de(contexto, it) } ?: ReglasVideo.POR_DEFECTO) }
    val idActual by rememberUpdatedState(id)
    DisposableEffect(player) {
        if (player == null) return@DisposableEffect onDispose { }
        fun tomar(v: VideoSize) {
            val del = player.currentMediaItem?.mediaId?.ifEmpty { null } ?: return
            val nueva = ReglasVideo.proporcion(v.width, v.height, v.pixelWidthHeightRatio) ?: return
            ProporcionesVideo.guardar(contexto, del, nueva)
            if (del == idActual) p = nueva
        }
        tomar(player.videoSize)
        val escucha = object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) = tomar(videoSize)
        }
        player.addListener(escucha)
        onDispose { player.removeListener(escucha) }
    }
    return p
}

/** El alto visible de la pantalla de la guía en dp (sin la barra de arriba ni las pestañas). null: el de la pantalla. */
internal val LocalAltoVisible = compositionLocalOf<Float?> { null }

/**
 * La caja del video en una tarjeta: todo el ancho con la proporción del clip y, si es vertical y no entra, el 60 % del
 * alto visible ([LocalAltoVisible]), centrada; a los costados queda el fondo de la tarjeta, nunca negro.
 */
@Composable
internal fun CajaVideo(proporcion: Float, modifier: Modifier = Modifier, contenido: @Composable BoxScope.() -> Unit) {
    val altoPantalla = LocalAltoVisible.current ?: LocalConfiguration.current.screenHeightDp.toFloat()
    BoxWithConstraints(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val (ancho, alto) = ReglasVideo.caja(proporcion, maxWidth.value, altoPantalla)
        Box(Modifier.size(ancho.dp, alto.dp).clipToBounds(), content = contenido)
    }
}

/**
 * El recuadro útil de cada clip (pedido de Mati del 6/11: hay clips con las franjas negras metidas en el archivo, como uno
 * de 1280×720 con contenido solo en las columnas 422 a 855). Se detecta una vez por url con 3 cuadros (10 %, 50 % y 90 %)
 * y queda en disco: el recorte, o «sin recorte». Si falla, no se recorta (la proporción del archivo) y se reintenta en la
 * próxima apertura de la app.
 */
internal object RecuadrosVideo {
    private const val ARCHIVO = "guia-video-recuadros"
    private const val SIN_RECORTE = "-"
    private val memoria = HashMap<String, String>()

    /** Lo guardado para [url]: null si todavía no se sabe; [SIN_RECORTE] o el recuadro en texto. */
    @Synchronized
    fun guardado(contexto: Context, url: String): String? =
        memoria[url] ?: contexto.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE).getString(url, null)?.also { memoria[url] = it }

    @Synchronized
    private fun guardar(contexto: Context, url: String, valor: String, enDisco: Boolean) {
        memoria[url] = valor
        if (enDisco) contexto.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE).edit().putString(url, valor).apply()
    }

    /** Para las pruebas: sin nada guardado. */
    @Synchronized
    fun olvidar(contexto: Context) {
        memoria.clear()
        contexto.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE).edit().clear().commit()
    }

    fun recorteGuardado(contexto: Context, url: String): ReglasVideo.Recuadro? =
        guardado(contexto, url)?.takeIf { it != SIN_RECORTE }?.let(ReglasVideo.Recuadro::desde)

    /** Detecta y guarda. Devuelve el recorte a aplicar (null = el cuadro entero). */
    suspend fun detectar(contexto: Context, url: String): ReglasVideo.Recuadro? = withContext(Dispatchers.IO) {
        // Los 3 cuadros todo negros no dicen nada (un fundido, o el decodificador ocupado que devuelve negro mientras
        // reproduce, visto en el emulador): se reintenta un par de veces antes de darlo por perdido.
        var r: Result<Medicion> = Result.failure(IllegalStateException("sin medir"))
        for (intento in 0 until 3) {
            if (intento > 0) delay(1_500)
            r = try {
                Result.success(medir(url))
            } catch (e: Exception) {
                Result.failure(e)
            }
            if (r.getOrNull()?.sabida == true) break
        }
        val m = r.getOrNull()
        // Un error (sin red, un formato raro) o sin ningún cuadro con imagen no se guarda en disco: solo en memoria, para no
        // insistir en esta sesión; en la próxima se vuelve a medir.
        guardar(contexto, url, m?.recorte?.aTexto() ?: SIN_RECORTE, enDisco = m?.sabida == true)
        m?.recorte
    }

    /** [sabida]: algún cuadro tenía imagen. [recorte]: el que se aplica (null = entero). */
    private class Medicion(val sabida: Boolean, val recorte: ReglasVideo.Recuadro?)

    /** El recorte del archivo en [url] (null = entero): la unión de 3 cuadros, con 1 px hacia adentro. */
    private fun medir(url: String): Medicion {
        val m = MediaMetadataRetriever()
        try {
            val u = Uri.parse(url)
            if (u.scheme == "file") m.setDataSource(u.path) else m.setDataSource(url, HashMap())
            val nada = Medicion(sabida = false, recorte = null)
            val duracionUs = (m.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: return nada) * 1000
            val ancho = m.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: return nada
            val alto = m.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: return nada
            if (ancho <= 0 || alto <= 0) return nada
            val chico = 320
            // El tamaño del cuadro analizado: el «1 px hacia adentro» es de ese cuadro (unos 4 px de un archivo de 1280).
            var analizado = ancho to alto
            val cuadros = listOf(0.1, 0.5, 0.9).map { f ->
                val t = (duracionUs * f).toLong()
                val b: Bitmap? = if (Build.VERSION.SDK_INT >= 27) {
                    m.getScaledFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, chico, chico)
                } else {
                    m.getFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                }
                b?.let { bmp ->
                    try {
                        val w = bmp.width
                        val h = bmp.height
                        analizado = w to h
                        val px = IntArray(w * h)
                        bmp.getPixels(px, 0, w, 0, 0, w, h)
                        val luma = IntArray(px.size) { i ->
                            val c = px[i]
                            (299 * ((c shr 16) and 0xff) + 587 * ((c shr 8) and 0xff) + 114 * (c and 0xff)) / 1000
                        }
                        ReglasVideo.recuadroDe(luma, w, h)
                    } finally {
                        bmp.recycle()
                    }
                }
            }
            val union = ReglasVideo.union(cuadros) ?: return nada
            return Medicion(sabida = true, recorte = ReglasVideo.recorte(union, analizado.first, analizado.second))
        } finally {
            try {
                m.release()
            } catch (_: Exception) {
            }
        }
    }
}

/** El recorte del clip en [url]: el guardado enseguida y, si no se sabe, lo detecta en segundo plano. */
@Composable
internal fun recorteDe(url: String?): ReglasVideo.Recuadro? {
    val contexto = LocalContext.current.applicationContext
    var r by remember(url) { mutableStateOf(url?.let { RecuadrosVideo.recorteGuardado(contexto, it) }) }
    LaunchedEffect(url) {
        if (url != null && RecuadrosVideo.guardado(contexto, url) == null) r = RecuadrosVideo.detectar(contexto, url)
    }
    return r
}

/**
 * Muestra solo la zona útil: escala y desplaza el marco del video de Media3 (`exo_content_frame`, con la superficie) para
 * que esa zona llene la vista; lo demás queda afuera (la vista recorta a sus hijos). Los controles no se mueven.
 */
internal fun aplicarRecorte(v: PlayerView, r: ReglasVideo.Recuadro?) {
    val marco = v.findViewById<View>(androidx.media3.ui.R.id.exo_content_frame) ?: return
    if (r == null || marco.width == 0 || marco.height == 0 || v.width == 0 || v.height == 0) {
        marco.scaleX = 1f
        marco.scaleY = 1f
        marco.translationX = 0f
        marco.translationY = 0f
        return
    }
    val (sx, sy, tx, ty) = ReglasVideo.transformacion(
        r, marco.left.toFloat(), marco.top.toFloat(), marco.width.toFloat(), marco.height.toFloat(), v.width.toFloat(), v.height.toFloat(),
    )
    marco.pivotX = 0f
    marco.pivotY = 0f
    marco.scaleX = sx
    marco.scaleY = sy
    marco.translationX = tx
    marco.translationY = ty
}
