package com.pumpteam.mypump.entreno

import android.os.Build
import android.os.SystemClock
import android.view.ViewTreeObserver
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.rellenoInferior

// Salir del peso sin registrar nada (2.3.3, S2; el gemelo en iOS es la barra «Listo» de TarjetaCarga.swift). Tres piezas:
// la barra «Listo» arriba del teclado, tocar afuera del campo suelta el foco, y el OK que espera al volver el panel
// ([EsperaTrasTeclado], en PanelCarga).

/** El reloj de la espera del OK. Las pruebas de interfaz lo cambian por uno que manejan ellas (y lo devuelven al terminar). */
object RelojCarga {
    @Volatile
    var ahora: () -> Long = { SystemClock.uptimeMillis() }
}

/**
 * Qué campo de kilos tiene el foco y dónde están todos en la ventana. Lo comparten la pantalla de Entreno (para soltar el foco
 * al tocar afuera), el panel (que con un kilo en edición muestra «Listo» en lugar del OK) y cada [CampoKilos].
 */
@Stable
class FocoKilos {
    /** El campo con el foco (su ficha), o null. Es estado: el panel se recompone al cambiar. */
    var enfocado by mutableStateOf<Any?>(null)
        internal set
    val activo: Boolean get() = enfocado != null

    /** Dónde está cada campo, en la ventana: un toque adentro de cualquiera no suelta el foco (pasar de un kilo a otro). */
    internal val lugares = HashMap<Any, Rect>()

    internal fun adentro(x: Float, y: Float): Boolean = lugares.values.any { it.contains(androidx.compose.ui.geometry.Offset(x, y)) }
}

val LocalFocoKilos = staticCompositionLocalOf<FocoKilos?> { null }

/**
 * Lo que hace cada [CampoKilos] con [FocoKilos]: avisa si tiene el foco y dónde está. Además, si el teclado se cierra con el
 * Atrás del teléfono (el foco sigue en el campo), suelta el foco: sin eso el panel no vuelve hasta tocar «Listo».
 */
@Composable
internal fun Modifier.registrarCampoKilos(enfocado: Boolean): Modifier {
    val foco = LocalFocoKilos.current ?: return this
    val focoManager = LocalFocusManager.current
    val ficha = remember { Any() }
    LaunchedEffect(enfocado) {
        if (enfocado) foco.enfocado = ficha else if (foco.enfocado === ficha) foco.enfocado = null
    }
    DisposableEffect(ficha) {
        onDispose {
            foco.lugares.remove(ficha)
            if (foco.enfocado === ficha) foco.enfocado = null
        }
    }
    val teclado = tecladoAbierto()
    var vioTeclado by remember { mutableStateOf(false) }
    LaunchedEffect(enfocado, teclado) {
        when {
            !enfocado -> vioTeclado = false
            teclado -> vioTeclado = true
            vioTeclado -> {
                vioTeclado = false
                focoManager.clearFocus()
            }
        }
    }
    return onGloballyPositioned { foco.lugares[ficha] = it.boundsInWindow() }
}

/**
 * Con un kilo en edición, un toque afuera de los campos suelta el foco y el teclado se cierra. Mira el toque al bajar el dedo,
 * antes que los botones, y no lo consume: lo tocado (el + de la carga, el dial) hace lo suyo igual.
 */
@Composable
internal fun Modifier.soltarFocoAlTocarAfuera(foco: FocoKilos): Modifier {
    val focoManager = LocalFocusManager.current
    val dondeEsta = remember { arrayOfNulls<LayoutCoordinates>(1) }
    return this
        .onGloballyPositioned { dondeEsta[0] = it }
        .pointerInput(foco, focoManager) {
            awaitEachGesture {
                val abajo = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                if (!foco.activo) return@awaitEachGesture
                val caja = dondeEsta[0]?.takeIf { it.isAttached } ?: return@awaitEachGesture
                val p = caja.localToWindow(abajo.position)
                if (!foco.adentro(p.x, p.y)) focoManager.clearFocus()
            }
        }
}

/**
 * La barra «Listo» pegada arriba del teclado mientras se escribe un kilo (gemela del `ToolbarItemGroup(placement: .keyboard)`
 * de iOS, con el mismo id `teclado-listo`). Va en el lugar del panel: el OK no está a la vista mientras se escribe.
 */
@Composable
internal fun BarraListoTeclado() {
    val c = MyPump.colores
    val foco = LocalFocusManager.current
    Row(
        Modifier
            .padding(bottom = altoTeclado().takeIf { it > 0.dp } ?: rellenoInferior())
            .fillMaxWidth()
            .background(if (c.oscuro) EstiloCarga.panelOscuro else EstiloCarga.panelClaro)
            .padding(horizontal = Espacio.m, vertical = 6.dp)
            .testTag("barra-teclado"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Text("Escribí el peso y tocá Listo", style = Letras.caption, color = c.textoSecundario, modifier = Modifier.weight(1f))
        Box(
            Modifier
                .heightIn(min = 44.dp)
                .widthIn(min = 96.dp)
                .clip(CircleShape)
                .background(c.marca)
                .clickable(role = Role.Button) { foco.clearFocus() }
                .padding(horizontal = Espacio.m)
                .testTag("teclado-listo"),
            contentAlignment = Alignment.Center,
        ) {
            Text("Listo", style = Numeros.chico.copy(fontWeight = FontWeight.ExtraBold), color = c.sobreMarca)
        }
    }
}

/**
 * Cuánto tapa el teclado desde abajo de la ventana. No es `imePadding()`: las pestañas ya descontaron la barra de navegación
 * y con eso «Listo» quedaba medio tapado (el alto de esa barra). Hasta Android 10 los insets no traen el teclado (sin
 * `adjustResize`): se mide lo que queda visible de la ventana, como en [tecladoAbierto].
 */
@Composable
internal fun altoTeclado(): Dp {
    val densidad = LocalDensity.current
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) return with(densidad) { WindowInsets.ime.getBottom(this).toDp() }
    val vista = LocalView.current
    var alto by remember { mutableIntStateOf(0) }
    DisposableEffect(vista) {
        val medir = ViewTreeObserver.OnGlobalLayoutListener {
            val visible = android.graphics.Rect()
            vista.getWindowVisibleDisplayFrame(visible)
            val total = vista.rootView.height
            val tapado = total - visible.bottom
            alto = if (tapado > total * 0.15f) tapado else 0
        }
        vista.viewTreeObserver.addOnGlobalLayoutListener(medir)
        onDispose { vista.viewTreeObserver.removeOnGlobalLayoutListener(medir) }
    }
    return with(densidad) { alto.toDp() }
}

/** [base] con la letra del teléfono, topeada en [TOPE_LETRA] ([letraConTope]). */
@Composable
internal fun letraTopeada(base: TextUnit): TextUnit = with(LocalDensity.current) { letraConTope(base) }
