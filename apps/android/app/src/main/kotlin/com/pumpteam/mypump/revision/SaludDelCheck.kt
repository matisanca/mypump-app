package com.pumpteam.mypump.revision

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.reglas.SaludSemana

/**
 * Las filas de «Tu salud, últimos 7 días» (`SaludSemana.resumen`), leyendo los flujos de los que dependen. Con cuenta, la
 * salud (60 días) y la recuperación (14) de [ModeloSalud], con el interruptor del número. La demo no tiene datos de salud
 * (como iOS): sin filas, el bloque no aparece.
 */
@Composable
fun filasSaludSemana(salud: ModeloSalud?): List<SaludSemana.Fila> {
    if (salud == null) return emptyList()
    val filas by salud.salud.collectAsStateWithLifecycle()
    val serie by salud.recuperacion.collectAsStateWithLifecycle()
    val mostrar by salud.mostrarRecuperacion.collectAsStateWithLifecycle()
    val hoy by salud.fecha.collectAsStateWithLifecycle()
    return remember(filas, serie, mostrar, hoy) { SaludSemana.resumen(filas, serie, hoy, mostrar) }
}

/**
 * «Tu salud, últimos 7 días», adentro de la tarjeta del check y arriba de «Enviar mi check» (2.1.0, pedido de Mati del
 * 4-nov: «cuando manden la revisión que se incluya todo eso también»). Una fila por dato: etiqueta, valor y detalle. Lo
 * que se ve es lo que ya está en el servidor para esa semana; el coach lo lee con su panel. Sin filas no se muestra.
 */
@Composable
fun SaludDelCheck(filas: List<SaludSemana.Fila>, modifier: Modifier = Modifier) {
    if (filas.isEmpty()) return
    val c = MyPump.colores
    Column(modifier.fillMaxWidth().testTag("salud-del-check"), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Text("Tu salud, últimos 7 días", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        Text("Va con tu check: Mati lo ve junto a tus respuestas.", style = Letras.caption, color = c.textoSecundario)
        for (f in filas) {
            Row(
                Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}.testTag("salud-check-${f.clave}"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            ) {
                Text(f.etiqueta, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End) {
                    Text(f.valor, style = MaterialTheme.typography.bodyMedium.merge(Letras.cifras), fontWeight = FontWeight.SemiBold)
                    Text(f.detalle, style = Letras.caption, color = c.textoSecundario)
                }
            }
        }
    }
}
