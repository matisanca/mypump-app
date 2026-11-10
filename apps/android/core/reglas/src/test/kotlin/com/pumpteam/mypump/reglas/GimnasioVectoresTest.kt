package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.ZoneId
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** Los vectores que comparte con iOS (`apps/shared/vectores/gimnasio.json`). */
class GimnasioVectoresTest {
    private val v: ValorJson = ValorJson.desde(Vectores.json(Vectores.publico("gimnasio")) as JsonObject)
    private fun lista(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos ?: emptyList()
    private fun textos(j: ValorJson?) = lista(j).mapNotNull { it.comoTexto }
    private fun entero(j: ValorJson?) = j?.comoNumero?.toInt() ?: -1
    private fun bool(j: ValorJson?) = j == ValorJson.Booleano(true)

    @Test fun zonasYConstantes() {
        assertEquals(lista(v["zonas"]).map { it["clave"]?.comoTexto }, Gimnasio.zonas.map { it.clave })
        assertEquals(lista(v["zonas"]).map { it["nombre"]?.comoTexto }, Gimnasio.zonas.map { it.nombre })
        assertEquals(entero(v["topeFotos"]), Gimnasio.TOPE_FOTOS)
        assertEquals(entero(v["maxNota"]), Gimnasio.MAX_NOTA)
        assertEquals(entero(v["maxPx"]), Gimnasio.MAX_PX)
    }

    @Test fun textos() {
        val t = (v["textos"] as ValorJson.Objeto).campos.mapValues { it.value.comoTexto }
        assertEquals(t, TextosGimnasio.todos)
        for (c in lista(v["plurales"])) {
            val n = entero(c["n"])
            assertEquals(c["fotos"]?.comoTexto, TextosGimnasio.cuentaFotos(n))
            assertEquals(c["faltan"]?.comoTexto, TextosGimnasio.faltanZonas(n))
            assertEquals(c["necesitamos"]?.comoTexto, TextosGimnasio.necesitamosFotos(n))
        }
        assertEquals("Adaptado por Mati el 12/11", TextosGimnasio.adaptadoPorMati("12/11"))
    }

    @Test fun zonasCompletasYTope() {
        for (c in lista(v["faltantes"])) assertEquals(textos(c["faltan"]), Gimnasio.zonasFaltantes(textos(c["conFotos"]).toSet(), textos(c["noHay"]).toSet(), c["modo"]!!.comoTexto!!))
        for (c in lista(v["puedeEnviar"])) assertEquals(bool(c["puede"]), Gimnasio.puedeEnviar(c["modo"]!!.comoTexto!!, textos(c["conFotos"]).toSet(), textos(c["noHay"]).toSet(), textos(c["quitar"]).toSet()))
        for (c in lista(v["tope"])) {
            assertEquals(entero(c["restan"]), Gimnasio.restan(entero(c["servidor"]), entero(c["cola"])))
            assertEquals(bool(c["puede"]), Gimnasio.puedeAgregar(entero(c["servidor"]), entero(c["cola"])))
        }
    }

    @Test fun pantallasYEntradas() {
        for (c in lista(v["pantalla"])) assertEquals(c["pantalla"]?.comoTexto, Gimnasio.pantalla(c["abierta"]?.comoTexto, bool(c["vigente"])).clave)
        for (c in lista(v["tarjeta"])) assertEquals(bool(c["visible"]), Gimnasio.tarjetaVisible(bool(c["habilitado"]), c["abierta"]?.comoTexto, bool(c["vigente"])))
        for (c in lista(v["entrada"])) assertEquals(bool(c["visible"]), Gimnasio.entradaVisible(bool(c["habilitado"]), bool(c["vigente"])))
    }

    @Test fun clasificacionDeSubidas() {
        for (c in lista(v["subida"])) {
            val s = Gimnasio.clasificarSubida(entero(c["status"]), bool(c["ok"]))
            assertEquals(c["accion"]?.comoTexto, s.accion.clave, "${entero(c["status"])}")
            assertEquals(bool(c["refrescar"]), s.refrescar)
            assertEquals(c["aviso"]?.comoTexto, s.aviso?.clave)
        }
    }

    @Test fun respuestas() {
        for (c in lista(v["respuestas"])) assertEquals(bool(c["valida"]), Gimnasio.respuestaValida(PreguntaGimnasio.desde(c["p"]!!)!!, c["v"]!!), "${c["p"]!!["id"]} ${c["v"]}")
        val e = v["paraEnviar"]!!
        val ps = lista(e["preguntas"]).mapNotNull(PreguntaGimnasio::desde)
        val b = (e["borrador"] as ValorJson.Objeto).campos
        assertEquals((e["resultado"] as ValorJson.Objeto).campos, Gimnasio.respuestasParaEnviar(ps, b))
        assertEquals(entero(e["fotosPedidas"]), Gimnasio.fotosPedidas(ps, b))
        for (c in lista(v["kilos"])) assertEquals(c["n"]?.comoNumero, Gimnasio.kilos(c["s"]!!.comoTexto!!), c["s"]!!.comoTexto)
    }

    @Test fun fechas() {
        for (c in lista(v["fechas"])) assertEquals(c["texto"]?.comoTexto, Gimnasio.fechaCorta(c["iso"]?.comoTexto, ZoneId.of(c["zona"]!!.comoTexto!!)))
    }

    @Test fun decodificacionTolerante() {
        for (c in lista(v["decodificar"])) {
            val e = EstadoGimnasio.desde(c["j"]!!)
            assertEquals(bool(c["habilitado"]), e != null)
            if (e == null) continue
            assertEquals(c["version"]?.comoTexto, e.consentimientoVersion)
            assertEquals(bool(c["aceptado"]), e.consentimientoAceptado)
            assertEquals(c["abierta"]?.comoTexto, e.abierta?.estado)
            if (c["equipos"] != null) {
                assertEquals(entero(c["equipos"]), e.vigente?.equipos?.size)
                assertEquals(entero(c["cantidad"]), e.vigente?.equipos?.last()?.cantidad)
            }
            if (c["preguntas"] != null) assertEquals(entero(c["preguntas"]), e.abierta?.preguntas?.size)
        }
    }
}
