package com.pumpteam.mypump.revision

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/**
 * Los íconos de Revisión que no están en `Iconos` (trazados de Material Icons, Apache 2.0, grilla de 24), como los de
 * `IconosSalud`. Van acá y no en `diseno/Iconos.kt` para no tocar un archivo de todas las pantallas.
 */
internal object IconosRevision {
    private fun icono(nombre: String, trazado: String): ImageVector =
        ImageVector.Builder(name = nombre, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .apply { addPath(pathData = addPathNodes(trazado), fill = SolidColor(Color.Black)) }
            .build()

    /** add: un vaso más. */
    val Mas: ImageVector by lazy { icono("Mas", "M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z") }

    /** water_drop: un vaso tomado. */
    val Gota: ImageVector by lazy {
        icono("Gota", "M12,2c-5.33,4.55 -8,8.48 -8,11.8c0,4.98 3.8,8.2 8,8.2s8,-3.22 8,-8.2C20,10.48 17.33,6.55 12,2z")
    }

    /** water_drop con contorno: un vaso por tomar. */
    val GotaVacia: ImageVector by lazy {
        icono(
            "GotaVacia",
            "M12,2c-5.33,4.55 -8,8.48 -8,11.8c0,4.98 3.8,8.2 8,8.2s8,-3.22 8,-8.2C20,10.48 17.33,6.55 12,2zM12,20c-3.35,0 -6,-2.57 -6,-6.2c0,-2.34 1.95,-5.44 6,-9.14c4.05,3.7 6,6.79 6,9.14C18,17.43 15.35,20 12,20z",
        )
    }

    /** hotel: descansé, dormí bien. */
    val Cama: ImageVector by lazy {
        icono("Cama", "M7,13c1.66,0 3,-1.34 3,-3S8.66,7 7,7s-3,1.34 -3,3 1.34,3 3,3zM19,7h-8v7H3V5H1v15h2v-3h18v3h2v-9c0,-2.21 -1.79,-4 -4,-4z")
    }

    /** north_east: el peso subió esta semana. */
    val Sube: ImageVector by lazy { icono("Sube", "M9,5v2h6.59L4,18.59 5.41,20 17,8.41V15h2V5z") }

    /** south_east: el peso bajó. */
    val Baja: ImageVector by lazy { icono("Baja", "M19,9h-2v6.59L5.41,4 4,5.41 15.59,17H9v2h10z") }

    /** drag_handle: el peso quedó igual. */
    val Igual: ImageVector by lazy { icono("Igual", "M20,9H4v2h16V9zM4,15h16v-2H4v2z") }

    /** cloud_upload: la foto espera señal para subir. */
    val NubeSubir: ImageVector by lazy {
        icono(
            "NubeSubir",
            "M19.35,10.04C18.67,6.59 15.64,4 12,4 9.11,4 6.6,5.64 5.35,8.04 2.34,8.36 0,10.91 0,14c0,3.31 2.69,6 6,6h13c2.76,0 5,-2.24 5,-5 0,-2.64 -2.05,-4.78 -4.65,-4.96zM14,13v4h-4v-4H7l5,-5 5,5h-3z",
        )
    }

    /** expand_more: abrir "Mis últimos 30 días". */
    val Desplegar: ImageVector by lazy { icono("Desplegar", "M16.59,8.59L12,13.17 7.41,8.59 6,10l6,6 6,-6z") }

    /** check_circle: el check ya salió. */
    val Enviado: ImageVector by lazy {
        icono("Enviado", "M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM10,17l-5,-5 1.41,-1.41L10,14.17l7.59,-7.59L19,8l-9,9z")
    }
}
