package com.pumpteam.mypump

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.diseno.TemaMyPump
import com.pumpteam.mypump.diseno.temaOscuro
import com.pumpteam.mypump.fotosinicio.FotoSinteticaFotosInicio
import com.pumpteam.mypump.raiz.RaizMyPump
import com.pumpteam.mypump.salud.PermisosHealthConnect

/**
 * La entrada de la app. Se llama `.MainActivity` como en la Capacitor a propósito: el launcher guarda el ícono del
 * cliente por nombre de componente, y al actualizar desde la 1.0.x no tiene que desaparecer.
 *
 * Hace lo de `RaizApp` de iOS con el modelo: el link del coach entra la cuenta, y los sondeos corren solo con la app a la
 * vista (al volver se mandan las colas y se recarga lo "de hoy" si cambió el día).
 */
class MainActivity : ComponentActivity() {
    private val vm: ModeloAppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Salud: el contrato de la hoja de permisos de Health Connect se registra acá (Android no deja hacerlo después de
        // crear la Activity); `FuenteHealthConnect.pedirLectura` lo usa desde cualquier pantalla.
        PermisosHealthConnect.registrar(this)
        enableEdgeToEdge()
        // Solo la primera vez: al rotar la pantalla el intent es el mismo y la cuenta ya entró.
        if (savedInstanceState == null) abrirLink(intent)
        // Solo en las builds de prueba: `adb shell am start … --ez elegirHorario true` prende la palanca de la videollamada
        // para probar y sacar capturas (como `-elegirHorario YES` en iPhone). En la de la tienda no existe.
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0 && intent?.hasExtra("elegirHorario") == true) {
            com.pumpteam.mypump.guia.Videollamada.forzada = intent.getBooleanExtra("elegirHorario", false)
        }
        // Avisos: tocar uno con la app cerrada la abre en su pestaña (NOT-03, arranque en frío).
        if (savedInstanceState == null) abrirAviso(intent)
        // Fotos de inicio en modo de prueba: solo en un build de depuración (`adb shell am start … --es fotosInicioDePrueba buena`).
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            intent?.getStringExtra("fotosInicioDePrueba")?.takeIf { it in FotoSinteticaFotosInicio.escenarios }?.let { Entorno.fotosInicioDePrueba = it }
        }
        lifecycle.addObserver(
            LifecycleEventObserver { _, evento ->
                when (evento) {
                    Lifecycle.Event.ON_START -> vm.primerPlano(true)
                    Lifecycle.Event.ON_STOP -> vm.primerPlano(false)
                    else -> {}
                }
            },
        )
        setContent {
            val oscuroGuardado by vm.apariencia.oscuroGuardado.collectAsStateWithLifecycle()
            val oscuro = temaOscuro(isSystemInDarkTheme(), oscuroGuardado)
            // Los íconos de la barra de estado van con el tema de la APP: con "Siempre en modo oscuro" y el teléfono en
            // claro, quedarían negros sobre negro.
            LaunchedEffect(oscuro) {
                val estilo = if (oscuro) SystemBarStyle.dark(Color.TRANSPARENT) else SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                enableEdgeToEdge(statusBarStyle = estilo, navigationBarStyle = estilo)
            }
            TemaMyPump(oscuro = oscuro) {
                RaizMyPump(vm)
            }
        }
    }

    /** `singleTask`: con la app abierta, tocar otro link llega acá. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        abrirLink(intent)
        abrirAviso(intent)
    }

    private fun abrirLink(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        intent.dataString?.let(vm::abrirLink)
    }

    /**
     * Avisos: un aviso propio (`ACCION_AVISO`) o un push que mostró FCM con la app en segundo plano trae su `destino` en los
     * extras. Desde Recientes el intent es el de la primera vez: no vuelve a cambiar de pestaña.
     */
    private fun abrirAviso(intent: Intent?) {
        if (intent == null || intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        CentroAvisos.destinoDe(intent)?.let(vm::abrirAviso)
    }
}
