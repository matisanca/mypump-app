package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.ErrorDecodificacion
import com.pumpteam.mypump.modelos.listaEstricta
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Un alimento de la base contra la que se buscan sustitutos (`window.MYPUMP_FOOD_DB` de la web). Macros POR 100 g.
 *
 * La base viene armada de la web: `apps/shared/food-db.json` es el MYPUMP_FOOD_DB que calcula food-db.js (categoría
 * inferida y medida casera por `detectUnit`), generado por scripts/nativa/vectores-alimentos.mjs. Acá no se porta el
 * armado: se empaqueta el resultado.
 */
class AlimentoBase(
    val nombre: String,
    /** Por 100 g, ya con el `|| 0` con que los lee el motor (undefined, null y NaN valen 0). */
    val kcal: Double,
    val prot: Double,
    val carb: Double,
    val fat: Double,
    val categoria: String?,
    /** Medida casera ("unidad", "rebanada"…). Solo cuenta si hay [gramosPorUnidad]. */
    val unidad: String? = null,
    gramosPorUnidad: Double? = null,
    /** `_isCustom`: alimento propio del cliente (mypump_custom_foods). */
    val esPropio: Boolean = false,
) {
    /** Gramos de una unidad. null cuando la web lo tiene en falso (sin dato, 0). */
    val gramosPorUnidad: Double? = gramosPorUnidad?.takeIf { SemanticaJs.verdadero(it) }

    // Lo que el motor calcula sobre el nombre de cada candidato, hecho una sola vez (son funciones puras del nombre).
    /** `name.toLowerCase()`: la identidad del alimento para la web. */
    internal val minusculas: String = nombre.lowercase()

    /** `_norm(name)`: minúsculas sin tildes, contra el que corren las preferencias y los universales. */
    internal val normalizado: String = SustitucionAlimentos.normalizar(nombre)

    /** `_isUniversal(name)`. */
    internal val universal: Boolean = SustitucionAlimentos.esUniversalNormalizado(normalizado)

    /** `_enLabel(name)` ("" si ninguna etiqueta matchea). */
    internal val nombreIngles: String = SustitucionAlimentos.etiquetaInglesNormalizado(normalizado)

    override fun equals(other: Any?): Boolean = other is AlimentoBase && nombre == other.nombre && kcal == other.kcal &&
        prot == other.prot && carb == other.carb && fat == other.fat && categoria == other.categoria && unidad == other.unidad &&
        gramosPorUnidad == other.gramosPorUnidad && esPropio == other.esPropio

    override fun hashCode(): Int = nombre.hashCode()

    override fun toString(): String = "AlimentoBase($nombre, $kcal kcal, $categoria${if (esPropio) ", propio" else ""})"

    companion object {
        /** Un elemento de food-db.json (`{name, kcal, prot, carb, fat, category, unit?, unitGrams?}`). */
        fun desde(e: JsonElement): AlimentoBase {
            val o = e as? JsonObject ?: throw ErrorDecodificacion("AlimentoBase: se esperaba un objeto")
            fun numero(k: String) = (o[k] as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.content?.toDoubleOrNull()
            fun texto(k: String) = (o[k] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content
            return AlimentoBase(
                nombre = texto("name") ?: "",
                kcal = SemanticaJs.oCero(numero("kcal")),
                prot = SemanticaJs.oCero(numero("prot")),
                carb = SemanticaJs.oCero(numero("carb")),
                fat = SemanticaJs.oCero(numero("fat")),
                categoria = texto("category"),
                unidad = texto("unit"),
                gramosPorUnidad = numero("unitGrams"),
                esPropio = (o["_isCustom"] as? JsonPrimitive)?.let { !it.isString && it.content == "true" } == true,
            )
        }
    }
}

/** La base completa. El orden importa: es el de la web, y el ranking desempata por él. */
class BaseAlimentos(
    val alimentos: List<AlimentoBase>,
    /** De qué commit de la web salió (`fuente` de food-db.json). */
    val fuente: String? = null,
) {
    /**
     * Suma los alimentos propios del cliente como `hydrateSwapsAndCustomFoodsFromBackend` (cliente.html:5936): en orden,
     * cada uno REEMPLAZA en su lugar al que tenga el mismo nombre en minúsculas, o se agrega al final. `Number(null)` es
     * 0 y `unit_grams` 0 o null queda sin medida casera, igual que en la web.
     */
    fun conPropios(propios: List<AlimentoPropio>): BaseAlimentos {
        val lista = alimentos.toMutableList()
        for (p in propios) {
            val a = AlimentoBase(
                nombre = p.nombre, kcal = SemanticaJs.oCero(p.kcal), prot = SemanticaJs.oCero(p.prot), carb = SemanticaJs.oCero(p.carb),
                fat = SemanticaJs.oCero(p.fat), categoria = p.categoria, unidad = p.unidad, gramosPorUnidad = p.gramosPorUnidad,
                esPropio = true,
            )
            val i = lista.indexOfFirst { it.minusculas == a.minusculas }
            if (i >= 0) lista[i] = a else lista += a
        }
        return BaseAlimentos(lista, fuente)
    }

    companion object {
        /** Lee food-db.json: `{"fuente": …, "alimentos": [...]}` (o el array pelado de MYPUMP_FOOD_DB). */
        fun desde(json: String): BaseAlimentos {
            val e = Json.parseToJsonElement(json)
            if (e is JsonObject && e["alimentos"] is JsonArray) {
                val fuente = (e["fuente"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                return BaseAlimentos(listaEstricta(e["alimentos"]!!, AlimentoBase::desde), fuente)
            }
            return BaseAlimentos(listaEstricta(e, AlimentoBase::desde))
        }
    }
}
