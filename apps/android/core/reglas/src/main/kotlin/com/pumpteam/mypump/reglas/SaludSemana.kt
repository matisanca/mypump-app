package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.RecuperacionDia

/**
 * «Tu salud, últimos 7 días» (2.1.0, pedido de Mati del 4-nov): lo que va con el check de la semana, en Revisión. Los
 * promedios de los últimos 7 días (hoy incluido) de lo que ya está en el servidor: el coach lo ve con su panel
 * (`mypump_get_recuperacion_cliente_coach` y la salud diaria), sin migración. Una fila por dato que tenga al menos un
 * día; sin ninguno, vacío y el bloque no se muestra. Gemelo de SaludSemana.swift; los vectores, en
 * `apps/shared/vectores/salud_semana.json`.
 */
object SaludSemana {
    data class Fila(
        /** recuperacion | sueno | hrv | fc_reposo | pasos */
        val clave: String,
        val etiqueta: String,
        val valor: String,
        /** "promedio de 5 días" | "1 día" */
        val detalle: String,
    )

    /** Los tipos de `mypump_salud_diaria`, en el orden en que se muestran (la recuperación va primero). */
    private val tipos: List<Triple<String, String, String>> = listOf(
        Triple("sueno", "sueno_min", "Sueño"),
        Triple("hrv", "hrv_ms", "Variabilidad (HRV)"),
        Triple("fc_reposo", "fc_reposo", "Pulso en reposo"),
        Triple("pasos", "pasos", "Pasos"),
    )

    /** `mostrarScore` es `mypump_get_mostrar_recuperacion`: si el cliente apagó el número, no se promedia. */
    fun resumen(salud: List<FilaSalud>, recuperacion: List<RecuperacionDia>, hoy: String, mostrarScore: Boolean): List<Fila> {
        val n = DiaCalendario.numero(hoy) ?: return emptyList()
        val fechas = (0 until 7).map { DiaCalendario.texto(n - it) }
        val filas = mutableListOf<Fila>()

        if (mostrarScore) {
            // Un score por fecha (la última fila de esa fecha, si viniera repetida).
            val porFecha = linkedMapOf<String, Int>()
            for (r in recuperacion) if (r.fecha in fechas) r.score?.let { porFecha[r.fecha] = it }
            if (porFecha.isNotEmpty()) {
                val prom = porFecha.values.sum().toDouble() / porFecha.size
                filas += Fila("recuperacion", "Recuperación", "${SaludVista.enteroJS(prom)} de 100", detalle(porFecha.size))
            }
        }

        for ((clave, tipo, etiqueta) in tipos) {
            val vals = fechas.mapNotNull { SaludVista.valor(salud, tipo, it) }.filter { it > 0 && it.isFinite() }
            if (vals.isEmpty()) continue
            val prom = vals.sum() / vals.size
            val valor = when (clave) {
                "sueno" -> SaludVista.horas(prom)
                "hrv" -> "${SaludVista.enteroJS(prom)} ms"
                "fc_reposo" -> "${SaludVista.enteroJS(prom)} lpm"
                else -> "${SaludVista.miles(prom)} por día"
            }
            filas += Fila(clave, etiqueta, valor, detalle(vals.size))
        }
        return filas
    }

    private fun detalle(dias: Int): String = if (dias == 1) "1 día" else "promedio de $dias días"
}
