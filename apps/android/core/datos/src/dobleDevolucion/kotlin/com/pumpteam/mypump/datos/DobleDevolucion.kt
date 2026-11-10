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
        const val TEXTO_ULTIMA = "las 4 sesiones hechas, de lujo\n" +
            "sentadilla 2kg arriba con las mismas repes\n" +
            "y el peso 500g abajo\n" +
            "esta semana enfocate en llegar a los pasos todos los días"
        const val TEXTO_ANTERIOR = "entrenaste las 5 veces, muy bien\n" +
            "la dieta casi entera\n" +
            "para esta sumale una fruta a la merienda"
        const val TEXTO_VIEJA = "bien que volviste después de la semana floja\n" +
            "el press inclinado una repe más en cada serie\n" +
            "como venis durmiendo?"

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
