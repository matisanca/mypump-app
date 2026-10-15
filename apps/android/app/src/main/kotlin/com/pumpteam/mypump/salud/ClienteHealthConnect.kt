package com.pumpteam.mypump.salud

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.request.AggregateGroupByDurationRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Duration
import java.time.Instant
import kotlin.reflect.KClass

/**
 * Lo que se le pregunta a Health Connect, sin nada encima: los permisos dados, si tiene el historial, una página de
 * registros y los agregados. La lógica del plugin (páginas, límites, orden, baldes, el respaldo de las calorías de un
 * entreno) vive en [FuenteHealthConnect] sobre esto, así se prueba en la JVM con un doble que contesta como Health
 * Connect.
 */
interface ClienteHealthConnect {
    suspend fun permisosDados(): Set<String>

    /** `isHistoryAccessAvailable`: el permiso de historial solo existe en un Health Connect nuevo (Android 14 ext. 13+ o
     *  el APK 171302+); en uno viejo no se puede dar nunca. */
    fun historialDisponible(): Boolean

    /** Una página de `readRecords`: ascendente, sin filtro de origen, `TimeRangeFilter.between(desde, hasta)`. */
    suspend fun <T : Record> pagina(tipo: KClass<T>, desde: Instant, hasta: Instant, tamano: Int, token: String?): Pagina<T>

    /** `aggregateGroupByDuration`: un grupo por tramo, con lo que dio cada métrica (las que no tuvieron dato no están). */
    suspend fun agrupado(metricas: Set<AggregateMetric<*>>, desde: Instant, hasta: Instant, tramo: Duration): List<Grupo>

    /** `aggregate` de todo el rango. */
    suspend fun agregado(metricas: Set<AggregateMetric<*>>, desde: Instant, hasta: Instant): Map<AggregateMetric<*>, Any>

    data class Pagina<T>(val registros: List<T>, val token: String?)

    data class Grupo(val inicio: Instant, val fin: Instant, val valores: Map<AggregateMetric<*>, Any>)
}

/** El de verdad: el `HealthConnectClient` del teléfono, con los mismos pedidos que arma el plugin. */
class ClienteHealthConnectReal(private val cliente: HealthConnectClient) : ClienteHealthConnect {
    override suspend fun permisosDados(): Set<String> = cliente.permissionController.getGrantedPermissions()

    override fun historialDisponible(): Boolean =
        cliente.features.getFeatureStatus(HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE

    override suspend fun <T : Record> pagina(tipo: KClass<T>, desde: Instant, hasta: Instant, tamano: Int, token: String?): ClienteHealthConnect.Pagina<T> {
        val r = cliente.readRecords(
            ReadRecordsRequest(recordType = tipo, timeRangeFilter = TimeRangeFilter.between(desde, hasta), pageSize = tamano, pageToken = token),
        )
        return ClienteHealthConnect.Pagina(r.records, r.pageToken)
    }

    override suspend fun agrupado(metricas: Set<AggregateMetric<*>>, desde: Instant, hasta: Instant, tramo: Duration): List<ClienteHealthConnect.Grupo> =
        cliente.aggregateGroupByDuration(
            AggregateGroupByDurationRequest(metrics = metricas, timeRangeFilter = TimeRangeFilter.between(desde, hasta), timeRangeSlicer = tramo),
        ).map { ClienteHealthConnect.Grupo(it.startTime, it.endTime, valores(it.result, metricas)) }

    override suspend fun agregado(metricas: Set<AggregateMetric<*>>, desde: Instant, hasta: Instant): Map<AggregateMetric<*>, Any> =
        valores(cliente.aggregate(AggregateRequest(metrics = metricas, timeRangeFilter = TimeRangeFilter.between(desde, hasta))), metricas)

    private fun valores(r: AggregationResult, metricas: Set<AggregateMetric<*>>): Map<AggregateMetric<*>, Any> = buildMap {
        for (m in metricas) r[m]?.let { put(m, it) }
    }
}
