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
import com.pumpteam.mypump.diseno.FilaDestino
import com.pumpteam.mypump.diseno.Letra
import com.pumpteam.mypump.diseno.Separador
import androidx.compose.foundation.layout.Box
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
 * «Recuperación» y «Tu progreso» en una sola tarjeta de dos filas con azulejo suave (2.3.0; antes dos tarjetas de tres
 * pisos con emojis). Ocupan bastante menos diciendo lo mismo, y las fotos y el check suben.
 */
@Composable
fun TarjetaComoVengo(salud: ModeloSalud?, modelo: ModeloApp, alAbrirSalud: () -> Unit, alAbrirFuerza: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().superficieTarjeta()) {
        TarjetaRecuperacionRevision(salud, alAbrirSalud)
        Separador(sangria = 64.dp)
        TarjetaProgresoRevision(modelo, alAbrirFuerza)
    }
}

/**
 * «Recuperación», arriba en Revisión (2.1.0, pedido de Mati del 4-nov: «la parte de salud […] la integraría con la
 * revisión»). Un resumen del caso que ya calcula `SaludVista.cardRecuperacion` (no se repite la lógica): el score con su
 * banda, o qué falta. Toda la fila se toca y abre Salud en Recuperación, donde está el detalle y el botón de conectar.
 * Gemela de la de iOS.
 *
 * Sin [salud] (la demo o sin cuenta) dice lo que se va a ver con la cuenta.
 */
@Composable
fun TarjetaRecuperacionRevision(salud: ModeloSalud?, alAbrirSalud: () -> Unit, modifier: Modifier = Modifier) {
    val card = salud?.let { cardRecuperacion(it) }
    val conScore = (card as? SaludVista.CardRecuperacion.ConScore)?.score
    // La línea de la fila: lo mismo que decía la tarjeta completa, en corto.
    val resumen = when {
        salud == null || card == null -> "Con tu cuenta, acá vas a ver tu recuperación de cada día."
        conScore != null -> listOfNotNull(
            conScore.bandaTexto,
            conScore.confianza?.etiqueta,
            conScore.frase ?: conScore.motivos.firstOrNull()?.let { "${if (it.sube) "↑" else "↓"} ${it.texto}" },
            conScore.notaVieja,
        ).joinToString(" · ")
        card is SaludVista.CardRecuperacion.Oculto -> "Ocultaste el número de recuperación. Tocá para ver tus datos de salud."
        card is SaludVista.CardRecuperacion.Calibrando -> listOfNotNull("Aprendiendo tu normal: ${card.dias} de 14 días", card.yaSe.ifEmpty { null }).joinToString(". ")
        card is SaludVista.CardRecuperacion.ConectadoSinScore -> card.sinScore.frase(salud.textos)
        // El botón de conectar está adentro de Salud.
        else -> "Conectá tu reloj o Health Connect para ver tu recuperación de cada día."
    }
    FilaDestino(
        Iconos.Corazon, "Recuperación", resumen, alAbrirSalud,
        modifier.testTag("tarjeta-recuperacion-revision"),
        etiquetaToque = "Abre Salud",
    ) {
        if (conScore != null) {
            Text(
                "${conScore.fila.score ?: 0}",
                style = Letra.dato,
                color = colorBanda(conScore.banda, apagado = conScore.confianza?.apagado == true),
                modifier = Modifier.testTag("score-revision"),
            )
        }
    }
}

/**
 * «Tu progreso», debajo de Recuperación (2.1.0, aprobada por Mati el 4-nov): lo que era la pestaña Progreso, en una línea
 * (`ProgresoSemana.linea`: récords, con el trofeo, ejercicios que subieron o sesiones de la semana). Sin línea (o en la demo), lo
 * genérico. Toda la fila abre Salud en Fuerza. Si el progreso todavía no se cargó, lo trae una vez.
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
        if (p.tarjetas.value.isEmpty() || p.estado.value == ModeloProgreso.Estado.SIN_RED) alcance.launch { modelo.cargarProgresoSiHaceFalta() }
    }
    val hoy = FechaLocal.hoy()
    val linea = remember(tarjetas, esDemo, hoy) {
        ProgresoSemana.linea(tarjetas.map { ProgresoSemana.ejercicio(it.nombre, it.filas) }, hoy)
    }
    val c = MyPump.colores
    val record = linea?.record == true
    FilaDestino(
        // Con un récord, el trofeo (decorativo: el texto ya dice «Récord»).
        if (record) Iconos.Trofeo else Iconos.Tendencia,
        "Tu progreso",
        linea?.texto ?: "Tu fuerza y tus récords, ejercicio por ejercicio.",
        alAbrirFuerza,
        modifier.testTag("tarjeta-progreso-revision"),
        color = if (record) c.record else c.marcaTexto,
        etiquetaToque = "Abre tu fuerza y tus récords",
    ) {
        // Lo que buscan las pruebas: hay trofeo solo con récord.
        if (record) Box(Modifier.size(1.dp).testTag("trofeo-progreso"))
    }
}
