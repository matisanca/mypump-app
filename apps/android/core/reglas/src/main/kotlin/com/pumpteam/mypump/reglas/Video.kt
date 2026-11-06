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

    // ── El recuadro útil: clips con las franjas negras metidas en el archivo ──

    /** Lo que no es negro, en fracciones del cuadro (0..1): izquierda, arriba, derecha, abajo. */
    data class Recuadro(val izquierda: Float, val arriba: Float, val derecha: Float, val abajo: Float) {
        val ancho: Float get() = derecha - izquierda
        val alto: Float get() = abajo - arriba

        /** «0.33,0,0.67,1»: para la caché en disco. */
        fun aTexto(): String = "$izquierda,$arriba,$derecha,$abajo"

        companion object {
            fun desde(t: String?): Recuadro? {
                val n = t?.split(',')?.mapNotNull { it.trim().toFloatOrNull() }?.takeIf { it.size == 4 } ?: return null
                val r = Recuadro(n[0], n[1], n[2], n[3])
                return r.takeIf { it.izquierda >= 0f && it.arriba >= 0f && it.derecha <= 1f && it.abajo <= 1f && it.ancho > 0f && it.alto > 0f }
            }
        }
    }

    /** Luminancia (0..255) por encima de la cual un píxel no es negro. */
    const val UMBRAL_NEGRO = 16

    /** Si lo que pasa el umbral ocupa al menos esto del ancho y del alto, no son franjas (y queda el cuadro entero). */
    const val MINIMO_SIN_RECORTE = 0.92f

    /** Un borde oscuro parejo (media < 40 y desvío < 12, como iOS) se quita hasta este tanto por lado. */
    const val BORDE_PAREJO_MAXIMO = 0.04f
    private const val MEDIA_BORDE = 40.0
    private const val DESVIO_BORDE = 12.0

    /**
     * La zona útil de un cuadro de [ancho]×[alto] con su luminancia por píxel ([luma], fila por fila), en fracciones:
     * 1. lo que pasa el [UMBRAL_NEGRO] (una columna o fila cuenta si más del 1 % de sus píxeles lo pasa, para que el ruido
     *    de la compresión no alcance); si eso ocupa el 92 % o más de los dos lados, el cuadro entero;
     * 2. además, como iOS, cualquier borde oscuro parejo de hasta el 4 % por lado.
     * null si el cuadro es todo negro (un fundido).
     */
    fun recuadroDe(luma: IntArray, ancho: Int, alto: Int): Recuadro? {
        if (ancho <= 0 || alto <= 0 || luma.size < ancho * alto) return null
        val porColumna = IntArray(ancho)
        val porFila = IntArray(alto)
        for (y in 0 until alto) for (x in 0 until ancho) {
            if (luma[y * ancho + x] > UMBRAL_NEGRO) {
                porColumna[x]++
                porFila[y]++
            }
        }
        val minCol = maxOf(1, alto / 100)
        val minFila = maxOf(1, ancho / 100)
        var x0 = porColumna.indexOfFirst { it >= minCol }
        var y0 = porFila.indexOfFirst { it >= minFila }
        if (x0 < 0 || y0 < 0) return null
        var x1 = porColumna.indexOfLast { it >= minCol } + 1
        var y1 = porFila.indexOfLast { it >= minFila } + 1
        if (x1 - x0 >= MINIMO_SIN_RECORTE * ancho && y1 - y0 >= MINIMO_SIN_RECORTE * alto) {
            x0 = 0; y0 = 0; x1 = ancho; y1 = alto
        }
        // Una columna (o fila) del borde, entre [desde, hasta) del otro eje, es oscura y pareja.
        fun pareja(columna: Boolean, k: Int, desde: Int, hasta: Int): Boolean {
            val n = hasta - desde
            if (n <= 0) return false
            var suma = 0.0
            var cuad = 0.0
            for (t in desde until hasta) {
                val v = (if (columna) luma[t * ancho + k] else luma[k * ancho + t]).toDouble()
                suma += v
                cuad += v * v
            }
            val media = suma / n
            val desvio = Math.sqrt(maxOf(0.0, cuad / n - media * media))
            return media < MEDIA_BORDE && desvio < DESVIO_BORDE
        }
        val tx = (ancho * BORDE_PAREJO_MAXIMO).toInt()
        val ty = (alto * BORDE_PAREJO_MAXIMO).toInt()
        var k = 0
        while (k < tx && x1 - x0 > 2 && pareja(true, x0, y0, y1)) { x0++; k++ }
        k = 0
        while (k < tx && x1 - x0 > 2 && pareja(true, x1 - 1, y0, y1)) { x1--; k++ }
        k = 0
        while (k < ty && y1 - y0 > 2 && pareja(false, y0, x0, x1)) { y0++; k++ }
        k = 0
        while (k < ty && y1 - y0 > 2 && pareja(false, y1 - 1, x0, x1)) { y1--; k++ }
        return Recuadro(x0.toFloat() / ancho, y0.toFloat() / alto, x1.toFloat() / ancho, y1.toFloat() / alto)
    }

    /** La unión de los recuadros de varios cuadros (los todo negros no cuentan). null si no hay ninguno. */
    fun union(recuadros: List<Recuadro?>): Recuadro? {
        val l = recuadros.filterNotNull().ifEmpty { return null }
        return Recuadro(l.minOf { it.izquierda }, l.minOf { it.arriba }, l.maxOf { it.derecha }, l.maxOf { it.abajo })
    }

    /**
     * El recorte que se aplica: si a [r] le falta algo del cuadro, se mete 1 px más hacia adentro en cada lado recortado
     * (en un archivo de [anchoPx]×[altoPx]) para que no quede nada de negro. null = el cuadro entero, sin recorte.
     */
    fun recorte(r: Recuadro?, anchoPx: Int, altoPx: Int): Recuadro? {
        if (r == null || anchoPx <= 0 || altoPx <= 0) return null
        val e = 1e-4f
        val izq = r.izquierda > e
        val arr = r.arriba > e
        val der = r.derecha < 1f - e
        val aba = r.abajo < 1f - e
        if (!izq && !arr && !der && !aba) return null
        val px = 1f / anchoPx
        val py = 1f / altoPx
        val n = Recuadro(
            if (izq) r.izquierda + px else 0f,
            if (arr) r.arriba + py else 0f,
            if (der) r.derecha - px else 1f,
            if (aba) r.abajo - py else 1f,
        )
        return n.takeIf { it.ancho > 0f && it.alto > 0f }
    }

    /** La proporción de lo que se ve: la del archivo ([proporcionArchivo]) por la parte que queda del recorte. */
    fun proporcionVisible(proporcionArchivo: Float, recorte: Recuadro?): Float =
        if (recorte == null) proporcionArchivo else proporcionArchivo * recorte.ancho / recorte.alto

    /**
     * Cómo mover la vista del video (la de Media3, de [anchoVista]×[altoVista] dentro de una caja de [anchoCaja]×[altoCaja],
     * en [x],[y]) para que solo la zona [r] llene la caja: escala y desplazamiento con el pivote arriba a la izquierda.
     * Devuelve (escalaX, escalaY, desplazamientoX, desplazamientoY).
     */
    fun transformacion(r: Recuadro, x: Float, y: Float, anchoVista: Float, altoVista: Float, anchoCaja: Float, altoCaja: Float): List<Float> {
        val sx = anchoCaja / (r.ancho * anchoVista)
        val sy = altoCaja / (r.alto * altoVista)
        return listOf(sx, sy, -x - sx * r.izquierda * anchoVista, -y - sy * r.arriba * altoVista)
    }
}
