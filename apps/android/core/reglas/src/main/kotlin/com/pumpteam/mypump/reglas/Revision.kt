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
/**
 * La semana de revisión y el aviso local (R2 de la 2.0.3). La semana es SIEMPRE de lunes a domingo (`FotosProgreso.lunes`):
 * el día de revisión del alumno (1 = lunes … 7 = domingo) solo mueve el aviso, no corre la semana. Vectores:
 * apps/shared/vectores/aviso_revision.json. Gemelo de `SemanaRevision` de iOS.
 */
object SemanaRevision {
    /** Lo que dice la pantalla de Revisión: un alumno no sabía si era diaria o semanal. Sin nombrar un día: cada alumno tiene el suyo. */
    const val EXPLICACION = "La revisión es semanal: una vez por semana subís tus 3 fotos y completás el check. No hace falta hacerla todos los días."

    const val DIA_POR_DEFECTO = 7

    /** El aviso sale el día de revisión a las 11:00, hora del teléfono (es cuando se arma la ronda de Mati). */
    const val MINUTOS_AVISO = 11 * 60

    /** Un día fuera de 1…7 (un dato raro) vale el domingo. */
    fun normalizado(dia: Int?): Int = if (dia != null && dia in 1..7) dia else DIA_POR_DEFECTO

    /** La línea de la pestaña Revisión para quien no revisa el domingo. Con el domingo (lo de siempre) no se dice nada. */
    fun textoDia(dia: Int?): String? {
        val d = normalizado(dia)
        if (d == DIA_POR_DEFECTO) return null
        return "Tu día de revisión es el ${listOf("lunes", "martes", "miércoles", "jueves", "viernes", "sábado")[d - 1]}"
    }

    /** Completa: lo mismo que deja el badge de Revisión en cero (el check guardado y las tres fotos de la semana). */
    fun completa(checkinEnviado: Boolean, posesDeLaSemana: Set<String>): Boolean =
        FotosProgreso.pendientes(checkinEnviado, posesDeLaSemana).total == 0

    /**
     * El día del próximo aviso: el día de revisión que viene (hoy, si es ese día antes de las 11). Si la semana de revisión
     * de hoy ya está completa y ese aviso cae en la misma semana, se saltea al de la semana siguiente: quien subió todo el
     * sábado no recibe nada el domingo.
     */
    fun fechaAviso(hoy: String, minutos: Int, completa: Boolean, dia: Int = DIA_POR_DEFECTO): String? {
        val n = DiaCalendario.numero(hoy) ?: return null
        val d = normalizado(dia)
        val dow = Math.floorMod(n + 3, 7L) + 1   // 1970-01-01 fue jueves: 1 = lunes … 7 = domingo
        var delta = Math.floorMod(d - dow, 7L)
        if (delta == 0L && minutos >= MINUTOS_AVISO) delta = 7
        var aviso = n + delta
        if (completa && FotosProgreso.lunes(DiaCalendario.texto(aviso)) == FotosProgreso.lunes(hoy)) aviso += 7
        return DiaCalendario.texto(aviso)
    }
}

object FotosProgreso {
    const val AVISO_TITULO = "Tus fotos de la semana"
    const val AVISO_CUERPO = "Esta semana todavía no subiste tus fotos. Sacalas en el mismo lugar y con la misma luz que siempre, con la misma ropa, el celu vertical a la altura del ombligo y a 2 o 3 metros. Frente, perfil y espalda. Así vemos bien cómo venís"

    /**
     * El aviso de la pestaña Revisión: mientras falte alguna de las tres de esta semana (el mismo criterio del banner).
     * Sin saber qué hay en el servidor no se dice nada: no se le puede decir «no subiste» a quien ya las subió.
     */
    fun mostrarAviso(cargadas: Boolean, posesDeLaSemana: Set<String>): Boolean = cargadas && posesDeLaSemana.size < 3

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

    // ── El peso del comparador (2.3.3, el arreglo de la web: cliente.html `TuCambio.pesaje` y `cambio`) ──
    // Antes era «el primero cargado desde el lunes», sin tope, sobre los 60 días de Salud: con una primera foto más vieja
    // tomaba un peso de meses después (Emmanuel veía +0,7 kg en vez de −4,6). Ahora el peso va en una serie aparte que llega
    // hasta la primera foto (`ModeloRevision.serieDelComparador`) y cada foto toma el de su semana:
    // · El de la misma semana (lunes a domingo): el primero cargado en ella.
    // · Si esa semana no tiene peso, el más cercano dentro de 7 días antes del lunes o 7 después del domingo. Empate: el de
    //   después (como la regla vieja, que miraba hacia adelante).
    // · Si tampoco hay, el pie dice solo «N semanas»: nunca un peso inventado.
    // Los casos están en apps/shared/vectores/tucambio.json (los corren iOS, Android y la web).

    /** Hasta cuántos días fuera de su semana se busca el peso de una foto. */
    const val PESO_DIAS_CERCA = 7L

    /**
     * Guarda de unidades: un cambio de más del 25 % del peso de la primera foto es imposible (libras contra kilos es un salto
     * de más del 50 %). No hay tope por semana a propósito: con tirzepatida se bajan 3 a 4 kg en dos semanas.
     */
    const val GUARDA_FRACCION = 0.25

    /** El pesaje elegido para una semana de fotos: el día ([DiaCalendario.numero]) y los kg. */
    internal data class Pesaje(val n: Long, val kg: Double)

    internal fun pesaje(semana: String, peso: List<PesoCorporal.Punto>): Pesaje? {
        val l = DiaCalendario.numero(semana) ?: return null
        var mejor: Pesaje? = null
        var dist = Long.MAX_VALUE
        val puntos = peso.mapNotNull { p -> DiaCalendario.numero(p.fecha)?.takeIf { p.kg > 0 }?.let { Pesaje(it, p.kg) } }.sortedBy { it.n }
        for (p in puntos) {
            val x = if (p.n < l) l - p.n else if (p.n > l + 6) p.n - (l + 6) else 0L
            if (x > PESO_DIAS_CERCA) continue
            if (x < dist || (x == dist && x > 0)) { mejor = p; dist = x }
        }
        return mejor
    }

    /** El peso de una semana de fotos, o null. */
    fun pesoDeSemana(semana: String, peso: List<PesoCorporal.Punto>): Double? = pesaje(semana, peso)?.kg

    /** Las semanas entre las dos fotos y el cambio de peso (`kg` null si no se puede decir). */
    data class Cambio(val semanas: Int, val kg: Double?)

    fun cambioComparador(primera: String, ultima: String, peso: List<PesoCorporal.Punto>): Cambio {
        val semanas = jsRound(((DiaCalendario.numero(ultima) ?: 0L) - (DiaCalendario.numero(primera) ?: 0L)) / 7.0).toInt()
        val a = pesaje(primera, peso) ?: return Cambio(semanas, null)
        val b = pesaje(ultima, peso) ?: return Cambio(semanas, null)
        // Las dos puntas tienen que ser pesajes distintos, en orden y cada uno fuera de la semana de la otra foto. Con fotos de
        // semanas seguidas las ventanas de ±7 días se pisan: el alumno nuevo que todavía no se pesó en su segunda semana veía
        // «1 semana · 0,0 kg» (el mismo pesaje en las dos fotos) o el cambio dentro de la semana 1.
        fun enSemana(n: Long, sem: String) = DiaCalendario.numero(sem)?.let { n >= it && n <= it + 6 } ?: false
        if (a.n >= b.n || enSemana(a.n, ultima) || enSemana(b.n, primera)) return Cambio(semanas, null)
        val d = b.kg - a.kg
        if (Math.abs(d) > GUARDA_FRACCION * a.kg) return Cambio(semanas, null)
        return Cambio(semanas, d)
    }

    /** El pie del comparador: "8 semanas · -2,4 kg". Lo usan «Tu cambio» y el comparador clásico («Antes y ahora»). */
    fun resumenComparador(primera: String, ultima: String, peso: List<PesoCorporal.Punto>): String {
        val c = cambioComparador(primera, ultima, peso)
        var r = "${c.semanas} semana${if (c.semanas == 1) "" else "s"}"
        val d = c.kg
        if (d != null) {
            val t = PesoCorporal.kg(d).let { if (it == "-0,0") "0,0" else it }
            r += " · ${if (d > 0 && t != "0,0") "+" else ""}$t kg"
        }
        return r
    }

    /**
     * Desde cuándo pedir el peso del comparador: el lunes de la semana de la foto más vieja menos 7 días (lo que necesita la
     * regla de ±7 días). `fechas`: las semanas o los días de las fotos (AAAA-MM-DD). null sin ninguna fecha válida.
     */
    fun desdePesoComparador(fechas: List<String>): String? =
        fechas.filter { it.length == 10 }.mapNotNull { DiaCalendario.numero(lunes(it)) }.minOrNull()?.let { DiaCalendario.texto(it - PESO_DIAS_CERCA) }

    /** Si hace falta la serie aparte: los 60 días de Salud (de hoy − 59 a hoy) no llegan a `desde`. */
    fun necesitaPesoComparador(desde: String, hoy: String): Boolean {
        val d = DiaCalendario.numero(desde) ?: return false
        val h = DiaCalendario.numero(hoy) ?: return false
        return d < h - 59
    }
}
