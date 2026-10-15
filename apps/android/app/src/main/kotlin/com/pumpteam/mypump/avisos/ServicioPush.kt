package com.pumpteam.mypump.avisos

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.pumpteam.mypump.datos.DestinoAviso

/**
 * El servicio de FCM. Un token nuevo se registra (NOT-01). push.py manda `notification{title, body}` + `data{destino}`: con
 * la app en segundo plano el aviso lo muestra el sistema con lo que dice el manifest (canal, ícono y color) y tocarlo trae
 * el `destino` en los extras; con la app abierta FCM no lo muestra y llega acá, y lo publica la app igual (NOT-04, el
 * `willPresent` de iOS). Un mensaje sin texto no se muestra.
 *
 * `open`: la prueba de instrumentación lo arma con el contexto de la app para pasarle un `RemoteMessage` hecho a mano.
 */
open class ServicioPush : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        CentroAvisos.alNuevoToken(applicationContext, token)
    }

    override fun onMessageReceived(mensaje: RemoteMessage) {
        val n = mensaje.notification
        CentroAvisos.mostrarPush(
            applicationContext,
            titulo = n?.title ?: mensaje.data["title"],
            cuerpo = n?.body ?: mensaje.data["body"],
            destino = mensaje.data[DestinoAviso.EXTRA_DESTINO],
            idMensaje = mensaje.messageId,
        )
    }
}
