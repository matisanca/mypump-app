package com.pumpteam.mypump.diseno

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

/**
 * El interruptor de iOS (`Toggle`): un riel de 51 × 31 y el círculo blanco de 27 con sombra, que se desliza al [color].
 * Reemplaza al `Switch` de Material (riel con borde y círculo que cambia de tamaño).
 *
 * Con [alCambiar] `null` es solo el dibujo: lo cambia la fila entera, que es la que anuncia el lector de pantalla.
 */
@Composable
fun Interruptor(
    prendido: Boolean,
    alCambiar: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    color: Color = MyPump.colores.exito,
    habilitado: Boolean = true,
) {
    val c = MyPump.colores
    val apagado = if (c.oscuro) Color(0xFF39393D) else Color(0xFFE9E9EA)
    val riel by animateColorAsState(if (prendido) color else apagado, label = "riel")
    val x by animateDpAsState(if (prendido) 20.dp else 0.dp, spring(dampingRatio = 0.8f, stiffness = 700f), label = "circulo")
    Box(
        modifier = modifier
            .then(
                if (alCambiar != null) {
                    Modifier.toggleable(value = prendido, enabled = habilitado, role = Role.Switch, onValueChange = alCambiar)
                } else {
                    Modifier
                },
            )
            .size(width = 51.dp, height = 31.dp)
            .clip(CircleShape)
            .background(if (habilitado) riel else riel.copy(alpha = riel.alpha * 0.5f))
            .padding(2.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            Modifier
                .offset(x = x)
                .size(27.dp)
                .shadow(2.dp, CircleShape)
                .clip(CircleShape)
                .background(Color.White),
        )
    }
}
