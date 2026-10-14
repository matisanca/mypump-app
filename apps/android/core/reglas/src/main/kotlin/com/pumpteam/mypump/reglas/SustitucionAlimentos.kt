package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.TextoJs
import com.pumpteam.mypump.modelos.ValorJson

/**
 * Un sustituto que ofrece el modal de "Sustituir", con la porción ya calculada. Es el objeto que arma `findSubstitutes`
 * de la web y el que se persiste en `mypump_food_swaps.food_data` (ver [foodData]).
 */
data class Sustituto(
    val nombre: String,
    /** Gramos, o unidades enteras si el alimento tiene medida casera ([unidad] dice cuál). */
    val qty: Double,
    val unidad: String,
    /** TOTALES de la porción que el cliente realmente come (no por 100 g). */
    val kcal: Double,
    val prot: Double,
    val carb: Double,
    val fat: Double,
    val categoria: String?,
    /** `_dev`: el peor desvío relativo entre kcal y macro dominante contra el original (0.05 = 5 %). */
    val desvio: Double,
    /** `_universal`: se consigue en cualquier país; la UI los muestra arriba. */
    val universal: Boolean = false,
    /** `_en`: etiqueta en inglés; solo la tienen los universales, y puede ser "". */
    val nombreIngles: String? = null,
    /** `_isCustom`: alimento propio del cliente. */
    val esPropio: Boolean = false,
) {
    /**
     * El objeto de la web: `{name, qty, unit, kcal, prot, carb, fat, category, _dev, _isCustom?, _universal?, _en?}`. (El
     * ancla `_orig` la agrega quien confirma el swap.)
     */
    val foodData: ValorJson
        get() {
            val o = linkedMapOf<String, ValorJson>(
                "name" to ValorJson.Texto(nombre), "qty" to ValorJson.Numero(qty), "unit" to ValorJson.Texto(unidad),
                "kcal" to ValorJson.Numero(kcal), "prot" to ValorJson.Numero(prot), "carb" to ValorJson.Numero(carb),
                "fat" to ValorJson.Numero(fat),
            )
            categoria?.let { o["category"] = ValorJson.Texto(it) }
            o["_dev"] = ValorJson.Numero(desvio)
            if (esPropio) o["_isCustom"] = ValorJson.Booleano(true)
            if (universal) {
                o["_universal"] = ValorJson.Booleano(true)
                o["_en"] = ValorJson.Texto(nombreIngles ?: "")
            }
            return ValorJson.Objeto(o)
        }
}

/** `_lastInfo` de la web: el diagnóstico de la última búsqueda, para los avisos del modal. */
data class InfoSustitucion(
    /** Cuántos candidatos escondieron las preferencias del cliente (si vacían la lista, el modal lo dice). */
    val prefsFiltraron: Int = 0,
    /** Densidad calórica absurda en el original (macros por porción guardadas como por 100 g en dietas viejas). */
    val macrosSospechosos: Boolean = false,
    /** La categoría exacta rendía menos de 3 candidatos reales y se sumaron los de la categoría por macros. */
    val categoriaFallback: Boolean = false,
)

data class ResultadoSustitucion(val sustitutos: List<Sustituto>, val info: InfoSustitucion)

/**
 * El motor de sustitución de alimentos: port exacto de `window.MyPump.foodSwap` (app.js:19-394), verificado con los
 * vectores que genera la web (scripts/nativa/vectores-alimentos.mjs).
 *
 * Política (decidida con Mati): misma categoría, mismo macro dominante, porción que ajusta a la vez kcal y macro
 * dominante, descartar solo los perfiles muy distintos (desvío > 35 %), top 30 más los universales y los propios, que se
 * garantizan siempre.
 */
object SustitucionAlimentos {
    /**
     * `_UNIVERSAL`: staples que se consiguen en cualquier país (clientes del exterior). Minúsculas y sin tilde; un
     * alimento es universal si su nombre normalizado los contiene como palabra. Nunca se filtran por desvío.
     */
    private val universales = listOf(
        "pechuga de pollo", "muslo de pollo", "pollo entero", "pavo pechuga",
        "huevo entero", "clara de huevo",
        "atun al natural", "merluza", "lenguado", "salmon", "trucha",
        "carne vacuna picada", "nalga", "cuadril", "lomo vacuno", "bife de chorizo", "bife de costilla", "asado de tira",
        "vacio", "entrana", "paleta vacuna", "matambre",
        "leche", "yogur", "queso cottage", "queso mozzarella", "ricota",
        "arroz blanco", "arroz integral", "avena", "pan", "papa", "patata", "lentejas", "garbanzos", "porotos", "fideos",
        "aceite de oliva", "palta", "aguacate", "mani", "almendras", "nueces",
        "banana", "manzana", "naranja", "tomate", "zanahoria", "cebolla", "lechuga", "espinaca",
    )

    /** `_uniRe`: `new RegExp('\\b(' + _UNIVERSAL.join('|') + ')\\b')`. */
    private val reUniversal = JsRegex("\\b(" + universales.joinToString("|") + ")\\b")

    /** `_EN`: etiqueta en inglés para las cards universales. De lo específico a lo general: gana la primera clave contenida. */
    private val etiquetasIngles = listOf(
        "carne vacuna picada (magra" to "Lean ground beef (90/10)",
        "carne vacuna picada (comun" to "Ground beef (80/20)",
        "carne vacuna picada" to "Ground beef",
        "nalga" to "Beef round / topside",
        "cuadril" to "Beef rump",
        "lomo vacuno" to "Beef tenderloin",
        "bife de chorizo" to "Beef sirloin",
        "bife de costilla" to "Beef rib steak",
        "asado de tira" to "Beef short ribs",
        "vacio" to "Beef flank steak",
        "entrana" to "Beef skirt steak",
        "paleta vacuna" to "Beef shoulder / chuck",
        "matambre" to "Beef flank (matambre)",
        "pechuga de pollo" to "Chicken breast",
        "muslo de pollo" to "Chicken thigh",
        "pollo entero" to "Whole chicken",
        "pavo pechuga" to "Turkey breast",
        "clara de huevo" to "Egg whites",
        "huevo entero" to "Whole egg",
        "atun al natural" to "Canned tuna (in water)",
        "merluza" to "White fish (hake / sea bass)",
        "lenguado" to "White fish (sole)",
        "salmon" to "Salmon",
        "trucha" to "Trout",
        "leche" to "Milk",
        "yogur" to "Yogurt",
        "queso cottage" to "Cottage cheese",
        "queso mozzarella" to "Mozzarella",
        "ricota" to "Ricotta",
        "arroz" to "Rice",
        "avena" to "Oats",
        "fideos" to "Pasta",
        "pan" to "Bread",
        "papa" to "Potato",
        "patata" to "Potato",
        "lentejas" to "Lentils",
        "garbanzos" to "Chickpeas",
        "porotos" to "Beans",
        "aceite de oliva" to "Olive oil",
        "palta" to "Avocado",
        "aguacate" to "Avocado",
        "mani" to "Peanut",
        "almendras" to "Almonds",
        "nueces" to "Walnuts",
        "banana" to "Banana",
        "manzana" to "Apple",
        "naranja" to "Orange",
        "tomate" to "Tomato",
        "zanahoria" to "Carrot",
        "cebolla" to "Onion",
        "lechuga" to "Lettuce",
        "espinaca" to "Spinach",
    )

    /**
     * `_EXCLUDE_GROUPS`: lo que esconde cada preferencia del cliente (`mypump_cliente_prefs.excluir`), sobre el nombre
     * normalizado. "Bife de chorizo" es carne vacuna: por eso el cerdo matchea "chorizo fresco" y no "chorizo".
     */
    private val gruposExclusion = mapOf(
        "cerdo" to JsRegex("""\bcerdo\b|lechon|bondiola|\bpanceta\b|\btocino\b|\bjamon\b|\bsalame\b|\bsalami\b|chorizo fresco|longaniza|morcilla|salchicha|mortadela|prosciutto|pancetta|\bbacon\b"""),
        "mariscos" to JsRegex("""langostino|camaron|\bgamba\b|mejillon|\bcalamar\b|\bpulpo\b|almeja|\bostra\b|vieira|cangrejo|\bkani\b|surimi|\bmarisco|\bsepia\b|jibia|scallop"""),
        "lacteos" to JsRegex("""\bleche\b|yogur|\bqueso\b|ricota|\bnata\b|mozzarella|parmesano|provolone|cottage|\bcasein"""),
    )

    // `_norm`: estas tildes, de a una regex como en la web (sin normalizar Unicode: una tilde suelta, NFD, queda).
    private val sinTilde = listOf(
        JsRegex("[áàäâã]") to "a", JsRegex("[éèëê]") to "e", JsRegex("[íìïî]") to "i",
        JsRegex("[óòöôõ]") to "o", JsRegex("[úùüû]") to "u", JsRegex("ñ") to "n",
    )

    /** `_norm(name)`: minúsculas y sin tildes. */
    fun normalizar(nombre: String?): String {
        var s = (nombre ?: "").lowercase()
        for ((re, letra) in sinTilde) s = re.reemplazarTodo(s, letra)
        return s
    }

    /** `_isUniversal(name)`. */
    fun esUniversal(nombre: String): Boolean = esUniversalNormalizado(normalizar(nombre))
    internal fun esUniversalNormalizado(normalizado: String): Boolean = reUniversal.prueba(normalizado)

    /** `_enLabel(name)`: "" si ninguna clave matchea. */
    fun etiquetaIngles(nombre: String): String = etiquetaInglesNormalizado(normalizar(nombre))
    internal fun etiquetaInglesNormalizado(normalizado: String): String =
        etiquetasIngles.firstOrNull { normalizado.contains(it.first) }?.second ?: ""

    /** El macro que domina las kcal de un alimento (`_getDominantMacro`; en empate gana prot, después carb). */
    private enum class MacroDominante {
        PROT, CARB, FAT;

        fun de(a: Alimento): Double? = when (this) { PROT -> a.prot; CARB -> a.carb; FAT -> a.fat }
        fun de(a: AlimentoBase): Double = when (this) { PROT -> a.prot; CARB -> a.carb; FAT -> a.fat }
        fun de(s: Sustituto): Double = when (this) { PROT -> s.prot; CARB -> s.carb; FAT -> s.fat }

        companion object {
            fun de(prot: Double?, carb: Double?, fat: Double?): MacroDominante {
                val p = SemanticaJs.oCero(prot) * 4
                val c = SemanticaJs.oCero(carb) * 4
                val f = SemanticaJs.oCero(fat) * 9
                return if (p >= c && p >= f) PROT else if (c >= f) CARB else FAT
            }
        }
    }

    /**
     * `findSubstitutes(original)` con `window.MYPUMP_FOOD_DB = base` y `window.MYPUMP_PREFS.excluir = excluir`.
     *
     * @param original el alimento del plan (macros TOTALES de su `qty`). Si no trae categoría, se infiere.
     * @param base la base con los alimentos propios ya sumados ([BaseAlimentos.conPropios]).
     * @param excluir las etiquetas de `mypump_cliente_prefs` ("cerdo", "mariscos", "lacteos"); las desconocidas no hacen nada.
     */
    fun buscar(original: Alimento, base: BaseAlimentos, excluir: List<String> = emptyList()): ResultadoSustitucion {
        val db = base.alimentos
        if (db.isEmpty()) return ResultadoSustitucion(emptyList(), InfoSustitucion())

        val originalCat = original.categoria?.takeIf { it.isNotEmpty() } ?: CategoriaAlimento.inferir(original)
        // Condimento REAL (sin calorías) no se sustituye. Uno calórico mal inferido como condimento sigue (F8).
        if (originalCat == CategoriaAlimento.CONDIMENTO && SemanticaJs.oCero(original.kcal) < 30) {
            return ResultadoSustitucion(emptyList(), InfoSustitucion())
        }

        val dominante = MacroDominante.de(original.prot, original.carb, original.fat)
        val m0 = SemanticaJs.oCero(dominante.de(original))
        // `originalFood.kcal` va SIN `|| 0`: undefined no es > 0, igual que 0.
        val k0 = original.kcal ?: Double.NaN
        val hayK0 = k0 > 0

        // Gramos del original, para acotar el tamaño del sustituto: unidades × unitGrams si viene en unidades.
        val q = SemanticaJs.oCero(original.qty)
        val originalQtyG = when {
            original.unidad == "g" || original.unidad == "ml" -> q
            SemanticaJs.verdadero(original.gramosPorUnidad) -> q * original.gramosPorUnidad!!
            else -> q
        }
        // El sustituto no puede pedir más de 3× el original (con piso de 500 g para porciones chicas).
        val maxQty = SemanticaJs.max(originalQtyG * 3, 500.0)

        // F8: densidad calórica implícita absurda → macros probablemente corruptos. No bloquea; el modal avisa.
        var macrosSospechosos = false
        if (originalQtyG >= 20 && hayK0) {
            val dens = (k0 / originalQtyG) * 100
            if (dens > 950 || dens < 10) macrosSospechosos = true
        }

        val exclusiones = excluir.mapNotNull { gruposExclusion[it] }
        val nombreOriginal = original.nombre.lowercase()
        var excluidosPorPrefs = 0

        // matchCat && pasaPrefs: misma categoría, otro nombre, y las preferencias (que cuentan lo que esconden).
        fun candidato(f: AlimentoBase, cat: String): Boolean {
            if (f.categoria != cat || f.minusculas == nombreOriginal) return false
            if (exclusiones.isEmpty()) return true
            if (exclusiones.any { it.prueba(f.normalizado) }) {
                excluidosPorPrefs++
                return false
            }
            return true
        }

        val pool = db.filter { candidato(it, originalCat) }.toMutableList()
        // F8: si la categoría exacta rinde poco (< 3 no universales ni propios), sumar la categoría por macros.
        var categoriaFallback = false
        val catMacros = CategoriaAlimento.porMacros(original.prot, original.carb, original.fat)
        if (catMacros != null && catMacros != originalCat) {
            val nReal = pool.count { !it.universal && !it.esPropio }
            if (nReal < 3) {
                categoriaFallback = true
                val extra = db.filter { candidato(it, catMacros) }
                val vistos = pool.mapTo(HashSet()) { it.minusculas }   // como en la web: no se actualiza dentro del loop
                for (f in extra) if (f.minusculas !in vistos) pool += f
            }
        }
        val info = InfoSustitucion(excluidosPorPrefs, macrosSospechosos, categoriaFallback)

        val ranked = mutableListOf<Sustituto>()
        for (food in pool) {
            val k = food.kcal                // kcal por 100 g del sustituto
            val m = dominante.de(food)       // macro dominante por 100 g
            if (m == 0.0) continue

            // Porción por MEJOR AJUSTE combinado: el factor f (porción/100 g) que minimiza
            // ((K·f−K0)/K0)² + ((M·f−M0)/M0)². Con a = K/K0 y b = M/M0, f* = (a+b)/(a²+b²).
            val factor = if (hayK0 && m0 > 0) {
                val a = k / k0
                val b = m / m0
                val denom = a * a + b * b
                if (denom > 0) (a + b) / denom else (m0 / m)
            } else if (hayK0 && k > 0) {
                k0 / k                       // F8: original con macros en cero pero kcal válida
            } else {
                m0 / m
            }
            val requiredQty = factor * 100
            if (requiredQty <= 0 || requiredQty > maxQty) continue

            var qty = jsRound(requiredQty)
            var unidad = "g"
            var gramosReales = qty
            val ug = food.gramosPorUnidad
            if (ug != null) {
                val unidades = requiredQty / ug
                if (unidades >= 0.5) {
                    qty = jsRound(unidades)
                    unidad = food.unidad?.takeIf { it.isNotEmpty() } ?: "unidad"
                    gramosReales = qty * ug
                }
            }
            // Las macros salen de lo que el cliente REALMENTE come (la porción redondeada), no del factor exacto.
            val factorReal = gramosReales / 100
            val s = Sustituto(
                nombre = food.nombre, qty = qty, unidad = unidad,
                kcal = jsRound(k * factorReal),
                prot = jsRound(food.prot * factorReal * 10) / 10,
                carb = jsRound(food.carb * factorReal * 10) / 10,
                fat = jsRound(food.fat * factorReal * 10) / 10,
                categoria = food.categoria, desvio = 0.0, esPropio = food.esPropio,
            )
            val kcalDev = if (hayK0) Math.abs(s.kcal - k0) / k0 else 0.0
            val macroDev = if (m0 > 0) Math.abs(SemanticaJs.oCero(dominante.de(s)) - m0) / m0 else 0.0
            var conDesvio = s.copy(desvio = SemanticaJs.max(kcalDev, macroDev))
            if (food.universal) conDesvio = conDesvio.copy(universal = true, nombreIngles = food.nombreIngles)

            // Propios y universales: siempre, con su desvío real. El resto, solo si el perfil se parece.
            if (food.esPropio || food.universal || !(conDesvio.desvio > 0.35)) ranked += conDesvio
        }

        // Más exacto primero: `.sort((a, b) => a._dev - b._dev)`, estable (a igual desvío, el orden de la base).
        val ordenados = SemanticaJs.ordenarEstable(ranked) { a, b ->
            val d = a.desvio - b.desvio
            if (d < 0) -1 else if (d > 0) 1 else 0   // NaN cuenta como empate, como en JS
        }

        // Universales y propios se garantizan; el resto se corta a 30. Después, sin repetir nombre.
        val garantizado = { s: Sustituto -> s.universal || s.esPropio }
        val vistos = HashSet<String>()
        val sustitutos = (ordenados.filter(garantizado) + ordenados.filterNot(garantizado).take(30))
            .filter { vistos.add(it.nombre.lowercase()) }
        return ResultadoSustitucion(sustitutos, info)
    }

    /** `searchSubstitutes` / el buscador del modal: los que contienen el texto (minúsculas, `trim` de JS). Sin texto, todos. */
    fun filtrar(sustitutos: List<Sustituto>, consulta: String?): List<Sustituto> {
        if (consulta.isNullOrEmpty()) return sustitutos
        val q = TextoJs.recortar(consulta.lowercase())
        return sustitutos.filter { it.nombre.lowercase().contains(q) }
    }
}
