package com.pumpteam.mypump.modelos

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** Lo esperado es lo que da node (V8) para cada número: `String(x)` y `Number(s)`. */
class NumeroJsTest {
    private fun bits(hex: String) = java.lang.Double.longBitsToDouble(java.lang.Long.parseUnsignedLong(hex, 16))

    @Test
    fun imprimeComoJs() {
        val casos = listOf(
            0.1 + 0.2 to "0.30000000000000004",
            Math.pow(2.0, 60.0) to "1152921504606847000",
            1e21 to "1e+21",
            999999999999999900000.0 to "999999999999999900000",
            1.0 / 3 to "0.3333333333333333",
            java.lang.Double.MIN_VALUE to "5e-324",
            Double.MAX_VALUE to "1.7976931348623157e+308",
            123456789012345680000.0 to "123456789012345680000",
            0.000001 to "0.000001",
            0.0000015 to "0.0000015",
            1e-7 to "1e-7",
            1.5e-7 to "1.5e-7",
            4.35 to "4.35",
            0.5 to "0.5",
            100.0 to "100",
            1e20 to "100000000000000000000",
            Math.pow(2.0, 53.0) to "9007199254740992",
            Math.pow(2.0, 53.0) + 2 to "9007199254740994",
            1234.5678 to "1234.5678",
            2.5e-5 to "0.000025",
            123e-20 to "1.23e-18",
            1e16 to "10000000000000000",
            12345678901234567.0 to "12345678901234568",
            4.94e-322 to "4.94e-322",
            Math.pow(2.0, 1023.0) to "8.98846567431158e+307",
            8.41e21 to "8.41e+21",
            -0.0000033 to "-0.0000033",
            -1e300 to "-1e+300",
            9.999999999999999e-7 to "0.000001",
            1.0000000000000002 to "1.0000000000000002",
            1e23 to "1e+23",
            2.675 to "2.675",
            -0.0 to "0",
            Double.NaN to "NaN",
            Double.NEGATIVE_INFINITY to "-Infinity",
        )
        for ((x, js) in casos) assertEquals(js, NumeroJs.texto(x), "String($x)")
    }

    @Test
    fun leeTextosComoNumberDeJs() {
        val casos = listOf(
            "" to "0000000000000000", " " to "0000000000000000", "45" to "4046800000000000", " 45 " to "4046800000000000",
            " 45﻿" to "4046800000000000", "45\u0085" to "7ff8000000000000", "1,5" to "7ff8000000000000",
            "1.5" to "3ff8000000000000", ".5" to "3fe0000000000000", "5." to "4014000000000000", "+5" to "4014000000000000",
            "-5" to "c014000000000000", "0x10" to "4030000000000000", "0X1f" to "403f000000000000", "-0x10" to "7ff8000000000000",
            "0o17" to "402e000000000000", "0b101" to "4014000000000000", "0b102" to "7ff8000000000000", "1e3" to "408f400000000000",
            "1E-3" to "3f50624dd2f1a9fc", "1e" to "7ff8000000000000", "e3" to "7ff8000000000000", "Infinity" to "7ff0000000000000",
            "-Infinity" to "fff0000000000000", "+Infinity" to "7ff0000000000000", "infinity" to "7ff8000000000000",
            "inf" to "7ff8000000000000", "NaN" to "7ff8000000000000", "abc" to "7ff8000000000000", "12abc" to "7ff8000000000000",
            "1_000" to "7ff8000000000000", "１２" to "7ff8000000000000", "\t\n 7 \r" to "401c000000000000", "0x" to "7ff8000000000000",
            "00012" to "4028000000000000", "-0" to "8000000000000000", "1.5f" to "7ff8000000000000", "1.5d" to "7ff8000000000000",
            "0x1p3" to "7ff8000000000000", "9007199254740993" to "4340000000000000", "1e400" to "7ff0000000000000",
            "-1e400" to "fff0000000000000", "1e-400" to "0000000000000000", "0.1e1" to "3ff0000000000000", "٣" to "7ff8000000000000",
        )
        for ((s, hex) in casos) {
            val esperado = bits(hex)
            val kotlin = NumeroJs.desdeTexto(s)
            // NaN no es igual a sí mismo: se comparan los bits (los dos NaN son el canónico).
            assertEquals(java.lang.Double.doubleToLongBits(esperado), java.lang.Double.doubleToLongBits(kotlin), "Number(${s.debug()})")
        }
    }

    @Test
    fun trimDeJs() {
        assertEquals("pan", TextoJs.recortar("﻿ pan 　"))
        assertEquals("pan\u0085", TextoJs.recortar("pan\u0085"))     // NEL no es espacio para JS
        assertEquals("\u001Cpan", TextoJs.recortar("\u001Cpan "))     // ni los separadores de información (Kotlin sí los saca)
        assertEquals("", TextoJs.recortar("   "))
    }

    private fun String.debug() = this.map { if (it.code < 0x20 || it.code > 0x7E) "\\u%04x".format(it.code) else "$it" }.joinToString("")
}
