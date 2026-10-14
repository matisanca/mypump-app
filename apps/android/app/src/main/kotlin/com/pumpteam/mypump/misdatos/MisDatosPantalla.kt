package com.pumpteam.mypump.misdatos

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.pumpteam.mypump.ModeloAppViewModel
import com.pumpteam.mypump.acceso.URL_BORRADO
import com.pumpteam.mypump.acceso.URL_PRIVACIDAD
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.IconoAzulejo
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.PantallaConTitulo
import com.pumpteam.mypump.diseno.PieSeccion
import com.pumpteam.mypump.diseno.RotuloSeccion
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.abrirEnNavegador
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.respaldo.HojaFuentes
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Mis datos (D3 de la paridad): un lugar fijo, colgado de Revisión, para la IA (D7), la apariencia (D5), el respaldo
 * científico, la privacidad y el borrado (D9), con la forma de los ajustes del teléfono.
 *
 * Todavía no están en Android: la recuperación y Salud (Health Connect) y el recordatorio del domingo (las notificaciones).
 */
@Composable
fun MisDatosPantalla(vm: ModeloAppViewModel, modelo: ModeloApp, alVolver: () -> Unit) {
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val iaDisponible by modelo.consentimientoIADisponible.collectAsStateWithLifecycle()
    val consentimiento by modelo.consentimientoIA.collectAsStateWithLifecycle()
    val oscuro by vm.apariencia.oscuroGuardado.collectAsStateWithLifecycle()
    var fuentes by remember { mutableStateOf(false) }
    var informe by rememberSaveable { mutableStateOf(false) }
    val contexto = LocalContext.current
    val c = MyPump.colores

    if (informe) {
        BackHandler { informe = false }
        InformeActualizacion(vm.registroMigracion, alVolver = { informe = false })
        return
    }

    PantallaConTitulo("Mis datos", alVolver = alVolver, desplazable = true, modifier = Modifier.testTag("mis-datos-pantalla")) {
        // D7: la decisión sobre la IA, para cambiarla cuando quiera (solo si el servidor puede respetarla).
        if (iaDisponible && !esDemo) {
            val pie = when (consentimiento) {
                true ->
                    "Lee tus mensajes del chat, las fotos que mandes a analizar y tu check para ayudar a Mati (OpenAI y Anthropic; los datos de salud van sin tu nombre). Si lo apagás, ninguna IA lee tus datos."
                false -> "Apagado: ninguna IA lee tus datos. Te contesta Mati y las fotos no se analizan."
                null ->
                    "Todavía no elegiste: te lo preguntamos antes de tu primer mensaje, foto o check. Si lo prendés, la IA ayuda con el chat, las fotos y tu revisión semanal."
            }
            Seccion("Inteligencia artificial", pie = pie, etiquetaPie = "pie-ia") {
                FilaInterruptor(
                    icono = Iconos.Chispas,
                    color = c.marcaTexto,
                    titulo = "Asistente de IA",
                    prendido = consentimiento == true,
                    // En el alcance del ViewModel: salir de Mis datos no corta el envío (igual queda en la cola).
                    alCambiar = { v -> vm.viewModelScope.launch { modelo.decidirConsentimientoIA(v) } },
                    etiqueta = "asistente-ia",
                )
            }
        }

        Seccion(
            "Apariencia",
            pie = if (oscuro) "La app queda oscura aunque el teléfono esté en claro." else "La app sigue al teléfono: clara u oscura según cómo lo tengas.",
        ) {
            FilaInterruptor(
                icono = Iconos.Luna,
                color = c.sueno,
                titulo = "Siempre en modo oscuro",
                prendido = oscuro,
                alCambiar = vm.apariencia::forzarOscuro,
                etiqueta = "tema-oscuro",
            )
        }

        Seccion("Tu información") {
            FilaEnlace(Iconos.Libro, c.marcaTexto, "Respaldo científico del plan", etiqueta = "mis-datos-respaldo") { fuentes = true }
            Separador(sangria = 58.dp)
            FilaEnlace(Iconos.Privacidad, c.agua, "Política de privacidad") { abrirEnNavegador(contexto, URL_PRIVACIDAD) }
            Separador(sangria = 58.dp)
            FilaEnlace(Iconos.Papelera, c.peligro, "Eliminar mis datos", colorTexto = c.peligro) { abrirEnNavegador(contexto, URL_BORRADO) }
        }

        var hayInforme by remember { mutableStateOf(false) }
        LaunchedEffect(Unit) { hayInforme = withContext(Dispatchers.IO) { vm.registroMigracion.isFile } }
        Seccion(null, pie = "MyPump no es un dispositivo médico. Ante cualquier duda de salud, consultá a tu médico.") {
            FilaValor("Versión", vm.version)
            if (hayInforme) {
                Separador(sangria = Espacio.m)
                FilaEnlace(null, c.textoSecundario, "Informe de la actualización", etiqueta = "informe-actualizacion") { informe = true }
            }
        }
    }
    if (fuentes) HojaFuentes(alCerrar = { fuentes = false })
}

/** Un grupo de filas en tarjeta, con su rótulo arriba y la letra chica abajo, pegada a la tarjeta. */
@Composable
private fun Seccion(titulo: String?, pie: String? = null, etiquetaPie: String? = null, filas: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.padding(horizontal = Espacio.m)) {
        if (titulo != null) RotuloSeccion(titulo, Modifier.padding(start = 0.dp))
        Column(Modifier.fillMaxWidth().superficieTarjeta(), content = filas)
        if (pie != null) PieSeccion(pie, if (etiquetaPie != null) Modifier.testTag(etiquetaPie) else Modifier)
    }
}

/** Fila con interruptor: toda la fila lo cambia (y el lector de pantalla la anuncia como un interruptor). */
@Composable
private fun FilaInterruptor(icono: ImageVector, color: Color, titulo: String, prendido: Boolean, alCambiar: (Boolean) -> Unit, etiqueta: String) {
    val c = MyPump.colores
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = prendido, role = Role.Switch, onValueChange = alCambiar)
            .padding(horizontal = Espacio.m, vertical = Espacio.xs)
            .testTag(etiqueta),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        IconoAzulejo(icono, color)
        Text(titulo, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Switch(
            checked = prendido,
            onCheckedChange = null,
            colors = SwitchDefaults.colors(
                checkedTrackColor = c.marcaVivo,
                checkedThumbColor = Color.White,
                checkedBorderColor = c.marcaVivo,
            ),
        )
    }
}

/** Fila que abre algo (una hoja, una página). */
@Composable
private fun FilaEnlace(
    icono: ImageVector?,
    color: Color,
    titulo: String,
    colorTexto: Color = MyPump.colores.texto,
    etiqueta: String? = null,
    alTocar: () -> Unit,
) {
    val c = MyPump.colores
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClick = alTocar)
            .padding(horizontal = Espacio.m, vertical = Espacio.xs)
            .then(if (etiqueta != null) Modifier.testTag(etiqueta) else Modifier),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        if (icono != null) IconoAzulejo(icono, color)
        Text(titulo, style = MaterialTheme.typography.bodyLarge, color = colorTexto, modifier = Modifier.weight(1f))
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun FilaValor(titulo: String, valor: String) {
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = Espacio.m),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(titulo, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Text(valor, style = MaterialTheme.typography.bodyLarge, color = MyPump.colores.textoSecundario)
    }
}

/**
 * Lo que hizo la migración desde la app vieja (`legado/registro.log`): conteos y estados, sin tokens ni contenido. Para el
 * soporte sin cables: se lee acá y se puede compartir con Mati.
 */
@Composable
private fun InformeActualizacion(archivo: File, alVolver: () -> Unit) {
    var texto by remember { mutableStateOf("") }
    val contexto = LocalContext.current
    LaunchedEffect(archivo) { texto = withContext(Dispatchers.IO) { runCatching { archivo.readText() }.getOrDefault("") } }
    PantallaConTitulo(
        "Informe de la actualización",
        alVolver = alVolver,
        desplazable = true,
        acciones = {
            if (texto.isNotEmpty()) {
                IconButton(onClick = {
                    val enviar = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, texto)
                    contexto.startActivity(Intent.createChooser(enviar, "Compartir el informe").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }) { Icon(Iconos.Compartir, contentDescription = "Compartir el informe") }
            }
        },
    ) {
        SelectionContainer(Modifier.padding(horizontal = Espacio.m)) {
            Text(
                texto.ifEmpty { "Todavía no hay nada registrado." },
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
            )
        }
    }
}
