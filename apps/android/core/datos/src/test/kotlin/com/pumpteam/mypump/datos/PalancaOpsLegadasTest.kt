package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 2 (gemelo de PalancaOpsLegadasTests.swift): con la palanca remota `migracion_ops_legadas`
 * apagada (el freno de emergencia de la migración, `nativa_001`), las ops que la Fase L deja directo en la cola (hábitos,
 * chat, peso, check, comidas, swaps y series con sesión) salían igual en la primera carga: la palanca solo frenaba la Fase R.
 */
class PalancaOpsLegadasTest {
    private val raiz = carpetaTemporal("palanca")

    /** Lo que contesta `mypump_get_app_config` (la regla del transporte corre fuera del hilo del test). */
    private class Palanca(@Volatile var prendida: Boolean)

    /** Una op de hábito de la cola vieja, como la deja la Fase L (`importarEnArchivo`) en la cola de la cuenta. */
    private fun sembrarOpVieja() {
        val vieja = Operacion(
            "cap-1", "habito", ValorJson.objeto("fecha" to texto("2026-10-14"), "campo" to texto("agua"), "valor" to numero(3)),
            "habito_2026-10-14_agua", ts = 1_000.0,
        )
        val quedaron = Outbox.importarEnArchivo(Disco(raiz, TOKEN).archivo("outbox.json"), listOf(vieja))
        assertEquals(true, quedaron.first().legado, "la Fase L la marca como de la Capacitor")
    }

    private fun modelo(palanca: Palanca, alcance: CoroutineScope): Pair<ModeloApp, TransporteProgramado> {
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_app_config" -> 200 to """{"migracion_ops_legadas":${palanca.prendida}}"""
                "mypump_set_habito" -> 200 to "true"
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance) to t
    }

    private fun TransporteProgramado.habitos(): Int = llamadas.count { it == "mypump_set_habito" }

    @Test
    fun conLaPalancaApagadaLaOpViejaNoSaleYAlPrenderlaSale() = enUnHilo { alcance ->
        sembrarOpVieja()
        val palanca = Palanca(prendida = false)
        val (m, t) = modelo(palanca, alcance)
        // Antes de leer la palanca (un toque antes de la primera carga) tampoco sale.
        m.outbox?.drenar()
        assertFalse("mypump_set_habito" in t.llamadas, "salió antes de leer la palanca")
        m.cargar()
        assertFalse("mypump_set_habito" in t.llamadas, "salió con la palanca apagada")
        assertEquals(1, m.outbox?.pendientes(), "quedó guardada en la cola")

        // Una escritura nativa sale igual, y la vieja sigue retenida.
        m.outbox?.encolar(
            "habito", ValorJson.objeto("fecha" to texto("2026-10-15"), "campo" to texto("entreno"), "valor" to texto("entrene")),
            "habito_2026-10-15_entreno",
        )
        m.outbox?.drenar()
        assertEquals(1, t.habitos())
        assertEquals(listOf("cap-1"), m.outbox?.operaciones()?.map { it.id })

        // Se vuelve a prender: en la próxima carga sale.
        palanca.prendida = true
        m.cargar()
        m.outbox?.drenar()
        assertEquals(2, t.habitos())
        assertEquals(0, m.outbox?.pendientes())
    }

    @Test
    fun conLaPalancaPrendidaSaleEnLaPrimeraCarga() = enUnHilo { alcance ->
        sembrarOpVieja()
        val (m, t) = modelo(Palanca(prendida = true), alcance)
        m.cargar()
        assertTrue("mypump_set_habito" in t.llamadas)
        assertEquals(0, m.outbox?.pendientes())
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
    }
}
