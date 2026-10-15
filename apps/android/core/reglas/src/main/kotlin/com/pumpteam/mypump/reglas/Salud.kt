package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.util.Locale

// La salud del teléfono: lo que hace public/js/healthkit-bridge.js con lo que le entrega el plugin
// @capgo/capacitor-health 8.9.3, portado tal cual (gemelo de MyPumpReglas/Salud.swift). Los vectores de
// scripts/nativa/vectores-salud.mjs corren el bridge real y la nativa tiene que dar lo mismo, registro por registro.
//
// Las horas se manejan como en la web: milisegundos desde 1970 (enteros guardados en Double, como un número de JS) y
// fechas locales con el calendario gregoriano en la zona del teléfono. Toda resta de tiempos se hace en ms, igual que
// el bridge, para que los redondeos den lo mismo hasta en el .5.

/**
 * De qué sistema sale la salud (healthkit-bridge.js:35-64). NO es cosmético: la fuente que se graba en
 * `mypump_salud_diaria.fuente` es la que desempata el motor de recuperación, y la métrica de HRV decide cuánto pesa
 * (HealthKit solo tiene SDNN; Health Connect solo rMSSD, que el motor pesa más).
 *
 * Los vectores son de iPhone ([IOS]). Lo de [ANDROID] sale de las tablas del bridge, con sus pruebas propias: el permiso
 * de historial de Health Connect (el alcance de 30 días sin `READ_HEALTH_DATA_HISTORY`, healthkit-bridge.js:266-330 y
 * 999-1060) en `SincronizadorSalud`, y la fuente de Health Connect en `:app` (`FuenteHealthConnect`).
 */
enum class PlataformaSalud(val fuente: String, val metricaHRV: String) {
    IOS("apple_health", "sdnn"),
    ANDROID("health_connect", "rmssd"),
}

/** Las tablas del bridge (`AGG`, `SAMPLES`, `NUCLEO`) y los topes de lectura y de envío. */
object PuenteSalud {
    /** `readSamples` no pagina: si vuelven exactamente estas, se parte la ventana al medio. */
    const val LIMITE_MUESTRAS = 5000
    const val LOTE_SALUD = 300
    const val LOTE_ENTRENOS = 200

    /** Camino A: `queryAggregated`, solo los tres que el plugin agrega sin rechazar. */
    data class Agregado(val dataType: String, val tipo: String, val agregacion: String)

    val agregados: List<Agregado> = listOf(
        Agregado("steps", "pasos", "sum"),
        Agregado("calories", "kcal_activas", "sum"),
        Agregado("restingHeartRate", "fc_reposo", "average"),
    )

    /** Cómo se colapsan las muestras de un día. */
    enum class Como { SUMA, MEDIANA, ULTIMO }

    /** Camino B: `readSamples` y agregación propia. */
    data class TipoMuestra(
        val dataType: String,
        val tipo: String,
        val como: Como,
        /** Se multiplica solo si el valor es ≤ 1 (SpO2 y grasa a veces vienen 0-1). */
        val escala: Double? = null,
        /** Conversión fija de unidad (m → km). */
        val factor: Double? = null,
        /** Un tipo que esta versión de iOS no conoce hace fallar el pedido de permisos entero. */
        val minIOS: Int? = null,
        /** No se pide en Android (el enum de Kotlin del plugin no lo tiene, o Google lo rechaza por acceso excesivo). */
        val soloIOS: Boolean = false,
        /** Otra forma de colapsar en Android: `basalCalories` es una TASA en Health Connect (sumarla da 4×). */
        val comoAndroid: Como? = null,
    )

    /** El orden importa: es el de los registros que salen. */
    val muestras: List<TipoMuestra> = listOf(
        TipoMuestra("exerciseTime", "actividad_min", Como.SUMA, soloIOS = true),
        TipoMuestra("respiratoryRate", "respiracion_rpm", Como.MEDIANA),
        TipoMuestra("oxygenSaturation", "spo2_pct", Como.MEDIANA, escala = 100.0, soloIOS = true),
        TipoMuestra("appleSleepingWristTemperature", "temp_muneca_c", Como.MEDIANA, minIOS = 16, soloIOS = true),
        TipoMuestra("bodyFat", "grasa_pct", Como.MEDIANA, escala = 100.0),
        TipoMuestra("weight", "peso_kg", Como.ULTIMO),
        TipoMuestra("distance", "distancia_km", Como.SUMA, factor = 0.001),
        TipoMuestra("flightsClimbed", "pisos", Como.SUMA),
        TipoMuestra("basalCalories", "kcal_basales", Como.SUMA, comoAndroid = Como.MEDIANA),
        TipoMuestra("bodyTemperature", "temp_corporal_c", Como.MEDIANA, soloIOS = true),
        TipoMuestra("bloodGlucose", "glucosa_mg_dl", Como.MEDIANA, soloIOS = true),
        TipoMuestra("mindfulness", "mindful_min", Como.SUMA, soloIOS = true),
        TipoMuestra("heartRate", "fc_media", Como.MEDIANA),
    )

    /** Lo que sostiene el score de recuperación: va en la primera tanda de permisos y sola. */
    val nucleo: List<String> = listOf("steps", "calories", "restingHeartRate", "sleep", "heartRateVariability", "weight")

    /** `soportado(m)`: `soloIOS` corta en Android; `minIOS` en iPhones viejos (con `iosMayor` 0, desconocido, se pide). */
    fun soportado(m: TipoMuestra, plataforma: PlataformaSalud, iosMayor: Int): Boolean {
        if (plataforma == PlataformaSalud.ANDROID) return !m.soloIOS
        val min = m.minIOS ?: return true
        return iosMayor == 0 || iosMayor >= min
    }

    /** `comoDe(m)`. */
    fun como(m: TipoMuestra, plataforma: PlataformaSalud): Como =
        if (plataforma == PlataformaSalud.ANDROID && m.comoAndroid != null) m.comoAndroid else m.como

    /** `tiposLectura()`: todo lo que se lee, en el orden del bridge. 'workouts' es el permiso de los entrenamientos. */
    fun tiposLectura(plataforma: PlataformaSalud, iosMayor: Int): List<String> =
        agregados.map { it.dataType } + muestras.filter { soportado(it, plataforma, iosMayor) }.map { it.dataType } +
            listOf("sleep", "heartRateVariability", "workouts")

    /** La tanda secundaria: todo lo que no es núcleo. */
    fun resto(plataforma: PlataformaSalud, iosMayor: Int): List<String> = tiposLectura(plataforma, iosMayor).filter { it !in nucleo }
}

// MARK: Lo que entra (lo que el plugin le entrega al bridge)

/** Una etapa de una sesión de sueño (`stages` del plugin: así manda Health Connect, una sesión con sus etapas adentro). */
data class EtapaSueno(val inicio: Double, val fin: Double, val estado: String)

/** Una muestra de `readSamples`. Las horas, redondeadas al ms (el ISO con milisegundos que el plugin le pasa a la web). */
data class MuestraSalud(
    val inicio: Double,
    val fin: Double,
    /** En la unidad del plugin: HRV en ms, SpO2 y grasa en 0-1, distancia en m, temperatura en °C. En el sueño y la
     *  meditación, la duración en minutos. */
    val valor: Double,
    /** `sourceId`: el paquete de la app o el reloj que la escribió. */
    val fuenteId: String,
    /** `sourceName`. */
    val fuenteNombre: String,
    /** Solo sueño: el `sleepState` del plugin (inBed, asleep, awake, light, deep, rem) o null si no lo conoce. En iPhone
     *  cada muestra con estado es su propia etapa (el plugin 8.9.3 manda `stages` con UNA etapa igual a la muestra). */
    val estadoSueno: String? = null,
    /** Solo sueño: las etapas de una sesión (Health Connect). Con etapas, la muestra es la sesión entera ('inbed'). */
    val etapas: List<EtapaSueno>? = null,
)

/** Un balde diario de `queryAggregated` (solo los que tienen valor). */
data class BaldeDiario(val inicio: Double, val valor: Double)

/** Un entrenamiento de `queryWorkouts` (`workoutToPayload`). */
data class EntrenoCrudo(
    /** `workoutType` del plugin ("running", "strengthTraining", "other"…). */
    val tipo: String,
    /** Segundos ENTEROS: el plugin hace `Int(workout.duration)`. */
    val duracion: Double,
    val inicio: Double,
    val fin: Double,
    /** kcal (`totalEnergyBurned`). */
    val kcal: Double? = null,
    /** Metros (`totalDistance`). */
    val distancia: Double? = null,
)

// MARK: Lo que sale

/** Una fila para `mypump_ingest_salud`. */
data class RegistroSalud(val fecha: String, val tipo: String, val valor: Double, val fuente: String, val detalle: ValorJson? = null) {
    /** Sin `detalle` la clave NO va: la base guarda `NULL` si falta, y un `null` explícito quedaría como JSON null. */
    val json: ValorJson
        get() {
            val o = linkedMapOf<String, ValorJson>(
                "fecha" to ValorJson.Texto(fecha), "tipo" to ValorJson.Texto(tipo), "valor" to ValorJson.Numero(valor),
                "fuente" to ValorJson.Texto(fuente),
            )
            if (detalle != null) o["detalle"] = detalle
            return ValorJson.Objeto(o)
        }
}

/** Una fila para `mypump_ingest_entrenos`. Van las nueve claves siempre, con null donde no hay dato (como la web). */
data class EntrenoSalud(
    val inicio: String,
    val fin: String?,
    val tipo: String,
    val duracionMin: Double?,
    val kcal: Double?,
    val distanciaKm: Double?,
    val fcMedia: Double?,
    val fcMax: Double?,
    val fuente: String,
) {
    val json: ValorJson
        get() {
            fun n(x: Double?): ValorJson = x?.let { ValorJson.Numero(it) } ?: ValorJson.Nulo
            return ValorJson.objeto(
                "inicio" to ValorJson.Texto(inicio), "fin" to (fin?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
                "tipo" to ValorJson.Texto(tipo), "duracion_min" to n(duracionMin), "kcal" to n(kcal),
                "distancia_km" to n(distanciaKm), "fc_media" to n(fcMedia), "fc_max" to n(fcMax), "fuente" to ValorJson.Texto(fuente),
            )
        }
}

// MARK: Fechas y horas locales, como el `Date` de JS

/**
 * Las cuentas de calendario que el bridge hace con `Date` de JS: gregoriano (proléptico, como JS), en la zona del
 * teléfono.
 */
class RelojLocal(val zona: ZoneId = ZoneId.systemDefault()) {
    private fun local(ms: Double): ZonedDateTime = instante(ms).atZone(zona)

    /** `ymd(d)`: la fecha local "YYYY-MM-DD". */
    fun ymd(ms: Double): String {
        val d = local(ms)
        return String.format(Locale.ROOT, "%04d-%02d-%02d", d.year, d.monthValue, d.dayOfMonth)
    }

    /** `getHours()` y `getMinutes()`. */
    fun horaYMinutos(ms: Double): Pair<Int, Int> {
        val d = local(ms)
        return d.hour to d.minute
    }

    /** El comienzo del día local `y-m-d` (si la medianoche no existe por un cambio de hora, el primer instante). Un día
     *  fuera de rango pasa al mes de al lado, como `new Date(y, m, d)`. */
    private fun inicioDelDia(y: Int, m: Int, d: Int, mediodia: Boolean = false): Double {
        val fecha = LocalDate.of(y, m, 1).plusDays(d.toLong() - 1)
        return if (mediodia) ms(ZonedDateTime.of(fecha, LocalTime.NOON, zona).toInstant()) else ms(fecha.atStartOfDay(zona).toInstant())
    }

    /** `haceNDias(n)`: la medianoche local de hace `n` días (0 = hoy). */
    fun medianoche(haceDias: Int, desde: Double): Double {
        val d = local(desde)
        return inicioDelDia(d.year, d.monthValue, d.dayOfMonth - haceDias)
    }

    /** Desde dónde se pide el sueño: el mediodía local del día anterior a `ms` (la noche que se imputa al día del borde
     *  empezó la tarde anterior). */
    fun mediodiaDelDiaAnterior(ms: Double): Double {
        val d = local(ms)
        return inicioDelDia(d.year, d.monthValue, d.dayOfMonth - 1, mediodia = true)
    }

    companion object {
        /** Holgado adentro de lo que entra en un `LocalDateTime` (±999.999.999 años, con la zona): más allá, java.time tira. */
        private const val MAX_SEGUNDOS = 3.0e16
        private const val MIN_SEGUNDOS = -3.0e16

        /** Un instante de ms (un NaN o algo fuera de rango no tira: queda en el borde, como el `Date` de iOS). */
        fun instante(ms: Double): Instant {
            val piso = Math.floor(ms / 1000)
            val s = if (piso.isNaN()) 0.0 else piso.coerceIn(MIN_SEGUNDOS, MAX_SEGUNDOS)
            val resto = if (piso.isNaN() || s != piso) 0.0 else (ms - piso * 1000).coerceIn(0.0, 999.999)
            return Instant.ofEpochSecond(s.toLong(), (resto * 1_000_000).toLong())
        }

        fun ms(i: Instant): Double = i.toEpochMilli().toDouble()

        /** `new Date(ms).toISOString()`. */
        fun iso(ms: Double): String {
            val i = instante(ms)
            val t = LocalDateTime.ofEpochSecond(i.epochSecond, 0, ZoneOffset.UTC)
            val segundos = Math.floor(ms / 1000)
            val resto = if (segundos.isFinite()) (ms - segundos * 1000).let { if (it.isFinite()) it.toLong() else 0L } else 0L
            return String.format(
                Locale.ROOT, "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", t.year, t.monthValue, t.dayOfMonth, t.hour, t.minute, t.second, resto,
            )
        }

        /**
         * `Date.parse` de un ISO: el de `marcarSync` ("…T13:59:00.000Z") o un timestamptz de PostgREST
         * ("2026-10-14 13:59:00.123456+00:00", con microsegundos). null si no se puede leer.
         */
        fun desdeIso(texto: String): Double? = FechaIsoReglas.instante(texto)?.let(::ms)
    }
}
