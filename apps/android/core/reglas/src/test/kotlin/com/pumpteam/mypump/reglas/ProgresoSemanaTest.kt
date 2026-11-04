package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.RegistroHistorico
import java.time.ZoneId
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assertions.fail
import org.junit.jupiter.api.Test

/** Gemelo de ProgresoSemanaTests.swift: la línea de «Tu progreso» y los kilos, contra progreso_semana.json. */
class ProgresoSemanaTest {
    private val vector by lazy { Vectores.json(Vectores.publico("progreso_semana")) }

    @Test
    fun lineaComoLosVectores() {
        val casos = vector["casos"]!!.jsonArray
        assertTrue(casos.isNotEmpty())
        val fallas = mutableListOf<String>()
        for (c in casos) {
            val o = c.jsonObject
            val ejercicios = o["ejercicios"]!!.jsonArray.map { e ->
                val eo = e.jsonObject
                ProgresoSemana.Ejercicio(
                    eo["nombre"]!!.jsonPrimitive.content,
                    eo["sesiones"]!!.jsonObject.mapValues { it.value.jsonPrimitive.double },
                )
            }
            val esperado = o["esperado"]?.takeIf { it !is JsonNull }?.jsonObject?.let {
                ProgresoSemana.Linea(it["texto"]!!.jsonPrimitive.content, it["record"]!!.jsonPrimitive.boolean)
            }
            val kotlin = ProgresoSemana.linea(ejercicios, o["hoy"]!!.jsonPrimitive.content)
            if (kotlin != esperado) fallas += "${o["nombre"]!!.jsonPrimitive.content}: esperado $esperado, kotlin $kotlin"
        }
        if (fallas.isNotEmpty()) fail<Unit>(fallas.joinToString("\n"))
    }

    @Test
    fun kilosComoLosVectores() {
        for (k in vector["kilos"]!!.jsonArray) {
            val par = k.jsonArray
            assertEquals(par[1].jsonPrimitive.content, ProgresoSemana.kilos(par[0].jsonPrimitive.double))
        }
    }

    /** El historial: por día local, el máximo de kg (un peso nulo cuenta como 0). */
    @Test
    fun ejercicioDesdeElHistorial() {
        fun r(en: String, kg: Double?) = RegistroHistorico(null, null, en, kg, null, null, null, null, null)
        val e = ProgresoSemana.ejercicio(
            "Press banca",
            listOf(r("2026-11-03T12:00:00Z", 80.0), r("2026-11-03T13:00:00Z", 82.5), r("2026-11-01T12:00:00Z", null)),
            ZoneId.of("America/Argentina/Buenos_Aires"),
        )
        assertEquals(mapOf("2026-11-03" to 82.5, "2026-11-01" to 0.0), e.sesiones)
    }
}
