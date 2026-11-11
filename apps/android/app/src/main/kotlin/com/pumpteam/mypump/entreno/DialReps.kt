package com.pumpteam.mypump.entreno

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.diseno.Archivo
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.reglas.Verosimilitud
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.truncate

/** Cuánto hay que deslizar para sumar o restar una repetición. */
private val ESCALON = 26.dp
internal const val TOPE_POR_ARRASTRE = 5

/**
 * El dial de repeticiones (gemelo de DialReps.swift): un tambor de números que sigue al dedo de verdad. Deslizar hacia arriba
 * suma y hacia abajo resta, de a una por escalón (como la corona del reloj); las rayitas de los costados son la regla que se
 * mueve con el dedo. Los botones de al lado hacen lo mismo y son la forma accesible; con TalkBack es un control ajustable. Vive
 * en el panel, fuera de lo que se desplaza: no compite con el scroll. Sin tope ni colores de «te pasaste»: son referencia.
 */
@Composable
fun DialReps(
    reps: Int?,
    /** Lo marcado respecto de la base: +1, −2; null si coincide. */
    diferencia: Int?,
    /** «La vez pasada» o «Según el plan». */
    referencia: String?,
    /** La serie: al cambiar, el tambor entra de abajo aunque el número sea el mismo. */
    clave: Int = 0,
    alCambiar: (Int) -> Unit,
) {
    val haptico = LocalHapticFeedback.current
    val cambiar by rememberUpdatedState(alCambiar)
    val alcance = rememberCoroutineScope()
    val densidad = LocalDensity.current
    val escalon = with(densidad) { ESCALON.toPx() }
    val reducir = reducirMovimiento()
    // Lo que se ve corrido el tambor entre escalón y escalón (en px). Lo comparten el arrastre y los botones.
    val desplazamiento = remember { Animatable(0f) }
    val enBase by rememberUpdatedState(diferencia == null && referencia != null)
    // Un escalón, una vibración. Al caer justo en la vez pasada es más firme, como la muesca de una perilla.
    val vibrar = {
        haptico.performHapticFeedback(if (enBase) HapticFeedbackType.GestureThresholdActivate else HapticFeedbackType.SegmentTick)
    }
    val impulso = { d: Int ->
        if (!reducir) alcance.launch {
            desplazamiento.snapTo(d * escalon)
            desplazamiento.animateTo(0f, EstiloCarga.resorteDial())
        }
    }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            BotonCircularCarga(Iconos.Menos, "Restar una repetición", "reps-menos") { cambiar(-1); vibrar(); if (reps != null && reps > 1) impulso(-1) }
            Rueda(reps, referencia, clave, desplazamiento, escalon, Modifier.weight(1f), alCambiar = { cambiar(it); vibrar() })
            BotonCircularCarga(Iconos.Mas, "Sumar una repetición", "reps-mas") { cambiar(1); vibrar(); if (reps != null && reps < Verosimilitud.REPS_MAX.toInt()) impulso(1) }
        }
        FilaReferencia(referencia, diferencia)
    }
}

/** De dónde sale el número y cuánto le sumaste. El alto es fijo: la pastilla aparece sin mover el dial. */
@Composable
private fun FilaReferencia(referencia: String?, diferencia: Int?) {
    val c = MyPump.colores
    Row(
        Modifier.heightIn(min = 22.dp).clearAndSetSemantics {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(referencia ?: " ", style = Letras.caption.copy(fontWeight = FontWeight.Medium), color = c.textoSecundario, maxLines = 1, overflow = TextOverflow.Ellipsis)
        AnimatedContent(diferencia, transitionSpec = { (fadeIn() + scaleIn(initialScale = 0.6f)) togetherWith fadeOut() }, label = "pastilla") { d ->
            if (d != null) {
                Text(
                    if (d > 0) "+$d" else "−${-d}",
                    style = Letras.caption.copy(fontWeight = FontWeight.Bold).merge(Letras.cifras),
                    color = if (d > 0) c.marcaTexto else c.textoSecundario,
                    modifier = Modifier.clip(CircleShape).background(if (d > 0) c.marcaSuave else c.campo).padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
        }
    }
}

@Composable
private fun Rueda(
    reps: Int?,
    referencia: String?,
    clave: Int,
    desplazamiento: Animatable<Float, *>,
    escalon: Float,
    modifier: Modifier,
    alCambiar: (Int) -> Unit,
) {
    val c = MyPump.colores
    val densidad = LocalDensity.current
    val alcance = rememberCoroutineScope()
    val reducir = reducirMovimiento()
    val cambiar by rememberUpdatedState(alCambiar)
    val actual by rememberUpdatedState(reps)
    var acumulado by remember { mutableFloatStateOf(0f) }
    var aplicados by remember { mutableIntStateOf(0) }
    var tocando by remember { mutableIntStateOf(0) }
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
    // Con letra grande, sin los números de al lado: el panel no puede comerse la pantalla.
    val letraGrande = densidad.fontScale >= 1.3f
    val chico = pantallaChica()
    val conVecinos = !letraGrande && reps != null
    val tamano = if (chico) 64f else 76f
    val paso = with(densidad) { (tamano * 0.58f).dp.toPx() }
    val alto = if (conVecinos) (if (chico) 104.dp else 122.dp) else (tamano * 1.15f).dp
    val valorTexto = reps?.toString() ?: "—"
    val escalaToque by animateFloatAsState(if (tocando > 0 && !reducir) 1.03f else 1f, label = "toque")

    // De −1 a 1: cuánto del escalón siguiente ya entró. Contra el borde (1 rep o 300) el tambor se resiste. Se lee recién al
    // dibujar (en los graphicsLayer y el Canvas): así el arrastre y el resorte no recomponen la rueda en cada cuadro.
    val fraccion: () -> Float = {
        val crudo = desplazamiento.value / escalon
        when {
            reducir -> 0f
            crudo > 0 && (actual ?: 2) <= 1 -> crudo * 0.22f
            crudo < 0 && (actual ?: 0) >= Verosimilitud.REPS_MAX.toInt() -> crudo * 0.22f
            else -> crudo
        }
    }
    val estilo = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Black, fontSize = tamano.sp, lineHeight = tamano.sp)

    Box(
        modifier
            .height(alto)
            .graphicsLayer { scaleX = escalaToque; scaleY = escalaToque }
            .draggable(
                estado,
                Orientation.Vertical,
                onDragStarted = { tocando++ },
                onDragStopped = {
                    // También corre si el sistema cancela el gesto: lo aplicado no puede quedar arrastrado al próximo.
                    tocando = 0
                    acumulado = 0f
                    aplicados = 0
                    desplazamiento.animateTo(0f, EstiloCarga.resorteDial())
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
        contentAlignment = Alignment.Center,
    ) {
        if (conVecinos) Regla({ fraccion() * escalon }, escalon, c.texto)
        // El tambor, con los bordes que se apagan. La serie nueva entra de abajo.
        Box(
            Modifier
                .fillMaxSize()
                .clipToBounds()
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .desvanecerBordes(),
            contentAlignment = Alignment.Center,
        ) {
            AnimatedContent(
                clave,
                transitionSpec = {
                    if (reducir) fadeIn() togetherWith fadeOut()
                    else (slideInVertically { it / 2 } + fadeIn() + scaleIn(initialScale = 0.8f)) togetherWith
                        (slideOutVertically { -it / 2 } + fadeOut() + scaleOut(targetScale = 0.8f))
                },
                label = "tambor",
            ) { _ ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    for (k in if (conVecinos) -2..2 else 0..0) {
                        val valor = (reps ?: 0) + k
                        if (k != 0 && (reps == null || valor < 1 || valor > Verosimilitud.REPS_MAX.toInt())) continue
                        Text(
                            if (k == 0) valorTexto else valor.toString(),
                            style = estilo,
                            color = c.texto,
                            maxLines = 1,
                            softWrap = false,
                            modifier = Modifier.graphicsLayer {
                                val d = k + fraccion()
                                val lejos = abs(d)
                                val escala = max(0.3f, 1f - 0.6f * min(lejos, 1f) - 0.1f * max(lejos - 1f, 0f))
                                val opacidad = if (lejos <= 1f) 1f - 0.68f * lejos else max(0f, 0.32f * (2f - lejos))
                                translationY = d * paso
                                scaleX = escala
                                scaleY = escala
                                alpha = opacidad
                                rotationX = -d * 20f
                                cameraDistance = 6f * density
                            },
                        )
                    }
                }
            }
        }
    }
}

/** Arriba y abajo el tambor se apaga, como una rueda que dobla. */
private fun Modifier.desvanecerBordes(): Modifier = drawWithContent {
    drawContent()
    drawRect(
        Brush.verticalGradient(0f to Color.Transparent, 0.1f to Color.Black, 0.9f to Color.Black, 1f to Color.Transparent),
        blendMode = BlendMode.DstIn,
    )
}

/**
 * La regla: una raya por repetición, a los costados del número, que viaja con el dedo. Va pegada al número y no a los botones,
 * y gris: en verde y a su lado se leía como otro «−».
 */
@Composable
private fun Regla(corrimiento: () -> Float, escalon: Float, color: Color) {
    Canvas(Modifier.fillMaxSize()) {
        val centro = size.height / 2
        val margen = 14.dp.toPx()
        val largo = 12.dp.toPx()
        val grosor = 2.5.dp.toPx()
        val resto = corrimiento() % escalon
        val cuantas = (centro / escalon).toInt() + 2
        for (n in -cuantas..cuantas) {
            val y = centro + n * escalon + resto
            val lejania = min(abs(y - centro) / centro, 1f)
            val opacidad = (1f - lejania).pow(1.2f) * 0.42f
            if (opacidad <= 0.01f) continue
            val tinta = color.copy(alpha = opacidad)
            drawLine(tinta, Offset(margen, y), Offset(margen + largo, y), grosor, StrokeCap.Round)
            drawLine(tinta, Offset(size.width - margen, y), Offset(size.width - margen - largo, y), grosor, StrokeCap.Round)
        }
    }
}
