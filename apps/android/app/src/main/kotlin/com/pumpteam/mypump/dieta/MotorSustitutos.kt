package com.pumpteam.mypump.dieta

import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.reglas.BaseAlimentos
import com.pumpteam.mypump.reglas.CategoriaAlimento
import com.pumpteam.mypump.reglas.SustitucionAlimentos
import com.pumpteam.mypump.reglas.Sustituto
import com.pumpteam.mypump.reglas.jsRound
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Puente entre la hoja "Reemplazar" y el motor portado ([SustitucionAlimentos], verificado con los vectores de la web),
 * gemelo de `MotorSustitutos` de iOS: la base empaquetada con los alimentos propios del cliente y sus exclusiones, los
 * avisos del modal (`openSwapModal`) y cómo se nombra cada categoría.
 */
object MotorSustitutos {
    data class Resultado(val opciones: List<Sustituto> = emptyList(), val avisos: List<String> = emptyList(), val categoria: String = "")

    /**
     * La base de la web (MYPUMP_FOOD_DB, `assets/bases/food-db.json`). La lee el ViewModel al arrancar, como el catálogo
     * de ejercicios; la hoja la mira como flujo por si se abre antes de que termine de leerse (son milisegundos).
     */
    private val _base = MutableStateFlow<BaseAlimentos?>(null)
    val base: StateFlow<BaseAlimentos?> = _base.asStateFlow()

    fun instalar(b: BaseAlimentos) {
        _base.value = b
    }

    /** food-db.json leído; null si no se puede leer o viene vacío (sin base, la hoja dice que no hay equivalentes). */
    fun leer(json: String): BaseAlimentos? = try {
        BaseAlimentos.desde(json).takeIf { it.alimentos.isNotEmpty() }
    } catch (_: Exception) {
        null
    }

    /** `openSwapModal` + `findSubstitutes`: la base con los alimentos propios del cliente y sus exclusiones. */
    fun buscar(original: Alimento, base: BaseAlimentos, propios: List<AlimentoPropio>, excluir: List<String>): Resultado {
        val categoria = CategoriaComida.inferir(original)
        val r = SustitucionAlimentos.buscar(original, base.conPropios(propios), excluir)
        val avisos = buildList {
            if (r.info.macrosSospechosos) add("Los datos de este alimento parecen incorrectos: avisale a Mati así lo corrige.")
            // Como la web: solo si las restricciones dejaron la lista sin opciones "de la base" (quedan universales o propios).
            if (r.info.prefsFiltraron > 0 && r.sustitutos.none { !it.universal && !it.esPropio }) {
                add("${r.info.prefsFiltraron} opciones quedaron ocultas por tus restricciones alimentarias.")
            }
        }
        return Resultado(r.sustitutos, avisos, categoria)
    }

    /** La búsqueda de la hoja (`searchSubstitutes`): las que contienen el texto, en el orden del motor. */
    fun filtrar(opciones: List<Sustituto>, busqueda: String): List<Sustituto> = SustitucionAlimentos.filtrar(opciones, busqueda)

    /** La diferencia de kcal contra el original, en % redondeado como `Math.round` de JS (0 si el original no tiene kcal). */
    fun deltaKcal(original: Alimento, s: Sustituto): Long {
        val k0 = original.kcal ?: 0.0
        if (!(k0 > 0)) return 0
        return Formato.entero(jsRound((s.kcal - k0) / k0 * 100))
    }

    fun nombreCategoria(c: String): String = when (c) {
        CategoriaAlimento.PROTEINA -> "proteínas"
        CategoriaAlimento.LACTEO -> "lácteos"
        CategoriaAlimento.GRASA -> "grasas"
        CategoriaAlimento.FRUTA_VERDURA -> "frutas y verduras"
        CategoriaAlimento.CARBOHIDRATO -> "carbohidratos"
        CategoriaAlimento.CONDIMENTO -> "condimentos"
        CategoriaAlimento.MIXTO -> "mixto"
        else -> c
    }
}

/** La categoría de un alimento del plan: la que trae o la inferida, igual que `inferFoodCategory` de la web. */
object CategoriaComida {
    fun inferir(a: Alimento): String = a.categoria?.takeIf { it.isNotEmpty() } ?: CategoriaAlimento.inferir(a)

    /**
     * DIE-09: el botón de reemplazo sale salvo en los condimentos y en lo que Mati marcó `swappable: false` (como iOS: la
     * fila no ofrece nada que el motor no pueda contestar).
     */
    fun sustituible(a: Alimento): Boolean = a.sustituible != false && inferir(a) != CategoriaAlimento.CONDIMENTO
}
