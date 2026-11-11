package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.LocalDate
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit

/** Una devolución publicada de Mati: 3 a 5 líneas sobre la semana. Gemelo de DevolucionSemanal.swift. */
data class DevolucionSemanal(
    val id: String,
    /** AAAA-MM-DD, el lunes de la semana que comenta. */
    val semanaLunes: String,
    val lineas: List<String>,
    /** AAAA-MM-DD de cuando salió (UTC, tal como lo manda el servidor); null si no vino. */
    val publicadaDia: String?,
) {
    val etiqueta: String get() = ReglasDevolucion.etiqueta(semanaLunes)

    companion object {
        fun desde(j: ValorJson): DevolucionSemanal? {
            val id = j["id"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
            val semana = j["semana_lunes"]?.comoTexto?.takeIf { ReglasDevolucion.fecha(it) != null } ?: return null
            val texto = j["texto"]?.comoTexto ?: return null
            val lineas = texto.split("\r\n", "\n", "\r").map { it.trim() }.filter { it.isNotEmpty() }
            if (lineas.isEmpty()) return null
            val publicada = j["publicado_en"]?.comoTexto?.take(10)?.takeIf { ReglasDevolucion.fecha(it) != null }
            return DevolucionSemanal(id, semana, lineas, publicada)
        }
    }
}

/** Lo que muestra Revisión: la última arriba y las anteriores debajo. null: apagada, sin token o sin habilitar. */
data class EstadoDevolucion(val devoluciones: List<DevolucionSemanal>) {
    val ultima: DevolucionSemanal? get() = devoluciones.firstOrNull()
    val anteriores: List<DevolucionSemanal> get() = devoluciones.drop(1)

    companion object {
        const val MAXIMO = 12

        fun desde(j: ValorJson): EstadoDevolucion? {
            if (j["habilitado"] != ValorJson.Booleano(true)) return null
            val validas = (j["devoluciones"] as? ValorJson.Lista)?.elementos?.mapNotNull(DevolucionSemanal::desde) ?: emptyList()
            // Orden estable por semana, de la más nueva a la más vieja; una sola por semana (la primera que vino).
            val lista = validas.sortedByDescending { it.semanaLunes }.distinctBy { it.semanaLunes }
            return EstadoDevolucion(lista.take(MAXIMO))
        }
    }
}

object ReglasDevolucion {
    private val meses = listOf("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
        "noviembre", "diciembre")

    fun fecha(s: String): LocalDate? = if (s.length != 10) null else try { LocalDate.parse(s) } catch (_: DateTimeParseException) { null }

    /** «Semana del 9 de noviembre»; con el año si no es el de hoy. */
    fun etiqueta(semana: String, hoy: String = LocalDate.now().toString()): String {
        val f = fecha(semana) ?: return "Tu semana"
        val anioHoy = fecha(hoy)?.year ?: f.year
        return "Semana del ${f.dayOfMonth} de ${meses[f.monthValue - 1]}" + if (f.year == anioHoy) "" else " de ${f.year}"
    }

    /** Recién llegada: publicada hoy o en los dos días anteriores. */
    fun esNueva(d: DevolucionSemanal, hoy: String = LocalDate.now().toString()): Boolean {
        val p = d.publicadaDia?.let(::fecha) ?: return false
        val h = fecha(hoy) ?: return false
        return ChronoUnit.DAYS.between(p, h) in 0..2
    }
}
