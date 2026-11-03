package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.RegistroHistorico
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * El aviso de récord apenas se confirma una serie efectiva (2.0.3, E3; gemelo de RecordSerie.swift): «Récord: +2,5 kg» o
 * «Récord: +1 rep». Es el mismo criterio del «Récord a superar» de la card (la serie más pesada,
 * [HistorialEntreno.record]), por serie y no por sesión como el 🏆 PR de Progreso ([ProgresoEjercicio.resumen]). Lo
 * verifican los vectores de `apps/shared/vectores/entreno_203.json`.
 *
 * - Lo mejor anterior es la serie más pesada del historial de días anteriores (misma clave) y, entre las de ese kg, la de
 *   más reps. Las series de hoy ya confirmadas también son piso: el récord que ya se avisó no se repite.
 * - Más kg con al menos 1 rep: «+N kg». El mismo kg que lo mejor con más reps: «+N rep(s)». Menos kg, nada.
 * - Sin historia de días anteriores no hay aviso. Los ejercicios sin kg y las series no verosímiles (las que hubo que
 *   preguntar) no avisan. Las filas con 0 kg no cuentan.
 */
object RecordSerie {
    data class Marca(val kg: Double, val reps: Int)

    data class Aviso(val tipo: Tipo, val delta: Double, val texto: String) {
        enum class Tipo { KG, REPS }
    }

    private const val TOLERANCIA = 1e-6

    fun evaluar(serie: Marca, sinKg: Boolean, verosimil: Boolean, anteriores: List<Marca>, hoy: List<Marca>): Aviso? {
        if (sinKg || !verosimil || serie.reps < 1 || !(serie.kg > 0) || !serie.kg.isFinite()) return null
        val sirve = { m: Marca -> m.kg > 0 && m.kg.isFinite() && m.reps >= 1 }
        val previas = anteriores.filter(sirve)
        if (previas.isEmpty()) return null
        val piso = previas + hoy.filter(sirve)
        val mejorKg = piso.maxOf { it.kg }
        val mejorReps = piso.filter { abs(it.kg - mejorKg) < TOLERANCIA }.maxOfOrNull { it.reps } ?: 0
        if (serie.kg > mejorKg + TOLERANCIA) {
            val d = ((serie.kg - mejorKg) * 100).roundToLong() / 100.0
            return Aviso(Aviso.Tipo.KG, d, "Récord: +${Js.texto(d).replace('.', ',')} kg")
        }
        if (abs(serie.kg - mejorKg) < TOLERANCIA && serie.reps > mejorReps) {
            val n = serie.reps - mejorReps
            return Aviso(Aviso.Tipo.REPS, n.toDouble(), "Récord: +$n rep${if (n == 1) "" else "s"}")
        }
        return null
    }

    /** Las marcas del historial que no son del día [hoy] (YYYY-MM-DD local). */
    fun anteriores(h: List<RegistroHistorico>, hoy: String?, zona: ZoneId): List<Marca> = h.mapNotNull { r ->
        val kg = r.pesoKg ?: return@mapNotNull null
        val reps = r.reps ?: return@mapNotNull null
        if (hoy != null && HistorialEntreno.fechaLocal(r.registradoEn, zona) == hoy) return@mapNotNull null
        Marca(kg, reps)
    }

    /** Una serie del día como marca (los campos son texto, como los tipeó el cliente). */
    fun marca(s: SerieLocal): Marca? {
        val kg = Js.parseFloat(Verosimilitud.primeraComaAPunto(s.kg)) ?: return null
        val reps = Js.parseInt(s.reps)?.takeIf { it.isFinite() } ?: return null
        if (kg.isNaN()) return null
        return Marca(kg, reps.toInt())
    }
}
