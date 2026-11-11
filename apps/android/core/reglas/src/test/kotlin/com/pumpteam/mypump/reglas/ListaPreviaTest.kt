package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Gemelo de ListaPreviaTests.swift: la lista previa a la videollamada contra los vectores de `lista_previa.json`. */
class ListaPreviaTest {
    private val v by lazy { Vectores.json(Vectores.publico("lista_previa")) }
    private fun texto(o: JsonObject, k: String): String? = o[k]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content

    @Test
    fun casos() {
        val casos = v["casos"]!!.jsonArray.map { it.jsonObject }
        assertTrue(casos.size >= 20)
        var conLista = 0
        for (c in casos) {
            val n = c["nombre"]!!.jsonPrimitive.content
            val r = ReglasListaPrevia.vista(ValorJson.desde(c["respuesta"]!!))
            val esp = c["salida"]!!
            if (esp is JsonNull) {
                assertNull(r, n)
                continue
            }
            conLista++
            assertNotNull(r, n)
            val e = esp.jsonObject
            val items = e["items"]!!.jsonArray.map { it.jsonObject }
            assertEquals(items.size, r!!.items.size, n)
            for ((x, i) in r.items.zip(items)) {
                assertEquals(texto(i, "clave"), x.clave, n)
                assertEquals(texto(i, "titulo"), x.titulo, n)
                assertEquals(i["hecho"]!!.jsonPrimitive.boolean, x.hecho, n)
                assertEquals(i["opcional"]!!.jsonPrimitive.boolean, x.opcional, n)
                assertEquals(texto(i, "detalle"), x.detalle, n)
                assertEquals(texto(i, "destino"), x.destino?.valor, n)
                assertEquals(texto(i, "accesible"), x.accesible, n)
            }
            assertEquals(texto(e, "resumen"), r.resumen, n)
            assertEquals(e["todo_listo"]!!.jsonPrimitive.boolean, r.todoListo, n)
        }
        assertTrue(conLista >= 10)
        assertNull(ReglasListaPrevia.vista(null))
        assertNull(ReglasListaPrevia.vista(ValorJson.Nulo))
    }

    @Test
    fun textosTitulosYDestinos() {
        val t = v["textos"]!!.jsonObject
        val propios = mapOf(
            "titulo" to ReglasListaPrevia.TITULO, "todo_listo" to ReglasListaPrevia.TODO_LISTO, "consejo" to ReglasListaPrevia.CONSEJO,
            "opcional" to ReglasListaPrevia.OPCIONAL, "hecho" to ReglasListaPrevia.HECHO, "falta" to ReglasListaPrevia.FALTA,
        )
        assertEquals(t.keys, propios.keys)
        for ((k, texto) in propios) assertEquals(t[k]!!.jsonPrimitive.content, texto, k)
        assertEquals(v["titulos"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content }, ReglasListaPrevia.TITULOS)
        assertEquals(v["destinos"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content }, ReglasListaPrevia.DESTINOS.mapValues { it.value.valor })
    }
}
