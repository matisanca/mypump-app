package com.pumpteam.mypump.entreno

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.reglas.Verosimilitud
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import kotlin.math.truncate

/** Cuánto hay que deslizar para sumar o restar una repetición. */
private val ESCALON = 26.dp
internal const val TOPE_POR_ARRASTRE = 5

/**
 * El dial de repeticiones (gemelo de DialReps.swift): el número grande con el anterior y el siguiente apenas visibles.
 * Deslizar hacia arriba suma y hacia abajo resta, de a una por escalón; los botones de al lado hacen lo mismo y son la forma
 * accesible. Con TalkBack es un control ajustable. Vive en el panel, fuera de lo que se desplaza: no compite con el scroll.
 */
@Composable
fun DialReps(
    reps: Int?,
    /** Lo marcado respecto de la base: +1, −2; null si coincide. */
    diferencia: Int?,
    /** «La vez pasada» o «Según el plan». */
    referencia: String?,
    alCambiar: (Int) -> Unit,
) {
    val haptico = LocalHapticFeedback.current
    val cambiar by rememberUpdatedState(alCambiar)
    val vibrar = { haptico.performHapticFeedback(HapticFeedbackType.SegmentTick) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        BotonDial(Iconos.Menos, "Restar una repetición", "reps-menos") { cambiar(-1); vibrar() }
        Rueda(reps, diferencia, referencia, Modifier.weight(1f), alCambiar = { cambiar(it); vibrar() })
        BotonDial(Iconos.Mas, "Sumar una repetición", "reps-mas") { cambiar(1); vibrar() }
    }
}

@Composable
private fun BotonDial(icono: ImageVector, etiqueta: String, id: String, alTocar: () -> Unit) {
    val c = MyPump.colores
    Box(
        Modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(c.campo)
            .clickable(role = Role.Button, onClick = alTocar)
            .semantics { contentDescription = etiqueta }
            .testTag(id),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icono, contentDescription = null, tint = c.texto, modifier = Modifier.size(24.dp))
    }
}

@Composable
private fun Rueda(reps: Int?, diferencia: Int?, referencia: String?, modifier: Modifier, alCambiar: (Int) -> Unit) {
    val c = MyPump.colores
    val densidad = LocalDensity.current
    val alcance = rememberCoroutineScope()
    val reducir = reducirMovimiento()
    val escalon = with(densidad) { ESCALON.toPx() }
    val cambiar by rememberUpdatedState(alCambiar)
    // El arrastre acumulado, los pasos ya aplicados y lo que se ve desplazado el número (entre escalón y escalón).
    var acumulado by remember { mutableFloatStateOf(0f) }
    var aplicados by remember { mutableIntStateOf(0) }
    val desplazamiento = remember { Animatable(0f) }
    val estado = rememberDraggableState { delta ->
        acumulado += delta
        // U2 (auditoría del 10/11): un desplazamiento largo con el pulgar sobre el dial llevaba las reps de 10 a 46. Un
        // arrastre mueve como mucho TOPE_POR_ARRASTRE; para más, se suelta y se vuelve a arrastrar.
        val pasos = truncate(-acumulado / escalon).toInt().coerceIn(-TOPE_POR_ARRASTRE, TOPE_POR_ARRASTRE)
        if (pasos != aplicados) {
            cambiar(pasos - aplicados)
            aplicados = pasos
        }
        if (!reducir) alcance.launch { desplazamiento.snapTo((acumulado + pasos * escalon).coerceIn(-escalon, escalon)) }
    }
    // Con letra grande o una pantalla baja, sin los números de al lado: el panel no puede comerse la pantalla.
    val letraGrande = densidad.fontScale >= 1.3f
    val pantallaBaja = LocalConfiguration.current.screenHeightDp < 700
    val conFantasmas = !letraGrande && !pantallaBaja
    val valorTexto = reps?.toString() ?: "—"
    val altoNumero = if (letraGrande) 76.dp else 62.dp
    val actual by rememberUpdatedState(reps)

    Column(
        modifier
            .draggable(
                estado,
                Orientation.Vertical,
                onDragStopped = {
                    // También corre si el sistema cancela el gesto: lo aplicado no puede quedar arrastrado al próximo.
                    acumulado = 0f
                    aplicados = 0
                    desplazamiento.animateTo(0f, spring(stiffness = 700f))
                },
            )
            .testTag("reps-dial")
            .clearAndSetSemantics {
                contentDescription = "Repeticiones"
                stateDescription = listOfNotNull(valorTexto, referencia).joinToString(", ")
                progressBarRangeInfo = ProgressBarRangeInfo((reps ?: 1).toFloat(), 1f..Verosimilitud.REPS_MAX.toFloat(), Verosimilitud.REPS_MAX.toInt() - 2)
                // TalkBack ajusta de a un paso con el deslizamiento o las teclas de volumen.
                setProgress { objetivo ->
                    val ahora = (actual ?: 1).toFloat()
                    if (objetivo != ahora) cambiar(if (objetivo > ahora) 1 else -1)
                    true
                }
                customActions = listOf(
                    CustomAccessibilityAction("Sumar una repetición") { cambiar(1); true },
                    CustomAccessibilityAction("Restar una repetición") { cambiar(-1); true },
                )
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(if (conFantasmas) altoNumero + 40.dp else altoNumero).clipToBounds(), contentAlignment = Alignment.Center) {
            Column(
                Modifier.offset { IntOffset(0, desplazamiento.value.roundToInt()) },
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (conFantasmas) Fantasma(reps?.let { maxOf(it - 1, 0) }, visible = (reps ?: 1) > 1)
                Box(Modifier.height(altoNumero), contentAlignment = Alignment.Center) {
                    Text(valorTexto, style = Numeros.gigante.copy(fontSize = 52.sp).merge(Letras.cifras), color = c.texto, maxLines = 1)
                }
                if (conFantasmas) Fantasma(reps?.plus(1), visible = true)
            }
            if (diferencia != null) {
                Text(
                    if (diferencia > 0) "+$diferencia" else "−${-diferencia}",
                    style = Letras.caption.copy(fontWeight = FontWeight.Bold).merge(Letras.cifras),
                    color = if (diferencia > 0) c.marcaTexto else c.textoSecundario,
                    modifier = Modifier
                        .align(Alignment.CenterEnd)
                        .padding(end = 4.dp)
                        .clip(CircleShape)
                        .background(if (diferencia > 0) c.marcaSuave else c.campo)
                        .padding(horizontal = 8.dp, vertical = 3.dp),
                )
            }
        }
        Text(
            referencia ?: " ",
            style = Letras.caption,
            color = c.textoSecundario,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun Fantasma(n: Int?, visible: Boolean) {
    Box(Modifier.height(20.dp), contentAlignment = Alignment.Center) {
        if (visible && n != null) {
            Text("$n", style = Numeros.chico.merge(Letras.cifras), color = MyPump.colores.textoTerciario, maxLines = 1)
        }
    }
}
