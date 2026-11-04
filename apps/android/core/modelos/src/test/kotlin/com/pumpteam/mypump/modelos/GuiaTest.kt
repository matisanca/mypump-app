package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** «Tu guía»: la respuesta de `entregas_app_get` y de `entregas_app_resumen` (fixtures en `apps/shared/fixtures/guia`). */
class GuiaTest {
    private fun fixture(n: String) = Json.parseToJsonElement(Rutas.leer(Rutas.compartido("fixtures/guia/$n.json")))

    @Test
    fun decodificaLaGuiaEntera() {
        val g = Guia.desde(fixture("get-tomas"))
        assertNotNull(g)
        g!!
        assertEquals("Tomás", g.nombrePila)
        assertNull(g.fechaEntrega)
        assertEquals(20, g.clips.size)
        assertEquals(5, g.clips.map { it.bloque }.distinct().size)
        val c = g.clips.first()
        assertEquals("FT-25a", c.id)
        assertEquals(0.7, c.minutos)
        assertFalse(c.visto)
        assertTrue(c.sePuedeVer)
        val s = g.suplementacion!!
        assertEquals(7, s.items.size)
        assertEquals(4, s.dia.size)
        assertEquals(3, s.items.count { it.videoId != null })
        assertEquals(listOf("Que diga *L-citrulina* sola.", "Mezclala con agua."), s.items[1].detalle)
        assertEquals(listOf("Seguí con la que venís usando."), s.items[0].detalle)
        assertEquals(2, s.items[0].tomas.size)
        assertTrue(s.items[4].opcional)
    }

    @Test
    fun conAvanceDudasYUnVideoSinSubir() {
        val g = Guia.desde(fixture("get-tomas-avanzado"))!!
        assertEquals(4, g.clips.count { it.visto })
        assertEquals(12, g.clips[4].segundos)
        assertEquals("¿Puedo cambiar el orden de los ejercicios?", g.clips[4].duda)
        assertFalse(g.clips[19].sePuedeVer)
        assertEquals(2, g.dudasLlamada.size)
        assertEquals("2026-11-06T14:00:00-03:00", g.fechaEntrega)
    }

    @Test
    fun sinGuiaEsNull() {
        assertNull(Guia.desde(fixture("sin-guia")))
        assertNull(Guia.desde(Json.parseToJsonElement("false")))
        assertNull(Guia.desde(Json.parseToJsonElement("null")))
        assertNull(Guia.desde(Json.parseToJsonElement("""{"ok":"true","clips":[]}""")))
        assertNull(ResumenGuia.desde(fixture("sin-guia")))
    }

    @Test
    fun toleraCamposQueFaltanONulos() {
        val g = Guia.desde(
            Json.parseToJsonElement(
                """{"ok":true,"clips":[null,{"id":"a"},{"titulo":"sin id"},{"id":"b","titulo":" ¿Qué? ","minutos":"0,5","visto":null,
                "segundos":"12","duda":"","bloque":null,"url":""},{"id":"c","titulo":"x","minutos":-3,"segundos":-1,"visto":1}],
                "dudas_llamada":null,"suplementacion":{"items":[]}}""",
            ),
        )!!
        assertNull(g.nombrePila)
        assertEquals(listOf("b", "c"), g.clips.map { it.id })
        val b = g.clips[0]
        assertEquals("¿Qué?", b.titulo)
        assertEquals(0.5, b.minutos)
        assertEquals(12, b.segundos)
        assertNull(b.duda)
        assertNull(b.bloque)
        assertFalse(b.sePuedeVer)
        assertEquals(0.0, g.clips[1].minutos)
        assertEquals(0, g.clips[1].segundos)
        assertTrue(g.clips[1].visto)
        assertTrue(g.dudasLlamada.isEmpty())
        assertNull(g.suplementacion)
    }

    @Test
    fun laCacheSeLeeIgual() {
        val g = Guia.desde(fixture("get-tomas-avanzado"))!!
        val vuelta = Guia.desde(g.aValor())
        assertEquals(g.copy(suplementacion = null), vuelta!!.copy(suplementacion = null))
        assertEquals(g.suplementacion!!.items, vuelta.suplementacion!!.items)
    }

    @Test
    fun resumen() {
        val r = ResumenGuia.desde(fixture("resumen-tomas"))!!
        assertEquals(ResumenGuia(20, 4, 11.6), r)
        assertEquals(r, ResumenGuia.desde(r.aValor()))
        assertNull(ResumenGuia.desde(Json.parseToJsonElement("""{"ok":true,"total":0}""")))
        assertEquals(ResumenGuia(3, 3, 0.0), ResumenGuia.desde(Json.parseToJsonElement("""{"ok":true,"total":3,"vistos":9}""")))
        val g = Guia.desde(fixture("get-tomas-avanzado"))!!
        val local = ResumenGuia.de(g)!!
        // Como la web (A5): los 3 videos que nombra un suplemento no cuentan; FT-4c (sin suplemento que lo nombre) sí.
        assertEquals(17, local.total)
        assertEquals(4, local.vistos)
        assertEquals(Math.round(g.clipsDeLaLista.filter { !it.visto }.sumOf { it.minutos } * 10) / 10.0, local.minutosRestantes)
    }

    /** Una guía mínima: un clip por (id, bloque) y los ítems de la suplementación tal cual (JSON). */
    private fun guiaCon(clips: List<Pair<String, String?>>, items: String): Guia {
        val cs = clips.joinToString(",") { (id, b) ->
            """{"id":"$id","titulo":"T $id","url":"https://x.invalid/$id.mp4","minutos":0.5,"bloque":${b?.let { Json.encodeToString(kotlinx.serialization.json.JsonPrimitive(it)) } ?: "null"}}"""
        }
        return Guia.desde(Json.parseToJsonElement("""{"ok":true,"clips":[$cs],"suplementacion":{"items":$items}}"""))!!
    }

    private fun fuera(g: Guia) = g.clips.map { it.id } - g.clipsDeLaLista.map { it.id }.toSet()

    /** La regla de `entregas_012`, borde por borde: sale solo con las dos condiciones a la vez. */
    @Test
    fun reglaDelServidorBordePorBorde() {
        val item = """[{"nombre":"Magnesio","estado":"sigue","video_id":"V1"}]"""
        // (a) El bloque: con espacios, en mayúsculas, sin acento, con no-break o BOM, sí; null u otro bloque, no.
        for (b in listOf("Tu suplementación", "  tu suplementación  ", "TU SUPLEMENTACIÓN", "Tu suplementacion", "\u00a0Tu suplementación\ufeff")) {
            assertEquals(listOf("V1"), fuera(guiaCon(listOf("V1" to b), item)), b)
        }
        for (b in listOf(null, "", "Tu app", "Tu suplementación extra", "Suplementación")) {
            assertEquals(emptyList<String>(), fuera(guiaCon(listOf("V1" to b), item)), b.toString())
        }
        // (b) El ítem: estado «sale», nombre vacío o null, video_id vacío o ausente: el clip queda en la lista y cuenta.
        val bloque = "Tu suplementación"
        for (i in listOf(
            """[{"nombre":"Magnesio","estado":"sale","video_id":"V1"}]""",
            """[{"nombre":"","estado":"sigue","video_id":"V1"}]""",
            """[{"nombre":null,"video_id":"V1"}]""",
            """[{"nombre":"Magnesio","video_id":""}]""",
            """[{"nombre":"Magnesio"}]""",
            """[{"nombre":"Magnesio","video_id":"OTRO"}]""",
        )) {
            val g = guiaCon(listOf("V1" to bloque), i)
            assertEquals(emptyList<String>(), fuera(g), i)
            assertEquals(1, ResumenGuia.de(g)!!.total, i)
        }
        // Como en SQL, sin recortar ni pasar a minúsculas: «Sale» no es «sale», un nombre de espacios no es vacío, estado
        // null no es «sale».
        for (i in listOf(
            """[{"nombre":"Magnesio","estado":"Sale","video_id":"V1"}]""",
            """[{"nombre":"  ","estado":"sigue","video_id":"V1"}]""",
            """[{"nombre":"Magnesio","estado":null,"video_id":"V1"}]""",
        )) assertEquals(listOf("V1"), fuera(guiaCon(listOf("V1" to bloque), i)), i)
        // Basta un ítem que lo nombre, aunque otro con el mismo video «sale».
        assertEquals(listOf("V1"), fuera(guiaCon(listOf("V1" to bloque), """[{"nombre":"A","estado":"sale","video_id":"V1"},{"nombre":"B","video_id":"V1"}]""")))
        // La caché guarda la suplementación cruda: la regla da lo mismo después de leerla de vuelta.
        val g = guiaCon(listOf("V1" to bloque, "V2" to bloque), """[{"nombre":"  ","video_id":"V1"}]""")
        assertEquals(listOf("V1"), fuera(g))
        assertEquals(listOf("V1"), fuera(Guia.desde(g.aValor())!!))
    }

    @Test
    fun losVideosDeLosSuplementosSalenDeLaLista() {
        val g = Guia.desde(fixture("get-tomas"))!!
        assertEquals(listOf("FT-50b", "FT-1b", "FT-4b"), g.clipsDeSuplementos.map { it.id })
        assertTrue(g.clipsDeLaLista.any { it.id == "FT-4c" })
        assertEquals(g.clips.size, g.clipsDeLaLista.size + g.clipsDeSuplementos.size)
        // Sin ningún suplemento que los nombre, quedan todos (los bordes, en reglaDelServidorBordePorBorde).
        assertEquals(g.clips, g.copy(idsDeSuplementos = emptySet()).clipsDeLaLista)
    }
}
