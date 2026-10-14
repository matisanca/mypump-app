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
        // D7 con la `nativa_002` aplicada y el cliente sin decidir: la app tiene que preguntar antes del primer uso.
        respuestas["mypump_get_consentimiento_ia"] = """{"acepta":null}"""
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
