package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonElement

/** Fila de `mypump_get_dieta_activa`. */
data class DietaActiva(val id: String, val version: Int, val estructura: EstructuraDieta) {
    companion object {
        fun desde(e: JsonElement): DietaActiva {
            val o = e.comoObjeto("DietaActiva")
            return DietaActiva(
                id = o.texto("id") ?: "",
                version = o.entero("version") ?: 1,
                estructura = o.objeto("estructura")?.let(EstructuraDieta::desde) ?: EstructuraDieta(),
            )
        }
    }
}

/**
 * `mypump_dietas.estructura`. Formato A: `macros_target` + `comidas`. Formato B: `tipos_dia[]`, cada uno con lo suyo
 * (ver `docs/SCHEMA_DIETA.md`). Las opciones A/B/C/D son POR COMIDA: el cliente combina desayuno A con almuerzo B.
 */
data class EstructuraDieta(
    val macrosTarget: Macros? = null,
    val comidas: List<Comida> = emptyList(),
    val tiposDia: List<TipoDia> = emptyList(),
) {
    companion object {
        fun desde(e: JsonElement): EstructuraDieta {
            val o = e.comoObjeto("EstructuraDieta")
            return EstructuraDieta(
                macrosTarget = o.objeto("macros_target")?.let(Macros::desde),
                comidas = o.lista("comidas", Comida::desde),
                tiposDia = o.lista("tipos_dia", TipoDia::desde),
            )
        }
    }
}

data class TipoDia(
    val id: String,
    val nombre: String? = null,
    val macrosTarget: Macros? = null,
    val comidas: List<Comida> = emptyList(),
) {
    companion object {
        fun desde(e: JsonElement): TipoDia {
            val o = e.comoObjeto("TipoDia")
            return TipoDia(
                id = o.texto("id") ?: "",
                nombre = o.texto("nombre"),
                macrosTarget = o.objeto("macros_target")?.let(Macros::desde),
                comidas = o.lista("comidas", Comida::desde),
            )
        }
    }
}

data class Comida(val id: String, val nombre: String? = null, val opciones: List<Opcion> = emptyList()) {
    companion object {
        fun desde(e: JsonElement): Comida {
            val o = e.comoObjeto("Comida")
            return Comida(id = o.texto("id") ?: "", nombre = o.texto("name"), opciones = o.lista("options", Opcion::desde))
        }
    }
}

data class Opcion(val nombre: String? = null, val alimentos: List<Alimento> = emptyList()) {
    companion object {
        fun desde(e: JsonElement): Opcion {
            val o = e.comoObjeto("Opcion")
            return Opcion(nombre = o.texto("name"), alimentos = o.lista("foods", Alimento::desde))
        }
    }
}

/**
 * Un alimento del plan. En `meals` del Cerebro y en FOOD_DB las macros son por 100 g; acá (en la estructura publicada)
 * son el TOTAL de esa `qty`, igual que en `food_data` de un swap. La qty de un contable va en unidades.
 */
data class Alimento(
    val nombre: String,
    val qty: Double? = null,
    val unidad: String? = null,
    val gramosPorUnidad: Double? = null,
    val kcal: Double? = null,
    val prot: Double? = null,
    val carb: Double? = null,
    val fat: Double? = null,
    val categoria: String? = null,
    val sustituible: Boolean? = null,
) {
    companion object {
        fun desde(e: JsonElement): Alimento {
            val o = e.comoObjeto("Alimento")
            return Alimento(
                nombre = o.texto("name") ?: "",
                qty = o.decimal("qty"),
                unidad = o.texto("unit"),
                gramosPorUnidad = o.decimal("unitGrams"),
                kcal = o.decimal("kcal"),
                prot = o.decimal("prot"),
                carb = o.decimal("carb"),
                fat = o.decimal("fat"),
                categoria = o.texto("category"),
                sustituible = o.booleano("swappable"),
            )
        }

        /** El alimento que guarda un swap (`food_data`): si no es un objeto, no hay alimento. */
        fun desdeValor(v: ValorJson): Alimento? = (v as? ValorJson.Objeto)?.let { desde(it.aJson()) }
    }
}

data class Macros(val kcal: Double? = null, val prot: Double? = null, val carb: Double? = null, val fat: Double? = null) {
    companion object {
        fun desde(e: JsonElement): Macros {
            val o = e.comoObjeto("Macros")
            return Macros(o.decimal("kcal"), o.decimal("prot"), o.decimal("carb"), o.decimal("fat"))
        }
    }
}
