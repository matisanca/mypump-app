package com.pumpteam.mypump.salud

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import kotlin.reflect.KClass

/**
 * Un Health Connect de mentira: los registros que hay, los permisos dados y lo que contestan los agregados. Pagina como
 * Health Connect (el token dice desde dónde sigue) y anota cada consulta, para ver que la fuente pide lo mismo que el
 * plugin.
 */
class ClienteDePrueba(
    registros: List<Record> = emptyList(),
    var dados: Set<String> = emptySet(),
    var conHistorial: Boolean = true,
) : ClienteHealthConnect {
    val registros = registros.toMutableList()

    data class Pagina(val tipo: String, val desde: Instant, val hasta: Instant, val tamano: Int, val token: String?)
    data class Agrupado(val desde: Instant, val hasta: Instant, val tramo: Duration, val metricas: Set<AggregateMetric<*>>)
    data class Agregado(val desde: Instant, val hasta: Instant, val metricas: Set<AggregateMetric<*>>)

    val paginas = ArrayList<Pagina>()
    val agrupados = ArrayList<Agrupado>()
    val agregados = ArrayList<Agregado>()

    /** Lo que da cada balde de `aggregateGroupByDuration` (por su inicio). */
    var balde: (Instant) -> Map<AggregateMetric<*>, Any> = { emptyMap() }

    /** Lo que da `aggregate` (o tira, como Health Connect sin el permiso). */
    var suma: (Set<AggregateMetric<*>>, Instant, Instant) -> Map<AggregateMetric<*>, Any> = { _, _, _ -> emptyMap() }

    override suspend fun permisosDados(): Set<String> = dados

    override fun historialDisponible(): Boolean = conHistorial

    override suspend fun <T : Record> pagina(tipo: KClass<T>, desde: Instant, hasta: Instant, tamano: Int, token: String?): ClienteHealthConnect.Pagina<T> {
        paginas += Pagina(tipo.simpleName ?: "?", desde, hasta, tamano, token)
        // Lo que se solapa con el rango, como `TimeRangeFilter.between`: un intervalo que se toca con [desde, hasta), o una
        // lectura con su hora adentro. (Las interfaces de intervalo y de lectura son internas de la librería: las horas se
        // leen por sus getters.)
        @Suppress("UNCHECKED_CAST")
        val todos = registros.filter { tipo.isInstance(it) }.filter {
            val inicio = hora(it, "getStartTime")
            val fin = hora(it, "getEndTime")
            val en = hora(it, "getTime")
            if (inicio != null && fin != null) inicio < hasta && fin > desde else en != null && en >= desde && en < hasta
        } as List<T>
        val desdeIndice = token?.toInt() ?: 0
        val pagina = todos.drop(desdeIndice).take(tamano)
        val siguiente = if (desdeIndice + tamano < todos.size) (desdeIndice + tamano).toString() else null
        return ClienteHealthConnect.Pagina(pagina, siguiente)
    }

    private fun hora(r: Record, getter: String): Instant? =
        r.javaClass.methods.firstOrNull { it.name == getter && it.parameterCount == 0 }?.invoke(r) as? Instant

    override suspend fun agrupado(metricas: Set<AggregateMetric<*>>, desde: Instant, hasta: Instant, tramo: Duration): List<ClienteHealthConnect.Grupo> {
        agrupados += Agrupado(desde, hasta, tramo, metricas)
        val grupos = ArrayList<ClienteHealthConnect.Grupo>()
        var t = desde
        while (t < hasta) {
            val fin = minOf(t.plus(tramo), hasta)
            grupos += ClienteHealthConnect.Grupo(t, fin, balde(t))
            t = fin
        }
        return grupos
    }

    override suspend fun agregado(metricas: Set<AggregateMetric<*>>, desde: Instant, hasta: Instant): Map<AggregateMetric<*>, Any> {
        agregados += Agregado(desde, hasta, metricas)
        return suma(metricas, desde, hasta)
    }
}

/** Una fuente sobre el cliente de mentira: SDK disponible (salvo que se diga otra cosa) y la hoja anotada. */
class FuenteDePrueba(
    val cliente: ClienteDePrueba = ClienteDePrueba(),
    var estado: Int = HealthConnectClient.SDK_AVAILABLE,
) {
    val hojas = ArrayList<Set<String>>()

    /** Lo que hace el cliente en la hoja: por defecto, dar todo lo que se le pidió. */
    var alAbrirHoja: (Set<String>) -> Unit = { cliente.dados = cliente.dados + it }

    val fuente = FuenteHealthConnect(
        estadoSdk = { estado },
        crearCliente = { cliente },
        hoja = { permisos ->
            hojas += permisos
            alAbrirHoja(permisos)
            cliente.dados
        },
        despachador = kotlinx.coroutines.Dispatchers.Unconfined,
    )
}

/** Fechas de las pruebas: el día [dia] de octubre de 2026 en UTC, a la hora que se pida. */
fun t(dia: Int, hora: Int, minuto: Int = 0, segundo: Int = 0, nanos: Int = 0): Instant =
    Instant.parse("2026-10-01T00:00:00Z").plus(Duration.ofDays(dia - 1L)).plusSeconds(hora * 3600L + minuto * 60L + segundo).plusNanos(nanos.toLong())

val UTC: ZoneOffset = ZoneOffset.UTC

/**
 * Un `Metadata` como el que devuelve Health Connect al leer (con el paquete que escribió el dato y el equipo). Los
 * constructores públicos de la librería son para ESCRIBIR y dejan el origen vacío; este es el que usa la propia librería
 * al leer, que existe pero no se publica para Kotlin.
 */
fun leido(paquete: String = "com.sec.android.app.shealth", fabricante: String? = "Samsung", modelo: String? = "Galaxy Watch6", id: String = "r"): Metadata =
    Metadata::class.java.getConstructor(
        Int::class.javaPrimitiveType, String::class.java, DataOrigin::class.java, Instant::class.java, String::class.java,
        Long::class.javaPrimitiveType, Device::class.java,
    ).newInstance(
        Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED, id, DataOrigin(paquete), Instant.EPOCH, null, 0L,
        if (fabricante == null && modelo == null) null else Device(Device.TYPE_WATCH, fabricante, modelo),
    )
