package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Los vectores que comparte con iOS y la web (`apps/shared/vectores/controles.json`). */
class ControlesVectoresTest {
    private val v: ValorJson = ValorJson.desde(Vectores.json(Vectores.publico("controles")) as JsonObject)
    private fun lista(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos ?: emptyList()
    private fun texto(j: ValorJson?) = j?.comoTexto

    @Test fun textos() {
        val t = TextosControles
        val propios = mapOf(
            "cejaInicio" to t.cejaInicio, "tituloInicio" to t.tituloInicio, "verMisEstudios" to t.verMisEstudios, "notaProgramado" to t.notaProgramado,
            "notaOrdenes" to t.notaOrdenes, "tituloPorDefecto" to t.tituloPorDefecto, "hitosTitulo" to t.hitosTitulo, "hitoProximo" to t.hitoProximo,
            "hitoRecibido" to t.hitoRecibido, "hitoVisto" to t.hitoVisto, "notaOrdenesSinLista" to t.notaOrdenesSinLista,
        )
        assertEquals((v["textos"] as ValorJson.Objeto).campos.mapValues { it.value.comoTexto }, propios)
        assertEquals(v["tituloMax"]?.comoNumero?.toInt(), Controles.TITULO_MAX)
    }

    @Test fun titulo() {
        for (c in lista(v["titulo"])) assertEquals(texto(c["sale"]), Controles.titulo(texto(c["entra"])), "${c["entra"]}")
    }

    @Test fun cuando() {
        for (c in lista(v["cuando"])) assertEquals(texto(c["texto"]), Controles.cuando(Estudios.dia(texto(c["fecha"]))!!, Estudios.dia(texto(c["hoy"]))))
    }

    @Test fun casos() {
        val casos = lista(v["casos"])
        assertTrue(casos.size >= 20)
        for (c in casos) {
            val n = texto(c["nombre"])
            val e = EstadoControles.desde(c["respuesta"])
            val sale = c["sale"]
            val est = e?.let { Controles.proximoParaEstudios(it, hayOrdenes = c["hayOrdenes"] != ValorJson.Booleano(false)) }
            val o = sale?.get("estudios") as? ValorJson.Objeto
            assertEquals(o?.let { Triple(texto(it["titulo"]), texto(it["cuando"]), texto(it["nota"])) }, est?.let { Triple(it.titulo, it.cuando, it.nota) }, n)
            val i = sale?.get("inicio") as? ValorJson.Objeto
            assertEquals(
                i?.let { Controles.TarjetaInicio(texto(it["titulo"])!!, texto(it["cuando"])!!, texto(it["nota"])!!, texto(it["boton"])!!) },
                e?.let { Controles.tarjetaInicio(it, Estudios.dia(texto(c["hoyTelefono"]))) }, n,
            )
            val hitos = lista(sale?.get("hitos")).map { Controles.Hito(texto(it["titulo"])!!, texto(it["cuando"])!!, texto(it["estado"])!!) }
            assertEquals(hitos, e?.let(Controles::hitos) ?: emptyList<Controles.Hito>(), n)
        }
    }

    /** Ningún texto que lee el alumno nombra el ciclo, fármacos ni «IA». */
    @Test fun ningunTextoNombraElCiclo() {
        val todos = ArrayList<String>()
        fun juntar(j: ValorJson?) {
            when (j) {
                is ValorJson.Texto -> todos += j.valor
                is ValorJson.Lista -> j.elementos.forEach(::juntar)
                is ValorJson.Objeto -> j.campos.values.forEach(::juntar)
                else -> Unit
            }
        }
        juntar(v["textos"])
        for (c in lista(v["casos"])) juntar(c["sale"])
        for (s in todos.filter { it != TextosControles.tituloPorDefecto }) assertNotEquals(TextosControles.tituloPorDefecto, Controles.titulo(s.take(60)), s)
    }
}
