package com.pumpteam.mypump.diseno

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * El torso del logo de Pump Team, el del ícono de la app (`public/icons/logo.svg`): el contorno de hombros, brazos y
 * cintura, los pectorales y los abdominales, en trazo. Recortado a su caja (de 110,150 a 402,442 en la grilla de 512) con
 * el margen que pide el trazo; [grosor] en unidades de esa grilla (en el ícono, 14), más grueso en lo chico.
 */
private fun torso(grosor: Float): ImageVector {
    val margen = grosor / 2 + 2
    val lado = 292f + 2 * margen
    val b = ImageVector.Builder(name = "TorsoPumpTeam", defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = lado, viewportHeight = lado)
        .addGroup(translationX = margen - 110f, translationY = margen - 150f)
    val trazos = listOf(
        "M110,195C130,165 175,145 210,150L256,178L302,150C337,145 382,165 402,195L402,250C395,270 380,280 365,282L350,282" +
            "L340,320L350,360L332,405L296,432L256,442L216,432L180,405L162,360L172,320L162,282L147,282C132,280 117,270 110,250Z",
        "M210,195C195,215 195,245 220,265L250,275",
        "M302,195C317,215 317,245 292,265L262,275",
        "M256,282L256,405",
        "M200,312L312,312",
        "M195,348L317,348",
        "M190,385L322,385",
    )
    for (d in trazos) {
        b.addPath(
            pathData = addPathNodes(d),
            stroke = SolidColor(Color.Black),
            strokeLineWidth = grosor,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        )
    }
    return b.clearGroup().build()
}

private val TorsoFino: ImageVector by lazy { torso(14f) }
private val TorsoGrueso: ImageVector by lazy { torso(26f) }

/**
 * El logo de Pump Team como el ícono de la app: el torso blanco sobre el verde de la marca. [circular] para el avatar del
 * chat (Mati, 15-oct: el logo en lugar de la «M»); si no, el cuadrado redondeado del ícono. TalkBack no lo lee.
 */
@Composable
fun LogoPumpTeam(lado: Dp, modifier: Modifier = Modifier, circular: Boolean = false) {
    val c = MyPump.colores
    val forma = if (circular) CircleShape else RoundedCornerShape(lado * 0.24f)
    val fondo = remember(c.marca) { Brush.verticalGradient(listOf(lerp(c.marca, Color.White, 0.14f), c.marca)) }
    Box(
        modifier.size(lado).clip(forma).background(fondo).clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            if (lado < 48.dp) TorsoGrueso else TorsoFino,
            contentDescription = null,
            tint = c.sobreMarca,
            modifier = Modifier.size(lado * (if (circular) 0.66f else 0.57f)),
        )
    }
}
