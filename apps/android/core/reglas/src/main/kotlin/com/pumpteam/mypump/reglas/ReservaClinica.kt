package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.Progresion

/**
 * Reserva clínica (19/11, OK de Mati). Todo va al fallo, salvo el plan que deja reps en reserva a propósito (cardiopatía,
 * lumbar, competencia: lo decide Mati y el servidor lo publica en el rir de la pauta). Con reserva clínica la app NUNCA dice
 * «Al fallo», «llevá al fallo» ni «Subí la carga», no sugiere subir y en lugar de la nota automática de progresión muestra
 * la pauta del plan. Sin reserva, todo igual.
 *
 * Fuente única: el rir de cada semana de la progresión ([Pauta.rir]), el mismo campo que ya lee [TextoAlumno.conReserva],
 * con dos diferencias a propósito:
 * - cuenta solo un rango sin el 0 («2-3», «1-2», «3»): «0-1» deja llegar al fallo y es el de los planes viejos y de la
 *   semana 1 del generador;
 * - es del alumno, no del ejercicio: alcanza un ejercicio con reserva en la semana que se muestra o en una posterior (el
 *   taper con rir vacío entre semanas con reserva no vuelve al fallo, ni los ejercicios sin rir de ese plan). Las semanas
 *   ya pasadas no cuentan: son las rampas viejas de las semanas 1 a 3.
 *
 * La demo no es el plan de un alumno: queda como siempre (lo resuelve `ModeloEntreno.reservaClinica`).
 * Gemelos: `reservaIndicada`/`reservaClinicaDelPlan`/`notaReserva` de `public/js/reglas-entreno.js` (web) y
 * `ReservaClinica.swift`. Vectores: `apps/shared/vectores/reserva_clinica.json`.
 */
object ReservaClinica {
    private val numero = Regex("""\d+([.,]\d+)?""")
    // Un número o un rango: «2-3», «2 – 3», «2—3», «2 a 3», «2 o 3». [\s\u00A0]: el \s de Java no agarra el espacio duro y
    // el de la web y Swift sí.
    private val rango = Regex("""\d+([.,]\d+)?(([\s\u00A0]*[-–—][\s\u00A0]*|[\s\u00A0]+[ao][\s\u00A0]+)\d+([.,]\d+)?)?""")
    private val rpe = Regex("rpe", RegexOption.IGNORE_CASE)

    /** ¿Este rir pide reserva? Todos los números del primer rango mayores que 0 («2-3», «3», «1,5-2»), y no es RPE. */
    fun indicada(rir: String?): Boolean {
        if (rir == null || rpe.containsMatchIn(rir)) return false
        val r = rango.find(rir)?.value ?: return false
        val numeros = numero.findAll(r).mapNotNull { it.value.replace(',', '.').toDoubleOrNull() }.toList()
        return numeros.isNotEmpty() && numeros.all { it > 0 }
    }

    /**
     * ¿El plan tiene reserva clínica en la semana que se muestra o en una posterior? [dias]: todos los del plan. La semana
     * se acota como [Progresiones.pauta] (pasada la última, la última); sin progresión, `rir_objetivo ?? rir`.
     */
    fun delPlan(dias: List<Dia>, semana: Int?): Boolean {
        val sem = Progresiones.semanaJs(semana)
        for (d in dias) for (b in d.bloques) for (e in b.ejercicios) {
            if (e.progresion.isNotEmpty()) {
                val desde = maxOf(0, minOf(sem - 1, e.progresion.size - 1))
                if ((desde until e.progresion.size).any { indicada(e.progresion[it].rir) }) return true
            } else if (indicada(e.rirObjetivo ?: e.rirSuelto)) {
                return true
            }
        }
        return false
    }

    /** La leyenda con reserva: la de esa semana («Dejando 2 a 3 en reserva»); sin número, ninguna. Nunca «Al fallo». */
    fun leyenda(rir: String?): String? = RirDelPlan.leyenda(rir).takeIf { it != "Al fallo" }

    /** La leyenda dentro de una frase: « dejando 2 a 3 en reserva»; sin leyenda, nada. */
    internal fun frase(l: String?): String =
        if (l == null) "" else " " + (if (l == "Al fallo") "al fallo" else l.replaceFirstChar { it.lowercase() })

    /** Un reps vacío o de puro relleno («—», «-», «.») no es pauta; «∞» sí (`rellenoRE` de la web). */
    private val relleno = Regex("""^[\s\u00A0\-–—_.·]*$""")
    private fun conTexto(s: String) = !relleno.matches(s)

    /**
     * La pauta como la ve el alumno: «3×10», «10 min» (sin series) o null. Nunca un guion de relleno en pantalla. La usan
     * [nota] y [Progresiones.nota] (gemelo de `pautaVisible` de la web).
     */
    internal fun pautaVisible(series: Int?, reps: String?): String? {
        val r = reps?.trim()?.takeIf { conTexto(it) } ?: return null
        return series?.let { "$it×$r" } ?: r
    }

    /**
     * En lugar de la nota automática de progresión, la pauta del plan: «Seguí la pauta de esta semana (3×10), dejando 2 a 3
     * en reserva.». Una pauta sin números («No va esta semana») va tal cual. Sin pauta ni reserva (reps «—» y rir vacío),
     * ninguna nota: null (nunca «—.»). Nunca `cambia` (sin cartel de cambio); [calibracion] es la semana sin anterior,
     * como en [Progresiones.nota].
     */
    fun nota(p: Progresion, calibracion: Boolean): NotaProgresion? {
        val reps = p.reps?.trim()?.takeIf { conTexto(it) }
        val texto = if (reps != null && p.series == null && reps.none { it in '0'..'9' }) {
            val fin = if (reps.endsWith(".") || reps.endsWith("!") || reps.endsWith("?")) "" else "."
            reps.replaceFirstChar { it.uppercase() } + fin
        } else {
            val pauta = pautaVisible(p.series, reps)
            val reserva = frase(leyenda(p.rir))
            if (pauta == null && reserva.isEmpty()) return null
            "Seguí la pauta de esta semana${pauta?.let { " ($it)" } ?: ""}${if (reserva.isEmpty()) "" else ",$reserva"}."
        }
        return NotaProgresion(texto, cambia = false, calibracion = calibracion)
    }
}
