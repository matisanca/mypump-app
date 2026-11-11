package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.nio.file.Files
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** «Novedades de tu plan»: la base del teléfono, la lista y la palanca. Los mismos casos que NovedadesModeloTests.swift. */
class ModeloNovedadesTest {
    private val raiz = Files.createTempDirectory("novedades").toFile()
    private val token = "AAAAAAAAAAAAAAAAAAAA"
    private fun disco() = Disco(raiz, token)
    private fun nuevo(ahora: () -> Long = System::currentTimeMillis) = ModeloNovedades(disco(), ahora)

    private fun rutina(ejercicio: String, series: Int = 3, semana: Int = 1, version: Int = 1): ModeloNovedades.Entrada =
        ModeloNovedades.Entrada.Hay(Json.parseToJsonElement(
            """{"id":"r-1","version":$version,"semana_actual":$semana,"estructura":{"dias":[{"id":"d1","n":1,"nombre":"Torso","bloques":[{"ejercicios":[{"id":"e1","nombre":"$ejercicio","series":$series,"reps":"8-10"},{"id":"e2","nombre":"Remo","series":3,"reps":"10"}]}]}]}}""",
        ))

    private fun supl(vararg nombres: String): ModeloNovedades.Entrada = ModeloNovedades.Entrada.Hay(Json.parseToJsonElement(
        """{"suplementacion":{"items":[${nombres.joinToString(",") { """{"nombre":"$it","cantidad":"5 g","momento":"desayuno"}""" }}]},"esquema":1}""",
    ))

    private val no = ModeloNovedades.Entrada.NoLlego
    private val ninguna = ModeloNovedades.Entrada.Ninguna

    @Test fun laPrimeraVezSinNadaGuardaYNoMuestra() {
        val m = nuevo()
        assertNull(m.observar(rutina("Press banca"), ninguna, no))
        assertTrue(m.lista.value.isEmpty())
        val n = m.observar(rutina("Press inclinado", version = 2), ninguna, no)
        assertEquals(listOf("En Torso cambia Press banca por Press inclinado"), n?.partes?.first()?.lineas)
        assertEquals(n?.id, m.pendiente?.id)
        assertEquals(n?.id, nuevo().pendiente?.id)
    }

    @Test fun conLaSemillaSeVeLoQueCambioAntesDeLaPrimeraVez() {
        val n = nuevo().observar(rutina("Press banca", series = 4), no, no, Triple(rutina("Press banca"), no, no))
        assertEquals("Mati actualizó tu rutina", n?.titular)
        assertEquals("En Torso, Press banca pasa a 4 series de 8 a 10", n?.resumen)
    }

    @Test fun loQueNoLlegoNoSeComparaNiSePisa() {
        val m = nuevo()
        m.observar(rutina("Press banca"), no, supl("Creatina"))
        assertNull(m.observar(no, no, no))
        val n = m.observar(no, no, supl("Creatina", "Omega 3"))
        assertEquals(listOf(listOf("Se suma Omega 3")), n?.partes?.map { it.lineas })
        assertFalse(n!!.resumen.contains("5 g"))
    }

    @Test fun republicarIgualOPasarDeSemanaNoMuestraNada() {
        val m = nuevo()
        m.observar(rutina("Press banca"), no, no)
        assertNull(m.observar(rutina("Press banca", semana = 2, version = 7), no, no))
        assertTrue(m.lista.value.isEmpty())
    }

    @Test fun soloConBaseNoArrancaUnaBase() {
        assertNull(nuevo().observar(no, no, supl("Creatina"), soloConBase = true))
        assertNull(disco().leer(ModeloNovedades.ARCHIVO_BASE))
    }

    @Test fun vistaUnaVezYLaListaTieneTope() {
        val m = nuevo()
        m.observar(rutina("E0"), no, no)
        for (i in 1..15) m.observar(rutina("E$i"), no, no)
        assertEquals(ModeloNovedades.MAXIMO, m.lista.value.size)
        val id = m.pendiente!!.id
        m.marcarVista(id)
        assertTrue(m.pendiente?.id != id)
        assertEquals(true, nuevo().lista.value.first { it.id == id }.vista)
    }

    @Test fun laTarjetaDuraUnaSemana() {
        var hoy = 1_800_000_000_000L
        val m = nuevo { hoy }
        m.observar(rutina("A"), no, no)
        m.observar(rutina("B"), no, no)
        assertNotNull(m.reciente())
        hoy += 8 * 86_400_000L
        assertNull(m.reciente())
    }

    @Test fun laPalancaSeLeeDeLaClave() {
        assertFalse(PalancaRemota.desde(ValorJson.objeto()).novedadesPlan)
        assertTrue(PalancaRemota.desde(ValorJson.objeto("novedades_plan" to ValorJson.Booleano(true))).novedadesPlan)
        assertFalse(PalancaRemota.desde(ValorJson.objeto("novedades_plan" to ValorJson.Texto("true"))).novedadesPlan)
    }

    @Test fun laListaGuardadaSeLeeIgual() {
        val m = nuevo()
        m.observar(rutina("A"), no, no)
        val n = m.observar(rutina("B"), no, no)!!
        val leido: JsonElement = disco().leer(ModeloNovedades.ARCHIVO_LISTA)!!
        assertEquals(n, NovedadPlan.desde((leido as kotlinx.serialization.json.JsonArray)[0]))
    }

    // ---------------------------------------------------------------- La carga entera, con la palanca

    private fun app(palanca: Boolean, ejercicio: () -> String, raizApp: java.io.File, alcance: kotlinx.coroutines.CoroutineScope): ModeloApp {
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_app_config" -> 200 to (if (palanca) """{"novedades_plan":true}""" else "{}")
                "mypump_get_rutina_activa" -> 200 to "[" + (rutina(ejercicio()) as ModeloNovedades.Entrada.Hay).valor.toString() + "]"
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(token), raizApp, PreferenciasEnMemoria(), alcance)
    }

    @Test fun conLaPalancaPrendidaUnaPublicacionNuevaSeVe() = enUnHilo { alcance ->
        var e = "Press banca"
        val r = carpetaTemporal("nov-app")
        app(true, { e }, r, alcance).cargar()
        e = "Press inclinado"
        val otra = app(true, { e }, r, alcance)
        otra.cargar()
        assertEquals("En Torso cambia Press banca por Press inclinado", otra.novedades.value?.pendiente?.resumen)
    }

    @Test fun conLaPalancaApagadaNoSeGuardaNiSeMuestraNada() = enUnHilo { alcance ->
        var e = "Press banca"
        val r = carpetaTemporal("nov-app-off")
        app(false, { e }, r, alcance).cargar()
        e = "Press inclinado"
        val otra = app(false, { e }, r, alcance)
        otra.cargar()
        assertTrue(otra.novedades.value?.lista?.value?.isEmpty() == true)
        val d = Disco(r, token)
        assertFalse(d.archivo(ModeloNovedades.ARCHIVO_BASE).exists())
        assertFalse(d.archivo(ModeloNovedades.ARCHIVO_LISTA).exists())
    }
}
