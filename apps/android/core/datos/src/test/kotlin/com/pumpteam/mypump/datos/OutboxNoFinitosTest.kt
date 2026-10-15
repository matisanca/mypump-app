package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Sospecha de la revisión del 15-oct (gemelo de OutboxNoFinitosTests.swift): en iOS `JSONEncoder` tira con NaN o infinito
 * y la cola dejaba de guardarse para siempre. Acá `ValorJson.aJson` ya los escribía como null (como `JSON.stringify` de la
 * web): el archivo y la RPC salían bien, pero en memoria seguía el número roto hasta reabrir la app. Ahora también en
 * memoria (`sinNoFinitos` al encolar y al reemplazar en Dieta), y estas pruebas cuidan las dos cosas.
 */
class OutboxNoFinitosTest {
    private val raiz = carpetaTemporal("outbox-nofinitos")
    private val archivo = File(raiz, "outbox.json")

    /** Un reemplazo con números que salieron de una cuenta rota (una porción de 0 g por unidad da infinito). */
    private val swapRoto = ValorJson.objeto(
        "dietaId" to texto("d1"), "comidaId" to texto("c1"), "optIdx" to numero(0), "foodIdx" to numero(0),
        "food" to ValorJson.objeto(
            "name" to texto("Agua"), "qty" to numero(Double.POSITIVE_INFINITY), "kcal" to numero(0), "_dev" to numero(Double.NaN),
        ),
    )

    @Test
    fun loQueSeEncolaDespuesSigueGuardandoseEnDisco() = enUnHilo { alcance ->
        val o = Outbox(archivo, reintentoAutomatico = false, alcance = alcance) {
            ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin red")))
        }
        o.encolar("swap", swapRoto, "swap_d1_c1_0_0")
        o.encolar(
            "habito", ValorJson.objeto("fecha" to texto("2026-10-15"), "campo" to texto("vasos_agua"), "valor" to texto("3")),
            "habito|2026-10-15|vasos_agua",
        )
        // En memoria, lo mismo que en disco.
        assertEquals(ValorJson.Nulo, o.operaciones().first().payload["food"]?.get("qty"), "en memoria seguía el infinito")
        // Otro arranque: lo que quedó en disco.
        val otra = Outbox(archivo, reintentoAutomatico = false, alcance = alcance) { ResultadoOp.Respuesta(Resultado.Ok(texto("ok"))) }
        assertEquals(2, otra.pendientes(), "la cola dejó de guardarse")
        val food = otra.operaciones().first().payload["food"]
        assertTrue(food?.get("qty") == ValorJson.Nulo && food["_dev"] == ValorJson.Nulo && food["name"]?.comoTexto == "Agua", "como JSON.stringify: null")
    }

    /** El mismo reemplazo desde Dieta: el archivo de reemplazos de la dieta también queda guardado, y con null. */
    @Test
    fun unReemplazoConNumerosRotosQuedaGuardado() = enUnHilo { alcance ->
        val dieta = """[{"id":"dieta-1","version":1,"estructura":{"macros_target":{"kcal":2500,"prot":180,"carb":250,"fat":80},"comidas":[""" +
            """{"id":"c1","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":80,"unit":"g","kcal":300,"prot":10,"carb":50,"fat":6}]}]}]}}]"""
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_dieta_activa" -> 200 to dieta
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance)
        m.cargar()
        val avena = m.comidasDelDia.first().opciones.first().alimentos.first()
        m.sustituir(avena, swapRoto["food"]!!, "c1", 0, 0)
        val enDisco = Disco(raiz, TOKEN).leer("swaps_dieta-1.json") as? JsonObject
        assertEquals(1, enDisco?.size, "el archivo de reemplazos no se guardó")
        assertEquals(ValorJson.Nulo, ValorJson.desde(enDisco!!.values.first())["current"]?.get("qty"))
        // Y lo que se ve en Dieta es lo mismo que al reabrir.
        assertEquals(ValorJson.Nulo, m.swaps.value.values.first().current["qty"], "en memoria seguía el infinito")
    }

    @Test
    fun laOpSeMandaConNullYNoTerminaEnFallidos() = enUnHilo { alcance ->
        val s = Servidor()
        s.cuando("save_food_swap", """[{"ok":true}]""")
        val esc = Escrituras(ClienteRpc(transporte = s), TOKEN)
        val o = Outbox(archivo, reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
        o.encolar("swap", swapRoto, "swap_d1_c1_0_0")
        repeat(3) { o.drenar() }
        val enviado = s.llamadas("save_food_swap").firstOrNull()?.get("p_food_data")
        assertEquals("Agua", enviado?.get("name")?.comoTexto, "la RPC no salió")
        assertTrue(enviado?.get("qty") == ValorJson.Nulo && enviado["_dev"] == ValorJson.Nulo, "como JSON.stringify: null")
        assertEquals(0, o.pendientes())
        assertEquals(0, o.fallidos().size)
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
    }
}
