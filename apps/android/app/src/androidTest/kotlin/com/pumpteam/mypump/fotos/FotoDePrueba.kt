package com.pumpteam.mypump.fotos

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.ExifInterface
import java.io.ByteArrayInputStream
import java.io.File

/**
 * Fotos armadas en el teléfono para las pruebas: ruido determinístico (la compresión tiene trabajo), un bloque rojo arriba a
 * la izquierda (para ver hacia dónde quedó girada) y, si se pide, el EXIF de una foto de cámara (orientación, GPS y un
 * comentario), escrito con el `ExifInterface` del sistema.
 */
object FotoDePrueba {
    fun imagen(ancho: Int, alto: Int): Bitmap {
        val pixeles = IntArray(ancho * alto)
        var semilla = 12345
        for (i in pixeles.indices) {
            semilla = semilla * 1_103_515_245 + 12345
            val x = i % ancho
            val y = i / ancho
            pixeles[i] = if (x < ancho / 8 && y < alto / 8) {
                Color.rgb(230, 20, 20)
            } else {
                val v = ((semilla ushr 16) and 0xFF) / 2 + x * 128 / ancho
                Color.rgb(v / 3, v.coerceAtMost(255), (255 - v).coerceIn(0, 255))
            }
        }
        return Bitmap.createBitmap(pixeles, ancho, alto, Bitmap.Config.ARGB_8888)
    }

    /** Un JPEG como los de la cámara de un teléfono: orientación, GPS y un comentario en el EXIF. */
    fun jpegDeCamara(
        contexto: Context,
        img: Bitmap,
        orientacion: Int = ExifInterface.ORIENTATION_NORMAL,
        conGps: Boolean = true,
    ): ByteArray {
        val f = File.createTempFile("foto-prueba", ".jpg", contexto.cacheDir)
        try {
            f.outputStream().use { img.compress(Bitmap.CompressFormat.JPEG, 95, it) }
            ExifInterface(f.path).apply {
                setAttribute(ExifInterface.TAG_ORIENTATION, "$orientacion")
                if (conGps) {
                    setAttribute(ExifInterface.TAG_GPS_LATITUDE, "34/1,36/1,0/1")
                    setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "S")
                    setAttribute(ExifInterface.TAG_GPS_LONGITUDE, "58/1,24/1,0/1")
                    setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, "W")
                    setAttribute(ExifInterface.TAG_USER_COMMENT, "foto de prueba")
                }
                saveAttributes()
            }
            return f.readBytes()
        } finally {
            f.delete()
        }
    }

    class Propiedades(val ancho: Int, val alto: Int, val tipo: String?, val exif: ExifInterface)

    fun propiedades(datos: ByteArray): Propiedades {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(datos, 0, datos.size, o)
        return Propiedades(o.outWidth, o.outHeight, o.outMimeType, ExifInterface(ByteArrayInputStream(datos)))
    }

    fun esRojo(p: Int) = Color.red(p) > 180 && Color.green(p) < 90 && Color.blue(p) < 90

    /** Una miniatura lisa (para que las capturas muestren algo en el lugar de las fotos firmadas). */
    fun miniatura(color: Int, ancho: Int = 300, alto: Int = 400): ByteArray {
        val b = Bitmap.createBitmap(ancho, alto, Bitmap.Config.ARGB_8888)
        val lienzo = android.graphics.Canvas(b)
        lienzo.drawColor(color)
        val pincel = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { this.color = Color.argb(70, 255, 255, 255) }
        // Una silueta simple: cabeza y torso.
        lienzo.drawCircle(ancho / 2f, alto * 0.22f, ancho * 0.13f, pincel)
        lienzo.drawRoundRect(ancho * 0.28f, alto * 0.34f, ancho * 0.72f, alto * 0.95f, 40f, 40f, pincel)
        val salida = java.io.ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.JPEG, 85, salida)
        b.recycle()
        return salida.toByteArray()
    }
}
