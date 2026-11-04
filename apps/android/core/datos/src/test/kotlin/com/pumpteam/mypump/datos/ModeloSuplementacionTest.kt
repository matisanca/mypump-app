package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.PlanSuplementacion
import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La pestaña Suplementación: `mypump_suplementacion`, la caché sin red y las cero filas (sin pestaña). Datos ficticios. */
class ModeloSuplementacionTest {
    /** La fila de la demo (el ejemplo del contrato) como la devuelve PostgREST: una lista con una fila. */
    private val unaFila = "[" + Compartido.texto("demo/suplementacion.json") + "]"

    @Test
    fun cargaGuardaYSeVeSinRed() = enUnHilo { alcance ->
        val disco = Disco(carpetaTemporal("supl"), "tok")
        val cuerpos = mutableListOf<ValorJson>()
        val t = TransporteProgramado { _, c ->
            cuerpos += c
            200 to unaFila
        }
        val m = ModeloSuplementacion(ClienteRpc(transporte = t), "tok", disco, alcance).also { it.alDia() }
        assertNull(m.plan.value)
        m.refrescar()
        assertEquals(listOf("mypump_suplementacion"), t.llamadas)
        assertEquals("tok", cuerpos[0]["p_token"]?.comoTexto)
        assertEquals(5, m.plan.value!!.suplementacion.items.size)
        assertFalse(m.desdeCache.value)
        m.alDia()

        // Otra vez, sin red: la pestaña sale de la caché, igual.
        val sinRed = ModeloSuplementacion(ClienteRpc(transporte = SinRed), "tok", disco, alcance).also { it.alDia() }
        assertEquals(m.plan.value, sinRed.plan.value)
        assertTrue(sinRed.desdeCache.value)
        sinRed.refrescar()
        assertEquals(m.plan.value, sinRed.plan.value)
        assertTrue(sinRed.desdeCache.value)
    }

    @Test
    fun ceroFilasBorraLaCacheYNoHayPestana() = enUnHilo { alcance ->
        val disco = Disco(carpetaTemporal("supl"), "tok")
        var respuesta = unaFila
        val m = ModeloSuplementacion(ClienteRpc(transporte = TransporteProgramado { _, _ -> 200 to respuesta }), "tok", disco, alcance).also { it.alDia() }
        m.refrescar()
        assertNotNull(m.plan.value)
        m.alDia()
        assertNotNull(disco.leer(ModeloSuplementacion.ARCHIVO))
        // Token inválido o sin suplementación: cero filas, sin error.
        respuesta = "[]"
        m.refrescar()
        assertNull(m.plan.value)
        m.alDia()
        assertNull(disco.leer(ModeloSuplementacion.ARCHIVO))
        // `null` también es «no hay».
        respuesta = unaFila
        m.refrescar()
        respuesta = "null"
        m.refrescar()
        assertNull(m.plan.value)
    }

    @Test
    fun laFuncionQueNoExisteEsComoNoTener() = enUnHilo { alcance ->
        val m = ModeloSuplementacion(
            ClienteRpc(transporte = TransporteProgramado { _, _ -> 404 to """{"code":"PGRST202","message":"no existe"}""" }),
            "tok", Disco(carpetaTemporal("supl"), "tok"), alcance,
        ).also { it.alDia() }
        m.refrescar()
        assertNull(m.plan.value)
    }

    @Test
    fun unErrorOUnaFormaRaraNoBorraLoQueHabia() = enUnHilo { alcance ->
        var respuesta = 200 to unaFila
        val m = ModeloSuplementacion(ClienteRpc(transporte = TransporteProgramado { _, _ -> respuesta }), "tok", Disco(carpetaTemporal("supl"), "tok"), alcance)
            .also { it.alDia() }
        m.refrescar()
        val antes = m.plan.value
        assertNotNull(antes)
        respuesta = 500 to """{"message":"caído"}"""
        m.refrescar()
        assertEquals(antes, m.plan.value)
        assertTrue(m.desdeCache.value)
        // Una fila que no se entiende (sin ítems): queda lo que había.
        respuesta = 200 to """[{"suplementacion":{"items":[]},"esquema":1}]"""
        m.refrescar()
        assertEquals(antes, m.plan.value)
        // Un objeto en lugar de la lista: tampoco borra.
        respuesta = 200 to """{"raro":true}"""
        m.refrescar()
        assertEquals(antes, m.plan.value)
    }

    @Test
    fun laDemoNoLlamaAlServidor() = enUnHilo { alcance ->
        val t = TransporteProgramado { _, _ -> 200 to "[]" }
        val plan = PlanSuplementacion.desde(ValorJson.parsear(Compartido.texto("demo/suplementacion.json")))!!
        val m = ModeloSuplementacion.demo(ClienteRpc(transporte = t), plan, alcance)
        m.refrescar()
        assertEquals(plan, m.plan.value)
        assertTrue(t.llamadas.isEmpty())
    }
}
