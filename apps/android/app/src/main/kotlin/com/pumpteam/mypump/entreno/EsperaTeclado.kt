package com.pumpteam.mypump.entreno

// Lo que no depende de la vista en «salir del peso sin registrar nada» (2.3.3, S2): la espera del OK cuando vuelve el panel.
// Sin Android adentro: se prueba en la JVM (src/test).

/**
 * El OK no toma toques un rato después de que vuelve el panel (Sebastián, 19/11: escribió 83 en el peso, no supo cómo salir,
 * tocó abajo y se le registró una serie). Mientras el teclado está arriba el panel se esconde; al cerrarse, el panel aparece
 * justo donde el alumno está tocando y ese toque confirmaba. Ahora, durante [ms] desde que el panel vuelve, el OK los ignora.
 *
 * El reloj se inyecta: en la app es `SystemClock.uptimeMillis` ([RelojCarga]); en las pruebas, uno que manejan ellas.
 */
class EsperaTrasTeclado(private val reloj: () -> Long, val ms: Long = MS) {
    /** Si el panel estaba escondido la última vez que se miró. */
    var oculto = false
        private set
    private var desde: Long? = null

    /** El estado del panel, cada vez que se compone. Solo el paso de escondido a visible arranca la espera. */
    fun ver(ocultoAhora: Boolean) {
        if (oculto && !ocultoAhora) desde = reloj()
        oculto = ocultoAhora
    }

    /** Si el OK puede registrar ahora: el panel a la vista y la espera cumplida (o nunca se escondió). */
    fun admite(): Boolean {
        if (oculto) return false
        val d = desde ?: return true
        return reloj() - d >= ms
    }

    companion object {
        /** Medio segundo: más que un toque doble apurado, menos de lo que tarda en volver la vista al botón. */
        const val MS = 500L
    }
}

