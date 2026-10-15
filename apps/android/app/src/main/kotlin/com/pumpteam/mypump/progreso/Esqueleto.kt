package com.pumpteam.mypump.progreso

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.entreno.reducirMovimiento

/**
 * El esqueleto de carga (`Esqueleto` de iOS): bloques grises con la forma de lo que va a aparecer y un brillo que los
 * cruza. El brillo se pinta solo sobre lo dibujado (las tarjetas y los bloques), como la máscara de iOS. Con "Quitar
 * animaciones" de Accesibilidad (GEN-08) queda quieto. TalkBack lee "Cargando" y nada de adentro: lo que se le ponga
 * DESPUÉS en la cadena (una `testTag`) también se pierde, así que va antes.
 *
 * Lo usan Progreso y el chat.
 */
@Composable
fun Modifier.esqueleto(): Modifier {
    val reducir = reducirMovimiento()
    val base = this.clearAndSetSemantics { contentDescription = "Cargando" }
    if (reducir) return base
    val transicion = rememberInfiniteTransition(label = "esqueleto")
    val fase by transicion.animateFloat(-1f, 1f, infiniteRepeatable(tween(1_300, easing = LinearEasing)), label = "brillo")
    // En claro el blanco se ve sobre los bloques grises; en oscuro, apenas sobre todo.
    val brillo = if (MyPump.colores.oscuro) Color.White.copy(alpha = 0.10f) else Color.White.copy(alpha = 0.6f)
    return base
        .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
        .drawWithContent {
            drawContent()
            val ancho = size.width * 0.6f
            // Como iOS: de 1,4 anchos a la izquierda a 1,4 a la derecha, en 1,3 s.
            val x = fase * size.width * 1.4f
            drawRect(
                Brush.horizontalGradient(listOf(Color.Transparent, brillo, Color.Transparent), startX = x, endX = x + ancho),
                blendMode = BlendMode.SrcAtop,
            )
        }
}

/** Un bloque del esqueleto (el lugar de un texto, un número o un gráfico). Sin [ancho], a lo ancho. */
@Composable
fun BloqueEsqueleto(ancho: Dp?, alto: Dp, modifier: Modifier = Modifier, forma: Shape = RoundedCornerShape(6.dp)) {
    Box(
        modifier
            .then(if (ancho != null) Modifier.width(ancho) else Modifier.fillMaxWidth())
            .height(alto)
            .clip(forma)
            .background(MyPump.colores.campo),
    )
}
