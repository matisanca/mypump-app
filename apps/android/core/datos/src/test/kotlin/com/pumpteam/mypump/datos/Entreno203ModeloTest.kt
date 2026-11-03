package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.Preparacion
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// 2.0.3, Entreno en el modelo (gemelo de Entreno203ModeloTests.swift): el equipo del catálogo para el ejercicio del plan en
// la preparación, el aviso de primera vez con la leyenda del RIR y el caché de la preparación.

/** «Sentadilla» a secas no dice barra: la reconoce por el `equipment` del catálogo. */
private val catalogoSentadilla = CatalogoEjercicios.desde(
    """[{"slug_en":"Barbell_Squat","name_en":"Barbell Squat","name_normalized":"sentadilla","primary_muscle":"quadriceps","equipment":"barbell"}]""",
)

private fun rutinaSentadilla(): RutinaActiva = RutinaActiva.desde(
    ValorJson.parsear(
        """{"id":"rut-203","version":1,"semana_actual":1,"tiene_siguiente":false,"estructura":{"semanas_total":4,"dias":[{"id":"d1","n":1,"nombre":"PIERNA","bloques":[{"titulo":"BLOQUE 1","ejercicios":[{"id":"sen-d1-0","nombre":"Sentadilla","tipo":"compuesto","descanso_segundos":120,"progresion":[{"semana":1,"series":2,"reps":"8","rir":"0"}]}]}]}]}}""",
    ).aJson(),
)

private fun Banco.modeloSentadilla(alcance: CoroutineScope): ModeloEntreno {
    val r = reloj
    return ModeloEntreno(
        cliente = ClienteRpc(transporte = servidor), token = null, outbox = null, disco = null, rutinaInicial = rutinaSentadilla(),
        catalogoInicial = catalogoSentadilla, zona = zonaAR, reloj = { Instant.ofEpochMilli(r.ms.toLong()) }, alcance = alcance,
    )
}

class Entreno203ModeloTest {
    @Test
    fun laPreparacionUsaElEquipoDelCatalogo() = enUnHilo { alcance ->
        val m = Banco(alcance).modeloSentadilla(alcance)
        m.escribir("sen-d1-0", 0, "kg", "60")
        val p = m.preparacion("sen-d1-0")
        assertTrue(p.first().tipo == Preparacion.Tipo.CALENTAMIENTO && p.first().barraSola && p.first().kg == 20.0, "$p")
        assertEquals(listOf(20.0, 35.0, 50.0, 65.0), p.map { it.kg })
        // El caché: tipear las reps no la recalcula (es la misma lista); el kg de la primera efectiva sí.
        m.escribir("sen-d1-0", 0, "reps", "8")
        assertTrue(m.preparacion("sen-d1-0") === p, "recalculó al tipear las reps")
        m.escribir("sen-d1-0", 0, "kg", "80")
        assertEquals(listOf(20.0, 47.5, 67.5, 85.0), m.preparacion("sen-d1-0").map { it.kg })
    }

    @Test
    fun elAvisoDePrimeraVezDiceLaLeyenda() = enUnHilo { alcance ->
        val m = Banco(alcance).modeloSentadilla(alcance)
        val c = m.tarjeta("sen-d1-0")?.filas?.first()?.calibracion ?: ""
        assertTrue(c.contains("llegues a 8 reps al fallo") && !c.contains("1–2"), c)
        assertEquals("Al fallo", m.leyendaRir("sen-d1-0"))
    }
}
