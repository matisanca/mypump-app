package com.pumpteam.mypump.reglas

/**
 * El tamaño de los reproductores de clips (pedido de Mati del 6/11: «nunca franjas negras»). La caja toma la proporción
 * real del clip (`VideoSize` de Media3, con `pixelWidthHeightRatio`) y no un 16:9 fijo. Hay verticales (~570×720),
 * horizontales (1280×720) y cuadrados. Mientras carga, la última proporción conocida de ese clip o, si no hay, 16:9.
 */
object ReglasVideo {
    const val POR_DEFECTO = 16f / 9f

    /** Un vertical (o un cuadrado en una pantalla baja) no pasa de este tanto del alto de la pantalla. */
    const val ALTO_MAXIMO = 0.6f

    /** Ancho sobre alto, con la forma del píxel. null si el tamaño todavía no se sabe (0×0) o no tiene sentido. */
    fun proporcion(ancho: Int, alto: Int, pixelAnchoAlto: Float = 1f): Float? {
        if (ancho <= 0 || alto <= 0) return null
        val pixel = if (pixelAnchoAlto.isFinite() && pixelAnchoAlto > 0f) pixelAnchoAlto else 1f
        val p = ancho * pixel / alto
        return p.takeIf { it.isFinite() && it in 0.2f..5f }
    }

    /**
     * La caja en la tarjeta: todo el [anchoDisponible] con la proporción [p]; si así pasa del 60 % del [altoPantalla], ese
     * alto y el ancho que corresponda (se centra, con el fondo de la tarjeta a los costados). Devuelve (ancho, alto).
     */
    fun caja(p: Float, anchoDisponible: Float, altoPantalla: Float): Pair<Float, Float> {
        val prop = p.takeIf { it.isFinite() && it > 0f } ?: POR_DEFECTO
        val tope = altoPantalla * ALTO_MAXIMO
        val alto = anchoDisponible / prop
        if (tope <= 0f || alto <= tope) return anchoDisponible to alto
        return tope * prop to tope
    }

    /** En pantalla completa: lo más grande que entra en la pantalla sin deformarse. Devuelve (ancho, alto). */
    fun completa(p: Float, ancho: Float, alto: Float): Pair<Float, Float> {
        val prop = p.takeIf { it.isFinite() && it > 0f } ?: POR_DEFECTO
        return if (ancho / alto > prop) alto * prop to alto else ancho to ancho / prop
    }
}
