package com.pumpteam.mypump.estudios

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.findRootCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.guia.VerdeGuia
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.EstadoEstudios
import com.pumpteam.mypump.reglas.Estudios
import com.pumpteam.mypump.reglas.TextosEstudios as T

// Que un estudio pedido o una orden nueva no se pierdan (pedido de Mati, 10-nov; hay alumnos mayores): una tarjeta arriba
// de Entreno que lleva a Estudios con un toque, un punto en el camino a Mis datos y la etiqueta «Nuevo» en la tarjeta.
// Ningún texto dice qué estudio ni por qué. Todo sale de lo que ya trajo el `get`: acá no se llama a nada.

/** Lo que se sabe de Estudios ahora; null con la palanca apagada, sin la sección o en la demo. */
@Composable
fun estadoDeEstudios(modelo: ModeloApp): EstadoEstudios? {
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val m by modelo.estudios.collectAsStateWithLifecycle()
    val e = m?.estado?.collectAsStateWithLifecycle()?.value
    return if (esDemo) null else e
}

/** Hay un estudio pedido o una orden sin ver: el punto de la pestaña, del botón de Mis datos y de la fila. */
@Composable
fun hayNovedadDeEstudios(modelo: ModeloApp): Boolean = estadoDeEstudios(modelo)?.let(Estudios::hayNovedad) == true

/**
 * La tarjeta de arriba de Entreno, con el patrón de la destacada de «Tu guía»: verde, con el botón blanco de ancho completo.
 * Con algo sin ver dice que hay un estudio o una orden nueva y el botón es «Ver»; sin novedad y con algo por hacer, «Tenés
 * un estudio para hacer» y «Subir resultado». Las dos llevan a Estudios, a esa tarjeta. Sin nada de eso no existe.
 */
@Composable
fun TarjetaEstudiosInicioDe(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val navegacion = LocalNavegacion.current
    val t = estadoDeEstudios(modelo)?.let(Estudios::tarjetaInicio) ?: return
    val abrir = { navegacion?.irAEstudios(resuelto = true) ?: Unit }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.tarjeta))
            .background(VerdeGuia)
            // TalkBack lee la tarjeta de una (la sección y el aviso); el botón, aparte.
            .semantics { contentDescription = "${T.entrada}. ${t.titulo}" }
            .clickable(onClickLabel = t.boton, role = Role.Button, onClick = abrir)
            .testTag("estudios-tarjeta-inicio")
            .padding(Espacio.m + 2.dp),
        verticalArrangement = Arrangement.spacedBy(Espacio.s + 4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s + 4.dp)) {
            Box(Modifier.size(52.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
                Icon(Iconos.Documento, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    T.entrada.uppercase(),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.08.em,
                    color = Color.White,
                    modifier = Modifier.clearAndSetSemantics {},
                )
                Text(
                    t.titulo,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    modifier = Modifier.testTag("estudios-tarjeta-inicio-texto"),
                )
            }
        }
        Button(
            onClick = abrir,
            modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).testTag("estudios-tarjeta-inicio-boton"),
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = VerdeGuia),
            elevation = null,
        ) {
            Icon(if (t.nueva) Iconos.FlechaDerecha else Iconos.FlechaArriba, contentDescription = null, modifier = Modifier.size(20.dp))
            Text(
                t.boton,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(start = Espacio.xs),
            )
        }
    }
}

/** El punto de «hay algo sin ver». TalkBack lo lee como «Novedad». */
@Composable
fun PuntoNovedad(modifier: Modifier = Modifier, lado: Dp = 12.dp) {
    Box(modifier.size(lado).clip(CircleShape).background(MyPump.colores.marcaVivo).semantics { contentDescription = T.novedad })
}

/** «Nuevo», en la tarjeta que el alumno todavía no vio: punto y texto, no solo color. */
@Composable
fun EtiquetaNuevo(modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Row(
        modifier.clip(CircleShape).background(c.marca).padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(c.sobreMarca))
        Text(T.nuevo, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = c.sobreMarca)
    }
}

/**
 * Avisa si esto está de verdad en pantalla: al menos la mitad de su alto (o de lo que entra en la pantalla, si es más
 * alto). Lo que quedó más abajo sin desplazarse no cuenta.
 */
fun Modifier.alEstarALaVista(accion: (Boolean) -> Unit): Modifier = onGloballyPositioned { c ->
    val alto = c.size.height
    val visto = c.isAttached && alto > 0 && c.boundsInWindow().height >= minOf(alto, c.findRootCoordinates().size.height) * 0.5f
    accion(visto)
}
