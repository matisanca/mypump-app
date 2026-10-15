package com.pumpteam.mypump.salud

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.reglas.PuntoSalud
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sign

/**
 * Una línea chica sin ejes, como los `Chart` de iOS con `.interpolationMethod(.monotone)`: la curva pasa por cada punto
 * sin pasarse de largo (un día bajo no dibuja un pozo más hondo que el dato). Sin [dominio], va del mínimo al máximo.
 */
@Composable
fun LineaSalud(
    valores: List<Double>,
    color: Color,
    alto: Dp,
    modifier: Modifier = Modifier,
    dominio: ClosedFloatingPointRange<Double>? = null,
    marcarUltimo: Boolean = false,
    descripcion: String? = null,
) {
    if (valores.size < 2) return
    val lo = dominio?.start ?: valores.min()
    val hi = dominio?.endInclusive ?: valores.max().let { if (it > lo) it else lo + 1 }
    val semantica = if (descripcion != null) Modifier.semantics { contentDescription = descripcion } else Modifier.clearAndSetSemantics {}
    Canvas(modifier.fillMaxWidth().height(alto).then(semantica)) {
        val margen = 3.dp.toPx()
        val ancho = size.width - 2 * margen
        val altoUtil = size.height - 2 * margen
        val puntos = valores.mapIndexed { i, v ->
            val x = margen + if (valores.size == 1) 0f else ancho * i / (valores.size - 1)
            val y = margen + altoUtil * (1 - ((v - lo) / (hi - lo)).coerceIn(0.0, 1.0)).toFloat()
            Offset(x, y)
        }
        drawPath(curvaMonotona(puntos), color, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        if (marcarUltimo) drawCircle(color, radius = 3.dp.toPx(), center = puntos.last())
    }
}

/** El gráfico chico de una serie de "Mis datos" (los últimos 30 puntos; hacen falta 3). */
@Composable
fun GraficoSalud(serie: List<PuntoSalud>, color: Color = MyPump.colores.marcaTexto, modifier: Modifier = Modifier) {
    val puntos = serie.takeLast(30)
    if (puntos.size < 3) return
    LineaSalud(puntos.map { it.valor }, color.copy(alpha = 0.85f), 30.dp, modifier)
}

/**
 * Curva monótona en x (la `monotoneX` de d3, la misma idea que la de Charts): las tangentes se achican donde la pendiente
 * cambia de signo, así la curva nunca se sale del rango de dos puntos vecinos.
 */
internal fun curvaMonotona(p: List<Offset>): Path {
    val camino = Path()
    if (p.isEmpty()) return camino
    camino.moveTo(p[0].x, p[0].y)
    if (p.size == 2) {
        camino.lineTo(p[1].x, p[1].y)
        return camino
    }
    val n = p.size
    val pendientes = FloatArray(n - 1) { i -> (p[i + 1].y - p[i].y) / (p[i + 1].x - p[i].x).let { if (it == 0f) 1e-6f else it } }
    val tangentes = FloatArray(n)
    for (i in 1 until n - 1) {
        val s0 = pendientes[i - 1]
        val s1 = pendientes[i]
        val h0 = p[i].x - p[i - 1].x
        val h1 = p[i + 1].x - p[i].x
        val q = (s0 * h1 + s1 * h0) / (h0 + h1)
        tangentes[i] = (sign(s0) + sign(s1)) * min(min(abs(s0), abs(s1)), 0.5f * abs(q))
    }
    tangentes[0] = (3 * pendientes[0] - tangentes[1]) / 2
    tangentes[n - 1] = (3 * pendientes[n - 2] - tangentes[n - 2]) / 2
    for (i in 0 until n - 1) {
        val dx = (p[i + 1].x - p[i].x) / 3
        camino.cubicTo(p[i].x + dx, p[i].y + dx * tangentes[i], p[i + 1].x - dx, p[i + 1].y - dx * tangentes[i + 1], p[i + 1].x, p[i + 1].y)
    }
    return camino
}
