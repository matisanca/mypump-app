package com.pumpteam.mypump.guia

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.raiz.AnclaRevision
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.ReglasListaPrevia

// «Antes de la videollamada» (2.3.0, palanca `lista_previa`; gemelo de ListaPreviaVistas.swift): lo que falta para la
// videollamada de comienzo. Los textos son los de `apps/shared/vectores/lista_previa.json` (`ReglasListaPrevia`). Siempre
// desplegada, arriba de todo en Entreno:
// · con la tarjeta de la videollamada (reserva de comienzo), DENTRO de esa tarjeta, debajo de lo que ya tiene;
// · sin tarjeta de videollamada, como tarjeta propia en ese mismo lugar;
// · con una reserva de revisión, no se muestra.
// Solo lee: tocar un punto que falta lleva directo a donde se resuelve (la guía de videos o las fotos de Revisión).

/**
 * La lista que hay para mostrar, o null. Con la palanca apagada el modelo no tiene nada (ni llama a nada); la demo trae la
 * suya (`historial.json`), sin palanca.
 */
@Composable
fun vistaListaPrevia(modelo: ModeloApp): ReglasListaPrevia.Vista? {
    val m = modelo.listaPrevia.collectAsStateWithLifecycle().value ?: return null
    val v by m.vista.collectAsStateWithLifecycle()
    return v
}

/** La lista sola, en el lugar de la tarjeta de la videollamada. [abrirGuia] null sin guía: esa fila no es un botón. */
@Composable
fun TarjetaListaPrevia(vista: ReglasListaPrevia.Vista, abrirGuia: (() -> Unit)?, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Box(
        modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .border(1.5.dp, c.marca.copy(alpha = 0.45f), RoundedCornerShape(Radio.tarjeta))
            .padding(20.dp)
            .testTag("lista-previa"),
    ) {
        ListaPreviaBloque(vista, sobreVerde = false, conIcono = true, abrirGuia = abrirGuia)
    }
}

/**
 * El contenido: título y resumen, una fila por punto y el consejo. [sobreVerde]: dentro de la tarjeta de la videollamada
 * cuando ya se puede entrar (fondo verde, letras claras).
 */
@Composable
fun ListaPreviaBloque(vista: ReglasListaPrevia.Vista, sobreVerde: Boolean, conIcono: Boolean, abrirGuia: (() -> Unit)?, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val navegacion = LocalNavegacion.current
    val grande = LocalDensity.current.fontScale >= 1.5f
    val principal = if (sobreVerde) Color.White else c.texto
    val secundario = if (sobreVerde) Color.White.copy(alpha = 0.86f) else c.textoSecundario
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        // La cabecera: con letra muy grande, el resumen baja debajo del título.
        val titulo: @Composable (Modifier) -> Unit = { m ->
            Row(m, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                if (conIcono) {
                    Box(Modifier.size(30.dp).background(c.marca, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Iconos.Checklist, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(17.dp))
                    }
                }
                Text(
                    ReglasListaPrevia.TITULO,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = principal,
                    modifier = Modifier.weight(1f, fill = false).semantics { heading() }.testTag("lista-previa-titulo"),
                )
            }
        }
        val resumen: @Composable () -> Unit = {
            vista.resumen?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (sobreVerde) VerdeGuia else c.marcaTexto,
                    modifier = Modifier
                        .background(if (sobreVerde) Color.White else c.marcaSuave, CircleShape)
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                        .testTag("lista-previa-resumen"),
                )
            }
        }
        if (grande) {
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                titulo(Modifier)
                resumen()
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                titulo(Modifier.weight(1f))
                resumen()
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            for (item in vista.items) {
                // A dónde lleva la fila, o null si no es un botón (hecha, sin destino, o sin a dónde ir).
                val accion: (() -> Unit)? = when (item.destino) {
                    ReglasListaPrevia.Destino.GUIA -> abrirGuia
                    ReglasListaPrevia.Destino.FOTOS -> navegacion?.let { n -> { n.irARevision(AnclaRevision.FOTOS) } }
                    null -> null
                }
                Fila(item, accion, sobreVerde, principal, secundario)
            }
        }
        Text(
            ReglasListaPrevia.CONSEJO,
            style = MaterialTheme.typography.bodySmall,
            color = secundario,
            modifier = Modifier.testTag("lista-previa-consejo"),
        )
    }
}

/** Un punto de la lista. Con [accion], toda la fila es un botón grande con su fondo y la flecha. */
@Composable
private fun Fila(item: ReglasListaPrevia.Item, accion: (() -> Unit)?, sobreVerde: Boolean, principal: Color, secundario: Color) {
    val c = MyPump.colores
    val forma = RoundedCornerShape(Radio.control + 4.dp)
    val base = Modifier.fillMaxWidth().testTag("lista-previa-${item.clave}")
    val fila = if (accion != null) {
        base
            .heightIn(min = 56.dp)
            .clip(forma)
            .background(if (sobreVerde) Color.White.copy(alpha = 0.18f) else c.marcaSuave)
            .clickable(role = Role.Button, onClick = accion)
            .padding(horizontal = Espacio.s, vertical = Espacio.s)
            // Se lee como un solo botón, con el texto de la regla.
            .clearAndSetSemantics {
                contentDescription = item.accesible
                role = Role.Button
                onClick { accion(); true }
            }
    } else {
        base.padding(vertical = 4.dp).clearAndSetSemantics { contentDescription = item.accesible }
    }
    Row(fila, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Icon(
            if (item.hecho) Iconos.TildeEnCirculo else Iconos.Circulo,
            contentDescription = null,
            tint = if (item.hecho) (if (sobreVerde) Color.White else c.marcaVivo) else secundario,
            modifier = Modifier.size(26.dp),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                item.titulo,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (accion != null) FontWeight.SemiBold else FontWeight.Normal,
                color = principal,
            )
            item.detalle?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = secundario) }
        }
        if (accion != null) {
            Icon(Iconos.Chevron, contentDescription = null, tint = if (sobreVerde) Color.White else c.marcaTexto, modifier = Modifier.size(18.dp))
        }
    }
}
