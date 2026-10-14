package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Una escritura pendiente. Mismo formato que la cola de la web (`mypump_outbox_<TOKEN>`: `_id`, `kind`, `payload`,
 * `dedupeKey`, `tries`, `ts`), así las ops que trae la migración del almacenamiento viejo entran tal cual.
 */
data class Operacion(
    val id: String,
    val kind: String,
    val payload: ValorJson,
    val dedupeKey: String?,
    val tries: Int = 0,
    /** ms desde 1970, como `Date.now()`. */
    val ts: Double,
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("_id", ValorJson.Texto(id))
            put("kind", ValorJson.Texto(kind))
            put("payload", payload)
            dedupeKey?.let { put("dedupeKey", ValorJson.Texto(it)) }
            put("tries", ValorJson.Numero(tries.toDouble()))
            put("ts", ValorJson.Numero(ts))
        },
    )

    companion object {
        /**
         * Una op guardada (por esta app o por la web). La v1.0.2 de la web no ponía `_id`: se arma uno con el `ts`
         * para que la op no se pierda al migrar.
         */
        fun desde(e: JsonElement): Operacion? {
            val o = ValorJson.desde(e) as? ValorJson.Objeto ?: return null
            val kind = o["kind"]?.comoTexto ?: return null
            val ts = o["ts"]?.comoNumero ?: 0.0
            return Operacion(
                id = o["_id"]?.comoTexto ?: "legado_${ts.toLong()}_$kind",
                kind = kind,
                payload = o["payload"] ?: ValorJson.Nulo,
                dedupeKey = o["dedupeKey"]?.comoTexto,
                tries = o["tries"]?.comoNumero?.toInt() ?: 0,
                ts = ts,
            )
        }
    }
}

/** El aviso de guardado que ve el cliente (el toast de la web, `showSaveState`). */
enum class EstadoGuardado {
    QUIETO,

    /** Solo si el envío tarda más de 900 ms. */
    GUARDANDO,

    /** Solo después de un problema: reasegura. */
    GUARDADO,

    /** "Se reintenta solo". */
    SIN_CONEXION,

    /** Algo se abandonó: "revisá y cargalo de nuevo" (9 s). */
    PERDIDO,
}

/** Qué pasó al ejecutar una op. El ejecutor (la app) llama a la RPC y devuelve la respuesta cruda. */
sealed interface ResultadoOp {
    data class Respuesta(val resultado: Resultado<ValorJson>) : ResultadoOp

    /** El token del cliente cayó: la op se estaciona sin gastar intentos (arreglo nativo n.º 3 de la paridad). */
    data object TokenCaido : ResultadoOp
}

/**
 * La cola de escrituras: la misma semántica que el Outbox de la web (cliente.html:2687-2968) y que Outbox.swift, con
 * cuatro arreglos a propósito: el dedupe con semana lo arma quien encola; un kind desconocido o una op abandonada van a
 * FALLIDOS (no se pierden); un token caído estaciona; el chat lo maneja la app con "en vuelo".
 *
 * Reglas que se conservan tal cual:
 * - Encolar borra las pendientes con el mismo `dedupeKey` (gana la última) y agrega al final.
 * - Se procesa una COPIA de la cola: lo encolado durante el vuelo no se pierde.
 * - `null`, `0` y `[]` cuentan como NO guardado (la base rechaza devolviendo vacío).
 * - Red y transitorio cortan la pasada sin gastar intento; cualquier otro fallo suma uno; con 8, se abandona.
 * - Backoff `min(30 s, 2 s × max(1, intentos de la primera, racha sin red))`.
 * - [drenar] comparte la pasada en curso: esperarla es esperar el envío de verdad (cerrar el día depende de eso).
 *
 * Como el actor de Swift: todo el estado se toca en un despachador de a un hilo por vez, y mientras una op espera la
 * red pueden entrar otras llamadas (encolar, por ejemplo).
 */
class Outbox(
    private val archivo: File?,
    val maxIntentos: Int = 8,
    /** En los tests se apaga el reintento automático para forzar las pasadas a mano, como `await Outbox.flush()`. */
    private val reintentoAutomatico: Boolean = true,
    private val alcance: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    private var ejecutor: suspend (Operacion) -> ResultadoOp,
) {
    data class Fallido(val op: Operacion, val motivo: String, val cuando: Double)

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    private val confinado: CoroutineDispatcher = Dispatchers.Default.limitedParallelism(1)

    private val ops = mutableListOf<Operacion>()
    private val fallidosLista = mutableListOf<Fallido>()
    private var enVuelo: Deferred<Unit>? = null
    private var temporizador: Job? = null
    private var huboProblema = false

    /** La última pasada dejó algo sin guardar (sin red, transitorio, rechazo o token caído). */
    private var ultimaFallo = false
    private var rachaSinRed = 0
    private var secuencia = 0
    private var alCambiar: ((EstadoGuardado) -> Unit)? = null
    private var alAbandonar: ((List<Operacion>) -> Unit)? = null

    /**
     * La soltó el modelo (salir, otra cuenta, la demo). En Swift el temporizador tiene una referencia débil y muere con
     * la cola; acá el alcance la sostiene, así que se le avisa: la pasada en curso termina, pero no se programa otra.
     */
    @Volatile private var cerrada = false

    init {
        archivo?.let(::leerJson)?.let { j ->
            val o = j as? JsonObject
            (o?.get("ops") as? JsonArray)?.mapNotNullTo(ops) { Operacion.desde(it) }
            (o?.get("fallidos") as? JsonArray)?.mapNotNullTo(fallidosLista) { f ->
                val fo = f as? JsonObject ?: return@mapNotNullTo null
                val op = fo["op"]?.let { Operacion.desde(it) } ?: return@mapNotNullTo null
                Fallido(op, (fo["motivo"] as? JsonPrimitive)?.content ?: "", (fo["cuando"] as? JsonPrimitive)?.content?.toDoubleOrNull() ?: 0.0)
            }
        }
    }

    suspend fun observar(estado: (EstadoGuardado) -> Unit, abandonadas: (List<Operacion>) -> Unit) = withContext(confinado) {
        alCambiar = estado
        alAbandonar = abandonadas
    }

    suspend fun cambiarEjecutor(e: suspend (Operacion) -> ResultadoOp) = withContext(confinado) { ejecutor = e }

    suspend fun pendientes(): Int = withContext(confinado) { ops.size }

    suspend fun operaciones(): List<Operacion> = withContext(confinado) { ops.toList() }

    suspend fun fallidos(): List<Fallido> = withContext(confinado) { fallidosLista.toList() }

    /** Lo pendiente con su payload, por `dedupeKey`: lo que se pinta encima de lo que trae el servidor. */
    suspend fun pendientesPorClave(): Map<String, Operacion> = withContext(confinado) {
        val m = LinkedHashMap<String, Operacion>()
        for (op in ops) op.dedupeKey?.let { m[it] = op }
        m
    }

    suspend fun encolar(kind: String, payload: ValorJson, dedupeKey: String?): Operacion = withContext(confinado) {
        if (dedupeKey != null) ops.removeAll { it.dedupeKey == dedupeKey }
        secuencia += 1
        val ahora = System.currentTimeMillis().toDouble()
        val op = Operacion(id = "${ahora.toLong()}_$secuencia", kind = kind, payload = payload, dedupeKey = dedupeKey, ts = ahora)
        ops += op
        guardar()
        programar(0)
        op
    }

    /** Mete ops que ya existían (la migración del almacenamiento viejo), sin ejecutar, respetando el orden. */
    suspend fun importar(viejas: List<Operacion>) = withContext(confinado) {
        for (op in viejas) {
            if (ops.any { it.id == op.id }) continue
            if (op.dedupeKey != null) ops.removeAll { it.dedupeKey == op.dedupeKey }
            ops += op
        }
        guardar()
    }

    /**
     * `importar` para la migración del almacenamiento viejo, con una regla más: lo pendiente MÁS NUEVO gana. Una op vieja
     * no pisa a una nativa posterior con la misma `dedupeKey` (pasa si el cliente usó la nativa, volvió a la app vieja y
     * vuelve). Devuelve las que quedaron en la cola, en orden (también las que ya estaban por id).
     */
    suspend fun importarSinPisar(nuevas: List<Operacion>): List<Operacion> = withContext(confinado) {
        val quedaron = mutableListOf<Operacion>()
        for (op in nuevas) {
            if (ops.any { it.id == op.id }) {
                quedaron += op
                continue
            }
            val k = op.dedupeKey
            if (k != null && (ops.lastOrNull { it.dedupeKey == k }?.ts ?: Double.NEGATIVE_INFINITY) > op.ts) continue
            if (k != null) ops.removeAll { it.dedupeKey == k }
            ops += op
            quedaron += op
        }
        guardar()
        quedaron
    }

    /**
     * Ops que no se mandan pero tampoco se pueden perder: quedan en fallidos con su motivo, como una abandonada. La
     * migración manda acá las ops viejas sin sesión que no pasan la validación contra la rutina activa ("para revisar").
     */
    suspend fun archivarEnFallidos(viejas: List<Operacion>, motivo: String) = withContext(confinado) {
        val ahora = System.currentTimeMillis().toDouble()
        for (op in viejas) {
            if (fallidosLista.any { it.op.id == op.id }) continue
            ops.removeAll { it.id == op.id }
            fallidosLista += Fallido(op, motivo, ahora)
        }
        guardar()
    }

    /**
     * Vacía la cola: pasadas hasta que no quede nada o hasta que una falle (sin red, el servidor mal, un rechazo). Si ya
     * hay una pasada en curso, la espera y sigue con lo que se encoló mientras tanto: así "cerrar el día" espera el envío
     * de TODO lo anterior.
     */
    suspend fun drenar() {
        repeat(6) {
            val pasada = withContext(confinado) {
                // `enVuelo` lo suelta la misma pasada al terminar, ANTES de programar la siguiente: si lo soltara quien la
                // creó (después de esperarla), el temporizador podía encontrarla "en vuelo" ya terminada, esperarla y
                // volver sin pasada, con lo encolado durante el vuelo trabado (lo encontró la revisión de Swift: 15 de 200).
                enVuelo ?: alcance.async(confinado) {
                    try {
                        pasada()
                    } finally {
                        enVuelo = null
                    }
                }.also { enVuelo = it }
            }
            pasada.await()
            if (withContext(confinado) { ops.isEmpty() || ultimaFallo }) return
        }
    }

    /** El modelo suelta esta cola: lo pendiente queda en el archivo de la cuenta y sale cuando vuelva a entrar. */
    fun cerrar() {
        cerrada = true
        alcance.launch(confinado) {
            temporizador?.cancel()
            temporizador = null
        }
    }

    private fun programar(demoraMs: Long) {
        if (!reintentoAutomatico || cerrada || temporizador != null) return
        temporizador = alcance.launch(confinado) {
            delay(demoraMs)
            temporizador = null
            if (!cerrada) drenar()
        }
    }

    private suspend fun pasada() {
        ultimaFallo = false
        if (ops.isEmpty()) return
        val tanda = ops.toList()
        val resueltas = HashSet<String>()
        val abandonadas = mutableListOf<Operacion>()
        var algunaFallo = false
        // "Guardando…" solo si tarda (y nunca después de terminar: cancelado, el delay corta).
        val lenta = alcance.launch(confinado) {
            delay(900)
            avisar(EstadoGuardado.GUARDANDO)
        }

        for (op in tanda) {
            val resultado = try {
                ejecutor(op)
            } catch (e: CancellationException) {
                lenta.cancel()
                throw e
            } catch (_: IOException) {
                algunaFallo = true      // un throw de red: no gasta intento
                rachaSinRed += 1
                break
            } catch (e: Exception) {
                // Un bug nuestro no es un corte de red: gasta intento y no congela a las de atrás.
                if (registrarFallo(op, "excepción: $e", resueltas, abandonadas)) algunaFallo = true
                continue
            }
            if (resultado is ResultadoOp.TokenCaido) {
                algunaFallo = true
                rachaSinRed += 1
                break                   // no tiene sentido seguir con las demás
            }
            val r = (resultado as ResultadoOp.Respuesta).resultado
            if (r is Resultado.Ok && seGuardo(r.valor)) {
                resueltas += op.id
                continue
            }
            val error = r.errorONull()
            if (error != null && error.clase != ErrorRpc.Clase.PERMANENTE) {
                algunaFallo = true
                rachaSinRed += 1
                break                   // red o transitorio: no tiene sentido seguir con las demás
            }
            if (error?.codigo == "KIND_DESCONOCIDO") {
                abandonadas += op
                resueltas += op.id
                continue
            }
            val motivo = if (error != null) "${error.codigo ?: error.status}: ${error.mensaje}" else "la base devolvió vacío"
            if (registrarFallo(op, motivo, resueltas, abandonadas)) algunaFallo = true
        }
        lenta.cancel()

        if (resueltas.isNotEmpty()) {
            ops.removeAll { it.id in resueltas }
            rachaSinRed = 0
        }
        if (abandonadas.isNotEmpty()) {
            val ahora = System.currentTimeMillis().toDouble()
            abandonadas.mapTo(fallidosLista) { Fallido(it, "abandonada tras ${it.tries} intentos", ahora) }
        }
        guardar()

        if (abandonadas.isNotEmpty()) {
            alAbandonar?.invoke(abandonadas.toList())
            huboProblema = false
            avisar(EstadoGuardado.PERDIDO)
        }
        ultimaFallo = algunaFallo
        if (algunaFallo) {
            huboProblema = true
            if (abandonadas.isEmpty()) avisar(EstadoGuardado.SIN_CONEXION)
            val base = maxOf(1, ops.firstOrNull()?.tries ?: 1, rachaSinRed)
            programar(minOf(30_000L, 2_000L * base))
        } else if (huboProblema) {
            huboProblema = false
            avisar(EstadoGuardado.GUARDADO)
        } else if (abandonadas.isEmpty()) {
            avisar(EstadoGuardado.QUIETO)
        }
        // Lo encolado DURANTE esta pasada quedó sin procesar: otra vuelta.
        if (ops.isNotEmpty() && !algunaFallo) programar(0)
    }

    /** Suma un intento a la op (en la cola real, no en la copia). Devuelve true si sigue pendiente. */
    private fun registrarFallo(op: Operacion, motivo: String, resueltas: MutableSet<String>, abandonadas: MutableList<Operacion>): Boolean {
        val i = ops.indexOfFirst { it.id == op.id }
        if (i < 0) return false
        val nueva = ops[i].copy(tries = ops[i].tries + 1)
        ops[i] = nueva
        if (nueva.tries >= maxIntentos) {
            resueltas += op.id
            abandonadas += nueva
            return false
        }
        return true
    }

    private fun avisar(e: EstadoGuardado) {
        alCambiar?.invoke(e)
    }

    private fun guardar() {
        val f = archivo ?: return
        // Sin disco no hay mucho que hacer; la op sigue en memoria y se reintenta.
        val json = ValorJson.objeto(
            "ops" to ValorJson.Lista(ops.map { it.aValor() }),
            "fallidos" to ValorJson.Lista(
                fallidosLista.map {
                    ValorJson.objeto("op" to it.op.aValor(), "motivo" to ValorJson.Texto(it.motivo), "cuando" to ValorJson.Numero(it.cuando))
                },
            ),
        )
        escribirAtomico(f, json.serializar())
    }

    companion object {
        /** `seGuardo` de la web: null, 0 y [] son "no se guardó". `false` SÍ cuenta (desmarcar algo que no estaba). */
        fun seGuardo(v: ValorJson): Boolean = when (v) {
            ValorJson.Nulo -> false
            is ValorJson.Numero -> v.valor != 0.0
            is ValorJson.Lista -> v.elementos.isNotEmpty()
            else -> true
        }
    }
}
