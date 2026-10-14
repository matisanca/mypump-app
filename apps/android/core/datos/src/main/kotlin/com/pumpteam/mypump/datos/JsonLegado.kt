package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.NumeroSwift
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.SemanticaJs
import java.security.MessageDigest

/** Lo que hace falta para leer lo que escribió JavaScript y para que el libro mayor sea determinista (JSONLegado.swift). */
object JsonLegado {
    /**
     * `JSON.parse` tolerante: null si no es JSON (la web hace `catch { queue = [] }` y sigue).
     *
     * `JSON.stringify` escribe un surrogate suelto como `\udXXX`. Pasa en la dedupeKey del chat, que la web arma con
     * `contenido.slice(0, 40)`: si el corte cae en medio de un emoji, queda la mitad. El suelto se cambia por U+FFFD antes
     * de decodificar (como iOS); el contenido del mensaje (que no se corta) no cambia.
     */
    fun parsear(texto: String): ValorJson? = try {
        ValorJson.parsear(sanearSurrogados(texto))
    } catch (_: Exception) {
        null
    }

    fun sanearSurrogados(s: String): String {
        if ('\\' !in s) return s   // sin barras no hay escapes
        fun hex4(i: Int): Int? {
            if (i + 4 > s.length) return null
            var v = 0
            for (k in i until i + 4) {
                val d = Character.digit(s[k], 16)
                if (d < 0 || s[k].code > 0x7F) return null
                v = v shl 4 or d
            }
            return v
        }
        val out = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            if (s[i] != '\\' || i + 1 >= s.length) {
                out.append(s[i])
                i++
                continue
            }
            // `\uXXXX`: lo único que puede venir roto. Cualquier otro escape (también `\\`) se copia entero, así una barra
            // escapada nunca se confunde con el comienzo de un escape.
            val v = if (s[i + 1] == 'u') hex4(i + 2) else null
            if (v == null) {
                out.append(s, i, i + 2)
                i += 2
                continue
            }
            when (v) {
                in 0xD800..0xDBFF -> {
                    val w = if (i + 12 <= s.length && s[i + 6] == '\\' && s[i + 7] == 'u') hex4(i + 8) else null
                    if (w != null && w in 0xDC00..0xDFFF) {
                        out.append(s, i, i + 12)
                        i += 12
                    } else {
                        out.append('�')
                        i += 6
                    }
                }
                in 0xDC00..0xDFFF -> {
                    out.append('�')
                    i += 6
                }
                else -> {
                    out.append(s, i, i + 6)
                    i += 6
                }
            }
        }
        return out.toString()
    }

    /**
     * Serialización canónica: claves ordenadas, sin espacios y los números enteros sin ".0". Es la base del id del libro
     * mayor, así que tiene que dar lo mismo en cada corrida (no hace falta que coincida con JavaScript ni con iOS).
     */
    fun canonico(v: ValorJson): String = StringBuilder().also { escribir(v, it) }.toString()

    private fun escribir(v: ValorJson, s: StringBuilder) {
        when (v) {
            ValorJson.Nulo -> s.append("null")
            is ValorJson.Booleano -> s.append(if (v.valor) "true" else "false")
            is ValorJson.Numero -> s.append(numero(v.valor))
            is ValorJson.Texto -> cadena(v.valor, s)
            is ValorJson.Lista -> {
                s.append('[')
                v.elementos.forEachIndexed { i, x ->
                    if (i > 0) s.append(',')
                    escribir(x, s)
                }
                s.append(']')
            }
            is ValorJson.Objeto -> {
                s.append('{')
                v.campos.keys.sorted().forEachIndexed { i, k ->
                    if (i > 0) s.append(',')
                    cadena(k, s)
                    s.append(':')
                    escribir(v.campos.getValue(k), s)
                }
                s.append('}')
            }
        }
    }

    fun numero(d: Double): String = if (d.isFinite() && d == Math.rint(d) && Math.abs(d) < 1e15) d.toLong().toString() else NumeroJs.texto(d)

    private fun cadena(t: String, s: StringBuilder) {
        s.append('"')
        for (c in t) {
            when {
                c == '"' -> s.append("\\\"")
                c == '\\' -> s.append("\\\\")
                c.code < 0x20 -> s.append("\\u00").append(HEX[c.code shr 4]).append(HEX[c.code and 0xF])
                else -> s.append(c)
            }
        }
        s.append('"')
    }

    fun sha256(s: String): String {
        val b = MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8))
        val out = StringBuilder(b.size * 2)
        for (x in b) out.append(HEX[(x.toInt() shr 4) and 0xF]).append(HEX[x.toInt() and 0xF])
        return out.toString()
    }

    private const val HEX = "0123456789abcdef"

    /** `!!valor` de JavaScript. */
    fun verdadero(v: ValorJson?): Boolean = SemanticaJs.esVerdadero(v)

    /** Un número de la web, que pudo quedar como texto (`localStorage` guarda todo como texto). El que no es finito no sirve. */
    fun numero(v: ValorJson?): Double? = when (v) {
        is ValorJson.Numero -> v.valor.takeIf { it.isFinite() }
        is ValorJson.Texto -> NumeroSwift.desdeTexto(NumeroSwift.recortarEspacios(v.valor))?.takeIf { it.isFinite() }
        else -> null
    }

    fun texto(v: ValorJson?): String? = when (v) {
        is ValorJson.Texto -> v.valor
        is ValorJson.Numero -> numero(v.valor)
        else -> null
    }
}
