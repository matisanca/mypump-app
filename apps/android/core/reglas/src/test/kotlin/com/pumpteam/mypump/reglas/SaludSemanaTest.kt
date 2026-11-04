package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.RecuperacionDia
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assertions.fail
import org.junit.jupiter.api.Test

/** Gemelo de SaludSemanaTests.swift: las filas de «Tu salud, últimos 7 días» contra salud_semana.json. */
class SaludSemanaTest {
    @Test
    fun resumenComoLosVectores() {
        val casos = Vectores.json(Vectores.publico("salud_semana"))["casos"]!!.jsonArray
        assertTrue(casos.isNotEmpty())
        val fallas = mutableListOf<String>()
        for (c in casos) {
            val o = c.jsonObject
            val nombre = o["nombre"]!!.jsonPrimitive.content
            val salud = o["salud"]!!.jsonArray.map(FilaSalud::desde)
            val recuperacion = o["recuperacion"]!!.jsonArray.map {
                val r = it.jsonObject
                RecuperacionDia(r["fecha"]!!.jsonPrimitive.content, score = r["score"]?.takeIf { s -> s !is JsonNull }?.jsonPrimitive?.int)
            }
            val esperado = o["esperado"]!!.jsonArray.map {
                val e = it.jsonObject
                SaludSemana.Fila(
                    e["clave"]!!.jsonPrimitive.content, e["etiqueta"]!!.jsonPrimitive.content,
                    e["valor"]!!.jsonPrimitive.content, e["detalle"]!!.jsonPrimitive.content,
                )
            }
            val kotlin = SaludSemana.resumen(salud, recuperacion, o["hoy"]!!.jsonPrimitive.content, o["mostrar_score"]!!.jsonPrimitive.boolean)
            if (kotlin != esperado) fallas += "$nombre:\n  esperado $esperado\n  kotlin   $kotlin"
        }
        if (fallas.isNotEmpty()) fail<Unit>(fallas.joinToString("\n"))
    }
}
