package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.ValorJson

/**
 * Lo de JavaScript que las reglas necesitan con su semántica exacta: la verdad de un valor, `Number(x)`,
 * `String(x || '')`, `x || 0`, `Math.max` y el sort estable.
 *
 * Lo que en Swift hizo falta escribir a mano porque compara texto por equivalencia canónica (`==`, `contains`, `Set`)
 * acá viene gratis: `==`, `contains`, `startsWith` y `lowercase()` de Kotlin trabajan por unidades UTF-16 como JS
 * ("Vacío" con la í compuesta y con la tilde suelta son dos textos distintos), y `lowercase()` aplica la sigma final
 * griega igual que `toLowerCase()`.
 */
object SemanticaJs {
    /** `!!x` de JS sobre un valor JSON: null, false, 0, NaN y "" son falsos; objetos y arrays (aun vacíos) verdaderos. */
    fun esVerdadero(v: ValorJson?): Boolean = when (v) {
        null, ValorJson.Nulo -> false
        is ValorJson.Booleano -> v.valor
        is ValorJson.Numero -> v.valor != 0.0 && !v.valor.isNaN()
        is ValorJson.Texto -> v.valor.isNotEmpty()
        is ValorJson.Lista, is ValorJson.Objeto -> true
    }

    /** `Number(x)` de JS: null es 0, undefined (ausente) NaN, un texto como `Number("…")`, un array como su texto. */
    fun numero(v: ValorJson?): Double = when (v) {
        null -> Double.NaN
        ValorJson.Nulo -> 0.0
        is ValorJson.Booleano -> if (v.valor) 1.0 else 0.0
        is ValorJson.Numero -> v.valor
        is ValorJson.Texto -> NumeroJs.desdeTexto(v.valor)
        is ValorJson.Lista -> NumeroJs.desdeTexto(comoTexto(v))
        is ValorJson.Objeto -> Double.NaN
    }

    /** `String(x || '')` de JS: lo falso es "", un número como lo imprime JS, un array con sus elementos y comas. */
    fun texto(v: ValorJson?): String = if (!esVerdadero(v)) "" else comoTexto(v!!)

    /** `${x}` de JS dentro de un template: ausente es "undefined", null "null", el resto como `String(x)`. */
    fun plantilla(v: ValorJson?): String = if (v == null) "undefined" else comoTexto(v)

    /** `String(x)` de JS para un valor que llegó del JSON. */
    private fun comoTexto(v: ValorJson): String = when (v) {
        ValorJson.Nulo -> "null"
        is ValorJson.Booleano -> v.valor.toString()
        is ValorJson.Numero -> NumeroJs.texto(v.valor)
        is ValorJson.Texto -> v.valor
        // Array.prototype.join: null y undefined adentro de un array son "".
        is ValorJson.Lista -> v.elementos.joinToString(",") { if (it == ValorJson.Nulo) "" else comoTexto(it) }
        is ValorJson.Objeto -> "[object Object]"
    }

    /** `x || 0` sobre un número: undefined, null, 0, −0 y NaN valen 0 (el +0: `-0 || 0` es 0). */
    fun oCero(x: Double?): Double = Js.oCero(x)

    /** `if (x)` sobre un número: ni undefined, ni 0, ni NaN. */
    fun verdadero(x: Double?): Boolean = x != null && x != 0.0 && !x.isNaN()

    /** `Math.max(a, b)`: con un NaN da NaN (`maxOf` de Kotlin también, pero se escribe para que no dependa de eso). */
    fun max(a: Double, b: Double): Double = if (a.isNaN() || b.isNaN()) Double.NaN else if (a > b) a else b

    /**
     * El sort de JS (estable desde ES2019) con un comparador que devuelve un número: lo que empata queda en el orden de
     * entrada, y un comparador inconsistente (un NaN) no tira excepción como puede hacerlo el TimSort de Java.
     */
    fun <T> ordenarEstable(lista: List<T>, comparar: (T, T) -> Int): List<T> {
        if (lista.size < 2) return lista.toList()
        val medio = lista.size / 2
        val a = ordenarEstable(lista.subList(0, medio), comparar)
        val b = ordenarEstable(lista.subList(medio, lista.size), comparar)
        val out = ArrayList<T>(lista.size)
        var i = 0
        var j = 0
        while (i < a.size && j < b.size) {
            // Solo si el de la derecha es estrictamente menor pasa adelante: así se conserva el orden de los empates.
            if (comparar(b[j], a[i]) < 0) out += b[j++] else out += a[i++]
        }
        while (i < a.size) out += a[i++]
        while (j < b.size) out += b[j++]
        return out
    }
}
