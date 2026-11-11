package com.pumpteam.mypump.avisos

/**
 * Auditoría del 10/11, F8: con la pantalla apagada el aviso del fin del descanso podía llegar hasta un minuto tarde. Una
 * alarma inexacta (sin `SCHEDULE_EXACT_ALARM`) puede sonar en cualquier momento entre su hora y su hora más el 75 % de lo
 * que faltaba, salvo que falten menos de 10 s: ahí el sistema no la corre. Y nunca antes de 5 s desde que se pide.
 *
 * En vez de una alarma para el fin, se encadenan alarmas cortas: cada una apunta lo bastante antes para que, aun con todo
 * el margen del sistema, despierte antes del fin; cuando faltan menos de [ESPERA_FINAL_MS], el receptor espera lo que
 * queda (con `goAsync`: el sistema mantiene el teléfono despierto hasta que el receptor termina) y avisa en el segundo.
 * Un descanso de 90 s despierta el teléfono cuatro veces como mucho; uno de 3 min, cinco.
 */
object SaltosDescanso {
    /** Lo que el receptor puede esperar despierto: menos de los 10 s que el sistema le da a un aviso. */
    const val ESPERA_FINAL_MS = 8_000L

    /** Lo mínimo que Android 12+ deja entre que se pide una alarma y que suena. */
    const val FUTURO_MINIMO_MS = 5_000L

    /** Debajo de esto el sistema corre la alarma en su hora, sin margen. */
    const val SIN_MARGEN_MS = 10_000L

    /** Margen que se deja antes del fin en el peor caso. */
    private const val RESGUARDO_MS = 1_000L

    /** La próxima alarma, o null si ya hay que esperar el resto en el receptor. */
    fun proximo(ahora: Long, fin: Long): Long? {
        val falta = fin - ahora
        if (falta <= ESPERA_FINAL_MS) return null
        // Que la hora más el margen del sistema (0,75 de lo que falta hasta la alarma) quede antes del fin.
        val hasta = ((falta - RESGUARDO_MS) / 1.75).toLong()
        return ahora + maxOf(FUTURO_MINIMO_MS, hasta)
    }

    /** El margen que el sistema le da a una alarma inexacta pedida `futuro` ms adelante (lo que puede llegar tarde). */
    fun margenDelSistema(futuro: Long): Long = if (futuro < SIN_MARGEN_MS) 0 else (0.75 * futuro).toLong()
}
