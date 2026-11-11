package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.FechaLocal
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Gemelo de MetasModeloTests.swift: la palanca `metas_pasos`, la meta de la dieta, los pasos de Salud y la celebración por cuenta. */
class MetasModeloTest {
    private val raiz = carpetaTemporal("metas")

    private fun modelo(palanca: String, dieta: String, pasosHoy: Int, alcance: CoroutineScope): ModeloApp {
        val hoy = FechaLocal.hoy()
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_dieta_activa" -> 200 to """[{"id":"d1","version":1,"estructura":$dieta}]"""
                "mypump_get_app_config" -> 200 to palanca
                "mypump_get_salud" -> 200 to """[{"fecha":"$hoy","tipo":"pasos","valor":$pasosHoy,"fuente":"health_connect"}]"""
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance)
    }

    private suspend fun cargar(m: ModeloApp) {
        m.cargar()
        m.salud.value?.cargar()
    }

    @Test
    fun conLaPalancaApagadaNoHayNada() = enUnHilo { alcance ->
        val m = modelo("""{"metas_pasos":false}""", CON_METAS, 12000, alcance)
        cargar(m)
        assertNull(m.metas())
        assertNull(m.pumpDelDia())
        val sinClave = modelo("{}", CON_METAS, 12000, alcance)
        cargar(sinClave)
        assertNull(sinClave.metas(), "sin la clave, apagada")
    }

    @Test
    fun sinMetaEnElPlanNoSeInventa() = enUnHilo { alcance ->
        val m = modelo("""{"metas_pasos":true}""", """{"macros_target":{"kcal":2000},$COMIDAS}""", 12000, alcance)
        cargar(m)
        assertTrue(m.palanca.value.metasPasos)
        assertNotNull(m.dieta.value)
        assertNull(m.metas())
        assertNull(m.pumpDelDia())
    }

    @Test
    fun celebraUnaVezYSeAcuerdaAlReabrir() = enUnHilo { alcance ->
        val m = modelo("""{"metas_pasos":true}""", CON_METAS, 10400, alcance)
        cargar(m)
        assertEquals(10000, m.metas()?.metaPasos)
        assertEquals(-0.5, m.metas()?.ritmoKgSemana)
        val (v, _) = m.pumpDelDia()!!
        assertTrue(v.cumplido)
        assertEquals(10400, v.pasosHoy)
        assertTrue(m.debeCelebrarPump(v))
        m.marcarPumpCelebrado()
        assertFalse(m.debeCelebrarPump(v))
        val otra = modelo("""{"metas_pasos":true}""", CON_METAS, 10400, alcance)
        cargar(otra)
        val (v2, _) = otra.pumpDelDia()!!
        assertFalse(otra.debeCelebrarPump(v2), "lo celebrado sigue en el disco de la cuenta")
        otra.salir()
        assertTrue(otra.registroMetas.value.celebrados.isEmpty())
    }

    companion object {
        const val TOKEN = "MMMMMMMMMMMMMMMMMMMM"
        const val COMIDAS = """"comidas":[{"id":"d","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7}]}]}]"""
        const val CON_METAS = """{"macros_target":{"kcal":2000},$COMIDAS,"meta_pasos_dia":10000,"ritmo_peso_kg_semana":-0.5}"""
    }
}
