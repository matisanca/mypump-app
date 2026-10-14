package com.pumpteam.mypump

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.pumpteam.mypump.diseno.TemaMyPump

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
        enableEdgeToEdge()
        // Solo la primera vez: al rotar la pantalla el intent es el mismo y la cuenta ya entró.
        if (savedInstanceState == null) abrirLink(intent)
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
            TemaMyPump {
                Bienvenida()
            }
        }
    }

    /** `singleTask`: con la app abierta, tocar otro link llega acá. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        abrirLink(intent)
    }

    private fun abrirLink(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        intent.dataString?.let(vm::abrirLink)
    }
}

/** Por ahora solo la marca: las pantallas llegan con las etapas de la Fase 5. */
@Composable
fun Bienvenida() {
    Scaffold { relleno ->
        Column(
            modifier = Modifier.fillMaxSize().padding(relleno).padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "MyPump",
                style = MaterialTheme.typography.displayMedium,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = "Pump Team",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun BienvenidaPrevia() {
    TemaMyPump { Bienvenida() }
}
