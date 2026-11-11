package com.pumpteam.mypump.presion

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.datos.SesionPresion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.reglas.Presion
import kotlin.math.ceil

/**
 * «Tus tomas»: la alta y la baja de cada toma, por día, tal como las anotó. Un solo color neutro, sin líneas de corte, sin
 * promedio y sin colores de riesgo (PROTOCOLO §5.3). La alta es el punto lleno y la baja el hueco.
 */
@Composable
internal fun GraficoPresion(sesiones: List<SesionPresion>) {
    val c = MyPump.colores
    // En orden de fecha, las últimas 30.
    val puntos = sesiones.asReversed().flatMap { s -> s.tomas.map { Triple(s.fecha, it.sis, it.dia) } }.takeLast(30)
    if (puntos.isEmpty()) return
    // La fecha, una vez por día; si son muchas, salteadas.
    val primeros = puntos.indices.filter { it == 0 || puntos[it - 1].first != puntos[it].first }
    val salto = maxOf(1, ceil(primeros.size / 5.0).toInt())
    val marcas = primeros.filterIndexed { i, _ -> i % salto == 0 }
    val piso = puntos.minOf { it.third } - 10
    val techo = puntos.maxOf { it.second } + 10
    val medidor = rememberTextMeasurer()
    // Los rótulos de los ejes no crecen sin tope: con la letra más grande se pisarían entre sí.
    val rotulo = TextStyle(color = c.textoSecundario, fontSize = 11.sp)
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(190.dp)
                .clearAndSetSemantics {
                    contentDescription = NP.graficoAlt(puntos.size)
                    role = Role.Image
                }
                .testTag("presion-grafico"),
        ) {
            val izquierda = 34.dp.toPx()
            val abajo = 20.dp.toPx()
            val arriba = 8.dp.toPx()
            val ancho = size.width - izquierda - 8.dp.toPx()
            val alto = size.height - abajo - arriba
            fun x(i: Int) = izquierda + ancho * (i + 0.6f) / (puntos.size + 0.2f)
            fun y(v: Int) = arriba + alto * (techo - v) / (techo - piso).toFloat()
            // Solo la escala (tres números), sin líneas de corte.
            for (v in listOf(techo - 10, (techo + piso) / 2, piso + 10).distinct()) {
                val m = medidor.measure("$v", rotulo)
                drawText(m, topLeft = Offset(izquierda - m.size.width - 6.dp.toPx(), y(v) - m.size.height / 2f))
            }
            for (i in marcas) {
                val m = medidor.measure(NumeroPresion.diaCorto(puntos[i].first), rotulo)
                drawText(m, topLeft = Offset((x(i) - m.size.width / 2f).coerceIn(0f, size.width - m.size.width), size.height - m.size.height))
            }
            val radio = 4.5.dp.toPx()
            puntos.forEachIndexed { i, p ->
                drawLine(c.textoSecundario.copy(alpha = 0.45f), Offset(x(i), y(p.second)), Offset(x(i), y(p.third)), strokeWidth = 2.dp.toPx(), cap = StrokeCap.Round)
                drawCircle(c.textoSecundario, radio, Offset(x(i), y(p.second)))
                drawCircle(c.tarjeta, radio, Offset(x(i), y(p.third)))
                drawCircle(c.textoSecundario, radio - 1.dp.toPx(), Offset(x(i), y(p.third)), style = Stroke(2.dp.toPx()))
            }
        }
        Row(Modifier.clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(Espacio.m), verticalAlignment = Alignment.CenterVertically) {
            Row(horizontalArrangement = Arrangement.spacedBy(Espacio.xxs), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(9.dp).clip(CircleShape).background(c.textoSecundario))
                Text(NP.alta, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Espacio.xxs), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(9.dp).border(2.dp, c.textoSecundario, CircleShape))
                Text(NP.baja, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
            }
        }
    }
}

/** La lista de tomas, la más nueva primero: el día, la alta y la baja y el pulso. Sin categorías ni colores. */
@Composable
internal fun ListaTomasPresion(sesiones: List<SesionPresion>) {
    val c = MyPump.colores
    val filas = sesiones.filter { it.tomas.isNotEmpty() }
    Column {
        filas.forEachIndexed { i, s ->
            Column(Modifier.fillMaxWidth().padding(vertical = Espacio.xs).testTag("presion-toma-$i"), verticalArrangement = Arrangement.spacedBy(Espacio.xxs)) {
                Text(NumeroPresion.dia(s.fecha), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = c.textoSecundario)
                for (t in s.tomas) FilaToma(t)
            }
            if (i < filas.size - 1) Separador()
        }
    }
}

@Composable
private fun FilaToma(t: Presion.Toma) {
    val c = MyPump.colores
    val voz = "${NP.alta} ${t.sis}. ${NP.baja} ${t.dia}. ${NP.pulso} ${t.pulso}." + if (t.latidoIrregular) " ${NP.irregular}." else ""
    val valores = @Composable { Text("${t.sis}/${t.dia}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, color = c.texto) }
    val pulso = @Composable { Text("${NP.pulso} ${t.pulso}", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario) }
    if (letraGrande()) {
        Column(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = voz }) {
            valores()
            pulso()
        }
    } else {
        Row(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = voz }, verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { valores() }
            pulso()
        }
    }
}
