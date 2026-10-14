package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement

/**
 * Fila de `mypump_ejercicios_catalogo`: lectura pública sin token, con las columnas que pide `getCatalogoEjercicios`
 * (public/js/supabase-client.js). Es free-exercise-db, en inglés, más el patrón de movimiento que decide qué sustituye a
 * qué. La app trae una copia (`apps/shared/catalogo-ejercicios.json`) para cuando no hay red.
 *
 * Los textos se leen solo si son texto: la web los compara con `===`, y un número nunca es igual a un texto.
 */
data class EntradaCatalogoEjercicio(
    val slugEn: String?,
    val nameEn: String? = null,
    val nameNormalized: String? = null,
    /** Palabras clave genéricas ("remo", "jalon", "core"): sirven para resolver un nombre, no para distinguir variantes. */
    val aliasesEs: List<String>? = null,
    val primaryMuscle: String? = null,
    val equipment: String? = null,
    /** NULL en casi la mitad del catálogo: sin patrón no se ofrecen sustitutos. */
    val patronMovimiento: String? = null,
    val imageEccentric: String? = null,
    val imageConcentric: String? = null,
) {
    companion object {
        fun desde(e: JsonElement): EntradaCatalogoEjercicio {
            val o = e.comoObjeto("EntradaCatalogoEjercicio")
            return EntradaCatalogoEjercicio(
                slugEn = o.cadena("slug_en"),
                nameEn = o.cadena("name_en"),
                nameNormalized = o.cadena("name_normalized"),
                // `Array.isArray(e.aliases_es) && e.aliases_es.includes(nn)`: lo que no es array no tiene alias, y un
                // elemento que no es texto nunca coincide.
                aliasesEs = (o["aliases_es"] as? JsonArray)?.mapNotNull(Lector::texto),
                primaryMuscle = o.cadena("primary_muscle"),
                equipment = o.cadena("equipment"),
                patronMovimiento = o.cadena("patron_movimiento"),
                imageEccentric = o.cadena("image_eccentric"),
                imageConcentric = o.cadena("image_concentric"),
            )
        }
    }
}
