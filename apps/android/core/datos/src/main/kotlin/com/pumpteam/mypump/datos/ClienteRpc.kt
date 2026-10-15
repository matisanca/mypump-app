package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.modelos.listaEstricta
import java.util.Base64
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/** A dónde va la app: el backend de Supabase, el servicio de visión de la Mini y el sitio. */
data class ConfigBackend(val supabase: String, val anonKey: String, val vision: String, val app: String) {
    companion object
}

/** Lo que devuelve una llamada al backend: el valor, o el error ya clasificado (`Result<_, ErrorRPC>` de iOS). */
sealed interface Resultado<out T> {
    data class Ok<T>(val valor: T) : Resultado<T>

    data class Falla(val error: ErrorRpc) : Resultado<Nothing>

    fun valorONull(): T? = (this as? Ok<T>)?.valor

    fun errorONull(): ErrorRpc? = (this as? Falla)?.error
}

inline fun <T, R> Resultado<T>.map(f: (T) -> R): Resultado<R> = when (this) {
    is Resultado.Ok -> Resultado.Ok(f(valor))
    is Resultado.Falla -> this
}

/**
 * Cliente propio y fino de PostgREST: `POST /rest/v1/rpc/<fn>` con la anon key, igual que la web (y que ClienteRPC.swift).
 * Devuelve el JSON tal cual (un `null`, un `[]`, un `0` o un `false` son respuestas válidas: con un token revocado la base
 * contesta 200 vacío, no un error) o un [ErrorRpc] clasificado.
 *
 * Arma el pedido y lee la respuesta fuera del hilo de quien llama (en iOS, `ClienteRPC` no es del hilo principal): el
 * modelo lo usa desde el principal y una dieta grande no puede trabar la pantalla mientras se decodifica.
 */
class ClienteRpc(
    val config: ConfigBackend = ConfigBackend.produccion,
    internal val transporte: Transporte = TransporteOkHttp(),
    private val esperaMs: Long = 20_000,
) {
    /** Los tipos de foto que lee mini-vision. */
    enum class TipoVision(val valor: String) { ETIQUETA("etiqueta"), PLATO("plato") }

    suspend fun llamar(funcion: String, parametros: Map<String, ValorJson>): Resultado<ValorJson> = withContext(Dispatchers.Default) {
        val pedido = Pedido(
            url = "${config.supabase}/rest/v1/rpc/$funcion",
            metodo = "POST",
            cabeceras = mapOf(
                "apikey" to config.anonKey,
                "Authorization" to "Bearer ${config.anonKey}",
                "Content-Type" to "application/json",
            ),
            cuerpo = ValorJson.Objeto(parametros).serializar().toByteArray(),
            esperaMs = esperaMs,
        )
        enviar(pedido)
    }

    /** Lectura directa de una tabla pública (el catálogo de ejercicios). */
    suspend fun tabla(nombre: String, columnas: String): Resultado<ValorJson> = withContext(Dispatchers.Default) {
        val pedido = Pedido(
            url = "${config.supabase}/rest/v1/$nombre?select=${java.net.URLEncoder.encode(columnas, "UTF-8").replace("+", "%20")}",
            metodo = "GET",
            cabeceras = mapOf("apikey" to config.anonKey, "Authorization" to "Bearer ${config.anonKey}"),
            cuerpo = null,
            esperaMs = esperaMs,
        )
        enviar(pedido)
    }

    /**
     * `visionDesdeFoto` de la web: `POST <vision>/vision` con `{token, tipo, imagen_base64}` (el token va en el cuerpo, no
     * hay cabecera de auth). Devuelve `data` o un error con el texto que mandó el servicio (`error`), para el aviso "No
     * pudimos leer la foto (…)". La IA tarda ~30 s: se espera hasta 150.
     */
    suspend fun vision(token: String, tipo: TipoVision, jpeg: ByteArray): Resultado<ValorJson> = withContext(Dispatchers.Default) {
        val cuerpo = ValorJson.objeto(
            "token" to texto(token), "tipo" to texto(tipo.valor),
            "imagen_base64" to texto("data:image/jpeg;base64," + Base64.getEncoder().encodeToString(jpeg)),
        )
        val pedido = Pedido(
            url = "${config.vision}/vision", metodo = "POST", cabeceras = mapOf("Content-Type" to "application/json"),
            cuerpo = cuerpo.serializar().toByteArray(), esperaMs = 150_000,
        )
        val r = try {
            transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return@withContext Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin conexión"))
        }
        val j = parsear(r.cuerpo.toString(Charsets.UTF_8))
        val data = j?.get("data")
        if (r.status in 200..299 && j?.get("ok") == ValorJson.Booleano(true) && data != null) return@withContext Resultado.Ok(data)
        val clase = when {
            r.status == 429 || r.status == 408 || r.status >= 500 -> ErrorRpc.Clase.TRANSITORIO
            j == null -> ErrorRpc.Clase.RED
            else -> ErrorRpc.Clase.PERMANENTE
        }
        Resultado.Falla(ErrorRpc(clase, r.status, mensaje = j?.get("error")?.comoTexto ?: "servicio no disponible"))
    }

    internal suspend fun enviar(pedido: Pedido): Resultado<ValorJson> {
        val r = try {
            transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Sin respuesta (sin señal, timeout, DNS): para la cola es falta de red y no gasta intento.
            return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = e.toString()))
        }
        val texto = r.cuerpo.toString(Charsets.UTF_8)
        if (r.status in 200..299) {
            if (r.cuerpo.isEmpty()) return Resultado.Ok(ValorJson.Nulo)
            // Un 200 con HTML es un portal cautivo (el wifi del gym): para la cola es falta de red.
            val json = parsear(texto) ?: return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, r.status, mensaje = "respuesta que no es JSON"))
            return Resultado.Ok(json)
        }
        val cuerpo = parsear(texto)
        val codigo = cuerpo?.get("code")?.comoTexto
        val mensaje = cuerpo?.get("message")?.comoTexto ?: r.cuerpo.copyOf(minOf(300, r.cuerpo.size)).toString(Charsets.UTF_8)
        return Resultado.Falla(ErrorRpc(ErrorRpc.claseDe(r.status), r.status, codigo, mensaje))
    }

    /**
     * Una respuesta de filas. Una forma inesperada es un error permanente (no se reintenta a ciegas); `null` es una
     * lista vacía.
     */
    suspend fun <T> filas(funcion: String, parametros: Map<String, ValorJson>, leer: (JsonElement) -> T): Resultado<List<T>> =
        when (val r = llamar(funcion, parametros)) {
            is Resultado.Falla -> r
            is Resultado.Ok -> if (r.valor == ValorJson.Nulo) {
                Resultado.Ok(emptyList())
            } else {
                withContext(Dispatchers.Default) {
                    try {
                        Resultado.Ok(listaEstricta(r.valor.aJson(), leer))
                    } catch (e: Exception) {
                        // Como el `catch` de iOS: cualquier forma inesperada (ErrorDecodificacion u otra) es un rechazo.
                        Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 200, "DECODE", "$funcion: ${e.message}"))
                    }
                }
            }
        }

    private fun parsear(texto: String): ValorJson? = try {
        ValorJson.desde(Json.parseToJsonElement(texto))
    } catch (_: Exception) {
        null
    }
}

/** Atajo para los parámetros de las RPC. */
internal fun texto(s: String): ValorJson = ValorJson.Texto(s)

internal fun numero(d: Double): ValorJson = ValorJson.Numero(d)

internal fun numero(i: Int): ValorJson = ValorJson.Numero(i.toDouble())
