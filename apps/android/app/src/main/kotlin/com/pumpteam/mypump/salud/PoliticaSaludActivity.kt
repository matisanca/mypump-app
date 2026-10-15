package com.pumpteam.mypump.salud

import android.app.Activity
import android.os.Bundle
import com.pumpteam.mypump.acceso.URL_PRIVACIDAD
import com.pumpteam.mypump.diseno.abrirEnNavegador

/**
 * Lo que Health Connect abre cuando el cliente pregunta para qué queremos sus datos: "Leer la política de privacidad" en
 * la hoja de permisos (`androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`, hasta Android 13) y el uso de los permisos
 * desde los ajustes (el `activity-alias` ViewPermissionUsageActivity, Android 14+). Google no publica una app de salud
 * sin las dos.
 *
 * Muestra la política de privacidad de la web en una Custom Tab, como las fuentes y las páginas legales
 * ([abrirEnNavegador]), y se cierra: no tiene pantalla propia (`Theme.NoDisplay`), así Atrás vuelve a Health Connect.
 */
class PoliticaSaludActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        abrirEnNavegador(this, URL_PRIVACIDAD)
        finish()
    }
}
