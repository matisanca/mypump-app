package com.pumpteam.mypump.reglas

import kotlin.math.abs

/**
 * 2.3.1: los reemplazos de comida no suben las kcal del plan en silencio. Mismas reglas y vectores que la web
 * (`window.MyPump.reemplazosKcal`) e iOS (`apps/shared/vectores/reemplazos_kcal.json`).
 * - Arriba («Disponibles en cualquier país») solo los universales con hasta 15 % de desvío; abajo, primero los propios
 *   con hasta 15 % y después todo lo demás ordenado por desvío (sin dato al final, en el orden del motor).
 * - Un reemplazo que suma más del 10 % o más de 60 kcal pide confirmación.
 * - La cabecera de Dieta dice cuánto suman los reemplazos del día.
 */
object ReemplazosKcal {
    const val DESVIO_ARRIBA = 0.15
    const val CONFIRMAR_FRACCION = 0.10
    const val CONFIRMAR_KCAL = 60.0
    const val USAR_IGUAL = "Usar igual"
    const val ELEGIR_OTRO = "Elegir otro"
    const val DESHACER = "Deshacer"

    /** Desvío relativo del reemplazo contra el original; `null` sin kcal en el original («sin dato»). */
    fun desvio(original: Double?, reemplazo: Double?): Double? {
        if (original == null || !original.isFinite() || original <= 0 || reemplazo == null || !reemplazo.isFinite()) return null
        return (reemplazo - original) / original
    }

    /** El «+N %» de cada opción, o `null` para mostrar «sin dato». */
    fun desvioPct(original: Double?, reemplazo: Double?): Long? = desvio(original, reemplazo)?.let { jsEntero(it * 100) }

    data class Orden<T>(val universales: List<T>, val resto: List<T>)

    fun <T> ordenar(items: List<T>, kcalOriginal: Double?, kcal: (T) -> Double?, universal: (T) -> Boolean, propio: (T) -> Boolean): Orden<T> {
        data class C<T>(val i: Int, val x: T, val d: Double?)
        val conD = items.mapIndexed { i, x -> C(i, x, desvio(kcalOriginal, kcal(x))) }
        fun cerca(d: Double?) = d != null && abs(d) <= DESVIO_ARRIBA + 1e-9
        val universales = conD.filter { universal(it.x) && cerca(it.d) }
        val propios = conD.filter { !universal(it.x) && propio(it.x) && cerca(it.d) }
        val tomados = (universales + propios).map { it.i }.toSet()
        val resto = conD.filter { it.i !in tomados }.sortedWith { a, b ->
            val da = a.d; val db = b.d
            when {
                da != null && db != null -> if (abs(da) != abs(db)) abs(da).compareTo(abs(db)) else a.i.compareTo(b.i)
                da == null && db == null -> a.i.compareTo(b.i)
                da == null -> 1
                else -> -1
            }
        }
        return Orden(universales.map { it.x }, (propios + resto).map { it.x })
    }

    private fun finito(x: Double?): Double? = x?.takeIf { it.isFinite() }

    /** Cuántas kcal suma el reemplazo por día (redondeado como `Math.round`). */
    fun suma(original: Double?, reemplazo: Double?): Long {
        val r = finito(reemplazo) ?: return 0
        return jsEntero(r - (finito(original) ?: 0.0))
    }

    fun pideConfirmacion(original: Double?, reemplazo: Double?): Boolean {
        val r = finito(reemplazo) ?: return false
        val s = r - (finito(original) ?: 0.0)
        if (s <= 0) return false
        if (s > CONFIRMAR_KCAL) return true
        val d = desvio(original, reemplazo) ?: return false
        return d > CONFIRMAR_FRACCION + 1e-9
    }

    fun textoConfirmacion(original: Double?, reemplazo: Double?): String =
        "Este cambio suma ${suma(original, reemplazo)} kcal a esta comida y a todos tus días. ¿Lo usás igual?"

    /** El renglón de la cabecera de Dieta con la suma de los reemplazos del día; `null` si no mueven nada. */
    fun renglon(suma: Double): String? {
        val n = if (suma.isFinite()) jsEntero(suma) else 0L
        if (n == 0L) return null
        return if (n > 0) "Tus reemplazos suman +$n kcal" else "Tus reemplazos restan ${-n} kcal"
    }
}
