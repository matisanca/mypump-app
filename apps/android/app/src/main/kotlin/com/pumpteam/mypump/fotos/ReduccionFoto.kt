package com.pumpteam.mypump.fotos

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.media.ExifInterface
import android.net.Uri
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * `_fotoABase64Reducida` de la web (y `ReduccionFoto` de iOS): la foto con el lado mayor ≤ `maxPx`, en JPEG con `calidad`,
 * con la orientación de la cámara ya aplicada y SIN metadatos (ni EXIF ni la ubicación). Lee lo que lea `BitmapFactory`:
 * JPEG, PNG, WebP y, desde Android 9, HEIC. Nunca agranda una foto más chica.
 *
 * Sin decodificar la foto entera: primero se leen las medidas, después se decodifica achicada de a potencias de 2 (sin
 * bajar del tamaño final) y recién ahí se escala justo. Una de 48 MP decodificada entera son ~190 MB, y eso puede hacer
 * que Android cierre la app.
 *
 * La orientación sale de `android.media.ExifInterface` (la del sistema, sin librerías) y se aplica a mano:
 * `BitmapFactory` la ignora siempre, en JPEG y en HEIC, así que no hay riesgo de girarla dos veces. `Bitmap.compress` no
 * escribe metadatos: lo que sale no lleva el EXIF ni el GPS de la original.
 *
 * Las de progreso van a 900 px y 0,7 (como la web); después la va a usar Dieta (la IA mira la foto a 0,85).
 */
object ReduccionFoto {
    /** Las fotos de progreso: 900 px de lado mayor, JPEG a 0,7 (REV-02). */
    const val LADO_PROGRESO = 900
    const val CALIDAD_PROGRESO = 0.7

    /** null si los datos no son una imagen. */
    fun jpeg(datos: ByteArray, maxPx: Int, calidad: Double): ByteArray? = jpeg({ ByteArrayInputStream(datos) }, maxPx, calidad)

    /** La foto que devolvió la cámara o la galería (un `content://`). Se lee tres veces sin guardarla entera en memoria. */
    fun jpeg(resolver: ContentResolver, uri: Uri, maxPx: Int, calidad: Double): ByteArray? =
        jpeg({ resolver.openInputStream(uri) }, maxPx, calidad)

    private fun jpeg(abrir: () -> InputStream?, maxPx: Int, calidad: Double): ByteArray? = try {
        reducir(abrir, maxPx, calidad)
    } catch (_: Exception) {
        // Un archivo que no se puede abrir o leer (un permiso que venció, una foto de la nube que no bajó): no es una foto.
        null
    } catch (_: OutOfMemoryError) {
        null
    }

    private fun reducir(abrir: () -> InputStream?, maxPx: Int, calidad: Double): ByteArray? {
        if (maxPx <= 0) return null
        // 1. Las medidas, sin decodificar.
        val medidas = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        (abrir() ?: return null).use { BitmapFactory.decodeStream(it, null, medidas) }
        val ancho = medidas.outWidth
        val alto = medidas.outHeight
        if (ancho <= 0 || alto <= 0) return null

        // 2. La orientación de la cámara. Si no se puede leer, la foto va como está.
        val orientacion = try {
            abrir()?.use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
        } catch (_: Exception) {
            null
        } ?: ExifInterface.ORIENTATION_NORMAL
        val girada = orientacion in GIRAN
        val anchoVisto = if (girada) alto else ancho
        val altoVisto = if (girada) ancho else alto
        val escala = min(1.0, maxPx.toDouble() / max(anchoVisto, altoVisto))
        val anchoFinal = max(1, (anchoVisto * escala).roundToInt())
        val altoFinal = max(1, (altoVisto * escala).roundToInt())

        // 3. Decodificada de a potencias de 2, sin bajar del lado final.
        var muestra = 1
        while (max(ancho, alto) / (muestra * 2) >= max(anchoFinal, altoFinal)) muestra *= 2
        val opciones = BitmapFactory.Options().apply {
            inSampleSize = muestra
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val fuente = (abrir() ?: return null).use { BitmapFactory.decodeStream(it, null, opciones) } ?: return null

        // 4. Derecha y al tamaño justo, sobre blanco (un PNG transparente no sale negro).
        val destino = try {
            Bitmap.createBitmap(anchoFinal, altoFinal, Bitmap.Config.ARGB_8888)
        } catch (e: Throwable) {
            fuente.recycle()
            throw e
        }
        try {
            val m = matrizDeOrientacion(orientacion)
            val caja = RectF(0f, 0f, fuente.width.toFloat(), fuente.height.toFloat())
            m.mapRect(caja)
            m.postTranslate(-caja.left, -caja.top)
            m.postScale(anchoFinal / caja.width(), altoFinal / caja.height())
            Canvas(destino).apply {
                drawColor(Color.WHITE)
                drawBitmap(fuente, m, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
            }
            // 5. JPEG sin metadatos: `compress` no copia nada de la original.
            val salida = ByteArrayOutputStream()
            if (!destino.compress(Bitmap.CompressFormat.JPEG, (calidad * 100).roundToInt().coerceIn(0, 100), salida)) return null
            return salida.toByteArray()
        } finally {
            fuente.recycle()
            destino.recycle()
        }
    }

    /** Las orientaciones que cambian ancho por alto. */
    private val GIRAN = setOf(
        ExifInterface.ORIENTATION_TRANSPOSE, ExifInterface.ORIENTATION_ROTATE_90,
        ExifInterface.ORIENTATION_TRANSVERSE, ExifInterface.ORIENTATION_ROTATE_270,
    )

    /** Lo que hay que hacerle a la foto guardada para verla derecha (las 8 orientaciones de EXIF). */
    private fun matrizDeOrientacion(orientacion: Int): Matrix = Matrix().apply {
        when (orientacion) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                setRotate(90f)
                postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                setRotate(-90f)
                postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
        }
    }
}
