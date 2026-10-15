package com.pumpteam.mypump.salud.banco

import android.content.Context
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import app.capgo.plugin.health.HealthDataType
import app.capgo.plugin.health.HealthManager
import com.pumpteam.mypump.salud.PluginDeLaCapacitor
import com.pumpteam.mypump.salud.RechazoDelPlugin
import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeParseException
import kotlin.coroutines.cancellation.CancellationException
import org.json.JSONArray
import org.json.JSONObject

/**
 * HealthPlugin.kt de @capgo/capacitor-health 8.9.3 sin Capacitor, para el banco: los mismos chequeos, los mismos textos de
 * rechazo y SU HealthManager (copiado de node_modules al compilar las pruebas) haciendo las consultas. Lo que en Capacitor
 * es `call.reject(m)` acá es [RechazoDelPlugin]; `call.resolve(o)`, devolver `o`; los `call.getX` leen como Capacitor
 * (un valor de otro tipo cuenta como ausente). La hoja de permisos no se abre: el banco corre con todo dado.
 */
class PluginCapgo(private val contexto: Context) : PluginDeLaCapacitor {
    private val manager = HealthManager()

    override suspend fun llamar(metodo: String, opciones: JSONObject): JSONObject = when (metodo) {
        "isAvailable" -> availabilityPayload(HealthConnectClient.getSdkStatus(contexto))
        "requestAuthorization" -> requestAuthorization(opciones)
        "checkAuthorization" -> checkAuthorization(opciones)
        "readSamples" -> readSamples(opciones)
        "queryAggregated" -> queryAggregated(opciones)
        "queryWorkouts" -> queryWorkouts(opciones)
        else -> throw RechazoDelPlugin("\"Health.$metodo()\" is not implemented on android")
    }

    // MARK: Como PluginCall

    private fun JSONObject.texto(k: String): String? = opt(k) as? String
    private fun JSONObject.entero(k: String): Int? = opt(k) as? Int
    private fun JSONObject.booleano(k: String): Boolean? = opt(k) as? Boolean
    private fun JSONObject.lista(k: String): JSONArray? = opt(k) as? JSONArray

    private fun rechazar(m: String?): Nothing = throw RechazoDelPlugin(m)

    // MARK: HealthPlugin.kt

    private suspend fun requestAuthorization(o: JSONObject): JSONObject {
        val (readTypes, includeWorkouts) = try {
            parseTypeListWithWorkouts(o, "read")
        } catch (e: IllegalArgumentException) {
            rechazar(e.message)
        }
        val writeTypes = try {
            parseTypeList(o, "write")
        } catch (e: IllegalArgumentException) {
            rechazar(e.message)
        }
        val includeHistoryAccess = o.booleano("requestHistoryAccess") ?: false
        val client = clientOrReject()
        val requestHistoryAccess = includeHistoryAccess && manager.isHistoryAccessAvailable(client)
        val permissions = manager.permissionsFor(readTypes, writeTypes, includeWorkouts, requestHistoryAccess)
        if (permissions.isEmpty()) return manager.authorizationStatus(client, readTypes, writeTypes, includeWorkouts, includeHistoryAccess)
        val granted = client.permissionController.getGrantedPermissions()
        if (granted.containsAll(permissions)) return manager.authorizationStatus(client, readTypes, writeTypes, includeWorkouts, includeHistoryAccess)
        rechazar("el banco no abre la hoja de permisos (faltan ${permissions - granted})")
    }

    private suspend fun checkAuthorization(o: JSONObject): JSONObject {
        val (readTypes, includeWorkouts) = try {
            parseTypeListWithWorkouts(o, "read")
        } catch (e: IllegalArgumentException) {
            rechazar(e.message)
        }
        val writeTypes = try {
            parseTypeList(o, "write")
        } catch (e: IllegalArgumentException) {
            rechazar(e.message)
        }
        val includeHistoryAccess = o.booleano("requestHistoryAccess") ?: false
        val client = clientOrReject()
        return manager.authorizationStatus(client, readTypes, writeTypes, includeWorkouts, includeHistoryAccess)
    }

    private suspend fun readSamples(o: JSONObject): JSONObject {
        val identifier = o.texto("dataType")
        if (identifier.isNullOrBlank()) rechazar("dataType is required")
        val dataType = HealthDataType.from(identifier) ?: rechazar("Unsupported data type: $identifier")
        val limit = (o.entero("limit") ?: DEFAULT_LIMIT).coerceAtLeast(0)
        val ascending = o.booleano("ascending") ?: false
        val (startInstant, endInstant) = rango(o)
        val client = clientOrReject()
        return try {
            JSONObject().put("samples", manager.readSamples(client, dataType, startInstant, endInstant, limit, ascending))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            rechazar(e.message ?: "Failed to read samples.")
        }
    }

    private suspend fun queryWorkouts(o: JSONObject): JSONObject {
        val workoutType = o.texto("workoutType")
        val limit = (o.entero("limit") ?: DEFAULT_LIMIT).coerceAtLeast(0)
        val ascending = o.booleano("ascending") ?: false
        val anchor = o.texto("anchor")
        val (startInstant, endInstant) = rango(o)
        val client = clientOrReject()
        return try {
            manager.queryWorkouts(client, workoutType, startInstant, endInstant, limit, ascending, anchor)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            rechazar(e.message ?: "Failed to query workouts.")
        }
    }

    private suspend fun queryAggregated(o: JSONObject): JSONObject {
        val identifier = o.texto("dataType")
        if (identifier.isNullOrBlank()) rechazar("dataType is required")
        val dataType = HealthDataType.from(identifier) ?: rechazar("Unsupported data type: $identifier")
        val bucket = o.texto("bucket") ?: "day"
        val aggregations: List<String> = o.lista("aggregation")?.let { a -> (0 until a.length()).map { a.getString(it) } }
            ?: o.texto("aggregation")?.let { listOf(it) }
            ?: listOf(
                when (dataType) {
                    HealthDataType.STEPS, HealthDataType.DISTANCE, HealthDataType.CALORIES -> "sum"
                    HealthDataType.HEART_RATE, HealthDataType.WEIGHT, HealthDataType.RESTING_HEART_RATE -> "average"
                    else -> "sum"
                },
            )
        if (aggregations.isEmpty()) rechazar("aggregation must not be empty")
        val (startInstant, endInstant) = rango(o)
        val client = clientOrReject()
        return try {
            manager.queryAggregated(client, dataType, startInstant, endInstant, bucket, aggregations)
        } catch (e: CancellationException) {
            throw e
        } catch (e: SecurityException) {
            Log.w("HealthPlugin", "Permission denied for aggregation: ${e.message}", e)
            rechazar(e.message ?: "Permission denied for aggregated data.")
        } catch (e: IllegalArgumentException) {
            rechazar(e.message ?: "Unsupported aggregation.")
        } catch (e: Exception) {
            rechazar(e.message ?: "Failed to query aggregated data.")
        }
    }

    /** `parseInstant` de las dos puntas con sus valores por defecto, y el chequeo del orden. */
    private fun rango(o: JSONObject): Pair<Instant, Instant> {
        val start = try {
            manager.parseInstant(o.texto("startDate"), Instant.now().minus(DEFAULT_PAST_DURATION))
        } catch (e: DateTimeParseException) {
            rechazar(e.message)
        }
        val end = try {
            manager.parseInstant(o.texto("endDate"), Instant.now())
        } catch (e: DateTimeParseException) {
            rechazar(e.message)
        }
        if (end.isBefore(start)) rechazar("endDate must be greater than or equal to startDate")
        return start to end
    }

    private fun parseTypeList(o: JSONObject, key: String): List<HealthDataType> {
        val array = o.lista(key) ?: JSONArray()
        val result = mutableListOf<HealthDataType>()
        for (i in 0 until array.length()) {
            val identifier = array.optString(i, null) ?: continue
            result.add(HealthDataType.from(identifier) ?: throw IllegalArgumentException("Unsupported data type: $identifier"))
        }
        return result
    }

    private fun parseTypeListWithWorkouts(o: JSONObject, key: String): Pair<List<HealthDataType>, Boolean> {
        val array = o.lista(key) ?: JSONArray()
        val result = mutableListOf<HealthDataType>()
        var includeWorkouts = false
        for (i in 0 until array.length()) {
            val identifier = array.optString(i, null) ?: continue
            if (identifier == "workouts") {
                includeWorkouts = true
            } else {
                result.add(HealthDataType.from(identifier) ?: throw IllegalArgumentException("Unsupported data type: $identifier"))
            }
        }
        return result to includeWorkouts
    }

    private fun clientOrReject(): HealthConnectClient {
        val status = HealthConnectClient.getSdkStatus(contexto)
        if (status != HealthConnectClient.SDK_AVAILABLE) rechazar(availabilityReason(status))
        return HealthConnectClient.getOrCreate(contexto)
    }

    private fun availabilityPayload(status: Int): JSONObject = JSONObject().apply {
        put("platform", "android")
        put("available", status == HealthConnectClient.SDK_AVAILABLE)
        if (status != HealthConnectClient.SDK_AVAILABLE) put("reason", availabilityReason(status))
    }

    private fun availabilityReason(status: Int): String = when (status) {
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "Health Connect needs an update."
        HealthConnectClient.SDK_UNAVAILABLE -> "Health Connect is unavailable on this device."
        else -> "Health Connect availability unknown."
    }

    private companion object {
        const val DEFAULT_LIMIT = 100
        val DEFAULT_PAST_DURATION: Duration = Duration.ofDays(1)
    }
}
