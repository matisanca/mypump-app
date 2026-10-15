package com.pumpteam.mypump.ui

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import com.pumpteam.mypump.fotos.FotoDePrueba
import com.pumpteam.mypump.fotos.ProveedorFotos
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

/**
 * La cámara y el selector de fotos del teléfono, de mentira, para las pruebas de Dieta (el mismo monitor que usa
 * `RevisionUiTest`): contestan con la foto que dé [foto] sin abrir nada. La cámara recibe el `content://` de
 * [ProveedorFotos] y escribe ahí, como la app de cámara; el selector devuelve un archivo del mismo provider.
 */
class CamaraDePrueba(private val instr: Instrumentation, private val app: Context, private val foto: () -> ByteArray = ::fotoGrande) {
    /** Lo que se le pidió (la cámara o el selector). */
    val pedidos = CopyOnWriteArrayList<Intent>()

    private val monitor = object : Instrumentation.ActivityMonitor() {
        override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
            val accion = intent.action ?: return null
            if (accion == MediaStore.ACTION_IMAGE_CAPTURE) {
                pedidos += intent
                @Suppress("DEPRECATION")
                val salida = intent.getParcelableExtra<Uri>(MediaStore.EXTRA_OUTPUT) ?: return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
                app.contentResolver.openOutputStream(salida)!!.use { it.write(foto()) }
                return Instrumentation.ActivityResult(Activity.RESULT_OK, null)
            }
            if ("PICK_IMAGES" in accion || accion == Intent.ACTION_OPEN_DOCUMENT || accion == Intent.ACTION_GET_CONTENT) {
                pedidos += intent
                val f = File(ProveedorFotos.carpeta(app), "de-la-galeria").apply {
                    parentFile?.mkdirs()
                    writeBytes(foto())
                }
                return Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(ProveedorFotos.uri(app, f)))
            }
            return null
        }
    }

    init {
        instr.addMonitor(monitor)
    }

    fun soltar() {
        instr.removeMonitor(monitor)
        ProveedorFotos.carpeta(app).deleteRecursively()
    }

    companion object {
        /** Una foto grande de cámara (2400×1800), con la ubicación en el EXIF: la que no tiene que llegar así a la IA. */
        fun fotoGrande(): ByteArray {
            val img = FotoDePrueba.imagen(2400, 1800)
            try {
                return FotoDePrueba.jpegDeCamara(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext, img)
            } finally {
                img.recycle()
            }
        }
    }
}
