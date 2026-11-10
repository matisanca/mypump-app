package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.IOException
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

/**
 * El servidor de la devolución de mentira: contesta `mypump_devolucion_get` y la palanca. Lo usan las pruebas JVM y las de
 * interfaz (este directorio se suma a sus fuentes: nunca va en la app). Nunca toca la red. Textos inventados.
 * Gemelo de DobleDevolucion.swift.
 */
class DobleDevolucion : Transporte {
    @Volatile var palanca = true
    @Volatile var habilitado = true
    @Volatile var sinFuncion = false
    @Volatile var tokenCaido = false
    @Volatile var sinRed = false
    @Volatile var devoluciones: List<ValorJson> = emptyList()
    val llamadas = java.util.concurrent.CopyOnWriteArrayList<String>()
    val llamadasDevolucion: List<String> get() = llamadas.filter { it.startsWith("mypump_devolucion") }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val f = pedido.ruta.substringAfterLast('/')
        llamadas += f
        if (sinRed) throw IOException("sin red (doble)")
        val (status, cuerpo) = when (f) {
            "mypump_get_app_config" -> 200 to """{"devolucion_semanal":$palanca}"""
            "mypump_devolucion_get" -> when {
                sinFuncion -> 404 to """{"code":"PGRST202","message":"no existe"}"""
                tokenCaido -> 200 to "null"
                !habilitado || !palanca -> 200 to """{"habilitado":false}"""
                else -> 200 to ValorJson.objeto("habilitado" to ValorJson.Booleano(true), "devoluciones" to ValorJson.Lista(devoluciones)).serializar()
            }
            else -> 200 to "[]"
        }
        return Respuesta(status, cuerpo.toByteArray())
    }

    companion object {
        const val TEXTO_ULTIMA = "Muy buena semana, cumpliste las cuatro sesiones y el peso bajó medio kilo.\n" +
            "En sentadilla subiste dos kilos y mantuviste las repeticiones, eso es progreso real.\n" +
            "Esta semana enfocate en llegar a los pasos todos los días.\n" +
            "Seguí así que vas muy bien."
        const val TEXTO_ANTERIOR = "Semana firme, entrenaste las cinco veces.\nLa dieta la cumpliste casi entera, bien ahí.\n" +
            "Para esta, sumá una fruta en la merienda."
        const val TEXTO_VIEJA = "Volviste después de una semana floja y se nota la intención.\n" +
            "El press inclinado subió una repetición en cada serie.\nEnfocate en dormir un poco más."

        /** `dos` (la última y dos anteriores), `una`, `vacio`, `apagado`, `noHabilitado`, `sinServidor`, `sinRed`. */
        fun escenario(nombre: String, hoy: LocalDate = LocalDate.now()): DobleDevolucion {
            val d = DobleDevolucion()
            val lunes = hoy.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
            fun fila(id: String, atras: Long, texto: String) = ValorJson.objeto(
                "id" to ValorJson.Texto(id), "semana_lunes" to ValorJson.Texto(lunes.minusWeeks(atras).toString()),
                "texto" to ValorJson.Texto(texto),
                "publicado_en" to ValorJson.Texto((if (atras == 0L) hoy else lunes.minusWeeks(atras - 1)).toString() + "T14:00:00Z"),
            )
            when (nombre) {
                "una" -> d.devoluciones = listOf(fila("d1", 0, TEXTO_ULTIMA))
                "vacio" -> {}
                "apagado" -> d.palanca = false
                "noHabilitado" -> d.habilitado = false
                "sinServidor" -> d.sinFuncion = true
                "sinRed" -> d.sinRed = true
                else -> d.devoluciones = listOf(fila("d1", 0, TEXTO_ULTIMA), fila("d2", 1, TEXTO_ANTERIOR), fila("d3", 2, TEXTO_VIEJA))
            }
            return d
        }
    }
}
