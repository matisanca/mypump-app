package com.pumpteam.mypump.reglas

import java.util.BitSet
import java.util.regex.Matcher
import java.util.regex.Pattern

/**
 * Una regex escrita para JavaScript (sin flag `u`), evaluada con la MISMA semántica en Kotlin.
 *
 * La lógica que se porta de la web (categorías de alimentos, sustitutos, variantes de ejercicio…) está llena de regex de
 * JS, y `java.util.regex` las lee distinto. Encima, en Android `java.util.regex` es ICU (como NSRegularExpression en
 * iOS) y en la JVM de los tests es el motor de OpenJDK: una traducción que confíe en el significado de `\b`, `\w`, `.`
 * o `$` de uno de los dos motores no vale para el otro. Por eso todo lo que difiere se reescribe con construcciones que
 * significan lo mismo en los dos y en JS:
 *
 * - `\b`, `\B`, `\w`, `\W`, `\d`, `\D` son ASCII en JS ("á" o "ñ" NO son letras de palabra): van como lookarounds y
 *   clases ASCII explícitas. `\bpan\b` matchea "pané" en JS.
 * - `\s` de JS incluye U+00A0, U+FEFF y los espacios Unicode, y no U+0085: va como clase explícita.
 * - `.` de JS no toma \n, \r, U+2028 ni U+2029 (y sí U+0085, VT y FF, que Java o ICU cortan): clase explícita.
 * - `$` sin flag `m` es el fin del texto; el de Java e ICU también acepta un salto de línea final (`/^ajo$/` matchearía
 *   "ajo\n"): va como `\z`.
 * - Adentro de `[...]`, `[` y `&&` son literales en JS y operadores en Java e ICU; `[]` no matchea nada y `[^]` todo.
 *   Las clases se arman como conjunto de unidades UTF-16 y se escriben con `\x{…}`.
 * - Una llave que no es cuantificador (`a{`, `{x}`) es literal en JS y un error en Java.
 * - `/i` de JS sin `u` iguala por `toUpperCase` simple y nunca lleva un carácter no ASCII a uno ASCII: "ſ" no es "s" y
 *   el signo Kelvin no es "k". `CASE_INSENSITIVE | UNICODE_CASE` de Java sí los iguala, así que no se usa: cada
 *   literal y cada clase se expanden a sus equivalentes de JS.
 *
 * Límite conocido: Java mira el texto por code points y JS (sin `u`) por unidades UTF-16. Para estas regex no cambia
 * nada (ninguna cuenta caracteres sueltos de un emoji), pero un `.` solo sobre un emoji toma las dos mitades juntas.
 */
class JsRegex(patronJs: String, banderas: String = "") {
    private val patron: Pattern

    init {
        require(banderas.all { it == 'i' || it == 'g' }) { "bandera de JS no soportada: $banderas" }
        patron = try {
            Pattern.compile(traducir(patronJs, ignorarMayusculas = 'i' in banderas))
        } catch (e: Exception) {
            throw IllegalArgumentException("regex de JS que no traduce: $patronJs", e)
        }
    }

    /** `re.test(s)`. */
    fun prueba(s: String): Boolean = patron.matcher(s).find()

    /** `s.replace(/…/g, r)` con un reemplazo literal (sin `$1` ni `$&`). */
    fun reemplazarTodo(s: String, por: String): String = patron.matcher(s).replaceAll(Matcher.quoteReplacement(por))

    /** `re.exec(s)` sin `g`: el texto de cada grupo de la primera coincidencia (0 = todo), o null si no hay. */
    fun primera(s: String): List<String?>? {
        val m = patron.matcher(s)
        if (!m.find()) return null
        return (0..m.groupCount()).map { m.group(it) }
    }

    /** `s.split(re)` (sin límite ni grupos de captura), con el algoritmo de la especificación. */
    fun dividir(s: String): List<String> {
        val m = patron.matcher(s)
        if (s.isEmpty()) return if (m.lookingAt()) emptyList() else listOf("")
        val partes = mutableListOf<String>()
        var p = 0
        var q = 0
        while (q < s.length) {
            if (!m.find(q) || m.start() >= s.length) break
            val e = minOf(m.end(), s.length)
            if (e == p) {
                q = m.start() + 1
            } else {
                partes += s.substring(p, m.start())
                p = e
                q = p
            }
        }
        partes += s.substring(p)
        return partes
    }

    override fun toString(): String = "JsRegex(${patron.pattern()})"

    companion object {
        private const val PALABRA = "[A-Za-z0-9_]"

        /** `\b` de JS: entre una letra de palabra ASCII y algo que no lo es (o el borde). */
        private const val LIMITE = "(?:(?<=$PALABRA)(?!$PALABRA)|(?<!$PALABRA)(?=$PALABRA))"
        private const val NO_LIMITE = "(?:(?<=$PALABRA)(?=$PALABRA)|(?<!$PALABRA)(?!$PALABRA))"

        /** WhiteSpace + LineTerminator de JS: lo que toman `\s` y `trim()`. */
        private val ESPACIOS: BitSet = BitSet(0x10000).apply {
            for (c in "\t\n\u000B\u000C\r       　﻿") set(c.code)
            set(0x2000, 0x200B)
        }
        private val DIGITOS: BitSet = BitSet(0x10000).apply { set('0'.code, '9'.code + 1) }
        private val LETRAS_DE_PALABRA: BitSet = BitSet(0x10000).apply {
            set('A'.code, 'Z'.code + 1); set('a'.code, 'z'.code + 1); set('0'.code, '9'.code + 1); set('_'.code)
        }
        private val TERMINADORES: BitSet = BitSet(0x10000).apply { for (c in "\n\r  ") set(c.code) }

        /** Lo que el `.` de JS toma: todo menos los terminadores de línea. */
        private val PUNTO: String = clase(TERMINADORES, negada = true)

        /** El patrón de Java/ICU equivalente. Es público para los tests y para ver qué se compiló. */
        fun traducir(p: String, ignorarMayusculas: Boolean = false): String = Traductor(p, ignorarMayusculas).traducir()

        private fun complemento(b: BitSet): BitSet = BitSet(0x10000).apply { set(0, 0x10000); andNot(b) }

        /** Una clase de Java/ICU que significa ese conjunto de unidades UTF-16 (o su complemento). */
        private fun clase(conjunto: BitSet, negada: Boolean): String {
            if (conjunto.isEmpty) return if (negada) "[\\x{0}-\\x{10FFFF}]" else "(?:(?!))"
            val sb = StringBuilder(if (negada) "[^" else "[")
            var i = conjunto.nextSetBit(0)
            while (i >= 0) {
                val fin = conjunto.nextClearBit(i) - 1
                sb.append(escapar(i))
                if (fin > i) sb.append('-').append(escapar(fin))
                i = conjunto.nextSetBit(fin + 1)
            }
            // Con las dos mitades de los pares sustitutos adentro, JS matchea cada mitad de un emoji; Java ve el emoji como
            // un solo code point y necesita el rango suplementario.
            if (!negada && (0xD800..0xDFFF).all { conjunto.get(it) }) sb.append("\\x{10000}-\\x{10FFFF}")
            return sb.append(']').toString()
        }

        /** `\x{…}` y no `\u…`: Java junta dos `\u` sustitutos seguidos en un solo code point, y eso rompe los rangos. */
        private fun escapar(c: Int): String = "\\x{" + Integer.toHexString(c).uppercase() + "}"

        /** `Canonicalize` de JS sin `u`: mayúscula simple, pero nunca de un carácter no ASCII a uno ASCII. */
        private fun canonica(c: Char): Char {
            val u = c.toString().uppercase()
            if (u.length != 1) return c
            val cu = u[0]
            return if (c.code >= 128 && cu.code < 128) c else cu
        }

        /** Para cada carácter, los que JS con `/i` considera iguales (incluido él). Se arma una vez, si hace falta. */
        private val equivalentes: Map<Char, CharArray> by lazy {
            val porCanonica = HashMap<Char, MutableList<Char>>()
            for (code in 0 until 0x10000) {
                val c = code.toChar()
                porCanonica.getOrPut(canonica(c)) { mutableListOf() }.add(c)
            }
            val m = HashMap<Char, CharArray>()
            for (grupo in porCanonica.values) if (grupo.size > 1) {
                val arr = grupo.toCharArray()
                for (c in grupo) m[c] = arr
            }
            m
        }

        private fun expandirMayusculas(b: BitSet): BitSet {
            val out = b.clone() as BitSet
            var i = b.nextSetBit(0)
            while (i >= 0) {
                equivalentes[i.toChar()]?.forEach { out.set(it.code) }
                i = b.nextSetBit(i + 1)
            }
            return out
        }

        private val CUANTIFICADOR = Regex("\\{[0-9]+(?:,[0-9]*)?\\}")
        private val PREFIJO_DE_GRUPO = Regex("\\(\\?(?::|=|!|<=|<!|<[A-Za-z_][A-Za-z0-9_]*>)")
        private val DIGITOS_SEGUIDOS = Regex("[0-9]+")
        private val OCTAL = Regex("[0-7]{1,3}")
    }

    /** Recorre el patrón de JS una vez y escribe el de Java/ICU. */
    private class Traductor(val p: String, val ignorarMayusculas: Boolean) {
        private val out = StringBuilder()
        private var i = 0
        private val grupos = contarGrupos()

        fun traducir(): String {
            while (i < p.length) {
                when (val c = p[i]) {
                    '\\' -> escapeAfuera()
                    '[' -> claseDeCaracteres()
                    '.' -> { out.append(PUNTO); i++ }
                    '$' -> { out.append("\\z"); i++ }
                    '^', '|', ')', '*', '+', '?' -> { out.append(c); i++ }
                    '(' -> grupo()
                    '{' -> llave()
                    '}', ']' -> { out.append(escapar(c.code)); i++ }
                    else -> {
                        val cp = p.codePointAt(i)   // un par sustituto del patrón va como un solo code point
                        literal(cp)
                        i += Character.charCount(cp)
                    }
                }
            }
            return out.toString()
        }

        /** `(`, `(?:`, `(?=`, `(?!`, `(?<=`, `(?<!` y `(?<nombre>` significan lo mismo en los tres motores. */
        private fun grupo() {
            val prefijo = PREFIJO_DE_GRUPO.matchAt(p, i)?.value ?: "("
            out.append(prefijo)
            i += prefijo.length
        }

        /** `{n}`, `{n,}` y `{n,m}` son cuantificadores; cualquier otra llave es literal en JS y un error en Java. */
        private fun llave() {
            val m = CUANTIFICADOR.matchAt(p, i)
            if (m != null) {
                out.append(m.value)
                i += m.value.length
            } else {
                out.append(escapar('{'.code))
                i++
            }
        }

        private fun literal(cp: Int) {
            if (ignorarMayusculas && cp < 0x10000) {
                val eq = equivalentes[cp.toChar()]
                if (eq != null) {
                    out.append(clase(BitSet(0x10000).apply { eq.forEach { set(it.code) } }, negada = false))
                    return
                }
            }
            val ascii = cp in 'a'.code..'z'.code || cp in 'A'.code..'Z'.code || cp in '0'.code..'9'.code
            out.append(if (ascii) cp.toChar().toString() else escapar(cp))
        }

        private fun escapeAfuera() {
            if (i + 1 >= p.length) {        // `\` al final: en JS es un error; acá, la barra literal
                literal('\\'.code)
                i++
                return
            }
            when (val e = p[i + 1]) {
                'b' -> { out.append(LIMITE); i += 2 }
                'B' -> { out.append(NO_LIMITE); i += 2 }
                'w', 'W', 'd', 'D', 's', 'S' -> {
                    val (conjunto, negada) = claseEscape(e)
                    out.append(clase(conjunto, negada))
                    i += 2
                }
                in '1'..'9' -> {
                    val n = DIGITOS_SEGUIDOS.matchAt(p, i + 1)!!.value
                    if (n.toInt() <= grupos) {
                        out.append('\\').append(n)
                        i += 1 + n.length
                    } else {
                        literal(octalOLiteral())
                    }
                }
                'k' -> { out.append("\\k"); i += 2 }
                else -> literal(caracterEscapado())
            }
        }

        /** `[...]` de JS como conjunto de unidades UTF-16. */
        private fun claseDeCaracteres() {
            i++   // '['
            var negada = false
            if (i < p.length && p[i] == '^') {
                negada = true
                i++
            }
            val conjunto = BitSet(0x10000)
            fun sumar(atomo: Pair<Int?, BitSet?>) {
                atomo.first?.let { conjunto.set(it) } ?: conjunto.or(atomo.second!!)
            }
            var cerrada = false
            while (i < p.length) {
                if (p[i] == ']') {
                    i++
                    cerrada = true
                    break
                }
                val desde = atomoDeClase()
                if (i + 1 < p.length && p[i] == '-' && p[i + 1] != ']') {
                    i++   // el guion
                    val hasta = atomoDeClase()
                    val a = desde.first
                    val b = hasta.first
                    if (a != null && b != null) {
                        require(a <= b) { "rango fuera de orden en la clase: $p" }
                        conjunto.set(a, b + 1)
                    } else {
                        // Anexo B: con `\w` en un extremo (`[\w-x]`) no es un rango: los dos extremos y el guion.
                        sumar(desde)
                        conjunto.set('-'.code)
                        sumar(hasta)
                    }
                    continue
                }
                sumar(desde)
            }
            require(cerrada) { "clase sin cerrar: $p" }
            out.append(clase(if (ignorarMayusculas) expandirMayusculas(conjunto) else conjunto, negada))
        }

        /** Un elemento de una clase: un carácter (código) o un conjunto (`\w`, `\d`, `\s` y sus negados). */
        private fun atomoDeClase(): Pair<Int?, BitSet?> {
            val c = p[i]
            if (c != '\\') {
                i++
                return c.code to null
            }
            if (i + 1 >= p.length) {
                i++
                return '\\'.code to null
            }
            return when (val e = p[i + 1]) {
                'w', 'W', 'd', 'D', 's', 'S' -> {
                    i += 2
                    val (conjunto, negada) = claseEscape(e)
                    null to (if (negada) complemento(conjunto) else conjunto)
                }
                'b' -> { i += 2; 0x08 to null }     // adentro de una clase, \b es backspace
                'B' -> { i += 2; 'B'.code to null }
                in '1'..'9' -> octalOLiteral() to null
                else -> caracterEscapado() to null
            }
        }

        private fun claseEscape(e: Char): Pair<BitSet, Boolean> = when (e) {
            'w' -> LETRAS_DE_PALABRA to false
            'W' -> LETRAS_DE_PALABRA to true
            'd' -> DIGITOS to false
            'D' -> DIGITOS to true
            's' -> ESPACIOS to false
            else -> ESPACIOS to true
        }

        /** Con `i` en la barra: `\n`, `\t`, `\0`, `\xHH`, `\uHHHH`, `\cX` o un escape de identidad (`\.`, `\/`, `\-`…). */
        private fun caracterEscapado(): Int {
            val e = p[i + 1]
            if (e == '0' && i + 2 < p.length && p[i + 2] in '0'..'9') return octalOLiteral()
            i += 2
            return when (e) {
                'n' -> '\n'.code
                'r' -> '\r'.code
                't' -> '\t'.code
                'f' -> 0x0C
                'v' -> 0x0B
                '0' -> 0
                'x' -> hexa(2) ?: 'x'.code
                'u' -> hexa(4) ?: 'u'.code
                'c' -> if (i < p.length && (p[i] in 'a'..'z' || p[i] in 'A'..'Z')) {
                    p[i++].code % 32
                } else {
                    i--               // `\c` sin letra: la barra es literal y la `c` se lee después
                    '\\'.code
                }
                else -> e.code
            }
        }

        /** Anexo B, con `i` en la barra: `\NNN` que no es referencia es octal (hasta 377), o el dígito literal (8 y 9). */
        private fun octalOLiteral(): Int {
            i++
            val m = OCTAL.matchAt(p, i)
            if (m == null) {
                return p[i++].code
            }
            var v = m.value
            while (v.toInt(8) > 0xFF) v = v.dropLast(1)
            i += v.length
            return v.toInt(8)
        }

        private fun hexa(n: Int): Int? {
            if (i + n > p.length) return null
            val h = p.substring(i, i + n)
            if (!h.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
            i += n
            return h.toInt(16)
        }

        /** Los grupos de captura: `(` sin `?`, o `(?<nombre>`. Para distinguir `\1` (referencia) de un octal. */
        private fun contarGrupos(): Int {
            var n = 0
            var k = 0
            var enClase = false
            while (k < p.length) {
                val c = p[k]
                when {
                    c == '\\' -> k++
                    enClase -> if (c == ']') enClase = false
                    c == '[' -> enClase = true
                    c == '(' -> {
                        val sinPregunta = k + 1 >= p.length || p[k + 1] != '?'
                        val conNombre = k + 3 < p.length && p[k + 2] == '<' && p[k + 3] != '=' && p[k + 3] != '!'
                        if (sinPregunta || conNombre) n++
                    }
                }
                k++
            }
            return n
        }
    }
}

/**
 * `Math.round` de JS: redondea .5 hacia +∞ (`Math.round(-2.5)` = -2; `round` de Kotlin va al par) y deja NaN e
 * infinitos como están (`roundToLong` los convierte en Long). No es `floor(x + 0.5)`: con 0.49999999999999994 la suma
 * ya redondea a 1.0 y daría 1 (JS da 0).
 */
fun jsRound(x: Double): Double {
    val piso = Math.floor(x)
    val r = if (x - piso >= 0.5) piso + 1 else piso
    // JS: entre -0.5 y 0 el resultado es -0 (no se ve al imprimir, pero así es igual bit a bit).
    return if (r == 0.0 && x < 0) -0.0 else r
}
