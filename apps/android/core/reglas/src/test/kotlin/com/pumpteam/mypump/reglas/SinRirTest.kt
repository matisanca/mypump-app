package com.pumpteam.mypump.reglas

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** REGLA DURA: RIR no aparece nunca en una pantalla del alumno. Mismos vectores que la web y iOS (`sin_rir.json`). */
class SinRirTest {
    private val v = Vectores.json(Vectores.publico("sin_rir"))
    private fun txt(e: kotlinx.serialization.json.JsonElement): String? = if (e is JsonNull) null else e.jsonPrimitive.content

    @Test fun los25TextosRealesQuedanSinRir() {
        val prohibido = Regex(v["prohibido"]!!.jsonPrimitive.content, RegexOption.IGNORE_CASE)
        val reales = v["reales"]!!.jsonArray
        assertEquals(25, reales.size)
        for (c in reales + v["otros"]!!.jsonArray) {
            val o = c.jsonObject
            val sale = TextoAlumno.sinRIR(o["entra"]!!.jsonPrimitive.content)
            assertEquals(o["sale"]!!.jsonPrimitive.content, sale, o["entra"]!!.jsonPrimitive.content)
            assertFalse(prohibido.containsMatchIn(sale), sale)
        }
        for (t in v["sinCambio"]!!.jsonArray) assertEquals(t.jsonPrimitive.content, TextoAlumno.sinRIR(t.jsonPrimitive.content))
    }

    @Test fun reservaClinicaDejaLaNotaEntera() {
        val r = v["reserva"]!!.jsonObject
        for (x in r["conReserva"]!!.jsonArray) assertTrue(TextoAlumno.conReserva(txt(x)), "$x")
        for (x in r["sinReserva"]!!.jsonArray) assertFalse(TextoAlumno.conReserva(txt(x)), "$x")
        for (c in r["casos"]!!.jsonArray) {
            val o = c.jsonObject
            assertEquals(txt(o["sale"]!!), TextoAlumno.notaParaAlumno(txt(o["entra"]!!), txt(o["rir"]!!)))
        }
        assertNull(TextoAlumno.notaParaAlumno("Quedate con 2 repeticiones en reserva.", "0"))
        assertNull(TextoAlumno.notaParaAlumno(null, null))
    }
}
