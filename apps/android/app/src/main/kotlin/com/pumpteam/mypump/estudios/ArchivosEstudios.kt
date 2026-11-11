package com.pumpteam.mypump.estudios

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import com.pumpteam.mypump.datos.ColaEstudios
import com.pumpteam.mypump.fotos.ProveedorFotos
import com.pumpteam.mypump.fotos.ReduccionFoto
import com.pumpteam.mypump.reglas.Estudios
import java.io.File
import java.util.UUID

/**
 * Los archivos de «Estudios» mientras están en el teléfono. Son datos de salud: todo vive en la caché propia de la app
 * (nunca en la galería ni en almacenamiento compartido), nada pasa por un registro, y cada cosa se borra apenas deja de
 * hacer falta: lo de la hoja al enviar o cancelar, lo que se bajó para ver al cerrar.
 */
internal object ArchivosEstudios {
    /** Lo que el alumno juntó en la hoja y todavía no envió. */
    fun borradores(contexto: Context): File = File(contexto.cacheDir, ColaEstudios.CARPETA_BORRADOR)

    /** Lo que se bajó para mostrar (una orden, un estudio propio). */
    fun paraVer(contexto: Context): File = File(contexto.cacheDir, ColaEstudios.CARPETA_VER)

    /** La clave de [ProveedorFotos.archivo] para la foto que deja la cámara: `camara/foto-estudios.jpg` ([ColaEstudios.FOTO_CAMARA]). */
    const val CLAVE_CAMARA = "estudios"

    /**
     * A un nombre propio (`camara/estudios-<id>.jpg`): la foto siguiente usa el mismo archivo de la cámara y no puede pisar
     * a esta mientras se convierte. Es la foto cruda, con sus metadatos: se borra apenas se convierte, y lo que quede de
     * una vez que Android cerró la app, al abrir la hoja y al arrancar ([ColaEstudios.limpiarCache]).
     */
    fun unicaDeCamara(contexto: Context): File = File(ProveedorFotos.carpeta(contexto), "${ColaEstudios.PREFIJO_CAMARA}${UUID.randomUUID()}.jpg")

    /**
     * Lo que quedó de otra vez en la hoja y en la cámara y ya nadie usa: todo menos [vivos] (lo que está en la hoja). Solo
     * tiene sentido sin conversiones en curso. Es la lista de AHORA: lo que se cree después no está en ella.
     */
    fun restos(contexto: Context, vivos: Set<String>): List<File> =
        borradores(contexto).listFiles().orEmpty().filter { it.absolutePath !in vivos } +
            ProveedorFotos.carpeta(contexto).listFiles().orEmpty().filter { it.name.startsWith(ColaEstudios.PREFIJO_CAMARA) }

    sealed interface Resultado {
        data class Listo(val archivo: File, val mime: String) : Resultado
        data object Ilegible : Resultado
        data object MuyPesado : Resultado
    }

    /** Una foto (JPEG, PNG, HEIC…) a JPEG de 2400 px y 0,8, derecha y sin metadatos (ni la ubicación). */
    fun foto(contexto: Context, resolver: ContentResolver, uri: Uri, topeMb: Int): Resultado {
        val jpeg = ReduccionFoto.jpeg(resolver, uri, Estudios.MAX_PX, Estudios.CALIDAD) ?: return Resultado.Ilegible
        if (Estudios.pesaDeMas(jpeg.size.toLong(), topeMb)) return Resultado.MuyPesado
        val destino = nuevo(contexto, "jpg")
        return try {
            destino.writeBytes(jpeg)
            Resultado.Listo(destino, Estudios.MIME_JPEG)
        } catch (_: Exception) {
            destino.delete()
            Resultado.Ilegible
        }
    }

    /** Un PDF tal cual. Se corta apenas pasa el tope, y lo que no empieza como un PDF no se acepta. */
    fun pdf(contexto: Context, resolver: ContentResolver, uri: Uri, topeMb: Int): Resultado {
        val destino = nuevo(contexto, "pdf")
        val tope = topeMb.toLong() * 1024 * 1024
        try {
            var total = 0L
            var principio = ByteArray(0)
            (resolver.openInputStream(uri) ?: return Resultado.Ilegible).use { entrada ->
                destino.outputStream().use { salida ->
                    val bloque = ByteArray(64 * 1024)
                    while (true) {
                        val n = entrada.read(bloque)
                        if (n < 0) break
                        if (principio.size < 5) principio += bloque.copyOf(minOf(n, 5 - principio.size))
                        total += n
                        if (total > tope) {
                            destino.delete()
                            return Resultado.MuyPesado
                        }
                        salida.write(bloque, 0, n)
                    }
                }
            }
            if (!Estudios.esPdf(principio)) {
                destino.delete()
                return Resultado.Ilegible
            }
            return Resultado.Listo(destino, Estudios.MIME_PDF)
        } catch (_: Exception) {
            destino.delete()
            return Resultado.Ilegible
        }
    }

    private fun nuevo(contexto: Context, extension: String): File {
        val carpeta = borradores(contexto).apply { mkdirs() }
        return File(carpeta, "${UUID.randomUUID()}.$extension")
    }
}
