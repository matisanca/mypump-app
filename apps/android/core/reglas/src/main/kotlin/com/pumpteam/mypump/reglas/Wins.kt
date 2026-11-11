package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * «Récords y logros» (2.3.0, palanca `wins_app`; gemelo de Wins.swift): los récords del día que se festejan al cerrar la
 * sesión, los hitos de la racha de pasos y los textos. La referencia es `scripts/nativa/generar-vectores-cola-a.py` y los
 * vectores de `apps/shared/vectores/wins.json`: esto tiene que dar exactamente lo mismo que iOS y la web.
 *
 * Por ejercicio del día: `anteriores` son las marcas de días anteriores (misma clave) y `hoy` las series de hoy
 * confirmadas y verosímiles. Una marca sirve si kg > 0, finito, y reps >= 1. Sin kg, sin historia suficiente, sin marcas
 * anteriores que sirvan o sin series de hoy que sirvan: no hay récord. Lo mejor es la marca de más kg y, entre las de ese
 * kg, la de más reps. A lo sumo un récord por ejercicio, en el orden del día, y como mucho [TOPE].
 */
object ReglasWins {
    /** Un ejercicio del día, como entra a la regla. */
    data class Ejercicio(
        val clave: String,
        /** El del ejercicio que se hace (el sustituto, si está sustituido). */
        val nombre: String,
        val anteriores: List<RecordSerie.Marca>,
        val hoy: List<RecordSerie.Marca>,
        /** Peso corporal, por tiempo, calentamiento o cardio: nunca hay récord. */
        val sinKg: Boolean = false,
        /** [RecordSerie.historiaSuficiente]: con la historia cortada no se habla de récord. */
        val suficiente: Boolean = true,
    )

    /** `tipo` de `mypump_wins`. Lo que no se conoce no se guarda ni se manda. */
    enum class Tipo(val valor: String) {
        RECORD_KG("record_kg"),
        RECORD_REPS("record_reps"),
        RACHA_PASOS("racha_pasos");

        companion object {
            fun desde(valor: String?): Tipo? = entries.firstOrNull { it.valor == valor }
        }
    }

    data class Record(
        val tipo: Tipo,
        val clave: String,
        val ejercicio: String,
        val kg: Double,
        val reps: Int,
        val antesKg: Double,
        val antesReps: Int,
        /** Lo que se superó: kg (2,5) o reps (1). */
        val delta: Double,
        /** «57,5 kg × 8» */
        val marca: String,
        /** «+2,5 kg» o «+1 rep» */
        val chip: String,
        /** «Antes: 55 kg × 8» */
        val antes: String,
    ) {
        /** Lo que viaja a `mypump_wins_registrar` en `p_datos`. */
        val datos: ValorJson
            get() = ValorJson.objeto(
                "ejercicio" to ValorJson.Texto(ejercicio), "kg" to ValorJson.Numero(kg), "reps" to ValorJson.Numero(reps.toDouble()),
                "antes_kg" to ValorJson.Numero(antesKg), "antes_reps" to ValorJson.Numero(antesReps.toDouble()),
            )
    }

    const val TOPE = 12
    private const val TOLERANCIA = 1e-6

    private fun sirve(m: RecordSerie.Marca): Boolean = m.kg > 0 && m.kg.isFinite() && m.reps >= 1

    private fun mejor(marcas: List<RecordSerie.Marca>): RecordSerie.Marca {
        val kg = marcas.maxOf { it.kg }
        val reps = marcas.filter { abs(it.kg - kg) < TOLERANCIA }.maxOf { it.reps }
        return RecordSerie.Marca(kg, reps)
    }

    /** 60 → «60», 62.5 → «62,5» (el número como lo escribe JS, con coma). */
    private fun kilos(x: Double): String = Js.texto(x).replace('.', ',')

    fun records(ejercicios: List<Ejercicio>): List<Record> {
        val salida = mutableListOf<Record>()
        for (e in ejercicios) {
            if (e.sinKg || !e.suficiente) continue
            val antes = e.anteriores.filter(::sirve)
            val hoy = e.hoy.filter(::sirve)
            if (antes.isEmpty() || hoy.isEmpty()) continue
            val a = mejor(antes)
            val h = mejor(hoy)
            val tipo: Tipo
            val delta: Double
            val chip: String
            if (h.kg > a.kg + TOLERANCIA) {
                tipo = Tipo.RECORD_KG
                delta = ((h.kg - a.kg) * 100).roundToLong() / 100.0
                chip = "+${kilos(delta)} kg"
            } else if (abs(h.kg - a.kg) < TOLERANCIA && h.reps > a.reps) {
                tipo = Tipo.RECORD_REPS
                val n = h.reps - a.reps
                delta = n.toDouble()
                chip = "+$n rep${if (n == 1) "" else "s"}"
            } else {
                continue
            }
            salida += Record(
                tipo, e.clave, e.nombre, h.kg, h.reps, a.kg, a.reps, delta,
                marca = "${kilos(h.kg)} kg × ${h.reps}", chip = chip, antes = "Antes: ${kilos(a.kg)} kg × ${a.reps}",
            )
            if (salida.size == TOPE) break
        }
        return salida
    }

    // ── Textos (los de `wins.json`) ──

    fun titulo(n: Int): String = if (n == 1) "Récord nuevo" else "$n récords hoy"
    fun subtitulo(n: Int): String = if (n == 1) "Superaste tu mejor marca." else "Superaste $n de tus mejores marcas."
    fun conPermiso(n: Int): String = if (n == 1) "Mati se va a enterar de este logro." else "Mati se va a enterar de estos logros."

    const val CONTARLE = "Contarle a Mati"
    const val SEGUIR = "Seguir"
    const val PERMISO_TITULO = "¿Compartir tus logros con Mati?"
    val PERMISO_CUERPO = listOf(
        "Cuando logres un récord o una racha de pasos, Mati lo va a ver y lo puede compartir con el equipo de Pump Team.",
        "Se comparte tu nombre, el ejercicio y la marca. Nunca tus fotos, tu peso ni tus datos de salud.",
        "Lo podés desactivar cuando quieras en Mis datos. Lo ya compartido no se puede borrar.",
    )
    const val PERMISO_SI = "Sí, compartir"
    const val PERMISO_NO = "Ahora no"
    const val AJUSTE_SECCION = "Logros"
    const val AJUSTE_INTERRUPTOR = "Compartir mis logros con Mati"
    const val AJUSTE_PIE = "Mati ve tus récords y tus rachas de pasos, y los puede compartir con el equipo de Pump Team. Nunca tus fotos, tu peso ni tus datos de salud."
    const val DESACTIVADO = "Listo, no se comparte nada más."
    const val SIN_RED = "No se pudo guardar. Probá de nuevo cuando tengas conexión."
    const val DEMO = "En la demo no se envía nada."
    const val RACHA_CON_PERMISO = "Mati se va a enterar de esta racha."

    /** La versión del texto del permiso que acepta el alumno (`p_version`). */
    const val PERMISO_VERSION = 1

    // ── Racha de pasos ──

    val HITOS_RACHA = listOf(7, 14, 21, 30, 60, 90, 120, 180, 365)
    fun esHito(dias: Int): Boolean = dias in HITOS_RACHA

    /** `p_datos` de un `racha_pasos`. */
    fun datosRacha(dias: Int, meta: Int): ValorJson =
        ValorJson.objeto("dias" to ValorJson.Numero(dias.toDouble()), "meta" to ValorJson.Numero(meta.toDouble()))
}
