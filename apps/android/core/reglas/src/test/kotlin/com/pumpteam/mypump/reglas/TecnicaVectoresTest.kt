package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** Los vectores que comparte con iOS (`apps/shared/vectores/tecnica.json`). */
class TecnicaVectoresTest {
    private val v: ValorJson = ValorJson.desde(Vectores.json(Vectores.publico("tecnica")) as JsonObject)
    private fun lista(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos ?: emptyList()
    private fun num(j: ValorJson?) = j?.comoNumero ?: -1.0
    private fun txt(j: ValorJson?) = (j as? ValorJson.Texto)?.valor

    @Test fun constantesYTextos() {
        assertEquals(num(v["maxNota"]).toInt(), Tecnica.MAX_NOTA)
        val f = TopesTecnica()
        assertEquals(num(v["topesDeFabrica"]?.get("duracion_min_s")), f.duracionMinS)
        assertEquals(num(v["topesDeFabrica"]?.get("duracion_max_s")), f.duracionMaxS)
        assertEquals(num(v["topesDeFabrica"]?.get("bytes_max")).toLong(), f.bytesMax)
        assertEquals((v["textos"] as ValorJson.Objeto).campos.mapValues { txt(it.value) }, TextosTecnica.todos)
        for (c in lista(v["plantillas"])) {
            val t = when (txt(c["clave"])) {
                "tituloDevolucion" -> TextosTecnica.tituloDevolucion(txt(c["valor"])!!)
                "revisadoEl" -> TextosTecnica.revisadoEl(txt(c["valor"])!!)
                "videoListo" -> TextosTecnica.videoListo(num(c["n"]).toInt())
                else -> error("clave")
            }
            assertEquals(txt(c["texto"]), t)
        }
    }

    @Test fun subidaYValidacion() {
        for (c in lista(v["subida"])) {
            val s = Tecnica.clasificarSubida(num(c["status"]).toInt(), c["ok"] == ValorJson.Booleano(true), txt(c["error"]))
            assertEquals(txt(c["accion"]), s.accion.clave, "$c")
            assertEquals(txt(c["rechazo"]), s.rechazo?.clave, "$c")
        }
        for (c in lista(v["validar"])) {
            assertEquals(txt(c["rechazo"]), Tecnica.validar(num(c["duracion"]), num(c["bytes"]).toLong(), TopesTecnica())?.clave, "$c")
        }
    }

    @Test fun decodificarTolerante() {
        for (c in lista(v["decodificar"])) {
            val e = EstadoTecnica.desde(c["json"]!!)
            if (c["nulo"] == ValorJson.Booleano(true)) {
                assertNull(e)
                continue
            }
            assertNotNull(e)
            assertEquals(lista(c["ids"]).map { txt(it) }, e!!.envios.map { it.id })
            assertEquals(num(c["duracionMax"]), e.topes.duracionMaxS)
            assertEquals(num(c["bytesMax"]).toLong(), e.topes.bytesMax)
            if (c["titulos"] != null) {
                val d = e.envios.first().devolucion!!
                assertEquals(lista(c["titulos"]).map { txt(it) }, d.correcciones.map { it.titulo })
                assertEquals(lista(c["momentos"]).map { (it as? ValorJson.Numero)?.valor }, d.correcciones.map { it.momentoS })
                assertEquals(num(c["bien"]).toInt(), d.bien.size)
                assertEquals(num(c["noEvaluable"]).toInt(), d.noEvaluable.size)
                assertEquals(txt(c["otroVideo"]), d.otroVideo)
            }
        }
    }
}
