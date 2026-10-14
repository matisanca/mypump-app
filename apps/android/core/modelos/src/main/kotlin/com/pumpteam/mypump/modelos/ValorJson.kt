package com.pumpteam.mypump.modelos

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral

/**
 * Valor JSON arbitrario (`JSONValue` en iOS). Hace falta donde la nativa tiene que devolver al servidor lo mismo que
 * recibió, como el `food_data` de un swap (con `_orig`, `_dev` y lo que se agregue mañana).
 *
 * Los números van como `Double`, igual que en JS: `80` y `80.0` son el mismo valor.
 */
sealed interface ValorJson {
    data object Nulo : ValorJson

    data class Booleano(val valor: Boolean) : ValorJson

    /** Igualdad de `Double` de verdad (0.0 == -0.0), no la de la caja (`equals` de `Double` las separa). */
    class Numero(val valor: Double) : ValorJson {
        override fun equals(other: Any?): Boolean = other is Numero && other.valor == valor
        override fun hashCode(): Int = if (valor == 0.0) 0 else valor.hashCode()
        override fun toString(): String = "Numero(${NumeroJs.texto(valor)})"
    }

    data class Texto(val valor: String) : ValorJson

    data class Lista(val elementos: List<ValorJson>) : ValorJson

    /** El orden de las claves se conserva (como `JSON.stringify` de un objeto de JS), pero no cuenta para la igualdad. */
    data class Objeto(val campos: Map<String, ValorJson>) : ValorJson

    /** `valor[clave]`: el campo de un objeto, o null si no es objeto o no lo tiene. */
    operator fun get(clave: String): ValorJson? = (this as? Objeto)?.campos?.get(clave)

    val comoTexto: String? get() = (this as? Texto)?.valor
    val comoNumero: Double? get() = (this as? Numero)?.valor

    /** A JSON de kotlinx. Los números como los imprime `JSON.stringify` (80, no 80.0); NaN e infinito, como null. */
    @OptIn(ExperimentalSerializationApi::class)
    fun aJson(): JsonElement = when (this) {
        Nulo -> JsonNull
        is Booleano -> JsonPrimitive(valor)
        is Numero -> if (valor.isFinite()) JsonUnquotedLiteral(NumeroJs.texto(valor)) else JsonNull
        is Texto -> JsonPrimitive(valor)
        is Lista -> JsonArray(elementos.map { it.aJson() })
        is Objeto -> JsonObject(campos.mapValues { it.value.aJson() })
    }

    /** El texto JSON. */
    fun serializar(): String = aJson().toString()

    companion object {
        fun desde(e: JsonElement): ValorJson = when (e) {
            JsonNull -> Nulo
            is JsonPrimitive -> when {
                e.isString -> Texto(e.content)
                e.content == "true" -> Booleano(true)
                e.content == "false" -> Booleano(false)
                else -> Numero(e.content.toDouble())
            }
            is JsonArray -> Lista(e.map(::desde))
            is JsonObject -> Objeto(e.mapValues { desde(it.value) })
        }

        fun parsear(texto: String): ValorJson = desde(Json.parseToJsonElement(texto))

        /** Atajo para armar objetos en el código y en los tests. */
        fun objeto(vararg campos: Pair<String, ValorJson>): Objeto = Objeto(linkedMapOf(*campos))
    }
}
