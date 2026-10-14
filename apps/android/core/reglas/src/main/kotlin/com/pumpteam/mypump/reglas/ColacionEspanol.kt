package com.pumpteam.mypump.reglas

import java.text.Normalizer

/**
 * `a.localeCompare(b, 'es')` de la web, igual en la JVM y en cualquier Android.
 *
 * Por qué no `java.text.Collator`: el de OpenJDK (la JVM de los tests) trata el espacio y la puntuación como ignorables,
 * y ICU (V8 en la web, y `java.text.Collator` en Android) les da peso primario y los pone antes que los dígitos y las
 * letras. Con el de OpenJDK, "Curl de bíceps agarre ancho" queda antes que "Curl de bíceps a una mano" y cambian 294 de
 * las 1746 listas de sustitutos de los vectores. Y el ICU de Android depende de la versión del sistema. Esto es la
 * colación de ICU (UCA con las tablas raíz de CLDR, no ignorable, nivel terciario) más la del español (la ñ es una letra
 * después de la n), con los pesos sacados de `Intl.Collator('es')` de node para todo lo que puede aparecer en un nombre:
 * ASCII, Latin-1, Latin Extended-A, la puntuación general y las marcas combinantes.
 *
 * Cómo compara, como UCA: el texto en NFD se lleva a elementos (primario, secundario, terciario); primero decide la
 * secuencia de primarios (la letra base, el espacio y la puntuación), después la de secundarios (los acentos: "á" va
 * después de "a"), y después la de terciarios (minúscula antes que mayúscula). Igual en los tres niveles es 0, y el sort
 * estable deja el orden de entrada, como el de JS.
 *
 * Fuera de esas tablas (otros alfabetos, emoji) el orden es por code point después de todas las letras: aproximado,
 * pero determinista. Los nombres del catálogo no los usan.
 */
internal object ColacionEspanol {
    private class Grupo(val caracteres: String, val secundarios: String, val terciarios: String)

    // Generado de Intl.Collator('es') de node 26.0.0 (ICU 78.3, CLDR 48.0).
    private val GRUPOS = arrayOf(
        Grupo("\u0009", "0", "0"),
        Grupo("\u000A", "0", "0"),
        Grupo("\u000B", "0", "0"),
        Grupo("\u000C", "0", "0"),
        Grupo("\u000D", "0", "0"),
        Grupo("\u0085", "0", "0"),
        Grupo("\u2028", "0", "0"),
        Grupo("\u2029", "0", "0"),
        Grupo("\u0020\u3000\u1680\u2002\u2003\u2004\u2005\u2006\u2008\u2009\u200A\u205F\u00A0\u2007\u202F", "000000000000000", "012222222222333"),
        Grupo("\u203E", "0", "0"),
        Grupo("\u005F", "0", "0"),
        Grupo("\u2017", "0", "0"),
        Grupo("\u002D", "0", "0"),
        Grupo("\u2010\u2011", "00", "01"),
        Grupo("\u2012", "0", "0"),
        Grupo("\u2013", "0", "0"),
        Grupo("\u2014", "0", "0"),
        Grupo("\u2015", "0", "0"),
        Grupo("\u2053", "0", "0"),
        Grupo("\u002C", "0", "0"),
        Grupo("\u003B", "0", "0"),
        Grupo("\u204F", "0", "0"),
        Grupo("\u003A", "0", "0"),
        Grupo("\u0021", "0", "0"),
        Grupo("\u203C", "0", "0"),
        Grupo("\u2049", "0", "0"),
        Grupo("\u00A1", "0", "0"),
        Grupo("\u003F", "0", "0"),
        Grupo("\u2048", "0", "0"),
        Grupo("\u2047", "0", "0"),
        Grupo("\u00BF", "0", "0"),
        Grupo("\u203D", "0", "0"),
        Grupo("\u002E\u2024", "00", "01"),
        Grupo("\u2025", "0", "0"),
        Grupo("\u2026", "0", "0"),
        Grupo("\u00B7", "0", "0"),
        Grupo("\u2055", "0", "0"),
        Grupo("\u2056", "0", "0"),
        Grupo("\u2058", "0", "0"),
        Grupo("\u2059", "0", "0"),
        Grupo("\u205A", "0", "0"),
        Grupo("\u205B", "0", "0"),
        Grupo("\u205C", "0", "0"),
        Grupo("\u205D", "0", "0"),
        Grupo("\u205E", "0", "0"),
        Grupo("\u0027\u2018\u2019\u201A\u201B", "01234", "00000"),
        Grupo("\u2039", "0", "0"),
        Grupo("\u203A", "0", "0"),
        Grupo("\u0022\u201C\u201D\u201E\u201F", "01234", "00000"),
        Grupo("\u00AB", "0", "0"),
        Grupo("\u00BB", "0", "0"),
        Grupo("\u0028", "0", "0"),
        Grupo("\u0029", "0", "0"),
        Grupo("\u005B", "0", "0"),
        Grupo("\u005D", "0", "0"),
        Grupo("\u007B", "0", "0"),
        Grupo("\u007D", "0", "0"),
        Grupo("\u2045", "0", "0"),
        Grupo("\u2046", "0", "0"),
        Grupo("\u2016", "0", "0"),
        Grupo("\u00A7", "0", "0"),
        Grupo("\u00B6", "0", "0"),
        Grupo("\u204B", "0", "0"),
        Grupo("\u0040", "0", "0"),
        Grupo("\u002A", "0", "0"),
        Grupo("\u204E", "0", "0"),
        Grupo("\u2051", "0", "0"),
        Grupo("\u002F", "0", "0"),
        Grupo("\u005C", "0", "0"),
        Grupo("\u0026", "0", "0"),
        Grupo("\u204A", "0", "0"),
        Grupo("\u0023", "0", "0"),
        Grupo("\u0025", "0", "0"),
        Grupo("\u2030", "0", "0"),
        Grupo("\u2031", "0", "0"),
        Grupo("\u2020", "0", "0"),
        Grupo("\u2021", "0", "0"),
        Grupo("\u2022", "0", "0"),
        Grupo("\u2023", "0", "0"),
        Grupo("\u2027", "0", "0"),
        Grupo("\u2043", "0", "0"),
        Grupo("\u204C", "0", "0"),
        Grupo("\u204D", "0", "0"),
        Grupo("\u2032", "0", "0"),
        Grupo("\u2033", "0", "0"),
        Grupo("\u2034", "0", "0"),
        Grupo("\u2057", "0", "0"),
        Grupo("\u2035", "0", "0"),
        Grupo("\u2036", "0", "0"),
        Grupo("\u2037", "0", "0"),
        Grupo("\u2038", "0", "0"),
        Grupo("\u203B", "0", "0"),
        Grupo("\u203F", "0", "0"),
        Grupo("\u2054", "0", "0"),
        Grupo("\u2040", "0", "0"),
        Grupo("\u2050", "0", "0"),
        Grupo("\u2041", "0", "0"),
        Grupo("\u2042", "0", "0"),
        Grupo("\u0060", "0", "0"),
        Grupo("\u00B4", "0", "0"),
        Grupo("\u005E", "0", "0"),
        Grupo("\u00AF", "0", "0"),
        Grupo("\u00A8", "0", "0"),
        Grupo("\u00B8", "0", "0"),
        Grupo("\u00B0", "0", "0"),
        Grupo("\u00A9", "0", "0"),
        Grupo("\u00AE", "0", "0"),
        Grupo("\u2190", "0", "0"),
        Grupo("\u2192", "0", "0"),
        Grupo("\u002B", "0", "0"),
        Grupo("\u00B1", "0", "0"),
        Grupo("\u00F7", "0", "0"),
        Grupo("\u00D7", "0", "0"),
        Grupo("\u003C", "0", "0"),
        Grupo("\u003D", "0", "0"),
        Grupo("\u003E", "0", "0"),
        Grupo("\u00AC", "0", "0"),
        Grupo("\u007C", "0", "0"),
        Grupo("\u00A6", "0", "0"),
        Grupo("\u007E", "0", "0"),
        Grupo("\u2052", "0", "0"),
        Grupo("\u2044", "0", "0"),
        Grupo("\u2713", "0", "0"),
        Grupo("\u00A4", "0", "0"),
        Grupo("\u00A2", "0", "0"),
        Grupo("\u0024", "0", "0"),
        Grupo("\u00A3", "0", "0"),
        Grupo("\u00A5", "0", "0"),
        Grupo("\u20AC", "0", "0"),
        Grupo("\u0030", "0", "0"),
        Grupo("\u0031\u00B9", "00", "01"),
        Grupo("\u0032\u00B2", "00", "01"),
        Grupo("\u0033\u00B3", "00", "01"),
        Grupo("\u0034", "0", "0"),
        Grupo("\u0035", "0", "0"),
        Grupo("\u0036", "0", "0"),
        Grupo("\u0037", "0", "0"),
        Grupo("\u0038", "0", "0"),
        Grupo("\u0039", "0", "0"),
        Grupo("\u0061\u0041\u00AA", "000", "012"),
        Grupo("\u00E6\u00C6", "00", "01"),
        Grupo("\u0062\u0042", "00", "01"),
        Grupo("\u0063\u0043", "00", "01"),
        Grupo("\u0064\u0044\u0111\u0110\u00F0\u00D0", "001122", "010101"),
        Grupo("\u0065\u0045", "00", "01"),
        Grupo("\u0066\u0046", "00", "01"),
        Grupo("\u0067\u0047", "00", "01"),
        Grupo("\u0068\u0048\u0127\u0126", "0011", "0101"),
        Grupo("\u0069\u0049", "00", "01"),
        Grupo("\u0133\u0132", "00", "01"),
        Grupo("\u0131", "0", "0"),
        Grupo("\u006A\u004A", "00", "01"),
        Grupo("\u006B\u004B", "00", "01"),
        Grupo("\u006C\u004C\u0142\u0141\u0140\u013F", "001122", "010101"),
        Grupo("\u006D\u004D", "00", "01"),
        Grupo("\u006E\u004E", "00", "01"),
        Grupo("\u014B\u014A", "00", "01"),
        Grupo("\u006F\u004F\u00BA\u00F8\u00D8", "00011", "01201"),
        Grupo("\u0153\u0152", "00", "01"),
        Grupo("\u0070\u0050", "00", "01"),
        Grupo("\u0071\u0051", "00", "01"),
        Grupo("\u0138", "0", "0"),
        Grupo("\u0072\u0052", "00", "01"),
        Grupo("\u0073\u0053\u017F", "001", "010"),
        Grupo("\u0074\u0054", "00", "01"),
        Grupo("\u2122", "0", "0"),
        Grupo("\u0167\u0166", "00", "01"),
        Grupo("\u0075\u0055", "00", "01"),
        Grupo("\u0076\u0056", "00", "01"),
        Grupo("\u0077\u0057", "00", "01"),
        Grupo("\u0078\u0058", "00", "01"),
        Grupo("\u0079\u0059", "00", "01"),
        Grupo("\u007A\u005A", "00", "01"),
        Grupo("\u00FE\u00DE", "00", "01"),
        Grupo("\u00B5", "0", "0"),
    )
    private val MARCAS = arrayOf(
        "\u0332",
        "\u0313",
        "\u0314",
        "\u0301",
        "\u0300",
        "\u0306",
        "\u0302",
        "\u030C",
        "\u030A",
        "\u0342",
        "\u0308",
        "\u030B",
        "\u0303",
        "\u0307",
        "\u0338",
        "\u0327",
        "\u0328",
        "\u0304",
        "\u030D\u030E\u0312\u0315\u031A\u033D\u033E\u033F\u0346\u034A\u034B\u034C\u0350\u0351\u0352\u0357\u035B\u035D\u035E",
        "\u0316\u0317\u0318\u0319\u031C\u031D\u031E\u031F\u0320\u0329\u032A\u032B\u032C\u032F\u0333\u033A\u033B\u033C\u0347\u0348\u0349\u034D\u034E\u0353\u0354\u0355\u0356\u0359\u035A\u035C\u035F\u0362",
        "\u0336\u0337",
        "\u0335",
        "\u0305",
        "\u0309",
        "\u030F",
        "\u0310",
        "\u0311",
        "\u031B",
        "\u0321",
        "\u0322",
        "\u0323",
        "\u0324",
        "\u0325",
        "\u0326",
        "\u032D",
        "\u032E",
        "\u0330",
        "\u0331",
        "\u0334",
        "\u0339",
        "\u0345",
        "\u0358",
        "\u0360",
        "\u0361",
    )
    private const val IGNORABLES = "\u00AD"

    /** Peso primario de los caracteres fuera de las tablas: después de todo lo conocido, por code point. */
    private const val PRIMARIO_DESCONOCIDO = 1_000_000

    /** Secundario común (letras y puntuación sin acento) y el de la primera marca combinante. */
    private const val SECUNDARIO_COMUN = 1
    private const val SECUNDARIO_MARCAS = 100

    private const val TERCIARIO_COMUN = 1

    // Por unidad UTF-16 del BMP: primario (0 = no está en las tablas), secundario y terciario.
    private val primario = IntArray(0x10000)
    private val secundario = IntArray(0x10000)
    private val terciario = IntArray(0x10000)
    private val ignorable = BooleanArray(0x10000)
    private val primarioEnie: Int

    init {
        // Los primarios van de a dos para que la ñ entre entre la n y lo que sigue (CLDR es: &N<ñ<<<Ñ).
        GRUPOS.forEachIndexed { i, g ->
            g.caracteres.forEachIndexed { j, c ->
                primario[c.code] = 2 * (i + 1)
                secundario[c.code] = SECUNDARIO_COMUN + (g.secundarios[j] - '0')
                terciario[c.code] = TERCIARIO_COMUN + (g.terciarios[j] - '0')
            }
        }
        MARCAS.forEachIndexed { i, grupo -> grupo.forEach { secundario[it.code] = SECUNDARIO_MARCAS + i } }
        IGNORABLES.forEach { ignorable[it.code] = true }
        primarioEnie = primario['n'.code] + 1
    }

    /** Las expansiones de UCA que pueden aparecer: un carácter que pesa como varios. */
    private val EXPANSIONES = mapOf(
        'ß' to "ss", '¼' to "1⁄4", '½' to "1⁄2", '¾' to "3⁄4", 'ŉ' to "ʼn",
    )

    /** La clave de un texto: sus pesos de cada nivel, para comparar muchas veces el mismo nombre sin recalcular. */
    class Clave internal constructor(
        private val primarios: IntArray,
        private val secundarios: IntArray,
        private val terciarios: IntArray,
    ) : Comparable<Clave> {
        override fun compareTo(other: Clave): Int {
            comparar(primarios, other.primarios).let { if (it != 0) return it }
            comparar(secundarios, other.secundarios).let { if (it != 0) return it }
            return comparar(terciarios, other.terciarios)
        }

        private fun comparar(a: IntArray, b: IntArray): Int {
            for (i in 0 until minOf(a.size, b.size)) if (a[i] != b[i]) return if (a[i] < b[i]) -1 else 1
            return a.size.compareTo(b.size)
        }
    }

    fun comparar(a: String, b: String): Int = clave(a).compareTo(clave(b))

    fun clave(texto: String): Clave {
        val s = Normalizer.normalize(texto, Normalizer.Form.NFD)
        val p = IntListaSimple()
        val sec = IntListaSimple()
        val ter = IntListaSimple()
        fun elemento(pr: Int, se: Int, te: Int) {
            if (pr != 0) p.add(pr)
            if (se != 0) sec.add(se)
            if (te != 0) ter.add(te)
        }
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            i += Character.charCount(cp)
            if (cp >= 0x10000) {
                elemento(PRIMARIO_DESCONOCIDO + cp, SECUNDARIO_COMUN, TERCIARIO_COMUN)
                continue
            }
            val c = cp.toChar()
            // La ñ del español: n + tilde combinante es una sola letra (con la mayúscula como variante terciaria).
            if ((c == 'n' || c == 'N') && i < s.length && s[i] == '̃') {
                elemento(primarioEnie, SECUNDARIO_COMUN, terciario[cp])
                i++
                continue
            }
            val expansion = EXPANSIONES[c]
            if (expansion != null) {
                for (x in expansion) {
                    elemento(primario[x.code].takeIf { it != 0 } ?: (PRIMARIO_DESCONOCIDO + x.code), SECUNDARIO_COMUN, TERCIARIO_COMUN + 3)
                }
                continue
            }
            when {
                ignorable[cp] -> {}
                primario[cp] != 0 -> elemento(primario[cp], secundario[cp], terciario[cp])
                secundario[cp] >= SECUNDARIO_MARCAS -> elemento(0, secundario[cp], TERCIARIO_COMUN)   // marca combinante
                Character.getType(cp) == Character.FORMAT.toInt() || Character.getType(cp) == Character.CONTROL.toInt() -> {}
                else -> elemento(PRIMARIO_DESCONOCIDO + cp, SECUNDARIO_COMUN, TERCIARIO_COMUN)
            }
        }
        return Clave(p.aArray(), sec.aArray(), ter.aArray())
    }

    /** Una lista de enteros sin cajas (los nombres son cortos y se comparan mucho). */
    private class IntListaSimple {
        private var datos = IntArray(32)
        private var n = 0
        fun add(x: Int) {
            if (n == datos.size) datos = datos.copyOf(n * 2)
            datos[n++] = x
        }
        fun aArray(): IntArray = datos.copyOf(n)
    }
}
