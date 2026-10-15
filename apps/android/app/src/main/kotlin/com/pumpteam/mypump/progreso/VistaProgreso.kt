package com.pumpteam.mypump.progreso

import com.pumpteam.mypump.datos.TarjetaProgreso
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.entreno.Bonito
import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.de
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeParseException
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.pow

/**
 * Lo que la pantalla de Progreso arma con las tarjetas de `ModeloProgreso`, sin Android (se prueba en la JVM): las
 * secciones por día, el máximo de cada sesión para el gráfico, los textos de los números y las fechas como iOS en es_AR, y
 * las marcas de los ejes.
 */
object VistaProgreso {
    /** Los ejercicios que aparecen en los mismos días ("Tirón · Piernas"), en el orden de la rutina. */
    data class Seccion(val id: String, val titulo: String, val tarjetas: List<TarjetaProgreso>)

    /** El máximo de una sesión con su día local. */
    data class Sesion(val dia: LocalDate, val kg: Double)

    /**
     * Las secciones de ProgresoView.swift: una por cada combinación de días ("Tirón", o "Tirón · Torso" si el ejercicio está
     * en los dos), en el orden en que aparece la primera vez. Lo que viene en mayúsculas pasa a nombre propio.
     */
    fun secciones(tarjetas: List<TarjetaProgreso>): List<Seccion> {
        val porDias = LinkedHashMap<String, MutableList<TarjetaProgreso>>()
        for (t in tarjetas) porDias.getOrPut(t.dias) { mutableListOf() } += t
        return porDias.map { (dias, ts) -> Seccion(dias, dias.split(" · ").joinToString(" · ") { Bonito.titulo(it) }, ts) }
    }

    /**
     * El máximo de cada sesión con su día (las 8 más recientes, de la más vieja a la más nueva): los mismos valores que
     * `resumen.serie`, con la fecha para el eje del gráfico. Un peso nulo cuenta como 0, como en el resumen.
     */
    fun sesiones(filas: List<RegistroHistorico>, zona: ZoneId = ZoneId.systemDefault()): List<Sesion> {
        val porFecha = HashMap<String, Double>()
        for (f in filas) {
            val fecha = FechaLocal.de(f.registradoEn, zona)
            if (fecha.isEmpty()) continue
            porFecha[fecha] = max(porFecha[fecha] ?: -1.0, f.pesoKg ?: 0.0)
        }
        return porFecha.keys.sorted().takeLast(8).mapNotNull { d -> dia(d)?.let { Sesion(it, porFecha.getValue(d)) } }
    }

    /** Con el peso del cuerpo no hay kilos: el tope es 0. */
    fun conPeso(t: TarjetaProgreso): Boolean = t.resumen.tope > 0

    /** "58" / "52,5": hasta un decimal, con coma y sin miles (el `kg` de iOS). */
    fun kg(x: Double): String = Formato.decimal(x)

    /** "+12,3 %": con la coma argentina, un decimal y los miles con punto, como el `formatted` de iOS en es_AR. */
    fun variacion(v: Double): String {
        val partes = Formato.decimal(abs(v)).split(',')
        val entero = Formato.miles(partes[0].toDoubleOrNull() ?: 0.0)
        val decimales = partes.getOrNull(1)?.let { ",$it" } ?: ""
        val signo = if (v > 0) "+" else if (v < 0) "-" else ""
        return "$signo$entero$decimales %"
    }

    /** "1 oct": el día local del registro, como el detalle de iOS. Si no se puede leer, lo que viene antes de la T. */
    fun fechaCorta(iso: String, zona: ZoneId = ZoneId.systemDefault()): String =
        dia(FechaLocal.de(iso, zona))?.let(::fechaCorta) ?: iso.take(10)

    fun fechaCorta(d: LocalDate): String = "${d.dayOfMonth} ${MESES_CORTOS[d.monthValue - 1]}"

    /** Lo que lee TalkBack en una fila: "Jalón al pecho prono (dorsal ancho): tope 58 kilos, +11,5 % de progresión, récord". */
    fun accesible(t: TarjetaProgreso): String {
        val partes = mutableListOf(if (conPeso(t)) "${t.nombre}: tope ${kg(t.resumen.tope)} kilos" else "${t.nombre}: peso corporal")
        t.resumen.variacion?.let { partes += "${variacion(it)} de progresión" }
        if (t.resumen.esPR) partes += "récord"
        return partes.joinToString(", ")
    }

    /** Lo que lee TalkBack en el gráfico del detalle: cada sesión con su fecha, y el tope. */
    fun graficoAccesible(sesiones: List<Sesion>, tope: Double): String =
        "Máximo por sesión: " + sesiones.joinToString(", ") { "${kg(it.kg)} kg el ${fechaCorta(it.dia)}" } + ". Tope ${kg(tope)} kg."

    /**
     * Las marcas de un eje entre [lo] y [hi]: unas [cuantas], en números redondos (de a 1, 2, 5 o 10 por la potencia de
     * diez que corresponda), como las `AxisMarks(values: .automatic(desiredCount: 4))` de Charts.
     */
    fun marcas(lo: Double, hi: Double, cuantas: Int = 4): List<Double> {
        if (!(hi > lo) || !lo.isFinite() || !hi.isFinite()) return emptyList()
        val bruto = (hi - lo) / cuantas
        val magnitud = 10.0.pow(floor(log10(bruto)))
        val normal = bruto / magnitud
        val paso = magnitud * when {
            normal < 1.5 -> 1.0
            normal < 3.0 -> 2.0
            normal < 7.0 -> 5.0
            else -> 10.0
        }
        // Redondeadas a los decimales del paso: sin el ruido del double (0,6000000000000001).
        val escala = 10.0.pow(max(0, -floor(log10(paso)).toInt()))
        val out = mutableListOf<Double>()
        var k = ceil(lo / paso)
        while (k * paso <= hi + paso * 1e-9 && out.size < 20) {
            out += Math.round(k * paso * escala) / escala
            k += 1
        }
        return out
    }

    private fun dia(d: String): LocalDate? = try {
        LocalDate.parse(d)
    } catch (_: DateTimeParseException) {
        null
    }

    /** Los meses abreviados de es_AR (CLDR, los de iOS): "sept" y no "sep". */
    private val MESES_CORTOS = listOf("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic")
}
