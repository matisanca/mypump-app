package com.pumpteam.mypump.revision

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.reglas.DevolucionSemanal
import com.pumpteam.mypump.reglas.ReglasDevolucion

/**
 * «Devolución de Mati», arriba de todo en Revisión (gemela de `DevolucionTarjeta.swift`): lo que Mati le dice de su semana,
 * como un mensaje suyo. Debajo, las semanas anteriores, que se abren de a una. Sin devolución publicada no se muestra nada.
 */
@Composable
fun TarjetaDevolucion(ultima: DevolucionSemanal, anteriores: List<DevolucionSemanal>, modifier: Modifier = Modifier) {
    Column(modifier.testTag("devolucion-seccion"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        MensajeDeMati(ultima)
        if (anteriores.isNotEmpty()) HistorialDevoluciones(anteriores)
    }
}

/** Las iniciales de Mati en un círculo de la marca: lo que lo hace sentir un mensaje de una persona y no un aviso. */
@Composable
private fun FirmaMati() {
    val c = MyPump.colores
    // Crece con la letra del sistema, como el @ScaledMetric de iOS.
    val lado = with(LocalDensity.current) { (40.dp.toPx() * fontScale.coerceAtMost(1.6f)).toDp() }
    Box(
        Modifier
            .size(lado)
            .clip(CircleShape)
            .background(Brush.linearGradient(listOf(c.marca, c.marcaTexto))),
        contentAlignment = Alignment.Center,
    ) {
        Text("M", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = c.sobreMarca)
    }
}

@Composable
private fun MensajeDeMati(d: DevolucionSemanal) {
    val c = MyPump.colores
    val nueva = ReglasDevolucion.esNueva(d)
    val grande = LocalDensity.current.fontScale >= 1.5f
    Column(
        Modifier
            .fillMaxWidth()
            .superficieTarjeta()
            // Un velo verde muy suave arriba: cálido y de la marca, sin competir con el texto.
            .background(Brush.verticalGradient(0f to c.marcaSuave, 0.5f to Color.Transparent), RoundedCornerShape(Radio.tarjeta))
            .padding(Espacio.m + 2.dp)
            .testTag("devolucion-tarjeta"),
        verticalArrangement = Arrangement.spacedBy(Espacio.m),
    ) {
        val textos: @Composable () -> Unit = {
            Column(Modifier.semantics(mergeDescendants = true) { heading() }) {
                Text("Devolución de Mati", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = c.texto)
                Text(d.etiqueta, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
            }
        }
        if (grande) {
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    FirmaMati(); Spacer(Modifier.weight(1f)); if (nueva) EtiquetaNueva()
                }
                textos()
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                FirmaMati()
                Box(Modifier.weight(1f)) { textos() }
                if (nueva) EtiquetaNueva()
            }
        }
        Row(Modifier.height(IntrinsicSize.Min).semantics(mergeDescendants = true) {}.testTag("devolucion-texto")) {
            Box(
                Modifier
                    .width(3.dp)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(2.dp))
                    .background(c.marca.copy(alpha = if (c.oscuro) 0.55f else 0.4f)),
            )
            Column(Modifier.padding(start = Espacio.s + 2.dp), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                d.lineas.forEach { Text(it, style = MaterialTheme.typography.bodyLarge, color = c.texto) }
            }
        }
    }
}

@Composable
private fun EtiquetaNueva() {
    val c = MyPump.colores
    Text(
        "Nueva",
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = c.marcaTexto,
        modifier = Modifier
            .clip(CircleShape)
            .background(c.marcaSuave)
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .testTag("devolucion-nueva"),
    )
}

/** Las semanas anteriores: una fila por semana con el principio del mensaje; tocar la abre ahí mismo. */
@Composable
private fun HistorialDevoluciones(lista: List<DevolucionSemanal>) {
    val c = MyPump.colores
    var abierta by rememberSaveable { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxWidth().superficieTarjeta().padding(bottom = Espacio.xs).testTag("devolucion-historial")) {
        Text(
            "Semanas anteriores",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = c.textoSecundario,
            modifier = Modifier.padding(start = Espacio.m, end = Espacio.m, top = Espacio.s, bottom = Espacio.xs).semantics { heading() },
        )
        lista.forEachIndexed { i, d ->
            if (i > 0) HorizontalDivider(Modifier.padding(start = Espacio.m), color = c.borde)
            val esta = abierta == d.id
            Column(
                Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button, onClickLabel = if (esta) "Cerrar esta devolución" else "Abrir esta devolución") {
                        abierta = if (esta) null else d.id
                    }
                    .animateContentSize()
                    .padding(horizontal = Espacio.m, vertical = Espacio.s)
                    .semantics(mergeDescendants = true) {}
                    .testTag("devolucion-anterior-${d.id}"),
                verticalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(d.etiqueta, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = c.texto, modifier = Modifier.weight(1f))
                    Icon(Iconos.Chevron, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(20.dp).rotate(if (esta) 270f else 90f))
                }
                AnimatedVisibility(esta) {
                    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                        d.lineas.forEach { Text(it, style = MaterialTheme.typography.bodyMedium, color = c.texto) }
                    }
                }
                if (!esta) {
                    Text(d.lineas.first(), style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
