package com.pumpteam.mypump.salud

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Length
import com.pumpteam.mypump.datos.ErrorFuenteSalud
import com.pumpteam.mypump.datos.FuenteSalud
import com.pumpteam.mypump.datos.HistorialSalud
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.datos.PermisosSalud
import com.pumpteam.mypump.reglas.BaldeDiario
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.MuestraSalud
import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import com.pumpteam.mypump.reglas.RelojLocal
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.max
import kotlin.math.min
import kotlin.reflect.KClass
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Health Connect consultado EXACTAMENTE como lo consulta hoy el plugin de la app Capacitor (@capgo/capacitor-health 8.9.3,
 * HealthPlugin.kt + HealthManager.kt): los mismos registros y unidades, las mismas páginas (de 500 como mucho, hasta
 * juntar el límite), el orden y el límite de muestras y entrenos, los baldes de un día desde la medianoche que manda el
 * bridge (`aggregateGroupByDuration` de 24 h, como el plugin), el respaldo de las calorías de un entreno y los mismos
 * textos de error (van al diagnóstico). Gemelo de FuenteHealthKit.swift. Lo que hace el bridge con lo que devuelve vive
 * en :core (PuenteSalud, AgregacionSalud, SincronizadorSalud).
 *
 * Solo LEE: ningún pedido lleva escritura, y el manifest no declara ningún permiso `WRITE_`. La hoja de permisos la abre
 * [hoja] (en la app, [PermisosHealthConnect], con el contrato registrado en la MainActivity).
 *
 * Lo que pesa (ordenar decenas de miles de lecturas de pulso) corre en [despachador], fuera del hilo principal.
 */
class FuenteHealthConnect(
    /** `HealthConnectClient.getSdkStatus(context)`. */
    private val estadoSdk: () -> Int,
    /** El cliente: se crea en cada consulta, con el SDK disponible, como `getClientOrReject`. */
    private val crearCliente: () -> ClienteHealthConnect,
    /** La hoja de permisos de Health Connect. Lo que devuelve no se usa: como el plugin, después se releen los dados. */
    private val hoja: suspend (Set<String>) -> Set<String>,
    private val despachador: CoroutineDispatcher = Dispatchers.Default,
) : FuenteSalud {
    constructor(contexto: Context) : this(
        estadoSdk = { HealthConnectClient.getSdkStatus(contexto) },
        crearCliente = { ClienteHealthConnectReal(HealthConnectClient.getOrCreate(contexto)) },
        hoja = PermisosHealthConnect::pedir,
    )

    override val plataforma: PlataformaSalud = PlataformaSalud.ANDROID

    // MARK: Disponibilidad y permisos (HealthPlugin.kt)

    /** `isAvailable`: solo con el SDK disponible (en Android 13 o menos, además, Health Connect instalado y al día). */
    override suspend fun disponible(): Boolean = estadoSdk() == HealthConnectClient.SDK_AVAILABLE

    override suspend fun pedirLectura(tipos: List<String>) {
        pedir(tipos, conHistorial = false)
    }

    override suspend fun pedirLecturaConHistorial(tipos: List<String>): HistorialSalud? = pedir(tipos, conHistorial = true)

    /**
     * `requestAuthorization`: si ya están todos los permisos no se abre nada; si falta alguno se abre la hoja (y vuelve
     * cuando el cliente la cierra, haya dicho que sí o que no). El historial se pide solo si este Health Connect lo
     * conoce: en uno viejo no se puede dar nunca y la hoja se reabriría cada vez.
     */
    private suspend fun pedir(tipos: List<String>, conHistorial: Boolean): HistorialSalud? {
        val (lectura, entrenos) = tiposYEntrenos(tipos)
        val c = cliente()
        val conPermisoDeHistorial = conHistorial && c.historialDisponible()
        val permisos = permisosPara(lectura, entrenos, conPermisoDeHistorial)
        if (permisos.isNotEmpty() && !c.permisosDados().containsAll(permisos)) {
            try {
                hoja(permisos)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                throw ErrorFuenteSalud("Failed to launch Health Connect permission request.")
            }
        }
        return if (conHistorial) historialDe(c) else null
    }

    /** `checkAuthorization`: en Health Connect lo autorizado es lo que el cliente DIO (no como HealthKit). */
    override suspend fun permisos(tipos: List<String>): PermisosSalud = withContext(despachador) {
        val (lectura, entrenos) = tiposYEntrenos(tipos)
        val dados = cliente().permisosDados()
        val si = ArrayList<String>()
        val no = ArrayList<String>()
        for (t in lectura) if (t.permisoLectura in dados) si += t.dataType else no += t.dataType
        if (entrenos) {
            if (TraduccionHealthConnect.permisoEntrenos in dados) si += "workouts" else no += "workouts"
        }
        PermisosSalud(preguntados = si, pendientes = no)
    }

    /** `checkAuthorization({read: NUCLEO, requestHistoryAccess: true})`: el historial, sin abrir la hoja. */
    override suspend fun historial(): HistorialSalud = withContext(despachador) {
        tiposYEntrenos(PuenteSalud.nucleo)
        historialDe(cliente())
    }

    /** `historyAccessAvailable` / `historyAccessAuthorized` (que es false sí o sí si no está disponible). */
    private suspend fun historialDe(c: ClienteHealthConnect): HistorialSalud {
        val dados = c.permisosDados()
        val disponible = c.historialDisponible()
        return HistorialSalud(autorizado = disponible && TraduccionHealthConnect.PERMISO_HISTORIAL in dados, disponible = disponible)
    }

    // MARK: Lecturas (HealthManager.kt)

    /** `queryAggregated(bucket: 'day', aggregation)`: un balde por día desde `desde`, solo los que tienen valor. */
    override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario> =
        withContext(despachador) {
            val tipo = tipo(dataType)
            val (inicio, fin) = rango(desde, hasta)
            val c = cliente()
            try {
                agregar(c, tipo, inicio, fin, listOf(agregacion))
            } catch (e: CancellationException) {
                throw e
            } catch (e: SecurityException) {
                throw ErrorFuenteSalud(e.message ?: "Permission denied for aggregated data.")
            } catch (e: IllegalArgumentException) {
                throw ErrorFuenteSalud(e.message ?: "Unsupported aggregation.")
            } catch (e: Exception) {
                throw ErrorFuenteSalud(e.message ?: "Failed to query aggregated data.")
            }
        }

    /** `readSamples({limit, ascending: true})`. */
    override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> =
        withContext(despachador) {
            val tipo = tipo(dataType)
            val (inicio, fin) = rango(desde, hasta)
            val c = cliente()
            try {
                leerMuestras(c, tipo, inicio, fin, max(limite, 0), ascendente = true)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                throw ErrorFuenteSalud(e.message ?: "Failed to read samples.")
            }
        }

    /** `queryWorkouts({startDate, endDate})`: el bridge no pasa límite ni orden, así que valen los del plugin (100, del
     *  más nuevo al más viejo). */
    override suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo> = withContext(despachador) {
        val (inicio, fin) = rango(desde, hasta)
        val c = cliente()
        try {
            leerEntrenos(c, inicio, fin, LIMITE_POR_DEFECTO, ascendente = false)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            throw ErrorFuenteSalud(e.message ?: "Failed to query workouts.")
        }
    }

    // MARK: El plugin por dentro

    /** `getClientOrReject`: sin el SDK disponible, el texto de `availabilityReason`. */
    private fun cliente(): ClienteHealthConnect {
        val estado = estadoSdk()
        if (estado != HealthConnectClient.SDK_AVAILABLE) throw ErrorFuenteSalud(motivo(estado))
        return crearCliente()
    }

    private fun tipo(dataType: String): TipoHealthConnect =
        TipoHealthConnect.de(dataType) ?: throw ErrorFuenteSalud("Unsupported data type: $dataType")

    /** Las horas que manda el bridge (ms) como el `Instant.parse` del plugin, y su chequeo del orden. */
    private fun rango(desde: Double, hasta: Double): Pair<Instant, Instant> {
        val inicio = RelojLocal.instante(desde)
        val fin = RelojLocal.instante(hasta)
        if (fin.isBefore(inicio)) throw ErrorFuenteSalud("endDate must be greater than or equal to startDate")
        return inicio to fin
    }

    companion object {
        /** `DEFAULT_LIMIT`, `DEFAULT_PAGE_SIZE`, `MAX_PAGE_SIZE` y `MAX_AGGREGATE_GROUP_BUCKETS` del plugin. */
        const val LIMITE_POR_DEFECTO = 100
        const val PAGINA_POR_DEFECTO = 100
        const val PAGINA_MAXIMA = 500
        const val BALDES_MAXIMOS = 5000L

        /**
         * Pone Health Connect como la fuente del sistema de `ModeloSalud` si nadie puso otra (las pruebas ponen un doble).
         * Va ANTES de crear el `ModeloApp`: el `ModeloSalud` de la cuenta la lee al crearse.
         */
        fun instalar(contexto: Context) {
            if (ModeloSalud.fuenteDelSistema == null) ModeloSalud.fuenteDelSistema = FuenteHealthConnect(contexto.applicationContext)
        }

        /** `availabilityReason`. */
        fun motivo(estado: Int): String = when (estado) {
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "Health Connect needs an update."
            HealthConnectClient.SDK_UNAVAILABLE -> "Health Connect is unavailable on this device."
            else -> "Health Connect availability unknown."
        }

        /** `parseTypeListWithWorkouts`: un tipo que el enum no conoce tira el pedido entero; 'workouts' va aparte. */
        internal fun tiposYEntrenos(tipos: List<String>): Pair<List<TipoHealthConnect>, Boolean> {
            val lectura = ArrayList<TipoHealthConnect>()
            var entrenos = false
            for (t in tipos) {
                if (t == "workouts") entrenos = true else lectura += TipoHealthConnect.de(t) ?: throw ErrorFuenteSalud("Unsupported data type: $t")
            }
            return lectura to entrenos
        }

        /** `permissionsFor`: los de lectura de cada tipo, el de los entrenos y el del historial. Nunca uno de escritura. */
        internal fun permisosPara(lectura: List<TipoHealthConnect>, entrenos: Boolean, historial: Boolean): Set<String> = buildSet {
            lectura.forEach { add(it.permisoLectura) }
            if (entrenos) add(TraduccionHealthConnect.permisoEntrenos)
            if (historial) add(TraduccionHealthConnect.PERMISO_HISTORIAL)
        }

        /**
         * `queryAggregated` con `bucket: 'day'`: se rechaza lo que el plugin rechaza (sueño, las lecturas sueltas y las
         * agregaciones fuera de su matriz) y se pide en tramos de 5000 baldes, con un balde de 24 h desde `inicio`.
         */
        internal suspend fun agregar(c: ClienteHealthConnect, tipo: TipoHealthConnect, inicio: Instant, fin: Instant, agregaciones: List<String>): List<BaldeDiario> {
            if (tipo == TipoHealthConnect.SLEEP) {
                throw IllegalArgumentException("Aggregated queries are not supported for sleep data. Use readSamples instead.")
            }
            if (tipo in listOf(TipoHealthConnect.RESPIRATORY_RATE, TipoHealthConnect.OXYGEN_SATURATION, TipoHealthConnect.HEART_RATE_VARIABILITY, TipoHealthConnect.VO2_MAX)) {
                throw IllegalArgumentException("Aggregated queries are not supported for ${tipo.dataType}. Use readSamples instead.")
            }
            val pedidas = agregaciones.distinct()
            pedidas.forEach { TraduccionHealthConnect.validarAgregacion(tipo, it) }
            val metricas = TraduccionHealthConnect.metricas(tipo)
            val dia = Duration.ofDays(1)
            val tramoMaximo = dia.multipliedBy(BALDES_MAXIMOS)
            val baldes = ArrayList<BaldeDiario>()
            var actual = inicio
            while (actual.isBefore(fin)) {
                val hasta = actual.plus(tramoMaximo).let { if (it.isAfter(fin)) fin else it }
                for (g in c.agrupado(metricas, actual, hasta, dia)) {
                    TraduccionHealthConnect.valorPrincipal(tipo, pedidas, g.valores)?.let { baldes += BaldeDiario(TraduccionHealthConnect.ms(g.inicio), it) }
                }
                actual = hasta
            }
            return baldes
        }

        /** `readSamples`: las páginas, cada registro a sus muestras, y el orden y el límite al final. */
        internal suspend fun leerMuestras(c: ClienteHealthConnect, tipo: TipoHealthConnect, inicio: Instant, fin: Instant, limite: Int, ascendente: Boolean): List<MuestraSalud> {
            val todas = ArrayList<Pair<Instant, MuestraSalud>>()
            @Suppress("UNCHECKED_CAST")
            leerRegistros(c, tipo.registro as KClass<Record>, inicio, fin, limite) { todas += TraduccionHealthConnect.muestras(tipo, it) }
            return TraduccionHealthConnect.ordenar(todas, limite, ascendente)
        }

        /**
         * `readRecords`: páginas de `min(limite, 500)` hasta que no haya más o se junten `limite` REGISTROS (el pulso trae
         * muchas lecturas por registro: el recorte por muestras va después).
         */
        private suspend fun <T : Record> leerRegistros(
            c: ClienteHealthConnect, clase: KClass<T>, inicio: Instant, fin: Instant, limite: Int, consumir: suspend (T) -> Unit,
        ) {
            val tamano = if (limite > 0) min(limite, PAGINA_MAXIMA) else PAGINA_POR_DEFECTO
            var token: String? = null
            var leidos = 0
            do {
                val p = c.pagina(clase, inicio, fin, tamano, token)
                for (r in p.registros) consumir(r)
                leidos += p.registros.size
                token = p.token
            } while (token != null && (limite <= 0 || leidos < limite))
        }

        /**
         * `queryWorkouts`: las mismas páginas; cada sesión, apenas llega, con lo que se sumó en su rango; y el orden y el
         * límite al final.
         */
        internal suspend fun leerEntrenos(c: ClienteHealthConnect, inicio: Instant, fin: Instant, limite: Int, ascendente: Boolean): List<EntrenoCrudo> {
            val ws = ArrayList<Pair<Instant, EntrenoCrudo>>()
            leerRegistros(c, ExerciseSessionRecord::class, inicio, fin, limite) { s ->
                val (distancia, kcal) = sumarEntreno(c, s)
                ws += s.startTime to TraduccionHealthConnect.entreno(s, distancia, kcal)
            }
            val ordenados = ws.sortedBy { it.first }
            val enOrden = if (ascendente) ordenados else ordenados.asReversed()
            return (if (limite > 0) enOrden.take(limite) else enOrden).map { it.second }
        }

        /**
         * `aggregateWorkoutData`: la distancia y las calorías activas en el rango del entreno, de cualquier fuente (el reloj
         * puede no ser el que anotó la sesión). Si eso falla (un permiso que falta) quedan las dos vacías; sin calorías
         * activas se prueba con las totales.
         */
        private suspend fun sumarEntreno(c: ClienteHealthConnect, s: ExerciseSessionRecord): Pair<Double?, Double?> {
            var distancia: Double? = null
            var kcal: Double? = null
            try {
                val r = c.agregado(setOf(DistanceRecord.DISTANCE_TOTAL, ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL), s.startTime, s.endTime)
                distancia = (r[DistanceRecord.DISTANCE_TOTAL] as? Length)?.inMeters
                kcal = (r[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL] as? Energy)?.inKilocalories
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            }
            if (kcal == null) {
                try {
                    val r = c.agregado(setOf(TotalCaloriesBurnedRecord.ENERGY_TOTAL), s.startTime, s.endTime)
                    kcal = (r[TotalCaloriesBurnedRecord.ENERGY_TOTAL] as? Energy)?.inKilocalories
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                }
            }
            return distancia to kcal
        }
    }
}
