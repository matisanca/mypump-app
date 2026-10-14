package com.pumpteam.mypump.modelos

import java.text.Normalizer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** La forma no es la esperada: no es un objeto, o un array que tenía que ser todo de objetos. */
class ErrorDecodificacion(mensaje: String) : Exception(mensaje)

/**
 * Lo que publica el Cerebro no tiene esquema fijo: `series` puede ser número o null, `reps` texto ("6-8", "10 min"),
 * `reemplaza` un array o un texto suelto, los bloques pueden venir null. Estos lectores nunca tiran: devuelven null
 * cuando el valor no sirve, y el modelo decide el default (como `normalizarRutina` de la web).
 *
 * Es la misma tolerancia que `Decodificacion.swift`, con una diferencia a propósito: un número se pasa a texto como lo
 * imprime JS (`String(x)`), que es lo que muestra la web ("1e-7" y no el "1e-07" de Swift).
 */
internal object Lector {
    fun entero(e: JsonElement): Int? {
        numero(e)?.let { d -> return if (d.isFinite()) truncarAInt(d) else null }
        texto(e)?.let { s -> return enteroAscii(recortarEspaciosSwift(s)) }
        return null
    }

    fun decimal(e: JsonElement): Double? {
        numero(e)?.let { d -> return if (d.isFinite()) d else null }
        texto(e)?.let { s -> return NumeroSwift.desdeTexto(recortarEspaciosSwift(s).replace(',', '.')) }
        return null
    }

    fun textoTolerante(e: JsonElement): String? {
        texto(e)?.let { return it }
        numero(e)?.let { d -> return if (d.isFinite()) NumeroJs.texto(d) else null }
        return null
    }

    fun booleano(e: JsonElement): Boolean? {
        booleanoCrudo(e)?.let { return it }
        numero(e)?.let { d -> return if (esEnteroDe64Bits(d)) d != 0.0 else null }
        texto(e)?.let { s ->
            // El `contains` de Swift compara por equivalencia canónica: "sí" con la tilde suelta también vale.
            return Normalizer.normalize(s.lowercase(), Normalizer.Form.NFC) in VERDADEROS
        }
        return null
    }

    /** Array de textos; un texto suelto vale como array de uno (pasa en `reemplaza`). Un elemento que no es texto ni null
     *  invalida el array entero, como `[String?]` de Swift. */
    fun textos(e: JsonElement): List<String>? {
        if (e is JsonArray) {
            if (e.any { it !is JsonNull && texto(it) == null }) return null
            return e.mapNotNull { texto(it) }
        }
        return texto(e)?.let { listOf(it) }
    }

    /** Array que tolera elementos null o con forma rota: se descartan, no rompen el resto. */
    fun <T : Any> lista(e: JsonElement?, leer: (JsonElement) -> T?): List<T> {
        if (e !is JsonArray) return emptyList()
        return e.mapNotNull { elemento ->
            try {
                leer(elemento)
            } catch (_: ErrorDecodificacion) {
                null
            }
        }
    }

    /** `Int` de Swift sobre un número: entero exacto y en rango; 2.5 o "2" no valen. */
    fun enteroEstricto(e: JsonElement): Int? {
        val d = numero(e) ?: return null
        return if (d == Math.floor(d) && d.isFinite()) truncarAInt(d) else null
    }

    // ── Lo crudo de kotlinx: JsonNull también es un JsonPrimitive, y true/false y los números no son "string". ──

    fun texto(e: JsonElement): String? = (e as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content

    fun numero(e: JsonElement): Double? {
        val p = e as? JsonPrimitive ?: return null
        if (p is JsonNull || p.isString || p.content == "true" || p.content == "false") return null
        return p.content.toDoubleOrNull()
    }

    fun booleanoCrudo(e: JsonElement): Boolean? {
        val p = e as? JsonPrimitive ?: return null
        if (p is JsonNull || p.isString) return null
        return when (p.content) {
            "true" -> true
            "false" -> false
            else -> null
        }
    }

    private val VERDADEROS = setOf("true", "1", "si", "sí")

    /** `Int(d)` de Swift trunca hacia el cero. Fuera del rango de `Int` de Kotlin (32 bits) no hay valor. */
    private fun truncarAInt(d: Double): Int? {
        val t = if (d < 0) Math.ceil(d) else Math.floor(d)
        return if (t >= Int.MIN_VALUE && t <= Int.MAX_VALUE) t.toInt() else null
    }

    private fun esEnteroDe64Bits(d: Double): Boolean =
        d.isFinite() && d == Math.floor(d) && d >= -9.223372036854775808E18 && d < 9.223372036854775808E18

    /** `Int(String)` de Swift: signo opcional y dígitos ASCII, nada más (ni espacios, ni "1.0", ni dígitos árabes). */
    private fun enteroAscii(s: String): Int? {
        if (s.isEmpty()) return null
        val inicio = if (s[0] == '+' || s[0] == '-') 1 else 0
        if (inicio == s.length || (inicio until s.length).any { s[it] !in '0'..'9' }) return null
        return s.toIntOrNull()
    }

    /** `trimmingCharacters(in: .whitespaces)`: categoría Zs de Unicode más el tabulador (los saltos de línea no). */
    private fun recortarEspaciosSwift(s: String): String {
        val esEspacio = { c: Char -> c == '\t' || Character.getType(c) == Character.SPACE_SEPARATOR.toInt() }
        return s.trim(esEspacio)
    }
}

/** `Double(String)` de Swift (strtod con locale C, entero o nada): decimal, hexadecimal, inf/infinity/nan. */
internal object NumeroSwift {
    private val DECIMAL = Regex("[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
    private val HEXA = Regex("([+-]?)0[xX]((?:[0-9a-fA-F]+(?:\\.[0-9a-fA-F]*)?|\\.[0-9a-fA-F]+))(?:[pP]([+-]?[0-9]+))?")

    fun desdeTexto(s: String): Double? {
        if (DECIMAL.matches(s)) return s.toDouble()
        HEXA.matchEntire(s)?.let { m ->
            val (signo, mantisa, exponente) = m.destructured
            // Java pide el exponente binario; strtod no.
            return "${signo}0x${mantisa}p${exponente.ifEmpty { "0" }}".toDoubleOrNull()
        }
        // inf, infinity y nan sin importar mayúsculas, pero solo letras ASCII ("ınf" con la ı turca no es infinito).
        val conSigno = s.startsWith("+") || s.startsWith("-")
        val palabra = (if (conSigno) s.substring(1) else s).map { if (it in 'A'..'Z') it + 32 else it }.joinToString("")
        return when {
            palabra == "inf" || palabra == "infinity" -> if (s.startsWith("-")) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY
            palabra == "nan" || NAN_CON_CARGA.matches(palabra) -> Double.NaN
            else -> null
        }
    }

    private val NAN_CON_CARGA = Regex("nan\\([0-9a-z_]*\\)")
}

/** Un campo de un objeto que tiene que ser objeto (si no, el modelo usa su default). */
internal fun JsonObject.objeto(clave: String): JsonObject? = this[clave] as? JsonObject

internal fun JsonObject.entero(clave: String): Int? = this[clave]?.let(Lector::entero)
internal fun JsonObject.decimal(clave: String): Double? = this[clave]?.let(Lector::decimal)
internal fun JsonObject.texto(clave: String): String? = this[clave]?.let(Lector::textoTolerante)
internal fun JsonObject.booleano(clave: String): Boolean? = this[clave]?.let(Lector::booleano)
internal fun JsonObject.textos(clave: String): List<String>? = this[clave]?.let(Lector::textos)
internal fun <T : Any> JsonObject.lista(clave: String, leer: (JsonElement) -> T?): List<T> = Lector.lista(this[clave], leer)

/** Solo si es texto: un número nunca es igual a un texto para el `===` de la web. */
internal fun JsonObject.cadena(clave: String): String? = this[clave]?.let(Lector::texto)

/** `decodeIfPresent(JSONValue.self)`: null o ausente es null. */
internal fun JsonObject.valorJson(clave: String): ValorJson? =
    this[clave]?.takeUnless { it is JsonNull }?.let(ValorJson::desde)

/** El objeto de un modelo, o el error que hace que `lista` lo descarte. */
internal fun JsonElement.comoObjeto(tipo: String): JsonObject =
    this as? JsonObject ?: throw ErrorDecodificacion("$tipo: se esperaba un objeto y vino $this")

/**
 * `[T]` de Swift: un array con TODOS sus elementos válidos (si uno no es un objeto, falla el array entero). Es lo que
 * usan las respuestas de las RPC: una forma inesperada es un error, no una lista corta.
 */
fun <T> listaEstricta(e: JsonElement, leer: (JsonElement) -> T): List<T> {
    val a = e as? JsonArray ?: throw ErrorDecodificacion("se esperaba un array y vino $e")
    return a.map(leer)
}

/** Lo mismo desde el texto JSON. */
fun <T> listaEstricta(texto: String, leer: (JsonElement) -> T): List<T> = listaEstricta(Json.parseToJsonElement(texto), leer)
