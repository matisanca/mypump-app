package com.pumpteam.mypump.revision

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.PantallaConTitulo
import com.pumpteam.mypump.diseno.Radio
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

/**
 * Revisión: lo de la semana (fotos, check, peso), Mi reloj y Mi Día. De acá cuelga Mis datos (el ícono de arriba, como
 * en iOS). Por ahora en Android: el encabezado de la semana, el aviso de plan incompleto y la entrada a Mis datos; las
 * tarjetas (que ya tienen su modelo en `:core:datos`) son la etapa que sigue.
 */
@Composable
fun RevisionPantalla(modelo: ModeloApp, alAbrirMisDatos: () -> Unit) {
    PantallaConTitulo(
        "Revisión",
        acciones = {
            IconButton(onClick = alAbrirMisDatos, modifier = Modifier.testTag("mis-datos")) {
                Icon(Iconos.Persona, contentDescription = "Mis datos", modifier = Modifier.size(28.dp))
            }
        },
    ) {
        Text(
            semanaActual(),
            style = MaterialTheme.typography.bodyMedium,
            color = MyPump.colores.textoSecundario,
            modifier = Modifier.padding(horizontal = Espacio.m).padding(top = 0.dp),
        )
        AvisoPlanIncompleto(modelo, Modifier.padding(horizontal = Espacio.m))
        EstadoVacio(
            icono = Iconos.Checklist,
            titulo = "Revisión",
            texto = "Las fotos, el check, el peso y Mi Día todavía no están listos en la app nueva de Android.",
            modifier = Modifier.weight(1f).testTag("en-construccion-revision"),
        )
    }
}

/**
 * GEN-05 (`avisarPlanIncompleto`): al plan publicado le falta algo. No es para el cliente sino para la captura que le
 * manda a Mati (qué republicar): discreto, con el detalle chico y gris.
 */
@Composable
fun AvisoPlanIncompleto(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val entreno by modelo.entreno.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    // Lo que mira `avisoPlanIncompleto`: los problemas de la dieta y los de la rutina (se leen para recomponer).
    val problemasDieta by modelo.problemasDieta.collectAsStateWithLifecycle()
    val problemasRutina = entreno?.problemas?.collectAsStateWithLifecycle()?.value
    if (esDemo || (problemasDieta.isEmpty() && problemasRutina.isNullOrEmpty())) return
    val aviso = modelo.avisoPlanIncompleto ?: return
    val c = MyPump.colores
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.control + 4.dp))
            .background(c.alerta.copy(alpha = 0.10f))
            .padding(Espacio.m)
            .semantics(mergeDescendants = true) {}
            .testTag("aviso-plan-incompleto"),
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(Iconos.Alerta, contentDescription = null, tint = c.alerta, modifier = Modifier.size(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(aviso.first, style = MaterialTheme.typography.bodyMedium)
            Text(aviso.second, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
        }
    }
}

private val MESES = listOf(
    "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
)

/** "Semana del 12 al 18 de octubre" (de lunes a domingo); si cambia el mes, "Semana del 28 de septiembre al 4 de octubre". */
fun semanaActual(hoy: LocalDate = LocalDate.now()): String {
    val lunes = hoy.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val domingo = lunes.plusDays(6)
    val desde = if (lunes.month == domingo.month) "${lunes.dayOfMonth}" else "${lunes.dayOfMonth} de ${MESES[lunes.monthValue - 1]}"
    return "Semana del $desde al ${domingo.dayOfMonth} de ${MESES[domingo.monthValue - 1]}"
}
