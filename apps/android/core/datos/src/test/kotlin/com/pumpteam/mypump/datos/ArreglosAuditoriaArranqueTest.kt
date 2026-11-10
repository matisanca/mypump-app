package com.pumpteam.mypump.datos

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Gemelo de ArreglosAuditoriaArranqueTests.swift. Auditoría del 10/11, F2: con mala señal la app miraba el logo 20 a 40
 * segundos aunque tuviera el plan guardado. Ahora la copia se muestra al toque y se actualiza por detrás.
 */
private const val RUTINA = """{"id":"rut-1","version":1,"semana_actual":3,"tiene_siguiente":false,"estructura":{"semanas_total":12,"dias":[{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":[{"id":"press-d1-0","tipo":"principal","nombre":"Press banca","progresion":[{"semana":1,"series":3,"reps":"8"}]}]}]}]}}"""

class ArreglosAuditoriaArranqueTest {
    private val raiz = carpetaTemporal("arranque-copia")

    private class Lento {
        @Volatile var ms = 0L
    }

    private fun modelo(lento: Lento, alcance: CoroutineScope): ModeloApp {
        val t = TransporteProgramado { fn, _ ->
            if (lento.ms > 0) delay(lento.ms)
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_rutina_activa" -> 200 to "[${RUTINA}]"
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raiz, PreferenciasEnMemoria(), alcance)
    }

    @Test
    fun conCopiaGuardadaSeMuestraSinEsperarAlServidor() = enUnHilo { alcance ->
        val lento = Lento()
        modelo(lento, alcance).cargar()
        lento.ms = 1500
        val m = modelo(lento, alcance)
        val carga = async { m.cargar() }
        delay(200)
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value, "con la copia no se espera al servidor")
        assertEquals("rut-1", m.rutina.value?.id)
        assertFalse(m.desdeCache.value, "mientras se actualiza no se avisa «sin conexión»")
        carga.await()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertFalse(m.desdeCache.value)
    }

    @Test
    fun sinCopiaSigueEsperando() = enUnHilo { alcance ->
        val lento = Lento().apply { ms = 600 }
        val m = modelo(lento, alcance)
        val carga = async { m.cargar() }
        delay(200)
        assertEquals(ModeloApp.Fase.CARGANDO, m.fase.value)
        carga.await()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
    }

    private fun rutinaV(v: Int) = RUTINA.replace("\"version\":1", "\"version\":$v")

    @Test
    fun conLaCopiaViejaElMotorSeRestauraConLaRutinaNueva() = enUnHilo { alcance ->
        var version = 1
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_rutina_activa" -> 200 to "[${rutinaV(version)}]"
                else -> 200 to "[]"
            }
        }
        ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raiz, PreferenciasEnMemoria(), alcance).cargar()
        version = 2
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raiz, PreferenciasEnMemoria(), alcance)
        val antes = t.llamadas.count { it == "mypump_get_sesion_dia" }
        m.cargar()
        delay(300)
        assertEquals(2, m.entreno.value?.rutina?.value?.version)
        assertTrue(t.llamadas.count { it == "mypump_get_sesion_dia" } - antes >= 2, "el día se restauró después de reemplazar la rutina")
    }

    @Test
    fun elPlanNuevoLlegaAlVolverPasadosUnosMinutos() = enUnHilo { alcance ->
        var version = 1
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_rutina_activa" -> 200 to "[${rutinaV(version)}]"
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raiz, PreferenciasEnMemoria(), alcance)
        var ahora = 1_792_000_000_000L
        m.relojRelecturas = { ahora }
        m.cargar()
        assertEquals(1, m.rutina.value?.version)
        version = 2
        val antes = t.llamadas.count { it == "mypump_get_rutina_activa" }
        ahora += 60_000
        m.alVolverAPrimerPlano()
        assertEquals(antes, t.llamadas.count { it == "mypump_get_rutina_activa" }, "al minuto no se relee")
        ahora += 6 * 60_000
        m.alVolverAPrimerPlano()
        assertEquals(2, m.rutina.value?.version, "pasados unos minutos llega el plan nuevo")
    }
}
