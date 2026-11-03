package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Aproximacion
import com.pumpteam.mypump.modelos.EstructuraRutina
import com.pumpteam.mypump.modelos.ValorJson
import java.nio.file.Files
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de PreparacionTests (Entreno203Tests.swift): E1 (2.0.3), los casos a mano de `apps/shared/vectores/preparacion.json`.

private fun JsonElement?.lista(): JsonArray = this as? JsonArray ?: JsonArray(emptyList())
private fun JsonElement?.num(): Double? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.doubleOrNull
private fun JsonElement?.txt(): String? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content
private fun JsonElement?.bool(): Boolean? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.booleanOrNull

class PreparacionTest {
    private val v: JsonObject = Json.parseToJsonElement(Files.readString(Vectores.publico("preparacion"))).jsonObject

    @Test fun losCasosCompartidos() {
        val dias = v["dias"]!!.jsonObject
        val casos = v["casos"].lista().map { it.jsonObject }
        assertTrue(casos.size >= 15)
        for (c in casos) {
            val nombre = c["nombre"].txt()!!
            val dia = dias[c["dia"].txt()!!].lista().map { it.jsonObject }.map {
                Preparacion.Entrada(it["tipo"].txt(), it["musculo"].txt(), it["nombre"].txt()!!, it["sinPeso"].bool()!!)
            }
            val plan = c["plan"]?.takeUnless { it is JsonNull }?.let { Aproximacion.lista(ValorJson.desde(it)) }
            val s = Preparacion.series(dia, c["indice"].num()!!.toInt(), c["ejercicio"].txt()!!, c["equipo"].txt(), c["sinKg"].bool()!!, c["kg"].num(), plan)
            val sale = c["sale"].lista().map { it.jsonObject }
            assertEquals(sale.size, s.size, "$nombre: $s")
            for ((a, b) in s.zip(sale)) {
                assertEquals(b["tipo"].txt(), a.tipo.valor, nombre)
                assertEquals(b["numero"].num()?.toInt(), a.numero, nombre)
                assertEquals(b["reps"].txt(), a.reps, nombre)
                assertEquals(b["kg"].num(), a.kg, "$nombre: $a")
                assertEquals(b["barraSola"].bool(), a.barraSola, nombre)
                assertEquals(b["opcional"].bool(), a.opcional, nombre)
                assertEquals(b["nota"].txt(), a.nota, nombre)
            }
        }
    }

    @Test fun clasificacion() {
        val casos = v["clasificacion"]!!.jsonObject["casos"].lista().map { it.jsonObject }
        assertTrue(casos.size >= 30)
        for (c in casos) {
            val n = c["nombre"].txt()!!
            assertEquals(c["principal"].bool(), Preparacion.esPrincipal(n, c["tipo"].txt()), "$n: principal")
            assertEquals(c["sinPreparacion"].bool(), Preparacion.sinPreparacion(n), "$n: sin preparación")
        }
    }

    /** El campo en la rutina: el decodificado nunca tira abajo el ejercicio ni la rutina. */
    @Test fun elCampoEnLaRutina() {
        val j = """{"dias":[{"id":"d1","bloques":[{"ejercicios":[{"id":"a","nombre":"A","aproximaciones":[{"reps":10,"pct":50}]},{"id":"b","nombre":"B","aproximaciones":{"x":1}},{"id":"c","nombre":"C","aproximaciones":[]},{"id":"d","nombre":"D"}]}]}]}"""
        val ej = EstructuraRutina.desde(Json.parseToJsonElement(j)).dias[0].bloques[0].ejercicios
        assertEquals(listOf("a", "b", "c", "d"), ej.map { it.id })
        assertEquals(listOf(Aproximacion(reps = "10", pct = 50.0)), ej[0].aproximaciones)
        assertNull(ej[1].aproximaciones)
        assertNull(ej[3].aproximaciones)
        assertEquals(emptyList<Aproximacion>(), ej[2].aproximaciones)
    }

    @Test fun textos() {
        assertEquals("Aproximación 2", Preparacion.Serie(Preparacion.Tipo.APROXIMACION, 2, "5", 22.5).etiqueta)
        assertEquals("22,5", Preparacion.Serie(Preparacion.Tipo.APROXIMACION, 2, "5", 22.5).textoKg)
        assertEquals("Potenciación (opcional)", Preparacion.Serie(Preparacion.Tipo.POTENCIACION, reps = "1-3", opcional = true).etiqueta)
        assertEquals("Barra sola", Preparacion.Serie(Preparacion.Tipo.CALENTAMIENTO, reps = "16-20", kg = 20.0, barraSola = true).textoKg)
        assertEquals(57.5, Preparacion.kgEfectivo("", "57.5"))
        assertEquals(60.5, Preparacion.kgEfectivo("60,5", "57.5"))
        assertNull(Preparacion.kgEfectivo("", "–"))
    }
}
