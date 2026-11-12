package com.pumpteam.mypump.reglas

/**
 * 2.3.1 (solo Android): con el permiso de pasos dado y ningún paso en los últimos 3 días, Samsung Health casi siempre no
 * está escribiendo en Health Connect (es un ajuste del usuario que la app no puede hacer). La pantalla de Salud lo avisa
 * con los pasos para activarlo y dice de qué app vienen los pasos cuando sí llegan («Pasos desde: Samsung Health»).
 */
object PasosHealthConnect {
    const val SAMSUNG_HEALTH = "com.sec.android.app.shealth"
    const val HEALTH_CONNECT = "com.google.android.apps.healthdata"
    const val DIAS = 3

    const val TITULO = "Tus pasos no llegan"
    const val TEXTO = "Abrí Samsung Health, andá a Ajustes → Health Connect y activá Pasos. Después abrí Samsung Health una vez para que se sincronice."
    const val BOTON_SAMSUNG = "Abrir Samsung Health"
    const val BOTON_HEALTH_CONNECT = "Abrir Health Connect"

    data class Estado(val sinPasos: Boolean, val origen: String?)

    /**
     * [permisoPasos]: READ_STEPS dado. [muestras]: (paquete que escribió, pasos) de los últimos [DIAS] días. Sin permiso,
     * nada que decir (`null`): eso lo maneja el aviso de conectar. El origen es la app que más pasos escribió.
     */
    fun evaluar(permisoPasos: Boolean, muestras: List<Pair<String, Double>>): Estado? {
        if (!permisoPasos) return null
        val con = muestras.filter { it.second.isFinite() && it.second > 0 }
        if (con.isEmpty()) return Estado(sinPasos = true, origen = null)
        val porApp = con.groupBy { it.first }.mapValues { (_, v) -> v.sumOf { it.second } }
        val origen = porApp.entries.sortedWith(compareByDescending<Map.Entry<String, Double>> { it.value }.thenBy { it.key }).first().key
        return Estado(sinPasos = false, origen = nombre(origen))
    }

    /** El nombre que reconoce el alumno; si no la conocemos, el paquete tal cual (sirve para la llamada). */
    fun nombre(paquete: String): String = when (paquete.trim()) {
        SAMSUNG_HEALTH -> "Samsung Health"
        "com.google.android.apps.fitness" -> "Google Fit"
        HEALTH_CONNECT, "com.android.healthconnect.controller" -> "Health Connect"
        "com.fitbit.FitbitMobile" -> "Fitbit"
        "com.garmin.android.apps.connectmobile" -> "Garmin Connect"
        "com.mi.health", "com.xiaomi.wearable" -> "Mi Fitness"
        "com.huami.watch.hmwatchmanager" -> "Zepp"
        "com.huawei.health" -> "Huawei Salud"
        "com.ouraring.oura" -> "Oura"
        "com.strava" -> "Strava"
        "com.withings.wiscale2" -> "Withings"
        "com.whoop.android" -> "WHOOP"
        "" -> "otra app"
        else -> paquete.trim()
    }

    fun pasosDesde(origen: String): String = "Pasos desde: $origen"
}
