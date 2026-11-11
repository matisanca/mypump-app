package com.pumpteam.mypump.revision

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.diseno.Archivo
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.reglas.CheckinSemanal

// El lenguaje visual del check guiado (2.3.0), en la línea de la carga rediseñada: un foco por pantalla, pocas cajas y el
// verde solo para lo que avanza. Colores y Archivo, los de `Tema.kt`. Todo lo de acá lleva «Check» en el nombre: las piezas
// de la carga viven en otra rama y no se comparten.

internal object EstiloCheck {
    /** El título de cada paso: Archivo 800 de 34. */
    val titulo = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W800, fontSize = 34.sp, lineHeight = 38.sp)

    /** El peso: el número grande de la pantalla. */
    val peso = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W800, fontSize = 66.sp, lineHeight = 72.sp, fontFeatureSettings = "tnum")

    /** La unidad al lado del peso. */
    val unidad = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W700, fontSize = 24.sp, lineHeight = 28.sp)

    /** El botón principal: Archivo 19/700. */
    val boton = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W700, fontSize = 19.sp, lineHeight = 24.sp)

    /** El riel de lo que todavía no se hizo: gris en claro y blanco al 14 % en oscuro (nunca verde translúcido). */
    val riel: Color
        @Composable get() = if (MyPump.colores.oscuro) Color.White.copy(alpha = 0.14f) else Color(0xFFDCDCE2)

    /** El margen de los costados de cada paso. */
    val margen = 20.dp
}

/**
 * El botón que avanza: cápsula de 58, con la luz arriba y la sombra verde. Deshabilitado pasa a gris (un verde lavado
 * parece un error) y pierde la sombra.
 */
@Composable
internal fun BotonPrincipalCheck(texto: String, alTocar: () -> Unit, modifier: Modifier = Modifier, habilitado: Boolean = true) {
    val c = MyPump.colores
    val interaccion = remember { MutableInteractionSource() }
    val apretado by interaccion.collectIsPressedAsState()
    val escala by animateFloatAsState(if (apretado) 0.97f else 1f, spring(stiffness = Spring.StiffnessHigh), label = "check-boton")
    val fondo by animateColorAsState(if (habilitado) c.marca else c.campo, label = "check-boton-color")
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 58.dp)
            .graphicsLayer { scaleX = escala; scaleY = escala }
            .then(if (habilitado && !c.oscuro) Modifier.shadow(14.dp, CircleShape, clip = false, ambientColor = c.marca, spotColor = c.marca) else Modifier)
            .clip(CircleShape)
            .background(fondo)
            .then(if (habilitado) Modifier.background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.14f), 0.55f to Color.Transparent)) else Modifier)
            .clickable(interactionSource = interaccion, indication = null, enabled = habilitado, role = Role.Button, onClick = alTocar)
            .padding(horizontal = 20.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(texto, style = EstiloCheck.boton, color = if (habilitado) c.sobreMarca else c.textoSecundario, textAlign = TextAlign.Center)
    }
}

/** La salida discreta («Hoy no me pesé», «Atrás»): solo texto, con una zona de toque de 48. */
@Composable
internal fun SalidaDiscretaCheck(texto: String, alTocar: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .heightIn(min = 48.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = alTocar)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(texto, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = MyPump.colores.textoSecundario)
    }
}

/** El avance: un segmento por paso, los hechos en verde lleno y el resto en el riel. Para TalkBack, «Paso 2 de 5». */
@Composable
internal fun AvanceCheck(total: Int, hechos: Int, modifier: Modifier = Modifier, descripcion: String? = null) {
    val c = MyPump.colores
    val riel = EstiloCheck.riel
    Row(
        modifier.clearAndSetSemantics { if (descripcion != null) contentDescription = descripcion },
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        repeat(maxOf(total, 1)) { i ->
            val color by animateColorAsState(if (i < hechos) c.marca else riel, label = "check-avance-$i")
            Box(Modifier.weight(1f).height(5.dp).clip(CircleShape).background(color))
        }
    }
}

/**
 * Una escala de 1 a 5 del check guiado: círculos de 52, el elegido en verde lleno. Sin íconos de color: el nombre y los
 * extremos alcanzan. Tocar el elegido lo borra.
 */
@Composable
internal fun EscalaCheck(metrica: CheckinSemanal.Metrica, valor: Int?, alCambiar: (Int?) -> Unit) {
    val c = MyPump.colores
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Text(metrica.etiqueta, style = MaterialTheme.typography.titleMedium, color = c.texto)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            for (n in 1..5) {
                val elegido = valor == n
                val fondo by animateColorAsState(if (elegido) c.marca else c.campo, label = "check-escala")
                Box(
                    Modifier
                        .size(52.dp)
                        .clip(CircleShape)
                        .background(fondo)
                        .clickable(role = Role.Button) { alCambiar(if (elegido) null else n) }
                        .semantics {
                            contentDescription = "${metrica.etiqueta}: $n de 5"
                            selected = elegido
                        }
                        .testTag("cg-escala-${metrica.clave}-$n"),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "$n",
                        style = EstiloCheck.boton.merge(Letras.cifras),
                        color = if (elegido) c.sobreMarca else c.texto,
                        maxLines = 1,
                        modifier = Modifier.clearAndSetSemantics {},
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp).clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Text(metrica.bajo, style = Letras.caption, color = c.textoSecundario, modifier = Modifier.weight(1f))
            Text(metrica.alto, style = Letras.caption, color = c.textoSecundario, textAlign = TextAlign.End)
        }
    }
}

/**
 * Una fila de selección de ancho completo (56 de alto mínimo): la elegida, con fondo suave de marca, anillo verde y tilde.
 */
@Composable
internal fun FilaSeleccionCheck(texto: String, elegida: Boolean, alTocar: () -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val forma = RoundedCornerShape(Radio.control + 4.dp)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(forma)
            .background(if (elegida) c.marcaSuave else c.tarjeta)
            .border(if (elegida) 2.dp else 1.dp, if (elegida) c.marca else c.borde, forma)
            .toggleable(value = elegida, role = Role.Checkbox, onValueChange = { alTocar() })
            .semantics { stateDescription = if (elegida) "Marcada" else "Sin marcar" }
            .padding(horizontal = Espacio.m, vertical = Espacio.s),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Text(texto, style = MaterialTheme.typography.bodyLarge, fontWeight = if (elegida) FontWeight.SemiBold else FontWeight.Normal, color = c.texto, modifier = Modifier.weight(1f))
        Box(
            Modifier
                .size(26.dp)
                .clip(CircleShape)
                .then(if (elegida) Modifier.background(c.marca) else Modifier.border(1.5.dp, c.textoTerciario, CircleShape)),
            contentAlignment = Alignment.Center,
        ) {
            if (elegida) Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(16.dp))
        }
    }
}
