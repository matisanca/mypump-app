package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.SeguimientoAvance
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/**
 * «Tu guía» contra el backend REAL con la cuenta `test-nativa-android` (guía aprobada de prueba: 20 videos en 5 bloques).
 * El token llega por `MYPUMP_TOKEN_GUIA` o, si no, del registro privado (como [IntegracionTest]); nunca se imprime. Sin
 * ninguno de los dos, se saltea.
 *
 * Solo escribe por los RPC `entregas_app_*`: el avance que manda es el que ya tiene el servidor (no cambia nada, el
 * servidor se queda con el mayor y `visto` no vuelve a false). Las dudas se acumulan, así que corren solo con
 * `MYPUMP_PROBAR_DUDAS=1`.
 */
class GuiaIntegracionTest {
    private lateinit var token: String

    @BeforeEach
    fun cuenta() {
        val t = System.getenv("MYPUMP_TOKEN_GUIA")?.ifBlank { null } ?: IntegracionTest.tokenDePrueba()
        assumeTrue(t != null, "sin token de la cuenta de prueba")
        token = t!!
    }

    private fun modelo(alcance: kotlinx.coroutines.CoroutineScope, disco: Disco = Disco(carpetaTemporal("guia-int"), token)): Pair<ModeloGuia, Outbox> {
        val cliente = ClienteRpc()
        val esc = Escrituras(cliente, token)
        val cola = Outbox(archivo = disco.archivo("outbox.json"), reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
        val m = ModeloGuia(cliente, token, cola, disco, alcance)
        return m to cola
    }

    @Test
    fun resumenYGuiaDeLaCuentaDePrueba() = enUnHilo { alcance ->
        val (m, _) = modelo(alcance)
        m.refrescarResumen()
        val r = m.resumen.value
        assertNotNull(r, "entregas_app_resumen tendría que dar ok true")
        assertEquals(20, r!!.total)
        m.abrir()
        assertEquals(ModeloGuia.Estado.LISTA, m.estado.value)
        val g = m.guia.value!!
        assertEquals(20, g.clips.size)
        assertEquals(5, g.clips.map { it.bloque }.distinct().size)
        assertTrue(g.clips.all { it.sePuedeVer })
        val s = g.suplementacion!!
        assertEquals(7, s.items.size)
        assertEquals(4, s.items.count { it.videoId != null })
        // Cada «Ver por qué» apunta a un clip de la guía.
        assertTrue(s.items.mapNotNull { it.videoId }.all { g.clip(it) != null })
        // El resumen y la guía cuentan lo mismo (la guía fresca con lo que diga el servidor).
        val deLaGuia = ResumenGuia.de(g)!!
        assertEquals(r.vistos, deLaGuia.vistos)
        assertEquals(r.minutosRestantes, deLaGuia.minutosRestantes, 0.051)
    }

    @Test
    fun elAvanceSaleYElServidorSeQuedaConElMayor() = enUnHilo { alcance ->
        val (m, cola) = modelo(alcance)
        m.abrir()
        val c = m.guia.value!!.clips.last()
        // Lo mismo que ya tiene: no cambia nada en la cuenta.
        m.guardarAvance(SeguimientoAvance.Guardado(c.id, c.segundos, c.visto))
        cola.drenar()
        assertEquals(0, cola.pendientes())
        assertTrue(cola.fallidos().isEmpty())
        val (otro, _) = modelo(alcance)
        otro.abrir()
        val despues = otro.guia.value!!.clip(c.id)!!
        assertEquals(c.visto, despues.visto)
        assertTrue(despues.segundos >= c.segundos)
    }

    @Test
    fun conUnTokenInventadoNoHayGuiaYNadaSeGuarda() = enUnHilo { alcance ->
        val cliente = ClienteRpc()
        val falso = mapOf("p_token" to ValorJson.Texto("token-que-no-existe-" + System.nanoTime()))
        assertEquals(ValorJson.Booleano(false), cliente.llamar("entregas_app_get", falso).valorONull()?.get("ok"))
        assertEquals(ValorJson.Booleano(false), cliente.llamar("entregas_app_resumen", falso).valorONull()?.get("ok"))
        val avance = falso + mapOf("p_video" to ValorJson.Texto("FT-25a"), "p_segundos" to ValorJson.Numero(1.0), "p_visto" to ValorJson.Booleano(false))
        assertEquals(ValorJson.Booleano(false), cliente.llamar("entregas_app_avance", avance).valorONull())
        val m = ModeloGuia(cliente, "token-que-no-existe", null, Disco(carpetaTemporal("guia-int"), "x"), alcance)
        m.abrir()
        assertEquals(ModeloGuia.Estado.NO_HAY, m.estado.value)
        assertNull(m.guia.value)
    }

    @Test
    fun dudasDeVideoYParaLaLlamada() = enUnHilo { alcance ->
        assumeTrue(System.getenv("MYPUMP_PROBAR_DUDAS") == "1", "las dudas se acumulan: solo con MYPUMP_PROBAR_DUDAS=1")
        val disco = Disco(carpetaTemporal("guia-int"), token)
        val (m, cola) = modelo(alcance, disco)
        cola.observar(estado = {}, abandonadas = m::alAbandonar, guardadas = m::alGuardar)
        m.abrir()
        val g = m.guia.value!!
        val video = g.clips.first().id
        val marca = "Prueba nativa Android ${System.currentTimeMillis()}"
        assertTrue(m.enviarDudaVideo(video, "$marca, video"))
        if (m.puedeSumarDudaLlamada()) assertTrue(m.enviarDudaLlamada("$marca, llamada"))
        cola.drenar()
        repeat(5) { kotlinx.coroutines.yield() }
        assertTrue(m.pendientes.value.isEmpty())
        val (otro, _) = modelo(alcance)
        otro.abrir()
        val ahora = otro.guia.value!!
        assertTrue(ahora.clip(video)!!.duda!!.contains("$marca, video"))
        if (g.dudasLlamada.size < 30) assertTrue(ahora.dudasLlamada.any { it.texto == "$marca, llamada" })
    }
}
