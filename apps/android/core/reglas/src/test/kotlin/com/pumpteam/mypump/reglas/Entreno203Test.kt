package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Bloque
import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.Progresion
import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.modelos.ValorJson
import java.nio.file.Files
import java.time.ZoneId
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
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de Entreno203Tests.swift (2.0.3): el descanso elegido a mano (E2), el aviso de récord (E3) y el RIR que arranca
// en el objetivo (E4). Casos a mano en `apps/shared/vectores/entreno_203.json` (la web no tiene estas reglas).

private fun JsonElement?.lista(): JsonArray = this as? JsonArray ?: JsonArray(emptyList())
private fun JsonElement?.num(): Double? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.doubleOrNull
private fun JsonElement?.txt(): String? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content
private fun JsonElement?.bool(): Boolean? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.booleanOrNull

class Entreno203Test {
    private val v: JsonObject = Json.parseToJsonElement(Files.readString(Vectores.publico("entreno_203"))).jsonObject
    private val zona: ZoneId = ZoneId.of("America/Argentina/Buenos_Aires")

    @Test fun descansoPropio() {
        val d = v["descanso"]!!.jsonObject
        assertEquals(d["opciones"].lista().map { it.num()!!.toInt() }, DescansoPropio.opciones)
        val casos = d["casos"].lista()
        assertTrue(casos.size >= 8)
        for (c in casos.map { it.jsonObject }) {
            val s = DescansoPropio.segundos(c["propio"].num()?.toInt(), c["plan"].num()?.toInt())
            assertEquals(c["sale"].num()!!.toInt(), s, c.toString())
        }
    }

    @Test fun rirInicial() {
        val casos = v["rirInicial"]!!.jsonObject["casos"].lista()
        assertTrue(casos.size >= 10)
        for (c in casos.map { it.jsonObject }) assertEquals(c["sale"].txt(), RirInicial.de(c["objetivo"].txt()), c.toString())
    }

    @Test fun record() {
        val casos = v["record"]!!.jsonObject["casos"].lista()
        assertTrue(casos.size >= 12)
        fun marca(j: JsonElement) = j.jsonObject.let { RecordSerie.Marca(it["kg"].num()!!, it["reps"].num()!!.toInt()) }
        for (c in casos.map { it.jsonObject }) {
            val a = RecordSerie.evaluar(
                marca(c["serie"]!!), c["sinKg"].bool() ?: false, c["verosimil"].bool() ?: true,
                c["anteriores"].lista().map(::marca), c["hoy"].lista().map(::marca),
            )
            assertEquals(c["sale"].txt(), a?.texto, c["nombre"].txt())
        }
    }

    private fun fila(fecha: String, kg: Double, reps: Int) =
        RegistroHistorico(null, null, "${fecha}T15:00:00+00:00", kg, reps, null, 1, null, null)

    /** El récord sale contra los días anteriores (no contra hoy) y no se repite con el mismo peso. */
    @Test fun recordAlConfirmar() {
        val ex = Ejercicio(id = "e1", nombre = "Press banca", tipo = "compuesto", series = 3, reps = "8-10", rirObjetivo = "1-2")
        val d = DiaEnCurso(Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(ex)))), semana = 1, sesionId = "s1", zona = zona)
        d.historial = mapOf("e1" to listOf(fila("2026-11-03", 90.0, 10), fila("2026-10-30", 80.0, 10)))
        d.escribir("e1", 0, "reps", "8"); d.escribir("e1", 0, "kg", "82,5")
        assertEquals("Récord: +2,5 kg", d.confirmarSerie("e1", 0, hoy = "2026-11-03").record?.texto, "los 90 kg de hoy no cuentan")
        d.escribir("e1", 1, "reps", "8"); d.escribir("e1", 1, "kg", "82.5")
        assertNull(d.confirmarSerie("e1", 1, hoy = "2026-11-03").record, "ya avisado")
        d.escribir("e1", 2, "reps", "9"); d.escribir("e1", 2, "kg", "82.5")
        assertEquals("Récord: +1 rep", d.confirmarSerie("e1", 2, hoy = "2026-11-03").record?.texto)
    }

    /** E2: el descanso del ejercicio (por su clave) le gana al del plan y es el que arranca al confirmar. */
    @Test fun descansoElegidoArrancaAlConfirmar() {
        val ex = Ejercicio(id = "e1", nombre = "Remo con barra", tipo = "compuesto", series = 2, reps = "10", descansoSegundos = 120)
        val d = DiaEnCurso(Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(ex)))), semana = 1, sesionId = "s1")
        assertTrue(d.descanso("e1") == 120 && !d.tieneDescansoPropio("e1"))
        d.descansosPropios = mapOf(ClaveEjercicio.de("Remo con barra") to 75)
        assertTrue(d.descanso("e1") == 75 && d.tieneDescansoPropio("e1"))
        assertEquals(75, d.copia().descanso("e1"), "la copia lo conserva")
        d.escribir("e1", 0, "reps", "10"); d.escribir("e1", 0, "kg", "60")
        assertTrue(d.confirmarSerie("e1", 0).efectos.contains(DiaEnCurso.Efecto.IniciarDescanso(75.0)))
    }

    /** E4: arranca en el objetivo de la semana; sin objetivo queda vacío y se guarda null; lo confirmado no se toca. */
    @Test fun rirPreseleccionado() {
        val e1 = Ejercicio(id = "e1", nombre = "Press banca", series = 2, reps = "8", progresion = listOf(Progresion(semana = 1, series = 2, reps = "8", rir = "1-2")))
        val e2 = Ejercicio(id = "e2", nombre = "Curl", series = 1, reps = "12")
        val d = DiaEnCurso(Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(e1, e2)))), semana = 1, sesionId = "s1")
        d.escribir("e1", 1, "rir", "3")
        d.preseleccionarRir()
        assertEquals(listOf("1", "3"), d.ejercicios.getValue("e1").series.map { it.rir })
        assertEquals(listOf(""), d.ejercicios.getValue("e2").series.map { it.rir })
        d.escribir("e2", 0, "reps", "12"); d.escribir("e2", 0, "kg", "10")
        val carga = d.confirmarSerie("e2", 0).efectos.filterIsInstance<DiaEnCurso.Efecto.Encolar>().first { it.kind == "carga" }
        assertEquals(ValorJson.Nulo, carga.payload["datos"]?.get("rir"), "RIR sin cargar va null")
        assertFalse(d.ejercicios.getValue("e2").series[0].rir.isNotEmpty())
    }
}
