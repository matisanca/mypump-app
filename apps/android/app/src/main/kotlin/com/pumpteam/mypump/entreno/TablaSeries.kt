package com.pumpteam.mypump.entreno

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.CamposSerie
import com.pumpteam.mypump.reglas.FilaSerie
import com.pumpteam.mypump.reglas.HistorialEntreno
import com.pumpteam.mypump.reglas.SerieLocal
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * La tabla de series del motor (TablaSeries.swift): campos grandes que invitan a cargar. Lo de la última vez aparece
 * sugerido en gris y un toque en ✓ lo registra (SER-01); el kg se hereda de la serie anterior (SER-03); el RIR nunca se
 * completa solo (SER-02); lo imposible se rechaza y lo raro se pregunta (SER-05); tocar ✓ de nuevo desconfirma (SER-06).
 * Al confirmar arranca el descanso (salvo el calentamiento) y, con la última, el ejercicio queda completo.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TablaSeries(
    motor: ModeloEntreno,
    v: VistaEntreno,
    lugar: String,
    t: ModeloEntreno.Tarjeta,
    preguntador: Preguntador,
    alCompletarDia: (ModeloEntreno.DiaCompletado) -> Unit,
) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val foco = LocalFocusManager.current
    val haptico = LocalHapticFeedback.current
    val filas = t.filas
    val sinKg = filas.firstOrNull()?.sinKg ?: t.sinKg
    val activa = filas.indexOfFirst { it.activa && !it.confirmada }.takeIf { it >= 0 }
    val series = v.dia.ejercicios[lugar]?.series ?: emptyList()
    val letraGrande = LocalDensity.current.fontScale >= 1.3f

    // El háptico de éxito cada vez que se confirma una serie.
    var confirmadasAntes by remember { mutableIntStateOf(t.confirmadas) }
    LaunchedEffect(t.confirmadas) {
        if (t.confirmadas > confirmadasAntes) haptico.performHapticFeedback(HapticFeedbackType.Confirm)
        confirmadasAntes = t.confirmadas
    }

    fun tocarCheck(i: Int, f: FilaSerie) {
        if (f.confirmada) {
            alcance.launch { motor.editarSerie(lugar, i) }
            return
        }
        foco.clearFocus()
        alcance.launch {
            val completo = motor.confirmarSerie(lugar, i) { preguntador.preguntar(it) }
            if (completo != null) alCompletarDia(completo)
        }
    }

    Tarjeta(Modifier.testTag("tabla-series")) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text("Series", style = Letras.titulo3, modifier = Modifier.weight(1f).semantics { heading() })
            Text(
                "${t.confirmadas} de ${filas.size}",
                style = Letras.subtitulo.copy(fontWeight = FontWeight.Medium).merge(Letras.cifras),
                color = if (t.confirmadas == filas.size && filas.isNotEmpty()) c.marcaTexto else c.textoSecundario,
                modifier = Modifier.testTag("series-confirmadas"),
            )
        }

        t.variantes?.let { va ->
            // SER-07: el agarre o el nivel (vale para las series que se confirmen después).
            val actual = t.varianteActual ?: va.opciones.firstOrNull() ?: ""
            Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(bottom = 2.dp)) {
                Text(va.etiqueta, style = Letras.caption.copy(fontWeight = FontWeight.SemiBold), color = c.textoSecundario)
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("variantes")) {
                    va.opciones.forEachIndexed { i, op ->
                        SegmentedButton(
                            selected = op == actual,
                            onClick = { motor.elegirVariante(lugar, op) },
                            shape = SegmentedButtonDefaults.itemShape(i, va.opciones.size),
                            enabled = !v.dia.diaFinalizado,
                            icon = {},
                            colors = SegmentedButtonDefaults.colors(
                                activeContainerColor = MaterialTheme.colorScheme.secondaryContainer,
                                activeContentColor = c.texto,
                                inactiveContainerColor = Color.Transparent,
                                inactiveContentColor = c.texto,
                                activeBorderColor = c.borde,
                                inactiveBorderColor = c.borde,
                            ),
                            modifier = Modifier.testTag("variante-$op"),
                        ) { Text(op, maxLines = 1, fontWeight = if (op == actual) FontWeight.SemiBold else FontWeight.Normal) }
                    }
                }
            }
        }

        if (filas.isEmpty()) {
            Text("Este ejercicio no tiene series esta semana.", style = Letras.subtitulo, color = c.textoSecundario)
        } else {
            Row(
                modifier = Modifier.fillMaxWidth().clearAndSetSemantics {},
                horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                val rotulo = Letras.caption2.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp)
                // Como el `fixedSize()` de iOS: el rótulo entero aunque la columna (la del número) sea más angosta.
                Text(
                    if (letraGrande) "#" else "SERIE",
                    style = rotulo,
                    color = c.textoSecundario,
                    textAlign = TextAlign.Center,
                    softWrap = false,
                    maxLines = 1,
                    modifier = Modifier.width(30.dp).wrapContentWidth(unbounded = true),
                )
                Text("REPS", style = rotulo, color = c.textoSecundario, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                if (!sinKg) Text("KG", style = rotulo, color = c.textoSecundario, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                Text("RIR", style = rotulo, color = c.textoSecundario, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(44.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                filas.forEachIndexed { i, f ->
                    val s = series.getOrNull(i) ?: SerieLocal()
                    FilaDeSerie(motor, lugar, i, f, s, series, sinKg, alTocarCheck = { tocarCheck(i, f) })
                }
            }
            Pista(activa, activa?.let { filas[it] }, alRegistrar = ::tocarCheck, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

@Composable
private fun FilaDeSerie(
    motor: ModeloEntreno,
    lugar: String,
    i: Int,
    f: FilaSerie,
    s: SerieLocal,
    series: List<SerieLocal>,
    sinKg: Boolean,
    alTocarCheck: () -> Unit,
) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val marcada = s.aviso != null && !f.confirmada
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            val activa = f.activa && !f.confirmada
            Box(
                Modifier
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(if (activa) c.marca else if (f.confirmada) Color.Transparent else c.campo)
                    .clearAndSetSemantics {},
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "${i + 1}",
                    style = Letras.subtitulo.copy(fontWeight = FontWeight.Bold).merge(Letras.cifras),
                    color = if (activa) c.sobreMarca else if (f.confirmada) c.marcaTexto else c.textoSecundario,
                )
            }
            CampoSerie(
                valor = s.reps,
                sugerencia = f.placeholderReps.ifEmpty { "–" },
                teclado = KeyboardType.Number,
                confirmada = f.confirmada,
                marcada = marcada,
                etiqueta = "Repeticiones de la serie ${i + 1}",
                alCambiar = { motor.escribir(lugar, i, "reps", it) },
                modifier = Modifier.weight(1f).testTag("campo-reps-${i + 1}"),
            )
            if (!sinKg) {
                // Con las reps escritas y el kg vacío se guarda el kg de la serie anterior (SER-03): la sugerencia muestra ese.
                val heredado = if (!f.confirmada && s.reps.isNotEmpty() && s.kg.isEmpty()) HistorialEntreno.kgHeredable(series, i) else ""
                val sugerido = heredado.ifEmpty { f.placeholderKg }
                CampoSerie(
                    valor = Bonito.coma(s.kg),
                    sugerencia = Bonito.coma(sugerido.ifEmpty { "–" }),
                    teclado = KeyboardType.Decimal,
                    confirmada = f.confirmada,
                    marcada = marcada,
                    etiqueta = "Kilos de la serie ${i + 1}",
                    alCambiar = { motor.escribir(lugar, i, "kg", it) },
                    modifier = Modifier.weight(1f).testTag("campo-kg-${i + 1}"),
                )
            }
            SelectorRir(s.rir, f.confirmada, i, Modifier.weight(1f)) { n -> alcance.launch { motor.elegirRir(lugar, i, n) } }
            BotonCheck(i, f, alTocarCheck)
        }
        val aviso = s.aviso
        if (!aviso.isNullOrEmpty() && !f.confirmada) {
            Row(Modifier.padding(start = 38.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Icon(Iconos.Alerta, contentDescription = null, tint = c.peligro, modifier = Modifier.size(13.dp))
                Text(aviso, style = Letras.caption, color = c.peligro, modifier = Modifier.testTag("aviso-serie-${i + 1}"))
            }
        }
    }
}

/**
 * Un campo de la tabla: grande, centrado, con la sugerencia en gris y teñido de marca cuando la serie está hecha.
 * Mientras se escribe el campo es dueño de su texto y cada cambio va al motor (que normaliza: coma a punto en kg, solo
 * dígitos en reps). Lo que cambia el motor (confirmar, desconfirmar, otra variante) entra cuando no se está escribiendo.
 *
 * SER-04: al enfocarlo se selecciona todo, como el `select()` de la web: lo que se escribe reemplaza lo anterior. Sin eso,
 * 80 kg corregido a 7 quedaba "807" o "780" (revisión del 14-oct, hallazgo 2). Va un instante después del foco: el toque
 * ubica el cursor después de enfocar y pisaría la selección.
 */
@Composable
private fun CampoSerie(
    valor: String,
    sugerencia: String,
    teclado: KeyboardType,
    confirmada: Boolean,
    marcada: Boolean,
    etiqueta: String,
    alCambiar: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = MyPump.colores
    val foco = LocalFocusManager.current
    var local by remember { mutableStateOf(TextFieldValue(valor)) }
    var enfocado by remember { mutableStateOf(false) }
    LaunchedEffect(valor, enfocado) {
        if (!enfocado && local.text != valor) local = TextFieldValue(valor)
    }
    LaunchedEffect(enfocado) {
        if (!enfocado) return@LaunchedEffect
        delay(SELECCION_MS)
        local = local.copy(selection = TextRange(0, local.text.length))
    }
    val forma = RoundedCornerShape(12.dp)
    BasicTextField(
        value = local,
        onValueChange = { nuevo ->
            val cambio = nuevo.text != local.text
            local = nuevo
            if (cambio) alCambiar(nuevo.text)
        },
        enabled = !confirmada,
        singleLine = true,
        textStyle = MaterialTheme.typography.titleLarge.copy(
            fontFamily = null,
            fontWeight = FontWeight.SemiBold,
            fontSize = 20.sp,
            textAlign = TextAlign.Center,
            color = c.texto,
        ).merge(Letras.cifras),
        keyboardOptions = KeyboardOptions(keyboardType = teclado, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { foco.clearFocus() }),
        cursorBrush = SolidColor(c.marcaTexto),
        modifier = modifier
            .heightIn(min = 48.dp)
            .onFocusChanged { enfocado = it.isFocused }
            .semantics {
                contentDescription = etiqueta
                if (local.text.isEmpty() && sugerencia != "–") stateDescription = "sugerido $sugerencia"
            },
        decorationBox = { campo ->
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .clip(forma)
                    .background(if (confirmada) c.marcaSuave else c.campo)
                    .then(if (enfocado || marcada) Modifier.border(2.dp, if (marcada) c.peligro else c.marcaVivo, forma) else Modifier)
                    .padding(horizontal = 4.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (local.text.isEmpty()) {
                    Text(
                        sugerencia,
                        style = MaterialTheme.typography.titleLarge.copy(fontFamily = null, fontWeight = FontWeight.SemiBold, fontSize = 20.sp).merge(Letras.cifras),
                        color = c.textoTerciario,
                        textAlign = TextAlign.Center,
                        maxLines = 1,
                        modifier = Modifier.clearAndSetSemantics {},
                    )
                }
                campo()
            }
        },
    )
}

/** Cuánto después del foco se selecciona todo (el toque ubica el cursor al soltar). */
private const val SELECCION_MS = 80L

/** RIR 0-5 en un menú, con la leyenda de la web; nunca se completa solo. "–" es sin dato, que no es lo mismo que 0. */
@Composable
private fun SelectorRir(rir: String, confirmada: Boolean, i: Int, modifier: Modifier = Modifier, elegir: (Int) -> Unit) {
    val c = MyPump.colores
    var abierto by remember { mutableStateOf(false) }
    Box(modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(if (confirmada) c.marcaSuave else c.campo)
                .clickable(role = Role.DropdownList) { abierto = true }
                .semantics {
                    contentDescription = "RIR de la serie ${i + 1}"
                    stateDescription = if (rir.isEmpty()) "sin cargar" else "$rir, ${CamposSerie.leyendaRir(rir)}"
                }
                .testTag("rir-serie-${i + 1}"),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                rir.ifEmpty { "–" },
                style = MaterialTheme.typography.titleLarge.copy(fontFamily = null, fontWeight = FontWeight.SemiBold, fontSize = 20.sp).merge(Letras.cifras),
                color = if (rir.isEmpty()) c.textoSecundario else c.texto,
            )
            Icon(Iconos.ArribaAbajo, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(12.dp))
        }
        DropdownMenu(expanded = abierto, onDismissRequest = { abierto = false }, containerColor = c.tarjeta) {
            for (n in 0..5) {
                DropdownMenuItem(
                    text = { Text("$n · ${CamposSerie.leyendaRir(n.toString())}") },
                    onClick = {
                        abierto = false
                        elegir(n)
                    },
                    leadingIcon = {
                        if (rir == n.toString()) {
                            Icon(Iconos.Tilde, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                        } else {
                            Spacer(Modifier.size(18.dp))
                        }
                    },
                    modifier = Modifier.testTag("rir-$n"),
                )
            }
        }
    }
}

/** El ✓ de la fila: confirma (lo escrito o lo sugerido) o, si ya está hecha, la desconfirma para corregirla. */
@Composable
private fun BotonCheck(i: Int, f: FilaSerie, alTocar: () -> Unit) {
    val c = MyPump.colores
    Box(
        modifier = Modifier
            .size(width = 44.dp, height = 48.dp)
            .clickable(enabled = f.puedeConfirmar, role = Role.Button, onClick = alTocar)
            .semantics {
                contentDescription = if (f.confirmada) "Serie ${i + 1} hecha. Tocá para corregirla" else (f.tituloConfirmar ?: "Confirmar serie ${i + 1}")
            }
            .testTag("confirmar-serie-${i + 1}"),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(if (f.confirmada) c.marca else Color.Transparent)
                .then(
                    if (f.confirmada) Modifier else Modifier.border(2.dp, if (f.puedeConfirmar) c.marcaVivo else c.textoTerciario, CircleShape),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Iconos.Tilde,
                contentDescription = null,
                tint = if (f.confirmada) c.sobreMarca else if (f.puedeConfirmar) c.marcaTexto else c.textoTerciario,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

/**
 * La pista de la fila activa: lo de la última vez a un toque, o la calibración la primera vez. Como en la web
 * (`data-sugconfirm`, cliente.html:4044 y :4307), la pista de la última vez ES un botón: tocarla registra la serie igual
 * que el ✓, con las mismas preguntas (reabrir el día, "¿Está bien cargado?"). En la 101 de iOS era solo texto y
 * "Tocá para registrar" no hacía nada (lo encontró Mati el 14-oct).
 */
@Composable
private fun Pista(i: Int?, f: FilaSerie?, alRegistrar: (Int, FilaSerie) -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val p = f?.pista
    val calibracion = f?.calibracion
    if (p != null && i != null) {
        // "Tocá para registrar lo de la última vez: **80 kg × 10**. O editá si hiciste otra cosa.", con la puntuación de una frase.
        val antes = p.antes.replace("✓ ", "").replace(" · ", "")
        val despues = p.despues.replace(" — ", "").trim()
        Row(
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(c.marcaSuave)
                .clickable(enabled = f.puedeConfirmar, role = Role.Button) { alRegistrar(i, f) }
                .padding(horizontal = 10.dp, vertical = 8.dp)
                .semantics(mergeDescendants = true) { contentDescription = "Registrar lo de la última vez: ${Bonito.carga(p.negrita)}" }
                .testTag("registrar-ultima-vez"),
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Icon(Iconos.Toque, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.padding(top = 1.dp).size(14.dp))
            Text(
                buildAnnotatedString {
                    append("$antes: ")
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = c.texto)) { append(Bonito.carga(p.negrita)) }
                    append(". ${despues.replaceFirstChar { it.uppercase() }}.")
                },
                style = Letras.caption,
                color = c.textoSecundario,
                modifier = Modifier.testTag("pista-serie"),
            )
        }
    } else if (calibracion != null) {
        Row(modifier.testTag("pista-serie"), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Icon(Iconos.Mira, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.padding(top = 1.dp).size(14.dp))
            Text(Bonito.sinEmoji(calibracion), style = Letras.caption, color = c.textoSecundario)
        }
    }
}
