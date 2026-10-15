package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ProveedoresDisponibles
import com.pumpteam.mypump.reglas.AgregacionSalud
import com.pumpteam.mypump.reglas.BaldeDiario
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.EntrenoSalud
import com.pumpteam.mypump.reglas.MuestraSalud
import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import com.pumpteam.mypump.reglas.RegistroSalud
import com.pumpteam.mypump.reglas.RelojLocal
import java.net.URLEncoder
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

// La salud del teléfono, la parte que habla con el sistema y con la base (gemelo de MyPumpDatos/Salud.swift). Health
// Connect queda detrás de [FuenteSalud] (en la app, la fuente de `:app`; en los tests, un doble que reproduce lo que
// contestó el plugin), así todo esto se prueba en la JVM sin teléfono.

/**
 * Lo que el bridge le pide al plugin, con los mismos nombres de tipo (`dataType`) y las horas en ms. Una implementación
 * hace exactamente las consultas del plugin @capgo/capacitor-health 8.9.3 de su plataforma.
 *
 * Las funciones que fallan tiran una excepción (idealmente [ErrorFuenteSalud], con el texto que va al diagnóstico).
 */
interface FuenteSalud {
    /** Decide qué tipos se piden, la fuente que se graba y la métrica de HRV. */
    val plataforma: PlataformaSalud

    /** La versión mayor de iOS (`iosMajor()`): decide qué tipos se pueden pedir en un iPhone. En Android no cuenta. */
    val iosMayor: Int get() = 0

    /** `isAvailable`. */
    suspend fun disponible(): Boolean

    /** `requestAuthorization({read, write: []})`. Nunca escritura. Tira si un tipo no existe en este sistema. */
    suspend fun pedirLectura(tipos: List<String>)

    /**
     * `requestAuthorization({read, write: [], requestHistoryAccess: true})`, la tanda del núcleo en Android: como
     * [pedirLectura] y además el permiso de historial (READ_HEALTH_DATA_HISTORY) si este Health Connect lo tiene. Devuelve
     * su veredicto; null donde no existe (HealthKit da todo el historial con el permiso normal).
     */
    suspend fun pedirLecturaConHistorial(tipos: List<String>): HistorialSalud? {
        pedirLectura(tipos)
        return null
    }

    /** `checkAuthorization`: qué tipos ya se preguntaron. HealthKit NUNCA dice si hay permiso de lectura. */
    suspend fun permisos(tipos: List<String>): PermisosSalud

    /**
     * `checkAuthorization({read: NUCLEO, requestHistoryAccess: true})`: el veredicto del historial SIN abrir la hoja (el
     * cliente lo pudo habilitar después desde Health Connect). null donde no existe; tira si no se puede preguntar.
     */
    suspend fun historial(): HistorialSalud? = null

    /** `queryAggregated(bucket: 'day')`: baldes anclados a la medianoche local, solo los que tienen valor. */
    suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario>

    /** `readSamples(limit, ascending: true)`: la muestra entra si se solapa con la ventana. */
    suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud>

    /** `queryWorkouts({startDate, endDate})`: límite 100, del más nuevo al más viejo. */
    suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo>
}

data class PermisosSalud(
    /** Los tipos ya preguntados (le haya dicho el cliente que sí o que no). */
    val preguntados: List<String>,
    /** Los que falta preguntar (o que este sistema no tiene). */
    val pendientes: List<String>,
)

/**
 * El permiso de historial de Health Connect (`historyAccessAuthorized` / `historyAccessAvailable` del plugin). Sin él,
 * Health Connect no da nada anterior a 30 días, y no avisa: devuelve vacío. [disponible] separa "el cliente lo negó" de
 * "este Health Connect es viejo y no lo conoce" (en ese caso [autorizado] es false sí o sí).
 */
data class HistorialSalud(val autorizado: Boolean, val disponible: Boolean)

/** Un error de la fuente con el texto que da el plugin (va al diagnóstico). */
class ErrorFuenteSalud(val mensaje: String) : Exception(mensaje) {
    override fun toString(): String = mensaje
}

/** El texto de un error de la fuente, como lo escribe iOS con `"\(error)"`. */
internal fun textoError(e: Throwable): String = (e as? ErrorFuenteSalud)?.mensaje ?: e.message ?: e.toString()

// MARK: Estado local (las claves `mypump_health_*` de la web)

/**
 * Dónde vive el estado del sincronizador: las [Preferencias] de la app (como `UserDefaults` en iOS), con las mismas claves
 * y el mismo formato que el localStorage de la web, así la migración del almacenamiento viejo lo copia tal cual
 * (NATIVA_CONTRATO §9). En la app cada cuenta tiene las suyas, con su huella al final ([AlmacenSaludPorCuenta]).
 */
object ClaveSalud {
    const val CONECTADO = "mypump_health_connected"        // "1"
    const val ULTIMA_SYNC = "mypump_health_last_sync"      // ISO de JS
    const val DENEGADO = "mypump_health_denegado"          // "1": la sospecha de "no llega nada"
    const val RACHA_VACIA = "mypump_health_racha_vacia"    // sincronizaciones vacías seguidas
    const val HISTORIAL_HECHO = "mypump_health_backfill_v1" // "1"
    const val CURSOR = "mypump_health_backfill_off"        // {"off":20,"alcance":60} o "20" (formato viejo)
    const val INTENTO = "mypump_health_backfill_intento"   // ms del último reintento sin avance
    const val DIAG = "mypump_health_diag"                  // último intento de conectar (JSON)
    const val HISTORIAL_OK = "mypump_health_historial_ok"  // "1" | "0": el permiso de historial de Health Connect
    val todas: List<String> = listOf(CONECTADO, ULTIMA_SYNC, DENEGADO, RACHA_VACIA, HISTORIAL_HECHO, CURSOR, INTENTO, DIAG, HISTORIAL_OK)
}

/**
 * El estado de Salud de UNA cuenta (revisión del 15-oct, hallazgo 3; gemelo de `AlmacenSaludPorCuenta` de iOS). Era del
 * teléfono, como el localStorage de la web: con el link de otra cuenta en el mismo teléfono (Mati mirando la de un
 * cliente), "conectado" seguía en pie y los pasos, el sueño y los entrenos de una persona subían a la ficha de otra. Ahora
 * cada cuenta tiene sus claves (`<clave>_<huella>`, con [Disco.huella]). La primera que usa Salud en el teléfono se queda
 * con lo que ya estaba (lo que trajo la migración de la app vieja o guardó una versión anterior); las demás arrancan sin
 * conectar y se conectan solo si alguien lo pide desde esa cuenta.
 */
class AlmacenSaludPorCuenta(private val base: Preferencias, cuenta: String) : Preferencias {
    private val sufijo = "_$cuenta"

    init {
        if (base.leer(DUENIA) == null) {
            base.guardar(DUENIA, cuenta)
            for (c in ClaveSalud.todas) {
                if (base.leer(c + sufijo) == null) base.leer(c)?.let { base.guardar(c + sufijo, it) }
            }
        }
    }

    override fun leer(clave: String): String? = base.leer(clave + sufijo)

    override fun guardar(clave: String, valor: String?) = base.guardar(clave + sufijo, valor)

    companion object {
        /** La huella de la cuenta que se quedó con el estado que había sin cuenta. */
        const val DUENIA = "mypump_health_cuenta"
    }
}

// MARK: Resultados

/** `sync()`: `ok` es "corrí", no "se guardó". `errorIngesta` dice si el servidor rechazó lotes (sin él, 0 ingresados es
 *  indistinguible de "no había nada nuevo"). */
data class ResultadoSync(val ok: Boolean, val motivo: String?, val ingresados: Int, val entrenos: Int, val errorIngesta: String?)

/** `backfill()`. */
data class ResultadoHistorial(
    val ok: Boolean,
    val saltado: Boolean,
    val ingresados: Int,
    val ventanasFallidas: Int,
    /** El veredicto "no llegó NADA", mirado al terminar (con los 60 días ya consultados). */
    val sinDatos: Boolean,
)

/** `connect()`. El historial sigue de fondo: [historial] es su tarea (la web devuelve la promesa). */
class ResultadoConexion(
    val ok: Boolean,
    /** no_disponible | error_nativo */
    val motivo: String?,
    val detalle: String?,
    val preguntados: Int?,
    val total: Int,
    val sinDatos: Boolean,
    /** (tipo, error) de los tipos que el sistema rechazó de a uno. */
    val rechazados: List<Pair<String, String>>,
    val historial: Deferred<ResultadoHistorial>?,
)

/** `estado()`: lo que muestra la sección de Salud de Mis datos. */
data class EstadoSalud(
    val disponible: Boolean,
    val conectado: Boolean,
    /** "No está llegando ningún dato" (deducido: el sistema no informa el permiso de lectura). */
    val sinDatos: Boolean,
    /** Tipos ya preguntados, NO "permisos dados". */
    val preguntados: Int?,
    val total: Int,
    val pendientes: List<String>,
    val errorEstado: String?,
    val ultimaSync: String?,
    val ios: Int,
)

/** `diagnostico()`: qué trajo cada tipo y el error textual del que falló (la pantalla de 5 toques). */
data class DiagnosticoSalud(
    val disponible: Boolean,
    val conToken: Boolean,
    val errorIngesta: String?,
    val tipos: List<Tipo>,
    val noches: List<NocheFuente>,
    val errores: List<String>,
) {
    data class Tipo(val tipo: String, val dataType: String, val via: String, val n: Int, val primero: String?, val ultimo: String?, val error: String?)

    /** fuente → estado → minutos */
    data class NocheFuente(val fecha: String, val fuentes: Map<String, Map<String, Long>>)
}

// MARK: Recolección de una ventana (recolectar + recolectarEntrenos)

/**
 * Las consultas del bridge para una ventana y su agregación, en el mismo orden: los tres agregados, las muestras de cada
 * tipo, el sueño (desde el mediodía anterior) y la HRV; los entrenos aparte, con la FC del entreno.
 */
class RecolectorSalud(val fuente: FuenteSalud, val reloj: RelojLocal) {
    private val plataforma: PlataformaSalud get() = fuente.plataforma

    /** Errores de lectura (el `__MYPUMP_DIAG` de la web): solo se juntan para el diagnóstico. */
    class Errores {
        private val lista = ArrayList<String>()

        @Synchronized internal fun anotar(dataType: String, e: Throwable) {
            lista += "$dataType: ${textoError(e)}"
        }

        val todos: List<String> @Synchronized get() = lista.toList()
    }

    /**
     * `leerMuestras`: si vuelven exactamente `limite`, quedaron más afuera: se parte la ventana al medio (hasta 4 veces y
     * si dura más de una hora) y se pegan las mitades sin repetir la muestra que cruza el corte.
     */
    suspend fun leer(dataType: String, desde: Double, hasta: Double, profundidad: Int = 0, errores: Errores? = null): List<MuestraSalud> {
        val arr = try {
            fuente.muestras(dataType, desde, hasta, PuenteSalud.LIMITE_MUESTRAS)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errores?.anotar(dataType, e)
            return emptyList()
        }
        if (arr.size >= PuenteSalud.LIMITE_MUESTRAS && profundidad < 4 && hasta - desde > 3_600_000) {
            val medio = Math.floor((desde + hasta) / 2)
            val a = leer(dataType, desde, medio, profundidad + 1, errores)
            val b = leer(dataType, medio, hasta, profundidad + 1, errores)
            return AgregacionSalud.sinRepetidas(a, b)
        }
        return arr
    }

    /** `recolectar(desde, hasta)`. */
    suspend fun recolectar(desde: Double, hasta: Double, errores: Errores? = null): List<RegistroSalud> {
        val registros = ArrayList<RegistroSalud>()
        for (a in PuenteSalud.agregados) {
            try {
                val baldes = fuente.agregado(a.dataType, a.agregacion, desde, hasta)
                registros += AgregacionSalud.agregados(baldes, a.tipo, reloj, plataforma)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errores?.anotar(a.dataType, e)
            }
        }
        for (m in PuenteSalud.muestras) {
            if (!PuenteSalud.soportado(m, plataforma, fuente.iosMayor)) continue
            val ms = leer(m.dataType, desde, hasta, errores = errores)
            registros += AgregacionSalud.muestras(ms, m, reloj, plataforma)
        }
        // El sueño se pide desde el mediodía anterior: la noche que se imputa al día del borde empezó la tarde de antes.
        // La del día anterior a la ventana queda partida y se descarta (fecha < corte) en vez de subirse a medias.
        val msSueno = leer("sleep", reloj.mediodiaDelDiaAnterior(desde), hasta, errores = errores)
        val sueno = AgregacionSalud.procesarSueno(msSueno, reloj, plataforma)
        val corte = reloj.ymd(desde)
        registros += sueno.filas.filter { it.fecha >= corte }
        val noches = sueno.noches.filter { it.fecha >= corte }
        val msHrv = leer("heartRateVariability", desde, hasta, errores = errores)
        registros += AgregacionSalud.procesarHRV(msHrv, noches, reloj, plataforma)
        return registros
    }

    /** `recolectarEntrenos(desde, hasta)`. Si la consulta falla, no hay entrenos (la web hace lo mismo). */
    suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoSalud> {
        val ws = try {
            fuente.entrenos(desde, hasta)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return emptyList()
        }
        val fc = if (ws.isEmpty()) emptyList() else leer("heartRate", desde, hasta)
        return AgregacionSalud.entrenos(ws, fc, plataforma)
    }
}

// MARK: Mi reloj (Oura, WHOOP)

/**
 * `GET /api/wearables/disponibles`, sin auth: los proveedores con credenciales cargadas en el servidor. null si no se pudo
 * preguntar (sin red: no se muestra nada, es el fallo seguro).
 */
suspend fun ClienteRpc.relojesDisponibles(): List<String>? = withContext(Dispatchers.Default) {
    val pedido = Pedido(url = "${config.app}/api/wearables/disponibles", metodo = "GET", cabeceras = emptyMap(), cuerpo = null, esperaMs = 20_000)
    val r = try {
        transporte.enviar(pedido)
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        return@withContext null
    }
    if (r.status !in 200..299) return@withContext null
    try {
        ProveedoresDisponibles.desde(Json.parseToJsonElement(r.cuerpo.toString(Charsets.UTF_8))).proveedores.map { it.id }
    } catch (_: Exception) {
        null
    }
}

/**
 * `…/api/wearables/iniciar?t=<TOKEN>&proveedor=…`: redirige al OAuth del proveedor. Se abre en una Custom Tab porque el
 * token viaja en la query (nunca en un WebView propio).
 */
fun ClienteRpc.urlConectarReloj(token: String, proveedor: String): String {
    // `encode(String, Charset)` es de Android 13: con el nombre del charset anda en todas (api-android.py lo vigila).
    fun q(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
    return "${config.app}/api/wearables/iniciar?t=${q(token)}&proveedor=${q(proveedor)}"
}
