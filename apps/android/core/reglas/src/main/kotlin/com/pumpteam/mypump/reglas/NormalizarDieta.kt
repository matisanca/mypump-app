package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.EstructuraDieta
import com.pumpteam.mypump.modelos.Macros

/**
 * `normalizarDieta` (cliente.html:1842), como NormalizarDieta.swift: lo que la web hace con la dieta publicada ANTES de
 * mostrarla o indexarla.
 * - Se van las comidas sin ninguna opción con alimentos, y de las que quedan, las opciones vacías. Los swaps de comida se
 *   guardan con el índice de la opción: sin esto una opción vacía en el medio corría los índices y lo reemplazado en una
 *   app no se veía en la otra (y el anclaje podía borrar el swap de la otra).
 * - Sin `macros_target` con kcal > 0, el objetivo es la suma de la opción A de cada comida, redondeada.
 * - `tipos_dia: []` es lo mismo que no tenerlos.
 */
object NormalizarDieta {
    data class Resultado(
        val estructura: EstructuraDieta,
        /** Hay al menos una comida en algún plan. */
        val usable: Boolean,
        /** Para el aviso "a tu plan le falta información" (no es para el cliente: es para que Mati lo corrija). */
        val problemas: List<String>,
    )

    fun normalizar(entrada: EstructuraDieta): Resultado {
        val problemas = mutableListOf<String>()
        fun limpiar(comidas: List<Comida>, objetivo: Macros?): Pair<List<Comida>, Macros> {
            val quedan = comidas.mapNotNull { c ->
                val opciones = c.opciones.filter { it.alimentos.isNotEmpty() }
                if (opciones.isEmpty()) {
                    problemas += "${c.nombre?.takeIf { it.isNotEmpty() } ?: "Una comida"}: sin opciones cargadas."
                    null
                } else {
                    c.copy(opciones = opciones)
                }
            }
            val k = objetivo?.kcal
            if (objetivo != null && k != null && k > 0) return quedan to objetivo
            var kcal = 0.0
            var prot = 0.0
            var carb = 0.0
            var fat = 0.0
            for (c in quedan) {
                for (a in c.opciones.firstOrNull()?.alimentos.orEmpty()) {
                    kcal += oCero(a.kcal)
                    prot += oCero(a.prot)
                    carb += oCero(a.carb)
                    fat += oCero(a.fat)
                }
            }
            problemas += "El plan no traía el objetivo de calorías; se calculó con la opción A."
            return quedan to Macros(jsRound(kcal), jsRound(prot), jsRound(carb), jsRound(fat))
        }
        if (entrada.tiposDia.isEmpty()) {
            val (comidas, macros) = limpiar(entrada.comidas, entrada.macrosTarget)
            return Resultado(entrada.copy(comidas = comidas, macrosTarget = macros), comidas.isNotEmpty(), problemas)
        }
        val tipos = entrada.tiposDia.map { t ->
            val (comidas, macros) = limpiar(t.comidas, t.macrosTarget)
            t.copy(comidas = comidas, macrosTarget = macros)
        }
        return Resultado(entrada.copy(tiposDia = tipos), tipos.any { it.comidas.isNotEmpty() }, problemas)
    }

    /** `Number(x) || 0`. */
    private fun oCero(x: Double?): Double = if (x == null || x.isNaN()) 0.0 else x
}
