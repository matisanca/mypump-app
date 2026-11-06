package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement

/**
 * `data` de `POST /vision` (mini-vision) con `tipo: etiqueta`: la tabla nutricional leída de una foto.
 * `porcionG` 100 = valores por 100 g; otra porción = valores de esa porción; null = no se sabe (desde el 6-nov la app
 * pregunta en vez de asumir 100 g). `base` ('porcion' | '100g' | 'desconocida') y `avisos` los manda mini-vision desde el
 * 6-nov; un servidor viejo no los trae.
 */
data class LecturaEtiqueta(
    val nombre: String?,
    val porcionG: Double?,
    val kcal: Double?,
    val prot: Double?,
    val carb: Double?,
    val fat: Double?,
    /** "alta" | "media" | "baja". */
    val confianza: String?,
    val base: String? = null,
    val avisos: List<String> = emptyList(),
) {
    companion object {
        fun desde(e: JsonElement): LecturaEtiqueta {
            val o = e.comoObjeto("LecturaEtiqueta")
            return LecturaEtiqueta(
                nombre = o.texto("nombre"), porcionG = o.decimal("porcion_g"), kcal = o.decimal("kcal"), prot = o.decimal("prot"),
                carb = o.decimal("carb"), fat = o.decimal("fat"), confianza = o.texto("confianza"),
                base = o.texto("base"), avisos = o.textos("avisos") ?: emptyList(),
            )
        }
    }
}

/**
 * `data` de `POST /vision` con `tipo: plato`: la estimación de un plato (la descripción, la escala que usó la IA, los
 * alimentos con sus gramos y los totales).
 */
data class EstimacionPlato(
    val descripcion: String?,
    val escala: String?,
    val alimentos: List<AlimentoEstimado>,
    val kcal: Double?,
    val prot: Double?,
    val carb: Double?,
    val fat: Double?,
    val confianza: String?,
) {
    data class AlimentoEstimado(
        val nombre: String?,
        val gramos: Double?,
        val kcal: Double?,
        val prot: Double?,
        val carb: Double?,
        val fat: Double?,
    ) {
        companion object {
            fun desde(e: JsonElement): AlimentoEstimado {
                val o = e.comoObjeto("AlimentoEstimado")
                return AlimentoEstimado(
                    nombre = o.texto("nombre"), gramos = o.decimal("gramos"), kcal = o.decimal("kcal"), prot = o.decimal("prot"),
                    carb = o.decimal("carb"), fat = o.decimal("fat"),
                )
            }
        }
    }

    companion object {
        fun desde(e: JsonElement): EstimacionPlato {
            val o = e.comoObjeto("EstimacionPlato")
            // Como en iOS: si un alimento viene roto, no se muestra ninguno (es una estimación entera o nada).
            val alimentos = (o["alimentos"] as? JsonArray)?.let { a ->
                try {
                    listaEstricta(a, AlimentoEstimado::desde)
                } catch (_: ErrorDecodificacion) {
                    null
                }
            } ?: emptyList()
            return EstimacionPlato(
                descripcion = o.texto("descripcion"), escala = o.texto("escala"), alimentos = alimentos, kcal = o.decimal("kcal"),
                prot = o.decimal("prot"), carb = o.decimal("carb"), fat = o.decimal("fat"), confianza = o.texto("confianza"),
            )
        }
    }
}
