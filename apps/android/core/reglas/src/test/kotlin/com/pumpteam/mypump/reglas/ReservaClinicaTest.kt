package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Bloque
import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.Progresion
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Reserva clínica (19/11, OK de Mati): el plan que deja reps en reserva a propósito nunca ve «Al fallo», «llevá al fallo» ni
 * «Subí la carga»; ve la pauta del plan. Mismos vectores que la web y iOS (`reserva_clinica.json`).
 */
class ReservaClinicaTest {
    private val v: JsonObject = Vectores.json(Vectores.publico("reserva_clinica"))
    private val prohibido = Regex(v.getValue("prohibido").jsonPrimitive.content, RegexOption.IGNORE_CASE)

    private fun txt(e: JsonElement?): String? = if (e == null || e is JsonNull) null else e.jsonPrimitive.content
    private fun JsonObject.lista(k: String): List<JsonObject> = getValue(k).jsonArray.map { it.jsonObject }
    private fun ejercicios(e: JsonElement): List<Ejercicio> = e.jsonArray.map { Ejercicio.desde(it) }
    private fun dia(e: JsonElement) = Dia(id = "d1", bloques = listOf(Bloque(ejercicios = ejercicios(e))))
    private fun nota(n: NotaProgresion?) = n?.let { Triple(it.texto, it.cambia, it.calibracion) }
    private fun esperada(e: JsonElement?) = (e as? JsonObject)?.let {
        Triple(it.getValue("texto").jsonPrimitive.content, it.getValue("cambia").jsonPrimitive.boolean, it.getValue("calibracion").jsonPrimitive.boolean)
    }

    @Test fun cuandoElRirPideReserva() {
        val i = v.getValue("indicada").jsonObject
        for (x in i.getValue("si").jsonArray) assertTrue(ReservaClinica.indicada(txt(x)), "$x")
        for (x in i.getValue("no").jsonArray) assertFalse(ReservaClinica.indicada(txt(x)), "$x")
    }

    @Test fun leyendaConReserva() {
        for (c in v.lista("leyenda")) assertEquals(txt(c["sale"]), ReservaClinica.leyenda(txt(c["rir"])), "$c")
        assertEquals(" dejando 2–3 en reserva", ReservaClinica.frase("Dejando 2–3 en reserva"))
        assertEquals("", ReservaClinica.frase(null))
    }

    @Test fun quePlanesTienenReserva() {
        val planes = v.lista("planes")
        assertEquals(10, planes.size)
        for (c in planes) {
            assertEquals(c.getValue("sale").jsonPrimitive.boolean,
                ReservaClinica.delPlan(listOf(dia(c.getValue("ejercicios"))), c["semana"]?.jsonPrimitive?.intOrNull), c.getValue("nombre").jsonPrimitive.content)
        }
        assertFalse(ReservaClinica.delPlan(emptyList(), 1))
    }

    @Test fun laNotaEsLaPautaDelPlan() {
        for (c in v.lista("notas")) {
            val e = Ejercicio.desde(c.getValue("ejercicio"))
            val semana = c["semana"]?.jsonPrimitive?.intOrNull
            val con = Progresiones.nota(e, semana, reservaClinica = true)
            val nombre = c.getValue("nombre").jsonPrimitive.content
            assertEquals(esperada(c["sale"]), nota(con), "con reserva: $nombre")
            assertEquals(esperada(c["sinReserva"]), nota(Progresiones.nota(e, semana)), "sin reserva: $nombre")
            assertFalse(prohibido.containsMatchIn(con!!.texto), con.texto)
        }
    }

    @Test fun sinCartelConReserva() {
        for (c in v.lista("banner")) {
            val d = dia(c.getValue("ejercicios"))
            val semana = c.getValue("semana").jsonPrimitive.int
            val offset = c.getValue("offset").jsonPrimitive.int
            val nombre = c.getValue("nombre").jsonPrimitive.content
            val es = c.getValue("sinReserva").jsonObject
            val ec = c.getValue("conReserva").jsonObject
            assertEquals(BannerSemana(es.getValue("cambian").jsonPrimitive.int, es.getValue("calibracion").jsonPrimitive.boolean),
                SemanaEntreno.banner(d, semana, offset), nombre)
            val con = SemanaEntreno.banner(d, semana, offset, reservaClinica = true)
            assertEquals(BannerSemana(ec.getValue("cambian").jsonPrimitive.int, ec.getValue("calibracion").jsonPrimitive.boolean), con, nombre)
            assertNull(con.texto)
        }
    }

    @Test fun laCargaNuncaSugiereSubirConReserva() {
        for (c in v.lista("aumento")) {
            val e = Ejercicio.desde(c.getValue("ejercicio"))
            val semana = c.getValue("semana").jsonPrimitive.int
            val refs = c.lista("ultimaVez").map { CargaSimple.Referencia(it.getValue("reps").jsonPrimitive.int, it["kg"]?.jsonPrimitive?.doubleOrNull) }
            val equipo = Preparacion.Equipo.valueOf(c.getValue("equipo").jsonPrimitive.content.uppercase())
            fun armar(reserva: Boolean, estado: CargaSimple.Estado? = null) =
                CargaSimple(e, semana, refs, equipo, estado = estado, reservaClinica = reserva)
            val es = c.getValue("sinReserva").jsonObject
            val nombre = c.getValue("nombre").jsonPrimitive.content
            val sin = armar(false)
            assertEquals(CargaSimple.Aumento.Sugerido(es.getValue("desde").jsonPrimitive.double, es.getValue("hasta").jsonPrimitive.double), sin.aumento, nombre)
            assertEquals(CargaSimple.Aumento.NoCorresponde, armar(true).aumento, nombre)
            assertTrue(AumentoCarga.corresponde(e, semana))
            assertFalse(AumentoCarga.corresponde(e, semana, reservaClinica = true))
            // Guardado antes de este arreglo con la sugerencia: con reserva se cae y la carga sigue en la de la última vez.
            val guardado = sin.estado
            assertEquals(CargaSimple.Aumento.NoCorresponde, armar(true, guardado).aumento)
            assertEquals(es.getValue("desde").jsonPrimitive.double, armar(true, guardado).carga)
            assertEquals(sin.aumento, armar(false, guardado).aumento)
            // Lo que el alumno ya aceptó, queda.
            sin.aceptarAumento()
            assertTrue(armar(true, sin.estado).aumento is CargaSimple.Aumento.Aceptado, "lo aceptado se perdió")
        }
    }

    @Test fun laLeyendaDelDia() {
        val c = v.lista("planes")[0]   // 2-3 en todas las semanas
        val d = DiaEnCurso(dia(c.getValue("ejercicios")), 2)
        val id = d.lista[0].id
        assertEquals("Al fallo", d.leyendaRir(id), "sin reserva clínica, como siempre (2.3.0)")
        assertEquals("Dejando 2–3 en reserva", d.leyendaRir(id, reservaClinica = true))
        assertNull(d.leyendaRir(d.lista[1].id, reservaClinica = true), "la plancha no lleva RIR")
        // Una semana sin rir en un plan con reserva (el taper): ninguna leyenda, nunca «Al fallo».
        val taper = Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(Ejercicio(
            id = "a", nombre = "Sentadilla con barra", tipo = "compuesto",
            progresion = listOf(Progresion(1, 3, "3", "3"), Progresion(2, 3, "2", null), Progresion(3, 3, "8", "1-2")),
        )))))
        val dt = DiaEnCurso(taper, 2)
        assertTrue(ReservaClinica.delPlan(listOf(taper), 2))
        assertNull(dt.leyendaRir("a", reservaClinica = true))
        assertEquals("Al fallo", dt.leyendaRir("a"))
        // El aviso de primera vez sigue a la leyenda.
        assertEquals("llegues a 10 reps dejando 2–3 en reserva.", RirDelPlan.calibracion("llegues a 10 reps dejando 1–2 en reserva.", "Dejando 2–3 en reserva"))
        assertEquals("llegues a 10 reps.", RirDelPlan.calibracion("llegues a 10 reps dejando 1–2 en reserva.", null))
    }

    @Test fun laNotaTecnicaVaEnteraConReserva() {
        val n = "Dejá 2 repeticiones en reserva y bajá controlado."
        assertEquals(n, TextoAlumno.notaParaAlumno(n, null, clinica = true))
        assertEquals(TextoAlumno.sinRIR(n), TextoAlumno.notaParaAlumno(n, "0"))
        assertEquals("Cerca del fallo, sin trampa.", TextoAlumno.notaParaAlumno("Cerca del fallo, sin trampa.", null, clinica = true))
    }
}
