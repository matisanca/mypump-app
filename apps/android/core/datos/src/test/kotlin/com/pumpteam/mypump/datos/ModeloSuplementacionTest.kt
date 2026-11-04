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
        // La primera lectura del disco terminó (la raíz espera esto antes de sacar la pestaña elegida).
        assertTrue(sinRed.leido.value)
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
    fun unErrorNoBorraLoQueHabia() = enUnHilo { alcance ->
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
        // Una fila que no es un objeto (como en iOS, falla la respuesta entera): tampoco borra.
        for (rara in listOf("[5]", "[null]")) {
            respuesta = 200 to rara
            m.refrescar()
            assertEquals(antes, m.plan.value, rara)
        }
        // Un objeto en lugar de la lista (la respuesta entera no se entiende): tampoco borra.
        respuesta = 200 to """{"raro":true}"""
        m.refrescar()
        assertEquals(antes, m.plan.value)
    }

    /** Como iOS: una fila mal formada o sin ningún ítem con nombre es «no hay»: se va la pestaña y se borra la copia. */
    @Test
    fun filaMalFormadaOSinItemsValidosSacaLaPestanaYBorraLaCopia() = enUnHilo { alcance ->
        for (mala in listOf(
            """[{"suplementacion":{"items":[]},"esquema":1}]""",
            """[{"suplementacion":{"items":[{"cantidad":"5 g"},{"nombre":""}]}}]""",
            """[{"suplementacion":"texto"}]""",
        )) {
            val disco = Disco(carpetaTemporal("supl"), "tok")
            var respuesta = unaFila
            val m = ModeloSuplementacion(ClienteRpc(transporte = TransporteProgramado { _, _ -> 200 to respuesta }), "tok", disco, alcance)
                .also { it.alDia() }
            m.refrescar()
            m.alDia()
            assertNotNull(disco.leer(ModeloSuplementacion.ARCHIVO), mala)
            respuesta = mala
            m.refrescar()
            assertNull(m.plan.value, mala)
            assertFalse(m.desdeCache.value, mala)
            m.alDia()
            assertNull(disco.leer(ModeloSuplementacion.ARCHIVO), mala)
        }
    }

    @Test
    fun laDemoNoLlamaAlServidor() = enUnHilo { alcance ->
        val t = TransporteProgramado { _, _ -> 200 to "[]" }
        val plan = PlanSuplementacion.desde(ValorJson.parsear(Compartido.texto("demo/suplementacion.json")))!!
        val m = ModeloSuplementacion.demo(ClienteRpc(transporte = t), plan, alcance)
        m.refrescar()
        assertEquals(plan, m.plan.value)
        assertTrue(m.leido.value)
        assertTrue(t.llamadas.isEmpty())
    }
}
