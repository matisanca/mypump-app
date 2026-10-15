package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * sim-migracion.sh (15-oct; gemelo de SwapsViejosPalancaTests.swift): un teléfono de la v1.0.11, sin la marca de migrados,
 * con un reemplazo de comida que solo estaba en el teléfono (c3) y otro en la cola vieja (c1). Al leer la palanca la cola
 * soltaba las ops de la migración, y el `swap` de c1 llegaba al servidor antes de que la hidratación preguntara qué tenía.
 * El servidor «ya tenía algo», ganaba la mezcla y c3 se perdía. Ahora los `swap` y `swap_del` viejos esperan esa decisión;
 * las demás ops viejas salen igual.
 */
class SwapsViejosPalancaTest {
    private val raiz = carpetaTemporal("swaps-viejos")

    /** Los reemplazos guardados en el servidor de la prueba. */
    private class Servidor {
        private val filas = LinkedHashMap<String, ValorJson>()
        @Volatile var lecturaFalla = false
        @Volatile var habitos = 0
        val comidas: List<String> get() = synchronized(filas) { filas.keys.sorted() }
        fun guardar(comida: String, food: ValorJson) = synchronized(filas) { filas[comida] = food }
        fun json(): String = synchronized(filas) {
            ValorJson.Lista(
                filas.entries.sortedBy { it.key }.map { (c, f) ->
                    ValorJson.objeto("comida_id" to texto(c), "opt_idx" to numero(0), "food_idx" to numero(0), "food_data" to f)
                },
            ).serializar()
        }
    }

    /** La cola vieja con un hábito y el reemplazo de c1; el mapa del teléfono con c1 y c3; sin la marca de migrados. */
    private fun sembrar() {
        val disco = Disco(raiz, TOKEN)
        val habito = Operacion(
            "cap-habito", "habito", ValorJson.objeto("fecha" to texto("2026-10-14"), "campo" to texto("agua"), "valor" to numero(3)),
            "habito_2026-10-14_agua", ts = 1_000.0,
        )
        val pollo = ValorJson.objeto("name" to texto("Pollo"), "qty" to numero(200), "unit" to texto("g"))
        val ricota = ValorJson.objeto("name" to texto("Ricota"), "_orig" to pollo)
        val swapC1 = Operacion(
            "cap-swap", "swap",
            ValorJson.objeto("dietaId" to texto(DIETA), "comidaId" to texto("c1"), "optIdx" to numero(0), "foodIdx" to numero(0), "food" to ricota),
            C1, ts = 1_001.0,
        )
        val quedaron = Outbox.importarEnArchivo(disco.archivo("outbox.json"), listOf(habito, swapC1))
        assertTrue(quedaron.all { it.legado == true })
        val merluza = ValorJson.objeto("name" to texto("Merluza"), "qty" to numero(250), "unit" to texto("g"))
        disco.guardar(
            "swaps_$DIETA.json",
            ValorJson.objeto(
                C1 to ValorJson.objeto("original" to pollo, "current" to ricota),
                C3 to ValorJson.objeto("original" to merluza, "current" to ValorJson.objeto("name" to texto("Atún"), "_orig" to merluza)),
            ),
        )
    }

    private fun modelo(s: Servidor, alcance: CoroutineScope, dieta: () -> String = { DIETA_JSON }, demoraSwaps: Long = 0): ModeloApp {
        val t = TransporteProgramado { fn, cuerpo ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_dieta_activa" -> 200 to dieta()
                "mypump_get_app_config" -> 200 to """{"migracion_ops_legadas":true}"""
                // Lo de antes de preguntar por los reemplazos tarda, como en un teléfono de verdad: la cola ya está mandando.
                "mypump_get_cliente_prefs", "mypump_get_custom_foods" -> {
                    delay(150)
                    200 to "[]"
                }
                "mypump_get_food_swaps" -> {
                    if (demoraSwaps > 0) delay(demoraSwaps)
                    if (s.lecturaFalla) throw IOException("sin conexión a internet") else 200 to s.json()
                }
                "mypump_save_food_swap" -> {
                    s.guardar(cuerpo["p_comida_id"]?.comoTexto ?: "?", cuerpo["p_food_data"] ?: ValorJson.Nulo)
                    200 to """[{"id":"1"}]"""
                }
                "mypump_set_habito" -> {
                    s.habitos++
                    200 to "true"
                }
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance)
    }

    @Test
    fun elReemplazoQueSoloEstabaEnElTelefonoNoSePierde() = enUnHilo { alcance ->
        sembrar()
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.drenar()
        assertEquals(listOf("c1", "c3"), s.comidas, "c3 se perdía: el swap viejo de c1 llegaba antes de la decisión")
        assertEquals(setOf(C1, C3), m.swaps.value.keys)
        assertEquals(1, s.habitos, "las demás ops viejas salen igual")
        assertEquals(0, m.outbox?.pendientes())
    }

    @Test
    fun sinPoderPreguntarLosReemplazosViejosEsperanYLoDemasSale() = enUnHilo { alcance ->
        sembrar()
        val s = Servidor()
        s.lecturaFalla = true
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.drenar()
        assertTrue(s.comidas.isEmpty(), "salió un reemplazo viejo sin decidir")
        assertEquals(1, s.habitos, "el hábito viejo no tiene por qué esperar")
        assertEquals(listOf("swap"), m.outbox?.operaciones()?.map { it.kind })
        assertEquals(setOf(C1, C3), m.swaps.value.keys, "sin poder preguntar no se toca nada")

        // Con la próxima carga se decide y suben los dos.
        s.lecturaFalla = false
        m.cargar()
        m.outbox?.drenar()
        assertEquals(listOf("c1", "c3"), s.comidas)
        assertEquals(setOf(C1, C3), m.swaps.value.keys)
    }

    /**
     * La revisión adversarial del 15-oct (hallazgos 1 y 4): retener solo los reemplazos VIEJOS no alcanzaba. Uno nativo llegaba
     * al servidor antes de la decisión, y uno viejo salía con una dieta que no se podía usar: c3 se perdía igual.
     */
    @Test
    fun unReemplazoNativoSinPoderDecidirEsperaYNoSePierdeC3() = enUnHilo { alcance ->
        sembrar()
        val s = Servidor()
        s.lecturaFalla = true
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.drenar()
        val pollo = m.dieta.value!!.estructura.comidas.first { it.id == "c1" }.opciones.first().alimentos.first()
        m.sustituir(pollo, ValorJson.objeto("name" to texto("Pavita"), "qty" to numero(200), "unit" to texto("g")), "c1", 0, 0)
        m.outbox?.drenar()
        assertTrue(s.comidas.isEmpty(), "el reemplazo nativo salió antes de decidir")
        s.lecturaFalla = false
        m.cargar()
        m.outbox?.drenar()
        assertEquals(listOf("c1", "c3"), s.comidas, "c3 nunca llegó al servidor")
        assertTrue(C3 in m.swaps.value.keys, "c3 se borró del teléfono")
    }

    @Test
    fun unReemplazoNativoEnLaVentanaDeLaPrimeraCargaNoPierdeC3() = enUnHilo { alcance ->
        sembrar()
        val s = Servidor()
        val m = modelo(s, alcance, demoraSwaps = 300)
        val carga = alcance.async { m.cargar() }
        while (m.fase.value != ModeloApp.Fase.LISTO || m.dieta.value == null) delay(10)
        val pollo = m.dieta.value!!.estructura.comidas.first { it.id == "c1" }.opciones.first().alimentos.first()
        m.sustituir(pollo, ValorJson.objeto("name" to texto("Pavita"), "qty" to numero(200), "unit" to texto("g")), "c1", 0, 0)
        carga.await()
        m.outbox?.drenar()
        assertTrue("c3" in s.comidas, "c3 nunca llegó al servidor")
        assertTrue(C3 in m.swaps.value.keys, "c3 se borró del teléfono")
    }

    @Test
    fun unaDietaQueTodaviaNoSePuedeUsarNoSueltaLosReemplazos() = enUnHilo { alcance ->
        sembrar()
        val s = Servidor()
        val rota = """[{"id":"dieta-d","version":2,"estructura":{"comidas":[{"id":"c1","name":"Desayuno","options":[{"name":"A","foods":[]}]}]}}]"""
        var usable = false
        val m = modelo(s, alcance, dieta = { if (usable) DIETA_JSON else rota })
        m.cargar()
        m.outbox?.drenar()
        assertTrue(m.dieta.value == null && s.comidas.isEmpty(), "con la dieta en armado salió un reemplazo viejo")
        usable = true
        m.cargar()
        m.outbox?.drenar()
        assertEquals(listOf("c1", "c3"), s.comidas)
        assertTrue(C3 in m.swaps.value.keys)
    }

    /** Quien ya migró (con la marca) no espera nada: el reemplazo sale enseguida. */
    @Test
    fun conLaMarcaDeMigradosLosReemplazosNoEsperan() = enUnHilo { alcance ->
        sembrar()
        Disco(raiz, TOKEN).guardar("swaps_migrados_$DIETA", ValorJson.Booleano(true))
        val s = Servidor()
        s.lecturaFalla = true
        val m = modelo(s, alcance)
        assertFalse(m.faltaDecidirSwaps(Disco(raiz, TOKEN)))
        m.cargar()
        m.outbox?.drenar()
        assertEquals(listOf("c1"), s.comidas, "el reemplazo de quien ya migró quedó esperando")
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
        const val DIETA = "dieta-d"
        const val C1 = "swap_dieta-d_c1_0_0"
        const val C3 = "swap_dieta-d_c3_0_0"
        const val DIETA_JSON = """[{"id":"dieta-d","version":1,"estructura":{"macros_target":{"kcal":2500,"prot":180,"carb":250,"fat":80},"comidas":[""" +
            """{"id":"c1","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Pollo","qty":200,"unit":"g","kcal":330,"prot":62,"carb":0,"fat":7}]}]},""" +
            """{"id":"c3","name":"Cena","options":[{"name":"A","foods":[{"name":"Merluza","qty":250,"unit":"g","kcal":225,"prot":45,"carb":0,"fat":4}]}]}]}}]"""
    }
}
