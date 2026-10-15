package com.pumpteam.mypump.diseno

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// El vidrio de iOS (Vidrio.swift) para lo que flota sobre el contenido: la barra de pestañas, la isla del descanso y los
// botones redondos de volver. Nunca en tarjetas de contenido: el vidrio es la capa de navegación, no la de lectura.
// Android no desenfoca lo que queda detrás de una vista sin dependencias nuevas: es la superficie casi opaca, con el borde
// de pelo y la sombra que usa iOS 17-25 como respaldo del Liquid Glass.

/**
 * Cuánto tapa lo que flota abajo (la barra de pestañas y el descanso, con el borde del sistema): las pantallas lo suman
 * al final de su desplazamiento para que lo último quede arriba de la barra, mientras el resto pasa por debajo, como en
 * iOS. Fuera de las pestañas vale 0.
 */
val LocalRellenoInferior = staticCompositionLocalOf { 0.dp }

/**
 * [LocalRellenoInferior], salvo con el teclado abierto: ahí la barra queda tapada por él y lo de abajo ya lo corre el
 * teclado (`imePadding`). Para las pantallas con campos de texto (Revisión, Ejercicio).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun rellenoInferior(): Dp = if (WindowInsets.isImeVisible) 0.dp else LocalRellenoInferior.current

/** La superficie de vidrio en la forma dada (una cápsula si no se dice): casi opaca, con borde de pelo y sombra. */
@Composable
fun Modifier.vidrio(forma: Shape = CircleShape, elevacion: Dp = 18.dp): Modifier {
    val c = MyPump.colores
    val sombra = Color.Black.copy(alpha = if (c.oscuro) 0.5f else 0.16f)
    return this
        .shadow(elevacion, forma, ambientColor = sombra, spotColor = sombra)
        .clip(forma)
        .background(c.tarjeta.copy(alpha = if (c.oscuro) 0.94f else 0.92f))
        .border(1.dp, c.borde, forma)
}
