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
import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.SaludSemana

/**
 * Las filas de «Tu salud, últimos 7 días» (`SaludSemana.resumen`), leyendo los flujos de los que dependen. Con cuenta, la
 * salud (60 días) y la recuperación (14) de [ModeloSalud], con el interruptor del número; en la demo ([salud] null y
 * [hoyDemo] con la fecha), las filas de salud de muestra, sin recuperación.
 */
@Composable
fun filasSaludSemana(salud: ModeloSalud?, hoyDemo: String?): List<SaludSemana.Fila> {
    if (salud == null) {
        val hoy = hoyDemo ?: return emptyList()
        return remember(hoy) { SaludSemana.resumen(MuestraSaludDemo.filas(hoy), emptyList(), hoy, mostrarScore = true) }
    }
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

/**
 * La salud de muestra de la demo (ficticia, sin datos de nadie): sueño, variabilidad, pulso en reposo y pasos de los
 * últimos 7 días, con la forma de `mypump_get_salud`. Solo alimenta «Tu salud, últimos 7 días» del check.
 */
internal object MuestraSaludDemo {
    private val porDia = listOf(
        // sueño (min), HRV (ms), pulso en reposo, pasos; de hoy hacia atrás
        listOf(412.0, 52.0, 58.0, 7400.0),
        listOf(438.0, 55.0, 57.0, 9150.0),
        listOf(395.0, 47.0, 60.0, 6200.0),
        listOf(450.0, 58.0, 56.0, 10300.0),
        listOf(421.0, 51.0, 58.0, 8050.0),
        listOf(405.0, 49.0, 59.0, 7700.0),
        listOf(444.0, 56.0, 57.0, 8900.0),
    )
    private val tipos = listOf("sueno_min", "hrv_ms", "fc_reposo", "pasos")

    fun filas(hoy: String): List<FilaSalud> {
        val n = DiaCalendario.numero(hoy) ?: return emptyList()
        return porDia.flatMapIndexed { i, valores ->
            val fecha = DiaCalendario.texto(n - i)
            tipos.zip(valores) { tipo, v -> FilaSalud(fecha, tipo, v, "demo", null) }
        }
    }
}
