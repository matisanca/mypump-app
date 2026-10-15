package com.pumpteam.mypump.salud

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.PieSeccion
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.AnilloProgreso
import com.pumpteam.mypump.reglas.SaludVista

/**
 * Salud en Mis datos (SAL-09…13), como MisDatosView de iOS: la recuperación de hoy en una fila (el anillo con el score, o
 * qué falta) que abre el detalle (con "Mostrarme el score", "Sincronizar", la conexión con Health Connect y, con 5 toques,
 * el diagnóstico), y "Conectar Health Connect" si todavía no está conectada. Sin cuenta (o en la demo) no existe.
 */
@Composable
fun SeccionSaludMisDatos(modelo: ModeloApp) {
    val salud by modelo.salud.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val s = salud
    if (s == null || esDemo) return
    var detalle by rememberSaveable { mutableStateOf(false) }
    val conectado by s.conectado.collectAsStateWithLifecycle()
    Column(Modifier.padding(horizontal = Espacio.m).testTag("mis-datos-seccion-salud")) {
        Column(Modifier.fillMaxWidth().superficieTarjeta()) {
            ResumenRecuperacion(s, alTocar = { detalle = true })
        }
        if (s.sincronizador != null && !conectado) BotonConectarSalud(s, Modifier.padding(top = Espacio.s))
        PieSeccion("Sueño, pulso, variabilidad y actividad, si mostrar el score, y la conexión con ${s.textos.app}.")
    }
    if (detalle) {
        PantallaSuperpuesta(alCerrar = { detalle = false }) {
            SaludDetallePantalla(s, alVolver = { detalle = false })
        }
    }
}

/**
 * La recuperación de hoy en una fila: el anillo con el score (o los días de calibración) y qué pasa, con lo mismo que
 * muestra la tarjeta de Recuperación.
 */
@Composable
private fun ResumenRecuperacion(s: ModeloSalud, alTocar: () -> Unit) {
    val e = resumen(cardRecuperacion(s), s)
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = alTocar)
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .semantics(mergeDescendants = true) {}
            .testTag("mis-datos-salud"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.m),
    ) {
        AnilloProgreso(e.fraccion, Modifier.size(72.dp), grosor = 7.dp, color = e.color ?: c.sueno) {
            if (e.numero != null) Text(e.numero, style = Numeros.mediano)
            else Icon(e.icono, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(24.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("Recuperación", style = MaterialTheme.typography.titleMedium)
            Text(e.texto, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

private class Resumen(
    val numero: String? = null,
    val icono: ImageVector = IconosSalud.Pulso,
    val fraccion: Double = 0.0,
    val color: Color? = null,
    val texto: String,
)

@Composable
private fun resumen(card: SaludVista.CardRecuperacion, s: ModeloSalud): Resumen = when (card) {
    SaludVista.CardRecuperacion.SinConectar -> Resumen(texto = "Conectá tu reloj o ${s.textos.app}")
    is SaludVista.CardRecuperacion.ConectadoSinScore -> Resumen(icono = IconosSalud.ArenaReloj, texto = card.sinScore.frase(s.textos))
    is SaludVista.CardRecuperacion.Calibrando ->
        Resumen(icono = IconosSalud.Barras, fraccion = card.porcentaje / 100.0, texto = "Calibrando: ${card.dias} de 14 días")
    SaludVista.CardRecuperacion.Oculto -> Resumen(icono = IconosSalud.OjoTachado, texto = "Tenés el score apagado")
    is SaludVista.CardRecuperacion.ConScore -> {
        val score = card.score.fila.score ?: 0
        Resumen(numero = "$score", fraccion = score / 100.0, color = colorBanda(card.score.banda), texto = "$score/100 · ${card.score.bandaTexto}")
    }
}

/**
 * Una pantalla entera por encima de la que la abre (el detalle de salud, el diagnóstico), como un `NavigationLink` o una
 * hoja de iOS: Atrás la cierra. Va en su propia ventana porque Mis datos es una sola columna (la sección no puede
 * reemplazar la pantalla que la contiene); los íconos de la barra de estado siguen el tema de la app.
 */
@Composable
fun PantallaSuperpuesta(alCerrar: () -> Unit, contenido: @Composable () -> Unit) {
    Dialog(onDismissRequest = alCerrar, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val ventana = (LocalView.current.parent as? DialogWindowProvider)?.window
        val oscuro = MyPump.colores.oscuro
        SideEffect {
            ventana?.let { w ->
                w.setDimAmount(0f)
                WindowCompat.getInsetsController(w, w.decorView).apply {
                    isAppearanceLightStatusBars = !oscuro
                    isAppearanceLightNavigationBars = !oscuro
                }
            }
        }
        Box(Modifier.fillMaxSize()) { contenido() }
    }
}

/** Los íconos de la fila de recuperación (trazados de Material Icons, Apache 2.0, como los de `Iconos`). */
internal object IconosSalud {
    private fun icono(nombre: String, trazado: String): ImageVector =
        ImageVector.Builder(name = nombre, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .apply { addPath(pathData = addPathNodes(trazado), fill = SolidColor(Color.Black)) }
            .build()

    /** favorite: sin conectar. */
    val Pulso: ImageVector by lazy {
        icono(
            "Pulso",
            "M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z",
        )
    }

    /** hourglass_empty: conectada, esperando datos. */
    val ArenaReloj: ImageVector by lazy {
        icono(
            "ArenaReloj",
            "M6,2v6h0.01L6,8.01 10,12l-4,4 0.01,0.01H6V22h12v-5.99h-0.01L18,16l-4,-4 4,-3.99 -0.01,-0.01H18V2H6zM16,16.5V20H8v-3.5l4,-4 4,4zM12,11.5l-4,-4V4h8v3.5l-4,4z",
        )
    }

    /** bar_chart: calibrando. */
    val Barras: ImageVector by lazy { icono("Barras", "M5,9.2h3V19H5zM10.6,5h2.8v14h-2.8zM16.2,13H19v6h-2.8z") }

    /** visibility_off: el score apagado. */
    val OjoTachado: ImageVector by lazy {
        icono(
            "OjoTachado",
            "M12,7c2.76,0 5,2.24 5,5 0,0.65 -0.13,1.26 -0.36,1.83l2.92,2.92c1.51,-1.26 2.7,-2.89 3.43,-4.75 -1.73,-4.39 -6,-7.5 -11,-7.5 " +
                "-1.4,0 -2.74,0.25 -3.98,0.7l2.16,2.16C10.74,7.13 11.35,7 12,7zM2,4.27l2.28,2.28 0.46,0.46C3.08,8.3 1.78,10.02 1,12c1.73,4.39 " +
                "6,7.5 11,7.5 1.55,0 3.03,-0.3 4.38,-0.84l0.42,0.42L19.73,22 21,20.73 3.27,3 2,4.27zM7.53,9.8l1.55,1.55c-0.05,0.21 -0.08,0.43 " +
                "-0.08,0.65 0,1.66 1.34,3 3,3 0.22,0 0.44,-0.03 0.65,-0.08l1.55,1.55c-0.67,0.33 -1.41,0.53 -2.2,0.53 -2.76,0 -5,-2.24 -5,-5 " +
                "0,-0.79 0.2,-1.53 0.53,-2.2zM11.84,9.02l3.15,3.15 0.02,-0.16c0,-1.66 -1.34,-3 -3,-3l-0.17,0.01z",
        )
    }
}
