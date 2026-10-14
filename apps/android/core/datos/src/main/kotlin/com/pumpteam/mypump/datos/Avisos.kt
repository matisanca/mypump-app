package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.Json

/**
 * A dónde lleva tocar un aviso: el `destino` que mandan `push.py` (comentarios del coach) y la notificación local del
 * domingo. Uno desconocido, como el histórico `comentarios`, cae a Chat (NOT-03).
 */
enum class DestinoAviso {
    ENTRENO, DIETA, CHAT, REVISION, PROGRESO, MI_DIA, MIS_DATOS;

    companion object {
        fun deDestino(destino: String?): DestinoAviso = when (destino) {
            "train" -> ENTRENO
            "diet" -> DIETA
            "progress" -> PROGRESO
            "myday" -> MI_DIA
            "revision" -> REVISION
            "salud" -> MIS_DATOS
            else -> CHAT
        }

        /**
         * `?scene=<escena>` del link (ACC-09): solo una escena que existe; cualquier otra cosa no hace nada (en la web, una
         * escena inexistente dejaba la app en blanco).
         */
        fun deEscena(escena: String?): DestinoAviso? =
            if (escena in listOf("train", "diet", "chat", "revision", "progress", "salud", "myday")) deDestino(escena) else null
    }
}

/**
 * `mypump_notif_prefs` (notificaciones.js): un solo recordatorio, la revisión del domingo, apagable y con hora. Lo
 * guardado se mezcla sobre los valores por defecto campo por campo; claves viejas (entreno, peso, racha) se ignoran.
 */
data class PreferenciasAvisos(val check: Recordatorio) {
    data class Recordatorio(val on: Boolean, val hora: Int, val min: Int)

    val texto: String
        get() = ValorJson.objeto(
            "check" to ValorJson.objeto(
                "on" to ValorJson.Booleano(check.on), "hora" to numero(check.hora), "min" to numero(check.min),
            ),
        ).serializar()

    companion object {
        val porDefecto = PreferenciasAvisos(Recordatorio(on = true, hora = 11, min = 0))
        const val CLAVE = "mypump_notif_prefs"

        /**
         * Ids fijos de la Capacitor (`LocalNotifications`): reprogramar pisa en vez de duplicar. 1001, 1003 y 1004 ya no
         * existen pero siguen agendados en los teléfonos que abrieron la app antes de que se sacaran: se cancelan siempre.
         */
        const val ID_REVISION = "1002"
        val idsViejos = listOf("1001", "1003", "1004")

        fun leer(texto: String?): PreferenciasAvisos {
            val c = try {
                texto?.let { ValorJson.desde(Json.parseToJsonElement(it)) }?.get("check") as? ValorJson.Objeto
            } catch (_: Exception) {
                null
            } ?: return porDefecto
            var r = porDefecto.check
            (c["on"] as? ValorJson.Booleano)?.let { r = r.copy(on = it.valor) }
            // Una hora imposible (25, 9.5, un 1e20) deja la de siempre: el aviso nunca queda sin poder sonar (como iOS).
            c["hora"]?.comoNumero?.takeIf { it == Math.rint(it) && it in 0.0..23.0 }?.let { r = r.copy(hora = it.toInt()) }
            c["min"]?.comoNumero?.takeIf { it == Math.rint(it) && it in 0.0..59.0 }?.let { r = r.copy(min = it.toInt()) }
            return PreferenciasAvisos(r)
        }
    }
}

/**
 * El token de APNs como lo registraba la Capacitor en iOS: hex en MAYÚSCULAS (`mypump_push_devices.token` es UNIQUE como
 * texto). En Android el token de FCM ya es texto y va tal cual.
 */
object TokenPush {
    fun hex(d: ByteArray): String = d.joinToString("") { "%02X".format(it) }
}

/**
 * `registrarPush`: directo; solo si cambió desde el último que se mandó (`mypump_push_token`, la misma clave que la web).
 * Devuelve si quedó registrado.
 */
suspend fun ModeloApp.registrarPush(dispositivo: String, version: String?, plataforma: String = "android"): Boolean {
    val t = token ?: return false
    if (esDemo.value) return false
    if (preferencias.leer("mypump_push_token") == dispositivo) return true
    val r = cliente.llamar(
        "mypump_registrar_push",
        mapOf(
            "p_token" to texto(t), "p_device" to texto(dispositivo), "p_plataforma" to texto(plataforma),
            "p_app_version" to (version?.let { texto(it) } ?: ValorJson.Nulo),
        ),
    )
    if (r.valorONull() != ValorJson.Booleano(true)) return false
    preferencias.guardar("mypump_push_token", dispositivo)
    return true
}
