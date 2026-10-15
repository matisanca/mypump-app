package com.pumpteam.mypump.salud

import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.units.Mass
import androidx.health.connect.client.units.Power
import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.PreferenciasEnMemoria
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.SincronizadorSalud
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.modelos.ValorJson
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * De punta a punta en la JVM: lo que lee la fuente de Health Connect pasa por la sincronización de :core (el bridge
 * portado) y sale como lo mandaría la app de hoy en un Android: fuente `health_connect`, el sueño de una sesión con sus
 * etapas, la HRV como rMSSD nocturna y las basales como la tasa del día (no la suma).
 */
class SincronizacionHealthConnectTest {
    private val ar = ZoneId.of("America/Argentina/Buenos_Aires")

    /** La base: anota los registros de cada lote de `mypump_ingest_salud` y dice que entraron todos. */
    private class Base : Transporte {
        val registros = ArrayList<ValorJson>()
        override suspend fun enviar(pedido: com.pumpteam.mypump.datos.Pedido): Respuesta {
            val cuerpo = pedido.cuerpo?.let { ValorJson.parsear(it.toString(Charsets.UTF_8)) }
            val lote = (cuerpo?.get("p_registros") as? ValorJson.Lista)?.elementos ?: emptyList()
            synchronized(this) { registros += lote }
            return Respuesta(200, lote.size.toString().toByteArray())
        }
    }

    @Test
    fun unaSemanaDeUnGalaxyWatchEntraComoHealthConnect() = runBlocking {
        // La noche del 12 al 13 (hora argentina: 23:10 → 07:06), con sus etapas; la HRV de esa noche y una del día; cuatro
        // lecturas de la tasa basal; dos pesadas.
        val sesion = SleepSessionRecord(
            t(13, 2, 10), UTC, t(13, 10, 6), UTC, metadata = leido(id = "s"),
            stages = listOf(
                SleepSessionRecord.Stage(t(13, 2, 10), t(13, 2, 20), SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED),
                SleepSessionRecord.Stage(t(13, 2, 20), t(13, 4, 0), SleepSessionRecord.STAGE_TYPE_LIGHT),
                SleepSessionRecord.Stage(t(13, 4, 0), t(13, 5, 0), SleepSessionRecord.STAGE_TYPE_DEEP),
                SleepSessionRecord.Stage(t(13, 5, 0), t(13, 6, 30), SleepSessionRecord.STAGE_TYPE_REM),
                SleepSessionRecord.Stage(t(13, 6, 30), t(13, 9, 30), SleepSessionRecord.STAGE_TYPE_LIGHT),
                SleepSessionRecord.Stage(t(13, 9, 30), t(13, 10, 6), SleepSessionRecord.STAGE_TYPE_AWAKE),
            ),
        )
        val registros = listOf(
            sesion,
            HeartRateVariabilityRmssdRecord(time = t(13, 5), zoneOffset = UTC, heartRateVariabilityMillis = 45.0, metadata = leido(id = "h1")),
            HeartRateVariabilityRmssdRecord(time = t(13, 15), zoneOffset = UTC, heartRateVariabilityMillis = 30.0, metadata = leido(id = "h2")),
        ) + listOf(3, 9, 15, 21).map {
            BasalMetabolicRateRecord(time = t(13, it), zoneOffset = UTC, basalMetabolicRate = Power.kilocaloriesPerDay(1800.0), metadata = leido(id = "b$it"))
        } + listOf(
            WeightRecord(time = t(13, 11), zoneOffset = UTC, weight = Mass.kilograms(82.4), metadata = leido(paquete = "com.withings.wiscale2", id = "w1")),
            WeightRecord(time = t(13, 23), zoneOffset = UTC, weight = Mass.kilograms(82.0), metadata = leido(paquete = "com.withings.wiscale2", id = "w2")),
        )
        val c = ClienteDePrueba(registros)
        c.balde = { mapOf(StepsRecord.COUNT_TOTAL to 9000L) }
        val base = Base()
        val alcance = CoroutineScope(coroutineContext + SupervisorJob())
        try {
            val s = SincronizadorSalud(
                FuenteDePrueba(c).fuente, ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", PreferenciasEnMemoria(), alcance,
                { t(14, 12) }, ar,
            )
            val r = s.sincronizar()
            assertTrue(r.ok)
        } finally {
            alcance.cancel()
        }

        fun fila(fecha: String, tipo: String) = base.registros.single { it["fecha"]?.comoTexto == fecha && it["tipo"]?.comoTexto == tipo }
        assertTrue(base.registros.all { it["fuente"]?.comoTexto == "health_connect" })
        // 100 + 60 + 90 + 180 minutos dormido (las etapas, sin lo despierto); la noche va al día del despertar.
        assertEquals(430.0, fila("2026-10-13", "sueno_min")["valor"]?.comoNumero)
        assertEquals(280.0, fila("2026-10-13", "sueno_ligero_min")["valor"]?.comoNumero)
        assertEquals(60.0, fila("2026-10-13", "sueno_profundo_min")["valor"]?.comoNumero)
        assertEquals(90.0, fila("2026-10-13", "sueno_rem_min")["valor"]?.comoNumero)
        assertEquals(90.0, fila("2026-10-13", "sueno_eficiencia_pct")["valor"]?.comoNumero)   // 430 de 476 en la cama
        // La HRV de la noche gana a la del día y va como rMSSD (el motor la pesa más que el SDNN de un Apple Watch).
        val hrv = fila("2026-10-13", "hrv_ms")
        assertEquals(45.0, hrv["valor"]?.comoNumero)
        assertEquals("rmssd", hrv["detalle"]?.get("metrica")?.comoTexto)
        assertEquals("nocturna", hrv["detalle"]?.get("ventana")?.comoTexto)
        // La basal es una TASA repetida: la mediana es la tasa (sumarla daba 7.200 kcal).
        assertEquals(1800.0, fila("2026-10-13", "kcal_basales")["valor"]?.comoNumero)
        assertEquals(82.0, fila("2026-10-13", "peso_kg")["valor"]?.comoNumero)   // la última pesada
        // Pasos: un balde por día local de los 8 que toca la semana.
        assertEquals(8, base.registros.count { it["tipo"]?.comoTexto == "pasos" })
        assertEquals(9000.0, fila("2026-10-13", "pasos")["valor"]?.comoNumero)
    }
}
