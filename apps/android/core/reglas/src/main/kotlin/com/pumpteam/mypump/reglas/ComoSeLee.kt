package com.pumpteam.mypump.reglas

/**
 * 2.3.1: «¿Cómo se lee?» de la cabecera de Dieta. Texto corto en pasos, para que cualquiera lo entienda. Mismos textos en
 * iOS y la web (`apps/shared/vectores/como_se_lee.json`). [VIDEO]: lugar para un video opcional (sin URL no hay botón).
 */
object ComoSeLee {
    const val BOTON = "¿Cómo se lee?"
    const val TITULO = "Cómo se lee tu dieta"
    val PASOS = listOf(
        "Cada tarjeta es una comida del día, con lo que tenés que comer y cuántas calorías suma.",
        "Si una comida tiene opciones (A, B…), elegí una sola: cualquiera te sirve igual.",
        "Cuando comés, tocá «Comí». Arriba se va sumando lo que comiste en el día.",
        "¿No conseguís un alimento? Tocá el botón de las dos flechas y elegí otro parecido.",
    )
    const val VER_VIDEO = "Ver el video"
    const val CERRAR = "Entendido"
    val VIDEO: String? = null

    /** La URL del video, solo si es https. */
    fun urlVideo(v: String? = VIDEO): String? {
        val t = v?.trim() ?: return null
        val m = Regex("^https://[^\\s/\"'<>]+(/[^\\s\"'<>]*)?$").matchEntire(t) ?: return null
        return m.value
    }
}
