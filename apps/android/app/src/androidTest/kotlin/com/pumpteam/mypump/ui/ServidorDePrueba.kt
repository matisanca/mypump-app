package com.pumpteam.mypump.ui

import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.datos.Pedido
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.Transporte
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.delay

/**
 * El backend de las pruebas de interfaz: nunca toca la red. Contesta con las respuestas REALES grabadas de la cuenta
 * `test-nativa-real` (`apps/shared/fixtures`, que van en los assets del APK de pruebas), las mismas de los tests de :core y
 * de iOS, y anota cada llamada.
 *
 * Solo [TOKEN] es una cuenta: cualquier otro token recibe `[]` de `mypump_get_cliente_info`, que es lo que contesta la
 * base con un link revocado ("Este link ya no sirve").
 */
class ServidorDePrueba : Transporte {
    data class Llamada(val funcion: String, val cuerpo: String)

    val llamadas = CopyOnWriteArrayList<Llamada>()

    /** Sin señal: cada pedido tira una IOException (para la cola es falta de red, no un rechazo). */
    @Volatile var sinRed = false

    /** El servicio contesta 503 ("Servicio fuera de línea"). */
    @Volatile var caido = false

    /** Cuánto tarda cada respuesta (una red lenta). */
    @Volatile var demoraMs = 0L

    /** Respuestas propias por función (`mypump_get_chat` → `[…]`); ganan sobre las grabadas. */
    val respuestas = ConcurrentHashMap<String, String>()

    init {
        // Sin la tabla de la palanca remota: vale la de fábrica.
        respuestas["mypump_get_app_config"] = SIN_FUNCION
    }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val funcion = pedido.ruta.substringAfterLast('/')
        val cuerpo = pedido.cuerpo?.toString(Charsets.UTF_8) ?: ""
        llamadas += Llamada(funcion, cuerpo)
        if (demoraMs > 0) delay(demoraMs)
        if (sinRed) throw IOException("sin conexión (prueba)")
        if (caido) return Respuesta(503, """{"message":"servicio caído (prueba)"}""".toByteArray())
        // Revisión: las fotos de progreso y los relojes no son RPC (ver el bloque de Revisión, abajo).
        rutaDeRevision(pedido.ruta, cuerpo)?.let { return it }
        val token = Regex("\"p_token\":\"([^\"]*)\"").find(cuerpo)?.groupValues?.get(1)
        val propia = respuestas[funcion]
        val (status, texto) = when {
            propia == SIN_FUNCION -> 404 to """{"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.$funcion"}"""
            funcion == "mypump_get_cliente_info" && token != TOKEN -> 200 to "[]"
            propia != null -> 200 to propia
            funcion.startsWith("mypump_get_") -> 200 to (grabada(funcion.removePrefix("mypump_")) ?: "[]")
            // Las escrituras salen bien (la cola las da por guardadas).
            funcion.startsWith("mypump_") -> 200 to "true"
            // Tablas (el catálogo de ejercicios) y servicios aparte: vacío.
            else -> 200 to "[]"
        }
        return Respuesta(status, texto.toByteArray())
    }

    /** Las llamadas a una función, con su cuerpo (para ver qué se mandó). */
    fun a(funcion: String): List<String> = llamadas.filter { it.funcion == funcion }.map { it.cuerpo }

    // ── Revisión: las rutas que no son RPC ─────────────────────────────────────────────────────────────────────────
    // Las fotos de progreso van al servicio de la Mini (`/progreso/upload` y `/progreso/urls`) y los relojes se preguntan
    // al sitio (`/api/wearables/disponibles`). Antes todo lo que no era `mypump_*` contestaba `[]`. En `llamadas` quedan
    // con el último tramo de la ruta: `upload`, `urls` y `disponibles`.

    /** Lo que llegó a `/progreso/upload`. */
    data class FotoSubida(val pose: String, val fecha: String, val dataUrl: String)

    val fotosSubidas = CopyOnWriteArrayList<FotoSubida>()

    /** Las fotos de la cuenta (lunes de la semana → poses): las contestan `get_fotos_progreso` y `/progreso/urls`. */
    private val fotosDeLaCuenta = ConcurrentHashMap<String, MutableSet<String>>()

    /** Subir una foto se queda sin red (lo demás contesta): la cola de fotos la guarda y reintenta sin gastar intentos. */
    @Volatile var fotosSinRed = false

    /** Los relojes que el servidor tiene habilitados (`/api/wearables/disponibles`): ninguno, como sin credenciales. */
    @Volatile var relojes: List<String> = emptyList()

    /** La cuenta ya tiene estas fotos (lunes → poses), como si se hubieran subido antes. */
    fun ponerFotos(porSemana: Map<String, List<String>>) {
        for ((lunes, poses) in porSemana) fotosDeLaCuenta.getOrPut(lunes) { java.util.Collections.synchronizedSet(LinkedHashSet()) } += poses
        actualizarFotos()
    }

    /** Cuántas veces se pidieron las URLs firmadas. Cada firma da URLs distintas, como el servicio real. */
    @Volatile var firmas = 0

    /** La URL firmada de prueba de una foto (https, para que `ImagenRemota` la pida), la de la firma [firma]. */
    fun urlDeFoto(lunes: String, pose: String, firma: Int = firmas): String = "https://fotos.prueba.invalid/$lunes/$pose.jpg?firma=$firma"

    private fun actualizarFotos() {
        val filas = fotosDeLaCuenta.entries.sortedBy { it.key }.flatMap { (lunes, poses) ->
            poses.toList().map { """{"semana_lunes":"$lunes","pose":"$it","tomada_el":"$lunes","created_at":"${lunes}T12:00:00+00:00"}""" }
        }
        respuestas["mypump_get_fotos_progreso"] = filas.joinToString(",", "[", "]")
    }

    // Con los nombres enteros (sin tocar los imports de arriba, que comparten otras pantallas).
    private fun rutaDeRevision(ruta: String, cuerpo: String): Respuesta? = when (ruta) {
        "/progreso/upload" -> {
            if (fotosSinRed) throw IOException("sin conexión para las fotos (prueba)")
            val o = kotlinx.serialization.json.Json.parseToJsonElement(cuerpo) as kotlinx.serialization.json.JsonObject
            fun campo(k: String) = (o[k] as? kotlinx.serialization.json.JsonPrimitive)?.content ?: ""
            if (campo("token") != TOKEN) {
                Respuesta(401, """{"ok":false,"error":"token inválido"}""".toByteArray())
            } else {
                fotosSubidas += FotoSubida(campo("pose"), campo("fecha"), campo("imagen_base64"))
                ponerFotos(mapOf(com.pumpteam.mypump.reglas.FotosProgreso.lunes(campo("fecha")) to listOf(campo("pose"))))
                Respuesta(200, """{"ok":true}""".toByteArray())
            }
        }
        "/progreso/urls" -> {
            firmas += 1
            val fotos = fotosDeLaCuenta.entries.flatMap { (lunes, poses) ->
                poses.toList().map { """{"semana_lunes":"$lunes","pose":"$it","url":"${urlDeFoto(lunes, it)}"}""" }
            }
            Respuesta(200, """{"ok":true,"fotos":${fotos.joinToString(",", "[", "]")}}""".toByteArray())
        }
        "/api/wearables/disponibles" ->
            Respuesta(200, """{"proveedores":${relojes.joinToString(",", "[", "]") { """{"id":"$it","nombre":"$it"}""" }}}""".toByteArray())
        else -> null
    }

    companion object {
        /** El token de la cuenta de prueba de este servidor (inventado: no es de nadie). */
        const val TOKEN = "pruebaInterfazAndroid_0001"

        /** Para que una función conteste "no existe" (PGRST202). */
        const val SIN_FUNCION = "\u0000sin-funcion"

        private fun grabada(nombre: String): String? = try {
            InstrumentationRegistry.getInstrumentation().context.assets.open("test-nativa-real/$nombre.json").use {
                it.readBytes().toString(Charsets.UTF_8)
            }
        } catch (_: FileNotFoundException) {
            null
        }
    }
}
