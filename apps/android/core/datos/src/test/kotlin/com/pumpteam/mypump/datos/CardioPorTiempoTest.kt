package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RegistroSesion
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.DiaEnCurso
import com.pumpteam.mypump.reglas.NormalizacionRutina
import com.pumpteam.mypump.reglas.Progresiones
import com.pumpteam.mypump.reglas.ReglasEjercicio
import java.time.Instant
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Reporte del 4-nov: la cinta, tal como la manda el plan (sin duración y con `progresion: []`), pedía reps, kg y RIR en vez
// de ir por tiempo, y no ofrecía «Sustituir». `normalizarRutina` le pone `series = 1` a todo lo que no trae series, así que
// la sesión le armaba una fila. Gemelo de CardioPorTiempoTests.swift.

private val catalogoReal: CatalogoEjercicios by lazy { CatalogoEjercicios.desde(Compartido.texto("catalogo-ejercicios.json")) }

/** La cinta exacta del reporte: cardio en el día 1 y calentamiento en el día 2, con un calentamiento de fuerza y fuerza al lado. */
private const val ESTRUCTURA_CARDIO = """
{"semanas_total":12,"dias":[
 {"id":"d1","n":1,"nombre":"TIRÓN","bloques":[{"titulo":"BLOQUE 1","ejercicios":[
  {"id":"cinta-caminata-inclinada-10-min-d1-0","tipo":"cardio","nombre":"Cinta (caminata inclinada 10 min)","catalogo_slug":"Walking_Treadmill","progresion":[],"descanso_segundos":0,"notas_tecnica":"Inclinación 10-12 %"},
  {"id":"movilidad-d1-1","tipo":"calentamiento","nombre":"Movilidad de hombros con banda","progresion":[],"series":2,"reps":"15","descanso_segundos":0},
  {"id":"remo-d1-2","tipo":"compuesto","nombre":"Remo con barra","descanso_segundos":120,"progresion":[{"semana":1,"series":3,"reps":"8-10","rir":"1-2"},{"semana":2,"series":3,"reps":"8-10","rir":"1"},{"semana":3,"series":4,"reps":"8","rir":"1"}]}]}]},
 {"id":"d2","n":2,"nombre":"PIERNA","bloques":[{"titulo":"BLOQUE 1","ejercicios":[
  {"id":"cinta-caminata-inclinada-10-min-d2-0","tipo":"calentamiento","nombre":"Cinta (caminata inclinada 10 min)","catalogo_slug":"Walking_Treadmill","progresion":[],"descanso_segundos":0},
  {"id":"sentadilla-d2-1","tipo":"compuesto","nombre":"Sentadilla con barra","descanso_segundos":150,"progresion":[{"semana":1,"series":3,"reps":"8","rir":"2"}]}]}]}]}
"""

private fun rutinaCardio(): RutinaActiva = RutinaActiva.desde(
    ValorJson.parsear("""{"id":"rut-cardio","version":1,"semana_actual":3,"tiene_siguiente":false,"estructura":$ESTRUCTURA_CARDIO}""").aJson(),
)

private fun registros(id: String): List<RegistroSesion> = listOf(
    RegistroSesion(ejercicioId = id, serie = 1, pesoKg = 0.0, reps = 1, rir = 2, ejercicioNombre = "Cinta (caminata inclinada 10 min)", notas = null),
)

private fun Banco.modeloCardio(alcance: kotlinx.coroutines.CoroutineScope): ModeloEntreno {
    val r = reloj
    return ModeloEntreno(
        cliente = ClienteRpc(transporte = servidor), token = "tok-prueba", outbox = cola, disco = disco, rutinaInicial = rutinaCardio(),
        catalogoInicial = catalogoReal, zona = zonaAR, reloj = { Instant.ofEpochMilli(r.ms.toLong()) }, alcance = alcance,
    )
}

class CardioPorTiempoTest {
    private val est = NormalizacionRutina.normalizar(rutinaCardio().estructura).estructura

    @Test
    fun laCintaEsCardioComoCardioYComoCalentamiento() {
        val d1 = est.dias[0].bloques[0].ejercicios
        val d2 = est.dias[1].bloques[0].ejercicios
        // La normalización le sigue poniendo series = 1 (como la web): la decisión es de la pauta.
        assertEquals(1, d1[0].series)
        for (cinta in listOf(d1[0], d2[0])) {
            assertTrue(ReglasEjercicio.esCardio(cinta), cinta.tipo)
            val p = Progresiones.pauta(cinta, 3)
            assertNull(p.series, "${cinta.tipo}: $p")
            assertNull(p.rir, "${cinta.tipo}: $p")
        }
        assertFalse(ReglasEjercicio.esCardio(d1[1]))
        assertEquals(2, Progresiones.pauta(d1[1], 3).series)
        assertFalse(ReglasEjercicio.esCardio(d1[2]))
        assertEquals(4, Progresiones.pauta(d1[2], 3).series)
    }

    @Test
    fun laSesionNoLeArmaFilasConOSinHistorial() {
        for ((i, id) in listOf(0 to "cinta-caminata-inclinada-10-min-d1-0", 1 to "cinta-caminata-inclinada-10-min-d2-0")) {
            val d = DiaEnCurso(est.dias[i], semana = 3, sesionId = "ses-1", zona = zonaAR)
            assertTrue(d.ejercicios[id]!!.series.isEmpty(), "$id: sin historial")
            // Con una carga vieja en esa clave (un cliente que registró la cinta como serie): sigue sin filas.
            d.aplicarRegistros(registros(id))
            assertTrue(d.ejercicios[id]!!.series.isEmpty(), "$id: con historial")
        }
        val d = DiaEnCurso(est.dias[0], semana = 3, sesionId = "ses-1", zona = zonaAR)
        assertEquals(2, d.ejercicios["movilidad-d1-1"]!!.series.size, "el calentamiento con banda va por series")
        assertEquals(4, d.ejercicios["remo-d1-2"]!!.series.size)
    }

    @Test
    fun detectaCardioPorTipoNombreOSlug() {
        assertTrue(ReglasEjercicio.esCardio("Cualquier cosa", " Cardio "))
        assertTrue(ReglasEjercicio.esCardio("Bicicleta fija 15 min", "calentamiento"))
        assertTrue(ReglasEjercicio.esCardio("Elíptico", null))
        assertTrue(ReglasEjercicio.esCardio("Escaladora 5'", ""))
        assertTrue(ReglasEjercicio.esCardio("Remo ergómetro", "calentamiento"))
        assertTrue(ReglasEjercicio.esCardio("Entrada en calor", "calentamiento", listOf("Rowing_Stationary")))
        assertFalse(ReglasEjercicio.esCardio("Remo con barra", null))
        assertFalse(ReglasEjercicio.esCardio("Caminata del granjero", null))
        assertFalse(ReglasEjercicio.esCardio("Face-pull con banda", "calentamiento"))
        assertFalse(ReglasEjercicio.esCardio("Cinta (caminata)", "compuesto"), "un tipo de fuerza manda")
    }

    @Test
    fun laTarjetaVaPorTiempoYOfreceSustituirCardio() = enUnHilo { alcance ->
        val m = Banco(alcance).modeloCardio(alcance)
        val lugar = "cinta-caminata-inclinada-10-min-d1-0"
        val t = m.tarjeta(lugar)!!
        assertTrue(t.filas.isEmpty(), "sin tabla de reps, kg y RIR")
        assertNull(t.pauta.series)
        assertNull(t.pauta.rir)
        assertNull(m.leyendaRir(lugar))
        assertTrue(m.preparacion(lugar).isEmpty())
        assertTrue(t.puedeSustituir, "la cinta ofrece «Sustituir»")
        val subs = m.sustitutos(lugar)
        assertEquals(listOf("Cinta (trote)", "Bicicleta fija", "Bicicleta reclinada", "Elíptico", "Remo ergómetro", "Escaladora"), subs.map { it.nombre })
        assertTrue(m.otrosDelMismoMusculo(lugar).isEmpty())
        // Sustituida por la bici: sigue por tiempo.
        m.sustituir(lugar, subs.first { it.nombre == "Bicicleta fija" }, fijar = false)
        val tb = m.tarjeta(lugar)!!
        assertEquals("Bicicleta fija", tb.efectivo.ejercicio.nombre)
        assertTrue(tb.filas.isEmpty())
        assertNull(tb.pauta.series)
        assertEquals(4, m.tarjeta("remo-d1-2")!!.filas.size)
        assertEquals(2, m.tarjeta("movilidad-d1-1")!!.filas.size)
    }
}
