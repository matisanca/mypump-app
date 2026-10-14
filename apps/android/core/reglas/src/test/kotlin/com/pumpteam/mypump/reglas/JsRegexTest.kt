package com.pumpteam.mypump.reglas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * Casos donde Java (o ICU, en Android) y JS dan distinto si no se traduce. Lo esperado es lo que da JS: cada caso se
 * corrió en node (V8) con la misma regex y el mismo texto. Gemelo de JSRegexTests.swift, con más casos.
 */
class JsRegexTest {
    private fun prueba(patron: String, texto: String, banderas: String = "") = JsRegex(patron, banderas).prueba(texto)

    private fun casos(vararg c: Triple<String, String, Boolean>, banderas: String = "") {
        for ((patron, texto, js) in c) assertEquals(js, prueba(patron, texto, banderas), "/$patron/$banderas sobre ${texto.debug()}")
    }

    @Test
    fun limiteDePalabraEsAscii() = casos(
        // En JS "é" no es letra de palabra: hay límite entre "pan" y "é".
        Triple("\\bpan\\b", "pané", true),
        Triple("\\bpan\\b", "pan dulce", true),
        Triple("\\bpan\\b", "panceta", false),
        // "ñ" tampoco: \bmani\b matchea dentro de "maniñ".
        Triple("\\bmani\\b", "maniñ", true),
        // Y una palabra que EMPIEZA con acento no tiene límite antes en JS.
        Triple("\\bárbol", "árbol", false),
    )

    @Test
    fun wYdSonAscii() = casos(
        Triple("^\\w+$", "arroz", true),
        Triple("^\\w+$", "arróz", false),
        Triple("manzan\\w*", "manzanas", true),
        Triple("^\\d$", "٣", false),   // dígito árabe: en JS \d no lo toma
    )

    @Test
    fun clasesConCorchetesYAmpersand() = casos(
        Triple("[[]", "a[b", true),
        Triple("[a&b]", "&", true),
        Triple("[a&&b]", "&", true),   // en Java `&&` es intersección
        Triple("jam[óo]n", "jamón", true),
        Triple("[]", "a", false),      // `[]` no matchea nada
        Triple("^[^]$", "\n", true),   // `[^]` matchea todo
        Triple("[\\w-]+", "-", true),
        Triple("[a-]", "-", true),
        Triple("[\\b]", "\b", true),   // adentro de una clase, \b es backspace
    )

    @Test
    fun finDeTextoComoJs() = casos(
        // En JS /^ajo$/ no acepta un salto de línea final; el `$` de Java y de ICU sí (por eso va como \z).
        Triple("^ajo$", "ajo", true),
        Triple("^ajo$", "ajo\n", false),
        Triple("^ajo$", "ajo\r\n", false),
        Triple("\\bmani$", "mani\u0085", false),
        Triple("[$]", "u\$s", true),
        Triple("\\$", "u\$s", true),
    )

    @Test
    fun puntoYEspaciosDeJs() = casos(
        Triple("^.$", "\u0085", true),
        Triple("^.$", "\u000B", true),
        Triple("^.$", "\u000C", true),
        Triple("^.$", "\n", false),
        Triple("^.$", "\u2028", false),
        Triple("^.$", "\r", false),
        Triple("^\\s$", "\u00A0", true),
        Triple("^\\s$", "\uFEFF", true),
        Triple("^\\s$", "\u0085", false),
        Triple("^\\s$", "\u2007", true),
        Triple("^\\s$", "\u180E", false),
        Triple("^[\\s]$", "\uFEFF", true),
        Triple("^\\S$", "\u0085", true),
        Triple("^[^\\s]$", "\u0085", true),
    )

    @Test
    fun mayusculasDeJsSinU() = casos(
        Triple("\\bsmith\\b", "SMITH row", true),
        Triple("\\bsmith\\b", "ſmith row", false),   // la s larga no es "s" (con UNICODE_CASE de Java, sí)
        Triple("\\bsmith\\b", "Smith", true),
        Triple("k", "\u212A", false),                // ni el signo Kelvin es "k"
        Triple("K", "k", true),
        Triple("ñ", "Ñ", true),                       // CASE_INSENSITIVE solo de Java no lo iguala
        Triple("[a-z]", "Q", true),
        Triple("[^a-z]", "Q", false),
        Triple("ß", "ẞ", false),
        Triple("µ", "μ", true),
        Triple("µ", "Μ", true),
        Triple("σ", "ς", true),
        banderas = "i",
    )

    @Test
    fun llavesEscapesYGrupos() = casos(
        Triple("a{", "a{", true),
        Triple("{x}", "{x}", true),
        Triple("a{2}", "aa", true),
        Triple("a{2,}", "a", false),
        Triple("x]", "x]", true),
        Triple("\\x41", "A", true),
        Triple("\\u00e1", "á", true),
        Triple("\\cJ", "\n", true),
        Triple("\\0", "\u0000", true),
        Triple("(a)\\1", "aa", true),
        Triple("\\8", "8", true),
        Triple("\\/", "/", true),
        Triple("(?:ab)+", "abab", true),
        Triple("a(?=b)", "ab", true),
        Triple("a(?!b)", "ab", false),
    )

    @Test
    fun reemplazoLiteral() {
        assertEquals("curl  1  x ", JsRegex("[^a-z0-9 ]+").reemplazarTodo("curl \$1 (x)", " "))
        // El `.` de JS toma el VT: el paréntesis se va entero.
        assertEquals("curl   martillo", JsRegex("\\(.*?\\)").reemplazarTodo("curl (a\u000Bb) martillo", " "))
        assertEquals("a b\u0085c", JsRegex("\\s+").reemplazarTodo("a \u00A0\uFEFF b\u0085c", " "))
        assertEquals("-a-b-c-", JsRegex("x*").reemplazarTodo("abc", "-"))
        assertEquals("cafe a", JsRegex("[áàäâã]").reemplazarTodo("cáfe ä", "a"))
        assertEquals("Con Guiones Bajos", JsRegex("_").reemplazarTodo("Con_Guiones_Bajos", " "))
    }

    @Test
    fun splitDeJs() {
        assertEquals(listOf("", "pan", "integral", ""), JsRegex("[\\s/]+").dividir(" pan / integral  "))
        assertEquals(listOf(""), JsRegex("[\\s/]+").dividir(""))
        assertEquals(listOf("a", "b", "c"), JsRegex("x*").dividir("abc"))
        assertEquals(emptyList<String>(), JsRegex("x*").dividir(""))
        assertEquals(listOf("a", "", "b", ""), JsRegex(",").dividir("a,,b,"))
        assertEquals(listOf("a", "b\u0085c"), JsRegex("\\s+").dividir("a\u00A0b\u0085c"))
    }

    @Test
    fun execPrimeraAparicion() {
        val re = JsRegex("exercise-images\\/([^/]+)\\/")
        assertEquals(listOf("exercise-images/No_Existe/", "No_Existe"), re.primera("a/exercise-images/No_Existe/exercise-images/Leg_Press/0.jpg"))
        assertNull(re.primera("exercise-images//0.jpg"))
    }

    @Test
    fun redondeoDeJs() {
        val casos = listOf(2.5 to "3", -2.5 to "-2", 0.49999999999999994 to "0", 1234.5 to "1235", -0.4 to "-0", -0.5 to "-0",
            1e300 to "1e+300", Double.NaN to "NaN", 4.5 to "5")
        for ((x, js) in casos) {
            val r = jsRound(x)
            val texto = if (r == 0.0 && 1 / r < 0) "-0" else com.pumpteam.mypump.modelos.NumeroJs.texto(r)
            assertEquals(js, texto, "Math.round($x)")
        }
    }

    private fun String.debug() = this.map { if (it.code < 0x20 || it.code > 0x7E) "\\u%04x".format(it.code) else "$it" }.joinToString("")
}
