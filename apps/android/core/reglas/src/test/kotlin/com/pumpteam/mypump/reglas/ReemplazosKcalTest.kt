package com.pumpteam.mypump.reglas

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** 2.3.1: reemplazos de comida sin subir kcal en silencio (vectores `reemplazos_kcal.json`, iguales en la web e iOS). */
class ReemplazosKcalTest {
    private val v = Vectores.json(Vectores.publico("reemplazos_kcal"))
    private fun num(e: JsonElement?): Double? = if (e == null || e is JsonNull) null else e.jsonPrimitive.double
    private fun txt(e: JsonElement?): String? = if (e == null || e is JsonNull) null else e.jsonPrimitive.content
    private data class Item(val nombre: String, val kcal: Double?, val universal: Boolean, val propio: Boolean)

    @Test fun textos() {
        val t = v["textos"]!!.jsonObject
        assertEquals(txt(t["usarIgual"]), ReemplazosKcal.USAR_IGUAL)
        assertEquals(txt(t["elegirOtro"]), ReemplazosKcal.ELEGIR_OTRO)
        assertEquals(txt(t["deshacer"]), ReemplazosKcal.DESHACER)
    }

    @Test fun ordenar() {
        for (e in v["ordenar"]!!.jsonArray) {
            val c = e.jsonObject
            val items = c["subs"]!!.jsonArray.map { val o = it.jsonObject; Item(txt(o["nombre"])!!, num(o["kcal"]), o["universal"]!!.jsonPrimitive.boolean, o["propio"]!!.jsonPrimitive.boolean) }
            val o = ReemplazosKcal.ordenar(items, num(c["kcalOriginal"]), { it.kcal }, { it.universal }, { it.propio })
            assertEquals(c["universales"]!!.jsonArray.map { txt(it) }, o.universales.map { it.nombre }, txt(c["nombre"]))
            assertEquals(c["resto"]!!.jsonArray.map { txt(it) }, o.resto.map { it.nombre }, txt(c["nombre"]))
        }
    }

    @Test fun confirmar() {
        for (e in v["confirmar"]!!.jsonArray) {
            val c = e.jsonObject
            val o = num(c["kcalOriginal"]); val r = num(c["kcalReemplazo"]); val k = "$o→$r"
            assertEquals(c["desvioPct"]?.let { if (it is JsonNull) null else it.jsonPrimitive.long }, ReemplazosKcal.desvioPct(o, r), k)
            assertEquals(c["pide"]!!.jsonPrimitive.boolean, ReemplazosKcal.pideConfirmacion(o, r), k)
            assertEquals(c["suma"]!!.jsonPrimitive.long, ReemplazosKcal.suma(o, r), k)
            txt(c["texto"])?.let { assertEquals(it, ReemplazosKcal.textoConfirmacion(o, r), k) }
        }
    }

    @Test fun renglon() {
        for (e in v["renglon"]!!.jsonArray) {
            val c = e.jsonObject
            assertEquals(txt(c["texto"]), ReemplazosKcal.renglon(num(c["suma"])!!), txt(c["suma"]))
        }
    }
}
