package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CargaSimple
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.TextoAlumno
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Reserva clínica (19/11, OK de Mati) en el modelo: un plan con RIR clínico y otro sin RIR, con todo lo que ve el alumno.
 * Con reserva nunca «Al fallo», «llevá al fallo» ni «Subí la carga». Gemelo de ReservaClinicaModeloTests.swift.
 */
class ReservaClinicaModeloTest {
    private val lugar = "pre-d1-0"
    private val clave = ClaveEjercicio.de("Press banca con barra")
    private val prohibido = Regex("""\bal fallo\b|sub[ií]\s+(un poco\s+)?la carga|toca subir|subí la próxima""", RegexOption.IGNORE_CASE)

    /** Press banca 4×10 → 4×8 (bajan las reps: sin reserva, «Subí la carga» y la sugerencia de subir) y unas aperturas sin historial. */
    private fun rutina(rir: String, semana: Int = 2): RutinaActiva {
        fun prog(reps: List<String>) = reps.mapIndexed { i, r -> """{"semana":${i + 1},"series":4,"reps":"$r","rir":"$rir"}""" }.joinToString(",")
        val est = """{"semanas_total":4,"dias":[{"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"B1","ejercicios":[""" +
            """{"id":"pre-d1-0","nombre":"Press banca con barra","tipo":"compuesto","descanso_segundos":120,"notas_tecnica":"Dejá 2 repeticiones en reserva y bajá controlado.","aproximaciones":[{"reps":"8","pct":60,"nota":"Con RIR 3, sin apurar."}],"progresion":[${prog(listOf("10", "8", "8", "6"))}]},""" +
            """{"id":"ape-d1-1","nombre":"Aperturas con mancuernas","tipo":"aislamiento","descanso_segundos":90,"progresion":[${prog(listOf("12", "12", "10", "10"))}]}""" +
            """]}]}]}"""
        return RutinaActiva.desde(ValorJson.parsear("""{"id":"r1","version":1,"semana_actual":$semana,"tiene_siguiente":false,"estructura":$est}""").aJson())
    }

    /** 80 kg × 10 hace una semana en el press (las aperturas, sin historial). */
    private fun historial(b: Banco) {
        val f = (1..4).map { """{"clave":"$clave","registrado_en":"2026-10-07T18:00:00Z","peso_kg":80,"reps_realizadas":10,"rir_real":0,"serie_numero":$it,"notas":null,"ejercicio_nombre":"Press banca con barra"}""" }
        b.servidor.cuando("get_historico_por_clave", "[${f.joinToString(",")}]")
    }

    private suspend fun modelo(b: Banco, r: RutinaActiva, token: String? = "tok-prueba"): ModeloEntreno {
        historial(b)
        return b.modelo(r, token).also { it.cargar() }
    }

    /** Todo lo que el alumno lee del entreno: el cartel y cada tarjeta (nota, leyenda, aviso de primera vez, nota técnica, preparación). */
    private fun textos(m: ModeloEntreno): List<String> {
        val t = mutableListOf<String>()
        m.banner.texto?.let(t::add)
        for (e in m.dia.value.lista) {
            val tj = m.tarjeta(e.id) ?: continue
            listOfNotNull(tj.nota?.texto, m.leyendaRir(e.id), TextoAlumno.notaParaAlumno(tj.efectivo.ejercicio.notasTecnica, tj.pauta.rir, tj.reservaClinica))
                .forEach(t::add)
            t += tj.filas.mapNotNull { it.calibracion }
            t += m.preparacion(e.id).mapNotNull { it.nota }
        }
        return t
    }

    @Test fun conReservaLaPautaDelPlanEnTodosLados() = enUnHilo { a: CoroutineScope ->
        val m = modelo(Banco(a), rutina("2-3"))
        assertTrue(m.reservaClinica)
        assertEquals(0, m.banner.cambian)
        assertFalse(m.banner.calibracion)
        assertNull(m.banner.texto)
        assertEquals("Seguí la pauta de esta semana (4×8), dejando 2 a 3 en reserva.", m.tarjeta(lugar)?.nota?.texto)
        assertEquals(false, m.tarjeta(lugar)?.nota?.cambia)
        assertEquals("Dejando 2 a 3 en reserva", m.leyendaRir(lugar))
        assertEquals(CargaSimple.Aumento.NoCorresponde, m.cargaSimple(lugar)?.aumento, "nunca «toca subir»")
        val t = textos(m)
        assertEquals(null, t.firstOrNull { prohibido.containsMatchIn(it) }, "apareció")
        assertTrue("Dejá 2 repeticiones en reserva y bajá controlado." in t, "la nota técnica de Mati entera")
        assertTrue("Con RIR 3, sin apurar." in t, "la nota de la preparación entera")
        assertTrue(t.any { "dejando 2 a 3 en reserva" in it && "Primera vez" in it }, "el aviso de primera vez con la reserva: $t")
    }

    @Test fun sinReservaTodoIgual() = enUnHilo { a: CoroutineScope ->
        val m = modelo(Banco(a), rutina("0"))
        assertFalse(m.reservaClinica)
        assertEquals(1, m.banner.cambian)
        assertTrue(m.tarjeta(lugar)?.nota?.texto?.contains("Subí la carga") == true)
        assertEquals("Al fallo", m.leyendaRir(lugar))
        assertEquals(CargaSimple.Aumento.Sugerido(80.0, 82.5), m.cargaSimple(lugar)?.aumento)
        val t = textos(m)
        assertFalse("Dejá 2 repeticiones en reserva y bajá controlado." in t, "sin reserva la nota va sin RIR")
        assertTrue(t.any { "al fallo" in it && "Primera vez" in it }, "$t")
    }

    @Test fun semanaUnoConReservaSinLaCalibracionAlFallo() = enUnHilo { a: CoroutineScope ->
        val m = modelo(Banco(a), rutina("2-3", semana = 1))
        assertFalse(m.banner.calibracion)
        assertNull(m.banner.texto)
        val n = m.tarjeta(lugar)?.nota
        assertEquals("Seguí la pauta de esta semana (4×10), dejando 2 a 3 en reserva.", n?.texto)
        assertTrue(n?.cambia == false && n.calibracion, "el rótulo «Semana 1», sin «al fallo»")
        assertEquals(null, textos(m).firstOrNull { prohibido.containsMatchIn(it) })
        val sin = modelo(Banco(a), rutina("0", semana = 1))
        assertTrue(sin.banner.calibracion)
        assertTrue(sin.tarjeta(lugar)?.nota?.texto?.startsWith("Semana de calibración. Llevá cada serie al fallo") == true)
    }

    @Test fun laDemoQuedaComoSiempre() = enUnHilo { a: CoroutineScope ->
        val m = modelo(Banco(a), rutina("2-3"), token = null)
        assertTrue(m.demo)
        assertFalse(m.reservaClinica)
        assertEquals("Al fallo", m.leyendaRir(lugar))
    }

    @Test fun otraRutinaSeVuelveACalcular() = enUnHilo { a: CoroutineScope ->
        val m = modelo(Banco(a), rutina("0"))
        assertFalse(m.reservaClinica)
        m.reemplazarRutina(rutina("2-3"))
        assertTrue(m.reservaClinica)
        assertEquals("Dejando 2 a 3 en reserva", m.leyendaRir(lugar))
        m.reemplazarRutina(rutina("0", semana = 3))
        assertFalse(m.reservaClinica)
    }
}
