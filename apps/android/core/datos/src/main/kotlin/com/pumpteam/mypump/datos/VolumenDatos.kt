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
 * que se hace, hasta 48 por clave: alcanzan para esta semana y la pasada) y, encima, las series confirmadas en el
 * teléfono que el historial todavía no tiene (puede estar viejo), cada una con su fecha real. La regla de conteo y el
 * cruce son del kit ([VolumenMusculo]). Gemelo de Volumen.swift.
 */
object VolumenDatos {
    /** Lo que se sabe de cada clave del plan: el músculo (la cadena de E1) y el tipo del ejercicio que se hace. */
    data class Info(val musculo: String?, val tipo: String?)

    /**
     * Si una clave que ya se vio con el tipo `ya` pasa a tomar el de un lugar nuevo con tipo `nuevo`: solo si el primero
     * no cuenta (calentamiento o cardio) y el nuevo sí (un lugar de trabajo gana).
     */
    fun esDeTrabajoMejor(ya: String?, nuevo: String?): Boolean {
        fun noCuenta(t: String?) = t != null && t in VolumenMusculo.TIPOS_QUE_NO_CUENTAN
        return noCuenta(ya) && !noCuenta(nuevo)
    }

    /**
     * Las filas del historial como registros. Cada fila es una serie distinta (el servidor guarda una por sesión,
     * ejercicio y número; la RPC por clave no trae `ejercicio_id`) y cuenta siempre; la clave y el número sirven para no
     * sumar de nuevo lo confirmado en vivo. Una clave que ya no está en el plan queda sin músculo.
     */
    fun registros(
        historial: Map<String, List<RegistroHistorico>>,
        ejercicios: Map<String, Info>,
        zona: ZoneId = ZoneId.systemDefault(),
    ): List<VolumenMusculo.Registro> =
        historial.keys.sorted().flatMap { clave ->
            val e = ejercicios[clave]
            historial[clave].orEmpty().map { VolumenMusculo.Registro(e?.musculo, e?.tipo, FechaLocal.de(it.registradoEn, zona), clave, it.serie, clave) }
        }
}

/**
 * El volumen por músculo de esta semana y la pasada. Sin el historial de Progreso cargado (Salud → Fuerza y el cierre del
 * día lo piden), solo lo confirmado en vivo.
 */
fun ModeloApp.volumenPorMusculo(zona: ZoneId = ZoneId.systemDefault(), ahora: Instant = Instant.now()): VolumenMusculo.Resumen {
    val entreno = entreno.value
    val ejercicios = LinkedHashMap<String, VolumenDatos.Info>()
    for (d in rutina.value?.estructura?.dias.orEmpty()) for (b in d.bloques) for (ex in b.ejercicios) {
        val ef = entreno?.efectivo(ex)?.ejercicio ?: ex
        val clave = ClaveEjercicio.de(ef.nombre).ifEmpty { ex.id }
        // La misma clave como calentamiento y como trabajo: gana el de trabajo, o su historial no contaría.
        val ya = ejercicios[clave]
        if (ya == null || VolumenDatos.esDeTrabajoMejor(ya.tipo, ef.tipo)) ejercicios[clave] = VolumenDatos.Info(entreno?.musculo(ex), ef.tipo)
    }
    val historial = VolumenDatos.registros(progreso.value?.historialPorClave?.value.orEmpty(), ejercicios, zona)
    return VolumenMusculo.calcular(historial, entreno?.registrosVolumenEnVivo.orEmpty(), FechaLocal.hoy(ahora, zona))
}
