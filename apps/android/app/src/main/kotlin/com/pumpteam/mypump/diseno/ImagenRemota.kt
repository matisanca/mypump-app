package com.pumpteam.mypump.diseno

import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.annotation.VisibleForTesting
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Las fotos del catálogo de ejercicios (el `AsyncImage` de iOS). Sin librerías de imágenes (no se agregan dependencias):
 * se bajan con `HttpURLConnection`, se decodifican achicadas al lado que se va a mostrar y quedan en memoria (las mismas
 * miniaturas aparecen en la lista, en el detalle y al sustituir). Sin red, o si la foto no está, se ve el marcador.
 */
object ImagenesRemotas {
    /**
     * Lo que baja los bytes de una foto. Las pruebas de interfaz lo cambian por uno sin red (y la demo, que no toca la red,
     * igual muestra las fotos si el teléfono tiene señal: son públicas, como en iOS y en la web).
     */
    @VisibleForTesting
    @Volatile
    var bajar: suspend (String) -> ByteArray? = { descargar(it) }

    /** La de siempre: por la red (para que las pruebas la vuelvan a poner). */
    @VisibleForTesting
    val porRed: suspend (String) -> ByteArray? = { descargar(it) }

    /** Hasta ~24 MB de fotos decodificadas. */
    private val memoria = object : LruCache<String, ImageBitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ImageBitmap): Int = value.width * value.height * 4
    }

    /** Lo que ya se está bajando (se usa desde el hilo principal): dos miniaturas iguales no bajan dos veces. */
    private val enCurso = HashMap<String, CompletableDeferred<ImageBitmap?>>()

    /** El lado se redondea hacia arriba a múltiplos de 128 px: la misma foto en tamaños parecidos se reusa. */
    private fun clave(url: String, ladoPx: Int): String = "${(ladoPx + 127) / 128 * 128}|$url"

    fun enMemoria(url: String, ladoPx: Int): ImageBitmap? = memoria.get(clave(url, ladoPx))

    @VisibleForTesting
    fun vaciar() {
        memoria.evictAll()
    }

    suspend fun cargar(url: String, ladoPx: Int): ImageBitmap? {
        if (!url.startsWith("https://")) return null
        val k = clave(url, ladoPx)
        memoria.get(k)?.let { return it }
        enCurso[k]?.let { return it.await() }
        val d = CompletableDeferred<ImageBitmap?>()
        enCurso[k] = d
        var imagen: ImageBitmap? = null
        try {
            val bytes = bajar(url)
            imagen = bytes?.let { withContext(Dispatchers.Default) { decodificar(it, (ladoPx + 127) / 128 * 128) } }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Sin red, un 404 o una foto rota: queda el marcador.
        } finally {
            imagen?.let { memoria.put(k, it) }
            enCurso.remove(k)
            d.complete(imagen)
        }
        return imagen
    }

    private suspend fun descargar(url: String): ByteArray? = withContext(Dispatchers.IO) {
        val conexion = URL(url).openConnection() as HttpURLConnection
        try {
            conexion.connectTimeout = 15_000
            conexion.readTimeout = 20_000
            if (conexion.responseCode != 200) return@withContext null
            conexion.inputStream.use { entrada ->
                val salida = ByteArrayOutputStream()
                val buffer = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val n = entrada.read(buffer)
                    if (n < 0) break
                    total += n
                    // Una foto del catálogo pesa decenas de KB: lo que pase de 8 MB no es una foto que sirva acá.
                    if (total > 8 * 1024 * 1024) return@withContext null
                    salida.write(buffer, 0, n)
                }
                salida.toByteArray()
            }
        } finally {
            conexion.disconnect()
        }
    }

    /** Decodifica achicando de a potencias de 2 hasta que el lado menor quede apenas por encima del pedido. */
    private fun decodificar(bytes: ByteArray, ladoPx: Int): ImageBitmap? {
        val medidas = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, medidas)
        if (medidas.outWidth <= 0 || medidas.outHeight <= 0) return null
        var muestra = 1
        while (minOf(medidas.outWidth, medidas.outHeight) / (muestra * 2) >= ladoPx) muestra *= 2
        val opciones = BitmapFactory.Options().apply { inSampleSize = muestra }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opciones)?.asImageBitmap()
    }
}

/**
 * Una foto de internet que llena su lugar (recortada al centro), con [marcador] mientras carga o si no se pudo.
 * [lado] es el lado mayor con el que se va a ver (para no decodificar una foto más grande que su lugar).
 */
@Composable
fun ImagenRemota(url: String?, lado: Dp, modifier: Modifier = Modifier, marcador: @Composable () -> Unit) {
    val px = with(LocalDensity.current) { lado.roundToPx() }
    val imagen by produceState(initialValue = url?.let { ImagenesRemotas.enMemoria(it, px) }, url, px) {
        if (value == null && url != null) value = ImagenesRemotas.cargar(url, px)
    }
    Crossfade(targetState = imagen, animationSpec = tween(250), modifier = modifier, label = "foto") { i ->
        Box(Modifier.fillMaxSize()) {
            if (i != null) Image(i, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop) else marcador()
        }
    }
}
