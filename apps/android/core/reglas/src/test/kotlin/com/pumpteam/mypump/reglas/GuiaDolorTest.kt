package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ClipGuia
import com.pumpteam.mypump.modelos.DolorGuia
import com.pumpteam.mypump.modelos.Guia
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Paths
import java.time.Instant

/** «Lo que más te importa»: los mismos casos que iOS (`apps/shared/fixtures/guia/dolor-casos.json`). */
class GuiaDolorTest {
    private val raiz = generateSequence(Paths.get("").toAbsolutePath()) { it.parent }
        .first { Files.isDirectory(it.resolve("apps/shared/fixtures/guia")) }

    private fun fixture(n: String) = Files.readString(raiz.resolve("apps/shared/fixtures/guia/$n"))
    private fun guia(n: String) = Guia.desde(Json.parseToJsonElement(fixture(n)))!!
    private fun guiaDe(json: String) = Guia.desde(Json.parseToJsonElement(json))

    private fun base(clips: List<ClipGuia>, fecha: String? = null, dolor: DolorGuia? = null) = Guia(null, fecha, clips, emptyList(), null, dolor = dolor)

    private fun clip(id: String, bloque: String?, visto: Boolean = false, nuevo: Boolean = false): ClipGuia {
        val p = guia("get-tomas.json").clips.first()
        return p.copy(id = id, titulo = id, bloque = bloque, visto = visto, nuevo = nuevo, duda = null)
    }

    private val ahora = Instant.ofEpochSecond(1_800_000_000)

    @Test
    fun losCasosCompartidos() {
        val casos = Json.parseToJsonElement(fixture("dolor-casos.json")).jsonArray
        assertTrue(casos.size >= 15)
        fun lista(e: kotlinx.serialization.json.JsonElement?) = (e as? JsonArray)?.map { it.jsonPrimitive.content }
        for (c in casos.map { it.jsonObject }) {
            val nombre = c["nombre"]!!.jsonPrimitive.content
            val v = ReglasDolor.vista(DolorGuia(c["titulo"]?.jsonPrimitive?.contentOrNull, c["texto"]!!.jsonPrimitive.content))
            if ((c["vacio"] as? JsonPrimitive)?.content == "true") {
                assertNull(v, nombre)
                continue
            }
            assertNotNull(v, nombre)
            assertEquals(c["subtitulo"]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content, v!!.subtitulo, nombre)
            assertEquals(lista(c["parrafos"]), v.parrafos, nombre)
            val partes = c["partes"] as JsonArray
            assertEquals(partes.map { it.jsonObject["titulo"]!!.jsonPrimitive.content }, v.partes.map { it.titulo }, nombre)
            assertEquals(partes.map { lista(it.jsonObject["parrafos"]) }, v.partes.map { it.parrafos }, nombre)
        }
    }

    @Test
    fun laRespuestaDeHoySigueIgual() {
        val g = guia("get-tomas.json")
        assertNull(g.dolor)
        assertNull(ReglasDolor.vista(g.dolor))
        assertNull(ReglasDolor.introduccion(g, false))
        val bloques = ReglasNovedad.bloques(ReglasNovedad.ordenDeLaLista(g))
        val r = ReglasDolor.reparto(bloques, null)
        assertNull(r.principal)
        assertTrue(r.partes.isEmpty())
        assertEquals(bloques, r.resto)
        assertEquals(ReglasNovedad.ordenDeLaLista(g.clipsDeLaLista), ReglasNovedad.ordenDeLaLista(g))
    }

    @Test
    fun dolorRaroNoRompe() {
        for (raro in listOf("null", "{}", """{"titulo":"x"}""", """{"titulo":"x","texto":""}""", """{"texto":null}""", "\"suelto\"", "[1,2]", """{"texto":{"a":1}}""")) {
            val g = guiaDe("""{"ok":true,"clips":[],"dolor":$raro}""")
            assertNotNull(g, raro)
            assertNull(g!!.dolor, raro)
        }
    }

    @Test
    fun seGuardaEnLaCopia() {
        val g = guia("get-tomas-dolor.json")
        assertEquals("Bajar la panza sin perder fuerza", g.dolor?.titulo)
        val json = g.aValor().aJson()
        assertEquals(g.dolor, Guia.desde(json)?.dolor)
        val sin = guia("get-tomas.json").aValor().aJson() as JsonObject
        assertTrue("dolor" !in sin)
    }

    @Test
    fun unBloqueDelDolorSinTextoSigueEnLaLista() {
        val g = base(listOf(clip("a", "Tu app"), clip("b", "Lo que más te importa")))
        assertEquals(listOf("a", "b"), ReglasNovedad.ordenDeLaLista(g).map { it.id })
    }

    @Test
    fun losVideosDelDolorVanPrimeroYElResto() {
        val g = base(
            listOf(clip("app", "Tu app"), clip("n", "Otro", nuevo = true), clip("otro", "Otro"), clip("plan", "Tu plan"), clip("d", "lo que mas te importa")),
            dolor = DolorGuia(null, "Uno.\n\n## Tu plan\n\nDos."),
        )
        val lista = ReglasNovedad.ordenDeLaLista(g)
        assertEquals(listOf("n", "d", "plan", "app", "otro"), lista.map { it.id })
        val r = ReglasDolor.reparto(ReglasNovedad.bloques(lista), ReglasDolor.vista(g.dolor))
        assertEquals("lo que mas te importa", r.principal?.titulo)
        assertEquals(listOf<String?>("Tu plan"), r.partes.map { it?.titulo })
        assertEquals(listOf(ReglasNovedad.TITULO, "Tu app", "Otro"), r.resto.map { it.titulo })
    }

    @Test
    fun dosPartesIgualesNoRepitenVideos() {
        val v = ReglasDolor.vista(DolorGuia(null, "## Plan\n\nA.\n\n## Plan\n\nB."))
        val r = ReglasDolor.reparto(ReglasGuia.bloques(listOf(clip("p", "Plan"))), v)
        assertEquals(listOf("Plan", null), r.partes.map { it?.titulo })
        assertTrue(r.resto.isEmpty())
    }

    @Test
    fun introConFechaEnHoraArgentina() {
        // 02:00 UTC del jueves es miércoles 23:00 en Argentina.
        val g = base(listOf(clip("a", "Otro")), "2035-03-08T02:00:00Z", DolorGuia(null, "Uno."))
        val i = ReglasDolor.introduccion(g, false, ahora)!!
        assertEquals("Antes de nuestra videollamada del miércoles 7/3, hacé estos dos pasos.", i.texto)
        assertEquals(listOf("Mirá tus videos", "Dejá tus dudas"), i.pasos.map { it.titulo })
        assertEquals(listOf(ReglasDolor.EstadoPaso.AHORA, ReglasDolor.EstadoPaso.PENDIENTE), i.pasos.map { it.estado })
    }

    @Test
    fun introSinFechaNoInventaNinguna() {
        val g = base(listOf(clip("a", "Otro", visto = true)), null, DolorGuia(null, "Uno."))
        val i = ReglasDolor.introduccion(g, true, ahora)!!
        assertEquals("Antes de nuestra videollamada, hacé estos dos pasos.", i.texto)
        assertEquals(listOf(ReglasDolor.EstadoPaso.HECHO, ReglasDolor.EstadoPaso.HECHO), i.pasos.map { it.estado })
    }

    @Test
    fun introNoVaDespuesDeLaLlamadaNiSinDolor() {
        assertNull(ReglasDolor.introduccion(base(emptyList(), "2020-01-01T10:00:00-03:00", DolorGuia(null, "Uno.")), false, ahora))
        assertNull(ReglasDolor.introduccion(base(emptyList(), "2035-03-07T14:00:00-03:00"), false, ahora))
    }

    @Test
    fun textoHabladoDelPaso() {
        val p = ReglasDolor.Paso("videos", 1, "Mirá tus videos", ReglasDolor.EstadoPaso.HECHO)
        assertEquals("Paso 1 de 2, Mirá tus videos, hecho", ReglasDolor.textoHablado(p, 2))
    }
}
