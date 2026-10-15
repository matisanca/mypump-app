package com.pumpteam.mypump.salud

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.FloorsClimbedRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Length
import androidx.health.connect.client.units.Mass
import androidx.health.connect.client.units.Percentage
import androidx.health.connect.client.units.Power
import com.pumpteam.mypump.datos.ErrorFuenteSalud
import com.pumpteam.mypump.datos.HistorialSalud
import com.pumpteam.mypump.datos.PermisosSalud
import com.pumpteam.mypump.reglas.EtapaSueno
import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import java.time.Duration
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * Lo que la fuente de Health Connect le entrega al bridge portado, contra lo que le entrega hoy el plugin
 * (@capgo/capacitor-health 8.9.3, HealthManager.kt + HealthPlugin.kt): registros de Health Connect (dobles) →
 * `MuestraSalud`, `BaldeDiario` y `EntrenoCrudo`, con las mismas páginas, límites, orden, permisos y textos de error.
 */
class FuenteHealthConnectTest {
    private fun ms(i: java.time.Instant) = i.toEpochMilli().toDouble()

    // MARK: Registro por registro (readSamples)

    /** Health Connect manda UNA sesión de sueño con las etapas adentro (HealthKit, una muestra por etapa). */
    @Test
    fun elSuenoEsUnaSesionConSuDuracionYSusEtapas() = runBlocking {
        val sesion = SleepSessionRecord(
            startTime = t(13, 2, 10), startZoneOffset = UTC, endTime = t(13, 10, 5, 59), endZoneOffset = UTC, metadata = leido(),
            stages = listOf(
                SleepSessionRecord.Stage(t(13, 2, 10), t(13, 2, 20), SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED),
                SleepSessionRecord.Stage(t(13, 2, 20), t(13, 4, 0), SleepSessionRecord.STAGE_TYPE_LIGHT),
                SleepSessionRecord.Stage(t(13, 4, 0), t(13, 5, 0), SleepSessionRecord.STAGE_TYPE_DEEP),
                SleepSessionRecord.Stage(t(13, 5, 0), t(13, 5, 30), SleepSessionRecord.STAGE_TYPE_OUT_OF_BED),
                SleepSessionRecord.Stage(t(13, 5, 30), t(13, 6, 30), SleepSessionRecord.STAGE_TYPE_REM),
                SleepSessionRecord.Stage(t(13, 6, 30), t(13, 7, 0), SleepSessionRecord.STAGE_TYPE_UNKNOWN),
                SleepSessionRecord.Stage(t(13, 7, 0), t(13, 10, 0), SleepSessionRecord.STAGE_TYPE_SLEEPING),
                SleepSessionRecord.Stage(t(13, 10, 0), t(13, 10, 5), SleepSessionRecord.STAGE_TYPE_AWAKE),
            ),
        )
        val f = FuenteDePrueba(ClienteDePrueba(listOf(sesion)))
        val m = f.fuente.muestras("sleep", ms(t(12, 12)), ms(t(14, 0)), 5000).single()
        assertEquals(ms(t(13, 2, 10)), m.inicio)
        assertEquals(ms(t(13, 10, 5, 59)), m.fin)
        assertEquals(475.0, m.valor)   // 7 h 55 min 59 s: `toMinutes()` trunca
        assertNull(m.estadoSueno)      // el plugin de Android nunca manda `sleepState`
        // "Fuera de la cama" y "desconocida" no van; despierto en la cama es despierto.
        assertEquals(listOf("awake", "light", "deep", "rem", "asleep", "awake"), m.etapas?.map { it.estado })
        assertEquals(EtapaSueno(ms(t(13, 2, 20)), ms(t(13, 4, 0)), "light"), m.etapas?.get(1))
        assertEquals("com.sec.android.app.shealth", m.fuenteId)
        assertEquals("Samsung Galaxy Watch6", m.fuenteNombre)
    }

    /** `hasNormalizedStages`: sin etapas que se entiendan, la muestra va sin `stages` y el bridge la toma entera. */
    @Test
    fun sinEtapasQueSeEntiendanLaSesionVaEntera() = runBlocking {
        val sinEtapas = SleepSessionRecord(t(13, 2), UTC, t(13, 9), UTC, metadata = leido(id = "a"))
        val raras = SleepSessionRecord(
            t(14, 2), UTC, t(14, 9), UTC, metadata = leido(id = "b"),
            stages = listOf(SleepSessionRecord.Stage(t(14, 2), t(14, 9), SleepSessionRecord.STAGE_TYPE_OUT_OF_BED)),
        )
        val ms = FuenteDePrueba(ClienteDePrueba(listOf(raras, sinEtapas))).fuente.muestras("sleep", ms(t(12, 0)), ms(t(15, 0)), 5000)
        assertEquals(listOf(420.0, 420.0), ms.map { it.valor })
        assertTrue(ms.all { it.etapas == null })
        assertEquals(listOf(ms(t(13, 2)), ms(t(14, 2))), ms.map { it.inicio })   // ordenadas por inicio
    }

    /** `createSamplePayload`: `sourceId` es el paquete y `sourceName` el equipo si lo dice (si no, el paquete). */
    @Test
    fun elOrigenEsElPaqueteYElNombreElEquipo() {
        assertEquals("com.x" to "com.x", TraduccionHealthConnect.fuente(leido("com.x", null, null)))
        assertEquals("com.x" to "com.x", TraduccionHealthConnect.fuente(leido("com.x", " ", "")))
        assertEquals("com.x" to "Google", TraduccionHealthConnect.fuente(leido("com.x", "Google", null)))
        assertEquals("com.x" to "Pixel Watch 2", TraduccionHealthConnect.fuente(leido("com.x", null, "Pixel Watch 2")))
        assertEquals("com.google.android.apps.fitness" to "Google Pixel Watch 2", TraduccionHealthConnect.fuente(leido("com.google.android.apps.fitness", "Google", "Pixel Watch 2")))
    }

    /** El pulso da una muestra por lectura de adentro del registro, y todo se ordena por la hora de cada lectura. */
    @Test
    fun elPulsoDaUnaMuestraPorLecturaYSeOrdenaPorHora() = runBlocking {
        val a = HeartRateRecord(
            t(13, 9), UTC, t(13, 9, 10), UTC,
            listOf(HeartRateRecord.Sample(t(13, 9, 5), 70), HeartRateRecord.Sample(t(13, 9, 0), 65)), leido(id = "a"),
        )
        val b = HeartRateRecord(t(13, 8), UTC, t(13, 8, 10), UTC, listOf(HeartRateRecord.Sample(t(13, 8, 1), 60)), leido(id = "b"))
        val ms = FuenteDePrueba(ClienteDePrueba(listOf(a, b))).fuente.muestras("heartRate", ms(t(13, 0)), ms(t(14, 0)), 5000)
        assertEquals(listOf(60.0, 65.0, 70.0), ms.map { it.valor })
        assertEquals(listOf(ms(t(13, 8, 1)), ms(t(13, 9, 0)), ms(t(13, 9, 5))), ms.map { it.inicio })
        assertTrue(ms.all { it.inicio == it.fin })
    }

    /** Cada tipo con el valor y la unidad del plugin (la que espera el bridge). */
    @Test
    fun cadaTipoConSuValorYSuUnidad() = runBlocking {
        val f = FuenteDePrueba(
            ClienteDePrueba(
                listOf(
                    WeightRecord(time = t(13, 7), zoneOffset = UTC, weight = Mass.kilograms(82.4), metadata = leido()),
                    BodyFatRecord(time = t(13, 7), zoneOffset = UTC, percentage = Percentage(18.5), metadata = leido()),
                    BasalMetabolicRateRecord(time = t(13, 7), zoneOffset = UTC, basalMetabolicRate = Power.kilocaloriesPerDay(1812.0), metadata = leido()),
                    DistanceRecord(startTime = t(13, 7), startZoneOffset = UTC, endTime = t(13, 8), endZoneOffset = UTC, distance = Length.meters(5420.0), metadata = leido()),
                    FloorsClimbedRecord(startTime = t(13, 7), startZoneOffset = UTC, endTime = t(13, 8), endZoneOffset = UTC, floors = 3.0, metadata = leido()),
                    RespiratoryRateRecord(time = t(13, 3), zoneOffset = UTC, rate = 14.5, metadata = leido()),
                    RestingHeartRateRecord(time = t(13, 6), zoneOffset = UTC, beatsPerMinute = 52, metadata = leido()),
                    HeartRateVariabilityRmssdRecord(time = t(13, 3), zoneOffset = UTC, heartRateVariabilityMillis = 48.2, metadata = leido()),
                    StepsRecord(startTime = t(13, 7), startZoneOffset = UTC, endTime = t(13, 8), endZoneOffset = UTC, count = 1234, metadata = leido()),
                ),
            ),
        )
        suspend fun uno(dataType: String) = f.fuente.muestras(dataType, ms(t(13, 0)), ms(t(14, 0)), 5000).single()
        assertEquals(82.4, uno("weight").valor)
        assertEquals(ms(t(13, 7)), uno("weight").fin)                     // una lectura: inicio = fin
        assertEquals(18.5, uno("bodyFat").valor)                          // 0-100 (el bridge escala solo si es ≤ 1)
        assertEquals(1812.0, uno("basalCalories").valor)                  // la TASA del día: el bridge hace la mediana
        assertEquals(5420.0, uno("distance").valor)                       // metros
        assertEquals(ms(t(13, 8)), uno("distance").fin)
        assertEquals(3.0, uno("flightsClimbed").valor)
        assertEquals(14.5, uno("respiratoryRate").valor)
        assertEquals(52.0, uno("restingHeartRate").valor)
        assertEquals(48.2, uno("heartRateVariability").valor)             // rMSSD en ms
        assertEquals(1234.0, uno("steps").valor)
    }

    /** `readRecords`: páginas de `min(limite, 500)` hasta que no haya más o se junten `limite` registros. */
    @Test
    fun lasPaginasSonDe500YCortanAlJuntarElLimite() = runBlocking {
        val pasos = (0 until 1203).map { i ->
            StepsRecord(t(13, 0).plusSeconds(i * 60L), UTC, t(13, 0).plusSeconds(i * 60L + 30), UTC, 10L + i, leido(id = "p$i"))
        }
        val c = ClienteDePrueba(pasos)
        val todas = FuenteDePrueba(c).fuente.muestras("steps", ms(t(13, 0)), ms(t(14, 0)), 5000)
        assertEquals(1203, todas.size)
        assertEquals(listOf(null, "500", "1000"), c.paginas.map { it.token })
        assertTrue(c.paginas.all { it.tamano == 500 && it.tipo == "StepsRecord" })

        c.paginas.clear()
        val tres = FuenteDePrueba(c).fuente.muestras("steps", ms(t(13, 0)), ms(t(14, 0)), 3)
        assertEquals(listOf(10.0, 11.0, 12.0), tres.map { it.valor })
        assertEquals(1, c.paginas.size)   // quedaban más, pero ya juntó 3
        assertEquals(3, c.paginas[0].tamano)
    }

    /** El límite de las páginas cuenta REGISTROS; el del final, muestras (el pulso trae varias por registro). */
    @Test
    fun elLimiteCuentaRegistrosEnLasPaginasYMuestrasAlFinal() = runBlocking {
        val registros = (0 until 4).map { r ->
            val base = t(13, 10 - r)   // del más nuevo al más viejo: el orden lo pone el plugin
            HeartRateRecord(base, UTC, base.plusSeconds(60), UTC, (0 until 3).map { HeartRateRecord.Sample(base.plusSeconds(it * 10L), 60L + r * 3 + it) }, leido(id = "h$r"))
        }
        val c = ClienteDePrueba(registros)
        val ms = FuenteDePrueba(c).fuente.muestras("heartRate", ms(t(13, 0)), ms(t(14, 0)), 5)
        assertEquals(5, c.paginas.single().tamano)
        assertEquals(listOf(69.0, 70.0, 71.0, 66.0, 67.0), ms.map { it.valor })   // las 5 primeras por hora: 07:00 y 08:00
    }

    // MARK: Agregados (queryAggregated)

    /** Los baldes son de 24 h desde la punta que manda el bridge (la medianoche local), y van solo los que tienen valor. */
    @Test
    fun losPasosVanEnBaldesDeUnDiaDesdeLaPuntaYSoloLosQueTienenValor() = runBlocking {
        val c = ClienteDePrueba()
        c.balde = { inicio -> if (inicio == t(10, 3)) emptyMap() else mapOf(StepsRecord.COUNT_TOTAL to 8000L + inicio.epochSecond % 7) }
        val baldes = FuenteDePrueba(c).fuente.agregado("steps", "sum", ms(t(8, 3)), ms(t(11, 15)))
        assertEquals(listOf(ms(t(8, 3)), ms(t(9, 3)), ms(t(11, 3))), baldes.map { it.inicio })
        assertEquals(listOf(8000.0 + t(8, 3).epochSecond % 7, 8000.0 + t(9, 3).epochSecond % 7, 8000.0 + t(11, 3).epochSecond % 7), baldes.map { it.valor })
        val pedido = c.agrupados.single()
        assertEquals(t(8, 3) to t(11, 15), pedido.desde to pedido.hasta)
        assertEquals(Duration.ofDays(1), pedido.tramo)
        assertEquals(setOf(StepsRecord.COUNT_TOTAL), pedido.metricas)
    }

    @Test
    fun caloriasActivasYPulsoEnReposo() = runBlocking {
        val c = ClienteDePrueba()
        c.balde = { mapOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL to Energy.kilocalories(430.5), RestingHeartRateRecord.BPM_AVG to 54L) }
        val f = FuenteDePrueba(c).fuente
        assertEquals(listOf(430.5), f.agregado("calories", "sum", ms(t(13, 3)), ms(t(14, 3))).map { it.valor })
        assertEquals(listOf(54.0), f.agregado("restingHeartRate", "average", ms(t(13, 3)), ms(t(14, 3))).map { it.valor })
        assertEquals(
            setOf(RestingHeartRateRecord.BPM_AVG, RestingHeartRateRecord.BPM_MAX, RestingHeartRateRecord.BPM_MIN),
            c.agrupados.last().metricas,
        )
    }

    /** Lo que el plugin no agrega tira con su texto (va al diagnóstico). */
    @Test
    fun loQueElPluginNoAgregaTiraConSuTexto() = runBlocking {
        val f = FuenteDePrueba().fuente
        suspend fun error(dataType: String, agregacion: String) =
            assertThrows<ErrorFuenteSalud> { runBlocking { f.agregado(dataType, agregacion, ms(t(13, 0)), ms(t(14, 0))) } }.mensaje
        assertEquals("Aggregated queries are not supported for sleep data. Use readSamples instead.", error("sleep", "sum"))
        assertEquals("Aggregated queries are not supported for heartRateVariability. Use readSamples instead.", error("heartRateVariability", "average"))
        assertEquals("Unsupported aggregation 'sum' for bodyFat", error("bodyFat", "sum"))
        assertEquals("Unsupported aggregation 'average' for steps", error("steps", "average"))
        assertEquals("Unsupported data type: exerciseTime", error("exerciseTime", "sum"))
    }

    // MARK: Entrenos (queryWorkouts)

    /** Del más nuevo al más viejo, con el nombre del plugin, los segundos enteros y lo que se sumó en su rango. */
    @Test
    fun entrenosDelMasNuevoAlMasViejoConLoQueSeSumoEnSuRango() = runBlocking {
        val pesas = ExerciseSessionRecord(t(13, 18), UTC, t(13, 18, 59, 59, 900_000_000), UTC, leido(id = "e1"), ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING)
        val correr = ExerciseSessionRecord(t(12, 7), UTC, t(12, 7, 40), UTC, leido(id = "e2"), ExerciseSessionRecord.EXERCISE_TYPE_RUNNING)
        val raro = ExerciseSessionRecord(t(13, 7), UTC, t(13, 7, 20), UTC, leido(id = "e3"), 999)
        val c = ClienteDePrueba(listOf(pesas, correr, raro))
        c.suma = { _, desde, _ ->
            when (desde) {
                t(12, 7) -> mapOf(DistanceRecord.DISTANCE_TOTAL to Length.meters(6100.0), ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL to Energy.kilocalories(420.0))
                t(13, 18) -> mapOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL to Energy.kilocalories(250.0))
                else -> emptyMap()
            }
        }
        val ws = FuenteDePrueba(c).fuente.entrenos(ms(t(10, 3)), ms(t(14, 12)))
        assertEquals(listOf("strengthTraining", "other", "running"), ws.map { it.tipo })
        assertEquals(listOf(3599.0, 1200.0, 2400.0), ws.map { it.duracion })   // 59:59,9 → 3599 (`.seconds`)
        assertEquals(listOf(250.0, null, 420.0), ws.map { it.kcal })
        assertEquals(listOf(null, null, 6100.0), ws.map { it.distancia })
        assertEquals(ms(t(13, 18)), ws[0].inicio)
        assertEquals(ms(t(13, 18, 59, 59, 900_000_000)), ws[0].fin)
        assertEquals(listOf(100), c.paginas.map { it.tamano })   // el límite por defecto del plugin
    }

    /**
     * `aggregateWorkoutData`: sin calorías activas se prueba con las totales; si la suma de distancia y activas tira (un
     * permiso que falta), las dos quedan vacías y también se prueba con las totales.
     */
    @Test
    fun sinCaloriasActivasSePruebaConLasTotales() = runBlocking {
        val a = ExerciseSessionRecord(t(13, 18), UTC, t(13, 19), UTC, leido(id = "a"), ExerciseSessionRecord.EXERCISE_TYPE_BIKING)
        val b = ExerciseSessionRecord(t(12, 18), UTC, t(12, 19), UTC, leido(id = "b"), ExerciseSessionRecord.EXERCISE_TYPE_BIKING)
        val c = ClienteDePrueba(listOf(a, b))
        c.suma = { metricas, desde, _ ->
            when {
                TotalCaloriesBurnedRecord.ENERGY_TOTAL in metricas -> mapOf(TotalCaloriesBurnedRecord.ENERGY_TOTAL to Energy.kilocalories(600.0))
                desde == t(13, 18) -> mapOf(DistanceRecord.DISTANCE_TOTAL to Length.meters(20000.0))
                else -> throw SecurityException("Caller doesn't have android.permission.health.READ_DISTANCE")
            }
        }
        val ws = FuenteDePrueba(c).fuente.entrenos(ms(t(12, 0)), ms(t(14, 0)))
        assertEquals(listOf(20000.0, null), ws.map { it.distancia })
        assertEquals(listOf(600.0, 600.0), ws.map { it.kcal })
        assertEquals(4, c.agregados.size)   // por cada entreno: distancia + activas, y el respaldo de totales
    }

    /** Como mucho 100: la primera página ya los junta, y van los 100 que dio Health Connect, del más nuevo al más viejo. */
    @Test
    fun noMasDeCienEntrenos() = runBlocking {
        val sesiones = (0 until 130).map { i ->
            ExerciseSessionRecord(t(1, 0).plusSeconds(i * 3600L), UTC, t(1, 0).plusSeconds(i * 3600L + 1800), UTC, leido(id = "s$i"), ExerciseSessionRecord.EXERCISE_TYPE_WALKING)
        }
        val c = ClienteDePrueba(sesiones)
        val ws = FuenteDePrueba(c).fuente.entrenos(ms(t(1, 0)), ms(t(14, 0)))
        assertEquals(100, ws.size)
        assertEquals(1, c.paginas.size)
        assertEquals(ms(t(1, 0).plusSeconds(99 * 3600L)), ws.first().inicio)
        assertEquals(ms(t(1, 0)), ws.last().inicio)
    }

    @Test
    fun losNombresDeLosEntrenosSonLosDelPlugin() {
        val casos = mapOf(
            ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING to "strengthTraining",
            ExerciseSessionRecord.EXERCISE_TYPE_WEIGHTLIFTING to "weightlifting",
            ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL to "runningTreadmill",
            ExerciseSessionRecord.EXERCISE_TYPE_BIKING to "cycling",
            ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY to "bikingStationary",
            ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING to "crossTraining",
            ExerciseSessionRecord.EXERCISE_TYPE_ROCK_CLIMBING to "climbing",
            ExerciseSessionRecord.EXERCISE_TYPE_SOCCER to "soccer",
            ExerciseSessionRecord.EXERCISE_TYPE_FRISBEE_DISC to "frisbeedisc",
            ExerciseSessionRecord.EXERCISE_TYPE_OTHER_WORKOUT to "other",
            ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL to "swimmingPool",
            12345 to "other",
        )
        for ((tipo, nombre) in casos) assertEquals(nombre, TraduccionHealthConnect.tipoEntreno(tipo), "$tipo")
    }

    // MARK: Disponibilidad y permisos (HealthPlugin.kt)

    /** Los permisos que se piden son SOLO de lectura y son exactamente los del manifest (13 más el historial). */
    @Test
    fun losPermisosSonSoloDeLecturaYSonLosDelManifest() {
        val (tipos, entrenos) = FuenteHealthConnect.tiposYEntrenos(PuenteSalud.tiposLectura(PlataformaSalud.ANDROID, 0))
        val p = FuenteHealthConnect.permisosPara(tipos, entrenos, historial = true)
        val esperados = listOf(
            "READ_STEPS", "READ_DISTANCE", "READ_ACTIVE_CALORIES_BURNED", "READ_BASAL_METABOLIC_RATE", "READ_FLOORS_CLIMBED",
            "READ_HEART_RATE", "READ_RESTING_HEART_RATE", "READ_HEART_RATE_VARIABILITY", "READ_SLEEP", "READ_RESPIRATORY_RATE",
            "READ_WEIGHT", "READ_BODY_FAT", "READ_EXERCISE", "READ_HEALTH_DATA_HISTORY",
        ).map { "android.permission.health.$it" }.toSet()
        assertEquals(esperados, p)
        assertFalse(p.any { "WRITE" in it })
    }

    @Test
    fun siYaEstanTodosNoSeAbreLaHoja() = runBlocking {
        val (tipos, entrenos) = FuenteHealthConnect.tiposYEntrenos(PuenteSalud.nucleo)
        val f = FuenteDePrueba(ClienteDePrueba(dados = FuenteHealthConnect.permisosPara(tipos, entrenos, historial = true)))
        val h = f.fuente.pedirLecturaConHistorial(PuenteSalud.nucleo)
        assertTrue(f.hojas.isEmpty())
        assertEquals(HistorialSalud(autorizado = true, disponible = true), h)
    }

    /** La hoja pide lo que falta del pedido entero (no solo lo que falta) y el historial solo si este Health Connect lo tiene. */
    @Test
    fun laHojaPideElPedidoYElHistorialSoloSiExiste() = runBlocking {
        val f = FuenteDePrueba(ClienteDePrueba(dados = setOf("android.permission.health.READ_STEPS")))
        f.alAbrirHoja = { f.cliente.dados = f.cliente.dados + "android.permission.health.READ_SLEEP" }   // dio solo el sueño
        val h = f.fuente.pedirLecturaConHistorial(listOf("steps", "sleep", "workouts"))
        assertEquals(
            setOf("READ_STEPS", "READ_SLEEP", "READ_EXERCISE", "READ_HEALTH_DATA_HISTORY").map { "android.permission.health.$it" }.toSet(),
            f.hojas.single(),
        )
        assertEquals(HistorialSalud(autorizado = false, disponible = true), h)   // lo negó

        // Un Health Connect viejo no conoce el historial: no se pide (la hoja se reabriría siempre) y se informa.
        val viejo = FuenteDePrueba(ClienteDePrueba(conHistorial = false))
        assertEquals(HistorialSalud(autorizado = false, disponible = false), viejo.fuente.pedirLecturaConHistorial(listOf("steps")))
        assertEquals(setOf("android.permission.health.READ_STEPS"), viejo.hojas.single())

        // La tanda sin historial ni lo pide ni lo informa.
        val resto = FuenteDePrueba()
        resto.fuente.pedirLectura(listOf("weight"))
        assertEquals(setOf("android.permission.health.READ_WEIGHT"), resto.hojas.single())
    }

    /** Un tipo que el enum de Kotlin no tiene tira la tanda entera antes de abrir nada (por eso hay tipos soloIOS). */
    @Test
    fun unTipoQueAndroidNoConoceTiraLaTandaEntera() {
        val f = FuenteDePrueba()
        val e = assertThrows<ErrorFuenteSalud> { runBlocking { f.fuente.pedirLectura(listOf("steps", "exerciseTime")) } }
        assertEquals("Unsupported data type: exerciseTime", e.mensaje)
        assertTrue(f.hojas.isEmpty())
    }

    @Test
    fun siLaHojaNoAbreTiraComoElPlugin() {
        val f = FuenteDePrueba()
        f.alAbrirHoja = { throw IllegalStateException("no hay una pantalla a la vista") }
        val e = assertThrows<ErrorFuenteSalud> { runBlocking { f.fuente.pedirLectura(listOf("steps")) } }
        assertEquals("Failed to launch Health Connect permission request.", e.mensaje)
    }

    /** Sin el SDK disponible no se consulta nada y el error dice por qué (`availabilityReason`). */
    @Test
    fun sinElSdkTiraConElTextoDelPlugin() = runBlocking {
        val f = FuenteDePrueba(estado = HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED)
        assertFalse(f.fuente.disponible())
        assertEquals("Health Connect needs an update.", assertThrows<ErrorFuenteSalud> { runBlocking { f.fuente.muestras("weight", 0.0, 1.0, 10) } }.mensaje)
        f.estado = HealthConnectClient.SDK_UNAVAILABLE
        assertEquals("Health Connect is unavailable on this device.", assertThrows<ErrorFuenteSalud> { runBlocking { f.fuente.permisos(listOf("steps")) } }.mensaje)
        f.estado = HealthConnectClient.SDK_AVAILABLE
        assertTrue(f.fuente.disponible())
        assertTrue(f.cliente.paginas.isEmpty())
    }

    /** `checkAuthorization`: los dados y los que faltan en el orden del pedido, con 'workouts' al final. */
    @Test
    fun permisosDadosYPendientesEnElOrdenDelPlugin() = runBlocking {
        val f = FuenteDePrueba(ClienteDePrueba(dados = setOf("android.permission.health.READ_WEIGHT", "android.permission.health.READ_EXERCISE")))
        val p = f.fuente.permisos(listOf("steps", "workouts", "sleep", "weight"))
        assertEquals(PermisosSalud(preguntados = listOf("weight", "workouts"), pendientes = listOf("steps", "sleep")), p)
    }

    @Test
    fun elHistorialSeRepreguntaSinHoja() = runBlocking {
        val f = FuenteDePrueba(ClienteDePrueba(dados = setOf(TraduccionHealthConnect.PERMISO_HISTORIAL)))
        assertEquals(HistorialSalud(autorizado = true, disponible = true), f.fuente.historial())
        f.cliente.conHistorial = false
        assertEquals(HistorialSalud(autorizado = false, disponible = false), f.fuente.historial())
        assertTrue(f.hojas.isEmpty())
    }

    @Test
    fun lasHorasAlRevesTiranComoElPlugin() {
        val e = assertThrows<ErrorFuenteSalud> { runBlocking { FuenteDePrueba().fuente.muestras("weight", 10.0, 5.0, 10) } }
        assertEquals("endDate must be greater than or equal to startDate", e.mensaje)
    }
}
