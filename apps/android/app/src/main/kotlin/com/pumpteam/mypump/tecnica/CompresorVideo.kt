package com.pumpteam.mypump.tecnica

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.pumpteam.mypump.reglas.Tecnica
import com.pumpteam.mypump.reglas.TopesTecnica
import java.io.File
import java.util.UUID
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Deja el video listo para subir: 720p, H.264, sin audio, en un archivo propio de la caché y nunca entero en memoria. Si la
 * compresión falla y el original entra en el tope, va el original. El servidor vuelve a medir. Gemelo de CompresorVideo.swift.
 */
internal object CompresorVideo {
    data class Listo(val archivo: File, val duracion: Double, val bytes: Long)

    sealed interface Resultado {
        data class Ok(val listo: Listo) : Resultado
        data class Rechazado(val rechazo: Tecnica.Rechazo) : Resultado
    }

    private const val PREFIJO = "tecnica-listo-"
    private const val LADO_CORTO = 720
    private const val BITRATE = 3_000_000
    private const val TOPE_COMPRESION_MS = 300_000L

    private data class Medida(val duracion: Double, val ladoCorto: Int)

    /** Los que quedaron de una vez anterior. */
    fun barrer(contexto: Context) {
        contexto.cacheDir.listFiles()?.filter { it.name.startsWith(PREFIJO) }?.forEach { it.delete() }
    }

    suspend fun preparar(contexto: Context, entrada: Uri, topes: TopesTecnica): Resultado = withContext(Dispatchers.IO) {
        val m = medir(contexto, entrada) ?: return@withContext Resultado.Rechazado(Tecnica.Rechazo.ILEGIBLE)
        // Lo de la duración se sabe antes de comprimir: el peso, después.
        Tecnica.validar(m.duracion, 1, topes)?.let { return@withContext Resultado.Rechazado(it) }
        val destino = File(contexto.cacheDir, "$PREFIJO${UUID.randomUUID()}.mp4")
        val comprimido = withTimeoutOrNull(TOPE_COMPRESION_MS) { exportar(contexto, entrada, destino, m.ladoCorto) } == true
        if (!comprimido && !copiar(contexto, entrada, destino, topes.bytesMax)) {
            destino.delete()
            return@withContext Resultado.Rechazado(if (tamano(contexto, entrada) > topes.bytesMax) Tecnica.Rechazo.PESADO else Tecnica.Rechazo.ILEGIBLE)
        }
        val bytes = destino.length()
        Tecnica.validar(m.duracion, bytes, topes)?.let {
            destino.delete()
            return@withContext Resultado.Rechazado(it)
        }
        Resultado.Ok(Listo(destino, m.duracion, bytes))
    }

    private fun medir(contexto: Context, uri: Uri): Medida? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(contexto, uri)
            if (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes") return null
            val ms = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toDoubleOrNull() ?: return null
            val ancho = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val alto = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            Medida(ms / 1000, minOf(ancho, alto))
        } catch (_: Exception) {
            null
        } finally {
            try {
                r.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun tamano(contexto: Context, uri: Uri): Long = try {
        contexto.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1
    } catch (_: Exception) {
        -1
    }

    private fun copiar(contexto: Context, uri: Uri, destino: File, tope: Long): Boolean = try {
        val n = tamano(contexto, uri)
        if (n > tope) {
            false
        } else {
            contexto.contentResolver.openInputStream(uri)?.use { i -> destino.outputStream().use { o -> i.copyTo(o) } }
            destino.length() in 1..tope
        }
    } catch (_: Exception) {
        false
    }

    /** `Transformer` vive en un hilo con Looper: acá, el principal; el trabajo pesado corre en los suyos. */
    @OptIn(UnstableApi::class)
    private suspend fun exportar(contexto: Context, uri: Uri, destino: File, ladoCorto: Int): Boolean = withContext(Dispatchers.Main) {
        suspendCancellableCoroutine { c ->
            val escucha = object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    if (c.isActive) c.resume(destino.length() > 0)
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    destino.delete()
                    if (c.isActive) c.resume(false)
                }
            }
            try {
                val codificador = DefaultEncoderFactory.Builder(contexto.applicationContext)
                    .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(BITRATE).build())
                    .build()
                val t = Transformer.Builder(contexto.applicationContext)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setEncoderFactory(codificador)
                    .addListener(escucha)
                    .build()
                val efectos = if (ladoCorto > LADO_CORTO) Effects(emptyList(), listOf(Presentation.createForShortSide(LADO_CORTO))) else Effects.EMPTY
                val item = EditedMediaItem.Builder(MediaItem.fromUri(uri)).setRemoveAudio(true).setEffects(efectos).build()
                t.start(item, destino.path)
                c.invokeOnCancellation { Handler(Looper.getMainLooper()).post { t.cancel() } }
            } catch (_: Exception) {
                if (c.isActive) c.resume(false)
            }
        }
    }
}
