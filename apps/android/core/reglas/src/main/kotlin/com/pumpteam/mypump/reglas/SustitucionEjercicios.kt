package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.EntradaCatalogoEjercicio
import com.pumpteam.mypump.modelos.Imagenes
import com.pumpteam.mypump.modelos.TextoJs
import com.pumpteam.mypump.modelos.listaEstricta

// Sustitución de ejercicios: port exacto de `window.MyPump.exerciseSwap` (public/js/app.js:396-747) y de
// `getEffectiveEx` y `exGetSubs` (cliente.html:2040 y 2554), igual que SustitucionEjercicios.swift. Lo verifican los
// vectores de scripts/nativa/vectores-ejercicios.mjs, que corren esas mismas funciones de la web.
//
// La regla (de la web, no negociable): un sustituto vale solo con el MISMO `patron_movimiento` y el MISMO
// `primary_muscle` que el original. Primero los de otro equipo ("la máquina está ocupada"), después alfabético en
// castellano, sin repetir nombre+equipo, máximo 30. Si el ejercicio no se resuelve en el catálogo o la fila no tiene
// patrón, no hay sustitutos. Calentamiento y cardio nunca tienen.
//
// Lo que la web hace raro y se iguala a propósito (se arregla allá, no acá):
// - `_toEs` junta variantes en el mismo nombre ("Curl de bíceps con barra" son varias filas): de cada nombre+equipo
//   queda la primera, y el resto no se ofrece.
// - Si el ejercicio del plan no trae imágenes ni slug y ya se sustituyó, `exGetSubs` resuelve por la foto del
//   SUSTITUTO (`ex._origImages || ex.images`), no por el original.
// - `_norm` no conoce los acentos descompuestos: "o" + U+0301 queda "o n".

/** Funciones puras de la sustitución: normalizar, resolver un nombre por reglas, traducir y ordenar. */
object SustitucionEjercicios {
    /**
     * `_norm`: minúsculas, sin las tildes que lista, sin paréntesis, sin el sufijo `-d1-0` del id, solo alfanumérico y
     * espacios colapsados. Es la del RPC `mypump_match_ejercicio_por_nombre`; NO es `claveEjercicio` (esa usa NFD).
     */
    fun normalizar(s: String?): String {
        var n = (s ?: "").lowercase()
        for ((re, letra) in vocales) n = re.reemplazarTodo(n, letra)
        n = parentesis.reemplazarTodo(n, " ")
        n = sufijoId.reemplazarTodo(n, " ")
        n = noAlfanumerico.reemplazarTodo(n, " ")
        n = espacios.reemplazarTodo(n, " ")
        return TextoJs.recortar(n)
    }

    /** `_resolveByRules`: el primer slug cuya regla matchea el nombre normalizado (específico → general). */
    fun slugPorReglas(nombre: String?): String? {
        val n = normalizar(nombre)
        if (n.isEmpty()) return null
        return reglas.firstOrNull { it.first.prueba(n) }?.second
    }

    /** `_toEs`: BASE (gesto) + MODIFICADORES + EQUIPO. Sin base devuelve el `name_en` tal cual (mejor inglés que algo roto). */
    fun castellano(e: EntradaCatalogoEjercicio): String {
        val en = (verdadero(e.nameEn) ?: "").lowercase()
        if (en.isEmpty()) return verdadero(e.slugEn)?.let { guionBajo.reemplazarTodo(it, " ") } ?: ""
        val base = bases.firstOrNull { it.first.prueba(en) }?.second ?: return e.nameEn ?: ""
        val eq = equipos.firstOrNull { it.first.prueba(en) }?.second ?: ""
        val mods = modificadores.filter { it.first.prueba(en) }.map { it.second }
        var out = base
        if (mods.isNotEmpty()) out += " " + mods.joinToString(" ")
        // Sin redundancia: "Cruce de poleas" ya dice polea.
        val nucleo = nucleosEquipo[eq] ?: eq.lowercase()
        if (eq.isNotEmpty() && !out.lowercase().contains(nucleo)) out += " $eq"
        return out
    }

    /** El músculo del catálogo en castellano, para el título de «Otros ejercicios de …». null si no se conoce. */
    fun musculo(m: String?): String? = when ((m ?: "").lowercase()) {
        "quadriceps" -> "cuádriceps"
        "shoulders" -> "hombros"
        "abdominals" -> "abdominales"
        "chest" -> "pecho"
        "hamstrings" -> "isquiotibiales"
        "triceps" -> "tríceps"
        "biceps" -> "bíceps"
        "lats" -> "dorsales"
        "middle back" -> "espalda media"
        "calves" -> "pantorrillas"
        "lower back" -> "zona lumbar"
        "forearms" -> "antebrazos"
        "glutes" -> "glúteos"
        "traps" -> "trapecios"
        "adductors" -> "aductores"
        "neck" -> "cuello"
        "abductors" -> "abductores"
        else -> null
    }

    /** `_equipLabel`: "Smith" en el nombre es Multipower (free-exercise-db lo etiqueta 'machine' o 'barbell'). */
    fun etiquetaEquipo(e: EntradaCatalogoEjercicio): String {
        if (smith.prueba(e.nameEn ?: "")) return "Multipower"
        e.equipment?.let { eq -> etiquetas[eq]?.let { return it } }
        return verdadero(e.equipment) ?: "Otro"
    }

    /**
     * `a.localeCompare(b, 'es')`, el orden alfabético de los sustitutos: [ColacionEspanol], la colación de ICU en Kotlin
     * puro (`java.text.Collator` da otro orden en la JVM y depende de la versión de Android). Verificado contra node con
     * todos los nombres del catálogo (vectores `orden`).
     */
    fun compararNombres(a: String, b: String): Int = ColacionEspanol.comparar(a, b)

    // ── Tablas: copiadas literal de app.js (el orden es la prioridad) ─────────

    internal val reglas = tabla(
        "cinta.*trote|trote suave|cinta.*suave" to "Jogging_Treadmill",
        "cinta|caminadora|treadmill" to "Running_Treadmill",
        "rollout|ab wheel|rueda abdom" to "Ab_Roller",
        "crunch.*maquina|crunch en m" to "Ab_Crunch_Machine",
        "plancha|plank" to "Plank",
        "remo.*maquina palanca|palanca|leverage.*row|iso.?row" to "Leverage_Iso_Row",
        "remo.*polea.*sentad|seated cable row|remo en polea sentad" to "Seated_Cable_Rows",
        "remo.*menton|upright row" to "Upright_Cable_Row",
        "remo.*polea|cable row" to "Seated_Cable_Rows",
        "remo.*mancuern" to "Bent_Over_Two-Dumbbell_Row",
        "remo.*barra|remo con barra" to "Bent_Over_Barbell_Row",
        "jalon.*neutr|jalon.*v.?bar|agarre neutro" to "V-Bar_Pulldown",
        "jalon.*pecho|jalon.*prono|pulldown|jalon" to "Wide-Grip_Lat_Pulldown",
        "pajaro|reverse.*fly|reverse pec deck|deltoides posterior" to "Reverse_Machine_Flyes",
        "face pull" to "Face_Pull",
        "elevac.*later.*polea|elevac.*later.*cable|elevac.*later.*una mano" to "Cable_Seated_Lateral_Raise",
        "elevac.*later" to "Side_Lateral_Raise",
        "extension.*overhead.*cuerda|overhead.*cuerda|rope.*overhead" to "Cable_Rope_Overhead_Triceps_Extension",
        "extension.*overhead.*mancuern|overhead.*mancuern" to "Seated_Triceps_Press",
        "extension.*polea alta|extension.*tricep.*polea|polea alta.*tricep|extension.*barra.*tricep|extension de tricep" to "Triceps_Pushdown",
        "push.?down" to "Triceps_Pushdown",
        "patada.*tricep|tricep.*kickback" to "Tricep_Dumbbell_Kickback",
        "press cerrad.*smith|press cerrad.*multipower" to "Smith_Machine_Close-Grip_Bench_Press",
        "press cerrad|close.?grip.*bench" to "Close-Grip_Barbell_Bench_Press",
        "press.*inclin.*maquin" to "Leverage_Incline_Chest_Press",
        "press.*inclin.*mancuern" to "Incline_Dumbbell_Press",
        "press.*inclin.*smith|press.*inclin.*multipower" to "Smith_Machine_Incline_Bench_Press",
        "press.*inclin" to "Barbell_Incline_Bench_Press_-_Medium_Grip",
        "press.*plano.*maquin" to "Leverage_Chest_Press",
        "press.*plano.*mancuern" to "Dumbbell_Bench_Press",
        "press.*plano.*smith|press.*plano.*multipower" to "Smith_Machine_Bench_Press",
        "press.*plano|press banca" to "Barbell_Bench_Press_-_Medium_Grip",
        "press.*militar.*maquin|press hombros?.*maquin|press.*hombro.*maquin" to "Machine_Shoulder_Military_Press",
        "press.*mancuern.*sentad|press hombros?.*mancuern|press.*hombro.*mancuern" to "Seated_Dumbbell_Press",
        "press.*hombro|press.*militar" to "Seated_Dumbbell_Press",
        "apertur.*inclin" to "Incline_Dumbbell_Flyes",
        "cruce.*polea.*bajo|low cable cross" to "Low_Cable_Crossover",
        "apertur.*polea|cruce.*polea|crossover" to "Cable_Crossover",
        "apertur|pec deck|butterfly" to "Butterfly",
        "fondos|dips" to "Dips_-_Chest_Version",
        "curl.*predicad.*maquin|preacher.*machine" to "Machine_Preacher_Curls",
        "curl.*predicad" to "Preacher_Curl",
        "curl.*martillo|hammer" to "Hammer_Curls",
        "curl.*spider|spider" to "Spider_Curl",
        "curl.*inclin" to "Incline_Dumbbell_Curl",
        "curl.*invers|reverse.*curl|curl inverso" to "Reverse_Cable_Curl",
        "curl.*polea.*una mano|curl.*cable.*una mano|curl en cable a una mano" to "Standing_One-Arm_Cable_Curl",
        "curl.*polea|curl.*cable" to "Standing_Biceps_Cable_Curl",
        "curl.*mancuern.*sentad" to "Seated_Dumbbell_Curl",
        "curl.*mancuern" to "Dumbbell_Bicep_Curl",
        "curl.*barra" to "Barbell_Curl",
        "curl femoral.*sentad|leg curl.*sentad|femoral sentad" to "Seated_Leg_Curl",
        "curl femoral|leg curl|hamstring curl|femoral" to "Lying_Leg_Curls",
        "extension.*cuad|leg extension|cuadricep" to "Leg_Extensions",
        "prensa|leg press" to "Leg_Press",
        "hack squat|sentadilla hack|sentadilla jaca" to "Hack_Squat",
        "sentadilla.*bulgar|split squat|bulgara" to "Split_Squat_with_Dumbbells",
        "sentadilla.*smith|smith.*squat|sentadilla.*multipower" to "Smith_Machine_Squat",
        "sentadilla|squat" to "Barbell_Squat",
        "zancada|lunge|estocada" to "Dumbbell_Lunges",
        "peso muerto.*rumano|romanian|rdl.*mancuern" to "Stiff-Legged_Dumbbell_Deadlift",
        "\\brdl\\b|peso muerto.*rigid|stiff.?leg" to "Romanian_Deadlift",
        "peso muerto|deadlift" to "Barbell_Deadlift",
        "hip thrust|empuje de cadera" to "Barbell_Hip_Thrust",
        "puente.*gluteo|glute bridge" to "Barbell_Glute_Bridge",
        "patada.*gluteo|patada.*tras|kickback.*glute" to "One-Legged_Cable_Kickback",
        "abductor|abduccion" to "Thigh_Abductor",
        "aductor|aduccion" to "Thigh_Adductor",
        "soleo|talon sentad|seated calf" to "Seated_Calf_Raise",
        "talon.*multipower|talon.*smith|smith.*calf" to "Smith_Machine_Calf_Raise",
        "talon|gemelo|\\bcalf\\b|gastrocnem|pantorrilla" to "Standing_Calf_Raises",
        "encogim|shrug|trapecio" to "Dumbbell_Shrug",
        "elevac.*frontal|front raise" to "Front_Cable_Raise",
        "pullover.*mancuern" to "Straight-Arm_Dumbbell_Pullover",
        "pullover" to "Straight-Arm_Pulldown",
        "skull|press frances|french|rompecraneo" to "EZ-Bar_Skullcrusher",
        "dominad|pull.?up|pullup" to "Pullups",
        "flexion|push.?up|lagartij" to "Pushups",
    )

    internal val bases = tabla(
        "romanian deadlift" to "Peso muerto rumano",
        "stiff.?leg.*deadlift|stiff legged" to "Peso muerto piernas rígidas",
        "sumo deadlift" to "Peso muerto sumo",
        "trap bar deadlift" to "Peso muerto con trap bar",
        "deadlift" to "Peso muerto",
        "good morning" to "Buenos días",
        "leg press" to "Prensa de piernas",
        "hack squat" to "Hack squat",
        "split squat|bulgarian" to "Sentadilla búlgara",
        "front squat" to "Sentadilla frontal",
        "squat" to "Sentadilla",
        "walking lunge" to "Zancadas caminando",
        "lunge|lunges" to "Zancadas",
        "step-?up" to "Subida al cajón",
        "leg extension" to "Extensión de cuádriceps",
        "lying leg curl" to "Curl femoral acostado",
        "seated leg curl" to "Curl femoral sentado",
        "leg curl|glute ham|nordic" to "Curl femoral",
        "hip thrust" to "Hip thrust",
        "glute bridge" to "Puente de glúteos",
        // Desvío a propósito de la web (20-oct): ahí la patada de tríceps también sale «Patada de glúteo». Allá no se ve
        // (no tiene variantes); en la app sí, entre los otros ejercicios de tríceps, y es el nombre que se registra.
        "tricep.*kickback|kickback.*tricep" to "Patada de tríceps",
        "(glute|cable) kickback|kickback" to "Patada de glúteo",
        "thigh abductor|hip abduction|abductor" to "Abductores",
        "thigh adductor|hip adduction|adductor" to "Aductores",
        "seated calf raise|calf raise.*seated" to "Elevación de talones sentado",
        "calf raise|calf press|calves" to "Elevación de talones",
        "bench press" to "Press de banca",
        "chest press" to "Press de pecho",
        "shoulder press|military press" to "Press militar",
        "overhead press|push press" to "Press sobre la cabeza",
        "arnold press" to "Press Arnold",
        "floor press" to "Press en el piso",
        "\\bpress\\b" to "Press",
        "lat pulldown|pulldown|pull-down|pull down" to "Jalón al pecho",
        "chin-?up" to "Dominadas supinas",
        "pull-?up|pullup" to "Dominadas",
        "straight-?arm|pullover" to "Pullover",
        "upright row" to "Remo al mentón",
        "t-bar row" to "Remo en T",
        "\\brows?\\b" to "Remo",
        "face pull" to "Face pull",
        "rear delt|reverse fly|reverse machine fly|rear lateral" to "Pájaros",
        "lateral raise|side lateral" to "Elevaciones laterales",
        "front raise" to "Elevaciones frontales",
        "shrug" to "Encogimientos",
        "pec deck|butterfly" to "Pec deck",
        "crossover|cross over|cable cross" to "Cruce de poleas",
        "fly|flye" to "Aperturas",
        "hammer curl" to "Curl martillo",
        "preacher curl" to "Curl predicador",
        "spider curl" to "Curl araña",
        "concentration curl" to "Curl concentrado",
        "reverse curl" to "Curl invertido",
        "wrist curl" to "Curl de muñeca",
        "bicep.*curl|curl" to "Curl de bíceps",
        "pushdown|push-down|push down" to "Extensión de tríceps en polea",
        "skull|french press|nose breaker" to "Press francés",
        "overhead.*(triceps|extension)|triceps.*overhead" to "Extensión de tríceps sobre la cabeza",
        "triceps? (extension|press)|extension.*triceps" to "Extensión de tríceps",
        "dips?\\b" to "Fondos",
        "push-?up|pushup" to "Flexiones",
        "rollout|roller|ab wheel" to "Rollout",
        "plank" to "Plancha",
        "hanging.*raise|leg raise|knee raise" to "Elevación de piernas",
        "russian twist|oblique|woodchop|wood chop" to "Oblicuos",
        "crunch|sit-?up" to "Crunch",
        "hyperextension|back extension" to "Hiperextensiones",
    )

    internal val equipos = tabla(
        "\\bsmith\\b" to "en multipower",
        "leverage|lever |machine" to "en máquina",
        "cable|pulley" to "en polea",
        "e-?z[ -]?(curl )?bar" to "con barra Z",
        "dumbbell|\\bdb\\b" to "con mancuernas",
        "barbell" to "con barra",
        "kettlebell" to "con kettlebell",
        "\\bband\\b|bands" to "con banda",
        "exercise ball|ball " to "con pelota",
    )

    internal val modificadores = tabla(
        "incline" to "inclinado",
        "decline" to "declinado",
        "close-?grip" to "agarre cerrado",
        "wide-?grip" to "agarre ancho",
        "one-?arm|single-?arm|one arm" to "a una mano",
    )

    /** `eqCore` de `_toEs`: lo que tiene que aparecer en el nombre para que el equipo sea redundante. */
    private val nucleosEquipo = mapOf(
        "en polea" to "polea", "en máquina" to "máquina", "en multipower" to "multipower", "con barra" to "barra",
        "con mancuernas" to "mancuern", "con kettlebell" to "kettlebell", "con banda" to "banda", "con barra Z" to "barra z",
        "con pelota" to "pelota",
    )

    /** `EQUIP_LABEL` (free-exercise-db → castellano). */
    private val etiquetas = mapOf(
        "machine" to "Máquina", "dumbbell" to "Mancuernas", "barbell" to "Barra", "cable" to "Polea",
        "body only" to "Peso corporal", "kettlebells" to "Kettlebell", "bands" to "Banda", "e-z curl bar" to "Barra Z",
        "exercise ball" to "Pelota", "medicine ball" to "Balón medicinal", "other" to "Otro",
    )

    private val vocales = tabla(
        "[áàäâã]" to "a", "[éèëê]" to "e", "[íìïî]" to "i", "[óòöôõ]" to "o", "[úùüû]" to "u", "ñ" to "n",
    )
    private val parentesis = JsRegex("\\(.*?\\)")
    private val sufijoId = JsRegex("-d\\d+-\\d+")
    private val noAlfanumerico = JsRegex("[^a-z0-9 ]+")
    private val espacios = JsRegex("\\s+")
    private val guionBajo = JsRegex("_")

    /** `/\bsmith\b/i`: con la `i` de JS sin `u` ("ſmith" no es Smith; con UNICODE_CASE de Java lo sería). */
    private val smith = JsRegex("\\bsmith\\b", "i")
    private val imagenUrl = JsRegex("exercise-images\\/([^/]+)\\/")

    /** `…/exercise-images/<SLUG>/<0|1>.jpg` → SLUG (`exec` de JS: la primera aparición, aunque no esté en el catálogo). */
    internal fun slugDeUrl(url: String): String? = imagenUrl.primera(url)?.get(1)

    /** Una lista `[[/regex/, valor], …]` de app.js, en el mismo orden. */
    private fun tabla(vararg pares: Pair<String, String>): List<Pair<JsRegex, String>> = pares.map { JsRegex(it.first) to it.second }
}

/** Lo que mira `_resolve` de un ejercicio: el que viene en el plan, o el `orig` que arma `exGetSubs`. */
data class ReferenciaEjercicio(
    val nombre: String? = null,
    val imagenes: Imagenes? = null,
    val catalogoSlug: String? = null,
    /** `_matched_slug` suelto. El `orig` de `exGetSubs` no lo trae. */
    val matchedSlug: String? = null,
) {
    /** El ejercicio del plan tal cual (lo que recibe `_resolve` desde `getEffectiveEx`). */
    constructor(ex: Ejercicio) : this(ex.nombre, ex.imagenes, ex.catalogoSlug, ex.matchedSlug)
}

/** Un sustituto válido, con los campos del objeto que arma `findSubstitutes`. */
data class SustitutoEjercicio(
    /** `slug` (el `slug_en` de la fila). */
    val slug: String?,
    /** `name`: el nombre en castellano (`_toEs`). Es el que se muestra y el que se registra al sustituir. */
    val nombre: String,
    /** `name_en` */
    val nombreIngles: String?,
    /** `equipo`: la etiqueta ("Máquina", "Multipower"…). */
    val equipo: String,
    /** `equipmentRaw`: el `equipment` del catálogo. */
    val equipoCrudo: String?,
    /** `primary_muscle` */
    val musculo: String?,
    /** `patron_movimiento` */
    val patron: String?,
    /** `images`: las del catálogo, con "" como null. Sin `_matched_slug`. */
    val imagenes: Imagenes,
    /** `_sameEquip`: mismo equipo que el original (van al final). */
    val mismoEquipo: Boolean,
) {
    /**
     * Lo que lo identifica aunque la lista cambie: el slug del catálogo; sin slug, el nombre con el equipo. La hoja de
     * "Sustituir" elige por esto y no por la posición: si mientras está abierta llega el catálogo del servidor, la lista
     * cambia de orden y la misma posición es otro ejercicio (revisión del 15-oct, hallazgo 13).
     */
    val clave: String get() = slug?.takeIf { it.isNotEmpty() } ?: "$nombre|${equipoCrudo ?: equipo}"

    internal constructor(e: EntradaCatalogoEjercicio, mismoEquipo: Boolean) : this(
        slug = e.slugEn,
        nombre = SustitucionEjercicios.castellano(e),
        nombreIngles = e.nameEn,
        equipo = SustitucionEjercicios.etiquetaEquipo(e),
        equipoCrudo = e.equipment,
        musculo = e.primaryMuscle,
        patron = e.patronMovimiento,
        imagenes = Imagenes(eccentric = verdadero(e.imageEccentric), concentric = verdadero(e.imageConcentric)),
        mismoEquipo = mismoEquipo,
    )
}

/**
 * La sustitución aplicada en un lugar (`STATE.exerciseSwaps[ex.id]`): el `current` que guarda `confirmExSwap`, y si
 * quedó fijada para las próximas semanas.
 */
data class SustitucionAplicada(
    val slug: String?,
    val nombre: String,
    /** `equipment` crudo del catálogo. */
    val equipo: String? = null,
    val imagenes: Imagenes? = null,
    val fijado: Boolean,
) {
    /** Lo que guarda `confirmExSwap` al elegir un sustituto. */
    constructor(s: SustitutoEjercicio, fijado: Boolean) : this(s.slug, s.nombre, s.equipoCrudo, s.imagenes, fijado)
}

/**
 * `getEffectiveEx`: el ejercicio que se muestra. Nombre e imágenes son los del sustituto si hay, o las fotos del
 * catálogo si el plan no las trae; id, tipo, descanso y progresión son siempre los del lugar. Guarda referencias al
 * original (`_orig*`) para ofrecer sustitutos sobre él y para volver.
 */
data class EjercicioEfectivo(
    val ejercicio: Ejercicio,
    /** `_isSwapped` */
    val sustituido: Boolean = false,
    /** `_swapSlug` */
    val slugSustituto: String? = null,
    /** `_swapFijado` */
    val fijado: Boolean = false,
    /** `_origNombre` */
    val nombreOriginal: String? = null,
    /** `_origImages` */
    val imagenesOriginales: Imagenes? = null,
    /** `_origSlug` */
    val slugOriginal: String? = null,
)

/**
 * El catálogo en memoria (`window.MYPUMP_EJERCICIO_DB`).
 *
 * El ORDEN de las filas es parte de la entrada, como en la web: de cada nombre+equipo repetido queda la primera fila,
 * los empates de nombre quedan en el orden del catálogo, y un alias genérico ("abdominales", "core") se resuelve a la
 * primera fila que lo tenga. La web usa el orden en que responde el servidor (el GET no tiene ORDER BY); el archivo
 * empaquetado va por `slug_en`, y con ese orden cambian unas 200 de las 873 listas. El catálogo bajado se usa tal cual
 * llega.
 */
class CatalogoEjercicios(val entradas: List<EntradaCatalogoEjercicio>) {
    /** `byId`: si un slug se repite, gana la última fila. */
    private val indice: Map<String, Int> = HashMap<String, Int>().apply {
        entradas.forEachIndexed { i, e -> e.slugEn?.let { put(it, i) } }
    }

    fun entrada(slug: String): EntradaCatalogoEjercicio? = indice[slug]?.let { entradas[it] }

    /**
     * El músculo de cada patrón de movimiento: el de la mayoría de sus filas (en un empate, el que aparece primero). Para
     * «otros del mismo músculo»: una fila mal clasificada (encogimientos como espalda media) no se ofrece, porque su patrón
     * es de otro músculo.
     */
    private val musculoDelPatron: Map<String, String> = run {
        val cuentas = LinkedHashMap<String, MutableList<Pair<String, Int>>>()
        for (e in entradas) {
            val p = verdadero(e.patronMovimiento) ?: continue
            val m = verdadero(e.primaryMuscle) ?: continue
            val lista = cuentas.getOrPut(p) { mutableListOf() }
            val i = lista.indexOfFirst { it.first == m }
            if (i >= 0) lista[i] = lista[i].first to lista[i].second + 1 else lista += m to 1
        }
        cuentas.mapValues { (_, l) -> l.reduce { mejor, x -> if (x.second > mejor.second) x else mejor }.first }
    }

    /** El músculo de un patrón (el de la mayoría de sus filas). */
    fun musculoDePatron(p: String?): String? = verdadero(p)?.let { musculoDelPatron[it] }

    /**
     * El músculo y el patrón de cada fila, y el patrón que nombra, por la clave del historial ([ClaveEjercicio]) de su nombre
     * en castellano, que es lo que de verdad comparten dos ejercicios con nombres parecidos. Para no ofrecer entre «otros del
     * mismo músculo» el nombre de otro ejercicio (ver [nombreDeOtroEjercicio]). Se arma una vez, la primera vez que hace
     * falta: traducir las 873 filas lleva su tiempo, y el catálogo empaquetado se arma al abrir la app.
     */
    private val usosDelNombre: Map<String, UsosDeUnNombre> by lazy {
        val filas = HashMap<String, MutableList<Pair<String?, String?>>>()
        for (e in entradas) {
            filas.getOrPut(ClaveEjercicio.de(SustitucionEjercicios.castellano(e))) { mutableListOf() } += verdadero(e.primaryMuscle) to verdadero(e.patronMovimiento)
        }
        filas.mapValues { UsosDeUnNombre(it.value) }
    }

    /**
     * El nombre del candidato es, en el catálogo, el de OTRO ejercicio de otro músculo, y compartiría con él el historial (que
     * va por la clave del nombre). Cuenta si hay filas con ese nombre de otro músculo y otro patrón, y el candidato no es del
     * patrón que tiene la mayoría de las filas con ese nombre: el movimiento que el nombre nombra (con un empate, no nombra a
     * ninguno). Revisión del 21-oct: salen los remos del deltoide posterior de los otros de hombros («Remo con barra», «Remo
     * en polea»: los nombres son de los remos de espalda) y «Curl de bíceps · Otro» (un curl invertido con disco). Se quedan
     * los que son el mismo ejercicio cargado también en otro músculo (los fondos, la sentadilla búlgara, las zancadas) o que
     * chocan con la traducción equivocada de otro que la app no ofrece (el cruce de poleas). Igual que en iOS.
     */
    internal fun nombreDeOtroEjercicio(s: SustitutoEjercicio): Boolean {
        val usos = usosDelNombre[ClaveEjercicio.de(s.nombre)] ?: return false
        val deOtroMusculo = usos.filas.any { (m, p) -> m != verdadero(s.musculo) && p != verdadero(s.patron) }
        return deOtroMusculo && usos.dominante != verdadero(s.patron)
    }

    /** `_resolve`: slug explícito → slug de la URL de la imagen → reglas por nombre → nombre normalizado o alias exactos. */
    fun resolver(r: ReferenciaEjercicio): EntradaCatalogoEjercicio? {
        if (entradas.isEmpty()) return null
        // 1) Slug explícito. Si el primero que hay no está en el catálogo, NO se prueba el siguiente.
        val slug = verdadero(r.catalogoSlug) ?: verdadero(r.imagenes?.matchedSlug) ?: verdadero(r.matchedSlug)
        if (slug != null) entrada(slug)?.let { return it }
        // 2) Slug embebido en la URL de la imagen.
        val url = verdadero(r.imagenes?.eccentric) ?: verdadero(r.imagenes?.concentric) ?: ""
        SustitucionEjercicios.slugDeUrl(url)?.let { s -> entrada(s)?.let { return it } }
        // 3) Reglas castellano → slug (gesto exacto). Sin trigram: matchea "pullover" con "crunch".
        val nombre = verdadero(r.nombre) ?: ""
        SustitucionEjercicios.slugPorReglas(nombre)?.let { s -> entrada(s)?.let { return it } }
        // 4) Nombre normalizado o alias, exactos y en el orden del catálogo.
        val nn = SustitucionEjercicios.normalizar(nombre)
        if (nn.isEmpty()) return null
        return entradas.firstOrNull { it.nameNormalized == nn } ?: entradas.firstOrNull { e -> e.aliasesEs?.contains(nn) == true }
    }

    fun resolver(ex: Ejercicio): EntradaCatalogoEjercicio? = resolver(ReferenciaEjercicio(ex))

    /** `findSubstitutes`: mismo patrón y mismo músculo, otro equipo primero, alfabético, sin repetir nombre+equipo, 30. */
    fun sustitutos(r: ReferenciaEjercicio): List<SustitutoEjercicio> {
        val original = resolver(r) ?: return emptyList()
        val patron = verdadero(original.patronMovimiento) ?: return emptyList()
        val candidatos = entradas
            .filter { it.patronMovimiento == patron && it.primaryMuscle == original.primaryMuscle && it.slugEn != original.slugEn }
            .map { SustitutoEjercicio(it, mismoEquipo = it.equipment == original.equipment) }
        // El sort de JS es estable: lo que empata queda en el orden del catálogo. La clave de colación de cada nombre se
        // calcula una vez y no en cada comparación.
        val claves = candidatos.map { ColacionEspanol.clave(it.nombre) }
        val ordenados = SemanticaJs.ordenarEstable(candidatos.indices.toList()) { i, j ->
            val a = candidatos[i]
            val b = candidatos[j]
            if (a.mismoEquipo != b.mismoEquipo) (if (a.mismoEquipo) 1 else -1) else claves[i].compareTo(claves[j])
        }.map { candidatos[it] }
        val vistos = HashSet<Pair<String, String>>()
        return ordenados.filter { vistos.add(it.nombre to it.equipo) }.take(30)
    }

    /**
     * Los otros ejercicios del mismo músculo, con otro movimiento (Mati, 20-oct: con la polea ocupada, a una extensión en
     * polea no le quedaba nada; Eric quería fondos). Es de la app, no de la web: van en su propia sección, debajo de las
     * variantes del mismo movimiento y sin repetirlas. Solo filas con su patrón (las sin clasificar no se ofrecen) y con un
     * patrón de ESE músculo (el de la mayoría de sus filas: así los encogimientos mal cargados como espalda media no
     * aparecen para un remo), sin nombres que no se tradujeron ni el «Press» suelto, ni el nombre de otro ejercicio
     * ([nombreDeOtroEjercicio]), otro equipo primero, alfabético, sin repetir nombre+equipo, 30. Igual que en iOS.
     */
    fun otrosDelMismoMusculo(r: ReferenciaEjercicio): List<SustitutoEjercicio> {
        val original = resolver(r) ?: return emptyList()
        val patron = verdadero(original.patronMovimiento) ?: return emptyList()
        val musculo = verdadero(original.primaryMuscle) ?: return emptyList()
        val deArriba = sustitutos(r).map { it.nombre to it.equipo }
        val propio = SustitucionEjercicios.castellano(original) to SustitucionEjercicios.etiquetaEquipo(original)
        val candidatos = entradas
            .filter {
                it.primaryMuscle == musculo && verdadero(it.patronMovimiento) != null && it.patronMovimiento != patron &&
                    it.slugEn != original.slugEn && musculoDePatron(it.patronMovimiento) == musculo
            }
            .map { SustitutoEjercicio(it, mismoEquipo = it.equipment == original.equipment) }
            .filter { it.nombre.isNotEmpty() && it.nombre != "Press" && it.nombre != it.nombreIngles && !nombreDeOtroEjercicio(it) }
        val claves = candidatos.map { ColacionEspanol.clave(it.nombre) }
        val ordenados = SemanticaJs.ordenarEstable(candidatos.indices.toList()) { i, j ->
            val a = candidatos[i]
            val b = candidatos[j]
            if (a.mismoEquipo != b.mismoEquipo) (if (a.mismoEquipo) 1 else -1) else claves[i].compareTo(claves[j])
        }.map { candidatos[it] }
        val vistos = HashSet(deArriba).apply { add(propio) }
        return ordenados.filter { vistos.add(it.nombre to it.equipo) }.take(30)
    }

    /** Los otros del mismo músculo para la tarjeta, resueltos sobre el original (como [sustitutos]). */
    fun otrosDelMismoMusculo(ef: EjercicioEfectivo): List<SustitutoEjercicio> {
        if (ef.ejercicio.tipo == "calentamiento" || ef.ejercicio.tipo == "cardio") return emptyList()
        return otrosDelMismoMusculo(referenciaDeLasListas(ef))
    }

    /** `getEffectiveEx(ex)` con `STATE.exerciseSwaps[ex.id]` = [sustitucion]. */
    fun efectivo(ex: Ejercicio, sustitucion: SustitucionAplicada?): EjercicioEfectivo {
        var ef = ex
        if (sustitucion != null) {
            // Desvío a propósito de la web (27-oct): el equipo del sustituto decide el kg cuando el nombre traducido lo
            // pierde («Rope Crunch» sale «Crunch»). Ver `ReglasEjercicio.esSinPeso`.
            ef = ef.copy(nombre = sustitucion.nombre, imagenes = sustitucion.imagenes, equipo = sustitucion.equipo)
        } else if (verdadero(ex.imagenes?.eccentric) == null) {
            // El plan no trae foto (ejercicio creado en NutriPlan sin match): sale del catálogo, sin republicar.
            val e = resolver(ex)
            if (e != null && verdadero(e.imageEccentric) != null) {
                ef = ef.copy(imagenes = Imagenes(eccentric = e.imageEccentric, concentric = e.imageConcentric, matchedSlug = e.slugEn))
            }
        }
        return EjercicioEfectivo(
            ejercicio = ef,
            sustituido = sustitucion != null,
            slugSustituto = sustitucion?.slug,
            fijado = sustitucion?.fijado ?: false,
            nombreOriginal = ex.nombre,
            imagenesOriginales = ex.imagenes,
            slugOriginal = verdadero(ex.imagenes?.matchedSlug) ?: verdadero(ex.catalogoSlug) ?: verdadero(ef.imagenes?.matchedSlug),
        )
    }

    /** `exGetSubs`: los sustitutos que ofrece la tarjeta, resueltos sobre el original. Ni calentamiento ni cardio. */
    fun sustitutos(ef: EjercicioEfectivo): List<SustitutoEjercicio> {
        if (ef.ejercicio.tipo == "calentamiento" || ef.ejercicio.tipo == "cardio") return emptyList()
        return sustitutos(referenciaDeLasListas(ef))
    }

    /**
     * Sobre qué se arman las dos listas de «Sustituir»: el `orig` de `exGetSubs` ([referencia]) y, con el lugar sustituido,
     * el del original tal como estaba antes de sustituir (su nombre, su slug y sus fotos o las del catálogo), así al reabrir
     * «Cambiar» las listas son las mismas. Desvío a propósito de la web (revisión del 21-oct): con un plan sin fotos (la demo,
     * que es la que mira Apple, o la cuenta test-nativa-ios) `_origImages || images` caía en la foto del sustituto, y después
     * de pasar la extensión en polea a fondos las listas eran las de los fondos. Igual que en iOS.
     */
    fun referenciaDeLasListas(ef: EjercicioEfectivo): ReferenciaEjercicio {
        if (!ef.sustituido) return referencia(ef)
        // El del plan con el nombre y las fotos del sustituto: se le devuelven los suyos.
        val plan = ef.ejercicio.copy(nombre = ef.nombreOriginal ?: "", imagenes = ef.imagenesOriginales)
        return referencia(efectivo(plan, null))
    }

    companion object {
        /** El JSON del GET (o del archivo empaquetado), en el orden en que viene. */
        fun desde(json: String): CatalogoEjercicios = CatalogoEjercicios(listaEstricta(json, EntradaCatalogoEjercicio::desde))

        /**
         * El `orig` de `exGetSubs`: `{nombre: _origNombre || nombre, images: _origImages || images,
         * catalogo_slug: _origSlug || images?._matched_slug || null}`.
         */
        fun referencia(ef: EjercicioEfectivo): ReferenciaEjercicio = ReferenciaEjercicio(
            nombre = verdadero(ef.nombreOriginal) ?: ef.ejercicio.nombre,
            imagenes = ef.imagenesOriginales ?: ef.ejercicio.imagenes,
            catalogoSlug = verdadero(ef.slugOriginal) ?: verdadero(ef.ejercicio.imagenes?.matchedSlug),
        )
    }
}

/**
 * Las filas del catálogo con un mismo nombre (su clave del historial): el músculo y el patrón de cada una, y el patrón de la
 * mayoría de las que tienen patrón, que es el movimiento que el nombre nombra (null sin patrones o con un empate).
 */
private class UsosDeUnNombre(val filas: List<Pair<String?, String?>>) {
    val dominante: String? = run {
        val cuentas = filas.mapNotNull { it.second }.groupingBy { it }.eachCount()
        val maximo = cuentas.values.maxOrNull()
        cuentas.filterValues { it == maximo }.keys.singleOrNull()
    }
}

/** Un texto en un `||` de JS: null y "" son falsos. */
private fun verdadero(s: String?): String? = s?.takeIf { it.isNotEmpty() }
