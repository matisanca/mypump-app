package com.pumpteam.mypump.entreno

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.reglas.Preparacion
import kotlinx.coroutines.launch

/**
 * E1 (2.0.3, gemelo de PreparacionBloque.swift): «Calentamiento y aproximación», la indicación liviana antes de las
 * series efectivas. No es un lugar para cargar: filas de texto (etiqueta a la izquierda, «5 × 35 kg» a la derecha) sobre
 * un relleno apenas distinto del de las efectivas, sin campos ni controles. Tocar una fila la atenúa con un tilde chico y
 * arranca el descanso de 30 s; tocarla de nuevo lo deshace. Nada se guarda como carga. «Ocultar» lo colapsa a una línea
 * y se recuerda por ejercicio.
 */
@Composable
fun PreparacionBloque(motor: ModeloEntreno, lugar: String, series: List<Preparacion.Serie>, sinKg: Boolean, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    // Para recomponer al tocar o al ocultar: el estado vive en el motor.
    val hechasTodas by motor.preparacionHechas.collectAsState()
    val ocultas by motor.preparacionOcultas.collectAsState()
    val oculta = remember(ocultas, lugar) { motor.preparacionOculta(lugar) }
    val hechas = remember(hechasTodas, lugar) { motor.preparacionHecha(lugar) }
    var ayuda by rememberSaveable { mutableStateOf(false) }
    // Sin el kg de la última vez no hay número que mostrar: solo las reps.
    val sinReferencia = sinKg || series.any { it.kg == null && !it.barraSola }
    // El `quaternarySystemFill` de iOS: un gris apenas distinto del fondo.
    val relleno = if (c.oscuro) Color(0x2E767680) else Color(0x14747480)

    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.control))
            .background(relleno)
            .padding(horizontal = Espacio.s, vertical = if (oculta) 6.dp else Espacio.xs)
            .animateContentSize()
            .testTag("bloque-preparacion"),
    ) {
        if (oculta) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "$TITULO · ${series.size}",
                    style = Letras.subtitulo,
                    color = c.textoSecundario,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                BotonOcultar(oculta = true) { motor.ocultarPreparacion(lugar, false) }
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    TITULO,
                    style = Letras.subtitulo.copy(fontWeight = FontWeight.Medium),
                    color = c.textoSecundario,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.semantics { heading() },
                )
                BotonAyuda { ayuda = true }
                Spacer(Modifier.weight(1f))
                BotonOcultar(oculta = false) { motor.ocultarPreparacion(lugar, true) }
            }
            Text(
                if (sinReferencia) "Usalas para encontrar tu peso de trabajo · 30 s entre cada una"
                else "30 s de descanso entre cada una · no se anotan",
                style = Letras.caption,
                color = c.textoTerciario,
                modifier = Modifier.padding(top = 2.dp, bottom = 6.dp).testTag("leyenda-preparacion"),
            )
            series.forEachIndexed { i, s ->
                if (i > 0) HorizontalDivider(thickness = 0.5.dp, color = c.separador)
                FilaPreparacion(i, s, sinKg, hecha = i in hechas) { motor.tocarPreparacion(lugar, i) }
            }
        }
    }
    if (ayuda) AyudaPreparacion { ayuda = false }
}

private const val TITULO = "Calentamiento y aproximación"

@Composable
private fun BotonOcultar(oculta: Boolean, alTocar: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = 32.dp)
            .clip(RoundedCornerShape(8.dp))
            .clickable(role = Role.Button, onClick = alTocar)
            .padding(horizontal = 4.dp)
            .testTag("ocultar-preparacion"),
        contentAlignment = Alignment.Center,
    ) {
        Text(if (oculta) "Mostrar" else "Ocultar", style = Letras.subtitulo, color = MyPump.colores.marcaTexto)
    }
}

/** El «?» del encabezado: un círculo de trazo fino, en terciario como en iOS. */
@Composable
private fun BotonAyuda(alTocar: () -> Unit) {
    val c = MyPump.colores
    Box(
        Modifier
            .size(32.dp)
            .clip(CircleShape)
            .clickable(onClickLabel = "Cómo se arma la preparación", role = Role.Button, onClick = alTocar)
            .semantics { contentDescription = "Cómo se arma la preparación" }
            .testTag("ayuda-preparacion"),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(15.dp).border(1.2.dp, c.textoTerciario, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text("?", style = Letras.caption2.copy(fontWeight = FontWeight.Bold), color = c.textoTerciario)
        }
    }
}

@Composable
private fun FilaPreparacion(i: Int, s: Preparacion.Serie, sinKg: Boolean, hecha: Boolean, alTocar: () -> Unit) {
    val c = MyPump.colores
    val haptico = LocalHapticFeedback.current
    val letraGrande = LocalDensity.current.fontScale >= 1.3f
    val opacidad by animateFloatAsState(if (hecha) 0.4f else 1f, label = "hecha")
    val accesible = etiquetaAccesible(s, sinKg, hecha)
    val pista = if (hecha) "desmarcarla" else "arrancar el descanso"
    Row(
        Modifier
            // La etiqueta antes de `clearAndSetSemantics`, que borra la de lo que va adentro.
            .testTag("preparacion-${i + 1}")
            .fillMaxWidth()
            .heightIn(min = if (letraGrande) 52.dp else 40.dp)
            .clickable(onClickLabel = pista, role = Role.Button) {
                haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
                alTocar()
            }
            .clearAndSetSemantics {
                contentDescription = accesible
                role = Role.Button
                onClick(label = pista) { alTocar(); true }
            }
            .alpha(opacidad),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Text(
            if (s.tipo == Preparacion.Tipo.POTENCIACION) "Potenciación" else s.etiqueta,
            style = Letras.subtitulo,
            color = c.texto,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (s.opcional) {
            Text(
                "opcional",
                style = Letras.caption2.copy(fontWeight = FontWeight.Medium),
                color = c.textoTerciario,
                modifier = Modifier.clip(CircleShape).background(c.campo).padding(horizontal = 6.dp, vertical = 1.dp),
            )
        }
        Spacer(Modifier.weight(1f))
        Text(cantidad(s, sinKg), style = Letras.subtitulo.merge(Letras.cifras), maxLines = 1)
        AnimatedVisibility(hecha, enter = fadeIn() + scaleIn(initialScale = 0.5f), exit = fadeOut()) {
            Icon(Iconos.Tilde, contentDescription = null, tint = c.exito, modifier = Modifier.size(14.dp))
        }
    }
}

/** «5 × 35 kg»: las reps en secundario, los kg en primario y semibold; sin kg de referencia, «5 reps». */
@Composable
private fun cantidad(s: Preparacion.Serie, sinKg: Boolean) = buildAnnotatedString {
    val c = MyPump.colores
    val reps = s.reps.replace('-', '–')
    val kg = if (sinKg) null else if (s.barraSola) "barra sola" else s.textoKg?.let { "$it kg" }
    if (kg != null) {
        withStyle(SpanStyle(color = c.textoSecundario)) { append("$reps × ") }
        withStyle(SpanStyle(color = c.texto, fontWeight = FontWeight.SemiBold)) { append(kg) }
    } else {
        withStyle(SpanStyle(color = c.textoSecundario)) { append("$reps reps") }
    }
}

private fun etiquetaAccesible(s: Preparacion.Serie, sinKg: Boolean, hecha: Boolean): String {
    val partes = mutableListOf(s.etiqueta, "${s.reps.replace("-", " a ")} repeticiones")
    s.textoKg?.takeIf { !sinKg }?.let { partes += if (s.barraSola) it else "$it kilos" }
    s.nota?.let { partes += it }
    if (hecha) partes += "hecha"
    return partes.joinToString(", ")
}

/** El «?» del bloque: el criterio en pocas líneas. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
private fun AyudaPreparacion(alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcance = rememberCoroutineScope()
    fun cerrar() {
        alcance.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-ayuda-preparacion"),
    ) {
        EncabezadoHoja("Antes de las efectivas", confirmar = AccionHoja("Listo", "listo-ayuda-preparacion", alTocar = ::cerrar))
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(Espacio.m).padding(bottom = Espacio.l),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
        ) {
            PuntoAyuda("Calentamiento", "Muy liviano, de 16 a 20 reps, para que entren en calor la articulación y el músculo. Va solo en el primer ejercicio de cada músculo.")
            PuntoAyuda("Aproximaciones", "Pocas reps (5, nunca más de 6), subiendo el peso hasta el de tu primera serie efectiva. Lejos del fallo: preparan y no cansan. La subida, lo más explosiva que puedas.")
            PuntoAyuda("Potenciación (opcional)", "De 1 a 3 reps con un poco más que tu peso de trabajo. Suele darte 1 o 2 reps extra en las efectivas. Si no te sentís bien, salteala.")
            PuntoAyuda("Los kilos", "Se calculan solos con el que pongas en tu primera serie efectiva.")
            PuntoAyuda("Descanso", "De 20 a 30 segundos entre cada una. No se anotan: solo cuentan las efectivas.")
        }
    }
}

@Composable
private fun PuntoAyuda(titulo: String, texto: String) {
    val c = MyPump.colores
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(titulo, style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.texto)
        Text(texto, style = Letras.subtitulo, color = c.textoSecundario)
    }
}
