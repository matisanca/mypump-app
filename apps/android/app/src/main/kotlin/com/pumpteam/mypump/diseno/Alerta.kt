package com.pumpteam.mypump.diseno

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider

/** Un botón de [Alerta]. [cancelar] va a la izquierda en fila y abajo de todo en columna, como en iOS. */
class BotonAlerta(
    val texto: String,
    val etiqueta: String? = null,
    val destructivo: Boolean = false,
    val cancelar: Boolean = false,
    val alTocar: () -> Unit,
)

/**
 * La alerta de iOS 26 (`.alert` y `.confirmationDialog` de MyPump en el iPhone), en lugar del `AlertDialog` de Material
 * (Mati, 15-oct: Android «igual que el iPhone»). Una tarjeta de puntas muy redondeadas sobre un fondo apenas oscurecido,
 * el título y el mensaje alineados a la izquierda, y los botones como cápsulas grises con el texto en el verde de la
 * marca (en rojo el que borra): dos en fila si entran, si no uno debajo del otro. Aparece como en iOS, de un poco más
 * grande a su tamaño. Atrás o tocar afuera es [alDescartar].
 *
 * [contenido] va entre el mensaje y los botones (la rueda de la hora).
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun Alerta(
    titulo: String,
    botones: List<BotonAlerta>,
    alDescartar: () -> Unit,
    modifier: Modifier = Modifier,
    mensaje: String? = null,
    etiquetaMensaje: String? = null,
    contenido: (@Composable () -> Unit)? = null,
) {
    val c = MyPump.colores
    Dialog(onDismissRequest = alDescartar, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        // El oscurecido de Android (0,6) es mucho más fuerte que el de iOS.
        val ventana = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect { ventana?.setDimAmount(if (c.oscuro) 0.45f else 0.2f) }
        val entrada = remember { Animatable(0f) }
        LaunchedEffect(Unit) { entrada.animateTo(1f, tween(220, easing = FastOutSlowInEasing)) }
        val forma = RoundedCornerShape(32.dp)
        val sombra = Color.Black.copy(alpha = if (c.oscuro) 0.5f else 0.18f)
        // Centrada en la ventana del diálogo, sea cual sea el ancho que le dé el sistema. El diálogo es otra ventana: las
        // etiquetas se exponen de nuevo para UiAutomator, como en la raíz.
        Box(Modifier.fillMaxWidth().semantics { testTagsAsResourceId = true }, contentAlignment = Alignment.Center) {
            Column(
                modifier
                    .padding(horizontal = 36.dp)
                    .widthIn(max = 320.dp)
                    .fillMaxWidth()
                    .graphicsLayer {
                        val e = entrada.value
                        alpha = e
                        scaleX = 1.08f - 0.08f * e
                        scaleY = scaleX
                    }
                    .shadow(28.dp, forma, ambientColor = sombra, spotColor = sombra)
                    .clip(forma)
                    .background(if (c.oscuro) Color(0xFF2C2C2E) else Color(0xFFFAFAFA))
                    .border(1.dp, c.borde, forma)
                    .semantics { paneTitle = titulo }
                    .padding(top = 24.dp, bottom = 16.dp),
            ) {
                Column(Modifier.padding(horizontal = 28.dp)) {
                    Text(
                        titulo,
                        style = MaterialTheme.typography.titleMedium,
                        color = c.texto,
                        modifier = Modifier.semantics { heading() },
                    )
                    if (mensaje != null) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            mensaje,
                            style = MaterialTheme.typography.bodyLarge,
                            color = c.textoSecundario,
                            modifier = if (etiquetaMensaje != null) Modifier.testTag(etiquetaMensaje) else Modifier,
                        )
                    }
                }
                if (contenido != null) {
                    Spacer(Modifier.height(12.dp))
                    Box(Modifier.padding(horizontal = 16.dp)) { contenido() }
                }
                Spacer(Modifier.height(20.dp))
                FilaOColumna(espacio = 8.dp, cancelar = botones.map { it.cancelar }, modifier = Modifier.padding(horizontal = 16.dp)) {
                    for (b in botones) BotonCapsula(b)
                }
            }
        }
    }
}

@Composable
private fun BotonCapsula(b: BotonAlerta) {
    val c = MyPump.colores
    Box(
        Modifier
            .heightIn(min = 48.dp)
            .clip(CircleShape)
            .background(c.campo)
            .then(if (b.etiqueta != null) Modifier.testTag(b.etiqueta) else Modifier)
            .clickable(role = Role.Button, onClick = b.alTocar)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            b.texto,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            color = if (b.destructivo) c.peligro else c.marcaTexto,
            textAlign = TextAlign.Center,
        )
    }
}

/**
 * Los botones de la alerta: en fila, del mismo ancho, si son dos y los dos textos entran en su mitad; si no, uno debajo
 * del otro a todo el ancho. Como ordena iOS, el de [cancelar] va a la izquierda en fila y abajo de todo en columna.
 */
@Composable
private fun FilaOColumna(espacio: Dp, cancelar: List<Boolean>, modifier: Modifier = Modifier, contenido: @Composable () -> Unit) {
    Layout(contenido, modifier.fillMaxWidth()) { medibles, restricciones ->
        val hueco = espacio.roundToPx()
        val ancho = restricciones.maxWidth
        val mitad = (ancho - hueco) / 2
        val enFila = medibles.size <= 2 && medibles.all { it.maxIntrinsicWidth(Constraints.Infinity) <= mitad }
        val esCancelar = { i: Int -> cancelar.getOrElse(i) { false } }
        if (enFila) {
            val cada = if (medibles.size == 2) mitad else ancho
            val alto = medibles.maxOfOrNull { it.minIntrinsicHeight(cada) } ?: 0
            val ps = medibles.map { it.measure(Constraints.fixed(cada, alto)) }
            val orden = ps.indices.sortedBy { if (esCancelar(it)) 0 else 1 }
            layout(ancho, alto) {
                var x = 0
                for (i in orden) {
                    ps[i].placeRelative(x, 0)
                    x += cada + hueco
                }
            }
        } else {
            val ps = medibles.map { it.measure(Constraints(minWidth = ancho, maxWidth = ancho)) }
            val orden = ps.indices.sortedBy { if (esCancelar(it)) 1 else 0 }
            val alto = ps.sumOf { it.height } + hueco * (ps.size - 1).coerceAtLeast(0)
            layout(ancho, alto) {
                var y = 0
                for (i in orden) {
                    ps[i].placeRelative(0, y)
                    y += ps[i].height + hueco
                }
            }
        }
    }
}
