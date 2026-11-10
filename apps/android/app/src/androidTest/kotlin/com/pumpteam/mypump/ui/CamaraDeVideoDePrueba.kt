package com.pumpteam.mypump.ui

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import com.pumpteam.mypump.fotos.ProveedorFotos
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

/**
 * La cámara y el selector de videos, de mentira: contestan con el video sintético de `apps/shared/fixtures` sin abrir nada. El video
 * pasa por el compresor de verdad.
 */
class CamaraDeVideoDePrueba(private val instr: Instrumentation, private val app: Context) {
    val pedidos = CopyOnWriteArrayList<Intent>()

    private fun copiarA(s: java.io.OutputStream) = instr.context.assets.open("video-prueba.mp4").use { it.copyTo(s) }

    private val monitor = object : Instrumentation.ActivityMonitor() {
        override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
            val accion = intent.action ?: return null
            if (accion == MediaStore.ACTION_VIDEO_CAPTURE) {
                pedidos += intent
                @Suppress("DEPRECATION")
                val salida = intent.getParcelableExtra<Uri>(MediaStore.EXTRA_OUTPUT) ?: return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
                app.contentResolver.openOutputStream(salida)!!.use { copiarA(it) }
                return Instrumentation.ActivityResult(Activity.RESULT_OK, null)
            }
            if ("PICK_IMAGES" in accion || accion == Intent.ACTION_OPEN_DOCUMENT || accion == Intent.ACTION_GET_CONTENT) {
                pedidos += intent
                val f = File(ProveedorFotos.carpeta(app), "de-la-galeria.mp4").apply { parentFile?.mkdirs() }
                f.outputStream().use { copiarA(it) }
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
}
