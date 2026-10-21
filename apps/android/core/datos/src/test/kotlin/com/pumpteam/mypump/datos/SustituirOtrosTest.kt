package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import java.time.Instant
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Revisión del 21-oct del cambio D24 («Otros ejercicios de [músculo]» en la hoja «Sustituir»): el modelo de Entreno con el
// catálogo real. Gemelo de SustituirOtrosTests.swift.

private val catalogoReal: CatalogoEjercicios by lazy { CatalogoEjercicios.desde(Compartido.texto("catalogo-ejercicios.json")) }

/**
 * Un día de empuje sin fotos en el plan (como la demo, la que mira Apple): la extensión en polea (agarre Barra, Soga o
 * Maneral), los fondos y la patada de tríceps (sin variantes, con otros de su músculo) y uno que el catálogo no conoce.
 */
private const val ESTRUCTURA_OTROS = """
{"semanas_total":12,"dias":[{"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"BLOQUE 1 — TRÍCEPS","ejercicios":[
  {"id":"ext-d1-0","nombre":"Extensión tríceps en polea","tipo":"aislamiento","descanso_segundos":90,"progresion":[{"semana":1,"series":4,"reps":"12","rir":"1"}]},
  {"id":"fon-d1-1","nombre":"Fondos","tipo":"compuesto","descanso_segundos":120,"progresion":[{"semana":1,"series":3,"reps":"10","rir":"1"}]},
  {"id":"pat-d1-2","nombre":"Patada de tríceps con mancuerna","tipo":"aislamiento","descanso_segundos":60,"progresion":[{"semana":1,"series":3,"reps":"12","rir":"1"}]},
  {"id":"inv-d1-3","nombre":"Saludo inventado","tipo":"aislamiento","descanso_segundos":60,"progresion":[{"semana":1,"series":3,"reps":"12","rir":"1"}]}]}]}]}
"""

private fun rutinaOtros(): RutinaActiva = RutinaActiva.desde(
    ValorJson.parsear("""{"id":"rut-otros","version":1,"semana_actual":1,"tiene_siguiente":false,"estructura":$ESTRUCTURA_OTROS}""").aJson(),
)

private fun Banco.modeloOtros(alcance: kotlinx.coroutines.CoroutineScope): ModeloEntreno {
    val r = reloj
    return ModeloEntreno(
        cliente = ClienteRpc(transporte = servidor), token = "tok-prueba", outbox = cola, disco = disco, rutinaInicial = rutinaOtros(),
        catalogoInicial = catalogoReal, zona = zonaAR, reloj = { Instant.ofEpochMilli(r.ms.toLong()) }, alcance = alcance,
    )
}

class SustituirOtrosTest {
    /**
     * Hallazgo 1: «Sustituir» miraba solo las variantes. A los fondos (van a Dips_-_Chest_Version) y a la patada de tríceps
     * (Tricep_Dumbbell_Kickback), sin variantes, se les apagaba el botón y se les decía «No hay otra variante equivalente…»
     * aunque tenían 26 a 30 otros ejercicios de su músculo.
     */
    @Test
    fun sinVariantesPeroConOtrosDelMismoMusculoSeSustituye() = enUnHilo { alcance ->
        val m = Banco(alcance).modeloOtros(alcance)
        assertEquals("Dips_-_Chest_Version", catalogoReal.resolver(m.dia.value.ejercicio("fon-d1-1")!!)?.slugEn)
        assertEquals("Tricep_Dumbbell_Kickback", catalogoReal.resolver(m.dia.value.ejercicio("pat-d1-2")!!)?.slugEn)
        for (lugar in listOf("fon-d1-1", "pat-d1-2")) {
            val t = m.tarjeta(lugar)!!
            assertTrue(m.sustitutos(lugar).isEmpty(), "$lugar: sin variantes del mismo movimiento")
            assertTrue(m.otrosDelMismoMusculo(lugar).size >= 15, "$lugar: ${m.otrosDelMismoMusculo(lugar).size} otros")
            assertTrue(t.puedeSustituir, "$lugar: con otros del mismo músculo se puede sustituir")
        }
        // Con variantes, como siempre.
        assertTrue(m.sustitutos("ext-d1-0").isNotEmpty() && m.tarjeta("ext-d1-0")!!.puedeSustituir)
        // Sin ninguna de las dos no se puede (y la tarjeta dice que no hay con qué).
        assertTrue(m.sustitutos("inv-d1-3").isEmpty() && m.otrosDelMismoMusculo("inv-d1-3").isEmpty())
        assertFalse(m.tarjeta("inv-d1-3")!!.puedeSustituir)
    }

    /**
     * Hallazgo 2: al cambiar de movimiento a mitad del ejercicio, el kg y el agarre del plan pasaban al sustituto. La
     * extensión en polea con Soga, 2 series de 30 kg × 12, y después «Fondos · Peso corporal»: la serie 3 sugería 30 kg y se
     * grababa {ejercicioNombre: "Fondos", peso: 30, notas: "Soga"} (récord e historial de fondos sucios).
     */
    @Test
    fun alCambiarDeMovimientoNoSeHeredanElKgNiElAgarre() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modeloOtros(alcance)
        val lugar = "ext-d1-0"
        suspend fun carga(i: Int): ValorJson? = b.cola.operaciones().firstOrNull { it.dedupeKey == "carga_d1_${lugar}_${i}_s1" }?.payload?.get("datos")
        m.elegirVariante(lugar, "Soga")
        for (i in 0 until 2) {
            m.escribir(lugar, i, "reps", "12")
            m.escribir(lugar, i, "kg", "30")
            m.confirmarSerie(lugar, i) { true }
        }
        assertEquals("Soga", carga(1)?.get("notas")?.comoTexto, "con el selector a la vista, el agarre viaja")
        assertEquals("Extensión tríceps en polea", m.dia.value.ejercicios[lugar]?.series?.get(1)?.nombreRegistrado)

        val fondos = m.otrosDelMismoMusculo(lugar).first { it.nombre == "Fondos" && it.equipo == "Peso corporal" }
        m.sustituir(lugar, fondos, fijar = false)
        val t = m.tarjeta(lugar)!!
        assertEquals(null, t.variantes, "los fondos no muestran el selector de agarre")
        assertEquals("", t.filas[2].placeholderKg, "la serie 3 no sugiere los 30 kg de la polea")
        // Con las reps y sin kg no hay de dónde heredarlo: no se registra.
        m.escribir(lugar, 2, "reps", "10")
        m.confirmarSerie(lugar, 2) { true }
        assertFalse(m.dia.value.ejercicios[lugar]!!.series[2].confirmada)
        assertEquals(null, carga(2))
        // Con el lastre cargado va con el nombre de los fondos y sin el agarre de la polea.
        m.escribir(lugar, 2, "kg", "10")
        m.confirmarSerie(lugar, 2) { true }
        val s3 = carga(2)!!
        assertTrue(s3["ejercicioNombre"]?.comoTexto == "Fondos" && s3["peso"] == ValorJson.Numero(10.0) && s3["notas"] == ValorJson.Nulo, "$s3")

        // De vuelta a la polea: la serie 4 hereda de las de la polea (30), no de los fondos, y el agarre vuelve.
        m.revertirSustitucion(lugar)
        m.escribir(lugar, 3, "reps", "11")
        m.confirmarSerie(lugar, 3) { true }
        val s4 = carga(3)!!
        assertTrue(
            s4["ejercicioNombre"]?.comoTexto == "Extensión tríceps en polea" && s4["peso"] == ValorJson.Numero(30.0) && s4["notas"]?.comoTexto == "Soga",
            "$s4",
        )
    }

    /**
     * La sugerencia de kg de la tabla es la de la confirmación (revisión del 21-oct: la tabla la calculaba con todas las
     * series). Con la polea, las reps de la serie 3 sugieren los 30; ya en fondos, nada, y sin kg no se registra.
     */
    @Test
    fun laSugerenciaDeKgEsLaQueSeHereda() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modeloOtros(alcance)
        val lugar = "ext-d1-0"
        for (i in 0 until 2) {
            m.escribir(lugar, i, "reps", "12")
            m.escribir(lugar, i, "kg", "30")
            m.confirmarSerie(lugar, i) { true }
        }
        m.escribir(lugar, 2, "reps", "10")
        assertEquals("30", m.tarjeta(lugar)!!.filas[2].sugerenciaKg, "con la polea se heredan los 30")
        val fondos = m.otrosDelMismoMusculo(lugar).first { it.nombre == "Fondos" && it.equipo == "Peso corporal" }
        m.sustituir(lugar, fondos, fijar = false)
        val f = m.tarjeta(lugar)!!.filas[2]
        assertTrue(f.sugerenciaKg.isEmpty() && !f.puedeConfirmar, "ya en fondos no sugiere los kg de la polea: $f")
    }

    /**
     * Una serie ya registrada se vuelve a mandar con el ejercicio con el que se registró, aunque el lugar ahora esté
     * sustituido (o se haya vuelto al original): el RIR, o el lápiz y confirmar de nuevo, corrigen lo que se hizo. Antes el
     * sustituto ganaba y la serie de la polea se volvía a mandar como fondos, con sus 30 kg.
     */
    @Test
    fun unaSerieYaRegistradaSeVuelveAMandarConSuEjercicio() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modeloOtros(alcance)
        val lugar = "ext-d1-0"
        suspend fun carga(i: Int): ValorJson? = b.cola.operaciones().firstOrNull { it.dedupeKey == "carga_d1_${lugar}_${i}_s1" }?.payload?.get("datos")
        m.elegirVariante(lugar, "Soga")
        for (i in 0 until 2) {
            m.escribir(lugar, i, "reps", "12")
            m.escribir(lugar, i, "kg", "30")
            m.confirmarSerie(lugar, i) { true }
        }
        val fondos = m.otrosDelMismoMusculo(lugar).first { it.nombre == "Fondos" && it.equipo == "Peso corporal" }
        m.sustituir(lugar, fondos, fijar = false)

        // El RIR de la serie 2, ya con los fondos puestos: va como la extensión, con su agarre.
        m.elegirRir(lugar, 1, 2)
        val s2 = carga(1)!!
        assertTrue(
            s2["ejercicioNombre"]?.comoTexto == "Extensión tríceps en polea" && s2["peso"] == ValorJson.Numero(30.0) &&
                s2["notas"]?.comoTexto == "Soga" && s2["rir"] == ValorJson.Numero(2.0),
            "$s2",
        )
        // El lápiz sobre la serie 1: se corrige el kg y sigue siendo de la extensión.
        m.editarSerie(lugar, 0)
        m.escribir(lugar, 0, "kg", "32")
        m.confirmarSerie(lugar, 0) { true }
        val s1 = carga(0)!!
        assertTrue(
            s1["ejercicioNombre"]?.comoTexto == "Extensión tríceps en polea" && s1["peso"] == ValorJson.Numero(32.0) && s1["notas"]?.comoTexto == "Soga",
            "$s1",
        )

        // La serie 3 con los fondos y después de vuelta a la polea: su RIR va como fondos, sin el agarre de la polea.
        m.escribir(lugar, 2, "reps", "10")
        m.escribir(lugar, 2, "kg", "10")
        m.confirmarSerie(lugar, 2) { true }
        m.revertirSustitucion(lugar)
        m.elegirRir(lugar, 2, 1)
        val s3 = carga(2)!!
        assertTrue(
            s3["ejercicioNombre"]?.comoTexto == "Fondos" && s3["peso"] == ValorJson.Numero(10.0) && s3["notas"] == ValorJson.Nulo &&
                s3["rir"] == ValorJson.Numero(1.0),
            "$s3",
        )
    }

    /**
     * Hallazgo 4: con un plan sin fotos (la demo, que es la que mira Apple, o la cuenta test-nativa-ios), al reabrir
     * «Cambiar» después de pasar la extensión en polea a fondos, las listas se armaban sobre los fondos: sin foto del
     * original, `referencia` caía en la del sustituto.
     */
    @Test
    fun alReabrirCambiarLasListasSonLasDelOriginal() = enUnHilo { alcance ->
        val m = Banco(alcance).modeloOtros(alcance)
        val lugar = "ext-d1-0"
        val plan = m.dia.value.ejercicio(lugar)!!
        assertTrue(plan.imagenes == null && plan.catalogoSlug == null, "el plan no trae fotos ni slug")
        val variantes = m.sustitutos(lugar)
        val otros = m.otrosDelMismoMusculo(lugar)
        assertTrue(variantes.isNotEmpty() && otros.isNotEmpty())
        val fondos = otros.first { it.nombre == "Fondos" && it.equipo == "Peso corporal" }
        m.sustituir(lugar, fondos, fijar = true)
        val ef = m.efectivo(plan)
        assertTrue(ef.sustituido && ef.ejercicio.imagenes?.eccentric != null, "el sustituto sí trae foto")
        assertEquals(variantes, m.sustitutos(lugar), "las variantes son las de la extensión")
        assertEquals(otros, m.otrosDelMismoMusculo(lugar), "los otros son los de la extensión")
        assertTrue(m.tarjeta(lugar)!!.puedeSustituir)
    }
}
