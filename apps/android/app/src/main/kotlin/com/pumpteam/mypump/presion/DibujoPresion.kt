package com.pumpteam.mypump.presion

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import com.pumpteam.mypump.R
import com.pumpteam.mypump.diseno.MyPump

/** Las dos capas de un dibujo: la base (color del contenido) y el acento (el manguito, verde de la marca). */
private class CapasDibujo(@DrawableRes val base: Int, @DrawableRes val acento: Int, val proporcion: Float)

/** Nombre → drawables, a mano y sin reflexión. Los archivos los genera scripts/nativa/presion-dibujos.mjs. */
private fun capasDe(nombre: String): CapasDibujo? = when (nombre) {
    "presion_g1_postura" -> CapasDibujo(R.drawable.presion_g1_postura_base, R.drawable.presion_g1_postura_acento, 360f / 240f)
    "presion_g2_altura_brazo" -> CapasDibujo(R.drawable.presion_g2_altura_brazo_base, R.drawable.presion_g2_altura_brazo_acento, 360f / 240f)
    "presion_g3_medir_brazo" -> CapasDibujo(R.drawable.presion_g3_medir_brazo_base, R.drawable.presion_g3_medir_brazo_acento, 360f / 240f)
    "presion_g4_colocar_manguito" -> CapasDibujo(R.drawable.presion_g4_colocar_manguito_base, R.drawable.presion_g4_colocar_manguito_acento, 360f / 240f)
    "presion_g5_01" -> CapasDibujo(R.drawable.presion_g5_01_base, R.drawable.presion_g5_01_acento, 1f)
    "presion_g5_02" -> CapasDibujo(R.drawable.presion_g5_02_base, R.drawable.presion_g5_02_acento, 1f)
    "presion_g5_03" -> CapasDibujo(R.drawable.presion_g5_03_base, R.drawable.presion_g5_03_acento, 1f)
    "presion_g5_04" -> CapasDibujo(R.drawable.presion_g5_04_base, R.drawable.presion_g5_04_acento, 1f)
    "presion_g5_05" -> CapasDibujo(R.drawable.presion_g5_05_base, R.drawable.presion_g5_05_acento, 1f)
    "presion_g5_06" -> CapasDibujo(R.drawable.presion_g5_06_base, R.drawable.presion_g5_06_acento, 1f)
    "presion_g5_07" -> CapasDibujo(R.drawable.presion_g5_07_base, R.drawable.presion_g5_07_acento, 1f)
    "presion_g5_08" -> CapasDibujo(R.drawable.presion_g5_08_base, R.drawable.presion_g5_08_acento, 1f)
    "presion_g5_09" -> CapasDibujo(R.drawable.presion_g5_09_base, R.drawable.presion_g5_09_acento, 1f)
    "presion_g5_10" -> CapasDibujo(R.drawable.presion_g5_10_base, R.drawable.presion_g5_10_acento, 1f)
    "presion_g6_ortostatica" -> CapasDibujo(R.drawable.presion_g6_ortostatica_base, R.drawable.presion_g6_ortostatica_acento, 360f / 240f)
    "presion_g6_ortostatica_sentado" -> CapasDibujo(R.drawable.presion_g6_ortostatica_sentado_base, R.drawable.presion_g6_ortostatica_sentado_acento, 360f / 240f)
    "presion_tilde" -> CapasDibujo(R.drawable.presion_tilde_base, R.drawable.presion_tilde_acento, 1f)
    "presion_cruz" -> CapasDibujo(R.drawable.presion_cruz_base, R.drawable.presion_cruz_acento, 1f)
    else -> null
}

/**
 * Una ilustración de la pantalla de presión arterial (GRAFICOS.md): `presion_g1_postura`, `presion_g5_03`,
 * `presion_tilde`…
 *
 * Son dos VectorDrawable negros superpuestos y teñidos: la base con el color del contenido y el acento con el verde de
 * la marca, así se ven bien en claro y en oscuro. No llevan texto adentro: los títulos y las aclaraciones van al lado,
 * en componentes nativos, y [alt] es lo que lee TalkBack. Con un nombre que no existe no dibuja nada.
 */
@Composable
fun DibujoPresion(nombre: String, alt: String, modifier: Modifier = Modifier) {
    val capas = capasDe(nombre) ?: return
    Box(
        modifier
            .aspectRatio(capas.proporcion)
            .semantics {
                contentDescription = alt
                role = Role.Image
            },
    ) {
        Image(
            painter = painterResource(capas.base),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Fit,
            colorFilter = ColorFilter.tint(LocalContentColor.current),
        )
        Image(
            painter = painterResource(capas.acento),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Fit,
            colorFilter = ColorFilter.tint(MyPump.colores.marcaVivo),
        )
    }
}
