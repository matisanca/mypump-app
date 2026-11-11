package com.pumpteam.mypump.suplementacion

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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloFeedback
import com.pumpteam.mypump.diseno.Alerta
import com.pumpteam.mypump.diseno.BotonAlerta
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaMenu
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.Inter
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.modelos.ItemSuplemento
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.ReglasSupleEstado
import com.pumpteam.mypump.reglas.ReglasSupleEstado.Estado
import com.pumpteam.mypump.reglas.TextosFeedback as T
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

/**
 * «¿Ya lo tenés?» (palanca `suple_estado`): cada suplemento una vez, con su marca. Se marca una sola vez y se puede cambiar.
 * Los protectores no aparecen acá. Con la palanca apagada o sin el servidor nuevo, la sección no existe. Gemelo de
 * `SeccionYaLoTenes` de SuplementacionView.swift.
 */
@Composable
internal fun SeccionYaLoTenes(modelo: ModeloFeedback?, items: List<ItemSuplemento>) {
    val m = modelo ?: return
    val estado by m.estado.collectAsStateWithLifecycle()
    val marcando by m.marcando.collectAsStateWithLifecycle()
    val e = estado ?: return
    if (!e.supleHabilitado) return
    val filas = remember(items, e.marcas) { ReglasSupleEstado.filas(items, e.marcas) }
    if (filas.isEmpty()) return
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val toque = LocalHapticFeedback.current
    var fallo by rememberSaveable { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth().padding(top = Espacio.xs).testTag("supl-estado"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Text(
                T.supleTitulo,
                style = MaterialTheme.typography.titleLarge.copy(fontFamily = Inter, fontWeight = FontWeight.Bold, fontSize = 20.sp),
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            Text(
                ReglasSupleEstado.resumen(filas),
                style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                color = c.textoSecundario,
                modifier = Modifier.testTag("supl-estado-resumen"),
            )
        }
        Column(Modifier.fillMaxWidth().superficieTarjeta()) {
            filas.forEachIndexed { n, f ->
                if (n > 0) Separador(sangria = Espacio.m)
                Fila(f, n, viajando = f.id in marcando) { nuevo ->
                    alcance.launch {
                        if (m.marcar(f.nombre, nuevo)) toque.performHapticFeedback(HapticFeedbackType.TextHandleMove) else fallo = true
                    }
                }
            }
        }
        Text(T.supleAyuda, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario, modifier = Modifier.padding(horizontal = 4.dp))
    }
    if (fallo) {
        Alerta(T.supleError, botones = listOf(BotonAlerta("OK", etiqueta = "supl-estado-error-ok", cancelar = true) { fallo = false }), alDescartar = { fallo = false })
    }
}

/** Un suplemento y su marca. Con la letra grande, la marca va debajo del nombre: nada se corta. */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun Fila(f: ReglasSupleEstado.Fila, n: Int, viajando: Boolean, alMarcar: (Estado) -> Unit) {
    val c = MyPump.colores
    var menu by remember { mutableStateOf(false) }
    val apilada = LocalDensity.current.fontScale > 1.3f
    val nombre: @Composable (Modifier) -> Unit = { m ->
        // El nombre lo dice la marca («Creatina, Comprado»): acá no se repite para TalkBack.
        Text(f.nombre, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = c.texto, modifier = m.clearAndSetSemantics {})
    }
    val marca: @Composable () -> Unit = {
        Box {
            // 48 de alto para el dedo; la píldora, de 40, queda centrada adentro.
            Box(
                Modifier
                    .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
                    .clip(CircleShape)
                    .clickable(enabled = !viajando, role = Role.Button, onClickLabel = T.supleMarcar) { menu = true }
                    .semantics { contentDescription = "${f.nombre}, ${f.estado?.marcado ?: T.supleMarcar}" }
                    .testTag("supl-estado-$n"),
                contentAlignment = Alignment.Center,
            ) {
                Marca(f.estado, viajando)
            }
            // El menú es otra ventana: las etiquetas como resource-id (UI Automator) se piden de nuevo, como en las hojas.
            DropdownMenu(
                expanded = menu,
                onDismissRequest = { menu = false },
                shape = FormaMenu,
                containerColor = c.tarjeta,
                shadowElevation = 12.dp,
                modifier = Modifier.semantics { testTagsAsResourceId = true },
            ) {
                for (e in Estado.entries) {
                    DropdownMenuItem(
                        text = { Text(e.accion, fontWeight = if (e == f.estado) FontWeight.SemiBold else FontWeight.Normal) },
                        leadingIcon = { if (e == f.estado) Icon(Iconos.Verificado, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp)) },
                        onClick = {
                            menu = false
                            alMarcar(e)
                        },
                        modifier = Modifier.testTag("supl-estado-opcion-${e.clave}"),
                    )
                }
            }
        }
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = Espacio.m, vertical = Espacio.xs), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        if (apilada) {
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xxs)) {
                nombre(Modifier.padding(top = Espacio.xxs))
                marca()
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                nombre(Modifier.weight(1f))
                marca()
            }
        }
        if (f.estado == Estado.NO_LO_CONSIGO) {
            Text(
                T.supleNoConsigoAviso,
                style = MaterialTheme.typography.bodySmall,
                color = c.textoSecundario,
                modifier = Modifier.padding(bottom = Espacio.xxs).testTag("supl-estado-no-consigo"),
            )
        }
    }
}

/** La píldora de la marca: «Marcar» sin elegir, o el estado con su color. */
@Composable
private fun Marca(estado: Estado?, viajando: Boolean) {
    val c = MyPump.colores
    val tono = when (estado) {
        Estado.TOMANDO -> c.exito
        Estado.COMPRADO -> c.marcaTexto
        Estado.NO_LO_CONSIGO -> c.alerta
        Estado.LO_DEJE -> c.textoSecundario
        null -> c.texto
    }
    val icono = when (estado) {
        Estado.TOMANDO -> Iconos.TildeEnCirculo
        Estado.COMPRADO -> Iconos.Bolsa
        Estado.NO_LO_CONSIGO -> Iconos.Buscar
        Estado.LO_DEJE -> Iconos.PausaEnCirculo
        null -> Iconos.Circulo
    }
    Row(
        Modifier
            .defaultMinSize(minHeight = 40.dp)
            .clip(CircleShape)
            .background(if (estado == null || estado == Estado.LO_DEJE) c.campo else tono.copy(alpha = 0.14f))
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .clearAndSetSemantics {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (viajando) {
            CircularProgressIndicator(Modifier.size(16.dp), color = tono, strokeWidth = 2.dp)
        } else {
            Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.size(16.dp))
        }
        Text(estado?.marcado ?: T.supleMarcar, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = tono)
        Icon(Iconos.ArribaAbajo, contentDescription = null, tint = tono.copy(alpha = 0.6f), modifier = Modifier.size(14.dp))
    }
}
