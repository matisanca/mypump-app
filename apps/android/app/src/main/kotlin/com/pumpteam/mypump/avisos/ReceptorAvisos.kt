package com.pumpteam.mypump.avisos

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Las alarmas de los avisos locales y lo que obliga a reagendar el del domingo:
 *
 * - el aviso del domingo (publica y agenda el siguiente) y el fin del descanso (si la app no está a la vista);
 * - al prender el teléfono (las alarmas no sobreviven a un reinicio) y al actualizar la app (`MY_PACKAGE_REPLACED`, que
 *   además se lleva lo que dejó la Capacitor aunque el cliente todavía no haya abierto la app nueva);
 * - al cambiar la zona o la hora: el próximo domingo a las 11:00 es otro instante.
 *
 * No se exporta: las del sistema llegan igual y nadie más puede dispararlas.
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
