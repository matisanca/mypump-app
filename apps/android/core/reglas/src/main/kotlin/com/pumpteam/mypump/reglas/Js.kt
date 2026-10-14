package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.TextoJs

/**
 * Lo que JavaScript hace con textos y números en la lógica de Entreno (gemelo de `JS`, SemanticaJS.swift): `parseInt`,
 * `parseFloat`, `${x}`, `trim()` y las cajas. Cada uno tiene su rareza: `parseInt("12abc")` es 12, `parseFloat(",5")` es
 * NaN, `${1e-7}` es "1e-7" y `trim()` saca U+FEFF pero no U+0085.
 *
 * Lo que Kotlin ya hace como JS no se reescribe: `==` compara por unidades UTF-16 (el `==` de Swift perdona NFC contra
 * NFD; JS y Kotlin no), y `uppercase()` / `lowercase()` usan el mapeo completo de Unicode sin idioma ("ß" → "SS") con la
 * sigma final.
 */
object Js {
    /** `s.trim()` */
    fun trim(s: String): String = TextoJs.recortar(s)

    /** `parseInt(s, 10)`; con `base10 = false` es `parseInt(s)`, que además acepta `0x`. null es NaN. */
    fun parseInt(s: String?, base10: Boolean = true): Double? {
        if (s == null) return null   // parseInt(null) es parseInt("null"): NaN
        var i = 0
        while (i < s.length && TextoJs.esEspacio(s[i])) i++
        var signo = 1.0
        if (i < s.length && s[i] == '-') {
            signo = -1.0
            i++
        } else if (i < s.length && s[i] == '+') {
            i++
        }
        var base = 10
        if (!base10 && i + 1 < s.length && s[i] == '0' && (s[i + 1] == 'x' || s[i + 1] == 'X')) {
            base = 16
            i += 2
        }
        val inicio = i
        while (i < s.length && valorDigito(s[i], base) != null) i++
        if (i == inicio) return null
        val digitos = s.substring(inicio, i)
        if (base == 10) return signo * digitos.toDouble()
        return signo * digitos.fold(0.0) { acc, c -> acc * 16 + valorDigito(c, 16)!! }
    }

    private fun valorDigito(c: Char, base: Int): Int? = when {
        c in '0'..'9' -> c - '0'
        base == 16 && c in 'a'..'f' -> c - 'a' + 10
        base == 16 && c in 'A'..'F' -> c - 'A' + 10
        else -> null
    }

    /** `parseFloat(s)`: el prefijo decimal más largo (con signo, punto y exponente), o `Infinity`. null es NaN. */
    fun parseFloat(s: String?): Double? {
        if (s == null) return null
        var i = 0
        while (i < s.length && TextoJs.esEspacio(s[i])) i++
        var signo = ""
        if (i < s.length && (s[i] == '+' || s[i] == '-')) {
            signo = s[i].toString()
            i++
        }
        if (s.startsWith("Infinity", i)) return if (signo == "-") Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY
        val cuerpo = StringBuilder()
        var hayDigitos = false
        while (i < s.length && s[i] in '0'..'9') {
            cuerpo.append(s[i])
            i++
            hayDigitos = true
        }
        if (i < s.length && s[i] == '.') {
            var k = i + 1
            val fraccion = StringBuilder()
            while (k < s.length && s[k] in '0'..'9') fraccion.append(s[k++])
            if (hayDigitos || fraccion.isNotEmpty()) {
                cuerpo.append('.').append(fraccion)
                i = k
                hayDigitos = true
            }
        }
        if (!hayDigitos) return null
        if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
            var k = i + 1
            val exponente = StringBuilder("e")
            if (k < s.length && (s[k] == '+' || s[k] == '-')) exponente.append(s[k++])
            val digitos = StringBuilder()
            while (k < s.length && s[k] in '0'..'9') digitos.append(s[k++])
            if (digitos.isNotEmpty()) cuerpo.append(exponente).append(digitos)
        }
        return (signo + cuerpo).toDouble()
    }

    /** `x || 0` sobre un número: null (null/undefined), NaN, 0 y −0 dan 0. */
    fun oCero(d: Double?): Double = if (d == null || d.isNaN() || d == 0.0) 0.0 else d

    /** `String(x)` y `${x}` de un número de JS ("1e-7", "100000000000000000000" hasta 1e21, "-0" es "0"). */
    fun texto(d: Double): String = NumeroJs.texto(d)

    /** `${x}` de un valor que puede ser null. */
    fun texto(d: Double?): String = if (d == null) "null" else NumeroJs.texto(d)

    /** `s.toUpperCase()` */
    fun mayusculas(s: String): String = s.uppercase()

    /** `s.toLowerCase()` */
    fun minusculas(s: String): String = s.lowercase()

    /** Un texto en un `||` o un `if` de JS: null y "" son falsos. */
    fun verdadero(s: String?): String? = s?.takeIf { it.isNotEmpty() }
}
