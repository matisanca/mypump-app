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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloEstudios
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.guia.VerdeGuia
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.Controles
import com.pumpteam.mypump.reglas.TextosControles as T

// «Tu próximo control de salud» (pedido de Mati, 11/11; palanca `controles_app`). Desde `avisar_desde` y mientras el control
// siga programado, una tarjeta arriba de todo en la primera pestaña con un botón grande «Ver mis estudios» que lleva a
// Estudios en un toque (el mismo camino que la tarjeta de estudios pendientes). Nunca dice por qué ni nombra el ciclo.
// Todo sale de lo que ya trajo `ModeloEstudios`: acá no se llama a nada.

/** El modelo de Estudios, solo con las dos palancas, la sección a la vista y fuera de la demo. */
@Composable
private fun estudiosConControles(modelo: ModeloApp): ModeloEstudios? {
    val palanca by modelo.palanca.collectAsStateWithLifecycle()
    val m by modelo.estudios.collectAsStateWithLifecycle()
    estadoDeEstudios(modelo) ?: return null
    return m?.takeIf { palanca.controlesApp }
}

/** La tarjeta de arriba de Entreno, con el patrón de la destacada: verde, letra grande y el botón blanco de ancho completo. */
@Composable
fun TarjetaControlInicioDe(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val navegacion = LocalNavegacion.current
    val m = estudiosConControles(modelo) ?: return
    val c by m.controles.collectAsStateWithLifecycle()
    val t = m.tarjetaControl(c) ?: return
    val abrir = { navegacion?.irAEstudios(resuelto = true) ?: Unit }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.tarjeta))
            .background(VerdeGuia)
            // TalkBack lee la tarjeta de una (qué y cuándo); el botón, aparte.
            .semantics { contentDescription = "${t.titulo}. ${t.cuando}. ${t.nota}" }
            .clickable(onClickLabel = t.boton, role = Role.Button, onClick = abrir)
            .testTag("control-tarjeta-inicio")
            .padding(Espacio.m + 2.dp),
        verticalArrangement = Arrangement.spacedBy(Espacio.s + 4.dp),
    ) {
        // Con la letra muy grande, el ícono va arriba y el texto usa todo el ancho (como en el iPhone).
        val apilada = LocalDensity.current.fontScale >= 1.5f
        val cabecera: @Composable (@Composable () -> Unit) -> Unit = { contenido ->
            if (apilada) Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) { contenido() }
            else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s + 4.dp)) { contenido() }
        }
        cabecera {
            Box(Modifier.size(52.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
                Icon(Iconos.Calendario, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
            }
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    T.cejaInicio.uppercase(),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.08.em,
                    color = Color.White,
                    modifier = Modifier.clearAndSetSemantics {},
                )
                Text(t.titulo, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Color.White,
                     modifier = Modifier.testTag("control-tarjeta-inicio-texto"))
                Text(t.cuando, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = Color.White,
                     modifier = Modifier.testTag("control-tarjeta-inicio-cuando"))
            }
        }
        Text(t.nota, style = MaterialTheme.typography.bodyLarge, color = Color.White, modifier = Modifier.testTag("control-tarjeta-inicio-nota"))
        Button(
            onClick = abrir,
            modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).testTag("control-tarjeta-inicio-boton"),
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = VerdeGuia),
            elevation = null,
        ) {
            Icon(Iconos.FlechaDerecha, contentDescription = null, modifier = Modifier.size(20.dp))
            Text(t.boton, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                 modifier = Modifier.padding(start = Espacio.xs))
        }
    }
}

/** «Tu recorrido»: el próximo control y los últimos, como hitos con fecha. Nada si no hay. */
@Composable
fun HitosControlRecorrido(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val m = estudiosConControles(modelo) ?: return
    val c by m.controles.collectAsStateWithLifecycle()
    val hitos = m.hitosControl(c)
    if (hitos.isEmpty()) return
    val k = MyPump.colores
    Column(modifier.fillMaxWidth().testTag("recorrido-controles"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Text(T.hitosTitulo, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = k.texto,
             modifier = Modifier.semantics { heading() })
        hitos.forEachIndexed { n, h -> Hito(h, Modifier.testTag("recorrido-control-$n")) }
    }
}

@Composable
private fun Hito(h: Controles.Hito, modifier: Modifier) {
    val k = MyPump.colores
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(k.marcaSuave)
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(if (h.estado == T.hitoProximo) Iconos.Calendario else Iconos.Tilde, contentDescription = null, tint = k.marcaTexto,
             modifier = Modifier.size(24.dp).padding(top = 2.dp))
        // El estado va abajo, como texto: con la letra más grande no se corta.
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(h.titulo, style = MaterialTheme.typography.titleMedium, color = k.texto)
            Text(h.cuando, style = MaterialTheme.typography.bodyLarge, color = k.textoSecundario)
            Text(h.estado, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = k.marcaTexto)
        }
    }
}
