package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ItemSuplemento
import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Feedback del alumno: los mismos casos que iPhone y la web (`apps/shared/fixtures/feedback/`). Gemelo de FeedbackTests.swift. */
class FeedbackTest {
    private fun json(n: String): ValorJson = ValorJson.parsear(Vectores.texto(Vectores.compartido("fixtures/feedback/$n.json")))
    private fun lista(j: ValorJson?): List<ValorJson> = (j as? ValorJson.Lista)?.elementos ?: emptyList()
    private fun objeto(j: ValorJson?): Map<String, ValorJson> = (j as? ValorJson.Objeto)?.campos ?: emptyMap()
    private fun vista(clave: String) = FiguraCuerpo.Vista.entries.first { it.clave == clave }

    @Test fun laFiguraEsLaDelArchivoCompartido() {
        val j = json("cuerpo")
        assertEquals(FiguraCuerpo.ANCHO, j["ancho"]?.comoNumero)
        assertEquals(FiguraCuerpo.ALTO, j["alto"]?.comoNumero)
        for (v in FiguraCuerpo.Vista.entries) {
            val esperadas = lista(j["vistas"]?.get(v.clave))
            val piezas = FiguraCuerpo.piezas(v)
            assertEquals(esperadas.size, piezas.size, v.clave)
            assertTrue(piezas.isNotEmpty())
            for ((p, e) in piezas.zip(esperadas)) {
                assertEquals(e["zona"]?.comoTexto, p.zona)
                assertEquals(e["lado"]?.comoTexto, p.lado)
                assertEquals(e["forma"]?.comoTexto, p.forma.clave)
                assertArrayEquals(lista(e["a"]).mapNotNull { it.comoNumero }.toDoubleArray(), p.a)
            }
        }
    }

    @Test fun todasLasZonasDelServidorEstanEnElDibujoYTienenNombre() {
        val todas = FiguraCuerpo.Vista.entries.flatMap { FiguraCuerpo.piezas(it) }
        assertEquals(ReglasMolestia.zonas.map { it.id }.toSet(), todas.mapNotNull { it.zona }.toSet())
        assertEquals(17, ReglasMolestia.zonas.size)
        for (p in todas.filter { it.zona != null }) {
            assertFalse(ReglasMolestia.nombreZona(p.zona!!, p.lado!!).isEmpty())
            assertTrue(p.lado in ReglasMolestia.lados)
            assertEquals(FiguraCuerpo.vista(p.zona!!), if (FiguraCuerpo.piezas(FiguraCuerpo.Vista.FRENTE).any { it.zona == p.zona }) FiguraCuerpo.Vista.FRENTE else FiguraCuerpo.Vista.ESPALDA)
        }
        // Cada pieza de una vista tiene su id propio: es la etiqueta de prueba y la clave del dibujo.
        for (v in FiguraCuerpo.Vista.entries) assertEquals(FiguraCuerpo.piezas(v).size, FiguraCuerpo.piezas(v).map { it.id }.toSet().size)
    }

    @Test fun casosCompartidos() {
        val j = json("casos")
        assertTrue(lista(j["zonas"]).size >= 12 && lista(j["toques"]).size >= 13)
        for (c in lista(j["zonas"])) assertEquals(c["nombre"]!!.comoTexto, ReglasMolestia.nombreZona(c["zona"]!!.comoTexto!!, c["lado"]!!.comoTexto!!))
        for (c in lista(j["niveles"]).map(::lista)) assertEquals(c[1].comoNumero!!.toInt(), ReglasMolestia.nivel(c[0].comoNumero!!.toInt()).id)
        for (c in lista(j["fuerte"]).map(::lista)) assertEquals(c[1], ValorJson.Booleano(ReglasMolestia.esFuerte(c[0].comoNumero!!.toInt())))
        for (c in lista(j["claves"]).map(::lista)) assertEquals(c[1].comoTexto, ReglasSupleEstado.clave(c[0].comoTexto!!))
        for (c in lista(j["toques"])) {
            val p = FiguraCuerpo.pieza(vista(c["vista"]!!.comoTexto!!), c["x"]!!.comoNumero!!, c["y"]!!.comoNumero!!)
            assertEquals(c["zona"]?.comoTexto, p?.zona, "$c")
            assertEquals(c["lado"]?.comoTexto, p?.lado, "$c")
        }
    }

    @Test fun filasDeSuplementos() {
        val s = json("casos")["suple"]!!
        val items = lista(s["items"]).mapNotNull { ItemSuplemento.desde(it.aJson()) }
        assertTrue(items.any { it.protector })
        val marcas = objeto(s["marcas"]).mapValues { ReglasSupleEstado.Estado.de(it.value.comoTexto)!! }
        val filas = ReglasSupleEstado.filas(items, marcas)
        val esperadas = lista(s["filas"])
        assertEquals(esperadas.map { it["id"]!!.comoTexto }, filas.map { it.id })
        assertEquals(esperadas.map { it["nombre"]!!.comoTexto }, filas.map { it.nombre })
        assertEquals(esperadas.map { it["estado"]?.comoTexto }, filas.map { it.estado?.clave })
        assertEquals(s["resumen"]!!.comoTexto, ReglasSupleEstado.resumen(filas))
        assertFalse(filas.any { it.id == "telmisartan" }, "un protector no se marca nunca")
    }

    @Test fun protectorEsOpcionalYNoRompe() {
        fun item(s: String) = ItemSuplemento.desde(Json.parseToJsonElement(s))!!
        assertFalse(item("""{"nombre":"Zinc"}""").protector)
        assertTrue(item("""{"nombre":"Zinc","protector":true}""").protector)
        assertFalse(item("""{"nombre":"Zinc","protector":null}""").protector)
        assertFalse(item("""{"nombre":"Zinc","protector":{"raro":1}}""").protector)
    }

    @Test fun decodificaConTolerancia() {
        val m = json("casos")["molestias"]!!
        val e = EstadoFeedback.desde(m["respuesta"]!!)!!
        assertTrue(e.dueleHabilitado)
        assertFalse(e.supleHabilitado)
        assertEquals(lista(m["ids"]).map { it.comoTexto }, e.molestias.map { it.id })
        for ((k, v) in objeto(m["por_ejercicio"])) assertEquals(v.comoTexto, e.molestia(k)?.id, k)
        assertEquals(m["nombre_a3"]!!.comoTexto, e.molestias[2].nombreZona)
        assertNull(e.molestias[2].intensidad)
        assertEquals(mapOf("zinc" to ReglasSupleEstado.Estado.COMPRADO), e.marcas)
        assertEquals(objeto(m["marcas"]).mapValues { it.value.comoTexto }, e.marcas.mapValues { it.value.clave })
        assertNull(EstadoFeedback.desde(ValorJson.Lista(emptyList())))
        // Un objeto vacío (un servidor que todavía no manda nada): todo apagado, sin romper.
        assertEquals(EstadoFeedback(), EstadoFeedback.desde(ValorJson.objeto()))
        assertEquals(EstadoFeedback(), EstadoFeedback.desde(ValorJson.parsear("""{"me_duele":7,"suple_estado":"x"}""")))
    }

    @Test fun borrador() {
        var b = ReglasMolestia.Borrador()
        assertFalse(b.completa)
        b = b.copy(zona = "hombro", lado = "derecho", desde = "hoy", cuando = "al_subir", tipo = "sordo")
        assertFalse(b.completa)
        b = b.copy(intensidad = 5)
        assertTrue(b.completa)
        assertEquals("Hombro derecho", b.nombreZona)
        assertFalse(b.copy(zona = "oreja").completa)
        assertFalse(b.copy(intensidad = 11).completa)
        val larga = ReglasMolestia.nota("á".repeat(600))
        assertEquals(500, larga.codePointCount(0, larga.length))
        // Un carácter de dos unidades no se parte al medio.
        val pares = ReglasMolestia.nota("💪".repeat(600))
        assertEquals(500, pares.codePointCount(0, pares.length))
        assertEquals(1000, pares.length)
        // Corregir: la intensidad guardada vuelve a su escalón.
        val m = Molestia.desde(ValorJson.parsear("""{"id":"a","ejercicio_id":"e","zona":"codo","lado":"izquierdo","intensidad":6,"estado":"avisada","nota":"x"}"""))!!
        assertEquals(ReglasMolestia.Borrador(zona = "codo", lado = "izquierdo", intensidad = 7, nota = "x"), ReglasMolestia.Borrador.de(m))
    }

    /** Lo que no puede aparecer en ningún texto que lee el alumno. */
    @Test fun textosSinLoProhibido() {
        val textos = TextosFeedback.todos + ReglasMolestia.desde.map { it.texto } + ReglasMolestia.cuando.map { it.texto } + ReglasMolestia.tipo.map { it.texto } +
            ReglasMolestia.niveles.map { it.texto } + ReglasMolestia.ladosParaElegir.map { it.texto } +
            ReglasSupleEstado.Estado.entries.flatMap { listOf(it.accion, it.marcado) } +
            ReglasMolestia.zonas.flatMap { z -> ReglasMolestia.lados.map { ReglasMolestia.nombreZona(z.id, it) } }
        assertTrue(textos.size > 100)
        val prohibido = Regex("""[:\-–—]|\bIA\b|inteligencia artificial|coach|entrenador|\bRIR\b|cerca del fallo|diagn[oó]stic|lesi[oó]n""", RegexOption.IGNORE_CASE)
        for (t in textos) {
            assertFalse(t.isBlank())
            assertNull(prohibido.find(t), t)
            assertTrue(t.codePoints().noneMatch { Character.getType(it) == Character.OTHER_SYMBOL.toInt() || Character.getType(it) == Character.SURROGATE.toInt() || it >= 0x1F000 }, t)
        }
    }

    /** Los textos son los mismos que en iPhone, letra por letra. */
    @Test fun textosIgualesALosDeIphone() {
        val swift = Vectores.texto(Vectores.raizRepo.resolve("apps/ios/MyPumpKit/Sources/MyPumpReglas/TextosFeedback.swift")) +
            Vectores.texto(Vectores.raizRepo.resolve("apps/ios/MyPumpKit/Sources/MyPumpReglas/Feedback.swift")) +
            Vectores.texto(Vectores.raizRepo.resolve("apps/ios/MyPump/Entreno/MeDueleView.swift"))
        val propios = TextosFeedback.todos + ReglasMolestia.desde.map { it.texto } + ReglasMolestia.cuando.map { it.texto } + ReglasMolestia.tipo.map { it.texto } +
            ReglasMolestia.niveles.map { it.texto } + ReglasSupleEstado.Estado.entries.flatMap { listOf(it.accion, it.marcado) } + ReglasMolestia.zonas.map { it.nombre }
        for (t in propios) assertTrue("\"$t\"" in swift, t)
        val enSwift = Regex("""public static let \w+ = "([^"]*)"""").findAll(Vectores.texto(Vectores.raizRepo.resolve("apps/ios/MyPumpKit/Sources/MyPumpReglas/TextosFeedback.swift"))).map { it.groupValues[1] }.toList()
        assertTrue(enSwift.size >= 30)
        for (t in enSwift) assertTrue(t in TextosFeedback.todos, t)
    }
}
