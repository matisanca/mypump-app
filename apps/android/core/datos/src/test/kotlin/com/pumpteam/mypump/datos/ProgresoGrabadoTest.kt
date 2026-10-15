package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ProgresoEjercicio
import java.util.TimeZone
import java.util.concurrent.atomic.AtomicReference
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * PRO-01 y PRO-02 en la JVM, con las respuestas grabadas de la cuenta de prueba (`apps/shared/fixtures/test-nativa-real`:
 * la rutina de 4 días y las 384 filas de `get_historico_por_clave`). Hasta ahora solo lo veía la integración, que
 * necesita el registro privado de cuentas. Las sesiones son días locales: se leen en Buenos Aires.
 */
class ProgresoGrabadoTest {
    private val historial = Compartido.texto("fixtures/test-nativa-real/get_historico_por_clave.json")
    private val rutina = RutinaActiva.desde(
        ValorJson.parsear(Compartido.texto("fixtures/test-nativa-real/get_rutina_activa.json")).primeraFila!!.aJson(),
    )

    @Test
    fun lasTarjetasDelHistorialGrabado() = enUnHilo {
        val zona = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("America/Argentina/Buenos_Aires"))
        try {
            // Las claves que pidió (la regla del transporte corre en otro hilo).
            val pedidas = AtomicReference<List<String>>(emptyList())
            val t = TransporteProgramado { fn, cuerpo ->
                if (fn == "mypump_get_historico_por_clave") {
                    (cuerpo["p_claves"] as? ValorJson.Lista)?.let { l -> pedidas.set(l.elementos.mapNotNull { it.comoTexto }) }
                    200 to historial
                } else {
                    200 to "[]"
                }
            }
            val p = ModeloProgreso(ClienteRpc(transporte = t), "tok")
            p.cargar(rutina)
            assertEquals(ModeloProgreso.Estado.LISTO, p.estado.value)
            // UN pedido, con una clave por ejercicio del plan: los que están en dos días no se repiten.
            assertEquals(listOf("mypump_get_historico_por_clave"), t.llamadas)
            assertEquals(33, pedidas.get().size)
            assertEquals(33, pedidas.get().toSet().size)
            // Una tarjeta por clave con historial, en el orden del plan (la cinta de la entrada en calor no tiene).
            val tarjetas = p.tarjetas.value
            assertEquals(pedidas.get() - "cinta 10 min", tarjetas.map { it.clave })
            assertEquals(32, tarjetas.size)
            assertEquals(14, p.sesiones.value)
            // El mismo ejercicio en dos días es UNA tarjeta, con los dos días.
            assertEquals("TIRÓN · PIERNAS", tarjetas.first { it.clave == "rollout con ab wheel" }.dias)
            assertEquals("EMPUJE · TORSO", tarjetas.first { it.clave == "crunch en maquina" }.dias)
            // El resumen: el máximo de cada sesión, el tope, la variación con un decimal y el 🏆 PR.
            val jalon = tarjetas.first { it.clave == "jalon al pecho prono" }
            assertEquals("Jalón al pecho prono (dorsal ancho)", jalon.nombre)
            assertEquals(ProgresoEjercicio.Resumen(listOf(52.0, 54.0, 56.0, 58.0), 58.0, 11.5, true), jalon.resumen)
            assertEquals(13, jalon.filas.size)
            // Sin peso (el core): todo en 0, sin variación ni PR.
            val rollout = tarjetas.first { it.clave == "rollout con ab wheel" }
            assertEquals(ProgresoEjercicio.Resumen(List(7) { 0.0 }, 0.0, null, false), rollout.resumen)
            assertTrue(tarjetas.all { it.resumen.serie.size <= 8 && it.dias.isNotEmpty() })
            // Lo traído queda para Entreno (última vez y récord).
            assertEquals(32, p.historialPorClave.value.size)

            // Sin red avisa y no deja tarjetas viejas mezcladas.
            val offline = ModeloProgreso(ClienteRpc(transporte = SinRed), "x")
            offline.cargar(rutina)
            assertEquals(ModeloProgreso.Estado.SIN_RED, offline.estado.value)
            assertTrue(offline.tarjetas.value.isEmpty())
        } finally {
            TimeZone.setDefault(zona)
        }
    }
}
