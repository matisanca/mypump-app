package com.pumpteam.mypump.diseno

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

private val ALTO_FILA = 36.dp
private const val VISIBLES = 5
private const val VUELTAS = 400

/**
 * La rueda de iOS para elegir la hora (el `DatePicker` de horas y minutos de iOS en rueda), en 24 h: dos columnas que
 * giran sin fin y frenan en un número, la fila elegida en una banda gris que cruza las dos, las de los costados más
 * tenues, y un tic en cada número que pasa. Reemplaza al reloj de agujas de Material. Para TalkBack cada columna es un
 * control ajustable («Horas, 13»: deslizar arriba o abajo suma o resta uno).
 */
@Composable
fun RuedaHora(hora: Int, minuto: Int, alCambiar: (hora: Int, minuto: Int) -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Box(modifier.height(ALTO_FILA * VISIBLES), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(ALTO_FILA)
                .clip(RoundedCornerShape(10.dp))
                .background(c.campo),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Rueda(24, hora, { alCambiar(it, minuto) }, "Horas", Modifier.width(76.dp).testTag("rueda-horas"))
            Text(":", style = estiloNumero, color = c.texto)
            Rueda(60, minuto, { alCambiar(hora, it) }, "Minutos", Modifier.width(76.dp).testTag("rueda-minutos"))
        }
    }
}

private val estiloNumero = TextStyle(fontFamily = Inter, fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum")

@Composable
private fun Rueda(n: Int, valor: Int, alCambiar: (Int) -> Unit, descripcion: String, modifier: Modifier) {
    val c = MyPump.colores
    val estado = rememberLazyListState(initialFirstVisibleItemIndex = n * (VUELTAS / 2) + valor - VISIBLES / 2)
    val alcance = rememberCoroutineScope()
    val haptico = LocalHapticFeedback.current
    val altoPx = with(LocalDensity.current) { ALTO_FILA.toPx() }
    // La fila del medio: la de arriba más dos, o más tres si la de arriba ya subió más de la mitad.
    val centro by remember {
        derivedStateOf { estado.firstVisibleItemIndex + VISIBLES / 2 + if (estado.firstVisibleItemScrollOffset > altoPx / 2) 1 else 0 }
    }
    val elegido = centro.mod(n)
    var avisado by remember { mutableIntStateOf(valor) }
    LaunchedEffect(elegido) {
        if (elegido != avisado) {
            avisado = elegido
            haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
            alCambiar(elegido)
        }
    }
    LazyColumn(
        state = estado,
        flingBehavior = rememberSnapFlingBehavior(estado),
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .height(ALTO_FILA * VISIBLES)
            .clearAndSetSemantics {
                contentDescription = descripcion
                stateDescription = elegido.toString()
                progressBarRangeInfo = ProgressBarRangeInfo(elegido.toFloat(), 0f..(n - 1).toFloat(), steps = n - 2)
                setProgress { v ->
                    val nuevo = v.roundToInt().coerceIn(0, n - 1)
                    alcance.launch { estado.scrollToItem(centro - elegido + nuevo - VISIBLES / 2) }
                    true
                }
            },
    ) {
        items(n * VUELTAS) { i ->
            val distancia = abs(i - centro)
            Box(Modifier.height(ALTO_FILA).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    String.format(Locale.ROOT, "%02d", i.mod(n)),
                    style = estiloNumero,
                    color = if (distancia == 0) c.texto else c.textoSecundario,
                    modifier = Modifier.graphicsLayer {
                        alpha = when (distancia) {
                            0 -> 1f
                            1 -> 0.75f
                            else -> 0.4f
                        }
                        val escala = if (distancia == 0) 1f else 0.92f
                        scaleX = escala
                        scaleY = escala
                    },
                )
            }
        }
    }
}
