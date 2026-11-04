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

    @Test fun rirDelPlan() {
        val casos = v["rir"]!!.jsonObject["casos"].lista()
        assertTrue(casos.size >= 12)
        for (c in casos.map { it.jsonObject }) {
            assertEquals(c["guarda"].txt(), RirDelPlan.guardar(c["objetivo"].txt()), c.toString())
            assertEquals(c["leyenda"].txt(), RirDelPlan.leyenda(c["objetivo"].txt()), c.toString())
        }
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

    /** El RIR del plan al confirmar: el primer número del rango, 0 sin objetivo; el calentamiento null; lo registrado no se toca. */
    @Test fun rirDelPlanAlConfirmar() {
        val e1 = Ejercicio(id = "e1", nombre = "Press banca", series = 2, reps = "8", progresion = listOf(Progresion(semana = 1, series = 2, reps = "8", rir = "1-2")))
        val e2 = Ejercicio(id = "e2", nombre = "Curl", series = 1, reps = "12")
        val e3 = Ejercicio(id = "e3", nombre = "Movilidad", tipo = "calentamiento", series = 1, reps = "10")
        val d = DiaEnCurso(Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(e1, e2, e3)))), semana = 1, sesionId = "s1")
        assertEquals("Dejando 1–2 en reserva", d.leyendaRir("e1"))
        assertEquals("Al fallo", d.leyendaRir("e2"))
        fun cargaRir(id: String, idx: Int): ValorJson? {
            d.escribir(id, idx, "reps", "8"); d.escribir(id, idx, "kg", "10")
            d.fijarRirDelPlan(id, idx)
            val carga = d.confirmarSerie(id, idx).efectos.filterIsInstance<DiaEnCurso.Efecto.Encolar>().first { it.kind == "carga" }
            return carga.payload["datos"]?.get("rir")
        }
        assertEquals(ValorJson.Numero(1.0), cargaRir("e1", 0))
        assertEquals(ValorJson.Numero(0.0), cargaRir("e2", 0))
        assertEquals(ValorJson.Nulo, cargaRir("e3", 0), "el calentamiento no es serie dura")
        d.ejercicios = d.ejercicios + ("e1" to d.ejercicios.getValue("e1").let { e -> e.copy(series = e.series.mapIndexed { i, s -> if (i == 1) s.copy(nombreRegistrado = "Press banca") else s }) })
        assertEquals(ValorJson.Nulo, cargaRir("e1", 1), "una serie ya registrada conserva su RIR")
    }

    /** E2: «Usar» no borra el propio aunque elija el del plan; sin mover la rueda con un del plan que no es opción, nada. */
    @Test fun usarDelSelector() {
        val casos = v["descanso"]!!.jsonObject["usar"]!!.jsonObject["casos"].lista()
        assertTrue(casos.size >= 6)
        for (c in casos.map { it.jsonObject }) {
            val g = DescansoPropio.alUsar(c["seleccion"].num()!!.toInt(), c["inicial"].num()!!.toInt(), c["plan"].num()!!.toInt(), c["propio"].bool()!!)
            assertEquals(c["guarda"].num()?.toInt(), g, c["nombre"].txt())
        }
    }

    /** El historial cortado por el tope: lleno y de un mes, no avisa; completo, o de más de medio año, sí. */
    @Test fun recordConHistoriaCorta() {
        val ex = Ejercicio(id = "e1", nombre = "Press banca", tipo = "compuesto", series = 1, reps = "8")
        fun confirmar(h: List<RegistroHistorico>): String? {
            val d = DiaEnCurso(Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(ex)))), semana = 1, sesionId = "s1", zona = zona)
            d.historial = mapOf("e1" to h)
            d.escribir("e1", 0, "reps", "8"); d.escribir("e1", 0, "kg", "82,5")
            return d.confirmarSerie("e1", 0, hoy = "2026-11-03").record?.texto
        }
        val corto = List(RecordSerie.TOPE_HISTORIAL) { fila("2026-10-01", 80.0, 8) }
        assertNull(confirmar(corto), "48 filas de un mes: la mejor puede ser más vieja")
        assertEquals("Récord: +2,5 kg", confirmar(corto.dropLast(1)), "47 filas: completo")
        assertEquals("Récord: +2,5 kg", confirmar(corto.dropLast(1) + fila("2026-04-01", 80.0, 8)), "48 filas de más de medio año")
    }

    /** El récord no se repite: el lápiz sobre la serie que lo dio, ni el mismo ejercicio en otro lugar del día. */
    @Test fun recordNoSeRepite() {
        val e1 = Ejercicio(id = "e1", nombre = "Press banca", tipo = "compuesto", series = 2, reps = "8")
        val e2 = Ejercicio(id = "e2", nombre = "Curl con barra", tipo = "aislamiento", series = 1, reps = "8")
        val e3 = Ejercicio(id = "e3", nombre = "Press banca", tipo = "compuesto", series = 1, reps = "8")
        val d = DiaEnCurso(Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(e1, e2, e3)))), semana = 1, sesionId = "s1", zona = zona)
        d.historial = mapOf("e1" to listOf(fila("2026-10-30", 80.0, 8)), "e3" to listOf(fila("2026-10-30", 80.0, 8)))
        d.escribir("e1", 0, "reps", "8"); d.escribir("e1", 0, "kg", "85")
        assertEquals("Récord: +5 kg", d.confirmarSerie("e1", 0, hoy = "2026-11-03").record?.texto)
        d.editarSerie("e1", 0)
        assertNull(d.copia().confirmarSerie("e1", 0, hoy = "2026-11-03").record, "el lápiz no repite el récord (también en la copia)")
        d.escribir("e3", 0, "reps", "8"); d.escribir("e3", 0, "kg", "85")
        assertNull(d.confirmarSerie("e3", 0, hoy = "2026-11-03").record, "mismo ejercicio en otro lugar")
        d.editarSerie("e3", 0)
        d.escribir("e3", 0, "kg", "87,5")
        assertEquals("Récord: +2,5 kg", d.confirmarSerie("e3", 0, hoy = "2026-11-03").record?.texto, "por encima de lo de hoy sí")
    }

    /** El RIR del que se hace: core y peso corporal en null; RPE es al fallo; el sustituto con peso lleva el de la pauta. */
    @Test fun rirDelQueSeHaceYCalibracion() {
        fun p(rir: String) = listOf(Progresion(semana = 1, series = 1, reps = "8", rir = rir))
        val e1 = Ejercicio(id = "e1", nombre = "Plancha", tipo = "core", series = 1, reps = "30", progresion = p("1-2"))
        val e2 = Ejercicio(id = "e2", nombre = "Flexiones de brazos", tipo = "compuesto", series = 1, reps = "8", progresion = p("1"))
        val e3 = Ejercicio(id = "e3", nombre = "Press banca", tipo = "compuesto", series = 1, reps = "8", progresion = p("RPE 8"))
        val d = DiaEnCurso(Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(e1, e2, e3)))), semana = 1, sesionId = "s1")
        assertNull(d.leyendaRir("e1")); assertNull(d.leyendaRir("e2"))
        assertEquals("Al fallo", d.leyendaRir("e3"))
        d.fijarRirDelPlan("e1", 0); d.fijarRirDelPlan("e2", 0); d.fijarRirDelPlan("e3", 0)
        assertEquals("", d.ejercicios.getValue("e1").series[0].rir)
        assertEquals("", d.ejercicios.getValue("e2").series[0].rir)
        assertEquals("0", d.ejercicios.getValue("e3").series[0].rir)
        d.fijarRirDelPlan("e2", 0, e2.copy(nombre = "Press banca con barra", equipo = "barbell"))
        assertEquals("1", d.ejercicios.getValue("e2").series[0].rir)
        assertEquals("… a 8 reps dejando 0–1 en reserva.", RirDelPlan.calibracion("… a 8 reps dejando 1–2 en reserva.", "Dejando 0–1 en reserva"))
        assertEquals("… a 8 reps al fallo.", RirDelPlan.calibracion("… a 8 reps dejando 1–2 en reserva.", "Al fallo"))
    }
}
