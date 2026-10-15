package com.pumpteam.mypump.avisos

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Las alarmas de los avisos locales y lo que obliga a volver a armar el del domingo:
 *
 * - el aviso del domingo (publica y NO agenda el siguiente: es de una vez, lo arma la app cuando se usa) y el fin del
 *   descanso (si la app no está a la vista);
 * - al prender el teléfono (las alarmas no sobreviven a un reinicio) y al actualizar la app (`MY_PACKAGE_REPLACED`, que
 *   además se lleva lo que dejó la Capacitor aunque el cliente todavía no haya abierto la app nueva);
 * - al cambiar la zona o la hora: las 11:00 de ese domingo son otro instante.
 *
 * En esos tres casos se vuelve a armar SOLO el aviso que estaba pendiente; si no había, no se inventa uno (revisión del
 * 15-oct, hallazgo 8). No se exporta: las del sistema llegan igual y nadie más puede dispararlas.
 */
class ReceptorAvisos : BroadcastReceiver() {
    override fun onReceive(contexto: Context, intent: Intent) {
        val c = contexto.applicationContext
        when (intent.action) {
            CentroAvisos.ACCION_DOMINGO -> CentroAvisos.alSonarDomingo(c)
            CentroAvisos.ACCION_FIN_DESCANSO -> if (!CentroAvisos.enPrimerPlano) CentroAvisos.mostrarFinDescanso(c)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            -> CentroAvisos.reagendar(c)
        }
    }
}
