package com.pumpteam.mypump.salud

import android.os.ParcelFileDescriptor
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.FloorsClimbedRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Length
import androidx.health.connect.client.units.Mass
import androidx.health.connect.client.units.Percentage
import androidx.health.connect.client.units.Power
import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlin.reflect.KClass

/**
 * Datos de mentira en el Health Connect del EMULADOR (nunca en un teléfono de verdad): 40 días de un reloj, con lo que
 * mira el score (sueño con etapas, HRV nocturna, pulso en reposo) y lo demás que se lee. Escribir necesita los permisos
 * de escritura que declara solo el manifest de debug; se dan y se sacan con `pm grant` / `pm revoke` (Android 14+).
 *
 * Día `k` = hace `k` días (hora local de [zona]); hoy no se siembra (un día a medias).
 */
object SembradoSalud {
    const val DIAS = 40
    val zona: ZoneId = ZoneId.of("America/Argentina/Buenos_Aires")

    /** Lo que se lee (los 13 del manifest y el historial) y lo que se escribe para sembrar (solo debug). */
    val lectura = listOf(
        "READ_STEPS", "READ_DISTANCE", "READ_ACTIVE_CALORIES_BURNED", "READ_BASAL_METABOLIC_RATE", "READ_FLOORS_CLIMBED",
        "READ_HEART_RATE", "READ_RESTING_HEART_RATE", "READ_HEART_RATE_VARIABILITY", "READ_SLEEP", "READ_RESPIRATORY_RATE",
        "READ_WEIGHT", "READ_BODY_FAT", "READ_EXERCISE",
    ).map { "android.permission.health.$it" }
    const val HISTORIAL = "android.permission.health.READ_HEALTH_DATA_HISTORY"
    val escritura = lectura.map { it.replace("READ_", "WRITE_") }

    /** Las clases que se siembran (para borrar lo sembrado: Health Connect deja borrar solo lo propio). */
    val clases: List<KClass<out Record>> = listOf(
        StepsRecord::class, ActiveCaloriesBurnedRecord::class, RestingHeartRateRecord::class, SleepSessionRecord::class,
        HeartRateVariabilityRmssdRecord::class, HeartRateRecord::class, WeightRecord::class, BasalMetabolicRateRecord::class,
        BodyFatRecord::class, DistanceRecord::class, FloorsClimbedRecord::class, RespiratoryRateRecord::class, ExerciseSessionRecord::class,
    )

    val reloj = Device(type = Device.TYPE_WATCH, manufacturer = "Google", model = "Pixel Watch 2")

    fun shell(comando: String): String {
        val pfd = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(comando)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.readBytes().toString(Charsets.UTF_8) }
    }

    /**
     * Da permisos de Health Connect a la app, como si el cliente los hubiera tocado en la hoja. Sacarlos no: sacar un
     * permiso dado MATA el proceso de la app, que es el de las pruebas (Gradle desinstala la app al terminar la corrida, y
     * con ella se van los permisos).
     */
    fun permisos(paquete: String, permisos: List<String>, dar: Boolean) {
        check(dar) { "sacar un permiso mata el proceso de las pruebas" }
        for (p in permisos) shell("pm grant $paquete $p")
    }

    fun dia(k: Int, hora: Int, minuto: Int = 0, hoy: LocalDate = LocalDate.now(zona)): Instant =
        hoy.minusDays(k.toLong()).atTime(LocalTime.of(hora, minuto)).atZone(zona).toInstant()

    private fun off(t: Instant) = zona.rules.getOffset(t)

    /** Lo de un día: la noche que termina ese día, la actividad, las lecturas y, cada 3 días, un entreno de fuerza. */
    fun registrosDelDia(k: Int, hoy: LocalDate = LocalDate.now(zona)): List<Record> {
        fun d(h: Int, m: Int = 0) = dia(k, h, m, hoy)
        val m = Metadata.autoRecorded(reloj)
        val acostarse = dia(k + 1, 23, 30, hoy)
        val etapas = listOf(
            Triple(acostarse, dia(k + 1, 23, 40, hoy), SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED),
            Triple(dia(k + 1, 23, 40, hoy), d(1, 30), SleepSessionRecord.STAGE_TYPE_LIGHT),
            Triple(d(1, 30), d(2, 30), SleepSessionRecord.STAGE_TYPE_DEEP),
            Triple(d(2, 30), d(4), SleepSessionRecord.STAGE_TYPE_REM),
            Triple(d(4), d(6, 40), SleepSessionRecord.STAGE_TYPE_LIGHT),
            Triple(d(6, 40), d(7), SleepSessionRecord.STAGE_TYPE_AWAKE),
        ).map { (a, b, s) -> SleepSessionRecord.Stage(a, b, s) }
        val r = ArrayList<Record>()
        r += SleepSessionRecord(startTime = acostarse, startZoneOffset = off(acostarse), endTime = d(7), endZoneOffset = off(d(7)), metadata = m, stages = etapas)
        r += HeartRateVariabilityRmssdRecord(time = d(3), zoneOffset = off(d(3)), heartRateVariabilityMillis = 40.0 + k % 10, metadata = m)
        r += RespiratoryRateRecord(time = d(3), zoneOffset = off(d(3)), rate = 14.0, metadata = m)
        r += RestingHeartRateRecord(time = d(6, 30), zoneOffset = off(d(6, 30)), beatsPerMinute = 50L + k % 7, metadata = m)
        r += StepsRecord(startTime = d(9), startZoneOffset = off(d(9)), endTime = d(10), endZoneOffset = off(d(10)), count = 6000L + k * 10, metadata = m)
        r += FloorsClimbedRecord(startTime = d(12), startZoneOffset = off(d(12)), endTime = d(12, 10), endZoneOffset = off(d(12, 10)), floors = 4.0, metadata = m)
        for (h in listOf(0, 12)) {
            r += BasalMetabolicRateRecord(time = d(h, 30), zoneOffset = off(d(h, 30)), basalMetabolicRate = Power.kilocaloriesPerDay(1750.0), metadata = m)
        }
        r += HeartRateRecord(
            startTime = d(18), startZoneOffset = off(d(18)), endTime = d(19), endZoneOffset = off(d(19)),
            samples = (0 until 6).map { HeartRateRecord.Sample(d(18, it * 10), 120L + it * 10) }, metadata = m,
        )
        r += ActiveCaloriesBurnedRecord(startTime = d(18, 10), startZoneOffset = off(d(18, 10)), endTime = d(18, 50), endZoneOffset = off(d(18, 50)), energy = Energy.kilocalories(300.0 + k), metadata = m)
        r += DistanceRecord(startTime = d(18, 10), startZoneOffset = off(d(18, 10)), endTime = d(18, 50), endZoneOffset = off(d(18, 50)), distance = Length.meters(5000.0), metadata = m)
        if (k % 2 == 0) r += WeightRecord(time = d(7, 30), zoneOffset = off(d(7, 30)), weight = Mass.kilograms(82.0 - k * 0.05), metadata = m)
        if (k % 7 == 0) r += BodyFatRecord(time = d(7, 31), zoneOffset = off(d(7, 31)), percentage = Percentage(18.0), metadata = m)
        if (k % 3 == 0) {
            r += ExerciseSessionRecord(
                startTime = d(18), startZoneOffset = off(d(18)), endTime = d(19), endZoneOffset = off(d(19)), metadata = m,
                exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING,
            )
        }
        return r
    }

    /** Siembra los [DIAS] días (borrando antes lo que haya sembrado otra corrida). */
    suspend fun sembrar(cliente: HealthConnectClient, hoy: LocalDate = LocalDate.now(zona)) {
        borrar(cliente, hoy)
        val todos = (1..DIAS).flatMap { registrosDelDia(it, hoy) }
        for (lote in todos.chunked(200)) cliente.insertRecords(lote)
    }

    /** Borra lo sembrado (Health Connect solo deja borrar lo que escribió esta app). */
    suspend fun borrar(cliente: HealthConnectClient, hoy: LocalDate = LocalDate.now(zona)) {
        val rango = TimeRangeFilter.between(dia(DIAS + 2, 0, hoy = hoy), Instant.now().plusSeconds(86_400))
        for (c in clases) cliente.deleteRecords(c, rango)
    }
}
