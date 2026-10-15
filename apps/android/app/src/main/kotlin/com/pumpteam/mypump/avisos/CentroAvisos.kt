package com.pumpteam.mypump.avisos

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.annotation.VisibleForTesting
import com.google.firebase.messaging.FirebaseMessaging
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.R
import com.pumpteam.mypump.acceso.PreferenciasCompartidas
import com.pumpteam.mypump.acceso.TokenEnKeystore
import com.pumpteam.mypump.datos.AvisoDomingo
import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.DestinoAviso
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.RegistroPush
import com.pumpteam.mypump.datos.TransporteOkHttp
import com.pumpteam.mypump.datos.registrarPush
import com.pumpteam.mypump.legado.ArranqueMigracion
import java.io.File
import java.time.Instant
import java.time.ZoneId
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** El permiso de notificaciones como lo usa la app (el `UNAuthorizationStatus` de iOS). */
enum class PermisoAvisos {
    /** Los avisos llegan. */
    CONCEDIDO,

    /** Todavía se puede pedir con la hoja del sistema: nunca se pidió, o dijo que no una sola vez. */
    SIN_PEDIR,

    /** Solo desde Ajustes: lo negó dos veces (Android 13+) o apagó las notificaciones de la app (12 o menos). */
    NEGADO,
}

/**
 * Las pruebas de interfaz no pueden sacar el permiso: `pm revoke` mata el proceso de la app, y con él el de la prueba.
 * Fijan acá lo que "dice el sistema" y lo que "contesta" su hoja. En la app los dos quedan en null.
 */
@VisibleForTesting
object PermisoDePrueba {
    @Volatile var estado: PermisoAvisos? = null

    /** Contestar cambia [estado], como el sistema. */
    @Volatile var respuesta: Boolean? = null
}

/**
 * Las notificaciones en Android (gemelo de `CentroAvisos.swift`):
 *
 * - **El push de los mensajes de Mati** (NOT-01, NOT-02): el token de FCM se manda a `mypump_registrar_push` al arrancar con
 *   una cuenta y con permiso, y cuando FCM da uno nuevo ([ServicioPush]); solo si cambió (ver `RegistroPush`). Nunca en la
 *   demo ni sin cuenta. Con la app en segundo plano el aviso lo muestra el sistema con el canal, el ícono y el color del
 *   manifest; con la app abierta lo publica la app (NOT-04).
 * - **El aviso del domingo** (NOT-05, D15): `AvisoDomingo`, domingo a las 11:00 de la hora del teléfono, sin configuración.
 *   Sin alarmas exactas (`setWindow`, hasta 10 minutos tarde, y en reposo profundo cuando el teléfono despierte): cada
 *   aviso agenda el siguiente, y se reagenda al abrir con una cuenta, al prender el teléfono, al actualizar la app y al
 *   cambiar la zona o la hora ([ReceptorAvisos]). Sin cuenta o en la demo no hay nada agendado.
 * - **Lo que dejó la Capacitor** (NOT-08): sus alarmas 1001-1004, lo que llegó a publicar y su canal.
 * - **El fin del descanso** (D8): con la app en segundo plano.
 * - **Tocar un aviso** (NOT-03): abre la Activity con su `destino` ([intentDeAviso], [destinoDe]).
 */
object CentroAvisos {
    private const val LOG = "MyPumpAvisos"

    /**
     * Los mensajes de Mati: el push de sus comentarios y su aviso del domingo. Es el `default_notification_channel_id` del
     * manifest: FCM lo usa con la app en segundo plano.
     */
    const val CANAL_MENSAJES = "mypump_mensajes"

    /** El fin del descanso, en su canal: quien lo apague en Ajustes no deja de recibir a Mati. */
    const val CANAL_DESCANSO = "mypump_descanso"

    /**
     * Los avisos de la app van con esta etiqueta. Los de la Capacitor van sin etiqueta y con los mismos números (1001-1004):
     * así se borran esos sin tocar el nuestro, que también es el 1002.
     */
    const val ETIQUETA = "mypump"
    const val ETIQUETA_PUSH = "mypump-push"

    /** El 1002 de la Capacitor, como iOS: el aviso del domingo pisa el que haya dejado la app vieja. */
    val ID_DOMINGO: Int = AvisoDomingo.ID.toInt()
    const val ID_DESCANSO = 7_001

    const val ACCION_AVISO = "com.pumpteam.mypump.AVISO"
    const val ACCION_DOMINGO = "com.pumpteam.mypump.AVISO_DOMINGO"
    const val ACCION_FIN_DESCANSO = "com.pumpteam.mypump.FIN_DESCANSO"

    /** Ya se le mostró la hoja del sistema (la clave de la web: la trae la migración). */
    const val CLAVE_PEDIDO = "mypump_notif_pedido"

    /** La ventana más chica que respeta Android 12+ sin alarma exacta: el aviso del domingo llega entre las 11:00 y las 11:10. */
    const val VENTANA_DOMINGO_MS = 10 * 60_000L

    /** Lo de la Capacitor: los ids de sus locales (1002 era la revisión; 1001, 1003 y 1004, las que se sacaron)… */
    private val IDS_CAPACITOR = listOf(1001, 1002, 1003, 1004)

    /** …la clase a la que apuntaban sus alarmas (ya no está en el APK, pero el PendingIntent se encuentra igual)… */
    const val PUBLICADOR_CAPACITOR = "com.capacitorjs.plugins.localnotifications.TimedNotificationPublisher"

    /** …y su canal ("Default"), que en Ajustes quedaría como una categoría sin nombre propio. */
    const val CANAL_CAPACITOR = "default"

    /** La app está a la vista (lo pone la raíz con el ciclo de vida): el fin del descanso no se avisa encima. */
    @Volatile var enPrimerPlano = false

    /** El modelo de la app viva: un token nuevo de FCM se registra con él (así respeta la demo). */
    @Volatile var modeloVivo: ModeloApp? = null

    /** Cuántas veces se pidió el permiso (las pruebas miran que "Ahora no" no pida nada). */
    @VisibleForTesting @Volatile var pedidos = 0

    /** El token de FCM en las pruebas de interfaz (sin Firebase ni red). */
    @VisibleForTesting @Volatile var tokenDePrueba: String? = null

    // ── Canales y permiso ──

    fun crearCanales(c: Context) {
        val nm = c.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannels(
            listOf(
                NotificationChannel(CANAL_MENSAJES, "Mensajes de Mati", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Lo que te escribe Mati y su aviso de los domingos para la revisión."
                },
                NotificationChannel(CANAL_DESCANSO, "Fin del descanso", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Cuando termina el descanso entre series y la app no está a la vista."
                },
            ),
        )
    }

    /** Llegan los avisos: el permiso (Android 13+) o las notificaciones de la app prendidas (12 o menos). */
    fun concedido(c: Context): Boolean {
        PermisoDePrueba.estado?.let { return it == PermisoAvisos.CONCEDIDO }
        return c.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() == true
    }

    fun permiso(c: Context): PermisoAvisos {
        PermisoDePrueba.estado?.let { return it }
        if (concedido(c)) return PermisoAvisos.CONCEDIDO
        // Hasta Android 12 no hay hoja: vienen prendidas, así que las apagó el cliente en Ajustes.
        if (Build.VERSION.SDK_INT < 33) return PermisoAvisos.NEGADO
        if (c.actividad()?.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS) == true) return PermisoAvisos.SIN_PEDIR
        // Android no dice si la hoja va a volver a salir: si ya se pidió y no corresponde explicar, la negó dos veces.
        return if (PreferenciasCompartidas(c).leer(CLAVE_PEDIDO) == "1") PermisoAvisos.NEGADO else PermisoAvisos.SIN_PEDIR
    }

    /**
     * La hoja del sistema (Android 13+), con el [lanzador] de la pantalla, que contesta en [alResultado]. Queda anotado que se
     * pidió, como en la web y en iOS. En 12 o menos no hay hoja: contesta lo que hay.
     */
    fun pedir(c: Context, lanzador: ActivityResultLauncher<String>, alResultado: (Boolean) -> Unit) {
        pedidos++
        PreferenciasCompartidas(c).guardar(CLAVE_PEDIDO, "1")
        PermisoDePrueba.respuesta?.let { ok ->
            PermisoDePrueba.estado = if (ok) PermisoAvisos.CONCEDIDO else PermisoAvisos.NEGADO
            alResultado(ok)
            return
        }
        if (Build.VERSION.SDK_INT < 33) {
            alResultado(concedido(c))
            return
        }
        try {
            lanzador.launch(Manifest.permission.POST_NOTIFICATIONS)
        } catch (_: ActivityNotFoundException) {
            alResultado(false)
        }
    }

    /** "Activar en Ajustes": las notificaciones de MyPump en los ajustes del teléfono. */
    fun abrirAjustes(c: Context) {
        val intentos = listOf(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, c.packageName),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", c.packageName, null)),
        )
        for (i in intentos) {
            try {
                c.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: ActivityNotFoundException) {
            }
        }
    }

    // ── Con una cuenta ──

    /**
     * Al arrancar con una cuenta (fuera de la demo): se borra lo que dejó la Capacitor y, si hay permiso, se agenda el aviso
     * del domingo y se registra el token de push; sin permiso no queda nada agendado. Corre en el hilo principal, como el
     * modelo.
     */
    suspend fun alEntrar(c: Context, m: ModeloApp, version: String) {
        crearCanales(c)
        limpiarCapacitor(c)
        if (!concedido(c)) {
            cancelarDomingo(c)
            return
        }
        programarDomingo(c)
        registrarPush(c, m, version)
    }

    /** El cliente acaba de dar el permiso (la hoja de la primera vez o Mis datos): lo mismo que [alEntrar], ya mismo. */
    fun alActivar(c: Context, m: ModeloApp, version: String, alcance: CoroutineScope) {
        if (!concedido(c)) return
        crearCanales(c)
        programarDomingo(c)
        alcance.launch { registrarPush(c, m, version) }
    }

    /** Sin cuenta (link vencido, salir) o en la demo: no queda nada agendado. */
    fun alQuedarSinCuenta(c: Context) {
        cancelarDomingo(c)
    }

    suspend fun registrarPush(c: Context, m: ModeloApp, version: String): Boolean {
        val dispositivo = tokenPush() ?: return false
        val ok = m.registrarPush(dispositivo, version, conPermiso = concedido(c))
        if (!ok) Log.i(LOG, "el token de push no se registró (se reintenta en el próximo arranque)")
        return ok
    }

    /**
     * Un token nuevo de FCM (`onNewToken`, en el hilo del servicio, que espera): con la app viva va por su modelo; con la app
     * cerrada, con la cuenta guardada (la demo vive solo en memoria: con la app cerrada no hay demo).
     */
    fun alNuevoToken(c: Context, dispositivo: String) {
        if (!concedido(c)) return
        val version = ArranqueMigracion.version(c)
        val registrar: suspend () -> Boolean = registrar@{
            val vivo = modeloVivo
            if (vivo != null) {
                withContext(Dispatchers.Main) { vivo.registrarPush(dispositivo, version) }
            } else {
                val cuenta = TokenEnKeystore(File(c.noBackupFilesDir, TokenEnKeystore.ARCHIVO)).leer() ?: return@registrar false
                val cliente = ClienteRpc(transporte = Entorno.transporte ?: TransporteOkHttp())
                RegistroPush.registrar(cliente, cuenta, esDemo = false, conPermiso = true, dispositivo, version, PreferenciasCompartidas(c))
            }
        }
        // FCM lo llama en su hilo y espera: con la app cerrada, el proceso no se va antes de registrar. Desde el principal
        // (no debería pasar) esperar al principal lo trabaría: ahí va sin esperar.
        if (Looper.myLooper() == Looper.getMainLooper()) {
            CoroutineScope(Dispatchers.Main).launch { withTimeoutOrNull(20_000) { registrar() } }
        } else {
            runBlocking { withTimeoutOrNull(20_000) { registrar() } }
        }
    }

    /** El token de FCM de este teléfono. null sin Google Play o sin red: se reintenta en el próximo arranque. */
    suspend fun tokenPush(): String? {
        tokenDePrueba?.let { return it }
        return withTimeoutOrNull(30_000) {
            suspendCancellableCoroutine { cont ->
                try {
                    FirebaseMessaging.getInstance().token.addOnCompleteListener { t ->
                        cont.resume(if (t.isSuccessful) t.result else null)
                    }
                } catch (_: Exception) {
                    // Sin la configuración de Firebase (no pasa con google-services.json): sin push, nada más.
                    cont.resume(null)
                }
            }
        }
    }

    /** Hay una cuenta guardada en el teléfono (sin descifrarla: alcanza para lo que corre sin la app). */
    fun hayCuentaGuardada(c: Context): Boolean = File(c.noBackupFilesDir, TokenEnKeystore.ARCHIVO).isFile

    // ── Publicar ──

    /** El Intent con que tocar un aviso abre la app: la Activity de siempre, con su destino (NOT-03). */
    fun intentDeAviso(c: Context, destino: String?): Intent =
        Intent(c, MainActivity::class.java)
            .setAction(ACCION_AVISO)
            .putExtra(DestinoAviso.EXTRA_AVISO, "1")
            .putExtra(DestinoAviso.EXTRA_DESTINO, destino)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** A dónde pidió ir el Intent con que se abrió la app: un aviso propio o un push que mostró FCM. null si no es un aviso. */
    fun destinoDe(intent: Intent?): DestinoAviso? = try {
        val extras = intent?.extras
        if (extras == null) null else DestinoAviso.alTocar(extras.keySet(), extras.getString(DestinoAviso.EXTRA_DESTINO))
    } catch (_: RuntimeException) {
        // Extras que no se pueden leer (no son nuestros): no es un aviso.
        null
    }

    private fun publicar(
        c: Context,
        etiqueta: String,
        id: Int,
        canal: String,
        titulo: String?,
        cuerpo: String?,
        destino: String?,
        categoria: String,
        soloUnaVez: Boolean = false,
    ) {
        if (!concedido(c)) return
        crearCanales(c)
        val toque = PendingIntent.getActivity(c, id, intentDeAviso(c, destino), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(c, canal)
            .setSmallIcon(R.drawable.ic_stat_mypump)
            .setColor(c.getColor(R.color.aviso_acento))
            .setContentTitle(titulo)
            .setContentText(cuerpo)
            .setStyle(Notification.BigTextStyle().bigText(cuerpo))
            .setCategory(categoria)
            .setAutoCancel(true)
            .setOnlyAlertOnce(soloUnaVez)
            .setContentIntent(toque)
            .build()
        try {
            c.getSystemService(NotificationManager::class.java)?.notify(etiqueta, id, n)
        } catch (_: SecurityException) {
            // Se sacó el permiso justo ahora.
        }
    }

    /** Un push con la app abierta (NOT-04): FCM no lo muestra, lo publica la app en el canal de los mensajes. */
    fun mostrarPush(c: Context, titulo: String?, cuerpo: String?, destino: String?, idMensaje: String?) {
        if (titulo.isNullOrBlank() && cuerpo.isNullOrBlank()) return
        val id = (idMensaje ?: System.currentTimeMillis().toString()).hashCode()
        publicar(c, ETIQUETA_PUSH, id, CANAL_MENSAJES, titulo, cuerpo, destino, Notification.CATEGORY_MESSAGE)
    }

    fun mostrarDomingo(c: Context) {
        publicar(c, ETIQUETA, ID_DOMINGO, CANAL_MENSAJES, AvisoDomingo.TITULO, AvisoDomingo.CUERPO, AvisoDomingo.DESTINO, Notification.CATEGORY_REMINDER)
    }

    // ── El aviso del domingo ──

    private fun alarmaDomingo(c: Context, crear: Boolean): PendingIntent? = PendingIntent.getBroadcast(
        c,
        ID_DOMINGO,
        Intent(c, ReceptorAvisos::class.java).setAction(ACCION_DOMINGO),
        PendingIntent.FLAG_IMMUTABLE or (if (crear) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE),
    )

    /** Agenda el próximo domingo a las 11:00 de la zona del teléfono (pisa el que hubiera). Devuelve cuándo. */
    fun programarDomingo(c: Context, ahora: Instant = Instant.now(), zona: ZoneId = ZoneId.systemDefault()): Instant? {
        val am = c.getSystemService(AlarmManager::class.java) ?: return null
        val pi = alarmaDomingo(c, crear = true) ?: return null
        val cuando = AvisoDomingo.proximo(ahora, zona)
        am.setWindow(AlarmManager.RTC_WAKEUP, cuando.toEpochMilli(), VENTANA_DOMINGO_MS, pi)
        return cuando
    }

    fun cancelarDomingo(c: Context) {
        val pi = alarmaDomingo(c, crear = false) ?: return
        c.getSystemService(AlarmManager::class.java)?.cancel(pi)
        pi.cancel()
    }

    /** Hay un aviso del domingo agendado. */
    fun domingoAgendado(c: Context): Boolean = alarmaDomingo(c, crear = false) != null

    /** Sonó la alarma del domingo: se publica (con cuenta y permiso) y se agenda el de la semana que viene. */
    fun alSonarDomingo(c: Context) {
        if (!hayCuentaGuardada(c) || !concedido(c)) {
            cancelarDomingo(c)
            return
        }
        mostrarDomingo(c)
        programarDomingo(c)
    }

    /** Al prender el teléfono, al actualizar la app o al cambiar la zona o la hora: el aviso del domingo con la hora local. */
    fun reagendar(c: Context) {
        crearCanales(c)
        limpiarCapacitor(c)
        if (hayCuentaGuardada(c) && concedido(c)) programarDomingo(c) else cancelarDomingo(c)
    }

    // ── Lo que dejó la Capacitor (NOT-08) ──

    /**
     * Las alarmas que agendó la Capacitor siguen en el sistema después de actualizar (Android no las borra en una
     * actualización) y apuntan a una clase que ya no existe. Se encuentran con el mismo PendingIntent que armaba su plugin
     * (`LocalNotificationManager.triggerScheduledNotification`: Intent explícito a `TimedNotificationPublisher`, sin acción,
     * con el id como código y `FLAG_MUTABLE` desde Android 12; los extras no cuentan) y se cancelan. Lo que ya publicó se
     * saca por id, sin etiqueta. Es idempotente: corre en cada arranque con una cuenta y al actualizar.
     */
    fun limpiarCapacitor(c: Context) {
        val am = c.getSystemService(AlarmManager::class.java)
        val nm = c.getSystemService(NotificationManager::class.java)
        val publicador = Intent().setComponent(ComponentName(c.packageName, PUBLICADOR_CAPACITOR))
        val banderas = PendingIntent.FLAG_NO_CREATE or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        for (id in IDS_CAPACITOR) {
            val pi = try {
                PendingIntent.getBroadcast(c, id, publicador, banderas)
            } catch (_: RuntimeException) {
                null
            }
            if (pi != null) {
                am?.cancel(pi)
                pi.cancel()
            }
            nm?.cancel(id)
        }
        try {
            nm?.deleteNotificationChannel(CANAL_CAPACITOR)
        } catch (_: RuntimeException) {
        }
    }

    // ── El fin del descanso (D8) ──

    private fun alarmaDescanso(c: Context, crear: Boolean): PendingIntent? = PendingIntent.getBroadcast(
        c,
        ID_DESCANSO,
        Intent(c, ReceptorAvisos::class.java).setAction(ACCION_FIN_DESCANSO),
        PendingIntent.FLAG_IMMUTABLE or (if (crear) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE),
    )

    /**
     * La app pasó a segundo plano con un descanso corriendo: una alarma inexacta para cuando termina, sin
     * `SCHEDULE_EXACT_ALARM` y también en reposo (`AllowWhileIdle`). Con la pantalla prendida llega en el momento; con la
     * pantalla apagada Android puede esperar a despertar el teléfono hasta el final de la ventana que le da a una alarma
     * inexacta (el 75 % de lo que faltaba): un descanso de 90 s puede avisar hasta un minuto tarde si nada lo despierta
     * antes (ver el README). Mientras el proceso corre, el aviso sale antes desde el reloj del descanso
     * ([mostrarFinDescanso]). Solo con permiso: nunca lo pide.
     */
    fun programarFinDescanso(c: Context, finMs: Long) {
        if (!concedido(c) || finMs - System.currentTimeMillis() <= 1_000) return
        val pi = alarmaDescanso(c, crear = true) ?: return
        c.getSystemService(AlarmManager::class.java)?.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, finMs, pi)
    }

    /** Volvió a la app o se salteó el descanso: ni la alarma ni el aviso. */
    fun cancelarFinDescanso(c: Context) {
        cancelarAlarmaDescanso(c)
        c.getSystemService(NotificationManager::class.java)?.cancel(ETIQUETA, ID_DESCANSO)
    }

    fun finDescansoAgendado(c: Context): Boolean = alarmaDescanso(c, crear = false) != null

    private fun cancelarAlarmaDescanso(c: Context) {
        val pi = alarmaDescanso(c, crear = false) ?: return
        c.getSystemService(AlarmManager::class.java)?.cancel(pi)
        pi.cancel()
    }

    /** "Terminó el descanso" (el texto de iOS): lleva a Entreno. Si llegan la alarma y el reloj, suena una sola vez. */
    fun mostrarFinDescanso(c: Context) {
        cancelarAlarmaDescanso(c)
        publicar(c, ETIQUETA, ID_DESCANSO, CANAL_DESCANSO, "Terminó el descanso", "Seguí con la próxima serie.", "train", Notification.CATEGORY_REMINDER, soloUnaVez = true)
    }
}

/** La Activity detrás de un contexto de Compose (la hoja de permisos lo necesita para saber si se puede volver a pedir). */
internal fun Context.actividad(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) {
        if (c is Activity) return c
        c = c.baseContext
    }
    return null
}
