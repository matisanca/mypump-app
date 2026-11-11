package com.pumpteam.mypump.datos

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** `metas_pasos`, `novedades_plan` y `chat_adjuntos` recuerdan su último valor sin red, como en iOS (`PalancaRemota.arranque`). */
class PalancasRecordadasTest {
    // ── Palancas recordadas (metas_pasos, novedades_plan, chat_adjuntos) ──

    @Test fun lasTresPalancasRecuerdanSuUltimoValorSinRed() = enUnHilo { alcance ->
        val r = carpetaTemporal("palancas-recordadas")
        val t = "PPPPPPPPPPPPPPPPPPPP"
        var config: String? = """{"metas_pasos":true,"novedades_plan":true,"chat_adjuntos":true}"""
        val adjuntosEstado = mutableListOf<String>()
        val tr = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_dieta_activa" -> 200 to """[{"id":"d1","version":1,"estructura":${MetasModeloTest.CON_METAS}}]"""
                "mypump_get_app_config" -> config?.let { 200 to it } ?: (503 to "{}")
                "mypump_chat_adjuntos_estado" -> {
                    adjuntosEstado += fn
                    200 to """{"habilitado":true,"audio_max_s":120}"""
                }
                else -> 200 to "[]"
            }
        }
        fun app() = ModeloApp(ClienteRpc(transporte = tr), TokenEnMemoria(t), r, PreferenciasEnMemoria(), alcance)

        // Nunca leídas: apagadas, aunque no haya red.
        config = null
        val nunca = app()
        nunca.cargar()
        assertFalse(nunca.palanca.value.metasPasos || nunca.palanca.value.novedadesPlan || nunca.palanca.value.chatAdjuntos)
        assertNull(nunca.metas())
        assertTrue(adjuntosEstado.isEmpty())

        // Con red, prendidas: quedan en el disco de la cuenta.
        config = """{"metas_pasos":true,"novedades_plan":true,"chat_adjuntos":true}"""
        val conRed = app()
        conRed.cargar()
        assertTrue(conRed.palanca.value.metasPasos && conRed.palanca.value.novedadesPlan && conRed.palanca.value.chatAdjuntos)
        assertEquals(10000, conRed.metas()?.metaPasos)
        assertTrue(conRed.chat.value!!.adjuntosActivos.value)

        // Sin red al arrancar: lo último que se leyó.
        config = null
        val sinRed = app()
        sinRed.cargar()
        assertTrue(sinRed.palanca.value.metasPasos, "metas_pasos recordada")
        assertTrue(sinRed.palanca.value.novedadesPlan, "novedades_plan recordada")
        assertTrue(sinRed.palanca.value.chatAdjuntos, "chat_adjuntos recordada")
        assertEquals(10000, sinRed.metas()?.metaPasos, "el Pump del día no desaparece sin red")
        assertTrue(sinRed.chat.value!!.adjuntosActivos.value, "los adjuntos siguen como la última vez")

        // Se apagan con red: sin red siguen apagadas.
        config = """{"metas_pasos":false,"novedades_plan":false,"chat_adjuntos":false}"""
        app().cargar()
        config = null
        val apagadas = app()
        apagadas.cargar()
        assertFalse(apagadas.palanca.value.metasPasos || apagadas.palanca.value.novedadesPlan || apagadas.palanca.value.chatAdjuntos)
        assertNull(apagadas.metas())
        assertFalse(apagadas.chat.value!!.adjuntosActivos.value)

        // Otra cuenta del teléfono no hereda lo de esta.
        config = """{"metas_pasos":true,"novedades_plan":true,"chat_adjuntos":true}"""
        app().cargar()
        config = null
        val otra = ModeloApp(ClienteRpc(transporte = tr), TokenEnMemoria("QQQQQQQQQQQQQQQQQQQQ"), r, PreferenciasEnMemoria(), alcance)
        otra.cargar()
        assertFalse(otra.palanca.value.metasPasos || otra.palanca.value.novedadesPlan || otra.palanca.value.chatAdjuntos)
    }
}
