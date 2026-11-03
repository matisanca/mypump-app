package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.VolumenMusculo
import com.pumpteam.mypump.reglas.de
import java.time.Instant
import java.time.ZoneId

/**
 * Volumen por músculo (2.1, S2) con lo que ya tiene la app: el historial de Progreso (las filas por clave del ejercicio
 * que se hace, hasta 48 por clave: alcanzan para esta semana y la pasada) y, si hoy ya hay series confirmadas en el
 * teléfono, esas en lugar de las del historial de hoy. La regla de conteo es la del kit ([VolumenMusculo]). Gemelo de
 * Volumen.swift.
 */
object VolumenDatos {
    /** Lo que se sabe de cada clave del plan: el músculo (la cadena de E1) y el tipo del ejercicio que se hace. */
    data class Info(val musculo: String?, val tipo: String?)

    /**
     * Las filas del historial como registros. Cada fila es una serie distinta (el servidor guarda una por sesión,
     * ejercicio y número; la RPC por clave no trae `ejercicio_id`): van sin número, así ninguna se descarta como repetida.
     * Una clave que ya no está en el plan queda sin músculo.
     */
    fun registros(
        historial: Map<String, List<RegistroHistorico>>,
        ejercicios: Map<String, Info>,
        zona: ZoneId = ZoneId.systemDefault(),
    ): List<VolumenMusculo.Registro> =
        historial.keys.sorted().flatMap { clave ->
            val e = ejercicios[clave]
            historial[clave].orEmpty().map { VolumenMusculo.Registro(e?.musculo, e?.tipo, FechaLocal.de(it.registradoEn, zona), clave, null) }
        }
}

/**
 * El volumen por músculo de esta semana y la pasada. Sin el historial de Progreso cargado (Salud → Fuerza y el cierre del
 * día lo piden), solo lo de hoy en vivo.
 */
fun ModeloApp.volumenPorMusculo(zona: ZoneId = ZoneId.systemDefault(), ahora: Instant = Instant.now()): VolumenMusculo.Resumen {
    val entreno = entreno.value
    val ejercicios = LinkedHashMap<String, VolumenDatos.Info>()
    for (d in rutina.value?.estructura?.dias.orEmpty()) for (b in d.bloques) for (ex in b.ejercicios) {
        val ef = entreno?.efectivo(ex)?.ejercicio ?: ex
        val clave = ClaveEjercicio.de(ef.nombre).ifEmpty { ex.id }
        if (clave !in ejercicios) ejercicios[clave] = VolumenDatos.Info(entreno?.musculo(ex), ef.tipo)
    }
    val historial = VolumenDatos.registros(progreso.value?.historialPorClave?.value.orEmpty(), ejercicios, zona)
    val vivo = entreno?.registrosVolumenHoy.orEmpty()
    return VolumenMusculo.calcular(historial, vivo.ifEmpty { null }, FechaLocal.hoy(ahora, zona))
}
