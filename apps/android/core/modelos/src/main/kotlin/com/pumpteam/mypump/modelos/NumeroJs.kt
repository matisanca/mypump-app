package com.pumpteam.mypump.modelos

import java.math.BigDecimal
import java.math.BigInteger
import java.math.MathContext
import java.math.RoundingMode

/**
 * Los números como los imprime y los lee JavaScript, que es la fuente de verdad de las reglas portadas.
 *
 * No se usa `Double.toString()`: en la JVM 21 da la representación más corta pero con otro formato ("1.0E-7", "80.0"),
 * y en Android depende de la versión del runtime. Acá el algoritmo es el de la especificación y da lo mismo en los dos.
 */
object NumeroJs {
    /** 2^53: por debajo, un entero se imprime tal cual (es la única representación que vuelve al mismo double). */
    private const val ENTERO_EXACTO = 9007199254740992.0

    /**
     * `String(x)` de JS (Number::toString, ECMA-262 §6.1.6.1.20): los dígitos más cortos que vuelven a dar el mismo
     * double; sin exponente entre 1e-6 y 1e21. `String(80)` = "80", `String(0.1 + 0.2)` = "0.30000000000000004",
     * `String(1e-7)` = "1e-7", `String(2 ** 60)` = "1152921504606847000".
     */
    fun texto(x: Double): String {
        if (x.isNaN()) return "NaN"
        if (x == 0.0) return "0"
        if (x.isInfinite()) return if (x > 0) "Infinity" else "-Infinity"
        if (x < 0) return "-" + texto(-x)
        if (x < ENTERO_EXACTO && x == Math.floor(x)) return x.toLong().toString()

        val (digitos, n) = digitosMasCortos(x)
        val k = digitos.length
        return when {
            n in k..21 -> digitos + "0".repeat(n - k)
            n in 1..21 -> digitos.substring(0, n) + "." + digitos.substring(n)
            n in -5..0 -> "0." + "0".repeat(-n) + digitos
            else -> {
                val e = n - 1
                val exponente = (if (e >= 0) "e+" else "e-") + Math.abs(e)
                if (k == 1) digitos + exponente else digitos[0] + "." + digitos.substring(1) + exponente
            }
        }
    }

    /**
     * Los dígitos `s` (sin ceros al final) y el exponente `n` tales que x = 0.s × 10^n, con la menor cantidad de dígitos
     * que vuelve a x. Entre dos candidatos del mismo largo gana el más cercano a x, y si empatan el par (como V8).
     */
    private fun digitosMasCortos(x: Double): Pair<String, Int> {
        val exacto = BigDecimal(x)
        for (p in 1..17) {
            val candidatos = listOf(RoundingMode.HALF_EVEN, RoundingMode.FLOOR, RoundingMode.CEILING)
                .map { exacto.round(MathContext(p, it)) }
                .filter { it.toString().toDouble() == x }
            if (candidatos.isEmpty()) continue
            val mejor = candidatos.minWith(
                compareBy<BigDecimal> { it.subtract(exacto).abs() }
                    .thenBy { it.stripTrailingZeros().unscaledValue().testBit(0) },
            ).stripTrailingZeros()
            val digitos = mejor.unscaledValue().toString()
            return digitos to (digitos.length - mejor.scale())
        }
        error("ningún largo de 1 a 17 dígitos vuelve a $x")
    }

    /**
     * `Number(s)` de JS sobre un texto: sin espacios de JS a los costados; vacío vale 0; decimal con signo y exponente,
     * `Infinity`, o entero en 0x / 0o / 0b (sin signo); cualquier otra cosa es NaN. `Number(" 45 ")` = 45,
     * `Number("abc")` = NaN, `Number("")` = 0, `Number("1,5")` = NaN.
     */
    fun desdeTexto(s: String): Double {
        val t = TextoJs.recortar(s)
        if (t.isEmpty()) return 0.0
        when (t) {
            "Infinity", "+Infinity" -> return Double.POSITIVE_INFINITY
            "-Infinity" -> return Double.NEGATIVE_INFINITY
        }
        if (t.length > 2 && t[0] == '0') {
            val base = when (t[1]) {
                'x', 'X' -> 16
                'o', 'O' -> 8
                'b', 'B' -> 2
                else -> 0
            }
            if (base != 0) {
                val cifras = t.substring(2)
                if (cifras.any { Character.digit(it, base) < 0 || it.code > 0x7F }) return Double.NaN
                return BigInteger(cifras, base).toDouble()
            }
        }
        return if (DECIMAL_JS.matches(t)) t.toDouble() else Double.NaN
    }

    // StrDecimalLiteral: dígitos ASCII, punto opcional, exponente opcional. Sin separadores ni sufijos (1.5f no vale).
    private val DECIMAL_JS = Regex("[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
}

/** Lo de los textos de JS que necesitan las reglas y la decodificación. */
object TextoJs {
    /**
     * Lo que `trim()` de JS considera espacio: WhiteSpace + LineTerminator. Incluye U+FEFF y NO incluye U+0085 ni
     * U+001C–U+001F (al revés que `trim()` de Kotlin).
     */
    fun esEspacio(c: Char): Boolean = when (c) {
        '\t', '\n', '\u000B', '\u000C', '\r', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
        '　', '﻿',
        -> true
        else -> c in ' '..' '
    }

    /** `s.trim()` de JS. */
    fun recortar(s: String): String {
        var i = 0
        var j = s.length
        while (i < j && esEspacio(s[i])) i++
        while (j > i && esEspacio(s[j - 1])) j--
        return s.substring(i, j)
    }
}
