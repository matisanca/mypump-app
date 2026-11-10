package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.DietaActiva
import com.pumpteam.mypump.modelos.PlanSuplementacion
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.Suplementacion
import java.nio.file.Files
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** «Novedades de tu plan»: los mismos casos que iOS y la web (`apps/shared/fixtures/novedades/casos.json`). */
class NovedadesPlanTest {
    private val casos: JsonArray by lazy {
        Json.parseToJsonElement(Files.readString(Vectores.compartido("fixtures/novedades/casos.json"))).jsonArray
    }

    private fun <T> area(o: JsonObject, k: String, f: (JsonElement) -> T?): AreaPlan<T> {
        val v = o[k] ?: return AreaPlan.Desconocida
        if (v is JsonNull) return AreaPlan.Ninguna
        return f(v)?.let { AreaPlan.Hay(it) } ?: AreaPlan.Desconocida
    }

    private fun foto(o: JsonObject): FotoPlan {
        val s: AreaPlan<Suplementacion> = when (val a = area(o, "suplementacion") { PlanSuplementacion.desde(it) }) {
            is AreaPlan.Hay -> AreaPlan.Hay(a.valor.suplementacion)
            else -> if (o["suplementacion"] is JsonNull) AreaPlan.Ninguna else AreaPlan.Desconocida
        }
        return FotoPlan(area(o, "rutina") { RutinaActiva.desde(it) }, area(o, "dieta") { DietaActiva.desde(it) }, s)
    }

    private fun esperado(e: JsonElement?): ResumenNovedad? {
        if (e == null || e is JsonNull) return null
        val o = e.jsonObject
        return ResumenNovedad(
            o["titular"]!!.jsonPrimitive.content,
            o["resumen"]!!.jsonPrimitive.content,
            o["partes"]!!.jsonArray.map { p ->
                val x = p.jsonObject
                ParteNovedad(x["area"]!!.jsonPrimitive.content, x["titular"]!!.jsonPrimitive.content,
                    x["grande"]!!.jsonPrimitive.boolean, x["lineas"]!!.jsonArray.map { it.jsonPrimitive.content })
            },
        )
    }

    private fun resultado(c: JsonObject) = NovedadesPlan.calcular(foto(c["antes"]!!.jsonObject), foto(c["despues"]!!.jsonObject))

    @Test fun losCasosCompartidos() {
        assertTrue(casos.size >= 30)
        for (c in casos) {
            val o = c.jsonObject
            assertEquals(esperado(o["esperado"]), resultado(o), o["nombre"]!!.jsonPrimitive.content)
        }
    }

    @Test fun losTextosCumplenLasReglas() {
        for (c in casos) {
            val o = c.jsonObject
            val r = resultado(o) ?: continue
            val textos = listOf(r.titular, r.resumen) + r.partes.flatMap { listOf(it.titular) + it.lineas }
            for (t in textos) {
                val b = t.lowercase()
                assertFalse(":" in t || " - " in t || "—" in t || "–" in t, t)
                assertFalse("rir" in b || "fallo" in b || "coach" in b || "entrenador" in b, t)
            }
            val dosis = listOf("antes", "despues").mapNotNull { (foto(o[it]!!.jsonObject).suplementacion as? AreaPlan.Hay)?.valor }
                .flatMap { s -> s.items.flatMap { listOf(it.cantidad, it.antes) + it.tomas.map { t -> t.cantidad } } }.filterNotNull()
            for (p in r.partes) {
                assertTrue(p.lineas.size <= NovedadesPlan.MAX_LINEAS)
                for (l in p.lineas) for (d in dosis) assertFalse(d in l, "dosis en $l")
            }
        }
    }

    @Test fun formatos() {
        assertEquals("980", NovedadesPlan.formatoKcal(980.0))
        assertEquals("12.346", NovedadesPlan.formatoKcal(12345.6))
        assertEquals("1 unidad", NovedadesPlan.formatoCantidad(1.0, "u"))
        assertEquals("1,3 g", NovedadesPlan.formatoCantidad(1.25, "g"))
        assertEquals("1 unidad", NovedadesPlan.formatoCantidad(1.04, "u"))
        assertEquals("3 series", NovedadesPlan.formatoPauta(3, "10-12 al fallo"))
        assertEquals("3 series, AMRAP", NovedadesPlan.formatoPauta(3, "AMRAP"))
        assertEquals(NovedadesPlan.clave("Pre\u0301nsa"), NovedadesPlan.clave("Prénsa"))
        assertEquals("250 ml", NovedadesPlan.formatoCantidad(250.0, "ml"))
        assertEquals("30 g", NovedadesPlan.formatoCantidad(30.0, null))
        assertEquals("8 a 10", NovedadesPlan.repsNormal(" 8–10 "))
        assertEquals("a, b y c", NovedadesPlan.lista(listOf("a", "b", "c")))
    }
}
