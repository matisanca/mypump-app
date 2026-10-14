package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.Progresion

/** Lo que pide el plan para un ejercicio en una semana. La progresión YA viene calculada por el Cerebro. */
data class Pauta(val series: Int?, val reps: String?, val rir: String?)

data class NotaProgresion(val texto: String, val cambia: Boolean, val calibracion: Boolean)

object Progresiones {
    /**
     * Port de `getProgresionActual` (cliente.html:1679). La semana se acota al largo del array: pasada la última, queda
     * la última. Sin progresión, valen los campos viejos (`series`, `reps`, `rir_objetivo ?? rir`).
     */
    fun pauta(e: Ejercicio, semana: Int?): Pauta {
        if (e.progresion.isNotEmpty()) {
            val idx = maxOf(0, minOf(semanaJs(semana) - 1, e.progresion.size - 1))
            val p = e.progresion[idx]
            return Pauta(p.series, p.reps, p.rir)
        }
        return Pauta(e.series, e.reps, e.rirObjetivo ?: e.rirSuelto)
    }

    const val TEXTO_CALIBRACION = "Semana de calibración: buscá el fallo muscular, no te guardes reps. Las reps son una guía " +
        "(±2-3): si apuntás a 12 y te salen 9 o 14, perfecto. La idea es encontrar tu peso real llegando cerca del fallo."

    /**
     * Port de `computeProgresionNota` (cliente.html:1701): explica el cambio de esta semana contra la anterior.
     * Devuelve null si el ejercicio no tiene progresión.
     */
    fun nota(e: Ejercicio, semanaActual: Int?): NotaProgresion? {
        val prog = e.progresion
        if (prog.isEmpty()) return null
        val sem = semanaJs(semanaActual)

        fun porSemana(s: Int): Progresion = prog.firstOrNull { it.semana == s } ?: prog[maxOf(0, minOf(s - 1, prog.size - 1))]
        val cur = porSemana(sem)

        // JS: ej.progresion.find(p => p.semana === sem - 1) || ej.progresion[sem - 2]. Sin acotar: fuera de rango es
        // undefined, y eso también es "calibración".
        val prev = if (sem > 1) prog.firstOrNull { it.semana == sem - 1 } ?: prog.getOrNull(sem - 2) else null
        if (prev == null) return NotaProgresion(TEXTO_CALIBRACION, cambia = false, calibracion = true)

        val curReps = tope(cur.reps)
        val prevReps = tope(prev.reps)
        val curSeries = tope(cur.series?.toString())
        val prevSeries = tope(prev.series?.toString())
        val curRir = tope(cur.rir)
        val prevRir = tope(prev.rir)

        // `a != null && b != null && a < b` de JS.
        fun ambos(a: Double?, b: Double?, op: (Double, Double) -> Boolean) = a != null && b != null && op(a, b)
        val repsBaja = ambos(curReps, prevReps) { a, b -> a < b }
        val repsSube = ambos(curReps, prevReps) { a, b -> a > b }
        val repsIgual = ambos(curReps, prevReps) { a, b -> a == b }
        val seriesSube = ambos(curSeries, prevSeries) { a, b -> a > b }
        val seriesIgual = ambos(curSeries, prevSeries) { a, b -> a == b }
        val rirBaja = ambos(curRir, prevRir) { a, b -> a < b }

        val partes = mutableListOf<String>()
        when {
            repsBaja && seriesIgual -> partes += "Esta semana bajan las reps (de ${js(prev.reps)} a ${js(cur.reps)}). Subí la " +
                "carga: apuntá a más kilos que la semana pasada, manteniendo buena técnica."
            repsBaja && seriesSube -> partes += "Más series y menos reps: subí un poco la carga y sumá volumen."
            seriesSube && repsIgual -> partes += "Sumamos una serie: mismo peso, más volumen total esta semana."
            repsSube && seriesIgual -> partes += "Suben las reps con el mismo peso. Si las completás sobrado, subí la carga la próxima."
        }
        if (rirBaja) partes += "Bajamos el RIR: acercate más al fallo en cada serie."

        val cambia = partes.isNotEmpty()
        if (!cambia) {
            partes += if (repsIgual && seriesIgual) {
                "Mantené el peso de la semana pasada e intentá superar tus reps, siempre cerca del fallo. Si te sobra, subí la carga."
            } else {
                "Seguí la pauta de esta semana (${cur.series?.toString() ?: "—"}×${cur.reps ?: "—"}) y trabajá cerca del " +
                    "fallo; si te sobra, subí la carga."
            }
        }
        return NotaProgresion(partes.joinToString(" "), cambia, calibracion = false)
    }

    /** `semana || 1` de JS: null, undefined y 0 valen 1. */
    internal fun semanaJs(s: Int?): Int = if (s == null || s == 0) 1 else s

    /**
     * `upper` de JS: el mayor de los números que aparezcan en el texto ("8-10" → 10, "10 min" → 10), con
     * `match(/\d+/g)` (dígitos ASCII) y `Math.max(...nums.map(Number))`: en double, como JS, así un número de 25 cifras
     * no se pierde.
     */
    internal fun tope(v: String?): Double? {
        if (v == null) return null
        var mayor: Double? = null
        var i = 0
        while (i < v.length) {
            if (v[i] in '0'..'9') {
                val inicio = i
                while (i < v.length && v[i] in '0'..'9') i++
                val n = v.substring(inicio, i).toDouble()
                mayor = if (mayor == null || n > mayor) n else mayor
            } else {
                i++
            }
        }
        return mayor
    }

    /** Cómo imprime JS un texto en un template literal: null → "null". */
    private fun js(v: String?): String = v ?: "null"
}
