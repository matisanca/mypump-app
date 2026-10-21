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
}
