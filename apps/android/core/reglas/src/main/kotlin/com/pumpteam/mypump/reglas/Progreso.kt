package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.RegistroHistorico
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Progreso (cliente.html:6036-6249): una tarjeta por ejercicio con el máximo por sesión de las últimas 8, el tope, la
 * variación entre la primera y la última de esas 8, y el 🏆 PR si la última sesión superó a TODAS las anteriores.
 */
object ProgresoEjercicio {
    data class Resumen(
        /** Máximo por sesión, de la más vieja a la más nueva (las 8 más recientes). */
        val serie: List<Double>,
        val tope: Double,
        /** Variación en % (un decimal, como `toFixed(1)`), o null con una sola sesión o arrancando en 0. */
        val variacion: Double?,
        val esPR: Boolean,
    )

    /** null si no hay ninguna sesión. Las filas llegan de la más nueva a la más vieja; un peso nulo cuenta como 0. */
    fun resumen(filas: List<RegistroHistorico>, zona: ZoneId = ZoneId.systemDefault()): Resumen? {
        val porFecha = HashMap<String, Double>()
        for (f in filas) {
            val fecha = FechaLocal.de(f.registradoEn, zona)
            if (fecha.isEmpty()) continue
            val kg = f.pesoKg ?: 0.0
            val previo = porFecha[fecha]
            if (previo == null || kg > previo) porFecha[fecha] = kg
        }
        val todos = porFecha.keys.sorted().map { porFecha.getValue(it) }
        val serie = todos.takeLast(8)
        val primero = serie.firstOrNull() ?: return null
        val ultimo = serie.last()
        val variacion = if (serie.size > 1 && primero > 0) toFixed((ultimo - primero) / primero * 100, 1).toDouble() else null
        val esPR = todos.size > 1 && ultimo > (todos.dropLast(1).maxOrNull() ?: 0.0)
        return Resumen(serie, serie.max(), variacion, esPR)
    }

    /** Las sesiones entrenadas: fechas locales distintas con algún registro. */
    fun sesiones(filas: List<RegistroHistorico>, zona: ZoneId = ZoneId.systemDefault()): Set<String> =
        filas.map { FechaLocal.de(it.registradoEn, zona) }.filter { it.isNotEmpty() }.toSet()
}

/**
 * `Number.prototype.toFixed(digitos)` de JS: el decimal más cercano al valor EXACTO del double, con el empate hacia
 * arriba en valor absoluto, y el signo aunque quede en cero (`(-0.04).toFixed(1)` es "-0.0"). No es redondear `x * 10`:
 * `(0.15).toFixed(1)` es "0.1" porque 0.15 en binario es 0.1499…, y `0.15 * 10` ya da 1.5.
 */
fun toFixed(x: Double, digitos: Int): String {
    if (x.isNaN()) return "NaN"
    if (Math.abs(x) >= 1e21) return NumeroJs.texto(x)
    val s = BigDecimal(Math.abs(x)).setScale(digitos, RoundingMode.HALF_UP).toPlainString()
    return if (x < 0) "-$s" else s
}

/** `fechaLocalDe(iso)`: la fecha local de un instante del servidor; si no se puede leer, lo que viene antes de la T. */
fun FechaLocal.de(iso: String, zona: ZoneId = ZoneId.systemDefault()): String {
    if (iso.isEmpty()) return ""
    val instante = FechaIsoReglas.instante(iso) ?: return iso.substringBefore('T')
    return hoy(instante, zona)
}

/**
 * Lectura de los instantes del servidor para las reglas: "2026-09-02T01:30:00.123456+00:00", con espacio en vez de T
 * o con la zona como "+00" (el formato de texto de Postgres).
 */
internal object FechaIsoReglas {
    private val ZONA_CORTA = Regex("[+-][0-9][0-9]$")
    private val FRACCION = Regex("\\.([0-9]+)")

    fun instante(iso: String): Instant? {
        var s = iso.replace(' ', 'T')
        // Más de 9 decimales no los lee java.time: como en iOS, se recortan (a 9, que no cambia el instante).
        s = FRACCION.replace(s) { m -> "." + m.groupValues[1].take(9) }
        if (ZONA_CORTA.containsMatchIn(s)) s += ":00"
        return try {
            OffsetDateTime.parse(s, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant()
        } catch (_: Exception) {
            null
        }
    }
}
