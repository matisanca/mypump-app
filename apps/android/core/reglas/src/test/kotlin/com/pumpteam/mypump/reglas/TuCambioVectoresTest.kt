package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.ZoneId
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Los vectores que comparte con iOS y la web (`apps/shared/vectores/tucambio.json`). Gemelo de TuCambioVectoresTests.swift. */
class TuCambioVectoresTest {
    private val v: ValorJson = ValorJson.desde(Vectores.json(Vectores.publico("tucambio")) as JsonObject)
    private fun lista(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos ?: emptyList()
    private fun foto(j: ValorJson?): TuCambio.Foto? {
        val o = j?.get("origen")?.comoTexto ?: return null
        val origen = TuCambio.Origen.entries.first { it.clave == o }
        return TuCambio.Foto(origen, j["semana"]?.comoTexto ?: "")
    }

    @Test fun textos() {
        val t = v["textos"]
        assertEquals(t?.get("titulo")?.comoTexto, TuCambio.TITULO)
        assertEquals(t?.get("textoEspera")?.comoTexto, TuCambio.TEXTO_ESPERA)
        assertEquals(t?.get("rotuloAntes")?.comoTexto, TuCambio.ROTULO_ANTES)
        assertEquals(t?.get("rotuloEstaSemana")?.comoTexto, TuCambio.ROTULO_ESTA_SEMANA)
        assertEquals(t?.get("botonVer")?.comoTexto, TuCambio.BOTON_VER)
        assertEquals(t?.get("poseInicial")?.comoTexto, TuCambio.POSE_INICIAL)
        assertEquals(t?.get("listoTitulo")?.comoTexto, TuCambio.LISTO_TITULO)
    }

    @Test fun casos() {
        val actual = v["semanaActual"]!!.comoTexto!!
        val casos = lista(v["casos"])
        assertTrue(casos.size > 15)
        for (c in casos) {
            val n = c["nombre"]?.comoTexto ?: "?"
            val fotos = lista(c["fotos"]).map { lista(it)[0].comoTexto!! to lista(it)[1].comoTexto!! }
            val inicio = ((c["inicio"] as? ValorJson.Objeto)?.campos ?: emptyMap()).mapValues { it.value.comoTexto!! }
            val peso = lista(c["peso"]).map { PesoCorporal.Punto(lista(it)[0].comoTexto!!, lista(it)[1].comoNumero!!) }
            val r = TuCambio.vista(fotos, inicio, actual, c["pose"]?.comoTexto ?: "", peso)
            val e = c["esperado"]
            assertEquals(e?.get("modo")?.comoTexto, r.modo.clave, n)
            assertEquals(e?.get("pose")?.comoTexto, r.pose, n)
            assertEquals(foto(e?.get("antes")), r.antes, n)
            assertEquals(foto(e?.get("despues")), r.despues, n)
            assertEquals(e?.get("texto")?.comoTexto, r.texto, n)
            assertEquals(e?.get("pie")?.comoTexto, r.pie, n)
            assertEquals(e?.get("rotuloAntes")?.comoTexto, r.rotuloAntes, n)
            assertEquals(e?.get("rotuloDespues")?.comoTexto, r.rotuloDespues, n)
            assertEquals(e?.get("accesibleAntes")?.comoTexto, r.accesibleAntes, n)
            assertEquals(e?.get("accesibleDespues")?.comoTexto, r.accesibleDespues, n)
            assertEquals(e?.get("vacioDespues")?.comoTexto, r.vacioDespues, n)
        }
    }

    @Test fun fechasYSinFoto() {
        for (f in lista(v["fechas"])) assertEquals(lista(f)[1].comoTexto, TuCambio.fecha(lista(f)[0].comoTexto!!))
        for (f in lista(v["sinFoto"])) assertEquals(lista(f)[1].comoTexto, TuCambio.sinFoto(lista(f)[0].comoTexto!!))
        assertTrue(lista(v["sinOtra"]).isNotEmpty())
        for (f in lista(v["sinOtra"])) assertEquals(lista(f)[1].comoTexto, TuCambio.sinOtra(lista(f)[0].comoTexto!!))
        for (f in lista(v["fechaLocal"])) {
            val zona = ZoneId.of(f["zona"]!!.comoTexto!!)
            assertEquals(f["esperado"]?.comoTexto, TuCambio.fechaLocal(f["iso"]!!.comoTexto!!, zona), f["iso"]?.comoTexto)
        }
    }
}
