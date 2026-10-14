package com.pumpteam.mypump.datos

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/** Un pedido HTTP, sin nada de OkHttp: así los tests usan dobles que contestan lo que contestó la API real. */
data class Pedido(
    val url: String,
    val metodo: String,
    val cabeceras: Map<String, String>,
    val cuerpo: ByteArray?,
    /** Tiempo máximo de la llamada entera (20 s las RPC, 150 s la visión, 90 s la subida de una foto). */
    val esperaMs: Long,
) {
    override fun equals(other: Any?): Boolean = other is Pedido && url == other.url && metodo == other.metodo &&
        cabeceras == other.cabeceras && (cuerpo?.contentEquals(other.cuerpo) ?: (other.cuerpo == null)) && esperaMs == other.esperaMs

    override fun hashCode(): Int = url.hashCode()

    /** La ruta, para los dobles que contestan según a dónde va el pedido. */
    val ruta: String get() = java.net.URI(url).path ?: ""
}

data class Respuesta(val status: Int, val cuerpo: ByteArray) {
    override fun equals(other: Any?): Boolean = other is Respuesta && status == other.status && cuerpo.contentEquals(other.cuerpo)

    override fun hashCode(): Int = status
}

/**
 * Lo que manda los bytes. En la app es OkHttp; en los tests, un doble. Sin respuesta (sin señal, timeout, DNS) tira una
 * `IOException`: para la cola es falta de red, no un rechazo.
 */
fun interface Transporte {
    suspend fun enviar(pedido: Pedido): Respuesta
}

/** El transporte de verdad. Un solo `OkHttpClient` para toda la app (comparte conexiones y el pool de hilos). */
class TransporteOkHttp(private val cliente: OkHttpClient = compartido) : Transporte {
    override suspend fun enviar(pedido: Pedido): Respuesta {
        val tipo = pedido.cabeceras["Content-Type"]?.toMediaTypeOrNull()
        val request = Request.Builder()
            .url(pedido.url)
            .apply { pedido.cabeceras.forEach { (k, v) -> header(k, v) } }
            .method(pedido.metodo, pedido.cuerpo?.toRequestBody(tipo))
            .build()
        val call = cliente.newCall(request)
        call.timeout().timeout(pedido.esperaMs, TimeUnit.MILLISECONDS)
        return call.esperar()
    }

    companion object {
        /** Sin timeouts propios: manda el de cada llamada (`esperaMs`). */
        val compartido: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(0, TimeUnit.MILLISECONDS)
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .writeTimeout(0, TimeUnit.MILLISECONDS)
                .build()
        }
    }
}

/** La llamada de OkHttp como suspensión: si se cancela la corrutina, se cancela el pedido. */
private suspend fun Call.esperar(): Respuesta = suspendCancellableCoroutine { cont ->
    cont.invokeOnCancellation { cancel() }
    enqueue(
        object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                cont.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                val r = try {
                    response.use { Respuesta(it.code, it.body.bytes()) }
                } catch (e: IOException) {
                    cont.resumeWithException(e)
                    return
                }
                cont.resume(r) { _, _, _ -> }
            }
        },
    )
}
