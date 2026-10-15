package com.pumpteam.mypump.diseno

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * El control segmentado de iOS (`Picker` con `.segmented`): un riel gris en cápsula y la opción elegida en una píldora
 * blanca (gris clara en oscuro) que se desliza hasta ella. Reemplaza al `SegmentedButton` de Material, de bordes y
 * relleno de color. Cada opción es un botón de radio para TalkBack, con su estado de elegida.
 *
 * [etiquetaPrueba] da la etiqueta de cada opción para las pruebas (`opcion-<comida>-<i>`, `variante-<nombre>`).
 */
@Composable
fun Segmentado(
    opciones: List<String>,
    elegida: Int,
    alElegir: (Int) -> Unit,
    modifier: Modifier = Modifier,
    habilitado: Boolean = true,
    etiquetaPrueba: (Int) -> String? = { null },
) {
    val c = MyPump.colores
    val pildora = if (c.oscuro) Color(0xFF636366) else Color.White
    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .height(36.dp)
            .clip(CircleShape)
            .background(c.campo)
            .padding(2.dp),
    ) {
        val n = opciones.size.coerceAtLeast(1)
        val ancho = maxWidth / n
        val x by animateDpAsState(ancho * elegida.coerceIn(0, n - 1), spring(dampingRatio = 0.85f, stiffness = 600f), label = "segmentado")
        if (elegida in opciones.indices) {
            Box(
                Modifier
                    .offset(x = x)
                    .width(ancho)
                    .fillMaxHeight()
                    .shadow(if (c.oscuro) 0.dp else 2.dp, CircleShape)
                    .clip(CircleShape)
                    .background(pildora),
            )
        }
        Row(Modifier.fillMaxWidth().fillMaxHeight().selectableGroup(), verticalAlignment = Alignment.CenterVertically) {
            opciones.forEachIndexed { i, op ->
                val esta = i == elegida
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clip(CircleShape)
                        .selectable(selected = esta, enabled = habilitado, role = Role.RadioButton, onClick = { alElegir(i) })
                        .then(etiquetaPrueba(i)?.let { Modifier.testTag(it) } ?: Modifier),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        op,
                        color = if (habilitado) c.texto else c.textoTerciario,
                        fontSize = 13.sp,
                        fontWeight = if (esta) FontWeight.SemiBold else FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 6.dp),
                    )
                }
            }
        }
    }
}
