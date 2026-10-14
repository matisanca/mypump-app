package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import java.nio.file.Path
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de VectoresTests.swift: `getProgresionActual`, `computeProgresionNota` y `claveEjercicio` de la web, corridas
// por scripts/nativa/generar-vectores.mjs.

private fun fallasProgresion(archivo: Path): Pair<Int, List<String>> {
    val v = Vectores.json(archivo)
    val ejercicios = v["ejercicios"]!!.jsonArray.map(Ejercicio::desde)
    val casos = v["casos"]!!.jsonArray
    val fallas = mutableListOf<String>()
    for (c in casos.map { it.jsonObject }) {
        val e = ejercicios[c["e"]!!.jsonPrimitive.int]
        val semana = c["semana"]!!.jsonPrimitive.int
        val actual = c["actual"]!!.jsonObject
        val p = Progresiones.pauta(e, semana)
        if (!(igualAJs(actual["series"], p.series) && igualAJs(actual["reps"], p.reps) && igualAJs(actual["rir"], p.rir))) {
            fallas += "pauta ${e.id} sem $semana: esperado $actual, kotlin $p"
        }
        val n = Progresiones.nota(e, semana)
        val nota = c["nota"]!!
        if (nota is JsonNull) {
            if (n != null) fallas += "nota ${e.id} sem $semana: esperado null, kotlin $n"
        } else {
            val o = nota.jsonObject
            val ok = n != null && n.texto == o["texto"]!!.jsonPrimitive.content &&
                n.cambia == (o["cambia"] == JsonPrimitive(true)) && n.calibracion == (o["calibracion"] == JsonPrimitive(true))
            if (!ok) fallas += "nota ${e.id} sem $semana: esperado $o, kotlin $n"
        }
    }
    return casos.size to fallas
}

class ProgresionVectoresTest {
    @Test
    fun vectoresPublicos() {
        val (total, fallas) = fallasProgresion(Vectores.publico("progresion"))
        assertTrue(total > 500, "$total casos")
        assertEquals(emptyList<String>(), fallas.take(5), "${fallas.size} de $total")
    }

    @Test
    fun vectoresDeLosPlanesReales() {
        val (total, fallas) = fallasProgresion(Vectores.privado("progresion"))
        assertTrue(total > 10_000, "$total casos")
        assertEquals(emptyList<String>(), fallas.take(5), "${fallas.size} de $total")
    }

    @Test
    fun topeComoElUpperDeJs() {
        assertEquals(10.0, Progresiones.tope("8-10"))
        assertEquals(10.0, Progresiones.tope("10 min"))
        assertEquals(0.0, Progresiones.tope("0 (al fallo)"))
        assertNull(Progresiones.tope(null))
        assertNull(Progresiones.tope("AMRAP"))
        assertEquals(20.0, Progresiones.tope("12/15/20"))
        assertEquals(1e25, Progresiones.tope("10000000000000000000000000 reps"))   // Number() de JS, no un Int que desborda
        assertNull(Progresiones.tope("١٢"))                                          // \d de JS es ASCII
    }
}

private fun fallasClave(archivo: Path): Pair<Int, List<String>> {
    val casos = Vectores.json(archivo)["casos"]!!.jsonArray.map { it.jsonObject }
    val fallas = casos.mapNotNull { c ->
        val nombre = c["nombre"]!!.jsonPrimitive.content
        val web = c["clave"]!!.jsonPrimitive.content
        val kotlin = ClaveEjercicio.de(nombre)
        if (kotlin == web) null else "${nombre.debug()}: web ${web.debug()}, kotlin ${kotlin.debug()}"
    }
    return casos.size to fallas
}

class ClaveVectoresTest {
    @Test
    fun vectoresPublicos() {
        val (n, fallas) = fallasClave(Vectores.publico("clave_ejercicio"))
        assertTrue(n > 20, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(8), "${fallas.size} de $n")
    }

    @Test
    fun nombresRealesDeLaBase() {
        val (n, fallas) = fallasClave(Vectores.privado("clave_ejercicio"))
        assertTrue(n > 500, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(8), "${fallas.size} de $n")
    }

    @Test
    fun loQueIcuHariaDistinto() {
        // El `.` de JS toma VT, FF y NEL: el paréntesis se va entero (con el `.` de ICU o de Java, no).
        assertEquals("curl martillo", ClaveEjercicio.de("Curl (a\u000Bb) martillo"))
        assertEquals("curl martillo", ClaveEjercicio.de("Curl (a\u0085b) martillo"))
        assertEquals("curl a b martillo", ClaveEjercicio.de("Curl (a\nb) martillo"))
        assertEquals("rsted row", ClaveEjercicio.de("Ørsted row"))      // la ø no es una o con tilde
        assertEquals("inclinado", ClaveEjercicio.de("İnclinado"))
    }
}
