package com.pumpteam.mypump.revision

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloProgreso
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.ProgresoSemana
import com.pumpteam.mypump.reglas.SaludVista
import kotlinx.coroutines.launch
import com.pumpteam.mypump.salud.EncabezadoSalud
import com.pumpteam.mypump.salud.NotaSalud
import com.pumpteam.mypump.salud.cardRecuperacion
import com.pumpteam.mypump.salud.colorBanda

/**
 * «Recuperación», arriba de todo en Revisión (2.1.0, pedido de Mati del 4-nov: «la parte de salud […] la integraría con
 * la revisión […] que aparezca arriba de todo ahí»). Un resumen del caso que ya calcula `SaludVista.cardRecuperacion` (no
 * se repite la lógica): el score con su banda, o qué falta. Toda la tarjeta se toca y abre Salud en Recuperación, donde
 * está el detalle y el botón de conectar. Reemplaza al corazón que había arriba de Revisión. Gemela de la de iOS.
 *
 * Sin [salud] (la demo o sin cuenta) dice lo que se va a ver con la cuenta. Debajo va [TarjetaProgresoRevision].
 */
@Composable
fun TarjetaRecuperacionRevision(salud: ModeloSalud?, alAbrirSalud: () -> Unit, modifier: Modifier = Modifier) {
    TarjetaRevision("🔋", "Recuperación", "Ver sueño, corazón y cuerpo", "tarjeta-recuperacion-revision", alAbrirSalud, modifier) {
        if (salud == null) {
            Texto("Con tu cuenta, acá vas a ver tu recuperación de cada día.")
        } else {
            when (val card = cardRecuperacion(salud)) {
                is SaludVista.CardRecuperacion.ConScore -> ConScore(card.score)
                SaludVista.CardRecuperacion.Oculto -> Texto("Ocultaste el número de recuperación. Tocá para ver tus datos de salud.")
                is SaludVista.CardRecuperacion.Calibrando -> {
                    Texto("Aprendiendo tu normal: ${card.dias} de 14 días")
                    if (card.yaSe.isNotEmpty()) NotaSalud(card.yaSe)
                }
                is SaludVista.CardRecuperacion.ConectadoSinScore -> Texto(card.sinScore.frase(salud.textos))
                // El botón de conectar está adentro de Salud.
                SaludVista.CardRecuperacion.SinConectar -> Texto("Conectá tu reloj o Health Connect para ver tu recuperación de cada día.")
            }
        }
    }
}

/**
 * «Tu progreso», debajo de Recuperación (2.1.0, aprobada por Mati el 4-nov): lo que era la pestaña Progreso, en una línea
 * (`ProgresoSemana.linea`: récords, con el trofeo, ejercicios que subieron o sesiones de la semana). Sin línea (o en la demo), lo
 * genérico en gris. Toda la tarjeta abre Salud en Fuerza. Si el progreso todavía no se cargó, lo trae una vez.
 */
@Composable
fun TarjetaProgresoRevision(modelo: ModeloApp, alAbrirFuerza: () -> Unit, modifier: Modifier = Modifier) {
    val progreso by modelo.progreso.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val conRutina = modelo.rutina.collectAsStateWithLifecycle().value != null
    val tarjetas = progreso?.tarjetas?.collectAsStateWithLifecycle()?.value.orEmpty()
    val alcance = LocalAlcanceApp.current
    // Como al abrir Fuerza: solo si no hay tarjetas o faltó la red, en el alcance de la app (cambiar de pestaña no la corta).
    // Espera a la rutina: sin ella la carga deja la lista vacía y la tarjeta quedaba en lo genérico (revisión, hallazgo 1).
    LaunchedEffect(progreso, esDemo, conRutina) {
        val p = progreso ?: return@LaunchedEffect
        // En la demo solo hay progreso con el historial inventado (no toca la red).
        if (!conRutina) return@LaunchedEffect
        if (p.tarjetas.value.isEmpty() || p.estado.value == ModeloProgreso.Estado.SIN_RED) alcance.launch { modelo.cargarProgreso() }
    }
    val hoy = FechaLocal.hoy()
    val linea = remember(tarjetas, esDemo, hoy) {
        ProgresoSemana.linea(tarjetas.map { ProgresoSemana.ejercicio(it.nombre, it.filas) }, hoy)
    }
    val c = MyPump.colores
    TarjetaRevision("📈", "Tu progreso", "Ver fuerza y récords", "tarjeta-progreso-revision", alAbrirFuerza, modifier,
        pista = "Abre tu fuerza y tus récords") {
        if (linea != null) {
            // Con un récord, el trofeo a la izquierda (decorativo: el texto ya dice «Récord»).
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                if (linea.record) {
                    Icon(Iconos.Trofeo, contentDescription = null, tint = c.alerta, modifier = Modifier.size(20.dp).testTag("trofeo-progreso"))
                }
                Texto(linea.texto)
            }
        } else {
            Text("Tu fuerza y tus récords, ejercicio por ejercicio.", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        }
    }
}

/** Lo que comparten las tarjetas de arriba de Revisión: encabezado, contenido y la fila del pie con chevron, toda tocable. */
@Composable
private fun TarjetaRevision(
    icono: String,
    titulo: String,
    pie: String,
    etiqueta: String,
    alTocar: () -> Unit,
    modifier: Modifier,
    pista: String = "Abre Salud",
    contenido: @Composable ColumnScope.() -> Unit,
) {
    val c = MyPump.colores
    Column(
        modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .clickable(role = Role.Button, onClickLabel = pista, onClick = alTocar)
            .padding(Espacio.m)
            .testTag(etiqueta),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        EncabezadoSalud(icono, titulo)
        contenido()
        HorizontalDivider(color = c.borde)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Text(
                pie,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = c.marcaTexto,
                modifier = Modifier.weight(1f),
            )
            Icon(Iconos.Chevron, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
private fun Texto(texto: String) {
    Text(texto, style = MaterialTheme.typography.bodyMedium.merge(Letras.cifras), fontWeight = FontWeight.Medium)
}

/** El score grande con «de 100», la banda en su color, la confianza (sin tocar: la tarjeta entera abre Salud) y una línea. */
@Composable
private fun ConScore(s: SaludVista.ConScore) {
    val c = MyPump.colores
    val color = colorBanda(s.banda, apagado = s.confianza?.apagado == true)
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("${s.fila.score ?: 0}", style = Numeros.grande, color = color, modifier = Modifier.testTag("score-revision"))
            Text("de 100", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.padding(bottom = 6.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(s.bandaTexto, style = MaterialTheme.typography.titleMedium, color = color)
            s.confianza?.let {
                Text(
                    it.etiqueta,
                    style = MaterialTheme.typography.labelMedium,
                    color = c.textoSecundario,
                    modifier = Modifier.clip(CircleShape).background(c.campo).padding(horizontal = 9.dp, vertical = 5.dp),
                )
            }
        }
    }
    // Como iOS: la frase o, sin frase, el primer motivo con su flecha.
    (s.frase ?: s.motivos.firstOrNull()?.let { "${if (it.sube) "↑" else "↓"} ${it.texto}" })
        ?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
    s.notaVieja?.let { NotaSalud(it) }
}
