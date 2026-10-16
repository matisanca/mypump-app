package com.pumpteam.mypump.progreso

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Oro
import com.pumpteam.mypump.diseno.SobreOro
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.salud.curvaMonotona
import kotlin.math.max

// Las piezas de Progreso que comparten la lista y el detalle (ProgresoView.swift): la insignia del récord, la píldora de
// la variación y la curva chica de cada fila.

/** Los íconos de la variación (Material Icons, Apache 2.0, en la grilla de 24, como los de `Iconos`). */
internal object IconosProgreso {
    private fun icono(nombre: String, trazado: String): ImageVector =
        ImageVector.Builder(name = nombre, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .apply { addPath(pathData = addPathNodes(trazado), fill = SolidColor(Color.Black)) }
            .build()

    /** north_east: sube. */
    val Sube: ImageVector by lazy { icono("Sube", "M9,5v2h6.59L4,18.59L5.41,20L17,8.41V15h2V5H9z") }

    /** south_east: baja. */
    val Baja: ImageVector by lazy { icono("Baja", "M19,9h-2v6.59L5.41,4L4,5.41L15.59,17H9v2h10V9z") }

    /** drag_handle: igual. */
    val Igual: ImageVector by lazy { icono("Igual", "M20,9H4v2h16V9zM4,15h16v-2H4V15z") }
}

/**
 * Insignia de récord personal: el trofeo sobre el oro claro de la marca, en negro (el oro es para lo importante, Mati
 * 15-oct). [compacta]: solo el trofeo en un círculo (las filas);
 * si no, la cápsula con "PR" (el detalle). TalkBack lee "Récord personal", salvo con [accesible] en false: adentro de una
 * fila o un encabezado que ya lo dice en su descripción (si no, se leería dos veces).
 */
@Composable
fun InsigniaPR(modifier: Modifier = Modifier, compacta: Boolean = false, accesible: Boolean = true) {
    val c = MyPump.colores
    val semantica = Modifier.clearAndSetSemantics { if (accesible) contentDescription = "Récord personal" }
    if (compacta) {
        // El lado sigue a la letra, como el `@ScaledMetric` de iOS.
        val lado = with(LocalDensity.current) { (22.dp * fontScale).coerceAtMost(34.dp) }
        Box(modifier.size(lado).clip(CircleShape).background(Oro).then(semantica), contentAlignment = Alignment.Center) {
            Icon(Iconos.Trofeo, contentDescription = null, tint = SobreOro, modifier = Modifier.size(lado * 0.55f))
        }
    } else {
        Row(
            modifier.clip(CircleShape).background(Oro).padding(horizontal = 9.dp, vertical = 4.dp).then(semantica),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(Iconos.Trofeo, contentDescription = null, tint = SobreOro, modifier = Modifier.size(14.dp))
            Text("PR", style = Letras.caption.copy(fontWeight = FontWeight.Black), color = SobreOro)
        }
    }
}

/**
 * La variación de las últimas 8 sesiones: "+12,3 %" en verde si sube y en rojo si baja (sin invertir: más kilos es mejor),
 * con su flecha y el fondo teñido. Con una sola sesión, "—". Va siempre adentro de algo que TalkBack lee entero (la fila,
 * el encabezado del detalle): no tiene semántica propia.
 */
@Composable
fun PildoraVariacion(variacion: Double?, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    if (variacion == null) {
        Text("—", style = Letras.caption.copy(fontWeight = FontWeight.SemiBold), color = c.textoTerciario, modifier = modifier)
        return
    }
    val color = when {
        variacion > 0 -> c.exito
        variacion < 0 -> c.peligro
        else -> c.textoSecundario
    }
    val texto = VistaProgreso.variacion(variacion)
    Row(
        modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        val icono = when {
            variacion > 0 -> IconosProgreso.Sube
            variacion < 0 -> IconosProgreso.Baja
            else -> IconosProgreso.Igual
        }
        Icon(icono, contentDescription = null, tint = color, modifier = Modifier.size(11.dp))
        Text(texto, style = Letras.caption.copy(fontWeight = FontWeight.SemiBold).merge(Letras.cifras), color = color, maxLines = 1)
    }
}

/**
 * La curva chica de una fila: el máximo por sesión de las últimas 8, con el área en degradé, la línea y el último punto
 * marcado (en el color del récord si lo es). Sin ejes; TalkBack no la lee (lo dice la fila).
 */
@Composable
fun CurvaChica(valores: List<Double>, esPR: Boolean, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val linea = c.marcaVivo
    val punto = if (esPR) c.record else c.marcaVivo
    Canvas(modifier.clearAndSetSemantics {}) {
        if (valores.isEmpty()) return@Canvas
        val minimo = valores.min()
        val maximo = valores.max()
        // Como iOS: un margen de un cuarto del rango (medio kilo como mínimo) arriba y abajo.
        val margen = max((maximo - minimo) * 0.25, 0.5)
        val lo = minimo - margen
        val hi = maximo + margen
        val radio = (if (esPR) 3.6f else 3f).dp.toPx()
        // El punto del final entra entero.
        val ancho = size.width - radio
        val ultimoX = max(valores.size - 1, 1)
        val puntos = valores.mapIndexed { i, v ->
            Offset(ancho * i / ultimoX, (size.height * (1 - (v - lo) / (hi - lo))).toFloat())
        }
        if (puntos.size >= 2) {
            val curva = curvaMonotona(puntos)
            val area = curvaMonotona(puntos).apply {
                lineTo(puntos.last().x, size.height)
                lineTo(puntos.first().x, size.height)
                close()
            }
            drawPath(area, Brush.verticalGradient(listOf(linea.copy(alpha = 0.3f), linea.copy(alpha = 0f)), startY = 0f, endY = size.height))
            drawPath(curva, linea, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
        drawCircle(punto, radius = radio, center = puntos.last())
    }
}
