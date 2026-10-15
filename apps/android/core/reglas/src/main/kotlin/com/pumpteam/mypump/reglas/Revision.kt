package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.FotoProgreso
import java.time.LocalDate
import java.util.Locale

/**
 * La card de peso de Revisión (cliente.html:7330-7464): la serie diaria (la carga manual gana sobre el reloj), la media
 * móvil de 7 días y la diferencia de esa media contra la de la semana anterior, en gramos. El rango objetivo NO se
 * muestra al cliente (lo interpreta Mati).
 */
object PesoCorporal {
    data class Punto(val fecha: String, val kg: Double)

    /**
     * `_pesoSerie`: un punto por fecha, mayor a 0, en orden ascendente. Si en una fecha hay manual y de un reloj, gana el
     * manual; entre dos del mismo tipo, el primero que vino.
     */
    fun serie(filas: List<FilaSalud>): List<Punto> {
        val porFecha = LinkedHashMap<String, FilaSalud>()
        for (r in filas) {
            if (r.tipo != "peso_kg") continue
            val previo = porFecha[r.fecha]
            if (previo == null || (previo.fuente != "manual" && r.fuente == "manual")) porFecha[r.fecha] = r
        }
        return porFecha.values.mapNotNull { r -> r.valor?.takeIf { it > 0 }?.let { Punto(r.fecha, it) } }.sortedBy { it.fecha }
    }

    /** `_pesoMedia`: la media de los puntos con fecha en (fin − días, fin]. */
    fun media(serie: List<Punto>, hasta: String, dias: Int): Double? {
        val fin = DiaCalendario.numero(hasta) ?: return null
        val valores = serie.filter { p ->
            val d = DiaCalendario.numero(p.fecha) ?: return@filter false
            d > fin - dias && d <= fin
        }.map { it.kg }
        return if (valores.isEmpty()) null else valores.sum() / valores.size
    }

    /** La línea del gráfico: la media de 7 días en cada punto (o el punto si no hay media). */
    fun lineaMedia(serie: List<Punto>): List<Punto> = serie.map { Punto(it.fecha, media(serie, it.fecha, 7) ?: it.kg) }

    /** Diferencia en gramos de la media de 7 días de hoy contra la de hace una semana (`deltaG`), o null. */
    fun deltaSemanal(serie: List<Punto>, hoy: String): Int? {
        val dHoy = DiaCalendario.numero(hoy) ?: return null
        val m7 = media(serie, hoy, 7) ?: return null
        val m7prev = media(serie, DiaCalendario.texto(dHoy - 7), 7) ?: return null
        return jsRound((m7 - m7prev) * 1000).toInt()
    }

    /** "+350 g" / "-1,3 kg" (la parte en negrita de "Esta semana: … vs la semana pasada"). */
    fun textoDelta(g: Int): String {
        val signo = if (g > 0) "+" else ""
        if (Math.abs(g) >= 1000) return "$signo${toFixed(g / 1000.0, 1).replace('.', ',')} kg"
        return "$signo$g g"
    }

    /** `v.toFixed(1).replace('.', ',')`. */
    fun kg(v: Double): String = toFixed(v, 1).replace('.', ',')

    /** Lo que escribe el cliente: coma o punto, entre 30 y 300 kg, redondeado a 100 g. Fuera de rango, null. */
    fun leer(texto: String): Double? {
        val v = leerNumeroEscrito(texto) ?: return null
        if (v < 30 || v > 300) return null
        return jsRound(v * 10) / 10
    }
}

/** El check de la semana (CHECKIN_METRICAS): cuatro escalas de 1 a 5 y una nota opcional. */
object CheckinSemanal {
    data class Metrica(val clave: String, val etiqueta: String, val bajo: String, val alto: String)

    val metricas: List<Metrica> = listOf(
        Metrica("energia", "Energía", "muy baja", "excelente"),
        Metrica("descanso", "Descanso", "dormí mal", "dormí bien"),
        Metrica("hambre", "Hambre", "sin hambre", "mucha"),
        Metrica("adherencia", "Adherencia", "me costó", "la seguí"),
    )

    /** "Faltan: Energía, Hambre", o null si están las cuatro. */
    fun faltan(valores: Map<String, Int>): String? {
        val f = metricas.filter { (valores[it.clave] ?: 0) == 0 }.map { it.etiqueta }
        return if (f.isEmpty()) null else "Faltan: ${f.joinToString(", ")}"
    }
}

/** Mi Día: el ícono de la racha (renderMydayStreak). */
object RachaTexto {
    fun icono(n: Int): String = if (n >= 7) "🔥" else if (n >= 3) "⚡" else if (n >= 1) "✨" else "💤"
}

/**
 * Días de calendario como número (días desde 1970-01-01), para comparar fechas "YYYY-MM-DD" sin zonas horarias. Como
 * `new Date("…T00:00:00")` de la web: el mes tiene que ser de 1 a 12 y un día de más pasa al mes siguiente
 * ("2026-02-30" es el 2 de marzo).
 */
object DiaCalendario {
    private val FECHA = Regex("([0-9]{4})-([0-9]{2})-([0-9]{2})")

    fun numero(f: String): Long? {
        val m = FECHA.matchAt(f, 0) ?: return null
        val (a, mes, dia) = m.destructured
        if (mes.toInt() !in 1..12 || dia.toInt() !in 1..31) return null
        return LocalDate.of(a.toInt(), mes.toInt(), 1).plusDays(dia.toLong() - 1).toEpochDay()
    }

    fun texto(n: Long): String {
        val d = LocalDate.ofEpochDay(n)
        return String.format(Locale.ROOT, "%04d-%02d-%02d", d.year, d.monthValue, d.dayOfMonth)
    }
}

/**
 * Fotos de progreso (cliente.html:7476-7962): tres poses por semana (lunes ISO), la racha de semanas completas, el
 * recordatorio semanal y el comparador antes/después (que espera a las 4 semanas: antes compara luz y retención de
 * líquido, no cambios reales).
 */
object FotosProgreso {
    val poses: List<Pair<String, String>> = listOf("frente" to "Frente", "perfil" to "Perfil", "espalda" to "Espalda")
    const val MAX_PENDIENTES = 3

    /** El servidor corta el body de más de 3 MB; el data URL se filtra antes de encolar. */
    const val MAX_CARACTERES = 2_400_000

    /** `_lunesISO`: el lunes de la semana de esa fecha. */
    fun lunes(fecha: String): String {
        val n = DiaCalendario.numero(fecha) ?: return fecha
        // 1970-01-01 fue jueves: (n + 3) mod 7 da 0 para el lunes.
        val dow = Math.floorMod(n + 3, 7L)
        return DiaCalendario.texto(n - dow)
    }

    /** Las poses de esta semana: las del servidor más las que esperan subir (pose, fecha). */
    fun posesDeLaSemana(fotos: List<FotoProgreso>, pendientes: List<Pair<String, String>>, semana: String): Set<String> {
        val s = fotos.filter { it.semanaLunes == semana }.map { it.pose }.toMutableSet()
        for ((pose, fecha) in pendientes) if (lunes(fecha) == semana) s += pose
        return s
    }

    /** Las semanas con alguna foto, en orden. */
    fun semanas(fotos: List<FotoProgreso>): List<String> = fotos.map { it.semanaLunes }.distinct().sorted()

    /** "🔥 N semanas seguidas": semanas con las tres poses, consecutivas hacia atrás desde la última completa. */
    fun racha(fotos: List<FotoProgreso>): Int {
        val porSemana = HashMap<String, MutableSet<String>>()
        for (f in fotos) porSemana.getOrPut(f.semanaLunes) { HashSet() } += f.pose
        val completas = porSemana.keys.sorted().filter { porSemana.getValue(it).size == 3 }
        val ultima = completas.lastOrNull() ?: return 0
        val nUltima = DiaCalendario.numero(ultima) ?: return 0
        var serie = 0
        for (i in completas.indices.reversed()) {
            if (completas[i] == DiaCalendario.texto(nUltima - (completas.size - 1 - i) * 7L)) serie++ else break
        }
        return serie
    }

    data class Pendientes(val faltaCheck: Boolean, val faltanFotos: Boolean, val total: Int)

    /** Lo que falta de la semana (badge de Revisión y banner en las otras pestañas). */
    fun pendientes(checkinEnviado: Boolean, posesDeLaSemana: Set<String>): Pendientes {
        val faltaCheck = !checkinEnviado
        val faltanFotos = posesDeLaSemana.size < 3
        return Pendientes(faltaCheck, faltanFotos, (if (faltaCheck) 1 else 0) + (if (faltanFotos) 1 else 0))
    }

    /** El texto del banner ("Te faltan tu check y tus fotos de la semana"). */
    fun textoRecordatorio(faltaCheck: Boolean, faltanFotos: Boolean): String? = when {
        faltaCheck && faltanFotos -> "Te faltan tu check y tus fotos de la semana"
        faltaCheck -> "Te falta tu check de la semana"
        faltanFotos -> "Te faltan tus fotos de la semana"
        else -> null
    }

    /** El pie del comparador: "8 semanas · -2,4 kg" (el peso es el primero cargado desde el lunes de cada semana). */
    fun resumenComparador(primera: String, ultima: String, peso: List<PesoCorporal.Punto>): String {
        fun pesoEn(sem: String) = peso.filter { it.fecha >= sem }.minByOrNull { it.fecha }?.kg
        val semDif = jsRound(((DiaCalendario.numero(ultima) ?: 0L) - (DiaCalendario.numero(primera) ?: 0L)) / 7.0).toInt()
        var r = "$semDif semana${if (semDif == 1) "" else "s"}"
        val p0 = pesoEn(primera)
        val p1 = pesoEn(ultima)
        if (p0 != null && p1 != null) {
            val d = p1 - p0
            r += " · ${if (d > 0) "+" else ""}${PesoCorporal.kg(d)} kg"
        }
        return r
    }
}
