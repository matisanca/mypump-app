package com.pumpteam.mypump.fotos

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import com.pumpteam.mypump.R
import java.io.File

/**
 * El FileProvider propio de las fotos. La cámara del teléfono (`TakePicture`) deja la foto en un archivo de la caché de
 * MyPump que se le presta con este provider, solo para esa foto: así MyPump no pide el permiso CAMERA (la foto la saca la
 * app de cámara) ni guarda nada en la galería del cliente.
 *
 * Es una subclase para que su entrada del manifest no choque con la de una librería que use `FileProvider` tal cual. Solo
 * comparte `cache/camara/` (`res/xml/rutas_fotos.xml`), y cada foto se borra apenas se lee.
 */
class ProveedorFotos : FileProvider(R.xml.rutas_fotos) {
    companion object {
        fun autoridad(contexto: Context): String = "${contexto.packageName}.fotos"

        /** La carpeta compartida: la caché, fuera del backup y de la galería. */
        fun carpeta(contexto: Context): File = File(contexto.cacheDir, "camara")

        /** Donde la cámara deja la foto de [clave] ("frente"): una por lugar, así se encuentra aunque Android cierre la app. */
        fun archivo(contexto: Context, clave: String): File = File(carpeta(contexto), "foto-${clave.filter(Char::isLetterOrDigit)}.jpg")

        fun uri(contexto: Context, archivo: File): Uri = getUriForFile(contexto, autoridad(contexto), archivo)

        /** El archivo vacío y su `content://`, listos para pasárselos a la cámara. */
        fun paraLaCamara(contexto: Context, clave: String): Pair<File, Uri> {
            val a = archivo(contexto, clave)
            a.parentFile?.mkdirs()
            a.delete()
            a.createNewFile()
            return a to uri(contexto, a)
        }
    }
}
