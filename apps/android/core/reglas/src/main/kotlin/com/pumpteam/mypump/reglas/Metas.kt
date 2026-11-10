package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.EstructuraDieta
import com.pumpteam.mypump.modelos.FilaSalud
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Las metas del plan (2.3.0, propuesta 8): `meta_pasos_dia` y `ritmo_peso_kg_semana` en la raíz de
 * `mypump_dietas.estructura`. La app nunca inventa una meta: un valor que falta, que no es del tipo o que está fuera de
 * rango, no está. Gemelo de Metas.swift; vectores en apps/shared/vectores/metas_pasos.json.
 */
class MetasPlan(metaPasos: Int?, ritmoKgSemana: Double?) {
    val metaPasos: Int? = metaPasos?.takeIf { it in RANGO_PASOS }
    /** Kilos por semana, con signo: negativo para bajar, 0 para mantener, positivo para subir. */
    val ritmoKgSemana: Double? = ritmoKgSemana?.takeIf { it.isFinite() && it >= RANGO_RITMO.start && it <= RANGO_RITMO.endInclusive }

    val vacio: Boolean get() = metaPasos == null && ritmoKgSemana == null

    override fun equals(other: Any?) = other is MetasPlan && other.metaPasos == metaPasos && other.ritmoKgSemana == ritmoKgSemana
    override fun hashCode() = (metaPasos ?: 0) * 31 + (ritmoKgSemana?.hashCode() ?: 0)

    companion object {
        /** El mismo rango que controla pumplib al publicar (EDITOR, 10/11). */
        val RANGO_PASOS = 3_000..25_000
        val RANGO_RITMO = -1.0..0.5

        fun desde(e: EstructuraDieta): MetasPlan {
            // Pasos enteros: 10000 o 10000.0 sirven; 10000.5 no.
            val pasos = e.metaPasosDia?.takeIf { it.isFinite() && it == Math.rint(it) && abs(it) < 1e9 }?.toInt()
            return MetasPlan(pasos, e.ritmoPesoKgSemana)
        }
    }
}

/**
 * «Pump del día»: el indicador propio de la marca para la meta de pasos. El torso del logo se llena con los pasos de
 * hoy; al llegar, «Pump lleno», una sola vez por día.
 */
object PumpDelDia {
    const val NOMBRE = "Pump del día"
    const val LLENO = "Pump lleno"

    enum class EstadoDia(val clave: String) { CUMPLIDO("cumplido"), NO("no"), SIN_DATO("sin_dato"), HOY("hoy"), FUTURO("futuro") }

    data class Dia(val fecha: String, val inicial: String, val estado: EstadoDia)

    data class Vista(
        val meta: Int,
        val pasosHoy: Int,
        /** De 0 a 1 (tope 1). */
        val fraccion: Double,
        val falta: Int,
        val cumplido: Boolean,
        /** Días seguidos con la meta, terminando hoy si ya llegó (si no, ayer: hoy todavía está en juego). */
        val racha: Int,
        /** De lunes a domingo, la semana de hoy. */
        val semana: List<Dia>,
        /** El promedio de los últimos 7 días completos con dato (sin hoy). null sin días. */
        val promedio7: Int?,
    )

    private val INICIALES = listOf("L", "M", "M", "J", "V", "S", "D")

    /** Los pasos por día (la mejor fuente de cada día: `SaludVista.serie(filas, "pasos")`). */
    fun pasosPorDia(filas: List<FilaSalud>): Map<String, Double> =
        SaludVista.serie(filas, "pasos").associate { it.fecha to it.valor }

    private fun entero(x: Double): Int = jsEntero(x).toInt()

    fun vista(p: Map<String, Double>, meta: Int, hoy: String): Vista? {
        val nHoy = DiaCalendario.numero(hoy) ?: return null
        if (meta <= 0) return null
        val pasosHoy = max(0, entero(p[hoy] ?: 0.0))
        val cumplido = pasosHoy >= meta
        fun llego(n: Long) = entero(p[DiaCalendario.texto(n)] ?: -1.0) >= meta

        var racha = 0
        var d = if (cumplido) nHoy else nHoy - 1
        while (llego(d) && racha < 400) { racha++; d-- }

        val lunes = DiaCalendario.numero(FotosProgreso.lunes(hoy)) ?: nHoy
        val semana = (0 until 7).map { i ->
            val n = lunes + i
            val f = DiaCalendario.texto(n)
            val v = p[f]
            val estado = when {
                n > nHoy -> EstadoDia.FUTURO
                n == nHoy -> if (cumplido) EstadoDia.CUMPLIDO else EstadoDia.HOY
                v != null -> if (entero(v) >= meta) EstadoDia.CUMPLIDO else EstadoDia.NO
                else -> EstadoDia.SIN_DATO
            }
            Dia(f, INICIALES[i], estado)
        }

        val previos = (1..7).mapNotNull { p[DiaCalendario.texto(nHoy - it)] }
        val promedio = if (previos.isEmpty()) null else entero(previos.sum() / previos.size)

        return Vista(meta, pasosHoy, min(1.0, pasosHoy.toDouble() / meta), max(0, meta - pasosHoy), cumplido, racha, semana, promedio)
    }

    // ── Una sola celebración por día ──

    /** Lo que se guarda en el teléfono, por cuenta: las fechas ya celebradas (las últimas 60, en orden). */
    data class Registro(val celebrados: List<String> = emptyList())

    /**
     * ¿Hay que celebrar ahora? Solo hoy, con la meta cumplida, si hoy no se celebró y hoy no es anterior a la última fecha
     * celebrada (un viaje hacia el oeste vuelve a «ayer»: no se festeja dos veces el mismo esfuerzo).
     */
    fun debeCelebrar(r: Registro, hoy: String, pasosHoy: Int, meta: Int): Boolean {
        if (meta <= 0 || pasosHoy < meta || DiaCalendario.numero(hoy) == null) return false
        if (hoy in r.celebrados) return false
        val ultima = r.celebrados.maxOrNull()
        return ultima == null || ultima < hoy
    }

    fun marcar(r: Registro, hoy: String): Registro =
        Registro((r.celebrados.filter { it != hoy } + hoy).sorted().takeLast(60))

    // ── Textos (TEXTOS_PARA_OK, sección Metas) ──

    fun numeroPasos(n: Int): String = SaludVista.miles(n.toDouble())
    fun deMeta(v: Vista) = "de ${numeroPasos(v.meta)} pasos"
    fun estado(v: Vista) = if (v.cumplido) "Llegaste a tus pasos de hoy" else "Te faltan ${numeroPasos(v.falta)} pasos"
    fun racha(n: Int): String? = if (n >= 2) "$n días seguidos" else null
    fun sinSalud(meta: Int) = "Tu meta es de ${numeroPasos(meta)} pasos por día"
    const val CONECTAR = "Conectá Salud y vas a ver cómo venís"
    const val CONECTAR_BOTON = "Conectar Salud"
    fun celebracion(meta: Int) = "Llegaste a tus ${numeroPasos(meta)} pasos de hoy"
    fun celebracionRacha(n: Int): String? = if (n >= 2) "Van $n días seguidos" else null
    const val SEGUIR = "Seguir"
    fun lineaSalud(meta: Int, promedio: Int?): String =
        if (promedio == null) "Meta ${numeroPasos(meta)} pasos por día"
        else "Meta ${numeroPasos(meta)} pasos por día, tu promedio ${numeroPasos(promedio)}"
    fun accesible(v: Vista): String {
        var s = "$NOMBRE, ${numeroPasos(v.pasosHoy)} de ${numeroPasos(v.meta)} pasos. ${estado(v)}."
        racha(v.racha)?.let { s += " $it." }
        return s
    }
}

/**
 * El ritmo de peso que buscamos, junto a la media de 7 días que ya muestra la tarjeta de peso. Nunca un juicio negativo:
 * la tendencia se cuenta tal cual y, si va al ritmo, se dice.
 */
object RitmoPeso {
    data class Resumen(val meta: String, val tendencia: String?, val enRitmo: Boolean)

    const val EN_RITMO = "Vas justo al ritmo que buscamos"

    /** «medio kilo», «300 g», «un kilo», «1,2 kg». De a 100 g, con 100 g de piso. */
    fun cantidad(kg: Double): String {
        val decimas = max(1.0, jsRound(abs(kg) * 10))
        if (decimas == 5.0) return "medio kilo"
        if (decimas < 10) return "${decimas.toInt() * 100} g"
        if (decimas == 10.0) return "un kilo"
        val t = toFixed(decimas / 10, 1).replace('.', ',')
        return (if (t.endsWith(",0")) t.dropLast(2) else t) + " kg"
    }

    fun textoMeta(ritmo: Double): String {
        if (abs(ritmo) < 0.001) return "Buscamos mantener tu peso"
        val c = cantidad(ritmo)
        val unos = if (c.endsWith(" g") || c.contains(',')) "unos " else ""
        return "Buscamos ${if (ritmo < 0) "bajar" else "subir"} $unos$c por semana"
    }

    fun resumen(ritmo: Double, serie: List<PesoCorporal.Punto>, hoy: String): Resumen {
        val meta = textoMeta(ritmo)
        val nHoy = DiaCalendario.numero(hoy) ?: return Resumen(meta, null, false)
        val ultimos = serie.count { p -> DiaCalendario.numero(p.fecha)?.let { it > nHoy - 7 && it <= nHoy } ?: false }
        val g = PesoCorporal.deltaSemanal(serie, hoy)
        if (ultimos < 4 || g == null) return Resumen(meta, null, false)
        val tendencia = if (abs(g) < 100) "Venís estable"
        else "Venís ${if (g < 0) "bajando" else "subiendo"} ${cantidad(g / 1000.0)} por semana"
        val objetivo = ritmo * 1000
        val enRitmo = if (abs(ritmo) < 0.001) abs(g) <= 150
        else (g < 0) == (objetivo < 0) && abs(g).toDouble() >= 0.75 * abs(objetivo) && abs(g).toDouble() <= 1.5 * abs(objetivo)
        return Resumen(meta, tendencia, enRitmo)
    }
}

