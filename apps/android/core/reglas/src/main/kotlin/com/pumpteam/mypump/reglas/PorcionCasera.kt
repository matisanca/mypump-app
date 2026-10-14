package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.TextoJs
import java.text.Normalizer

/**
 * "La mano": la equivalencia casera de un alimento (palmas, puños, tazas, cucharadas, vasos, latas…) para el cliente que
 * no usa balanza. Port exacto de `porcionReferencia` (cliente.html:5464). Devuelve el texto sin el "≈ " (lo agrega la
 * pantalla, salvo en "libre 🥗") o null si no hay equivalencia útil.
 */
object PorcionCasera {
    /**
     * @param qty `Number(food.qty)`: null es que no vino (NaN en la web) y no hay porción.
     * @param gramosPorUnidad `Number(food.unitGrams)`: null es que no vino.
     */
    fun referencia(nombre: String?, qty: Double?, unidad: String?, gramosPorUnidad: Double?): String? {
        val name = normalizar(nombre)
        if (name.isEmpty()) return null
        if (qty == null || !qty.isFinite() || qty <= 0) return null
        val unitRaw = normalizar(unidad)
        val unitGrams = gramosPorUnidad ?: Double.NaN
        val isMl = unitRaw in UNIDADES_ML
        val isGram = unitRaw.isEmpty() || unitRaw in UNIDADES_GRAMO || isMl

        // ---- Rama unidad: qty ya es un conteo ----
        if (!isGram) {
            val n: Double
            val base: String
            if (unitGrams > 0 && qty > 20) {
                n = qty / unitGrams
                base = if (unitRaw.isNotEmpty() && unitRaw !in PALABRAS_UNIDAD) singular(unitRaw) else sustantivo(name)
            } else if (unitRaw in PALABRAS_UNIDAD) {
                n = qty
                base = sustantivo(name)
            } else {
                return null   // unidad ya casera (plato, taza…): no aporta nada
            }
            return contar(n, base)
        }

        // ---- Rama gramos / ml ----
        fun has(vararg kw: String) = kw.any { name.contains(it) }
        val g = qty

        if (has("mani", "cacahuate") && has("mantequilla", "manteca", "crema", "pasta", "untable")) {
            if (g < 8) return "1 cucharadita"
            return contar(g / 16, "cucharada")
        }
        if (has("leche", "bebida", "jugo", "zumo", "licuado", "gaseosa", "kefir", "caldo", "infusion", "yogur bebible", "chocolatada")) {
            return contar(g / 200, "vaso")
        }
        if (isMl || has("aceite", "oliva", "ghee") || has("manteca", "mantequilla")) {
            if (isMl && g > 100 && !has("aceite", "oliva", "ghee", "manteca", "mantequilla")) return contar(g / 200, "vaso")
            if (g < 7.5) return "1 cucharadita"
            return contar(g / 15, "cucharada")
        }
        if (has("almendra", "nuez", "nueces", "castana", "avellana", "pistacho", "mani", "cacahuate", "frutos secos", "semilla",
                "girasol", "chia", "lino", "mix de")) {
            return contar(g / 30, "puñado")
        }
        if (has("whey", "proteina en polvo", "caseina") || (has("proteina") && g <= 60)) {
            val scoops = maxJs(1.0, jsRound(g / 30))
            return if (scoops == 1.0) "1 scoop (1 medida)" else "${num(scoops)} scoops"
        }
        if (has("atun")) {
            val n = g / 120
            val frac = n - Math.floor(n)
            if (frac >= 0.75) return "casi ${num(Math.ceil(n))} latas"
            val nh = jsRound(n * 2) / 2
            val whole = Math.floor(nh)
            val s = if (whole > 1) "s" else ""
            if (nh - whole == 0.5) return if (whole >= 1) "${num(whole)} lata$s y media" else "media lata"
            return "${num(whole)} lata$s escurrida$s"
        }
        if (has("pollo", "pechuga", "carne", "nalga", "bife", "cerdo", "lomo", "pescado", "merluza", "pavo", "salmon", "cuadril",
                "cuadrada", "peceto", "asado", "bondiola", "milanesa", "tira", "magra", "roast", "colita")) {
            val gCocido = if (has("crud")) g * 0.75 else g   // palma = 100 g COCIDO; crudo pierde ~25 %
            return contar(gCocido / 100, "palma")
        }
        if (has("arroz", "fideo", "pasta", "avena", "quinoa", "polenta", "tallarin", "noqui", "cuscus", "couscous", "trigo",
                "mostacho", "spaghetti", "ravioli")) {
            if (has("avena")) return taza(g / 80)
            if (has("cocid", "hervid", "al dente")) return taza(g / 175)
            var ratio = 2.8
            var rawCup = 185.0
            if (has("fideo", "pasta", "tallarin", "noqui", "mostacho", "spaghetti", "ravioli", "cuscus", "couscous")) {
                ratio = 2.4; rawCup = 100.0
            } else if (has("quinoa")) {
                ratio = 2.6; rawCup = 170.0
            } else if (has("polenta")) {
                ratio = 4.0; rawCup = 150.0
            }
            val cruda = taza(g / rawCup) ?: return null
            // JS concatena el null como "null" si la cocida no existe (no pasa: ratio > 0).
            return "$cruda en crudo (≈ ${taza((g * ratio) / 175) ?: "null"} cocido)"
        }
        if (has("lenteja", "garbanzo", "poroto", "alubia", "frijol", "chaucha seca")) return taza(g / 190)
        if (has("papa", "patata", "batata", "boniato") && !has("papaya")) {
            if (g < 110) return "1 chica"
            if (g <= 190) return "1 mediana"
            if (g <= 280) return "1 grande"
            return "${num(maxJs(2.0, jsRound(g / 160)))} medianas"
        }
        if (has("lechuga", "rucula", "radicheta", "escarola", "hojas verdes", "mix de hojas")) return "libre 🥗"
        if (has("brocoli", "brecol", "coliflor", "calabaza", "zapallo", "zanahoria", "espinaca", "morron", "pimiento", "berenjena",
                "zucchini", "zapallito", "repollo", "remolacha", "chaucha", "cebolla", "tomate", "verdura")) {
            return contar(g / 90, "puño")
        }
        if (has("ricota", "untable", "yogur", "yoghurt", "queso blanco", "queso crema", "cottage", "requeson")) return taza(g / 245)
        if (has("frutilla", "arandano", "mora", "frambuesa", "frutos rojos", "berries")) return contar(g / 80, "puñado")
        if (has("palta", "aguacate")) {
            if (g <= 90) return "media palta chica"
            if (g <= 160) return "1 palta"
            return "${medio(g / 140)} paltas"
        }
        if (has("pan") && !has("rallado")) {
            val n = maxJs(1.0, jsRound(g / 30))
            return "${num(n)} rebanada${if (n > 1) "s" else ""}"
        }
        if (has("tostada")) {
            val n = maxJs(1.0, jsRound(g / (if (has("arroz")) 9.0 else 25.0)))
            return "${num(n)} tostada${if (n > 1) "s" else ""}"
        }
        return null
    }

    // ── Helpers (los mismos de la web) ──

    private val UNIDADES_GRAMO = setOf("g", "gr", "grs", "gramo", "gramos")
    private val UNIDADES_ML = setOf("ml", "cc", "mililitro", "mililitros")
    private val PALABRAS_UNIDAD = setOf("u", "un", "uni", "unid", "unidad", "unidades")
    private val PALABRAS_VACIAS = setOf("de", "del", "la", "el", "los", "las", "al", "con", "a", "en", "sin", "y")
    private val separador = JsRegex("[\\s/]+")

    /** `norm`: minúsculas, NFD sin U+0300–U+036F, `trim` de JS. */
    internal fun normalizar(s: String?): String {
        val d = Normalizer.normalize((s ?: "").lowercase(), Normalizer.Form.NFD)
        return TextoJs.recortar(d.filterNot { it in '̀'..'ͯ' })
    }

    internal fun singular(w: String): String = when {
        w.length > 4 && w.endsWith("ces") -> w.dropLast(3) + "z"
        w.length > 3 && w.endsWith("es") -> w.dropLast(2)
        w.length > 3 && w.endsWith("s") -> w.dropLast(1)
        else -> w
    }

    internal fun plural(w: String): String = if (w.isNotEmpty() && w.last() in "aeiou") w + "s" else w + "es"

    /** `nounFromName`: la primera palabra con contenido del nombre, en singular. */
    internal fun sustantivo(name: String): String {
        val tokens = separador.dividir(name).filter { it.isNotEmpty() && it !in PALABRAS_VACIAS }
        return singular(tokens.firstOrNull() ?: name)
    }

    /** `fmtCount`: medias; "½ palma", "1½ palmas", "2 palmas". */
    internal fun contar(valor: Double, base: String): String? {
        val n = jsRound(valor * 2) / 2
        if (n <= 0) return null
        val whole = Math.floor(n)
        if (whole == 0.0) return "½ $base"
        if (n - whole == 0.5) return "${num(whole)}½ ${plural(base)}"
        return "${num(whole)} ${if (n == 1.0) base else plural(base)}"
    }

    /** `nStr`: medias sin sustantivo. */
    internal fun medio(valor: Double): String {
        val n = jsRound(valor * 2) / 2
        val whole = Math.floor(n)
        if (whole == 0.0) return "½"
        return if (n - whole == 0.5) "${num(whole)}½" else num(whole)
    }

    /** `fmtCup`: cuartos de taza (¼ ½ ¾). */
    internal fun taza(valor: Double): String? {
        val cups = jsRound(valor * 4) / 4
        if (cups <= 0) return null
        val whole = Math.floor(cups)
        val frac = when (cups - whole) {
            0.25 -> "¼"
            0.5 -> "½"
            0.75 -> "¾"
            else -> ""
        }
        val cantidad = if (whole == 0.0) frac else num(whole) + frac
        return "$cantidad ${if (cups > 1) "tazas" else "taza"}"
    }

    /** Un número en un texto de JS (`whole + '½'`): sin ".0", y con exponente pasado 1e21 como la web. */
    private fun num(d: Double): String = NumeroJs.texto(d)

    private fun maxJs(a: Double, b: Double) = SemanticaJs.max(a, b)
}
