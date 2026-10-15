package com.pumpteam.mypump.salud

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.annotation.VisibleForTesting
import androidx.health.connect.client.HealthConnectClient

/**
 * Si este teléfono puede usar Health Connect, con `HealthConnectClient.getSdkStatus` (el `isAvailable` de la Capacitor):
 *
 * - [DISPONIBLE]: Android 14+ (viene en el sistema) o el APK instalado y al día.
 * - [INSTALAR] / [ACTUALIZAR]: Android 9 a 13 sin el APK, o con uno viejo. Se ofrece desde Google Play.
 * - [NO_SOPORTADO]: Android 8 o un perfil de trabajo que no lo tiene: no se ofrece nada.
 */
enum class EstadoHealthConnect {
    DISPONIBLE, INSTALAR, ACTUALIZAR, NO_SOPORTADO;

    /** Se puede ofrecer: está, o se consigue en Play. */
    val ofrecible: Boolean get() = this != NO_SOPORTADO

    companion object {
        /** El paquete de Health Connect (hasta Android 13 es una app aparte; el del `<queries>` del manifest). */
        const val PAQUETE = "com.google.android.apps.healthdata"

        /** Las pruebas de interfaz fuerzan un estado (sin Health Connect, viejo) sin desinstalar nada del emulador. */
        @VisibleForTesting
        @Volatile
        var forzado: EstadoHealthConnect? = null

        /** Lo que miran las pantallas. */
        fun actual(contexto: Context): EstadoHealthConnect = forzado ?: de(contexto)

        fun de(contexto: Context): EstadoHealthConnect = when (HealthConnectClient.getSdkStatus(contexto)) {
            HealthConnectClient.SDK_AVAILABLE -> DISPONIBLE
            // "Hay que actualizar" también es "no está": se distingue para que el botón diga lo que va a pasar. Ver el
            // paquete necesita el <queries> del manifest (Android 11+).
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> if (instalado(contexto)) ACTUALIZAR else INSTALAR
            else -> NO_SOPORTADO
        }

        private fun instalado(contexto: Context): Boolean = try {
            contexto.packageManager.getPackageInfo(PAQUETE, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }

        /**
         * Health Connect en Google Play, como lo indica Google: con `url=healthconnect://onboarding` Play lo instala (o lo
         * actualiza) y abre su presentación. Sin la app de Play, la página web.
         */
        fun abrirEnPlay(contexto: Context) {
            val enPlay = Intent(Intent.ACTION_VIEW)
                .setPackage("com.android.vending")
                .setData(Uri.parse("market://details?id=$PAQUETE&url=healthconnect%3A%2F%2Fonboarding"))
                .putExtra("overlay", true)
                .putExtra("callerId", contexto.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                contexto.startActivity(enPlay)
            } catch (_: ActivityNotFoundException) {
                try {
                    contexto.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$PAQUETE")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                } catch (_: ActivityNotFoundException) {
                    // Sin Play ni navegador no hay a dónde ir.
                }
            }
        }
    }
}
