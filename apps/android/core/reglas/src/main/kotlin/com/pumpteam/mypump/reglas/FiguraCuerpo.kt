package com.pumpteam.mypump.reglas

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * La figura del cuerpo de «Me duele»: dibujo propio hecho de cápsulas, elipses y cajas en un lienzo de 200 × 420. Las piezas
 * salen de `scripts/nativa/generar-cuerpo.py` (`FiguraCuerpoDatos.kt`), las mismas en iPhone y en la web
 * (`apps/shared/fixtures/feedback/cuerpo.json`). Tocar una pieza da la zona y el lado de una vez. Gemelo de FiguraCuerpo.swift.
 */
object FiguraCuerpo {
    const val ANCHO = 200.0
    const val ALTO = 420.0

    enum class Vista(val clave: String) { FRENTE("frente"), ESPALDA("espalda") }
    enum class Forma(val clave: String) { CAPSULA("capsula"), ELIPSE("elipse"), CAJA("caja") }

    /** El rectángulo que contiene una pieza. */
    data class Marco(val x: Double, val y: Double, val ancho: Double, val alto: Double)

    /**
     * [zona] null = la cabeza, que es solo dibujo.
     * [a]: cápsula x1, y1, x2, y2, radio · elipse cx, cy, rx, ry · caja x, y, ancho, alto, radio.
     */
    class Pieza(val zona: String?, val lado: String?, val forma: Forma, val a: DoubleArray) {
        val id: String get() = "${zona ?: "cabeza"}-${lado ?: ""}"

        /** El centro de la pieza, para ordenar la lectura y elegir la más cercana al dedo. */
        val centro: Pair<Double, Double>
            get() = when (forma) {
                Forma.CAPSULA -> (a[0] + a[2]) / 2 to (a[1] + a[3]) / 2
                Forma.ELIPSE -> a[0] to a[1]
                Forma.CAJA -> a[0] + a[2] / 2 to a[1] + a[3] / 2
            }

        val marco: Marco
            get() = when (forma) {
                Forma.CAPSULA -> Marco(min(a[0], a[2]) - a[4], min(a[1], a[3]) - a[4], abs(a[2] - a[0]) + 2 * a[4], abs(a[3] - a[1]) + 2 * a[4])
                Forma.ELIPSE -> Marco(a[0] - a[2], a[1] - a[3], 2 * a[2], 2 * a[3])
                Forma.CAJA -> Marco(a[0], a[1], a[2], a[3])
            }

        /** ¿El punto cae en la pieza? [margen] agranda el blanco: un codo de 20 puntos es chico para un dedo. */
        fun contiene(x: Double, y: Double, margen: Double = 0.0): Boolean = when (forma) {
            Forma.ELIPSE -> {
                val dx = (x - a[0]) / (a[2] + margen)
                val dy = (y - a[1]) / (a[3] + margen)
                dx * dx + dy * dy <= 1
            }
            Forma.CAJA -> x >= a[0] - margen && x <= a[0] + a[2] + margen && y >= a[1] - margen && y <= a[1] + a[3] + margen
            Forma.CAPSULA -> {
                val vx = a[2] - a[0]
                val vy = a[3] - a[1]
                val largo2 = vx * vx + vy * vy
                val t = if (largo2 == 0.0) 0.0 else max(0.0, min(1.0, ((x - a[0]) * vx + (y - a[1]) * vy) / largo2))
                val px = a[0] + t * vx - x
                val py = a[1] + t * vy - y
                val r = a[4] + margen
                px * px + py * py <= r * r
            }
        }
    }

    fun piezas(v: Vista): List<Pieza> = if (v == Vista.FRENTE) FiguraCuerpoDatos.frente else FiguraCuerpoDatos.espalda

    /** La pieza tocada. Primero sin margen (lo que el dedo tapa de verdad) y después con margen, la de centro más cercano. */
    fun pieza(v: Vista, x: Double, y: Double, margen: Double = 7.0): Pieza? {
        val tocables = piezas(v).filter { it.zona != null }
        tocables.lastOrNull { it.contiene(x, y) }?.let { return it }
        return tocables.filter { it.contiene(x, y, margen) }.minByOrNull { p ->
            val (cx, cy) = p.centro
            (cx - x) * (cx - x) + (cy - y) * (cy - y)
        }
    }

    /** La vista donde se ve una zona, para abrir el dibujo del lado correcto al corregir un aviso. */
    fun vista(zona: String): Vista = if (FiguraCuerpoDatos.frente.any { it.zona == zona }) Vista.FRENTE else Vista.ESPALDA
}
