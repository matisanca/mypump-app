package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.ValorJson
import java.nio.file.Path
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de PorcionYAnclajeTests.swift: `porcionReferencia`, `_huellaFood` y `_swapAplicable` de la web.

private fun fallasPorcion(archivo: Path): Pair<Int, List<String>> {
    val casos = Vectores.json(archivo)["casos"]!!.jsonArray.map { it.jsonObject }
    val fallas = mutableListOf<String>()
    for (c in casos) {
        val a = ValorJson.desde(c["alimento"]!!)
        // Lo que lee la web del alimento: String(x || '') para los textos y Number(x) para los números.
        val kotlin = PorcionCasera.referencia(
            nombre = SemanticaJs.texto(a["name"]),
            qty = SemanticaJs.numero(a["qty"]),
            unidad = SemanticaJs.texto(a["unit"]),
            gramosPorUnidad = a["unitGrams"]?.let(SemanticaJs::numero),
        )
        val web = c["porcion"]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content
        if (kotlin != web) fallas += "${a.serializar()}: web $web, kotlin $kotlin"
    }
    return casos.size to fallas
}

private fun fallasAnclaje(archivo: Path): Pair<Int, List<String>> {
    val casos = Vectores.json(archivo)["casos"]!!.jsonArray.map { it.jsonObject }
    fun clave(c: kotlinx.serialization.json.JsonObject) =
        "${c["dieta"]}|${c["comidaId"]!!.jsonPrimitive.content}|${c["optIdx"]}|${c["foodIdx"]}"
    // Los alimentos de esa posición en todos los tipos de día se reconstruyen de los mismos vectores, agrupando por
    // (dieta, comida, opción, índice): el generador evaluó cada caso contra su propia dieta.
    val porPosicion = HashMap<String, MutableList<Alimento>>()
    for (c in casos) {
        val a = Alimento.desde(c["original"]!!)
        val lista = porPosicion.getOrPut(clave(c)) { mutableListOf() }
        if (lista.none { AnclajeSwaps.huella(it) == AnclajeSwaps.huella(a) }) lista += a
    }
    val fallas = mutableListOf<String>()
    for (c in casos) {
        val original = Alimento.desde(c["original"]!!)
        val actual = ValorJson.desde(c["current"]!!)
        val enPosicion = { porPosicion[clave(c)] ?: emptyList<Alimento>() }
        val con = AnclajeSwaps.aplica(actual, original, c["comidaId"]!!.jsonPrimitive.content, enPosicion)
        val sin = AnclajeSwaps.aplica(actual, original, null, enPosicion)
        val web = c["aplica"]!!.jsonPrimitive.boolean
        val webSin = c["aplicaSinComida"]!!.jsonPrimitive.boolean
        if (con != web || sin != webSin) fallas += "${original.nombre} ${actual.serializar()}: web $web/$webSin, kotlin $con/$sin"
    }
    return casos.size to fallas
}

class PorcionYAnclajeTest {
    @Test
    fun porcionPublica() {
        val (n, fallas) = fallasPorcion(Vectores.publico("porcion_casera"))
        assertTrue(n > 1000, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(6), "${fallas.size} de $n")
    }

    @Test
    fun porcionDietasReales() {
        val (n, fallas) = fallasPorcion(Vectores.privado("porcion_casera"))
        assertTrue(n > 100, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(6), "${fallas.size} de $n")
    }

    @Test
    fun anclajePublico() {
        val (n, fallas) = fallasAnclaje(Vectores.publico("anclaje_swaps"))
        assertTrue(n > 100, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(6), "${fallas.size} de $n")
    }

    @Test
    fun anclajeDietasReales() {
        val (n, fallas) = fallasAnclaje(Vectores.privado("anclaje_swaps"))
        assertTrue(n > 1000, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(6), "${fallas.size} de $n")
    }

    @Test
    fun avenaDeEntrenoVistaEnDescanso() {
        val avena50 = Alimento(nombre = "Avena", qty = 50.0, unidad = "g")
        val avena80 = Alimento(nombre = "Avena", qty = 80.0, unidad = "g")
        val swap = ValorJson.objeto(
            "name" to ValorJson.Texto("Granola"),
            "_orig" to ValorJson.objeto("name" to ValorJson.Texto("Avena"), "qty" to ValorJson.Numero(80.0), "unit" to ValorJson.Texto("g")),
        )
        assertTrue(AnclajeSwaps.aplica(swap, avena50, "desayuno") { listOf(avena80, avena50) })
        assertFalse(AnclajeSwaps.aplica(swap, avena50, null) { listOf(avena80, avena50) })
        // Mati publicó 60 → 80 sin que quede ningún 60: el swap ya no vale.
        assertFalse(AnclajeSwaps.aplica(swap, avena50, "desayuno") { listOf(avena50) })
    }

    @Test
    fun huellaComoLaWeb() {
        assertEquals("pan lactal|60|g", AnclajeSwaps.huella("  PAN LACTAL ", 60.0, " G "))
        assertEquals("avena|0|g", AnclajeSwaps.huella("Avena", Double.NaN, "g"))
        assertEquals("avena|0.30000000000000004|g", AnclajeSwaps.huella("Avena", 0.1 + 0.2, "g"))
        // Un ancla con la qty como texto o el nombre como número: Number("80") y String(5), como la web.
        val ancla = ValorJson.objeto("name" to ValorJson.Numero(5.0), "qty" to ValorJson.Texto(" 80 "), "unit" to ValorJson.Nulo)
        assertEquals("5|80|", AnclajeSwaps.huella(ancla))
        // Un food_data que JS considera falso no es un swap (Swift solo miraba el null).
        assertFalse(AnclajeSwaps.aplica(ValorJson.Texto(""), Alimento("Pan"), "c1") { emptyList() })
        assertFalse(AnclajeSwaps.aplica(ValorJson.Numero(0.0), Alimento("Pan"), "c1") { emptyList() })
    }

    /** Lo esperado salió de `porcionReferencia` corrida en node. */
    @Test
    fun porcionesConocidas() {
        assertEquals("1½ palmas", PorcionCasera.referencia("Pechuga de pollo", 150.0, "g", null))
        assertEquals("1½ palmas", PorcionCasera.referencia("Pechuga de pollo cruda", 230.0, "g", null)) // 172,5 g cocida
        assertEquals("¾ taza en crudo (≈ 2 tazas cocido)", PorcionCasera.referencia("Arroz", 130.0, "g", null))
        assertEquals("3 huevos", PorcionCasera.referencia("Huevos", 3.0, "u", null))
        assertEquals("libre 🥗", PorcionCasera.referencia("Lechuga", 50.0, "g", null))
        assertEquals("1 lata y media", PorcionCasera.referencia("Atún", 200.0, "g", null))
        assertEquals(null, PorcionCasera.referencia("Pollo", Double.NaN, "g", null))
        // Una cantidad absurda se imprime como en la web (Swift pasaba por Int y se caía).
        assertEquals("1.0000000000000001e+23 palmas", PorcionCasera.referencia("Pollo", 1e25, "g", null))
        assertEquals("3.3333333333333333e+28 rebanadas", PorcionCasera.referencia("Pan", 1e30, "g", null))
        assertEquals("1.25e+22 tazas", PorcionCasera.referencia("Avena", 1e24, "g", null))
    }
}
