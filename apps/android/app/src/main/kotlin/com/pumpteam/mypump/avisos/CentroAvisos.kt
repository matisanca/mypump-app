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
 * - **El aviso del domingo** (NOT-05, D15): `AvisoDomingo`, el domingo que viene a las 11:00 de la hora del teléfono, sin
 *   configuración y de UNA vez (revisión del 15-oct, hallazgo 8): se arma al entrar con una cuenta y cada vez que la app
 *   vuelve a primer plano, y al sonar no agenda otro. Sin alarmas exactas (`setWindow`, hasta 10 minutos tarde, y en
 *   reposo profundo cuando el teléfono despierte). Al prender el teléfono, al actualizar la app y al cambiar la zona o la
 *   hora ([ReceptorAvisos]) se vuelve a armar SOLO el que estaba pendiente ([CLAVE_DOMINGO]). Sin cuenta, con el link
 *   vencido o en la demo no hay nada agendado.
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
     * El descanso en curso con la app atrás (Ian Actis, 20-oct: «verlo en tiempo real en notificaciones, que quedan 10
     * segundos y ya ir preparándote»): la cuenta regresiva fija, también con el teléfono bloqueado. Prioridad normal y SIN
     * sonido ni vibración: con prioridad baja Android la cuenta como «silenciosa» y en los Pixel de fábrica no se ve con el
     * teléfono bloqueado (revisión del 20-oct). El que suena es el fin del descanso.
     */
    const val CANAL_DESCANSO_EN_CURSO = "mypump_descanso_cuenta"

    /** El primer canal de la cuenta regresiva (prioridad baja), de builds de prueba: la prioridad de un canal no se cambia. */
    private const val CANAL_DESCANSO_EN_CURSO_VIEJO = "mypump_descanso_en_curso"

    /**
     * Los avisos de la app van con esta etiqueta. Los de la Capacitor van sin etiqueta y con los mismos números (1001-1004):
     * así se borran esos sin tocar el nuestro, que también es el 1002.
     */
    const val ETIQUETA = "mypump"
    const val ETIQUETA_PUSH = "mypump-push"

    /** El 1002 de la Capacitor, como iOS: el aviso del domingo pisa el que haya dejado la app vieja. */
    val ID_DOMINGO: Int = AvisoDomingo.ID.toInt()
    const val ID_DESCANSO = 7_001
    const val ID_DESCANSO_EN_CURSO = 7_002

    const val ACCION_AVISO = "com.pumpteam.mypump.AVISO"
    const val ACCION_DOMINGO = "com.pumpteam.mypump.AVISO_DOMINGO"
    const val ACCION_FIN_DESCANSO = "com.pumpteam.mypump.FIN_DESCANSO"

    /** Ya se le mostró la hoja del sistema (la clave de la web: la trae la migración). */
    const val CLAVE_PEDIDO = "mypump_notif_pedido"

    /**
     * El aviso del domingo que está agendado y todavía no sonó: su domingo ("2026-10-18", `AvisoDomingo.anotar`). Con esto
     * el reinicio, la actualización y el cambio de zona o de hora vuelven a armar ESE, sin inventar uno nuevo.
     */
    const val CLAVE_DOMINGO = "mypump_aviso_domingo"

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
        nm.deleteNotificationChannel(CANAL_DESCANSO_EN_CURSO_VIEJO)
        nm.createNotificationChannels(
            listOf(
                NotificationChannel(CANAL_MENSAJES, "Mensajes de Mati", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Lo que te escribe Mati y su aviso de los domingos para la revisión."
                },
                NotificationChannel(CANAL_DESCANSO, "Fin del descanso", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Cuando termina el descanso entre series y la app no está a la vista."
                },
                NotificationChannel(CANAL_DESCANSO_EN_CURSO, "Descanso en curso", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "La cuenta regresiva del descanso entre series, también con el teléfono bloqueado."
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
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
     * Al arrancar con una cuenta (fuera de la demo) y cada vez que la app vuelve a primer plano: se borra lo que dejó la
     * Capacitor y, si hay permiso, se agenda el aviso del domingo que viene (es de una vez: así le sigue llegando a quien
     * usa la app) y se registra el token de push (solo si cambió); sin permiso no queda nada agendado. Corre en el hilo
     * principal, como el modelo.
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

    /** Sin cuenta (salió), con el link vencido o en la demo: el aviso del domingo ya no es para este teléfono. */
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

    /**
     * Agenda el domingo que viene a las 11:00 de la zona del teléfono, una sola vez (pisa el que hubiera), y lo anota en
     * [CLAVE_DOMINGO]. Devuelve cuándo.
     */
    fun programarDomingo(c: Context, ahora: Instant = Instant.now(), zona: ZoneId = ZoneId.systemDefault()): Instant? {
        val cuando = AvisoDomingo.proximo(ahora, zona)
        if (!armarDomingo(c, cuando)) return null
        PreferenciasCompartidas(c).guardar(CLAVE_DOMINGO, AvisoDomingo.anotar(cuando, zona))
        return cuando
    }

    private fun armarDomingo(c: Context, cuando: Instant): Boolean {
        val am = c.getSystemService(AlarmManager::class.java) ?: return false
        val pi = alarmaDomingo(c, crear = true) ?: return false
        am.setWindow(AlarmManager.RTC_WAKEUP, cuando.toEpochMilli(), VENTANA_DOMINGO_MS, pi)
        return true
    }

    /** Ni la alarma ni lo anotado: no queda ningún aviso del domingo pendiente. */
    fun cancelarDomingo(c: Context) {
        PreferenciasCompartidas(c).guardar(CLAVE_DOMINGO, null)
        val pi = alarmaDomingo(c, crear = false) ?: return
        c.getSystemService(AlarmManager::class.java)?.cancel(pi)
        pi.cancel()
    }

    /** Hay un aviso del domingo agendado. */
    fun domingoAgendado(c: Context): Boolean = alarmaDomingo(c, crear = false) != null

    /** El domingo del aviso pendiente, como quedó anotado ("2026-10-18"), o null si no hay ninguno. */
    fun domingoPendiente(c: Context): String? = PreferenciasCompartidas(c).leer(CLAVE_DOMINGO)

    /**
     * Sonó la alarma del domingo: se publica (con cuenta y permiso) y NO se agenda el de la semana que viene. Lo vuelve a
     * armar la app cuando se usa: a quien la dejó o tiene el link vencido le llega como mucho este (hallazgo 8). Se suelta
     * el PendingIntent y lo anotado: no queda ninguno pendiente.
     */
    fun alSonarDomingo(c: Context) {
        val publicar = hayCuentaGuardada(c) && concedido(c)
        cancelarDomingo(c)
        if (publicar) mostrarDomingo(c)
    }

    /**
     * Al prender el teléfono (las alarmas no sobreviven a un reinicio), al actualizar la app o al cambiar la zona o la hora:
     * SOLO el aviso que estaba pendiente, a las 11:00 de su domingo en la zona de ahora (`AvisoDomingo.pendiente`). Si no
     * había uno, no se inventa: la app no se abrió desde que sonó el último (hallazgo 8). Sin cuenta o sin permiso, nada.
     */
    fun reagendar(c: Context, zona: ZoneId = ZoneId.systemDefault()) {
        crearCanales(c)
        limpiarCapacitor(c)
        val cuando = AvisoDomingo.pendiente(domingoPendiente(c), zona)
        if (cuando != null && hayCuentaGuardada(c) && concedido(c) && armarDomingo(c, cuando)) return
        cancelarDomingo(c)
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
        cancelarDescansoEnCurso(c)
    }

    /**
     * La cuenta regresiva fija hasta [finMs]. La anima el sistema: sigue con la app dormida y se va sola al terminar. Sin
     * barra de progreso, que quedaría congelada (nadie la actualiza con la app atrás).
     */
    fun mostrarDescansoEnCurso(c: Context, finMs: Long) {
        val falta = finMs - System.currentTimeMillis()
        if (!concedido(c) || falta <= 1_000) return
        crearCanales(c)
        val toque = PendingIntent.getActivity(c, ID_DESCANSO_EN_CURSO, intentDeAviso(c, "train"), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(c, CANAL_DESCANSO_EN_CURSO)
            .setSmallIcon(R.drawable.ic_stat_mypump)
            .setColor(c.getColor(R.color.aviso_acento))
            .setContentTitle("Descanso")
            .setContentText("Preparate para la próxima serie")
            .setWhen(finMs)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setTimeoutAfter(falta + 1_000)
            .setContentIntent(toque)
            .build()
        try {
            c.getSystemService(NotificationManager::class.java)?.notify(ETIQUETA, ID_DESCANSO_EN_CURSO, n)
        } catch (_: SecurityException) {
        }
    }

    fun cancelarDescansoEnCurso(c: Context) {
        c.getSystemService(NotificationManager::class.java)?.cancel(ETIQUETA, ID_DESCANSO_EN_CURSO)
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
        cancelarDescansoEnCurso(c)
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
