package com.pumpteam.mypump.ui

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.firebase.messaging.RemoteMessage
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.R
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.avisos.PermisoAvisos
import com.pumpteam.mypump.avisos.PermisoDePrueba
import com.pumpteam.mypump.avisos.ReceptorAvisos
import com.pumpteam.mypump.avisos.ServicioPush
import com.pumpteam.mypump.datos.AvisoDomingo
import com.pumpteam.mypump.entreno.SonidoDescanso
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las notificaciones (NOT-01 a NOT-08 y D8) en el emulador, con el backend de prueba: tocar un aviso abre su pestaña (en
 * frío y en caliente), el push con la app abierta se muestra, el aviso del domingo se agenda solo con una cuenta y con
 * permiso y es de una vez (se vuelve a armar al usar la app; el sistema solo vuelve a armar el pendiente), lo de la
 * Capacitor se borra, el manifest trae el canal y el ícono, y el fin del descanso avisa en segundo plano.
 *
 * El envío real de un push (FCM → teléfono) no se puede probar acá: necesita un teléfono con Google Play y una cuenta.
 * La recepción sí, con un `RemoteMessage` armado a mano contra el servicio.
 */
@RunWith(AndroidJUnit4::class)
class AvisosUiTest : PruebaUi() {
    private val nm: NotificationManager get() = app.getSystemService(NotificationManager::class.java)

    /** Lo que FCM pone en el Intent al tocar un push que mostró el sistema (la app en segundo plano). */
    private fun intentDePush(destino: String?): Intent =
        Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setClassName(app, MainActivity::class.java.name)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra("google.message_id", "0:1760000000000000%prueba")
            .putExtra("google.sent_time", 1_760_000_000_000L)
            .putExtra("from", "1018918634428")
            .apply { if (destino != null) putExtra("destino", destino) }

    private fun publicado(etiqueta: String, id: Int) =
        p.esperar("publicado $etiqueta/$id") { AvisosDePrueba.publicadas(app).firstOrNull { it.tag == etiqueta && it.id == id } }

    /**
     * Las alarmas que el sistema tiene pendientes ahora, una por bloque (su renglón y los de abajo, unidos con " | "). Es la
     * parte de `dumpsys alarm` que sigue a "N pending alarms:" (Android 12 en adelante) o a "Pending alarm batches: N" (hasta
     * Android 11, con las alarmas agrupadas en renglones `Batch{…}`), hasta el renglón siguiente de la sección ("Pending
     * alarms per uid", o cualquiera con dos espacios o menos); lo demás es historia, con las que ya se cancelaron. El formato
     * cambia entre versiones (el 15-oct en Android 9 no se encontraba ninguna): así se lee en todas.
     */
    private fun alarmasPendientes(): List<String> {
        val lineas = Telefono.shell("dumpsys alarm").lines()
        val desde = lineas.indexOfFirst { it.trim().endsWith("pending alarms:") || it.trim().startsWith("Pending alarm batches:") }
        if (desde < 0) return emptyList()
        val bloques = ArrayList<String>()
        for (l in lineas.drop(desde + 1)) {
            if (l.startsWith("Batch{")) continue
            if (l.trim().startsWith("Pending alarms per uid") || Regex("^\\s{0,2}\\S").containsMatchIn(l)) break
            if (Regex("^\\s{4}\\S").containsMatchIn(l)) bloques += l.trim() else if (bloques.isNotEmpty()) bloques[bloques.size - 1] += " | " + l.trim()
        }
        return bloques
    }

    // ── NOT-03: tocar un aviso ──

    @Test
    fun tocarUnAvisoConLaAppCerradaAbreSuPestana() {
        guardarCuenta()
        registrar(ActivityScenario.launch<MainActivity>(CentroAvisos.intentDeAviso(app, "diet"))).also {
            p.esperar("Dieta elegida") { p.seleccionado(etiqueta("pestana-dieta")) }
            p.nodo(texto("2.373"))
        }.close()
        // Un push que mostró el sistema: "salud" es Mis datos.
        registrar(ActivityScenario.launch<MainActivity>(intentDePush("salud"))).also {
            p.nodo(etiqueta("mis-datos-pantalla"))
            assertTrue(p.seleccionado(etiqueta("pestana-revision")))
        }.close()
        // Uno desconocido (el histórico "comentarios") o sin destino: Chat.
        for (destino in listOf("comentarios", null)) {
            registrar(ActivityScenario.launch<MainActivity>(intentDePush(destino))).also {
                p.esperar<Boolean>("Chat elegido con $destino") { p.seleccionado(etiqueta("pestana-chat")) }
            }.close()
        }
        // Abrir desde el ícono no cambia de pestaña.
        abrir()
        p.nodo(etiqueta("pestana-entreno"))
        p.quieto(1_500)
        assertTrue(p.seleccionado(etiqueta("pestana-entreno")))
    }

    @Test
    fun tocarUnAvisoConLaAppAbiertaCambiaDePestana() {
        guardarCuenta()
        abrir()
        p.esperar("Entreno elegido") { p.seleccionado(etiqueta("pestana-entreno")) }
        app.startActivity(CentroAvisos.intentDeAviso(app, "revision"))
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
        app.startActivity(intentDePush("train"))
        p.esperar("Entreno elegido") { p.seleccionado(etiqueta("pestana-entreno")) }
        app.startActivity(intentDePush("progress"))
        p.esperar("Progreso elegido") { p.seleccionado(etiqueta("pestana-progreso")) }
    }

    /** De punta a punta: el aviso que publica la app, con su PendingIntent de verdad. */
    @Test
    fun elAvisoDelDomingoPublicadoLlevaARevision() {
        AvisosDePrueba.concederDeVerdad(app)
        guardarCuenta()
        abrir()
        p.esperar("Entreno elegido") { p.seleccionado(etiqueta("pestana-entreno")) }
        CentroAvisos.mostrarDomingo(app)
        val n = publicado(CentroAvisos.ETIQUETA, CentroAvisos.ID_DOMINGO).notification
        // Un mensaje de Mati (D15): su nombre de título y su texto, en el canal de los mensajes.
        assertEquals(AvisoDomingo.TITULO, n.extras.getString(Notification.EXTRA_TITLE))
        assertEquals(AvisoDomingo.CUERPO, n.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals(CentroAvisos.CANAL_MENSAJES, n.channelId)
        assertEquals(R.drawable.ic_stat_mypump, n.smallIcon.resId)
        n.contentIntent.send()
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
    }

    // ── NOT-04: el push con la app abierta ──

    @Test
    fun conLaAppAbiertaElPushSeMuestraYLlevaASuPestana() {
        AvisosDePrueba.concederDeVerdad(app)
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-dieta"))
        // Lo que manda push.py: notification{title, body} + data{destino}.
        val mensaje = RemoteMessage(
            Bundle().apply {
                putString("google.message_id", "0:1760000000000001%prueba")
                putString("from", "1018918634428")
                putString("gcm.n.e", "1")
                putString("gcm.n.title", "Mati")
                putString("gcm.n.body", "Bajá un poco el peso y apretá arriba un segundo.")
                putString("destino", "train")
            },
        )
        ServicioDePrueba(app).onMessageReceived(mensaje)
        val n = p.esperar("el push publicado") { AvisosDePrueba.publicadas(app).firstOrNull { it.tag == CentroAvisos.ETIQUETA_PUSH } }.notification
        assertEquals("Mati", n.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Bajá un poco el peso y apretá arriba un segundo.", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals(CentroAvisos.CANAL_MENSAJES, n.channelId)
        assertEquals(R.drawable.ic_stat_mypump, n.smallIcon.resId)
        // Para la evidencia: el aviso en la cortina, con el ícono chico, el título y el texto (la cortina tarda en bajar).
        Telefono.shell("cmd statusbar expand-notifications")
        p.quieto(1_500)
        Telefono.captura("26-aviso-push-claro")
        Telefono.shell("cmd statusbar collapse")
        n.contentIntent.send()
        p.esperar("Entreno elegido") { p.seleccionado(etiqueta("pestana-entreno")) }
        // Un mensaje sin texto no se muestra.
        nm.cancelAll()
        ServicioDePrueba(app).onMessageReceived(RemoteMessage(Bundle().apply { putString("destino", "chat") }))
        p.quieto(500)
        assertTrue(AvisosDePrueba.publicadas(app).isEmpty())
    }

    // ── NOT-01, NOT-05: con una cuenta y con permiso ──

    @Test
    fun conCuentaYPermisoSeAgendaElDomingoYSeRegistraElPush() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        guardarCuenta()
        abrir().also {
            p.nodo(etiqueta("pestana-entreno"))
            p.esperar("el aviso del domingo agendado") { CentroAvisos.domingoAgendado(app) }
            val registro = p.esperar("el registro del push") { servidor.a("mypump_registrar_push").firstOrNull() }
            assertTrue(registro, "\"p_token\":\"${ServidorDePrueba.TOKEN}\"" in registro)
            assertTrue(registro, "\"p_device\":\"${AvisosDePrueba.TOKEN_PUSH}\"" in registro)
            assertTrue(registro, "\"p_plataforma\":\"android\"" in registro)
            assertTrue(registro, "\"p_app_version\":\"2.0.0 (100)\"" in registro)
            // En el sistema: una sola alarma del domingo, RTC_WAKEUP con ventana (inexacta). La anota para la evidencia.
            val domingo = alarmasPendientes().filter { "AVISO_DOMINGO" in it }
            assertEquals(domingo.toString(), 1, domingo.size)
            assertTrue(domingo.single(), "RTC_WAKEUP" in domingo.single() && "window=+10m" in domingo.single())
            println("Avisos: ${domingo.single()}")
            // Es el domingo que viene, de una vez, y queda anotado para volver a armarlo si el teléfono se reinicia.
            val zona = ZoneId.systemDefault()
            assertEquals(AvisoDomingo.anotar(AvisoDomingo.proximo(Instant.now(), zona), zona), CentroAvisos.domingoPendiente(app))
        }.close()
        // Al reabrir no se vuelve a registrar (el token no cambió).
        abrir()
        p.nodo(etiqueta("pestana-entreno"))
        p.quieto(1_500)
        assertEquals(1, servidor.a("mypump_registrar_push").size)
    }

    @Test
    fun sinPermisoEnLaDemoOSinCuentaNoSeAgendaNiSeRegistra() {
        // Sin permiso, con cuenta.
        PermisoDePrueba.estado = PermisoAvisos.SIN_PEDIR
        guardarCuenta()
        abrir().also {
            p.nodo(etiqueta("pestana-entreno"))
            p.quieto(1_500)
        }.close()
        assertFalse(CentroAvisos.domingoAgendado(app))
        // En la demo, aunque haya permiso.
        reiniciarEstado()
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        abrir().also {
            p.tocar(etiqueta("ver-demo"))
            p.nodo(texto("Estás viendo la demo"))
            p.quieto(1_500)
        }.close()
        assertFalse(CentroAvisos.domingoAgendado(app))
        assertTrue(servidor.a("mypump_registrar_push").isEmpty())
        // Sin cuenta, la bienvenida.
        abrir()
        p.nodo(etiqueta("ver-demo"))
        p.quieto(1_000)
        assertFalse(CentroAvisos.domingoAgendado(app))
        assertTrue(servidor.a("mypump_registrar_push").isEmpty())
    }

    /** Al quedarse sin cuenta (el link venció) o al salir de la cuenta no queda nada agendado (hallazgo 8 del 15-oct). */
    @Test
    fun alQuedarseSinCuentaSeCancelaElDomingo() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        CentroAvisos.programarDomingo(app)
        assertTrue(CentroAvisos.domingoAgendado(app))
        guardarCuenta("linkVencidoDePrueba_00000000")
        abrir().also {
            p.nodo(etiqueta("link-vencido"))
            p.esperar("cancelado") { !CentroAvisos.domingoAgendado(app) }
            assertNull(CentroAvisos.domingoPendiente(app))
        }.close()
        // Con una cuenta que anda: al salir de la cuenta.
        reiniciarEstado()
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("pestana-entreno"))
        p.esperar("agendado con la cuenta") { CentroAvisos.domingoAgendado(app) }
        instr.runOnMainSync { CentroAvisos.modeloVivo?.salir() }
        p.esperar("cancelado al salir") { !CentroAvisos.domingoAgendado(app) }
        assertNull(CentroAvisos.domingoPendiente(app))
    }

    /**
     * La alarma del domingo publica un mensaje de Mati y NO agenda el de la semana que viene (hallazgo 8 del 15-oct: a quien
     * dejó la app o tiene el link vencido le llegaba para siempre); sin cuenta, nada.
     */
    @Test
    fun alSonarElDomingoPublicaYNoAgendaOtro() {
        AvisosDePrueba.concederDeVerdad(app)
        guardarCuenta()
        CentroAvisos.programarDomingo(app)
        assertNotNull(CentroAvisos.domingoPendiente(app))
        ReceptorAvisos().onReceive(app, Intent(app, ReceptorAvisos::class.java).setAction(CentroAvisos.ACCION_DOMINGO))
        val n = publicado(CentroAvisos.ETIQUETA, CentroAvisos.ID_DOMINGO).notification
        assertEquals("Mati", n.extras.getString(Notification.EXTRA_TITLE))
        // De una vez: ni alarma ni pendiente, y un reinicio no inventa otro.
        assertFalse(CentroAvisos.domingoAgendado(app))
        assertNull(CentroAvisos.domingoPendiente(app))
        assertTrue(alarmasPendientes().none { "AVISO_DOMINGO" in it })
        ReceptorAvisos().onReceive(app, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertFalse(CentroAvisos.domingoAgendado(app))
        // Sin cuenta: ni se publica ni queda agendado.
        nm.cancelAll()
        reiniciarEstado()
        CentroAvisos.programarDomingo(app)
        ReceptorAvisos().onReceive(app, Intent(app, ReceptorAvisos::class.java).setAction(CentroAvisos.ACCION_DOMINGO))
        p.quieto(500)
        assertTrue(AvisosDePrueba.publicadas(app).isEmpty())
        assertFalse(CentroAvisos.domingoAgendado(app))
    }

    /**
     * Al prender el teléfono, al actualizar la app y al cambiar la zona o la hora se vuelve a armar SOLO el que estaba
     * pendiente (hallazgo 8 del 15-oct): sin uno anotado no se inventa otro, y sin cuenta o sin permiso no queda nada. Que
     * con otra zona son las 11:00 de allá lo prueban los de la JVM (`AgendaAvisosTest`).
     */
    @Test
    fun elSistemaVuelveAArmarSoloElPendiente() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        guardarCuenta()
        val delSistema = listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED)
        // Sin uno pendiente (sonó y la app no se volvió a abrir): nada.
        for (accion in delSistema) {
            ReceptorAvisos().onReceive(app, Intent(accion))
            assertFalse(accion, CentroAvisos.domingoAgendado(app))
        }
        // Con uno pendiente que se llevó el reinicio: el mismo domingo, otra vez (y uno solo).
        CentroAvisos.programarDomingo(app)
        val anotado = CentroAvisos.domingoPendiente(app)
        assertNotNull(anotado)
        for (accion in delSistema) {
            perderLaAlarma()
            assertFalse(CentroAvisos.domingoAgendado(app))
            ReceptorAvisos().onReceive(app, Intent(accion))
            assertTrue(accion, CentroAvisos.domingoAgendado(app))
            assertEquals(accion, anotado, CentroAvisos.domingoPendiente(app))
        }
        assertEquals(1, alarmasPendientes().count { "AVISO_DOMINGO" in it })
        // Sin permiso: nada.
        PermisoDePrueba.estado = PermisoAvisos.NEGADO
        ReceptorAvisos().onReceive(app, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertFalse(CentroAvisos.domingoAgendado(app))
        assertNull(CentroAvisos.domingoPendiente(app))
        // Sin cuenta: nada.
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        CentroAvisos.programarDomingo(app)
        reiniciarEstado()
        guardarPreferencia(CentroAvisos.CLAVE_DOMINGO, anotado!!)
        ReceptorAvisos().onReceive(app, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertFalse(CentroAvisos.domingoAgendado(app))
        assertNull(CentroAvisos.domingoPendiente(app))
    }

    /** Es de una vez y se vuelve a armar cada vez que la app vuelve a primer plano con la cuenta (hallazgo 8 del 15-oct). */
    @Test
    fun alVolverAPrimerPlanoSeVuelveAArmar() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        guardarCuenta()
        val escenario = abrir()
        p.nodo(etiqueta("pestana-entreno"))
        p.esperar("el aviso del domingo agendado") { CentroAvisos.domingoAgendado(app) }
        // Sonó con la app en segundo plano: no queda ninguno.
        escenario.moveToState(Lifecycle.State.CREATED)
        ReceptorAvisos().onReceive(app, Intent(app, ReceptorAvisos::class.java).setAction(CentroAvisos.ACCION_DOMINGO))
        assertFalse(CentroAvisos.domingoAgendado(app))
        // Vuelve a la app (sin un arranque nuevo): el domingo que viene, otra vez.
        escenario.moveToState(Lifecycle.State.RESUMED)
        p.esperar("armado de nuevo al volver") { CentroAvisos.domingoAgendado(app) }
        assertNotNull(CentroAvisos.domingoPendiente(app))
        // Si sacó el permiso en Ajustes, al volver no queda nada.
        escenario.moveToState(Lifecycle.State.CREATED)
        PermisoDePrueba.estado = PermisoAvisos.NEGADO
        escenario.moveToState(Lifecycle.State.RESUMED)
        p.esperar("cancelado sin permiso") { !CentroAvisos.domingoAgendado(app) }
    }

    /** Lo que hace un reinicio: el sistema se lleva la alarma, y lo anotado queda. */
    private fun perderLaAlarma() {
        val pi = PendingIntent.getBroadcast(
            app, CentroAvisos.ID_DOMINGO, Intent(app, ReceptorAvisos::class.java).setAction(CentroAvisos.ACCION_DOMINGO),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE,
        ) ?: return
        app.getSystemService(AlarmManager::class.java).cancel(pi)
        pi.cancel()
    }

    /** Un token nuevo de FCM se registra aunque la app esté cerrada (con la cuenta guardada); en la demo, no. */
    @Test
    fun unTokenNuevoSeRegistraConLaCuentaYNuncaEnLaDemo() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        guardarCuenta()
        ServicioDePrueba(app).onNewToken("fcmNuevoDePrueba:0002")
        val registro = servidor.a("mypump_registrar_push").single()
        assertTrue(registro, "\"p_device\":\"fcmNuevoDePrueba:0002\"" in registro)
        assertTrue(registro, "\"p_plataforma\":\"android\"" in registro)
        // Con la app abierta en la demo, no.
        reiniciarEstado()
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.nodo(texto("Estás viendo la demo"))
        ServicioDePrueba(app).onNewToken("fcmNuevoDePrueba:0003")
        assertEquals(1, servidor.a("mypump_registrar_push").size)
        // Sin permiso, tampoco.
        PermisoDePrueba.estado = PermisoAvisos.SIN_PEDIR
        guardarCuenta()
        ServicioDePrueba(app).onNewToken("fcmNuevoDePrueba:0004")
        assertEquals(1, servidor.a("mypump_registrar_push").size)
    }

    // ── NOT-08: lo que dejó la Capacitor ──

    @Test
    fun loQueDejoLaCapacitorSeBorraYLoNuestroQueda() {
        AvisosDePrueba.concederDeVerdad(app)
        val am = app.getSystemService(AlarmManager::class.java)
        // Como la Capacitor: su canal "default", sus alarmas (Intent explícito a TimedNotificationPublisher, el id como
        // código, CANCEL_CURRENT y sus extras, con MUTABLE solo desde Android 12 como su plugin: la bandera es parte del
        // PendingIntent, y con ella en Android 9 la alarma ya no era la de la Capacitor) y lo que llegó a publicar, sin etiqueta.
        val mutable = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        nm.createNotificationChannel(NotificationChannel(CentroAvisos.CANAL_CAPACITOR, "Default", NotificationManager.IMPORTANCE_DEFAULT))
        val publicador = ComponentName(app.packageName, CentroAvisos.PUBLICADOR_CAPACITOR)
        for (id in 1001..1004) {
            val intent = Intent().setComponent(publicador).putExtra("LocalNotificationId", id).putExtra("NotificationPublisher.cron", "1 11 * * *")
            val pi = PendingIntent.getBroadcast(app, id, intent, PendingIntent.FLAG_CANCEL_CURRENT or mutable)
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + 3 * 86_400_000L, pi)
            nm.notify(id, Notification.Builder(app, CentroAvisos.CANAL_CAPACITOR).setSmallIcon(R.drawable.ic_stat_mypump).setContentTitle("Tu revisión de la semana").build())
        }
        // El nuestro: el mismo 1002, con etiqueta.
        CentroAvisos.mostrarDomingo(app)
        p.esperar("las cinco publicadas") { AvisosDePrueba.publicadas(app).size == 5 }
        assertEquals(4, alarmasPendientes().count { "TimedNotificationPublisher" in it })
        // Lo que manda el sistema después de actualizar la app.
        ReceptorAvisos().onReceive(app, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))
        for (id in 1001..1004) {
            assertNull("quedó la alarma $id", PendingIntent.getBroadcast(app, id, Intent().setComponent(publicador), PendingIntent.FLAG_NO_CREATE or mutable))
        }
        assertTrue(alarmasPendientes().none { "TimedNotificationPublisher" in it })
        p.esperar("solo el nuestro") { AvisosDePrueba.publicadas(app).map { it.tag to it.id } == listOf(CentroAvisos.ETIQUETA to CentroAvisos.ID_DOMINGO) }
        assertNull(nm.getNotificationChannel(CentroAvisos.CANAL_CAPACITOR))
    }

    // ── NOT-07: el canal, el ícono y el permiso ──

    @Test
    fun elManifestTraeElCanalElIconoYNingunaAlarmaExacta() {
        @Suppress("DEPRECATION")
        val meta = app.packageManager.getApplicationInfo(app.packageName, PackageManager.GET_META_DATA).metaData
        assertEquals(CentroAvisos.CANAL_MENSAJES, meta.getString("com.google.firebase.messaging.default_notification_channel_id"))
        assertEquals(R.drawable.ic_stat_mypump, meta.getInt("com.google.firebase.messaging.default_notification_icon"))
        assertEquals(R.color.aviso_acento, meta.getInt("com.google.firebase.messaging.default_notification_color"))
        assertFalse("sin token hasta que haga falta", meta.getBoolean("firebase_messaging_auto_init_enabled", true))
        @Suppress("DEPRECATION")
        val pedidos = app.packageManager.getPackageInfo(app.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions!!.toSet()
        assertTrue("android.permission.POST_NOTIFICATIONS" in pedidos)
        assertTrue("android.permission.RECEIVE_BOOT_COMPLETED" in pedidos)
        assertFalse("android.permission.SCHEDULE_EXACT_ALARM" in pedidos)
        assertFalse("android.permission.USE_EXACT_ALARM" in pedidos)
        // Los canales: los mensajes de Mati y el fin del descanso, aparte, con banner.
        CentroAvisos.crearCanales(app)
        val mensajes = nm.getNotificationChannel(CentroAvisos.CANAL_MENSAJES)
        assertEquals("Mensajes de Mati", mensajes.name.toString())
        assertEquals(NotificationManager.IMPORTANCE_HIGH, mensajes.importance)
        assertNotNull(nm.getNotificationChannel(CentroAvisos.CANAL_DESCANSO))
        // El ícono chico es un vector monocromo: solo blanco sobre transparente (la barra de estado usa la transparencia).
        val b = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
        app.getDrawable(R.drawable.ic_stat_mypump)!!.apply { setBounds(0, 0, 96, 96) }.draw(Canvas(b))
        var pintados = 0
        for (x in 0 until 96) for (y in 0 until 96) {
            val px = b.getPixel(x, y)
            if (Color.alpha(px) == 0) continue
            pintados++
            assertTrue("($x,$y) no es blanco: ${Integer.toHexString(px)}", Color.red(px) > 240 && Color.green(px) > 240 && Color.blue(px) > 240)
        }
        assertTrue("el ícono quedó vacío", pintados > 96 * 96 / 10)
        b.recycle()
    }

    // ── Mis datos ──

    @Test
    fun misDatosOfreceActivarSiFaltaElPermiso() {
        PermisoDePrueba.estado = PermisoAvisos.SIN_PEDIR
        PermisoDePrueba.respuesta = true
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(texto("Notificaciones"))
        p.nodo(texto("Activar notificaciones"))
        p.nodo(texto("Para que te lleguen los mensajes de Mati."))
        // Sin interruptores de recordatorios: el aviso del domingo no se configura (D15).
        assertFalse(p.existe(textoQueContiene("ecordatorio")))
        Telefono.captura("24-mis-datos-notificaciones-claro")
        p.tocar(etiqueta("activar-notificaciones"))
        p.esperarQueNoEste(etiqueta("seccion-notificaciones"))
        assertEquals(1, CentroAvisos.pedidos)
        assertTrue(CentroAvisos.domingoAgendado(app))
        p.esperar("el registro del push") { servidor.a("mypump_registrar_push").firstOrNull() }
    }

    @Test
    fun misDatosConElPermisoNegadoLlevaAAjustes() {
        PermisoDePrueba.estado = PermisoAvisos.NEGADO
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(texto("Activar en Ajustes"))
        p.nodo(texto("Las notificaciones de Pump Team están apagadas en el teléfono: los mensajes de Mati no te van a llegar hasta que las prendas."))
        Telefono.captura("25-mis-datos-ajustes-claro")
        p.tocar(etiqueta("activar-notificaciones"))
        // Abre los ajustes del teléfono, no la hoja.
        p.esperar("los ajustes") { "settings" in Telefono.shell("dumpsys activity activities").lines().firstOrNull { "ResumedActivity" in it }.orEmpty() }
        assertEquals(0, CentroAvisos.pedidos)
        Telefono.shell("input keyevent KEYCODE_BACK")
    }

    @Test
    fun conPermisoOEnLaDemoNoHaySeccion() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        guardarCuenta()
        abrir().also {
            p.tocar(etiqueta("pestana-revision"))
            p.tocar(etiqueta("mis-datos"))
            p.nodo(etiqueta("tema-oscuro"))
            assertFalse(p.existe(etiqueta("seccion-notificaciones")))
        }.close()
        reiniciarEstado()
        PermisoDePrueba.estado = PermisoAvisos.SIN_PEDIR
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("tema-oscuro"))
        assertFalse(p.existe(etiqueta("seccion-notificaciones")))
    }

    // ── D8: el fin del descanso con la app en segundo plano ──

    @Test
    fun elFinDelDescansoAvisaEnSegundoPlanoYSeCancelaAlVolver() {
        AvisosDePrueba.concederDeVerdad(app)
        val escenario = abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("ejercicio-ex_010"))
        p.nodo(etiqueta("tabla-series"))
        p.escribir(etiqueta("campo-reps-1"), "10")
        p.escribir(etiqueta("campo-kg-1"), "60")
        p.tocar(etiqueta("confirmar-serie-1"))
        p.nodo(etiqueta("descanso"))
        // A segundo plano con el descanso corriendo: queda la alarma del fin.
        escenario.moveToState(Lifecycle.State.CREATED)
        p.esperar("la alarma del fin") { CentroAvisos.finDescansoAgendado(app) }
        // Para la evidencia: la ventana que le da el sistema a una alarma inexacta (lo que puede tardar con la pantalla apagada).
        println("Avisos: ${alarmasPendientes().filter { "FIN_DESCANSO" in it }}")
        // De vuelta a la app: ni alarma ni aviso.
        escenario.moveToState(Lifecycle.State.RESUMED)
        p.esperar("sin la alarma") { !CentroAvisos.finDescansoAgendado(app) }
        // Que termine en segundo plano (quedan entre 6 y 20 s: cada toque resta 15): el aviso sale, sin el pitido encima.
        // Se espera a ver cada toque: recién vuelta a primer plano, la barra puede tardar en pintar el anterior.
        while (true) {
            val s = segundos()
            if (s <= 20) break
            p.tocar(etiqueta("descanso-menos"))
            p.esperar("−15 desde $s") { segundos() <= s - 14 }
        }
        val sonidos = SonidoDescanso.reproducciones
        val fin = System.currentTimeMillis() + segundos() * 1000L
        escenario.moveToState(Lifecycle.State.CREATED)
        p.esperar("la alarma, por si el proceso se cierra") { CentroAvisos.finDescansoAgendado(app) }
        val sbn = p.esperar("el aviso del fin", ms = 45_000) {
            AvisosDePrueba.publicadas(app).firstOrNull { it.tag == CentroAvisos.ETIQUETA && it.id == CentroAvisos.ID_DESCANSO }
        }
        // Con el proceso vivo sale desde el reloj del descanso: en el segundo (el reloj redondea para arriba).
        println("Avisos: el fin del descanso salió a los ${sbn.postTime - fin} ms (con el proceso vivo)")
        assertTrue("salió a los ${sbn.postTime - fin} ms del fin", sbn.postTime - fin in -1_500L..3_000L)
        val n = sbn.notification
        assertEquals("Terminó el descanso", n.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Seguí con la próxima serie.", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals(CentroAvisos.CANAL_DESCANSO, n.channelId)
        assertEquals("sin pitido en segundo plano", sonidos, SonidoDescanso.reproducciones)
        // Al volver se saca.
        escenario.moveToState(Lifecycle.State.RESUMED)
        p.esperar("sin el aviso") { AvisosDePrueba.publicadas(app).none { it.id == CentroAvisos.ID_DESCANSO } }
    }

    /**
     * Sin la app (el proceso que el sistema cerró, o la pantalla apagada): la alarma inexacta publica el aviso. Anota cuánto
     * tardó después del fin, que es lo que se documenta (sin `SCHEDULE_EXACT_ALARM` el sistema puede correrla).
     */
    @Test
    fun laAlarmaDelFinDelDescansoAvisaSinLaApp() {
        AvisosDePrueba.concederDeVerdad(app)
        CentroAvisos.enPrimerPlano = false
        val fin = System.currentTimeMillis() + 5_000
        CentroAvisos.programarFinDescanso(app, fin)
        assertTrue(CentroAvisos.finDescansoAgendado(app))
        val sbn = p.esperar("el aviso por la alarma", ms = 90_000) {
            AvisosDePrueba.publicadas(app).firstOrNull { it.tag == CentroAvisos.ETIQUETA && it.id == CentroAvisos.ID_DESCANSO }
        }
        println("Avisos: la alarma del fin del descanso llegó a los ${sbn.postTime - fin} ms (setAndAllowWhileIdle, pantalla prendida)")
        assertTrue(sbn.postTime >= fin)
        assertFalse("la alarma ya no está", CentroAvisos.finDescansoAgendado(app))
        // Volver a la app lo saca (el sistema lo saca un instante después).
        CentroAvisos.cancelarFinDescanso(app)
        p.esperar("sin el aviso") { AvisosDePrueba.publicadas(app).none { it.id == CentroAvisos.ID_DESCANSO } }
    }

    private fun segundos(): Int {
        val t = p.textosBajo(etiqueta("descanso-tiempo")).single()
        val (m, s) = t.split(":").map { it.toInt() }
        return m * 60 + s
    }

    /** El servicio de FCM armado a mano con el contexto de la app (sin que lo levante el sistema). */
    private class ServicioDePrueba(base: Context) : ServicioPush() {
        init {
            attachBaseContext(base)
        }
    }
}
