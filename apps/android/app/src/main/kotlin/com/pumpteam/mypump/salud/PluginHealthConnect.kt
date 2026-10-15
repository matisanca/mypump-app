package com.pumpteam.mypump.salud

import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.feature.ExperimentalMindfulnessSessionApi
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalBodyTemperatureRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.BloodGlucoseRecord
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.BodyTemperatureRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.FloorsClimbedRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.MindfulnessSessionRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Length
import androidx.health.connect.client.units.Mass
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.EtapaSueno
import com.pumpteam.mypump.reglas.MuestraSalud
import java.time.Duration
import java.time.Instant
import kotlin.reflect.KClass

// Lo que hace el plugin de la app de hoy (@capgo/capacitor-health 8.9.3, android/src/main/java/app/capgo/plugin/health)
// con cada registro de Health Connect, sin la vuelta por JSON: lo que el bridge termina leyendo de cada payload
// (`new Date(startDate).getTime()`, `value`, `sourceId`, `sourceName`, `stages`). La consulta en sí (páginas, límites,
// orden, baldes) está en FuenteHealthConnect; esto es puro y se prueba en la JVM.

/**
 * `HealthDataType.kt`: el `dataType` que manda el bridge y el registro de Health Connect que se lee. Están los 22, no
 * solo los que se piden: un tipo que el enum no tiene falla distinto ("Unsupported data type") que uno que está pero
 * cuyo permiso la app no declara (Health Connect tira), y el diagnóstico muestra los dos como hoy.
 */
@OptIn(ExperimentalMindfulnessSessionApi::class)
enum class TipoHealthConnect(val dataType: String, val registro: KClass<out Record>) {
    STEPS("steps", StepsRecord::class),
    DISTANCE("distance", DistanceRecord::class),
    CALORIES("calories", ActiveCaloriesBurnedRecord::class),
    HEART_RATE("heartRate", HeartRateRecord::class),
    WEIGHT("weight", WeightRecord::class),
    SLEEP("sleep", SleepSessionRecord::class),
    RESPIRATORY_RATE("respiratoryRate", RespiratoryRateRecord::class),
    OXYGEN_SATURATION("oxygenSaturation", OxygenSaturationRecord::class),
    RESTING_HEART_RATE("restingHeartRate", RestingHeartRateRecord::class),
    HEART_RATE_VARIABILITY("heartRateVariability", HeartRateVariabilityRmssdRecord::class),
    VO2_MAX("vo2Max", Vo2MaxRecord::class),
    BLOOD_PRESSURE("bloodPressure", BloodPressureRecord::class),
    BLOOD_GLUCOSE("bloodGlucose", BloodGlucoseRecord::class),
    BODY_TEMPERATURE("bodyTemperature", BodyTemperatureRecord::class),
    HEIGHT("height", HeightRecord::class),
    FLIGHTS_CLIMBED("flightsClimbed", FloorsClimbedRecord::class),
    DISTANCE_CYCLING("distanceCycling", DistanceRecord::class),
    BODY_FAT("bodyFat", BodyFatRecord::class),
    BASAL_BODY_TEMPERATURE("basalBodyTemperature", BasalBodyTemperatureRecord::class),
    BASAL_CALORIES("basalCalories", BasalMetabolicRateRecord::class),
    TOTAL_CALORIES("totalCalories", TotalCaloriesBurnedRecord::class),
    MINDFULNESS("mindfulness", MindfulnessSessionRecord::class);

    val permisoLectura: String get() = HealthPermission.getReadPermission(registro)

    companion object {
        fun de(dataType: String): TipoHealthConnect? = entries.firstOrNull { it.dataType == dataType }
    }
}

/** Lo que el plugin hace con los registros, los baldes y los entrenos (HealthManager.kt). */
object TraduccionHealthConnect {
    /** El permiso que levanta el corte de 30 días de Health Connect (no es un tipo de dato). */
    const val PERMISO_HISTORIAL = "android.permission.health.READ_HEALTH_DATA_HISTORY"

    /** El de los entrenos ('workouts' no está en el enum: lo agrega `parseTypeListWithWorkouts`). */
    val permisoEntrenos: String get() = HealthPermission.getReadPermission(ExerciseSessionRecord::class)

    /** `Instant` → los ms que ve el bridge: `formatter.format(t)` (ISO_INSTANT) y `new Date(…)` truncan al ms. */
    fun ms(t: Instant): Double = t.toEpochMilli().toDouble()

    /**
     * `createSamplePayload`: `sourceId` es el paquete que escribió el dato y `sourceName` el equipo ("Google Pixel Watch
     * 2") si lo dice, o si no, el paquete.
     */
    fun fuente(metadata: Metadata): Pair<String, String> {
        val paquete = metadata.dataOrigin.packageName
        val equipo = metadata.device?.let { d ->
            listOfNotNull(d.manufacturer?.takeIf { it.isNotBlank() }, d.model?.takeIf { it.isNotBlank() }).joinToString(" ").trim()
        }
        return paquete to (equipo?.takeIf { it.isNotEmpty() } ?: paquete)
    }

    private fun muestra(inicio: Instant, fin: Instant, valor: Double, metadata: Metadata, etapas: List<EtapaSueno>? = null): MuestraSalud {
        val (id, nombre) = fuente(metadata)
        return MuestraSalud(ms(inicio), ms(fin), valor, id, nombre, estadoSueno = null, etapas = etapas)
    }

    /**
     * `mapSleepStageToString`: las etapas de Health Connect con el nombre que entiende el bridge. "Fuera de la cama" y
     * "desconocida" no van (`return@forEach`).
     */
    fun etapa(stage: Int): String? = when (stage) {
        SleepSessionRecord.STAGE_TYPE_AWAKE -> "awake"
        SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED -> "awake"
        SleepSessionRecord.STAGE_TYPE_SLEEPING -> "asleep"
        SleepSessionRecord.STAGE_TYPE_LIGHT -> "light"
        SleepSessionRecord.STAGE_TYPE_DEEP -> "deep"
        SleepSessionRecord.STAGE_TYPE_REM -> "rem"
        else -> null
    }

    /**
     * `readSamples`, registro por registro: cada muestra con la hora por la que el plugin las ordena. El pulso da una
     * muestra por cada lectura de adentro del registro; el sueño, UNA por sesión con su duración en minutos (truncada,
     * `toMinutes()`) y sus etapas aparte; las basales, la TASA del día (`inKilocaloriesPerDay`, por eso el bridge hace
     * la mediana).
     */
    @OptIn(ExperimentalMindfulnessSessionApi::class)
    fun muestras(tipo: TipoHealthConnect, r: Record): List<Pair<Instant, MuestraSalud>> = when (tipo) {
        TipoHealthConnect.STEPS -> (r as StepsRecord).let { listOf(it.startTime to muestra(it.startTime, it.endTime, it.count.toDouble(), it.metadata)) }
        TipoHealthConnect.DISTANCE, TipoHealthConnect.DISTANCE_CYCLING ->
            (r as DistanceRecord).let { listOf(it.startTime to muestra(it.startTime, it.endTime, it.distance.inMeters, it.metadata)) }
        TipoHealthConnect.CALORIES ->
            (r as ActiveCaloriesBurnedRecord).let { listOf(it.startTime to muestra(it.startTime, it.endTime, it.energy.inKilocalories, it.metadata)) }
        TipoHealthConnect.WEIGHT -> (r as WeightRecord).let { listOf(it.time to muestra(it.time, it.time, it.weight.inKilograms, it.metadata)) }
        TipoHealthConnect.HEART_RATE ->
            (r as HeartRateRecord).let { h -> h.samples.map { s -> s.time to muestra(s.time, s.time, s.beatsPerMinute.toDouble(), h.metadata) } }
        TipoHealthConnect.SLEEP -> (r as SleepSessionRecord).let { s ->
            val minutos = Duration.between(s.startTime, s.endTime).toMinutes().toDouble()
            val etapas = s.stages.mapNotNull { g -> etapa(g.stage)?.let { EtapaSueno(ms(g.startTime), ms(g.endTime), it) } }
            // `hasNormalizedStages`: sin etapas que se entiendan, la muestra va sin `stages` (y el bridge la toma entera).
            listOf(s.startTime to muestra(s.startTime, s.endTime, minutos, s.metadata, etapas.ifEmpty { null }))
        }
        TipoHealthConnect.RESPIRATORY_RATE -> (r as RespiratoryRateRecord).let { listOf(it.time to muestra(it.time, it.time, it.rate, it.metadata)) }
        TipoHealthConnect.OXYGEN_SATURATION ->
            (r as OxygenSaturationRecord).let { listOf(it.time to muestra(it.time, it.time, it.percentage.value, it.metadata)) }
        TipoHealthConnect.RESTING_HEART_RATE ->
            (r as RestingHeartRateRecord).let { listOf(it.time to muestra(it.time, it.time, it.beatsPerMinute.toDouble(), it.metadata)) }
        TipoHealthConnect.HEART_RATE_VARIABILITY ->
            (r as HeartRateVariabilityRmssdRecord).let { listOf(it.time to muestra(it.time, it.time, it.heartRateVariabilityMillis, it.metadata)) }
        TipoHealthConnect.VO2_MAX ->
            (r as Vo2MaxRecord).let { listOf(it.time to muestra(it.time, it.time, it.vo2MillilitersPerMinuteKilogram, it.metadata)) }
        TipoHealthConnect.BLOOD_PRESSURE ->
            (r as BloodPressureRecord).let { listOf(it.time to muestra(it.time, it.time, it.systolic.inMillimetersOfMercury, it.metadata)) }
        TipoHealthConnect.BLOOD_GLUCOSE ->
            (r as BloodGlucoseRecord).let { listOf(it.time to muestra(it.time, it.time, it.level.inMilligramsPerDeciliter, it.metadata)) }
        TipoHealthConnect.BODY_TEMPERATURE ->
            (r as BodyTemperatureRecord).let { listOf(it.time to muestra(it.time, it.time, it.temperature.inCelsius, it.metadata)) }
        TipoHealthConnect.HEIGHT -> (r as HeightRecord).let { listOf(it.time to muestra(it.time, it.time, it.height.inMeters * 100.0, it.metadata)) }
        TipoHealthConnect.FLIGHTS_CLIMBED ->
            (r as FloorsClimbedRecord).let { listOf(it.startTime to muestra(it.startTime, it.endTime, it.floors, it.metadata)) }
        TipoHealthConnect.BODY_FAT -> (r as BodyFatRecord).let { listOf(it.time to muestra(it.time, it.time, it.percentage.value, it.metadata)) }
        TipoHealthConnect.BASAL_BODY_TEMPERATURE ->
            (r as BasalBodyTemperatureRecord).let { listOf(it.time to muestra(it.time, it.time, it.temperature.inCelsius, it.metadata)) }
        TipoHealthConnect.BASAL_CALORIES ->
            (r as BasalMetabolicRateRecord).let { listOf(it.time to muestra(it.time, it.time, it.basalMetabolicRate.inKilocaloriesPerDay, it.metadata)) }
        TipoHealthConnect.TOTAL_CALORIES ->
            (r as TotalCaloriesBurnedRecord).let { listOf(it.startTime to muestra(it.startTime, it.endTime, it.energy.inKilocalories, it.metadata)) }
        TipoHealthConnect.MINDFULNESS -> (r as MindfulnessSessionRecord).let {
            listOf(it.startTime to muestra(it.startTime, it.endTime, Duration.between(it.startTime, it.endTime).toMinutes().toDouble(), it.metadata))
        }
    }

    /**
     * El cierre de `readSamples`: orden por la hora de cada muestra (estable, como `sortedBy`), al revés si no es
     * ascendente, y recién ahí el límite (que cuenta MUESTRAS; el de las páginas cuenta registros).
     */
    fun ordenar(muestras: List<Pair<Instant, MuestraSalud>>, limite: Int, ascendente: Boolean): List<MuestraSalud> {
        val ordenadas = muestras.sortedBy { it.first }
        val enOrden = if (ascendente) ordenadas else ordenadas.asReversed()
        return (if (limite > 0) enOrden.take(limite) else enOrden).map { it.second }
    }

    // MARK: Agregados (queryAggregated)

    /** `validateAggregation`: la matriz chica que acepta el plugin. */
    fun validarAgregacion(tipo: TipoHealthConnect, agregacion: String) {
        val aceptadas = when (tipo) {
            TipoHealthConnect.STEPS, TipoHealthConnect.DISTANCE, TipoHealthConnect.CALORIES -> setOf("sum")
            TipoHealthConnect.HEART_RATE, TipoHealthConnect.WEIGHT, TipoHealthConnect.RESTING_HEART_RATE -> setOf("average", "min", "max")
            else -> emptySet()
        }
        if (agregacion !in aceptadas) throw IllegalArgumentException("Unsupported aggregation '$agregacion' for ${tipo.dataType}")
    }

    /** `aggregateMetrics`: lo que se le pide a Health Connect para cada tipo. */
    fun metricas(tipo: TipoHealthConnect): Set<AggregateMetric<*>> = when (tipo) {
        TipoHealthConnect.STEPS -> setOf(StepsRecord.COUNT_TOTAL)
        TipoHealthConnect.DISTANCE -> setOf(DistanceRecord.DISTANCE_TOTAL)
        TipoHealthConnect.CALORIES -> setOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
        TipoHealthConnect.HEART_RATE -> setOf(HeartRateRecord.BPM_AVG, HeartRateRecord.BPM_MAX, HeartRateRecord.BPM_MIN)
        TipoHealthConnect.WEIGHT -> setOf(WeightRecord.WEIGHT_AVG, WeightRecord.WEIGHT_MAX, WeightRecord.WEIGHT_MIN)
        TipoHealthConnect.RESTING_HEART_RATE -> setOf(RestingHeartRateRecord.BPM_AVG, RestingHeartRateRecord.BPM_MAX, RestingHeartRateRecord.BPM_MIN)
        else -> throw IllegalArgumentException("Unsupported data type for aggregation: ${tipo.dataType}")
    }

    /** `aggregateValue`: el valor de un balde en la unidad del plugin (pasos, metros, kcal, lpm, kg). */
    fun valor(tipo: TipoHealthConnect, agregacion: String, valores: Map<AggregateMetric<*>, Any>): Double? {
        fun entero(m: AggregateMetric<*>) = (valores[m] as? Long)?.toDouble()
        return when (tipo) {
            TipoHealthConnect.STEPS -> entero(StepsRecord.COUNT_TOTAL)
            TipoHealthConnect.DISTANCE -> (valores[DistanceRecord.DISTANCE_TOTAL] as? Length)?.inMeters
            TipoHealthConnect.CALORIES -> (valores[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL] as? Energy)?.inKilocalories
            TipoHealthConnect.HEART_RATE -> when (agregacion) {
                "average" -> entero(HeartRateRecord.BPM_AVG)
                "max" -> entero(HeartRateRecord.BPM_MAX)
                "min" -> entero(HeartRateRecord.BPM_MIN)
                else -> null
            }
            TipoHealthConnect.WEIGHT -> when (agregacion) {
                "average" -> (valores[WeightRecord.WEIGHT_AVG] as? Mass)?.inKilograms
                "max" -> (valores[WeightRecord.WEIGHT_MAX] as? Mass)?.inKilograms
                "min" -> (valores[WeightRecord.WEIGHT_MIN] as? Mass)?.inKilograms
                else -> null
            }
            TipoHealthConnect.RESTING_HEART_RATE -> when (agregacion) {
                "average" -> entero(RestingHeartRateRecord.BPM_AVG)
                "max" -> entero(RestingHeartRateRecord.BPM_MAX)
                "min" -> entero(RestingHeartRateRecord.BPM_MIN)
                else -> null
            }
            else -> null
        }
    }

    /** `buildAggregatedValues`: el valor principal es el de la primera agregación pedida que dio algo. */
    fun valorPrincipal(tipo: TipoHealthConnect, agregaciones: List<String>, valores: Map<AggregateMetric<*>, Any>): Double? =
        agregaciones.firstNotNullOfOrNull { valor(tipo, it, valores) }

    // MARK: Entrenos (queryWorkouts)

    /**
     * `createWorkoutPayload`: el tipo con el nombre del plugin, la duración en segundos ENTEROS (`.seconds.toInt()`) y la
     * distancia y las calorías que se sumaron en el rango del entreno (de cualquier fuente).
     */
    fun entreno(s: ExerciseSessionRecord, distancia: Double?, kcal: Double?): EntrenoCrudo = EntrenoCrudo(
        tipo = tipoEntreno(s.exerciseType),
        duracion = Duration.between(s.startTime, s.endTime).seconds.toInt().toDouble(),
        inicio = ms(s.startTime),
        fin = ms(s.endTime),
        kcal = kcal,
        distancia = distancia,
    )

    /** `WorkoutType.toWorkoutTypeString`: lo que no está en la tabla es "other". */
    fun tipoEntreno(tipo: Int): String = when (tipo) {
        ExerciseSessionRecord.EXERCISE_TYPE_FOOTBALL_AMERICAN -> "americanFootball"
        ExerciseSessionRecord.EXERCISE_TYPE_FOOTBALL_AUSTRALIAN -> "australianFootball"
        ExerciseSessionRecord.EXERCISE_TYPE_BADMINTON -> "badminton"
        ExerciseSessionRecord.EXERCISE_TYPE_BASEBALL -> "baseball"
        ExerciseSessionRecord.EXERCISE_TYPE_BASKETBALL -> "basketball"
        ExerciseSessionRecord.EXERCISE_TYPE_BOXING -> "boxing"
        ExerciseSessionRecord.EXERCISE_TYPE_ROCK_CLIMBING -> "climbing"
        ExerciseSessionRecord.EXERCISE_TYPE_CRICKET -> "cricket"
        ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING -> "crossTraining"
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING -> "cycling"
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY -> "bikingStationary"
        ExerciseSessionRecord.EXERCISE_TYPE_DANCING -> "dancing"
        ExerciseSessionRecord.EXERCISE_TYPE_ELLIPTICAL -> "elliptical"
        ExerciseSessionRecord.EXERCISE_TYPE_FENCING -> "fencing"
        ExerciseSessionRecord.EXERCISE_TYPE_GOLF -> "golf"
        ExerciseSessionRecord.EXERCISE_TYPE_GYMNASTICS -> "gymnastics"
        ExerciseSessionRecord.EXERCISE_TYPE_HANDBALL -> "handball"
        ExerciseSessionRecord.EXERCISE_TYPE_HIKING -> "hiking"
        ExerciseSessionRecord.EXERCISE_TYPE_ICE_HOCKEY -> "iceHockey"
        ExerciseSessionRecord.EXERCISE_TYPE_ICE_SKATING -> "iceSkating"
        ExerciseSessionRecord.EXERCISE_TYPE_MARTIAL_ARTS -> "martialArts"
        ExerciseSessionRecord.EXERCISE_TYPE_PILATES -> "pilates"
        ExerciseSessionRecord.EXERCISE_TYPE_RACQUETBALL -> "racquetball"
        ExerciseSessionRecord.EXERCISE_TYPE_ROWING -> "rowing"
        ExerciseSessionRecord.EXERCISE_TYPE_ROWING_MACHINE -> "rowingMachine"
        ExerciseSessionRecord.EXERCISE_TYPE_RUGBY -> "rugby"
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING -> "running"
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL -> "runningTreadmill"
        ExerciseSessionRecord.EXERCISE_TYPE_SAILING -> "sailing"
        ExerciseSessionRecord.EXERCISE_TYPE_SKATING -> "skating"
        ExerciseSessionRecord.EXERCISE_TYPE_SKIING -> "skiing"
        ExerciseSessionRecord.EXERCISE_TYPE_SNOWBOARDING -> "snowboarding"
        ExerciseSessionRecord.EXERCISE_TYPE_SNOWSHOEING -> "snowshoeing"
        ExerciseSessionRecord.EXERCISE_TYPE_SOCCER -> "soccer"
        ExerciseSessionRecord.EXERCISE_TYPE_SOFTBALL -> "softball"
        ExerciseSessionRecord.EXERCISE_TYPE_SQUASH -> "squash"
        ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING -> "stairClimbing"
        ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING_MACHINE -> "stairClimbingMachine"
        ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING -> "strengthTraining"
        ExerciseSessionRecord.EXERCISE_TYPE_STRETCHING -> "stretching"
        ExerciseSessionRecord.EXERCISE_TYPE_SURFING -> "surfing"
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL -> "swimmingPool"
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER -> "swimmingOpenWater"
        ExerciseSessionRecord.EXERCISE_TYPE_TABLE_TENNIS -> "tableTennis"
        ExerciseSessionRecord.EXERCISE_TYPE_TENNIS -> "tennis"
        ExerciseSessionRecord.EXERCISE_TYPE_VOLLEYBALL -> "volleyball"
        ExerciseSessionRecord.EXERCISE_TYPE_WALKING -> "walking"
        ExerciseSessionRecord.EXERCISE_TYPE_WATER_POLO -> "waterPolo"
        ExerciseSessionRecord.EXERCISE_TYPE_WEIGHTLIFTING -> "weightlifting"
        ExerciseSessionRecord.EXERCISE_TYPE_WHEELCHAIR -> "wheelchair"
        ExerciseSessionRecord.EXERCISE_TYPE_YOGA -> "yoga"
        ExerciseSessionRecord.EXERCISE_TYPE_BOOT_CAMP -> "bootCamp"
        ExerciseSessionRecord.EXERCISE_TYPE_CALISTHENICS -> "calisthenics"
        ExerciseSessionRecord.EXERCISE_TYPE_EXERCISE_CLASS -> "exerciseClass"
        ExerciseSessionRecord.EXERCISE_TYPE_FRISBEE_DISC -> "frisbeedisc"
        ExerciseSessionRecord.EXERCISE_TYPE_GUIDED_BREATHING -> "guidedBreathing"
        ExerciseSessionRecord.EXERCISE_TYPE_PADDLING -> "paddling"
        ExerciseSessionRecord.EXERCISE_TYPE_ROLLER_HOCKEY -> "rollerHockey"
        ExerciseSessionRecord.EXERCISE_TYPE_SCUBA_DIVING -> "scubaDiving"
        ExerciseSessionRecord.EXERCISE_TYPE_OTHER_WORKOUT -> "other"
        else -> "other"
    }
}
