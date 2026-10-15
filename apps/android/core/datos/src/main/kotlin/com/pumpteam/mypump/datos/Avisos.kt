package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.TemporalAdjusters
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

        /** Los extras con que tocar un aviso abre la app: el `destino` (el de push.py y el de los locales)… */
        const val EXTRA_DESTINO = "destino"

        /** …la marca de los avisos que publica la app (el push con la app abierta, el domingo, el fin del descanso)… */
        const val EXTRA_AVISO = "mypump_aviso"

        /** …y lo que agrega FCM al tocar un push que mostró el sistema con la app en segundo plano. */
        const val EXTRA_FCM = "google.message_id"

        /**
         * A dónde lleva el toque según los extras con que se abrió la app ([claves] y el valor de [EXTRA_DESTINO]): null si
         * no vino de un aviso (el ícono, un link); uno sin `destino` o con uno desconocido va a Chat (NOT-03).
         */
        fun alTocar(claves: Set<String>, destino: String?): DestinoAviso? =
            if (EXTRA_AVISO in claves || EXTRA_FCM in claves) deDestino(destino) else null
    }
}

/**
 * El aviso del domingo (pedido de Mati, 14-oct): no se configura y llega como un mensaje suyo, con el título de sus
 * mensajes del chat ("Mati", mig 057) y su forma de escribirles a los clientes (sin dos puntos, guiones ni emojis).
 * Reusa el id 1002 de la Capacitor: reprogramar pisa el que dejó la app vieja. Gemelo de `AvisoDomingo` de iOS; en
 * Android lo agenda `avisos/CentroAvisos` de `:app` con [proximo].
 *
 * Es de UNA vez (revisión del 15-oct, hallazgo 8): repetido cada semana, a quien dejó la app o tiene el link vencido le
 * seguía llegando para siempre un "mensaje de Mati" pidiéndole la revisión. La app lo arma al entrar con la cuenta y cada
 * vez que vuelve a primer plano: a quien la usa le llega igual; a quien la dejó, como mucho uno más.
 */
object AvisoDomingo {
    const val ID = PreferenciasAvisos.ID_REVISION
    const val TITULO = "Mati"
    const val CUERPO = "Cómo venís esta semana? Subí tu revisión así te hago la devolución"
    const val DESTINO = "revision"

    /** Domingo a las 11:00, hora del teléfono: es cuando se arma la ronda de Mati (en iOS, el `weekday` 1). */
    val diaDeLaSemana: DayOfWeek = DayOfWeek.SUNDAY
    const val HORA = 11
    const val MINUTO = 0

    /**
     * Cuándo suena: el primer domingo a las 11:00 de [zona] estrictamente después de [ahora] (hoy, si es domingo antes de
     * las 11). La hora sale del reloj de ESE domingo: si en el medio cambia el horario de verano sigue siendo a las 11:00
     * del teléfono, y con otra zona (un viaje) da otro instante. Lo mismo que `AvisoDomingo.proximo` de iOS (el
     * `nextDate(after:)` con domingo, 11 y 0); allá el sistema lo sigue en la zona de ese momento, acá lo vuelve a armar
     * [pendiente] cuando cambian la zona o la hora.
     */
    fun proximo(ahora: Instant, zona: ZoneId): Instant {
        var dia = ahora.atZone(zona).toLocalDate().with(TemporalAdjusters.nextOrSame(diaDeLaSemana))
        while (true) {
            val t = en(dia, zona)
            if (t.isAfter(ahora)) return t
            dia = dia.plusWeeks(1)
        }
    }

    /** Las 11:00 de [dia] en [zona]. */
    fun en(dia: LocalDate, zona: ZoneId): Instant = ZonedDateTime.of(dia, LocalTime.of(HORA, MINUTO), zona).toInstant()

    /** Lo que se anota del aviso agendado: su domingo en la zona de ese momento ("2026-10-18"). Es lo que lee [pendiente]. */
    fun anotar(cuando: Instant, zona: ZoneId): String = cuando.atZone(zona).toLocalDate().toString()

    /**
     * Lo que vuelve a armar el sistema (al prender el teléfono, al actualizar la app, al cambiar la zona o la hora): SOLO el
     * aviso que estaba pendiente ([anotado], lo que dejó [anotar] al agendarlo), a las 11:00 de su domingo en la zona de
     * ahora. Sin uno anotado no hay otro: si la app no se abrió, no se inventa (hallazgo 8). Si ya pasó (el teléfono estuvo
     * apagado a esa hora), suena apenas se arma: es el que faltaba, no uno más.
     */
    fun pendiente(anotado: String?, zona: ZoneId): Instant? {
        val dia = try {
            anotado?.let(LocalDate::parse)
        } catch (_: Exception) {
            null
        } ?: return null
        return en(dia, zona)
    }
}

/**
 * `mypump_notif_prefs` (notificaciones.js): un solo recordatorio, la revisión del domingo, apagable y con hora. La
 * nativa no lo usa para agendar (el aviso del domingo es [AvisoDomingo], que no se configura): queda por los ids de la
 * Capacitor y porque la migración trae la clave. Lo guardado se mezcla sobre los valores por defecto campo por campo;
 * claves viejas (entreno, peso, racha) se ignoran.
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
 * Cuándo y cómo se manda el token de push a `mypump_registrar_push` (NOT-01, NOT-02): con una cuenta, nunca en la demo, con
 * el permiso de notificaciones y solo si cambió desde el último que se mandó (`mypump_push_token`, la misma clave que la
 * web).
 *
 * A diferencia de la web y de iOS, se recuerda también DE QUÉ CUENTA fue ese registro ([CLAVE_CUENTA], una huella del token
 * de acceso, nunca el token). Con otra cuenta en el mismo teléfono (el link de otro, ACC-10) el token de push es el mismo:
 * antes no se volvía a mandar y los avisos de la cuenta anterior seguían llegando acá.
 *
 * Un solo transporte por teléfono: la nativa registra solo este token (en Android, el de FCM tal cual) y nunca Web Push.
 * Es el mismo que registraba la Capacitor (la instalación de Firebase sobrevive a la actualización), así que el upsert por
 * `token` deja una sola fila.
 */
object RegistroPush {
    const val CLAVE_TOKEN = "mypump_push_token"
    const val CLAVE_CUENTA = "mypump_push_cuenta"

    enum class Decision { REGISTRAR, YA_REGISTRADO, NO_CORRESPONDE }

    fun decidir(cuenta: String?, esDemo: Boolean, conPermiso: Boolean, dispositivo: String, preferencias: Preferencias): Decision = when {
        cuenta == null || esDemo || !conPermiso || dispositivo.isBlank() -> Decision.NO_CORRESPONDE
        preferencias.leer(CLAVE_TOKEN) == dispositivo && preferencias.leer(CLAVE_CUENTA) == huella(cuenta) -> Decision.YA_REGISTRADO
        else -> Decision.REGISTRAR
    }

    /** La de la carpeta de la cuenta ([Disco.huella]): identifica la cuenta sin guardar el token en las preferencias. */
    fun huella(cuenta: String): String = Disco.huella(cuenta)

    /**
     * El registro en sí, sin el modelo: lo usa [ModeloApp.registrarPush] y el servicio de push con la app cerrada (un token
     * nuevo de FCM). Devuelve si quedó registrado (o ya lo estaba).
     */
    suspend fun registrar(
        cliente: ClienteRpc,
        cuenta: String?,
        esDemo: Boolean,
        conPermiso: Boolean,
        dispositivo: String,
        version: String?,
        preferencias: Preferencias,
        plataforma: String = "android",
    ): Boolean {
        when (decidir(cuenta, esDemo, conPermiso, dispositivo, preferencias)) {
            Decision.NO_CORRESPONDE -> return false
            Decision.YA_REGISTRADO -> return true
            Decision.REGISTRAR -> {}
        }
        val t = cuenta ?: return false
        val r = cliente.llamar(
            "mypump_registrar_push",
            mapOf(
                "p_token" to texto(t), "p_device" to texto(dispositivo), "p_plataforma" to texto(plataforma),
                "p_app_version" to (version?.let { texto(it) } ?: ValorJson.Nulo),
            ),
        )
        if (r.valorONull() != ValorJson.Booleano(true)) return false
        preferencias.guardar(CLAVE_TOKEN, dispositivo)
        preferencias.guardar(CLAVE_CUENTA, huella(t))
        return true
    }
}

/** `registrarPush` con la cuenta del modelo: directo, ver [RegistroPush]. Devuelve si quedó registrado. */
suspend fun ModeloApp.registrarPush(dispositivo: String, version: String?, plataforma: String = "android", conPermiso: Boolean = true): Boolean =
    RegistroPush.registrar(cliente, token, esDemo.value, conPermiso, dispositivo, version, preferencias, plataforma)
