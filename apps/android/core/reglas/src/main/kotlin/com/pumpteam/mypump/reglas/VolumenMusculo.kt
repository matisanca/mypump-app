package com.pumpteam.mypump.reglas

/**
 * Volumen por músculo (2.1, S2): las series efectivas de cada músculo en la semana (de lunes a domingo, como el check),
 * con la semana pasada al lado y lo de hoy aparte (el cierre del día). Gemelo de VolumenMusculo.swift; lo verifican los
 * vectores de `apps/shared/vectores/volumen.json`.
 *
 * - Cuenta cada serie registrada (una fila del historial o una serie confirmada hoy). Las de preparación nunca se
 *   registran, así que no cuentan; tampoco el cardio ni el calentamiento ([TIPOS_QUE_NO_CUENTAN]).
 * - El músculo es el principal del catálogo del ejercicio que se hizo, con la misma cadena que la preparación (E1): el
 *   del sustituto si el catálogo lo tiene y si no `CatalogoEjercicios.resolver` (catalogo_slug → matched → reglas y
 *   nombre). Sin músculo, o uno que no está en [orden], va a «Sin músculo asignado» (el respaldo conservador: no se
 *   inventa un músculo) y queda al final.
 * - Cada fila del historial cuenta (el servidor guarda una por sesión, ejercicio y número: dos rutinas el mismo día con
 *   el mismo ejercicio son filas distintas). Lo confirmado en el teléfono (`enVivo`) va con la fecha REAL de cada serie
 *   (la del toque, o el `registrado_en` si vino del servidor), no con la de hoy: una sesión de otro día mirada hoy no
 *   cuenta como hoy. En vivo, una misma serie (lugar + fecha + número) cuenta una vez, y una que ya está en el historial
 *   (misma clave del ejercicio, fecha y número; cada fila del historial cubre a una sola) no se suma: el historial puede
 *   estar viejo y lo en vivo completa solo lo que le falta, por ejercicio (revisión del 3-nov: antes lo en vivo
 *   reemplazaba TODO el historial de hoy, y contaba dos veces o borraba otra rutina del mismo día). Una fecha que no sea
 *   YYYY-MM-DD exacto no cuenta.
 * - Orden: más series esta semana, después más la semana pasada, después el orden del catálogo ([orden]).
 */
object VolumenMusculo {
    val TIPOS_QUE_NO_CUENTAN = setOf("cardio", "calentamiento")
    val orden = listOf(
        "quadriceps", "shoulders", "abdominals", "chest", "hamstrings", "triceps", "biceps", "lats",
        "middle back", "calves", "lower back", "forearms", "glutes", "traps", "adductors", "neck", "abductors",
    )
    const val SIN_MUSCULO = "Sin músculo asignado"

    /** Una serie registrada. `musculo` null = el catálogo no lo tiene; `fecha` local YYYY-MM-DD. */
    data class Registro(
        val musculo: String?,
        val tipo: String?,
        val fecha: String,
        val lugar: String,
        val serie: Int?,
        /** La clave del ejercicio ([ClaveEjercicio]) con la que se cruza lo en vivo con el historial; null = `lugar`. */
        val clave: String? = null,
    )

    data class Fila(val musculo: String?, val nombre: String, val semana: Int, val anterior: Int, val hoy: Int) {
        val id: String get() = musculo ?: "-"

        /** «Pecho, 12 series esta semana, 10 la semana pasada». */
        val textoAccesible: String get() = "$nombre, ${series(semana)} esta semana, $anterior la semana pasada"
    }

    data class Resumen(val semana: String, val filas: List<Fila>, val total: Int, val totalAnterior: Int, val totalHoy: Int) {
        /** Lo de hoy (el cierre del día): los músculos con series hoy, más series primero. */
        val filasDeHoy: List<Fila> get() = filas.filter { it.hoy > 0 }.sortedByDescending { it.hoy }

        /** El máximo de series de un músculo en las dos semanas (la escala de las barras). */
        val tope: Int get() = filas.maxOfOrNull { maxOf(it.semana, it.anterior) } ?: 0
    }

    /** «1 serie», «12 series». */
    fun series(n: Int): String = if (n == 1) "1 serie" else "$n series"

    /** El músculo normalizado si es uno del catálogo; null si no. */
    fun normalizar(m: String?): String? = m?.trim()?.lowercase()?.takeIf { it in orden }

    /** «Pecho», «Espalda media»; sin músculo, «Sin músculo asignado». */
    fun nombre(m: String?): String {
        val n = SustitucionEjercicios.musculo(normalizar(m)) ?: return SIN_MUSCULO
        return n.substring(0, 1).uppercase() + n.substring(1)
    }

    fun calcular(historial: List<Registro>, enVivo: List<Registro> = emptyList(), hoy: String): Resumen {
        val lunes = FotosProgreso.lunes(hoy)
        val anterior = DiaCalendario.numero(lunes)?.let { DiaCalendario.texto(it - 7) } ?: ""
        fun valida(r: Registro) = r.fecha.length == 10 && DiaCalendario.numero(r.fecha) != null
        fun cruce(r: Registro, s: Int) = "${r.clave ?: r.lugar}|${r.fecha}|$s"
        // Lo que ya está en el historial, para no sumarlo de nuevo en vivo: cada fila cubre a una sola serie en vivo.
        val cubiertas = HashMap<String, Int>()
        for (r in historial) if (valida(r) && r.serie != null) cubiertas.merge(cruce(r, r.serie), 1, Int::plus)
        val regs = ArrayList(historial)
        val vistos = HashSet<String>()
        for (r in enVivo) {
            if (!valida(r)) continue
            val s = r.serie
            if (s == null) { regs += r; continue }
            if (!vistos.add("${r.lugar}|${r.fecha}|$s")) continue
            val k = cruce(r, s)
            val n = cubiertas[k] ?: 0
            if (n > 0) { cubiertas[k] = n - 1; continue }
            regs += r
        }
        // Por músculo ("" = sin músculo): semana, anterior, hoy. LinkedHashMap: el orden de llegada no importa (se ordena).
        val cuenta = LinkedHashMap<String, IntArray>()
        for (r in regs) {
            if (r.tipo != null && r.tipo in TIPOS_QUE_NO_CUENTAN) continue
            if (!valida(r)) continue
            val semanaDe = FotosProgreso.lunes(r.fecha)
            val clave = normalizar(r.musculo) ?: ""
            val c = cuenta[clave] ?: IntArray(3)
            when (semanaDe) {
                lunes -> {
                    c[0]++
                    if (r.fecha == hoy) c[2]++
                }
                anterior -> c[1]++
                else -> continue
            }
            cuenta[clave] = c
        }
        fun rango(m: String) = if (m.isEmpty()) orden.size else orden.indexOf(m).let { if (it < 0) orden.size else it }
        val filas = cuenta.entries
            .sortedWith(compareByDescending<Map.Entry<String, IntArray>> { it.value[0] }.thenByDescending { it.value[1] }.thenBy { rango(it.key) })
            .map { (k, v) -> Fila(k.ifEmpty { null }, nombre(k.ifEmpty { null }), v[0], v[1], v[2]) }
        // Sin músculo, siempre al final.
        val ordenadas = filas.filter { it.musculo != null } + filas.filter { it.musculo == null }
        return Resumen(lunes, ordenadas, ordenadas.sumOf { it.semana }, ordenadas.sumOf { it.anterior }, ordenadas.sumOf { it.hoy })
    }
}
