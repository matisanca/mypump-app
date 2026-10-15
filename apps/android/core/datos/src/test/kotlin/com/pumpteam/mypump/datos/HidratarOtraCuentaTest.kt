package com.pumpteam.mypump.datos

import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 10 (gemelo de HidratarOtraCuentaTests.swift): `hidratarDieta` no volvía a mirar si la
 * cuenta seguía siendo la misma después de esperar al servidor. Si en ese momento entraba otro link (Mati abriendo la
 * cuenta de un cliente), las preferencias, los alimentos propios y los reemplazos de A quedaban en B: en memoria, en su
 * carpeta y en su cola.
 */
class HidratarOtraCuentaTest {
    private val raiz = carpetaTemporal("hidratar-cuenta")

    private fun dieta(id: String, comida: String): String =
        """[{"id":"$id","version":1,"estructura":{"macros_target":{"kcal":2500,"prot":180,"carb":250,"fat":80},"comidas":[""" +
            """{"id":"$comida","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":80,"unit":"g","kcal":300,"prot":10,"carb":50,"fat":6}]}]}]}}]"""

    @Test
    fun loDeAQueLlegaTardeNoQuedaEnB() = enUnHilo { alcance ->
        val senal = AtomicBoolean(false)
        val t = TransporteProgramado { fn, cuerpo ->
            val deA = cuerpo["p_token"]?.comoTexto == TOK_A
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"${if (deA) "c-a" else "c-b"}","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_dieta_activa" -> 200 to if (deA) dieta("dieta-a", "a1") else dieta("dieta-b", "b1")
                "mypump_get_cliente_prefs" -> if (!deA) {
                    200 to """[{"excluir":[],"idioma":"es"}]"""
                } else {
                    // Las de A tardan: mientras tanto se abre el link de B.
                    senal.set(true)
                    delay(300)
                    200 to """[{"excluir":["cerdo"],"idioma":"es"}]"""
                }
                "mypump_get_custom_foods" -> 200 to if (deA) """[{"name":"Pan de A","kcal":250,"prot":8,"carb":48,"fat":3,"unit":"g"}]""" else "[]"
                "mypump_get_food_swaps" -> 200 to if (deA) {
                    """[{"comida_id":"a1","opt_idx":0,"food_idx":0,"food_data":{"name":"Ricota","qty":100,"unit":"g","kcal":138}}]"""
                } else {
                    "[]"
                }
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(TOK_A), raiz, PreferenciasEnMemoria(), alcance)
        val cargaA = async { m.cargar() }
        repeat(100) { if (!senal.get()) delay(10) }
        assertTrue(senal.get())
        assertTrue(m.entrar("https://app.mypumpteam.com/?t=$TOK_B"))
        cargaA.await()

        assertTrue(m.token == TOK_B && m.dieta.value?.id == "dieta-b")
        assertTrue(m.excluir.value.isEmpty(), "quedaron las preferencias de A")
        assertTrue(m.alimentosPropios.value.isEmpty(), "quedaron los alimentos propios de A")
        assertFalse(m.swaps.value.keys.any { "dieta-a" in it }, "quedaron los reemplazos de A")
        val enDiscoB = (Disco(raiz, TOK_B).leer("swaps_dieta-b.json") as? JsonObject)?.keys ?: emptySet()
        assertFalse(enDiscoB.any { "dieta-a" in it }, "los reemplazos de A se escribieron en la carpeta de B")
        val colaB = m.outbox!!.operaciones()
        assertFalse(colaB.any { it.payload["dietaId"]?.comoTexto == "dieta-a" }, "la cola de B tiene escrituras de A")
        assertEquals(TOK_B, m.token)
    }

    private companion object {
        const val TOK_A = "AAAAAAAAAAAAAAAAAAAA"
        const val TOK_B = "BBBBBBBBBBBBBBBBBBBB"
    }
}
