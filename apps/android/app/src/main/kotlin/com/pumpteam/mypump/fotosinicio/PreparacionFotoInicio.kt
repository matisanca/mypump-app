package com.pumpteam.mypump.fotosinicio

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import com.pumpteam.mypump.fotos.ReduccionFoto
import com.pumpteam.mypump.reglas.FotosInicio
import java.io.ByteArrayOutputStream
import java.time.OffsetDateTime
import kotlin.math.roundToInt

/**
 * La foto de inicio lista para revisar: el JPEG que sube (ya reducido por [ReduccionFoto]: lado mayor ≤ 1600, 0,85, derecho y
 * sin metadatos), sus medidas, lo que midió el control de calidad sobre esos mismos píxeles y cuándo se sacó.
 */
class FotoPreparada(
    val jpeg: ByteArray,
    val ancho: Int,
    val alto: Int,
    val medida: FotosInicio.Medida,
    val tomadaEn: OffsetDateTime,
    /** Lo que se le avisa al alumno, en el orden en que se muestra. */
    val problemas: List<FotosInicio.Problema>,
    val dias: Int,
)

object PreparacionFotoInicio {
    /** null si el JPEG no se puede leer. [tomada]: la fecha del EXIF de la original (galería); sin ella, ahora. */
    fun preparar(pose: String, jpeg: ByteArray, tomada: OffsetDateTime?, ahora: OffsetDateTime = OffsetDateTime.now()): FotoPreparada? {
        val bitmap = try {
            BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 })
        } catch (_: OutOfMemoryError) {
            null
        } ?: return null
        try {
            val ancho = bitmap.width
            val alto = bitmap.height
            val medida = FotosInicio.medir(luma(bitmap), ancho, alto)
            val cuando = tomada ?: ahora
            val dias = FotosInicio.dias(cuando.toInstant(), ahora.toInstant())
            // Sin fecha de la original no se sabe cuándo se sacó: no se avisa que es vieja.
            val problemas = FotosInicio.problemas(pose, ancho, alto, medida, if (tomada != null) dias else null)
            return FotoPreparada(jpeg, ancho, alto, medida, cuando, problemas, dias)
        } finally {
            bitmap.recycle()
        }
    }

    /** Una luma por píxel, por filas ([FotosInicio.luma]). De a una fila: una foto de 1600 px no duplica la memoria. */
    private fun luma(b: Bitmap): ByteArray {
        val w = b.width
        val h = b.height
        val salida = ByteArray(w * h)
        val fila = IntArray(w)
        for (y in 0 until h) {
            b.getPixels(fila, 0, w, 0, y, w, 1)
            val base = y * w
            for (x in 0 until w) {
                val p = fila[x]
                salida[base + x] = FotosInicio.luma((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF).toByte()
            }
        }
        return salida
    }
}

/**
 * Las fotos de mentira del modo de prueba (`fotosInicioDePrueba <escenario>`): el botón de foto arma una de estas en vez de
 * abrir la cámara, y pasa por la misma reducción y el mismo control que una de verdad.
 */
object FotoSinteticaFotosInicio {
    val escenarios = listOf("buena", "oscura", "chica", "movida")

    /** buena: 1200 × 1600, clara y con bordes nítidos; oscura: igual pero sin luz; chica: 600 × 800; movida: un degradé suave. */
    fun jpeg(escenario: String): ByteArray {
        val (ancho, alto) = if (escenario == "chica") 600 to 800 else 1200 to 1600
        val b = Bitmap.createBitmap(ancho, alto, Bitmap.Config.ARGB_8888)
        try {
            val lienzo = Canvas(b)
            val pintura = Paint()
            if (escenario == "movida") {
                for (y in 0 until alto) {
                    val v = 90 + (130.0 * y / alto).roundToInt()
                    pintura.color = Color.rgb(v, v, v)
                    lienzo.drawRect(0f, y.toFloat(), ancho.toFloat(), y + 1f, pintura)
                }
            } else {
                val (claro, oscuro) = if (escenario == "oscura") 40 to 10 else 210 to 120
                lienzo.drawColor(Color.rgb(claro, claro, claro))
                pintura.color = Color.rgb(oscuro, oscuro, oscuro)
                val lado = ancho / 15
                for (fy in 0..alto / lado) for (fx in 0..ancho / lado) {
                    if ((fx + fy) % 2 == 0) lienzo.drawRect((fx * lado).toFloat(), (fy * lado).toFloat(), ((fx + 1) * lado).toFloat(), ((fy + 1) * lado).toFloat(), pintura)
                }
            }
            val salida = ByteArrayOutputStream()
            b.compress(Bitmap.CompressFormat.JPEG, (FotosInicio.CALIDAD * 100).roundToInt(), salida)
            return salida.toByteArray()
        } finally {
            b.recycle()
        }
    }
}
