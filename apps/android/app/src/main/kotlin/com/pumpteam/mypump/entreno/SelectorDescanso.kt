package com.pumpteam.mypump.entreno

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Oro
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.SobreOro
import com.pumpteam.mypump.reglas.DescansoPropio
import com.pumpteam.mypump.reglas.TiempoEntreno
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * E2 (2.0.3, gemelo de SelectorDescanso.swift): el descanso de este ejercicio, de 0:30 a 5:00 en pasos de 15 s. Lo
 * elegido queda en el teléfono para el ejercicio (por su clave) y le gana al del plan; «Volver al del plan» lo borra.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class, ExperimentalLayoutApi::class)
@Composable
fun HojaDescanso(motor: ModeloEntreno, t: ModeloEntreno.Tarjeta, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    var elegido by remember { mutableIntStateOf(DescansoPropio.valido(t.descansoSegundos) ?: DescansoPropio.opciones.minBy { kotlin.math.abs(it - t.descansoSegundos) }) }

    fun cerrar() {
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-descanso"),
    ) {
        EncabezadoHoja(
            "Descanso",
            subtitulo = "Para este ejercicio",
            cancelar = AccionHoja("Cancelar", "cancelar-descanso", alTocar = ::cerrar),
            confirmar = AccionHoja("Guardar", "guardar-descanso") {
                motor.elegirDescanso(t.lugar, elegido)
                cerrar()
            },
        )
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(Espacio.m),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
        ) {
            Text(
                TiempoEntreno.fmtTiempo(elegido.toDouble()),
                style = MaterialTheme.typography.displaySmall.merge(Letras.cifras).copy(fontWeight = FontWeight.SemiBold),
                color = c.texto,
                modifier = Modifier.align(Alignment.CenterHorizontally).testTag("descanso-elegido"),
            )
            FlowRow(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Espacio.xs, Alignment.CenterHorizontally),
                verticalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                for (s in DescansoPropio.opciones) {
                    val marcado = s == elegido
                    val texto = TiempoEntreno.fmtTiempo(s.toDouble())
                    Box(
                        Modifier
                            .width(68.dp)
                            .defaultMinSize(minHeight = 44.dp)
                            .clip(RoundedCornerShape(Radio.control))
                            .background(if (marcado) c.marca else c.campo)
                            .clickable(role = Role.RadioButton) { elegido = s }
                            .semantics { selected = marcado; contentDescription = texto }
                            .testTag("opcion-descanso-$s"),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            texto,
                            style = MaterialTheme.typography.labelLarge.merge(Letras.cifras),
                            color = if (marcado) c.sobreMarca else c.texto,
                        )
                    }
                }
            }
            if (t.descansoPropio) {
                Text(
                    "Volver al del plan (${TiempoEntreno.fmtTiempo(t.descansoPlan.toDouble())})",
                    style = MaterialTheme.typography.labelLarge,
                    color = c.marcaTexto,
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .clip(RoundedCornerShape(Radio.control))
                        .clickable(role = Role.Button) {
                            motor.elegirDescanso(t.lugar, null)
                            cerrar()
                        }
                        .padding(horizontal = Espacio.m, vertical = 12.dp)
                        .testTag("descanso-del-plan"),
                )
            }
        }
    }
}

/**
 * E3 (2.0.3): «Récord: +2,5 kg» apenas se confirma la serie, en el oro de los récords (relleno con texto negro), con el
 * háptico de éxito. Se va solo a los 3 s o al tocarlo.
 */
@Composable
fun AvisoRecordVista(motor: ModeloEntreno, lugar: String) {
    val aviso by motor.avisoRecord.collectAsState()
    val haptico = LocalHapticFeedback.current
    val a = aviso?.takeIf { it.lugar == lugar }
    LaunchedEffect(a?.id) {
        val id = a?.id ?: return@LaunchedEffect
        haptico.performHapticFeedback(HapticFeedbackType.Confirm)
        delay(3000)
        motor.descartarRecord(id)
    }
    AnimatedVisibility(a != null, enter = fadeIn() + scaleIn(initialScale = 0.9f), exit = fadeOut()) {
        val texto = a?.texto ?: ""
        Row(
            Modifier
                .clip(CircleShape)
                .background(Oro)
                .clickable { a?.let { motor.descartarRecord(it.id) } }
                .padding(horizontal = 14.dp, vertical = 8.dp)
                .semantics { liveRegion = LiveRegionMode.Polite; contentDescription = texto }
                .testTag("aviso-record"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Iconos.Trofeo, contentDescription = null, tint = SobreOro, modifier = Modifier.size(18.dp))
            Text(texto, style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = SobreOro)
        }
    }
}
