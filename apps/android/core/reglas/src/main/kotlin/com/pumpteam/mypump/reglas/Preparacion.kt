package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Aproximacion
import java.text.Normalizer
import kotlin.math.floor

/**
 * E1 (2.0.3, gemelo de Preparacion.swift): el calentamiento y las aproximaciones antes de las series efectivas. Es una
 * indicación, no se registra. Los números viven acá (y en Swift) y los verifican los vectores de
 * `apps/shared/vectores/preparacion.json`.
 *
 * - PRINCIPAL = todo compuesto menos la lista de accesorios ([palabrasAccesorio]); ACCESORIO = lo demás que cuenta.
 * - Primer principal de su músculo: calentamiento 16-20 liviano, dos aproximaciones de 5 al 60 y al 85 % y la
 *   potenciación opcional. Los principales siguientes del mismo músculo: una de 5 al 75 %.
 * - Primer accesorio de su músculo: una de 5-6 al 60 %. Los demás accesorios, nada.
 * - Sin músculo: el principal lleva calentamiento solo si es el primero de fuerza del día, y dos aproximaciones.
 * - Sin preparación: cardio, core, calentamiento, sin peso y los de potencia o isométricos ([palabrasSinPreparacion]).
 * - `aproximaciones` en el plan gana (`[]` = nada). El kg sale del de la primera efectiva (o el sugerido), redondeado
 *   por equipo: barra de a 2,5 y nunca menos que la barra; mancuernas de a 1 hasta 10 y de a 2 desde ahí; máquina de a 5.
 */
object Preparacion {
    const val DESCANSO_SEGUNDOS = 30
    const val PCT_CALENTAMIENTO = 25.0
    val pctAproximaciones = listOf(60.0, 85.0)
    const val PCT_SIGUIENTE_PRINCIPAL = 75.0
    const val PCT_ACCESORIO = 60.0
    const val REPS_CALENTAMIENTO = "16-20"
    const val REPS_APROXIMACION = "5"
    const val REPS_ACCESORIO = "5-6"
    const val REPS_POTENCIACION = "1-3"
    const val POTENCIACION_KG = 5.0
    const val POTENCIACION_KG_LIVIANO = 2.5
    const val POTENCIACION_LIMITE_LIVIANO = 50.0
    const val POTENCIACION_TOPE = 10.0
    const val KG_BARRA = 20.0
    const val PASO = 2.5
    const val PASO_MAQUINA = 5.0
    const val PASO_MANCUERNA_LIVIANA = 1.0
    const val PASO_MANCUERNA_PESADA = 2.0
    const val LIMITE_MANCUERNA_LIVIANA = 10.0

    private val barraRE = JsRegex("""\bbarra\b""")
    private val noBarraLibreRE = JsRegex("""polea|cable|jalon|maquina|smith|multipower|dominada|mancuerna|barra\s*(z|ez)\b""")
    private val mancuernaRE = JsRegex("""mancuerna""")
    private val maquinaRE = JsRegex("""maquina|polea|cable|prensa|smith|multipower|jalon|hack|pec\s*deck|contractora""")

    val palabrasAccesorio = listOf(
        "remo al menton", "unilateral", "a una mano", "a un brazo", "a una pierna", "bulgara", "zancada", "estocada",
        "press cerrado", "agarre cerrado", "fondos en maquina", """pull[\s-]*through""", "subida al cajon", """\bstep\b""", "goblet",
    )
    val palabrasSinPreparacion = listOf(
        "salto al cajon", "box jump", "swing", "turkish", """get[\s-]*up""", "power clean", "cargada", "farmer", "granjero",
        "monster walk", "rollout", "isometric",
    )
    private val accesorioRE = JsRegex(palabrasAccesorio.joinToString("|"))
    private val sinPreparacionRE = JsRegex(palabrasSinPreparacion.joinToString("|"))

    enum class Equipo { BARRA, MANCUERNA, MAQUINA, OTRO }

    enum class Tipo(val valor: String) { CALENTAMIENTO("calentamiento"), APROXIMACION("aproximacion"), POTENCIACION("potenciacion") }

    /** Un ejercicio del día visto por la regla: el tipo del plan, el músculo del catálogo (null = no está) y el nombre. */
    data class Entrada(val tipo: String?, val musculo: String?, val nombre: String, val sinPeso: Boolean) {
        val cuenta: Boolean get() = (compuesto(tipo) || monoarticular(tipo)) && !sinPeso && !sinPreparacion(nombre)
        val principal: Boolean get() = esPrincipal(nombre, tipo)
        val grupo: String? get() = musculo?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
    }

    data class Serie(
        val tipo: Tipo,
        val numero: Int? = null,
        val reps: String,
        val kg: Double? = null,
        val barraSola: Boolean = false,
        val opcional: Boolean = false,
        val nota: String? = null,
    ) {
        val etiqueta: String get() = when (tipo) {
            Tipo.CALENTAMIENTO -> "Calentamiento"
            Tipo.APROXIMACION -> numero?.let { "Aproximación $it" } ?: "Aproximación"
            Tipo.POTENCIACION -> "Potenciación (opcional)"
        }

        /** "Barra sola", "22,5" o null (sin kg de referencia). */
        val textoKg: String? get() = if (barraSola) "Barra sola" else kg?.let { Js.texto(it).replace('.', ',') }
    }

    private fun compuesto(tipo: String?) = tipo == "compuesto"
    private fun monoarticular(tipo: String?) = tipo == "aislamiento" || tipo == "aislado"

    internal fun normal(s: String): String =
        Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()

    fun esPrincipal(nombre: String, tipo: String?): Boolean = compuesto(tipo) && !accesorioRE.prueba(normal(nombre))

    fun sinPreparacion(nombre: String): Boolean = sinPreparacionRE.prueba(normal(nombre))

    fun esBarra(nombre: String, equipo: String?): Boolean {
        if (equipo?.trim()?.lowercase() == "barbell") return true
        val n = normal(nombre)
        return barraRE.prueba(n) && !noBarraLibreRE.prueba(n)
    }

    fun equipo(nombre: String, equipo: String?): Equipo {
        val e = equipo?.trim()?.lowercase() ?: ""
        val n = normal(nombre)
        if (e == "dumbbell" || mancuernaRE.prueba(n)) return Equipo.MANCUERNA
        if (esBarra(nombre, equipo)) return Equipo.BARRA
        if (e == "machine" || e == "cable" || maquinaRE.prueba(n)) return Equipo.MAQUINA
        return Equipo.OTRO
    }

    /** Al paso del equipo, la mitad hacia arriba; la barra nunca menos que la barra; 0 = sin número. */
    fun redondear(kg: Double, equipo: Equipo): Double? {
        val p = when (equipo) {
            Equipo.MANCUERNA -> if (kg < LIMITE_MANCUERNA_LIVIANA) PASO_MANCUERNA_LIVIANA else PASO_MANCUERNA_PESADA
            Equipo.MAQUINA -> PASO_MAQUINA
            Equipo.BARRA, Equipo.OTRO -> PASO
        }
        val r = floor(kg / p + 0.5 + 1e-9) * p
        if (equipo == Equipo.BARRA) return maxOf(KG_BARRA, r)
        return if (r > 0) r else null
    }

    /** Es el primero de su músculo y su clase (principal o accesorio) en el orden del día, sustitutos incluidos. */
    fun primero(dia: List<Entrada>, indice: Int): Boolean {
        val e = dia.getOrNull(indice)?.takeIf { it.cuenta } ?: return false
        val g = e.grupo ?: return e.principal && dia.indexOfFirst { it.cuenta } == indice
        return dia.indexOfFirst { it.cuenta && it.grupo == g && it.principal == e.principal } == indice
    }

    fun series(
        dia: List<Entrada>,
        indice: Int,
        nombre: String,
        equipo: String?,
        sinKg: Boolean,
        kgEfectivo: Double?,
        plan: List<Aproximacion>?,
    ): List<Serie> {
        if (indice < 0 || indice >= dia.size) return emptyList()
        val ref = if (sinKg) null else kgEfectivo?.takeIf { it > 0 && it.isFinite() }
        val eq = equipo(nombre, equipo)
        fun kg(pct: Double): Pair<Double?, Boolean> {
            val k = ref?.let { redondear(it * pct / 100, eq) } ?: return null to false
            return k to (eq == Equipo.BARRA && k <= KG_BARRA)
        }
        if (plan != null) {
            val n = plan.size
            return plan.mapIndexed { i, a ->
                val (k, sola) = when {
                    sinKg -> null to false
                    a.kg != null -> a.kg to false
                    a.pct != null -> kg(a.pct!!)
                    else -> null to false
                }
                Serie(Tipo.APROXIMACION, if (n > 1) i + 1 else null, a.reps ?: "–", k, sola, nota = a.nota)
            }
        }
        val e = dia[indice]
        if (!e.cuenta || sinKg) return emptyList()
        val esPrimero = primero(dia, indice)
        if (!e.principal) {
            if (!esPrimero) return emptyList()
            val (k, sola) = kg(PCT_ACCESORIO)
            return listOf(Serie(Tipo.APROXIMACION, reps = REPS_ACCESORIO, kg = k, barraSola = sola))
        }
        val aproximaciones = pctAproximaciones.mapIndexed { i, p ->
            val (k, sola) = kg(p)
            Serie(Tipo.APROXIMACION, i + 1, REPS_APROXIMACION, k, sola)
        }
        // Principal sin músculo: el respaldo conservador (calentamiento solo si es el primero de fuerza, dos aproximaciones).
        if (e.grupo == null) {
            val s = mutableListOf<Serie>()
            if (esPrimero) {
                val (k, sola) = kg(PCT_CALENTAMIENTO)
                s += Serie(Tipo.CALENTAMIENTO, reps = REPS_CALENTAMIENTO, kg = k, barraSola = sola)
            }
            return s + aproximaciones
        }
        if (!esPrimero) {
            val (k, sola) = kg(PCT_SIGUIENTE_PRINCIPAL)
            return listOf(Serie(Tipo.APROXIMACION, reps = REPS_APROXIMACION, kg = k, barraSola = sola))
        }
        val (kc, solac) = kg(PCT_CALENTAMIENTO)
        val kp = ref?.let {
            val suma = minOf(POTENCIACION_TOPE, if (it < POTENCIACION_LIMITE_LIVIANO) POTENCIACION_KG_LIVIANO else POTENCIACION_KG)
            redondear(it + suma, eq)
        }
        return listOf(Serie(Tipo.CALENTAMIENTO, reps = REPS_CALENTAMIENTO, kg = kc, barraSola = solac)) + aproximaciones +
            Serie(Tipo.POTENCIACION, reps = REPS_POTENCIACION, kg = kp, opcional = true)
    }

    /** El kg de referencia: el escrito en la primera efectiva o, si no hay, el sugerido. */
    fun kgEfectivo(escrito: String, sugerido: String): Double? {
        val t = escrito.ifEmpty { sugerido }
        return Js.parseFloat(Verosimilitud.primeraComaAPunto(t))?.takeIf { it > 0 && it.isFinite() }
    }

    fun claveTildes(fecha: String, dia: String, lugar: String): String = "$fecha|$dia|$lugar"
}
