package com.pumpteam.mypump.diseno

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Las hojas de iOS 26 para los `ModalBottomSheet` de Material (Mati, 15-oct: Android «igual que el iPhone»): las puntas
// de arriba muy redondeadas, el asa corta y gris, y la barra de arriba con «Cancelar» a la izquierda, el título al centro
// y lo que confirma a la derecha, en cápsulas de vidrio (la de Material ponía el título grande a la izquierda y un botón
// de texto suelto).

/** Las puntas de arriba de una hoja, como en iOS 26. */
val FormaHoja = RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp)

/** Los menús que se despliegan (el `Menu` de iOS): puntas redondeadas en lugar de las casi rectas de Material. */
val FormaMenu = RoundedCornerShape(18.dp)

/** El asa de iOS: una cápsula gris corta y sin el margen alto del asa de Material. */
@Composable
fun AsaHoja() {
    Box(
        Modifier
            .padding(top = 6.dp, bottom = 6.dp)
            .size(width = 36.dp, height = 5.dp)
            .clip(CircleShape)
            .background(MyPump.colores.textoTerciario.copy(alpha = 0.55f)),
    )
}

/** Un botón de la barra de la hoja. */
class AccionHoja(val texto: String, val etiqueta: String? = null, val habilitada: Boolean = true, val alTocar: () -> Unit)

/**
 * La barra de arriba de una hoja: el título (y un subtítulo) al centro, [cancelar] a la izquierda y [confirmar] a la
 * derecha, en cápsulas de vidrio. El título queda centrado en la hoja y, si no entra entre las cápsulas, pasa a dos
 * renglones. [izquierda] reemplaza a «Cancelar» (la flecha de volver de una hoja con dos pasos).
 */
@Composable
fun EncabezadoHoja(
    titulo: String,
    modifier: Modifier = Modifier,
    subtitulo: String? = null,
    etiquetaSubtitulo: String? = null,
    cancelar: AccionHoja? = null,
    confirmar: AccionHoja? = null,
    izquierda: (@Composable () -> Unit)? = null,
) {
    val c = MyPump.colores
    Layout(
        contents = listOf(
            {
                when {
                    izquierda != null -> izquierda()
                    cancelar != null -> CapsulaHoja(cancelar, principal = false)
                }
            },
            {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        titulo,
                        style = MaterialTheme.typography.titleMedium,
                        color = c.texto,
                        textAlign = TextAlign.Center,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.semantics { heading() },
                    )
                    if (subtitulo != null) {
                        Text(
                            subtitulo,
                            // El caption de iOS (12) con dígitos de ancho fijo, como `Letras.caption` de Entreno.
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, lineHeight = 16.sp, fontFeatureSettings = "tnum"),
                            color = c.textoSecundario,
                            textAlign = TextAlign.Center,
                            modifier = if (etiquetaSubtitulo != null) Modifier.testTag(etiquetaSubtitulo) else Modifier,
                        )
                    }
                }
            },
            { if (confirmar != null) CapsulaHoja(confirmar, principal = true) },
        ),
        modifier = modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 2.dp, bottom = 8.dp),
    ) { (izquierda, centro, derecha), restricciones ->
        val libre = restricciones.copy(minWidth = 0, minHeight = 0)
        val izq = izquierda.firstOrNull()?.measure(libre)
        val der = derecha.firstOrNull()?.measure(libre)
        val hueco = 8.dp.roundToPx()
        val lado = maxOf(izq?.width ?: 0, der?.width ?: 0).let { if (it > 0) it + hueco else 0 }
        val ancho = restricciones.maxWidth
        val medio = centro.firstOrNull()?.measure(Constraints(maxWidth = (ancho - 2 * lado).coerceAtLeast(0)))
        val alto = maxOf(izq?.height ?: 0, der?.height ?: 0, medio?.height ?: 0, 44.dp.roundToPx())
        layout(ancho, alto) {
            izq?.placeRelative(0, (alto - izq.height) / 2)
            der?.placeRelative(ancho - der.width, (alto - der.height) / 2)
            medio?.placeRelative((ancho - medio.width) / 2, (alto - medio.height) / 2)
        }
    }
}

@Composable
private fun CapsulaHoja(a: AccionHoja, principal: Boolean) {
    val c = MyPump.colores
    Box(
        Modifier
            .heightIn(min = 44.dp)
            .vidrio(CircleShape, elevacion = 6.dp)
            .then(if (a.etiqueta != null) Modifier.testTag(a.etiqueta) else Modifier)
            .clickable(enabled = a.habilitada, role = Role.Button, onClick = a.alTocar)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            a.texto,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (principal) FontWeight.SemiBold else FontWeight.Normal,
            color = if (a.habilitada) c.marcaTexto else c.textoTerciario,
            maxLines = 1,
        )
    }
}
