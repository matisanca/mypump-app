package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.ValorJson

/** Las macros de un alimento cada 100 g (las de la base y las de los alimentos propios). Gemelo de iOS. */
data class MacrosPor100(val kcal: Double, val p: Double, val c: Double, val g: Double) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "kcal" to ValorJson.Numero(kcal), "p" to ValorJson.Numero(p), "c" to ValorJson.Numero(c), "g" to ValorJson.Numero(g),
    )

    companion object {
        /** Estricto, como el `Decodable` de iOS: los cuatro números, entre 0 y 10000. */
        fun desde(v: ValorJson?): MacrosPor100? {
            val o = v as? ValorJson.Objeto ?: return null
            fun n(k: String): Double? = o[k]?.comoNumero?.takeIf { it.isFinite() && it >= 0 && it <= 10000 }
            return MacrosPor100(n("kcal") ?: return null, n("p") ?: return null, n("c") ?: return null, n("g") ?: return null)
        }
    }
}

/**
 * Un alimento que el cliente sumó a una comida del plan (2.0.3, D1: «comí 80 g de puré de zapallo y no lo pude cargar»,
 * «el huevo lo tuve que poner en extras y no en la misma comida»). Vive en el ajuste de esa comida y de ese día
 * ([AjusteComida.agregados]), con las macros ya calculadas por la cantidad: así la ficha y el brief lo leen sin la base.
 * Gemelo de `AlimentoAgregado` de iOS (mismo JSON).
 */
data class AlimentoAgregado(
    val nombre: String,
    /** La cantidad en [unidad]: «g» o una medida casera («unidad», «palma», «taza»…). */
    val cantidad: Double,
    val unidad: String,
    /** Los gramos de una [unidad] que no es «g» (para volver a editarla igual). null en gramos. */
    val gramosUnidad: Double?,
    /** Los gramos de la cantidad (lo mismo que [cantidad] si es en gramos). */
    val gramos: Double,
    /** Por la cantidad: kcal enteras y macros con un decimal, como [AjustePorciones.conCantidad]. */
    val kcal: Double,
    val p: Double,
    val c: Double,
    val g: Double,
    /** Para recalcular al cambiar la cantidad sin volver a buscar el alimento (un propio se puede borrar). */
    val por100: MacrosPor100,
    val origen: Origen,
    /** Cuándo se agregó (ms): lo identifica dentro de la comida. */
    val ts: Long,
) {
    enum class Origen(val valor: String) { BASE("base"), PROPIO("propio") }

    /** Como alimento de la comida (para las sumas, lo consumido y las filas). */
    val alimento: Alimento get() = Alimento(nombre = nombre, qty = cantidad, unidad = unidad, kcal = kcal, prot = p, carb = c, fat = g)

    /** El alimento del que salió, para volver a abrir la hoja de cantidad. */
    val candidato: AgregadosComida.Candidato
        get() = AgregadosComida.Candidato(nombre, por100, if (gramosUnidad != null) unidad else null, gramosUnidad, origen)

    fun aValor(): ValorJson {
        val campos = linkedMapOf<String, ValorJson>(
            "nombre" to ValorJson.Texto(nombre), "cantidad" to ValorJson.Numero(cantidad), "unidad" to ValorJson.Texto(unidad),
        )
        gramosUnidad?.let { campos["gramosUnidad"] = ValorJson.Numero(it) }
        campos["gramos"] = ValorJson.Numero(gramos)
        campos["kcal"] = ValorJson.Numero(kcal)
        campos["p"] = ValorJson.Numero(p)
        campos["c"] = ValorJson.Numero(c)
        campos["g"] = ValorJson.Numero(g)
        campos["por100"] = por100.aValor()
        campos["origen"] = ValorJson.Texto(origen.valor)
        campos["_ts"] = ValorJson.Numero(ts.toDouble())
        return ValorJson.Objeto(campos)
    }

    companion object {
        /**
         * Estricto, como el `Decodable` de iOS: lo que no tiene sentido (sin nombre, cantidad cero, macros negativas o
         * absurdas) no es un agregado y el ajuste lo descarta (solo ese, no el ajuste entero).
         */
        fun desde(v: ValorJson?): AlimentoAgregado? {
            val o = v as? ValorJson.Objeto ?: return null
            fun n(k: String, max: Double): Double? = o[k]?.comoNumero?.takeIf { it.isFinite() && it >= 0 && it <= max }
            val nombre = o["nombre"]?.comoTexto?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            val cantidad = n("cantidad", 100000.0)?.takeIf { it > 0 } ?: return null
            val unidad = o["unidad"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: "g"
            val gramosUnidad = o["gramosUnidad"]?.comoNumero?.takeIf { it.isFinite() && it > 0 }
            val gramos = n("gramos", 100000.0) ?: return null
            val kcal = n("kcal", 30000.0) ?: return null
            val p = n("p", 10000.0) ?: return null
            val c = n("c", 10000.0) ?: return null
            val g = n("g", 10000.0) ?: return null
            val por100 = MacrosPor100.desde(o["por100"]) ?: return null
            val origen = Origen.entries.firstOrNull { it.valor == o["origen"]?.comoTexto } ?: Origen.BASE
            val ts = o["_ts"]?.comoNumero?.takeIf { it.isFinite() && it >= 0 && it < 1e15 } ?: return null
            return AlimentoAgregado(nombre, cantidad, unidad, gramosUnidad, gramos, kcal, p, c, g, por100, origen, ts.toLong())
        }
    }
}

/**
 * Las cuentas de los alimentos agregados a una comida (D1) y de la hoja de cantidad (D2). Puro: lo usan las pantallas y
 * los tests, igual que `AgregadosComida` de iOS (vectores en `apps/shared/vectores/agregados_comida.json`).
 */
object AgregadosComida {
    /** Topes (la fila del día no puede pasar los 16000 bytes de nativa_004): por comida, por día y el tamaño del JSON. */
    const val MAXIMO_POR_COMIDA = 8
    const val MAXIMO_POR_DIA = 24
    const val MAXIMO_BYTES = 12000

    /** Lo más que se lee de una comida (una fila rota no puede traer mil). */
    internal const val MAXIMO_AL_LEER = 50
    const val LARGO_NOMBRE = 80

    /** Un alimento que se puede agregar: de la base (food-db) o propio del cliente. Macros por 100 g. */
    data class Candidato(
        val nombre: String,
        val por100: MacrosPor100,
        /** La medida casera que trae la base («unidad», «rebanada»…), con sus gramos. */
        val unidad: String?,
        val gramosPorUnidad: Double?,
        val origen: AlimentoAgregado.Origen,
    ) {
        constructor(a: AlimentoBase) : this(
            a.nombre, MacrosPor100(a.kcal, a.prot, a.carb, a.fat), a.unidad, a.gramosPorUnidad,
            if (a.esPropio) AlimentoAgregado.Origen.PROPIO else AlimentoAgregado.Origen.BASE,
        )
    }

    /** Una forma de contar la cantidad: «g» (gramos = 1) o una medida casera con sus gramos. */
    data class Medida(val nombre: String, val gramos: Double) {
        val esGramo: Boolean get() = nombre == "g"

        companion object {
            val GRAMO = Medida("g", 1.0)
        }
    }

    /**
     * Las medidas de un alimento: siempre gramos y, si la hay, una casera. Primero la de la base (huevo: «unidad» de 60 g);
     * si no, la de la porción casera de la web (`porcionReferencia`: palma, taza, puño, cucharada…).
     */
    fun medidas(c: Candidato): List<Medida> {
        val u = c.unidad
        val gu = c.gramosPorUnidad
        if (u != null && gu != null && gu.isFinite() && gu > 0) {
            val n = PorcionCasera.normalizar(u)
            if (n !in setOf("", "g", "gr", "grs", "gramo", "gramos", "ml", "cc")) {
                val nombre = if (n in setOf("u", "un", "uni", "unid", "unidad", "unidades")) "unidad" else PorcionCasera.singular(n)
                return listOf(Medida.GRAMO, Medida(nombre, gu))
            }
        }
        return medidaCasera(c.nombre)?.let { listOf(Medida.GRAMO, it) } ?: listOf(Medida.GRAMO)
    }

    /**
     * La medida casera de un alimento que va en gramos, con los mismos gramos con que la web arma «la mano»
     * ([PorcionCasera.referencia]). null si la web no da una (o es «libre», como las hojas verdes).
     */
    fun medidaCasera(nombre: String): Medida? {
        val name = PorcionCasera.normalizar(nombre)
        if (name.isEmpty()) return null
        fun has(vararg kw: String): Boolean = kw.any { name.contains(it) }
        if (has("mani", "cacahuate") && has("mantequilla", "manteca", "crema", "pasta", "untable")) return Medida("cucharada", 16.0)
        if (has("leche", "bebida", "jugo", "zumo", "licuado", "gaseosa", "kefir", "caldo", "infusion", "yogur bebible", "chocolatada")) {
            return Medida("vaso", 200.0)
        }
        if (has("aceite", "oliva", "ghee") || has("manteca", "mantequilla")) return Medida("cucharada", 15.0)
        if (has("almendra", "nuez", "nueces", "castana", "avellana", "pistacho", "mani", "cacahuate", "frutos secos",
                "semilla", "girasol", "chia", "lino", "mix de")) return Medida("puñado", 30.0)
        if (has("whey", "proteina en polvo", "caseina")) return Medida("scoop", 30.0)
        if (has("atun")) return Medida("lata", 120.0)
        if (has("pollo", "pechuga", "carne", "nalga", "bife", "cerdo", "lomo", "pescado", "merluza", "pavo", "salmon",
                "cuadril", "cuadrada", "peceto", "asado", "bondiola", "milanesa", "tira", "magra", "roast", "colita")) {
            // La palma es de 100 g cocido; en crudo, lo que pesa antes de perder el 25 %.
            return Medida("palma", if (has("crud")) jsRound(100 / 0.75) else 100.0)
        }
        if (has("arroz", "fideo", "pasta", "avena", "quinoa", "polenta", "tallarin", "noqui", "cuscus", "couscous",
                "trigo", "mostacho", "spaghetti", "ravioli")) {
            if (has("avena")) return Medida("taza", 80.0)
            if (has("cocid", "hervid", "al dente")) return Medida("taza", 175.0)
            if (has("fideo", "pasta", "tallarin", "noqui", "mostacho", "spaghetti", "ravioli", "cuscus", "couscous")) {
                return Medida("taza en crudo", 100.0)
            }
            if (has("quinoa")) return Medida("taza en crudo", 170.0)
            if (has("polenta")) return Medida("taza en crudo", 150.0)
            return Medida("taza en crudo", 185.0)
        }
        if (has("lenteja", "garbanzo", "poroto", "alubia", "frijol", "chaucha seca")) return Medida("taza", 190.0)
        if (has("papa", "patata", "batata", "boniato") && !has("papaya")) {
            // Puré: va por taza (la de los cocidos); la papa entera, por unidad mediana.
            return if (has("pure")) Medida("taza", 175.0) else Medida("mediana", 150.0)
        }
        if (has("lechuga", "rucula", "radicheta", "escarola", "hojas verdes", "mix de hojas")) return null
        if (has("brocoli", "brecol", "coliflor", "calabaza", "zapallo", "zanahoria", "espinaca", "morron", "pimiento",
                "berenjena", "zucchini", "zapallito", "repollo", "remolacha", "chaucha", "cebolla", "tomate", "verdura")) {
            return Medida("puño", 90.0)
        }
        if (has("ricota", "untable", "yogur", "yoghurt", "queso blanco", "queso crema", "cottage", "requeson")) return Medida("taza", 245.0)
        if (has("frutilla", "arandano", "mora", "frambuesa", "frutos rojos", "berries")) return Medida("puñado", 80.0)
        if (has("palta", "aguacate")) return Medida("palta", 140.0)
        if (has("pan") && !has("rallado")) return Medida("rebanada", 30.0)
        if (has("tostada")) return Medida("tostada", if (has("arroz")) 9.0 else 25.0)
        return null
    }

    /**
     * La búsqueda de la hoja de agregar, sobre la base con los propios: cada palabra de la consulta (sin tildes ni
     * mayúsculas) tiene que estar en el nombre. Primero los que empiezan con la primera palabra; después, el orden de la
     * base. Como mucho [limite]. Sin consulta, nada.
     */
    fun buscar(base: BaseAlimentos, consulta: String, limite: Int = 60): List<AlimentoBase> {
        val palabras = SustitucionAlimentos.normalizar(consulta).split(' ', '/').filter { it.isNotEmpty() }
        val primera = palabras.firstOrNull() ?: return emptyList()
        val todos = base.alimentos.filter { a -> palabras.all { a.normalizado.contains(it) } }
        val (empiezan, resto) = todos.partition { it.normalizado.startsWith(primera) }
        return (empiezan + resto).take(limite)
    }

    /** La medida con que abre la hoja: la de la base si la trae (1 huevo), si no 100 g. */
    fun inicial(c: Candidato): Pair<Double, Medida> {
        val ms = medidas(c)
        return if (c.unidad != null && ms.size > 1) 1.0 to ms[1] else 100.0 to Medida.GRAMO
    }

    /** De a cuánto cambian − y +: 5 g (10 g desde 100 g) o media medida. */
    fun paso(cantidad: Double, m: Medida): Double = if (m.esGramo) (if (cantidad >= 100) 10.0 else 5.0) else 0.5

    /** Lo que se puede poner: de 1 g a 2 kg, o de media a 50 medidas, en porciones servibles (gramos enteros, medias). */
    fun acotar(cantidad: Double, m: Medida): Double {
        if (!cantidad.isFinite()) return if (m.esGramo) 1.0 else 0.5
        if (m.esGramo) return jsRound(cantidad).coerceIn(1.0, 2000.0)
        return (jsRound(cantidad * 2) / 2).coerceIn(0.5, 50.0)
    }

    fun subir(cantidad: Double, m: Medida): Double {
        val p = paso(cantidad, m)
        // Desde una cantidad fuera de la grilla (37 g), el + lleva a la siguiente de la grilla (40 g).
        val siguiente = if (m.esGramo) (Math.floor(cantidad / p) + 1) * p else cantidad + p
        return acotar(siguiente, m)
    }

    fun bajar(cantidad: Double, m: Medida): Double {
        val p = paso(maxOf(0.0, cantidad - 1), m)
        val anterior = if (m.esGramo) (Math.ceil(cantidad / p) - 1) * p else cantidad - p
        return acotar(anterior, m)
    }

    /** El agregado con esa cantidad: los gramos y las macros por la cantidad (kcal enteras, macros con un decimal). */
    fun agregado(c: Candidato, cantidad: Double, medida: Medida, ts: Long): AlimentoAgregado {
        val q = acotar(cantidad, medida)
        val gramos = jsRound(q * medida.gramos * 10) / 10
        val f = gramos / 100
        return AlimentoAgregado(
            nombre = c.nombre.trim().let { recortar(it) }, cantidad = q, unidad = medida.nombre,
            gramosUnidad = if (medida.esGramo) null else medida.gramos, gramos = gramos, kcal = jsRound(c.por100.kcal * f),
            p = jsRound(c.por100.p * f * 10) / 10, c = jsRound(c.por100.c * f * 10) / 10, g = jsRound(c.por100.g * f * 10) / 10,
            por100 = c.por100, origen = c.origen, ts = ts,
        )
    }

    /** Los primeros [LARGO_NOMBRE] caracteres (los de Swift: grafemas, así una tilde suelta no queda cortada). */
    private fun recortar(s: String): String {
        val bi = java.text.BreakIterator.getCharacterInstance()
        bi.setText(s)
        var fin = 0
        repeat(LARGO_NOMBRE) {
            val sig = bi.next()
            if (sig == java.text.BreakIterator.DONE) return s
            fin = sig
        }
        return s.substring(0, fin)
    }

    /** Por qué no se puede agregar uno más (null: se puede). [ajustes] es el día con el agregado ya puesto. */
    fun motivoNoEntra(ajustes: Map<String, AjusteComida>, comidaId: String): String? {
        if ((ajustes[comidaId]?.agregados?.size ?: 0) > MAXIMO_POR_COMIDA) return "Llegaste a $MAXIMO_POR_COMIDA alimentos agregados en esta comida."
        if (ajustes.values.sumOf { it.agregados.size } > MAXIMO_POR_DIA) return "Llegaste a $MAXIMO_POR_DIA alimentos agregados en el día."
        if (bytes(ajustes) > MAXIMO_BYTES) return "No entran más alimentos agregados hoy."
        return null
    }

    /** Lo que pesa el día en JSON (lo que la base acota a 16000 bytes). */
    fun bytes(ajustes: Map<String, AjusteComida>): Int =
        ValorJson.Objeto(ajustes.mapValues { it.value.aValor() }).serializar().toByteArray(Charsets.UTF_8).size

    /** Los agregados de la comida como alimentos (los de una comida que hoy no se come no cuentan, pero quedan guardados). */
    fun alimentos(aj: AjusteComida?): List<Alimento> = if (aj == null || aj.omitida) emptyList() else aj.agregados.map { it.alimento }

    /**
     * Los tildes de «Comí» de una comida son índices: los del plan (0 until n) y después los agregados (n + j). Al borrar el
     * agregado [j], su tilde se va y los de los siguientes bajan uno (si no, se destildaba otro alimento).
     */
    fun excluidosTrasBorrar(excluidos: List<Int>, alimentosPlan: Int, borrado: Int): List<Int> {
        val k = alimentosPlan + borrado
        return excluidos.mapNotNull { if (it == k) null else if (it > k) it - 1 else it }
    }

    /**
     * Los agregados de una comida en el `resumen` que lee la ficha (nativa_004): nombre, cantidad, gramos y macros. Vacío,
     * la clave no va (el renglón queda como antes).
     */
    fun resumen(aj: AjusteComida?): List<ValorJson> = aj?.agregados.orEmpty().map {
        ValorJson.objeto(
            "nombre" to ValorJson.Texto(it.nombre), "cantidad" to ValorJson.Numero(it.cantidad), "unidad" to ValorJson.Texto(it.unidad),
            "gramos" to ValorJson.Numero(it.gramos), "kcal" to ValorJson.Numero(it.kcal), "p" to ValorJson.Numero(it.p),
            "c" to ValorJson.Numero(it.c), "g" to ValorJson.Numero(it.g),
        )
    }
}
