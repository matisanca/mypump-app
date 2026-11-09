package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.ValorJson
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

// La carga única por ejercicio (2.3.0, aprobada por Mati el 9-nov; gemelo de CargaSimple.swift). La carga se elige una vez y
// vale para todas las series que faltan; abajo queda fija la serie que toca. Las reglas son puras y las verifican los mismos
// vectores que iOS (`apps/shared/vectores/carga_simple.json`). Sale a `registrar_carga` serie por serie, como siempre: la
// carga única no existe en la base y por eso la web, el Cerebro y el brief siguen leyendo lo mismo.

/**
 * Cuándo se sugiere subir y hasta cuánto. El plan NO trae kilos: `progresion` solo tiene series, reps, RIR y título. Lo único
 * que dice es «bajan las reps». Lo que no entra en la regla no se inventa: sin sugerencia.
 */
object AumentoCarga {
    private val tituloFuera = JsRegex("""descarga|deload|re-?entrada|calibr|mantener|t[ée]cnica""", "i")
    private val tituloAnteriorFuera = JsRegex("""descarga|deload|re-?entrada""", "i")
    private val tituloCarga = JsRegex("""carga|fuerza|pico|potencia""", "i")

    /** «30 m», «50 s», «10 min»: va por tiempo o distancia, no por repeticiones. */
    private val repsNoContables = JsRegex("""\d\s*(s|seg|segundos?|m|mts?|metros?|min|minutos?|km)\b""", "i")

    /** La semana manda explícitamente la misma carga: la app no puede decir otra cosa. */
    private val mismaCarga = JsRegex("""misma\s+carga|mismo\s+peso|manten[eé]\w*\s+(el\s+|la\s+)?(peso|carga)""", "i")
    private val prefijoSemana = JsRegex("""^\s*semana\s+\d+\s*""", "i")
    private const val ORILLAS_TITULO = " —–-·:\n\t"

    /** El título sin el «Semana 3 — » de adelante; vacío si no dice otra cosa. */
    internal fun nombreDelTitulo(titulo: String?): String {
        val t = titulo ?: return ""
        return prefijoSemana.reemplazarTodo(t, "").trim { it in ORILLAS_TITULO }
    }

    /** Esta semana bajan las reps con las mismas series, y nada del plan dice lo contrario. Nunca en calibración. */
    fun corresponde(e: Ejercicio, semana: Int, mensajeSemana: String? = null): Boolean {
        if (e.progresion.isEmpty() || ReglasEjercicio.esCardio(e) || e.tipo == "calentamiento") return false
        val nota = Progresiones.nota(e, semana) ?: return false
        if (nota.calibracion) return false
        val (cur, prev) = Progresiones.pasoDePlan(e.progresion, Progresiones.semanaJs(semana))
        if (prev == null) return false
        val a = Progresiones.tope(cur.reps) ?: return false
        val b = Progresiones.tope(prev.reps) ?: return false
        val s = cur.series ?: return false
        if (!(a < b) || s != prev.series) return false
        if (ReglasEjercicio.repsDelPlan(cur.reps) == null || ReglasEjercicio.repsDelPlan(prev.reps) == null) return false
        if (repsNoContables.prueba(cur.reps ?: "") || repsNoContables.prueba(prev.reps ?: "")) return false
        val titulo = nombreDelTitulo(cur.titulo)
        if (tituloFuera.prueba(titulo) || tituloAnteriorFuera.prueba(nombreDelTitulo(prev.titulo))) return false
        if (titulo.isNotEmpty() && !tituloCarga.prueba(titulo)) return false
        if (mensajeSemana != null && mismaCarga.prueba(mensajeSemana)) return false
        return true
    }

    /** El paso según con qué se carga (el mismo criterio y las mismas constantes que la corona del reloj). */
    fun paso(equipo: Preparacion.Equipo, kg: Double): Double = when (equipo) {
        Preparacion.Equipo.MAQUINA -> Preparacion.PASO_MAQUINA
        Preparacion.Equipo.MANCUERNA -> if (kg < Preparacion.LIMITE_MANCUERNA_LIVIANA) Preparacion.PASO_MANCUERNA_LIVIANA else Preparacion.PASO_MANCUERNA_PESADA
        Preparacion.Equipo.BARRA, Preparacion.Equipo.OTRO -> Preparacion.PASO
    }

    /** Un paso arriba o abajo, alineado a la grilla del equipo (como la corona del reloj). */
    fun mover(kg: Double, pasos: Int, equipo: Preparacion.Equipo): Double {
        var k = kg
        repeat(abs(pasos)) {
            if (pasos > 0) {
                val p = paso(equipo, k)
                k = floor(k / p + 1e-9) * p + p
            } else {
                val p = paso(equipo, maxOf(0.0, k - 1e-6))
                k = ceil(k / p - 1e-9) * p - p
            }
            // floor(x + 0,5) y no `round`: el de Kotlin desempata al par y el de Swift, lejos del cero.
            k = minOf(Verosimilitud.KG_MAX, maxOf(0.0, floor(k * 100 + 0.5) / 100))
        }
        return k
    }

    const val SUBIDA_MINIMA = 2.5
    const val SUBIDA_MAXIMA = 5.0

    /**
     * A cuánto se sugiere subir: la primera marca del equipo a 2,5 kg o más, si no pasa de 5 (barra 2,5; máquina 5; mancuerna
     * 3 o 4, porque su grilla es de 1 o 2). null si en esa grilla no hay un salto entre 2,5 y 5 (43 en máquina): sin sugerencia.
     */
    fun hasta(desde: Double, equipo: Preparacion.Equipo): Double? {
        if (!(desde > 0)) return null
        var k = desde
        repeat(10) {
            k = mover(k, 1, equipo)
            val subida = k - desde
            if (subida >= SUBIDA_MINIMA - 1e-9) return if (subida <= SUBIDA_MAXIMA + 1e-9) k else null
        }
        return null
    }

    /** La carga base de la vez pasada: la moda de sus kilos y, en empate, la más alta. Una serie con menos no corre la base. */
    fun moda(kilos: List<Double>): Double? {
        val validos = kilos.filter { it > 0 }   // un 0 viejo no es una carga
        if (validos.isEmpty()) return null
        return validos.groupingBy { it }.eachCount().entries.maxWith(compareBy({ it.value }, { it.key })).key
    }
}

/**
 * La guardia del OK apurado: el primer OK a menos de 10 s del anterior, sin cambiar reps, no registra y pide otro toque. El
 * segundo toque vale entre medio segundo y 3 segundos después: un doble toque no la vence y un toque tardío vuelve a pedir.
 */
data class GuardiaOK(val desde: Double? = null, val serie: Int? = null) {
    fun activa(serie: Int, ahora: Double): Boolean {
        val d = desde ?: return false
        return this.serie == serie && ahora - d < VENCE_EN
    }

    fun levantar(serie: Int, ahora: Double): GuardiaOK = GuardiaOK(ahora, serie)

    fun limpiar(): GuardiaOK = GuardiaOK()

    /** ¿Este toque cuenta como el segundo? Si fue un doble toque, no cuenta ni levanta nada; si vencía, arranca de nuevo. */
    fun esSegundoToque(serie: Int, ahora: Double): Boolean {
        val d = desde ?: return false
        if (this.serie != serie) return false
        val t = ahora - d
        return t >= ESPERA_SEGUNDO_TOQUE && t < VENCE_EN
    }

    fun esDobleToque(serie: Int, ahora: Double): Boolean {
        val d = desde ?: return false
        return this.serie == serie && ahora - d < ESPERA_SEGUNDO_TOQUE
    }

    companion object {
        const val ESPERA_SEGUNDO_TOQUE = 500.0
        const val VENCE_EN = 3_000.0
    }
}

class CargaSimple(
    e: Ejercicio,
    semana: Int,
    val ultimaVez: List<Referencia>,
    val equipo: Preparacion.Equipo,
    sinKg: Boolean? = null,
    val recordKg: Double = 0.0,
    /** Milisegundos en los que un OK sin cambiar reps se toma como sospechoso. */
    val guardiaMs: Double = 10_000.0,
    mensajeSemana: String? = null,
    /** Las del día (hechas y por hacer), que mandan sobre la cantidad. */
    seriesLocales: List<SerieLocal>? = null,
    /** Lo guardado. Sin estado, la base sale de [ultimaVez]. */
    estado: Estado? = null,
    /** El mismo ejercicio en otro día de la semana ya aceptó o rechazó: sin sugerencia. */
    yaAumentadoEstaSemana: Boolean = false,
) {
    data class Referencia(val reps: Int, val kg: Double?)

    data class Serie(
        val reps: Int? = null,
        val kg: Double? = null,
        val confirmada: Boolean = false,
        /** El cliente movió las reps: lo que marcó no se pisa con la base (lo mismo que «lo girado no se pisa» del reloj). */
        val tocada: Boolean = false,
        val variante: String? = null,
    )

    sealed interface Aumento {
        data object NoCorresponde : Aumento
        data class Sugerido(val desde: Double, val hasta: Double) : Aumento
        data class Aceptado(val desde: Double, val hasta: Double) : Aumento
        data object Descartado : Aumento
    }

    enum class OrigenBase { ULTIMA_VEZ, PLAN, NINGUNO }

    data class Base(val reps: Int?, val origen: OrigenBase)

    sealed interface Evaluacion {
        data object FaltanDatos : Evaluacion

        /** OK sin tocar nada a pocos segundos del anterior: se pide un segundo toque. */
        data object Guardia : Evaluacion
        data class Lista(val reps: Int, val kg: Double?) : Evaluacion
    }

    /** Lo que se guarda en el teléfono por ejercicio y semana: sobrevive a relanzar la app. Solo local. */
    data class Estado(
        val carga: Double? = null,
        /** La base congelada: el historial trae también las filas de hoy y, sin esto, relanzar sugeriría sobre lo ya aceptado. */
        val cargaUltimaVez: Double? = null,
        val mismoPeso: Boolean = true,
        val aumento: Aumento = Aumento.NoCorresponde,
        /** Las reps que el cliente marcó en series que faltan (índice → reps). */
        val repsMarcadas: Map<Int, Int> = emptyMap(),
        /** El peso por serie con «mismo peso» destildado (índice → kg). */
        val kilos: Map<Int, Double> = emptyMap(),
        val cargaCambioDesdeOK: Boolean = false,
        /** ms del último OK (para la guardia). */
        val ultimoOK: Double? = null,
    ) {
        fun aValor(): ValorJson = ValorJson.Objeto(
            buildMap {
                carga?.let { put("carga", ValorJson.Numero(it)) }
                cargaUltimaVez?.let { put("cargaUltimaVez", ValorJson.Numero(it)) }
                put("mismoPeso", ValorJson.Booleano(mismoPeso))
                put("aumento", aumentoAValor(aumento))
                put("repsMarcadas", ValorJson.Objeto(repsMarcadas.entries.associate { it.key.toString() to ValorJson.Numero(it.value.toDouble()) }))
                put("kilos", ValorJson.Objeto(kilos.entries.associate { it.key.toString() to ValorJson.Numero(it.value) }))
                put("cargaCambioDesdeOK", ValorJson.Booleano(cargaCambioDesdeOK))
                ultimoOK?.let { put("ultimoOK", ValorJson.Numero(it)) }
            },
        )

        companion object {
            private fun aumentoAValor(a: Aumento): ValorJson = when (a) {
                Aumento.NoCorresponde -> ValorJson.objeto("tipo" to ValorJson.Texto("noCorresponde"))
                Aumento.Descartado -> ValorJson.objeto("tipo" to ValorJson.Texto("descartado"))
                is Aumento.Sugerido -> ValorJson.objeto("tipo" to ValorJson.Texto("sugerido"), "desde" to ValorJson.Numero(a.desde), "hasta" to ValorJson.Numero(a.hasta))
                is Aumento.Aceptado -> ValorJson.objeto("tipo" to ValorJson.Texto("aceptado"), "desde" to ValorJson.Numero(a.desde), "hasta" to ValorJson.Numero(a.hasta))
            }

            private fun aumentoDesde(v: ValorJson?): Aumento {
                val desde = v?.get("desde")?.comoNumero
                val hasta = v?.get("hasta")?.comoNumero
                return when (v?.get("tipo")?.comoTexto) {
                    "descartado" -> Aumento.Descartado
                    "sugerido" -> if (desde != null && hasta != null) Aumento.Sugerido(desde, hasta) else Aumento.NoCorresponde
                    "aceptado" -> if (desde != null && hasta != null) Aumento.Aceptado(desde, hasta) else Aumento.NoCorresponde
                    else -> Aumento.NoCorresponde
                }
            }

            /** Un archivo roto o tocado no tira la pantalla: lo que no se pueda leer queda como si no estuviera. */
            private fun enteros(v: ValorJson?): Map<Int, Double> = (v as? ValorJson.Objeto)?.campos?.entries?.mapNotNull { (k, n) ->
                val i = k.toIntOrNull() ?: return@mapNotNull null
                val d = n.comoNumero?.takeIf { it.isFinite() } ?: return@mapNotNull null
                i to d
            }?.toMap() ?: emptyMap()

            fun desde(v: ValorJson): Estado = Estado(
                carga = v["carga"]?.comoNumero,
                cargaUltimaVez = v["cargaUltimaVez"]?.comoNumero,
                mismoPeso = (v["mismoPeso"] as? ValorJson.Booleano)?.valor ?: true,
                aumento = aumentoDesde(v["aumento"]),
                repsMarcadas = enteros(v["repsMarcadas"]).mapValues { it.value.toInt() },
                kilos = enteros(v["kilos"]),
                cargaCambioDesdeOK = (v["cargaCambioDesdeOK"] as? ValorJson.Booleano)?.valor ?: false,
                ultimoOK = v["ultimoOK"]?.comoNumero,
            )
        }
    }

    val sinKg: Boolean = sinKg ?: ReglasEjercicio.sinKg(e)
    val repsPlan: String?
    val calibracion: Boolean
    val repsDelPlanCambian: Boolean

    var carga: Double?
        private set
    var cargaUltimaVez: Double?
        private set
    var mismoPeso: Boolean = true
        private set
    var series: List<Serie>
        internal set
    var aumento: Aumento = Aumento.NoCorresponde
        private set
    var ultimoOK: Double?
        internal set
    var varianteActual: String? = null

    /** Cambió la carga después del último OK: recién ahí tiene sentido ofrecer corregir las hechas. */
    var cargaCambioDesdeOK: Boolean = false
        private set

    init {
        val pauta = Progresiones.pauta(e, semana)
        repsPlan = pauta.reps
        calibracion = Progresiones.nota(e, semana)?.calibracion ?: false
        val previaReps = if (e.progresion.isNotEmpty()) Progresiones.pasoDePlan(e.progresion, Progresiones.semanaJs(semana)).second?.reps else null
        repsDelPlanCambian = previaReps != null && Progresiones.tope(previaReps) != Progresiones.tope(pauta.reps)

        val base = if (this.sinKg) null else AumentoCarga.moda(ultimaVez.mapNotNull { it.kg })
        carga = if (estado == null) base else estado.carga
        cargaUltimaVez = if (estado == null) base else estado.cargaUltimaVez
        mismoPeso = estado?.mismoPeso ?: true
        cargaCambioDesdeOK = estado?.cargaCambioDesdeOK ?: false
        ultimoOK = estado?.ultimoOK
        if (estado != null) {
            aumento = estado.aumento
        } else if (!yaAumentadoEstaSemana && base != null && !this.sinKg && AumentoCarga.corresponde(e, semana, mensajeSemana)) {
            AumentoCarga.hasta(base, equipo)?.let { aumento = Aumento.Sugerido(base, it) }
        }

        val cuantas = seriesLocales?.size ?: maxOf(pauta.series ?: 1, 1)
        val cargaInicial = carga
        series = List(cuantas) { i ->
            val l = seriesLocales?.getOrNull(i)
            if (l != null && l.confirmada) {
                Serie(l.reps.toIntOrNull(), l.kg.toDoubleOrNull(), confirmada = true, tocada = false, variante = l.varianteRegistrada)
            } else {
                val marcada = estado?.repsMarcadas?.get(i) ?: l?.reps?.toIntOrNull()
                val kg = if (estado?.mismoPeso != false) cargaInicial else estado.kilos[i] ?: cargaInicial
                Serie(marcada, kg, confirmada = false, tocada = marcada != null, variante = null)
            }
        }
    }

    /** Lo que se guarda en disco. */
    val estado: Estado
        get() {
            val marcadas = LinkedHashMap<Int, Int>()
            val kilos = LinkedHashMap<Int, Double>()
            series.forEachIndexed { i, s ->
                if (s.confirmada) return@forEachIndexed
                if (s.tocada && s.reps != null) marcadas[i] = s.reps
                if (!mismoPeso && s.kg != null) kilos[i] = s.kg
            }
            return Estado(carga, cargaUltimaVez, mismoPeso, aumento, marcadas, kilos, cargaCambioDesdeOK, ultimoOK)
        }

    // ── Lo que se ve ──

    /** La primera sin confirmar: la del dial. */
    val activa: Int? get() = series.indexOfFirst { !it.confirmada }.takeIf { it >= 0 }
    val confirmadas: Int get() = series.count { it.confirmada }
    val completo: Boolean get() = activa == null

    /** La vez pasada, en esta misma serie; si hoy hay más series que entonces, la última que hizo. */
    fun referencia(i: Int): Referencia? = ultimaVez.getOrNull(i) ?: ultimaVez.lastOrNull()

    /** Sin número de reps en el plan (AMRAP, máx.) y el cliente no marcó nada: el OK no significa nada todavía. */
    val pideElegirReps: Boolean get() = ReglasEjercicio.repsDelPlan(repsPlan) == null

    /**
     * Las reps base y de dónde salen. Con otra carga que la vez pasada o con otras reps del plan esta semana, lo de la vez
     * pasada ya no describe esta serie y manda el plan. Son referencia, no tope.
     */
    fun base(i: Int): Base {
        val plan = ReglasEjercicio.repsDelPlan(repsPlan)?.toInt()
        val s = series.getOrNull(i) ?: return Base(null, OrigenBase.NINGUNO)
        val r = referencia(i)
        if (r != null && (plan == null || (!repsDelPlanCambian && (sinKg || s.kg == r.kg)))) return Base(r.reps, OrigenBase.ULTIMA_VEZ)
        if (plan != null) return Base(plan, OrigenBase.PLAN)
        return Base(null, OrigenBase.NINGUNO)
    }

    fun reps(i: Int): Int? {
        val s = series.getOrNull(i) ?: return null
        return s.reps ?: base(i).reps
    }

    /** Lo marcado respecto de la base (+1, −2); null si coincide o no hay base. */
    fun diferencia(i: Int): Int? {
        val r = reps(i) ?: return null
        val b = base(i).reps ?: return null
        return if (r != b) r - b else null
    }

    fun puedeConfirmar(i: Int): Boolean {
        val s = series.getOrNull(i) ?: return false
        if (s.confirmada) return false
        val r = reps(i) ?: return false
        if (r < 1) return false
        if (pideElegirReps && !s.tocada) return false
        return sinKg || s.kg != null
    }

    /** Las ya hechas con otro peso que la carga actual. */
    val hechasConOtraCarga: Int
        get() {
            val c = carga
            if (!mismoPeso || !cargaCambioDesdeOK || c == null) return 0
            return series.count { it.confirmada && it.kg != c && it.variante == varianteActual }
        }

    /** La vez pasada no fueron todas con el mismo peso. */
    val ultimaVezMixta: Boolean get() = ultimaVez.mapNotNull { it.kg }.toSet().size > 1

    // ── Carga ──

    private inline fun cambiarSeries(condicion: (Serie) -> Boolean, f: (Serie) -> Serie) {
        series = series.map { if (condicion(it)) f(it) else it }
    }

    /** Toca solo las series que faltan: lo ya hecho se hizo con el peso que se hizo. Las reps sin tocar se recalculan. */
    fun fijarCarga(kg: Double?) {
        if (sinKg) return
        if (kg != carga) cargaCambioDesdeOK = true
        carga = kg
        // Tocó la carga a mano: la sugerencia o el «subiste a…» ya no describen lo que hay.
        when (val a = aumento) {
            is Aumento.Sugerido -> if (kg != a.desde) aumento = Aumento.Descartado
            is Aumento.Aceptado -> if (kg != a.hasta) aumento = Aumento.Descartado
            else -> {}
        }
        if (!mismoPeso) return
        cambiarSeries({ !it.confirmada }) { it.copy(kg = kg) }
    }

    fun moverCarga(pasos: Int) {
        val c = carga ?: return
        fijarCarga(AumentoCarga.mover(c, pasos, equipo))
    }

    /** La corrección de «me olvidé de cambiarla antes de empezar»: pasa las hechas a la carga actual. Devuelve cuáles. */
    fun aplicarCargaALasHechas(): List<Int> {
        val c = carga
        if (!mismoPeso || !cargaCambioDesdeOK || c == null) return emptyList()
        cargaCambioDesdeOK = false
        val tocadas = series.indices.filter { series[it].confirmada && series[it].kg != c && series[it].variante == varianteActual }
        series = series.mapIndexed { i, s -> if (i in tocadas) s.copy(kg = c) else s }
        return tocadas
    }

    fun aceptarAumento() {
        val a = aumento as? Aumento.Sugerido ?: return
        aumento = Aumento.Aceptado(a.desde, a.hasta)
        fijarCarga(a.hasta)
        if (!mismoPeso) cambiarSeries({ !it.confirmada }) { it.copy(kg = a.hasta) }
    }

    fun descartarAumento() {
        if (aumento is Aumento.Sugerido) aumento = Aumento.Descartado
    }

    /** Volver a la carga anterior desde el aviso de aumento aceptado. */
    fun deshacerAumento() {
        val a = aumento as? Aumento.Aceptado ?: return
        aumento = Aumento.Sugerido(a.desde, a.hasta)
        fijarCarga(a.desde)
    }

    // ── Peso por serie ──

    /**
     * Destildar «mismo peso»: cada serie que falta arranca con el suyo de la vez pasada si fue una mezcla; si no, con la carga.
     * Volver a tildarlo iguala las que faltan a la carga; las hechas no se tocan.
     */
    fun usarMismoPeso(si: Boolean) {
        if (si == mismoPeso) return
        mismoPeso = si
        series = series.mapIndexed { i, s ->
            if (s.confirmada) return@mapIndexed s
            if (si) {
                // En primera vez con pesos por fila la carga puede estar vacía: toma la de la primera que tenga peso.
                if (carga == null) carga = series.firstNotNullOfOrNull { it.kg }
                s.copy(kg = carga)
            } else {
                val k = if (ultimaVezMixta && carga == cargaUltimaVez) referencia(i)?.kg else null
                if (k != null) s.copy(kg = k) else s
            }
        }
    }

    fun fijarKg(i: Int, kg: Double?) {
        val s = series.getOrNull(i) ?: return
        if (s.confirmada || mismoPeso) return
        series = series.mapIndexed { j, x -> if (j == i) x.copy(kg = kg) else x }
    }

    fun moverKg(i: Int, pasos: Int) {
        val k = series.getOrNull(i)?.kg ?: return
        fijarKg(i, AumentoCarga.mover(k, pasos, equipo))
    }

    // ── Reps ──

    /** Sumar o restar. Solo el piso de 1 y el tope de Verosimilitud: hacer más de lo que dice el plan siempre vale. */
    fun ajustarReps(i: Int, d: Int) {
        val s = series.getOrNull(i) ?: return
        if (s.confirmada || d == 0) return
        val actual = reps(i) ?: ReglasEjercicio.repsDelPlan(repsPlan)?.toInt() ?: 10
        val nuevas = minOf(Verosimilitud.REPS_MAX.toInt(), maxOf(1, actual + d))
        series = series.mapIndexed { j, x -> if (j == i) x.copy(reps = nuevas, tocada = true) else x }
    }

    // ── Confirmar ──

    /** El OK de la serie: qué se registraría o por qué todavía no. `insistio` es el segundo toque después de la guardia. */
    fun evaluarOK(i: Int, ahora: Double, insistio: Boolean = false): Evaluacion {
        val r = reps(i)
        if (!puedeConfirmar(i) || r == null) return Evaluacion.FaltanDatos
        val s = series[i]
        val miro = s.tocada && r != base(i).reps   // sumar y restar lo mismo no es mirar
        val u = ultimoOK
        if (!miro && !insistio && u != null && ahora - u < guardiaMs) return Evaluacion.Guardia
        return Evaluacion.Lista(r, if (sinKg) null else s.kg)
    }

    /** El OK ya quedó registrado: anota cuándo, para la guardia de la próxima. */
    fun anotarOK(ahora: Double) {
        ultimoOK = ahora
        cargaCambioDesdeOK = false
    }
}
