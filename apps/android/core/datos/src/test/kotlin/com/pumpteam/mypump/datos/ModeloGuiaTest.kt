package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.SeguimientoAvance
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.yield
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * «Tu guía» (`entregas_010_app`) con dobles que contestan las respuestas de las fixtures (`apps/shared/fixtures/guia`):
 * la caché, `ok: false`, el resumen de la tarjeta y las escrituras por la cola con sus kinds nuevos.
 */
class ModeloGuiaTest {
    private val guia = Compartido.texto("fixtures/guia/get-marcelo.json")
    private val avanzada = Compartido.texto("fixtures/guia/get-marcelo-avanzado.json")
    private val resumen = Compartido.texto("fixtures/guia/resumen-marcelo.json")
    private val sinGuia = Compartido.texto("fixtures/guia/sin-guia.json")

    private class Entorno(val m: ModeloGuia, val cola: Outbox, val t: TransporteProgramado, val disco: Disco, val cuerpos: MutableList<Pair<String, ValorJson>>)

    /** El modelo con la cola de verdad ([Escrituras]) sin reintento automático: las pasadas se hacen a mano con `drenar`. */
    private suspend fun entorno(
        alcance: CoroutineScope,
        disco: Disco = Disco(carpetaTemporal("guia"), "tok"),
        regla: (String, ValorJson) -> Pair<Int, String>,
    ): Entorno {
        val cuerpos = mutableListOf<Pair<String, ValorJson>>()
        val t = TransporteProgramado { fn, c ->
            synchronized(cuerpos) { cuerpos += fn to c }
            regla(fn, c)
        }
        val cliente = ClienteRpc(transporte = t)
        val esc = Escrituras(cliente, "tok")
        val cola = Outbox(archivo = disco.archivo("outbox.json"), reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
        val m = ModeloGuia(cliente, "tok", cola, disco, alcance)
        cola.observar(estado = {}, abandonadas = m::alAbandonar, guardadas = m::alGuardar)
        yield()
        return Entorno(m, cola, t, disco, cuerpos)
    }

    /** Deja correr lo que el modelo lanzó en el alcance (los avisos de la cola llegan así). */
    private suspend fun asentar() = repeat(5) { yield() }

    @Test
    fun abrirCargaYGuardaLaCache() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ -> if (fn == "entregas_app_get") 200 to guia else 200 to "true" }
        assertEquals(ModeloGuia.Estado.SIN_DATOS, e.m.estado.value)
        assertNull(e.m.resumen.value)
        e.m.abrir()
        assertEquals(ModeloGuia.Estado.LISTA, e.m.estado.value)
        assertFalse(e.m.desdeCache.value)
        assertEquals(20, e.m.guia.value!!.clips.size)
        assertEquals(ResumenGuia(20, 0, ResumenGuia.deTodos(e.m.guia.value!!)!!.minutosRestantes), e.m.resumen.value)
        // Solo el get, con el token: nada de escrituras al abrir.
        assertEquals(listOf("entregas_app_get"), e.t.llamadas)
        assertEquals("tok", e.cuerpos[0].second["p_token"]?.comoTexto)

        // Sin red: abre desde la caché, sin error.
        val sinRed = ModeloGuia(ClienteRpc(transporte = SinRed), "tok", null, e.disco, alcance)
        assertEquals(ModeloGuia.Estado.LISTA, sinRed.estado.value)
        assertTrue(sinRed.desdeCache.value)
        sinRed.abrir()
        assertEquals(ModeloGuia.Estado.LISTA, sinRed.estado.value)
        assertTrue(sinRed.desdeCache.value)
        assertEquals(e.m.guia.value, sinRed.guia.value)
        assertEquals(e.m.resumen.value, sinRed.resumen.value)
    }

    @Test
    fun sinRedYSinCache() = enUnHilo { alcance ->
        val m = ModeloGuia(ClienteRpc(transporte = SinRed), "tok", null, Disco(carpetaTemporal("guia"), "tok"), alcance)
        m.abrir()
        assertEquals(ModeloGuia.Estado.SIN_RED, m.estado.value)
        assertNull(m.guia.value)
        // Un 200 que no es JSON (portal cautivo) tampoco es «no hay guía».
        val portal = ModeloGuia(ClienteRpc(transporte = PortalCautivo), "tok", null, Disco(carpetaTemporal("guia"), "tok"), alcance)
        portal.abrir()
        assertEquals(ModeloGuia.Estado.SIN_RED, portal.estado.value)
    }

    @Test
    fun okFalseBorraLaSeccionYLaTarjeta() = enUnHilo { alcance ->
        var respuesta = guia
        val e = entorno(alcance) { fn, _ -> if (fn == "entregas_app_get") 200 to respuesta else 200 to resumen }
        e.m.abrir()
        e.m.refrescarResumen()
        assertNotNull(e.m.resumen.value)
        respuesta = sinGuia
        e.m.abrir()
        assertEquals(ModeloGuia.Estado.NO_HAY, e.m.estado.value)
        assertNull(e.m.guia.value)
        assertNull(e.m.resumen.value)
        assertFalse(e.disco.archivo(ModeloGuia.ARCHIVO_GUIA).exists())
        assertFalse(e.disco.archivo(ModeloGuia.ARCHIVO_RESUMEN).exists())
        // Al abrir otra vez la app no queda nada guardado.
        val otra = ModeloGuia(ClienteRpc(transporte = SinRed), "tok", null, e.disco, alcance)
        assertNull(otra.resumen.value)
        assertEquals(ModeloGuia.Estado.SIN_DATOS, otra.estado.value)
    }

    @Test
    fun elResumenEsLaTarjetaYNoLlamaAlGet() = enUnHilo { alcance ->
        var r = resumen
        val e = entorno(alcance) { fn, _ -> if (fn == "entregas_app_resumen") 200 to r else 500 to "{}" }
        e.m.refrescarResumen()
        assertEquals(ResumenGuia(20, 4, 11.6), e.m.resumen.value)
        assertEquals(listOf("entregas_app_resumen"), e.t.llamadas)
        // Sin red queda el último.
        val sinRed = ModeloGuia(ClienteRpc(transporte = SinRed), "tok", null, e.disco, alcance)
        sinRed.refrescarResumen()
        assertEquals(ResumenGuia(20, 4, 11.6), sinRed.resumen.value)
        // Token inválido, revocado o sin guía: la tarjeta desaparece.
        r = sinGuia
        e.m.refrescarResumen()
        assertNull(e.m.resumen.value)
        assertEquals(ModeloGuia.Estado.NO_HAY, e.m.estado.value)
    }

    @Test
    fun elResumenNoTapaLoVistoQueTodaviaNoSalio() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_get" -> 200 to guia
                "entregas_app_resumen" -> 200 to """{"ok":true,"total":20,"vistos":0,"minutos_restantes":14.5}"""
                else -> 200 to "true"
            }
        }
        e.m.abrir()
        e.m.guardarAvance(SeguimientoAvance.Guardado("FT-25a", 42, true))
        e.m.refrescarResumen()
        assertEquals(1, e.m.resumen.value!!.vistos)
    }

    @Test
    fun elAvanceSaleDeduplicadoPorVideoYNoPierdeElVisto() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ -> if (fn == "entregas_app_get") 200 to guia else 200 to "true" }
        e.m.abrir()
        e.m.guardarAvance(SeguimientoAvance.Guardado("FT-25a", 34, true))
        e.m.guardarAvance(SeguimientoAvance.Guardado("FT-25a", 12, false))
        e.m.guardarAvance(SeguimientoAvance.Guardado("FT-2b", 10, false))
        val ops = e.cola.operaciones()
        assertEquals(2, ops.size)
        val a = ops.first { it.dedupeKey == ModeloGuia.claveAvance("FT-25a") }
        assertEquals(34.0, a.payload["segundos"]?.comoNumero)
        assertEquals(ValorJson.Booleano(true), a.payload["visto"])
        // En el teléfono ya se ve visto (y en la caché).
        assertTrue(e.m.guia.value!!.clip("FT-25a")!!.visto)
        assertEquals(1, e.m.resumen.value!!.vistos)
        val cache = ModeloGuia(ClienteRpc(transporte = SinRed), "tok", null, e.disco, alcance)
        assertTrue(cache.guia.value!!.clip("FT-25a")!!.visto)

        e.cola.drenar()
        assertEquals(0, e.cola.pendientes())
        val avances = e.cuerpos.filter { it.first == "entregas_app_avance" }.map { it.second }
        assertEquals(2, avances.size)
        val c = avances.first { it["p_video"]?.comoTexto == "FT-25a" }
        assertEquals(34.0, c["p_segundos"]?.comoNumero)
        assertEquals(ValorJson.Booleano(true), c["p_visto"])
        assertEquals("tok", c["p_token"]?.comoTexto)
    }

    @Test
    fun unGetConElAvanceTodaviaEnLaColaLoMuestraVisto() = enUnHilo { alcance ->
        val disco = Disco(carpetaTemporal("guia"), "tok")
        // Sin red: el avance queda en la cola.
        val e = entorno(alcance, disco) { fn, _ -> if (fn == "entregas_app_get") 200 to guia else throw java.io.IOException("sin red") }
        e.m.abrir()
        e.m.guardarAvance(SeguimientoAvance.Guardado("FT-2b", 20, true))
        e.cola.drenar()
        assertEquals(1, e.cola.pendientes())
        // El servidor todavía no lo tiene, pero la guía que trae el get se ve con lo del teléfono encima.
        e.m.abrir()
        assertTrue(e.m.guia.value!!.clip("FT-2b")!!.visto)
        assertEquals(20, e.m.guia.value!!.clip("FT-2b")!!.segundos)
    }

    @Test
    fun dudasDeVideoYGeneralesSinDeduplicar() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ -> if (fn == "entregas_app_get") 200 to avanzada else 200 to "true" }
        e.m.abrir()
        assertTrue(e.m.enviarDudaVideo("FT-9a", "  ¿Y si no consigo el alimento?  "))
        assertTrue(e.m.enviarDudaVideo("FT-9a", "¿Y si no consigo el alimento?"))
        assertTrue(e.m.enviarDudaLlamada("Quiero hablar del cardio"))
        assertFalse(e.m.enviarDudaVideo("FT-9a", "   "))
        assertFalse(e.m.enviarDudaLlamada("x".repeat(1001)))
        assertEquals(3, e.cola.pendientes())
        assertEquals(3, e.m.pendientes.value.size)
        e.cola.drenar()
        asentar()
        assertTrue(e.m.pendientes.value.isEmpty())
        val dudas = e.cuerpos.filter { it.first == "entregas_app_duda" }.map { it.second }
        assertEquals(2, dudas.size)
        assertEquals("¿Y si no consigo el alimento?", dudas[0]["p_texto"]?.comoTexto)
        assertEquals("FT-9a", dudas[0]["p_video"]?.comoTexto)
        val llamada = e.cuerpos.single { it.first == "entregas_app_llamada_duda" }.second
        assertEquals("Quiero hablar del cardio", llamada["p_texto"]?.comoTexto)
        assertNull(llamada["p_video"])
        // Quedan sumadas como las suma el servidor, y el aviso de cada una.
        assertEquals("¿Y si no consigo el alimento?\n¿Y si no consigo el alimento?", e.m.guia.value!!.clip("FT-9a")!!.duda)
        assertEquals(3, e.m.guia.value!!.dudasLlamada.size)
        assertEquals(3, e.m.avisos.value.size)
        assertTrue(e.m.avisos.value.all { it is ModeloGuia.AvisoDuda.Guardada })
        e.m.avisos.value.toList().forEach(e.m::avisoVisto)
        assertTrue(e.m.avisos.value.isEmpty())
    }

    @Test
    fun falseDelServidorDevuelveElTextoAlCampo() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_get" -> 200 to guia
                // El token sigue siendo válido: el false es el tope.
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"x"}]"""
                else -> 200 to "false"
            }
        }
        e.m.abrir()
        e.m.enviarDudaVideo("FT-2b", "Una duda larga")
        e.cola.drenar()
        asentar()
        assertEquals(0, e.cola.pendientes())
        assertTrue(e.m.pendientes.value.isEmpty())
        assertEquals(listOf(ModeloGuia.AvisoDuda.Rechazada("FT-2b", "Una duda larga")), e.m.avisos.value)
        assertNull(e.m.guia.value!!.clip("FT-2b")!!.duda)
    }

    @Test
    fun conElTokenCaidoQuedaEstacionada() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_get" -> 200 to guia
                "mypump_get_cliente_info" -> 200 to "[]"
                else -> 200 to "false"
            }
        }
        e.m.abrir()
        e.m.enviarDudaLlamada("Para la llamada")
        e.m.guardarAvance(SeguimientoAvance.Guardado("FT-2b", 15, false))
        e.cola.drenar()
        asentar()
        // No se pierde ni gasta intentos: espera un link nuevo.
        assertEquals(2, e.cola.pendientes())
        assertTrue(e.cola.operaciones().all { it.tries == 0 })
        assertEquals(1, e.m.pendientes.value.size)
        assertTrue(e.m.avisos.value.isEmpty())
    }

    @Test
    fun lasDudasQueQuedaronEnLaColaSeVenAlVolver() = enUnHilo { alcance ->
        val disco = Disco(carpetaTemporal("guia"), "tok")
        val e = entorno(alcance, disco) { fn, _ -> if (fn == "entregas_app_get") 200 to guia else throw java.io.IOException("sin red") }
        e.m.abrir()
        e.m.enviarDudaVideo("FT-2c", "¿Cuándo paso de semana?")
        e.m.enviarDudaLlamada("Algo para la llamada")
        e.cola.cerrar()
        // La app se cerró: la cola de la cuenta y el modelo se arman de nuevo desde el disco.
        val otra = entorno(alcance, disco) { fn, _ -> if (fn == "entregas_app_get") 200 to guia else 200 to "true" }
        asentar()
        assertEquals(listOf("FT-2c" to "¿Cuándo paso de semana?", null to "Algo para la llamada"), otra.m.pendientes.value.map { it.video to it.texto })
        otra.cola.drenar()
        asentar()
        assertTrue(otra.m.pendientes.value.isEmpty())
        assertEquals("¿Cuándo paso de semana?", otra.m.guia.value!!.clip("FT-2c")!!.duda)
    }

    @Test
    fun topeDeTreintaDudasParaLaLlamada() = enUnHilo { alcance ->
        val llena = avanzada.replace(
            Regex("\"dudas_llamada\": \\[[^\\]]*\\]"),
            "\"dudas_llamada\": [" + (1..29).joinToString(",") { "{\"texto\":\"d$it\",\"en\":null}" } + "]",
        )
        val e = entorno(alcance) { fn, _ -> if (fn == "entregas_app_get") 200 to llena else throw java.io.IOException("sin red") }
        e.m.abrir()
        assertEquals(29, e.m.guia.value!!.dudasLlamada.size)
        assertTrue(e.m.puedeSumarDudaLlamada())
        assertTrue(e.m.enviarDudaLlamada("la 30"))
        assertFalse(e.m.puedeSumarDudaLlamada())
        assertFalse(e.m.enviarDudaLlamada("la 31"))
        assertEquals(1, e.cola.pendientes())
    }

    @Test
    fun laCuentaDeOtroTokenNoVeLaCache() = enUnHilo { alcance ->
        val raiz = carpetaTemporal("guia")
        val e = entorno(alcance, Disco(raiz, "tok")) { fn, _ -> if (fn == "entregas_app_get") 200 to guia else 200 to "true" }
        e.m.abrir()
        val otra = ModeloGuia(ClienteRpc(transporte = SinRed), "otro", null, Disco(raiz, "otro"), alcance)
        assertNull(otra.guia.value)
        assertNull(otra.resumen.value)
    }
}
