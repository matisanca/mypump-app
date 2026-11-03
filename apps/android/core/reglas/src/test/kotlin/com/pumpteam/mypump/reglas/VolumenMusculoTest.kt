package com.pumpteam.mypump.reglas

import java.nio.file.Files
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de VolumenMusculoTests.swift: 2.1, S2, los casos a mano de `apps/shared/vectores/volumen.json`.

private fun JsonElement?.lista(): JsonArray = this as? JsonArray ?: JsonArray(emptyList())
private fun JsonElement?.num(): Double? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.doubleOrNull
private fun JsonElement?.txt(): String? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content

private fun registros(v: JsonElement?): List<VolumenMusculo.Registro> = v.lista().map { it.jsonObject }.map {
    VolumenMusculo.Registro(it["musculo"].txt(), it["tipo"].txt(), it["fecha"].txt() ?: "", it["lugar"].txt() ?: "", it["serie"].num()?.toInt(), it["clave"].txt())
}

class VolumenMusculoTest {
    private val v: JsonObject = Json.parseToJsonElement(Files.readString(Vectores.publico("volumen"))).jsonObject

    @Test fun losCasosCompartidos() {
        val casos = v["casos"].lista().map { it.jsonObject }
        assertTrue(casos.size >= 15)
        for (c in casos) {
            val nombre = c["nombre"].txt()!!
            val r = VolumenMusculo.calcular(registros(c["historial"]), registros(c["enVivo"]), c["hoy"].txt()!!)
            val sale = c["sale"]!!.jsonObject
            assertEquals(sale["semana"].txt(), r.semana, nombre)
            assertEquals(sale["total"].num()!!.toInt(), r.total, nombre)
            assertEquals(sale["totalAnterior"].num()!!.toInt(), r.totalAnterior, nombre)
            assertEquals(sale["totalHoy"].num()!!.toInt(), r.totalHoy, nombre)
            val filas = sale["filas"].lista().map { it.jsonObject }
            assertEquals(filas.size, r.filas.size, "$nombre: ${r.filas}")
            for ((a, b) in r.filas.zip(filas)) {
                assertEquals(b["musculo"].txt(), a.musculo, nombre)
                assertEquals(b["nombre"].txt(), a.nombre, nombre)
                assertEquals(b["semana"].num()!!.toInt(), a.semana, "$nombre: $a")
                assertEquals(b["anterior"].num()!!.toInt(), a.anterior, "$nombre: $a")
                assertEquals(b["hoy"].num()!!.toInt(), a.hoy, "$nombre: $a")
            }
            assertEquals(sale["deHoy"].lista().map { it.txt() }, r.filasDeHoy.map { it.musculo }, nombre)
        }
    }

    @Test fun textos() {
        assertEquals("1 serie", VolumenMusculo.series(1))
        assertEquals("0 series", VolumenMusculo.series(0))
        assertEquals("Espalda media", VolumenMusculo.nombre("middle back"))
        assertEquals("Sin músculo asignado", VolumenMusculo.nombre(null))
        val f = VolumenMusculo.Fila("chest", "Pecho", 12, 10, 0)
        assertEquals("Pecho, 12 series esta semana, 10 la semana pasada", f.textoAccesible)
    }
}
