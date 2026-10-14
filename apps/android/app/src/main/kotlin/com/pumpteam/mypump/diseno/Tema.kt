package com.pumpteam.mypump.diseno

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// La identidad de MyPump en Material 3, con los mismos colores que el Tema.swift de iOS: el lima de la marca como
// relleno (siempre con texto negro encima) y un verde oscuro para texto e íconos en claro, porque el lima sobre blanco
// no tiene contraste.

/** Relleno de marca (botones principales, día hecho). */
val Marca = Color(0xFFB8F060)

/** Lo que va encima del lima. */
val SobreMarca = Color(0xFF0A0A0A)

/** Verde para texto e íconos en modo claro. */
val MarcaTextoClaro = Color(0xFF3F6212)

private val esquemaClaro = lightColorScheme(
    primary = MarcaTextoClaro,
    onPrimary = Color.White,
    primaryContainer = Marca,
    onPrimaryContainer = SobreMarca,
)

private val esquemaOscuro = darkColorScheme(
    primary = Marca,
    onPrimary = SobreMarca,
    primaryContainer = Marca,
    onPrimaryContainer = SobreMarca,
)

/** Sigue al sistema (D5: el `'light'` que guarda la web no es una elección del cliente). */
@Composable
fun TemaMyPump(oscuro: Boolean = isSystemInDarkTheme(), contenido: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (oscuro) esquemaOscuro else esquemaClaro, content = contenido)
}
