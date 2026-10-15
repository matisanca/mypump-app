package com.pumpteam.mypump.ui

import android.app.NotificationManager
import android.content.Context
import android.service.notification.StatusBarNotification
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.avisos.PermisoDePrueba

/**
 * Los avisos en las pruebas de interfaz: nunca Firebase de verdad (el token es inventado y lo registra el
 * [ServidorDePrueba]), y al terminar no queda nada agendado ni publicado.
 *
 * El permiso: darlo de verdad (`pm grant`) no mata el proceso, sacarlo sí (y con él, la prueba). Las pruebas que necesitan
 * "sin permiso" lo fijan en [PermisoDePrueba]; las que miran lo publicado lo dan de verdad ([concederDeVerdad]), porque el
 * sistema descarta en silencio lo que se publica sin permiso.
 */
object AvisosDePrueba {
    /** El token de FCM de las pruebas (inventado: no es de ningún teléfono). */
    const val TOKEN_PUSH = "fcmDePruebaAndroid:0001"

    fun preparar() {
        CentroAvisos.tokenDePrueba = TOKEN_PUSH
        CentroAvisos.pedidos = 0
        PermisoDePrueba.estado = null
        PermisoDePrueba.respuesta = null
    }

    fun soltar(app: Context) {
        PermisoDePrueba.estado = null
        PermisoDePrueba.respuesta = null
        CentroAvisos.cancelarDomingo(app)
        CentroAvisos.cancelarFinDescanso(app)
        app.getSystemService(NotificationManager::class.java)?.cancelAll()
        CentroAvisos.tokenDePrueba = null
    }

    fun concederDeVerdad(app: Context) {
        Telefono.shell("pm grant ${app.packageName} android.permission.POST_NOTIFICATIONS")
    }

    /** Lo que la app tiene publicado ahora. */
    fun publicadas(app: Context): List<StatusBarNotification> =
        app.getSystemService(NotificationManager::class.java)?.activeNotifications?.toList() ?: emptyList()
}
