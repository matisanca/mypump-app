package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.MensajeChat
import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.EstadoDevolucion
import com.pumpteam.mypump.reglas.FechaJs
import com.pumpteam.mypump.reglas.MetasPlan
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters

/**
 * El historial INVENTADO de la demo sin cuenta («Ver demo», la que mira la revisión de las tiendas; gemelo de
 * HistorialDemo.swift): ocho semanas de un alumno que no existe, de `apps/shared/demo/historial.json` (lo genera
 * `scripts/nativa/generar-demo-historial.py`), que la app trae empaquetado. Los `dia` son relativos a hoy (0 = hoy,
 * -1 = ayer): acá se convierten a fechas locales, así el historial nunca queda viejo. Nada de esto viaja ni se escribe, y
 * nunca se mezcla con una cuenta: solo con `esDemo`.
 */
class HistorialDemo private constructor(
    /** Las series por la clave del ejercicio, de la más nueva a la más vieja (como las da `get_historico_por_clave`). */
    val porClave: Map<String, List<RegistroHistorico>>,
    /** El peso (`peso_kg`) y los pasos por día, con la forma de `mypump_get_salud`. */
    val salud: List<FilaSalud>,
    /** El chat con Mati (`autor: coach` = Mati), del más viejo al más nuevo. */
    val chat: List<MensajeChat>,
    /** Las metas del plan de la demo (pasos por día y ritmo de peso). */
    val metas: MetasPlan?,
    /** Las devoluciones de Mati (`semanas_atras: 1` = el lunes de la semana pasada). */
    val devoluciones: EstadoDevolucion?,
    /** La respuesta de `mypump_lista_previa` de la demo, tal cual. */
    val listaPrevia: ValorJson?,
) {
    /** Todas las series, sin agrupar. */
    val historial: List<RegistroHistorico> get() = porClave.values.flatten()

    companion object {
        private val ISO: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssxxx")

        /** null si el archivo no es un objeto JSON. Lo que no se entiende de adentro (una fila rota) se saltea. */
        fun desde(json: String, ahora: Instant = Instant.now(), zona: ZoneId = ZoneId.systemDefault()): HistorialDemo? {
            val raiz = try {
                ValorJson.parsear(json) as? ValorJson.Objeto
            } catch (_: Exception) {
                null
            } ?: return null
            val hoy = ahora.atZone(zona).toLocalDate()
            fun lista(j: ValorJson?): List<ValorJson> = (j as? ValorJson.Lista)?.elementos ?: emptyList()
            fun entero(j: ValorJson?): Int? = j?.comoNumero?.takeIf { it.isFinite() && it == Math.rint(it) && Math.abs(it) < 100_000 }?.toInt()
            fun fecha(dia: Int): LocalDate = hoy.plusDays(dia.toLong())

            /** El instante de un día relativo a una hora «HH:MM» local (más unos minutos), en ISO con la zona del teléfono. */
            fun instante(dia: Int, hora: String?, masMinutos: Int = 0): String? {
                val p = (hora ?: "12:00").split(":").mapNotNull { it.toIntOrNull() }
                if (p.size != 2 || p[0] !in 0..23 || p[1] !in 0..59) return null
                return fecha(dia).atTime(LocalTime.of(p[0], p[1])).atZone(zona).plusMinutes(masMinutos.toLong()).format(ISO)
            }

            // Entreno: una fila por serie.
            val porClave = LinkedHashMap<String, MutableList<RegistroHistorico>>()
            for (e in lista(raiz["entreno"])) {
                val nombre = e["nombre"]?.comoTexto ?: continue
                val clave = ClaveEjercicio.de(nombre)
                if (clave.isEmpty()) continue
                val id = e["ejercicio_id"]?.comoTexto
                for (s in lista(e["sesiones"])) {
                    val dia = entero(s["dia"])?.takeIf { it < 0 } ?: continue   // hoy no hay sesión: lo de hoy lo carga quien mira
                    lista(s["series"]).forEachIndexed { i, serie ->
                        val kg = serie["kg"]?.comoNumero?.takeIf { it.isFinite() } ?: return@forEachIndexed
                        val reps = entero(serie["reps"]) ?: return@forEachIndexed
                        val cuando = instante(dia, s["hora"]?.comoTexto, 3 * i) ?: return@forEachIndexed
                        porClave.getOrPut(clave) { mutableListOf() } += RegistroHistorico(
                            clave = clave, ejercicioId = id, registradoEn = cuando, pesoKg = kg, reps = reps, rir = null, serie = i + 1,
                            notas = null, ejercicioNombre = nombre,
                        )
                    }
                }
            }
            // De la más nueva a la más vieja; dentro del día, en el orden de las series.
            val ordenado = porClave.mapValues { (_, filas) ->
                filas.sortedWith(compareByDescending<RegistroHistorico> { it.registradoEn.take(10) }.thenBy { it.serie ?: 0 })
            }

            // Salud: peso y pasos por día.
            val salud = mutableListOf<FilaSalud>()
            for (p in lista(raiz["peso"])) {
                val dia = entero(p["dia"])?.takeIf { it <= 0 } ?: continue
                val kg = p["kg"]?.comoNumero?.takeIf { it.isFinite() } ?: continue
                salud += FilaSalud(fecha(dia).toString(), "peso_kg", kg, "manual", null)
            }
            for (p in lista(raiz["pasos"])) {
                val dia = entero(p["dia"])?.takeIf { it <= 0 } ?: continue
                val n = p["pasos"]?.comoNumero?.takeIf { it.isFinite() } ?: continue
                salud += FilaSalud(fecha(dia).toString(), "pasos", n, "health_connect", null)
            }

            // Chat.
            val chat = lista(raiz["chat"]).mapIndexedNotNull { i, m ->
                val dia = entero(m["dia"])?.takeIf { it <= 0 } ?: return@mapIndexedNotNull null
                val texto = m["texto"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return@mapIndexedNotNull null
                val autor = m["autor"]?.comoTexto?.takeIf { it == "coach" || it == "cliente" } ?: return@mapIndexedNotNull null
                val cuando = instante(dia, m["hora"]?.comoTexto) ?: return@mapIndexedNotNull null
                MensajeChat("demo-${i + 1}", autor, texto, leidoPorCliente = true, createdAt = cuando)
            }.sortedBy { FechaJs.leer(it.createdAt) ?: Instant.MIN }

            // Metas del plan.
            val metas = MetasPlan(entero(raiz["metas"]?.get("meta_pasos_dia")), raiz["metas"]?.get("ritmo_peso_kg_semana")?.comoNumero).takeIf { !it.vacio }

            // Devoluciones: la semana que comenta y el lunes siguiente como día de publicación.
            val lunes = hoy.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
            val devs = lista(raiz["devoluciones"]).mapIndexedNotNull { i, d ->
                val atras = entero(d["semanas_atras"])?.takeIf { it >= 1 } ?: return@mapIndexedNotNull null
                val texto = d["texto"]?.comoTexto ?: return@mapIndexedNotNull null
                ValorJson.objeto(
                    "id" to ValorJson.Texto("demo-${i + 1}"), "semana_lunes" to ValorJson.Texto(lunes.minusWeeks(atras.toLong()).toString()),
                    "texto" to ValorJson.Texto(texto),
                    "publicado_en" to ValorJson.Texto(lunes.minusWeeks(atras - 1L).toString() + "T14:00:00Z"),
                )
            }
            val devoluciones = if (devs.isEmpty()) null else EstadoDevolucion.desde(
                ValorJson.objeto("habilitado" to ValorJson.Booleano(true), "devoluciones" to ValorJson.Lista(devs)),
            )

            return HistorialDemo(ordenado, salud, chat, metas, devoluciones, raiz["lista_previa"])
        }
    }
}
