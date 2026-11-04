package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.RegistroHistorico
import java.time.ZoneId

/**
 * La línea de la tarjeta «Tu progreso» de Revisión (2.1.0, aprobada por Mati el 4-nov): lo más útil de la semana en una
 * frase. Mira los últimos 7 días (hoy incluido) y, por ejercicio, su última sesión contra las anteriores (el máximo de kg
 * por día, como Progreso). En orden: récords, ejercicios que subieron, sesiones entrenadas; sin nada, null y la tarjeta
 * dice lo genérico. Gemelo de ProgresoSemana.swift; los vectores, en `apps/shared/vectores/progreso_semana.json`.
 */
object ProgresoSemana {
    data class Ejercicio(
        val nombre: String,
        /** Fecha local ("YYYY-MM-DD") → máximo de kg de ese día. */
        val sesiones: Map<String, Double>,
    )

    /** Las sesiones de un ejercicio desde su historial (un peso nulo cuenta como 0, como `ProgresoEjercicio`). */
    fun ejercicio(nombre: String, filas: List<RegistroHistorico>, zona: ZoneId = ZoneId.systemDefault()): Ejercicio {
        val porFecha = mutableMapOf<String, Double>()
        for (f in filas) {
            val fecha = HistorialEntreno.fechaLocal(f.registradoEn, zona)
            if (fecha.isEmpty()) continue
            porFecha[fecha] = maxOf(porFecha[fecha] ?: 0.0, f.pesoKg ?: 0.0)
        }
        return Ejercicio(nombre, porFecha)
    }

    /** El texto va sin emojis (la voz de Mati con el cliente): el trofeo lo pone la tarjeta como ícono si [record]. */
    data class Linea(val texto: String, val record: Boolean)

    fun linea(ejercicios: List<Ejercicio>, hoy: String): Linea? {
        val n = DiaCalendario.numero(hoy) ?: return null
        val semana = (0 until 7).map { DiaCalendario.texto(n - it) }.toSet()
        val records = mutableListOf<Pair<String, Double>>()
        val subieron = mutableListOf<String>()
        val dias = mutableSetOf<String>()

        for (e in ejercicios) {
            val fechas = e.sesiones.keys.filter { DiaCalendario.numero(it) != null }.sorted()
            dias += fechas.filter { it in semana }
            val ultima = fechas.lastOrNull() ?: continue
            val kg = e.sesiones[ultima] ?: continue
            if (ultima !in semana || !kg.isFinite() || kg <= 0) continue
            val anteriores = fechas.dropLast(1).mapNotNull { e.sesiones[it] }.filter { it.isFinite() }
            val previa = anteriores.lastOrNull() ?: continue
            if (kg > (anteriores.maxOrNull() ?: 0.0)) records += e.nombre to kg
            else if (kg > previa) subieron += e.nombre
        }

        when {
            records.size == 1 -> return Linea("Récord en ${records[0].first}, ${kilos(records[0].second)} kg", record = true)
            records.size == 2 -> return Linea("2 récords esta semana, en ${records[0].first} y ${records[1].first}", record = true)
            records.size >= 3 ->
                return Linea("${records.size} récords esta semana, en ${records[0].first}, ${records[1].first} y ${records.size - 2} más", record = true)
        }
        when {
            subieron.size == 1 -> return Linea("Subiste en ${subieron[0]} esta semana", record = false)
            subieron.size >= 2 -> return Linea("Subiste en ${subieron.size} ejercicios esta semana", record = false)
        }
        return when (dias.size) {
            0 -> null
            1 -> Linea("1 sesión entrenada esta semana", record = false)
            else -> Linea("${dias.size} sesiones entrenadas esta semana", record = false)
        }
    }

    /** 82.5 → "82,5"; 80 → "80"; hasta dos decimales. */
    fun kilos(kg: Double): String {
        val centesimos = Math.round(kg * 100)
        val entero = centesimos / 100
        val resto = centesimos % 100
        if (resto == 0L) return "$entero"
        return if (resto % 10 == 0L) "$entero,${resto / 10}" else "$entero,${resto.toString().padStart(2, '0')}"
    }
}
