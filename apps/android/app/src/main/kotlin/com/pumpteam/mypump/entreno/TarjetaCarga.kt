package com.pumpteam.mypump.entreno

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.isSpecified
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import com.pumpteam.mypump.diseno.Archivo
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.Interruptor
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Segmentado
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.CamposSerie
import com.pumpteam.mypump.reglas.CargaSimple
import com.pumpteam.mypump.reglas.Js
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Los kilos como se escriben acá: con coma. */
object KgTexto {
    fun de(v: Double?): String = v?.let { Js.texto(it).replace(".", ",") } ?: ""

    /** El texto del campo como número, o null si está vacío. */
    fun numero(t: String): Double? = CamposSerie.normalizar("kg", t).takeIf { it.isNotEmpty() }?.toDoubleOrNull()
}

/** Cuánto después del foco se selecciona todo (el toque ubica el cursor al soltar). */
private const val SELECCION_MS = 80L

/**
 * La carga única del ejercicio y sus series, en la lista de Entreno o en la página del ejercicio (gemelo de TarjetaCarga.swift).
 * Lo que se confirma va en el panel fijo de abajo ([PanelCarga]). Las series hechas se tocan para corregirlas: no se desmarcan.
 */
@Composable
fun TarjetaCarga(motor: ModeloEntreno, v: VistaEntreno, lugar: String, t: ModeloEntreno.Tarjeta, enLista: Boolean = false) {
    val s = motor.cargaSimple(lugar) ?: return
    // El háptico de éxito al confirmar lo da el panel, que es donde está el OK (acá se repetía).

    // La preparación va antes de las efectivas, fuera de su tarjeta. Nunca hereda la carga como serie.
    val preparacion = motor.preparacion(lugar)
    if (preparacion.isNotEmpty()) {
        PreparacionBloque(
            motor,
            lugar,
            preparacion,
            sinKg = s.sinKg,
            modifier = if (enLista) Modifier.padding(start = Espacio.m, end = Espacio.m, top = Espacio.s) else Modifier,
        )
    }
    val contenido: @Composable ColumnScope.() -> Unit = {
        AvisoRecordVista(motor, lugar)
        t.variantes?.let { va ->
            val actual = t.varianteActual ?: va.opciones.firstOrNull() ?: ""
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(va.etiqueta, style = Letras.caption.copy(fontWeight = FontWeight.SemiBold), color = MyPump.colores.textoSecundario)
                Segmentado(
                    opciones = va.opciones,
                    elegida = va.opciones.indexOf(actual),
                    alElegir = { motor.elegirVariante(lugar, va.opciones[it]) },
                    habilitado = !v.dia.diaFinalizado,
                    etiquetaPrueba = { "variante-${va.opciones[it]}" },
                    modifier = Modifier.testTag("variantes"),
                )
            }
        }
        if (!s.sinKg) BloqueCarga(motor, lugar, s)
        ListaSeries(motor, lugar, t, s, enLista, conPreparacion = preparacion.isNotEmpty())
    }
    if (enLista) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = Espacio.m, vertical = Espacio.s).testTag("tabla-series"),
            verticalArrangement = Arrangement.spacedBy(Espacio.s),
            content = contenido,
        )
    } else {
        Tarjeta(Modifier.testTag("tabla-series"), contenido = contenido)
    }
}

@Composable
private fun BloqueCarga(motor: ModeloEntreno, lugar: String, s: CargaSimple) {
    val c = MyPump.colores
    val foco = LocalFocusManager.current
    val haptico = LocalHapticFeedback.current
    val letraGrande = LocalDensity.current.fontScale >= 1.3f
    // Sube al aceptar el aumento: el número se enciende un momento.
    var encendido by remember { mutableStateOf(false) }
    LaunchedEffect(encendido) { if (encendido) { delay(900); encendido = false } }
    Column(Modifier.animateContentSize(EstiloCarga.resorte()), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        if (s.mismoPeso) {
            val botones: @Composable () -> Unit = {
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.xs + 2.dp)) {
                    BotonCircularCarga(Iconos.Menos, "Bajar la carga", "carga-menos", lado = 56.dp, tamanoIcono = 22.dp, habilitado = s.carga != null) {
                        foco.clearFocus()
                        motor.cambiarCarga(lugar) { it.moverCarga(-1) }
                        haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
                    }
                    BotonCircularCarga(Iconos.Mas, "Subir la carga", "carga-mas", lado = 56.dp, tamanoIcono = 22.dp, habilitado = s.carga != null) {
                        foco.clearFocus()
                        motor.cambiarCarga(lugar) { it.moverCarga(1) }
                        haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
                    }
                }
            }
            val resumen: @Composable () -> Unit = {
                Column {
                    Text("CARGA", style = Letras.ceja, color = c.textoSecundario, modifier = Modifier.semantics { heading() })
                    CampoCarga(motor, lugar, s, encendido)
                    s.cargaUltimaVez?.let { Text("La vez pasada ${KgTexto.de(it)} kg", style = Letras.caption, color = c.textoSecundario) }
                }
            }
            if (letraGrande) {
                Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) { resumen(); botones() }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { resumen() }
                    botones()
                }
            }
        } else {
            Text("CARGA", style = Letras.ceja, color = c.textoSecundario, modifier = Modifier.semantics { heading() })
            Text("Cada serie lleva su peso: ajustalo en la lista.", style = Letras.subtitulo, color = c.textoSecundario)
        }
        BannerAumento(motor, lugar, s) {
            haptico.performHapticFeedback(HapticFeedbackType.Confirm)
            encendido = true
        }
        if (s.hechasConOtraCarga > 0) BannerHechas(motor, lugar, s)
        if (s.ultimaVezMixta && s.mismoPeso && s.confirmadas == 0) {
            Text("La vez pasada una serie fue con otro peso. Si querés repetirlo, destildá abajo.", style = Letras.caption, color = c.textoSecundario)
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Mismo peso en todas las series",
                style = Letras.subtitulo,
                color = c.textoSecundario,
                modifier = Modifier.weight(1f),
            )
            Interruptor(
                prendido = s.mismoPeso,
                alCambiar = { nuevo -> motor.cambiarCarga(lugar) { it.usarMismoPeso(nuevo) } },
                modifier = Modifier.semantics { contentDescription = "Mismo peso en todas las series" }.testTag("toggle-mismo-peso"),
            )
        }
    }
}

@Composable
internal fun BotonRedondo(icono: ImageVector, etiqueta: String, id: String, habilitado: Boolean = true, lado: Dp = 44.dp, alTocar: () -> Unit) {
    val c = MyPump.colores
    Box(
        Modifier
            .size(lado)
            .clip(CircleShape)
            .background(c.campo)
            .clickable(enabled = habilitado, role = Role.Button, onClick = alTocar)
            .semantics { contentDescription = etiqueta }
            .testTag(id),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icono, contentDescription = null, tint = if (habilitado) c.texto else c.textoTerciario, modifier = Modifier.size(22.dp))
    }
}

/**
 * Un campo de kilos. Mientras se escribe es dueño de su texto y cada cambio va afuera; lo que cambia de afuera entra cuando no
 * se está escribiendo. Al enfocarlo se selecciona todo: lo que se escribe reemplaza lo anterior (80 corregido a 7 no queda 807).
 */
@Composable
internal fun CampoKilos(
    valor: String,
    etiqueta: String,
    alCambiar: (String) -> Unit,
    estilo: TextStyle,
    modifier: Modifier = Modifier,
    decorar: @Composable (Boolean, @Composable () -> Unit) -> Unit,
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
    BasicTextField(
        value = local,
        onValueChange = { nuevo ->
            val cambio = nuevo.text != local.text
            local = nuevo
            if (cambio) alCambiar(nuevo.text)
        },
        singleLine = true,
        textStyle = if (estilo.color.isSpecified) estilo else estilo.copy(color = c.texto),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { foco.clearFocus() }),
        cursorBrush = SolidColor(c.marcaTexto),
        modifier = modifier.onFocusChanged { enfocado = it.isFocused }.semantics { contentDescription = etiqueta },
        decorationBox = { campo -> decorar(enfocado, campo) },
    )
}

/** El kilo grande, alineado a la izquierda con el «kg» pegado. Achica la letra si el número es largo (122,5). */
@Composable
private fun CampoCarga(motor: ModeloEntreno, lugar: String, s: CargaSimple, encendido: Boolean) {
    val c = MyPump.colores
    val texto = KgTexto.de(s.carga)
    val tamano = when {
        texto.length >= 5 -> 42.sp
        texto.length == 4 -> 48.sp
        else -> 54.sp
    }
    val color by animateColorAsState(if (encendido) c.marcaTexto else c.texto, label = "kilo-encendido")
    val escala by animateFloatAsState(if (encendido) 1.06f else 1f, spring(dampingRatio = 0.55f), label = "kilo-escala")
    val estilo = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.Black, fontSize = tamano, lineHeight = tamano)
    // El «kg» va afuera del campo: adentro, el ancho del campo (el del número) lo dejaba sin lugar.
    Row(
        Modifier.heightIn(min = 60.dp).graphicsLayer { scaleX = escala; scaleY = escala; transformOrigin = TransformOrigin(0f, 0.5f) },
        verticalAlignment = Alignment.Bottom,
    ) {
        CampoKilos(
            valor = texto,
            etiqueta = "Carga en kilos",
            alCambiar = { t -> motor.cambiarCarga(lugar) { it.fijarCarga(KgTexto.numero(t)) } },
            estilo = estilo.copy(color = color),
            modifier = Modifier.width(IntrinsicSize.Min).widthIn(min = 56.dp).testTag("carga-valor"),   // con lugar para la raya si no hay carga
        ) { _, campo ->
            Box(contentAlignment = Alignment.CenterStart) {
                if (s.carga == null) Text("—", style = estilo, color = c.textoTerciario, modifier = Modifier.clearAndSetSemantics {})
                campo()
            }
        }
        Spacer(Modifier.width(6.dp))
        Text("kg", style = Numeros.chico.copy(fontSize = 20.sp), color = c.textoSecundario, maxLines = 1, softWrap = false, modifier = Modifier.padding(bottom = 8.dp).clearAndSetSemantics {})
    }
}

@Composable
private fun BannerAumento(motor: ModeloEntreno, lugar: String, s: CargaSimple, alSubir: () -> Unit) {
    val c = MyPump.colores
    val letraGrande = LocalDensity.current.fontScale >= 1.3f
    when (val a = s.aumento) {
        is CargaSimple.Aumento.Sugerido -> Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(c.marcaSuave).padding(Espacio.s),
            verticalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Iconos.Tendencia, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(16.dp))
                Text("Esta semana bajan las reps: toca subir", style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.marcaTexto)
            }
            val subir: @Composable (Modifier) -> Unit = { m ->
                BotonConfirmar(
                    alTocar = {
                        motor.cambiarCarga(lugar) { it.aceptarAumento() }
                        alSubir()
                    },
                    compacto = true,
                    modifier = m.testTag("aumento-subir"),
                ) { tinta -> Text("Subir a ${KgTexto.de(a.hasta)} kg", style = Numeros.chico.copy(color = tinta, fontWeight = FontWeight.ExtraBold), maxLines = 1) }
            }
            val dejar: @Composable (Modifier) -> Unit = { m ->
                Box(
                    m.heightIn(min = 48.dp).clip(CircleShape).clickable(role = Role.Button) { motor.cambiarCarga(lugar) { it.descartarAumento() } }
                        .padding(horizontal = Espacio.s).testTag("aumento-dejar"),
                    contentAlignment = Alignment.Center,
                ) { Text("Dejar ${KgTexto.de(a.desde)} kg", style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.texto, maxLines = 1) }
            }
            if (letraGrande) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { subir(Modifier.fillMaxWidth()); dejar(Modifier.fillMaxWidth()) }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                    subir(Modifier.weight(1f))
                    dejar(Modifier)
                }
            }
        }
        is CargaSimple.Aumento.Aceptado -> Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(Espacio.xs))
            Text(
                if (s.confirmadas > 0) "Subiste a ${KgTexto.de(a.hasta)} kg en las que faltan" else "Subiste a ${KgTexto.de(a.hasta)} kg en todas las series",
                style = Letras.caption.copy(fontWeight = FontWeight.Medium),
                color = c.texto,
                modifier = Modifier.weight(1f),
            )
            if (s.confirmadas == 0) {
                EnlaceTexto("Volver a ${KgTexto.de(a.desde)}", "aumento-volver") { motor.cambiarCarga(lugar) { it.deshacerAumento() } }
            }
        }
        else -> Unit
    }
}

/** Un botón de solo texto, con el alto mínimo para tocarlo. */
@Composable
internal fun EnlaceTexto(texto: String, id: String, estilo: TextStyle = Letras.caption, alTocar: () -> Unit) {
    Box(
        Modifier.heightIn(min = 44.dp).clickable(role = Role.Button, onClick = alTocar).padding(horizontal = 6.dp).testTag(id),
        contentAlignment = Alignment.Center,
    ) {
        Text(texto, style = estilo.copy(fontWeight = FontWeight.SemiBold), color = MyPump.colores.marcaTexto)
    }
}

@Composable
private fun BannerHechas(motor: ModeloEntreno, lugar: String, s: CargaSimple) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val n = s.hechasConOtraCarga
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            if (n == 1) "La serie hecha sigue con su peso." else "Las $n hechas siguen con su peso.",
            style = Letras.caption,
            color = c.textoSecundario,
            modifier = Modifier.weight(1f),
        )
        EnlaceTexto("Cambiarlas también", "aplicar-a-hechas") { alcance.launch { motor.aplicarCargaALasHechas(lugar) } }
    }
}

@Composable
private fun ListaSeries(motor: ModeloEntreno, lugar: String, t: ModeloEntreno.Tarjeta, s: CargaSimple, enLista: Boolean, conPreparacion: Boolean) {
    val c = MyPump.colores
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Row(verticalAlignment = Alignment.Bottom) {
            // Abierta en la lista va más chica: arriba ya está el nombre del ejercicio, que es lo que manda.
            Text(
                if (conPreparacion) "Series efectivas" else "Series",
                style = Numeros.chico.copy(fontSize = if (enLista) 17.sp else 20.sp, fontWeight = FontWeight.ExtraBold),
                color = c.texto,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            Text(
                "${s.confirmadas} de ${s.series.size}",
                style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold).merge(Letras.cifras),
                color = if (s.confirmadas == s.series.size) c.marcaTexto else c.textoSecundario,
                modifier = Modifier.testTag("series-confirmadas"),
            )
        }
        motor.leyendaRir(lugar)?.let {
            Text(it, style = Letras.caption, color = c.textoSecundario, modifier = Modifier.testTag("leyenda-rir"))
        }
        s.activa?.let { t.filas.getOrNull(it)?.calibracion }?.let { cal ->
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Icon(Iconos.Mira, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.padding(top = 1.dp).size(14.dp))
                Text(Bonito.sinEmoji(cal), style = Letras.caption, color = c.textoSecundario, modifier = Modifier.testTag("pista-serie"))
            }
        }
        Column { s.series.indices.forEach { FilaCarga(motor, lugar, it, s) } }
    }
}

@Composable
private fun FilaCarga(motor: ModeloEntreno, lugar: String, i: Int, s: CargaSimple) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val h = s.series[i]
    val corrigiendo by motor.corrigiendo.collectAsStateWithLifecycle()
    val enCorreccion = corrigiendo?.lugar == lugar && corrigiendo?.indice == i
    val activa = s.activa == i && corrigiendo?.lugar != lugar
    val resaltada = activa || h.confirmada
    val etiqueta = etiquetaFila(i, s)
    // Con letra grande y peso por serie, los botones del kilo van abajo: al lado partían el número de reps.
    val apilar = LocalDensity.current.fontScale >= 1.3f && !s.sinKg && !s.mismoPeso && !h.confirmada
    val base = Modifier
        .fillMaxWidth()
        .heightIn(min = 56.dp)
        .clip(RoundedCornerShape(12.dp))
        .background(if (enCorreccion) c.marcaSuave else Color.Transparent)
        .drawBehind { conector(i, s, c.marca, c.campo) }
        .testTag("fila-serie-${i + 1}")
    val semantica = when {
        h.confirmada -> base.clickable(role = Role.Button) { alcance.launch { motor.editarSerie(lugar, i) } }.clearAndSetSemantics { contentDescription = etiqueta }
        s.mismoPeso -> base.clearAndSetSemantics { contentDescription = etiqueta }
        else -> base   // con peso por serie, adentro están el campo y sus botones
    }
    Row(semantica, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Insignia(i, h.confirmada, activa)
        val repsYKilos: @Composable () -> Unit = {
            // Un solo «8 reps» para TalkBack, aunque sean dos textos.
            Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    s.reps(i)?.toString() ?: "—",
                    style = TextStyle(fontFamily = Archivo, fontWeight = if (resaltada) FontWeight.ExtraBold else FontWeight.SemiBold, fontSize = if (activa) 24.sp else 20.sp),
                    color = if (resaltada) c.texto else c.textoSecundario,
                    maxLines = 1,
                    softWrap = false,
                )
                if (s.reps(i) != null) Text("reps", style = Letras.subtitulo, color = c.textoSecundario, maxLines = 1, modifier = Modifier.padding(bottom = 2.dp))
            }
        }
        if (apilar) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                repsYKilos()
                KgPorSerie(motor, lugar, i, s)
            }
        } else {
            repsYKilos()
            Spacer(Modifier.weight(1f))
            if (!s.sinKg) {
                if (!s.mismoPeso && !h.confirmada) {
                    KgPorSerie(motor, lugar, i, s)
                } else {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            KgTexto.de(h.kg).ifEmpty { "—" },
                            style = Numeros.chico.copy(fontSize = 18.sp, fontWeight = if (resaltada) FontWeight.Bold else FontWeight.SemiBold).merge(Letras.cifras),
                            color = if (resaltada) c.texto else c.textoSecundario,
                            maxLines = 1,
                        )
                        if (h.kg != null) Text("kg", style = Letras.caption, color = c.textoSecundario, modifier = Modifier.padding(bottom = 1.dp))
                    }
                }
            }
            if (h.confirmada) {
                Icon(Iconos.Lapiz, contentDescription = null, tint = if (enCorreccion) c.marcaTexto else c.textoTerciario, modifier = Modifier.padding(end = 4.dp).size(14.dp))
            }
        }
    }
}

/** La insignia de la serie: hecha en verde con tilde, la de ahora con anillo, las que faltan apagadas. */
@Composable
private fun Insignia(i: Int, hecha: Boolean, activa: Boolean) {
    val c = MyPump.colores
    Box(
        Modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(if (hecha) c.marca else if (activa) c.marcaSuave else c.campo)
            .then(if (activa) Modifier.border(2.dp, c.marca, CircleShape) else Modifier)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        AnimatedContent(hecha, transitionSpec = { scaleIn(initialScale = 0.3f) + fadeIn() togetherWith fadeOut() }, label = "insignia-$i") { h ->
            if (h) {
                Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(16.dp))
            } else {
                Text(
                    "${i + 1}",
                    style = Numeros.chico.copy(fontSize = 14.sp, fontWeight = if (activa) FontWeight.ExtraBold else FontWeight.SemiBold),
                    color = if (activa) c.marcaTexto else c.textoSecundario,
                )
            }
        }
    }
}

/** El hilo entre series: se pinta de verde lo que ya se hizo. */
private fun DrawScope.conector(i: Int, s: CargaSimple, verde: Color, gris: Color) {
    val x = 16.dp.toPx()
    val hueco = 20.dp.toPx()
    val medio = size.height / 2
    val ancho = 2.dp.toPx()
    if (i > 0) {
        val hecho = s.series[i - 1].confirmada && s.series[i].confirmada
        drawLine(if (hecho) verde.copy(alpha = 0.6f) else gris, Offset(x, 0f), Offset(x, medio - hueco), ancho)
    }
    if (i + 1 < s.series.size) {
        val hecho = s.series[i].confirmada && s.series[i + 1].confirmada
        drawLine(if (hecho) verde.copy(alpha = 0.6f) else gris, Offset(x, medio + hueco), Offset(x, size.height), ancho)
    }
}

private fun etiquetaFila(i: Int, s: CargaSimple): String {
    val h = s.series[i]
    val kg = if (s.sinKg) "" else ", ${KgTexto.de(h.kg)} kilos"
    return if (h.confirmada) {
        "Serie ${i + 1}, hecha: ${s.reps(i) ?: 0} repeticiones$kg. Tocá para corregirla"
    } else {
        "Serie ${i + 1}, pendiente: ${s.reps(i)?.toString() ?: "sin dato"} repeticiones$kg"
    }
}

@Composable
private fun KgPorSerie(motor: ModeloEntreno, lugar: String, i: Int, s: CargaSimple) {
    val c = MyPump.colores
    // Crece con la letra: con letra grande un 82,5 no entraba en el ancho fijo.
    val anchoKg = with(LocalDensity.current) { (66.dp * maxOf(1f, fontScale)) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        BotonCircularCarga(Iconos.Menos, "Bajar el peso de la serie ${i + 1}", "kg-menos-${i + 1}", lado = 44.dp, tamanoIcono = 18.dp) { motor.cambiarCarga(lugar) { it.moverKg(i, -1) } }
        CampoKilos(
            valor = KgTexto.de(s.series[i].kg),
            etiqueta = "Peso de la serie ${i + 1} en kilos",
            alCambiar = { texto -> motor.cambiarCarga(lugar) { it.fijarKg(i, KgTexto.numero(texto)) } },
            estilo = Numeros.chico.copy(fontSize = 19.sp, fontWeight = FontWeight.ExtraBold, textAlign = TextAlign.Center).merge(Letras.cifras),
            modifier = Modifier.width(anchoKg).testTag("kg-serie-${i + 1}"),
        ) { enfocado, campo ->
            val forma = RoundedCornerShape(8.dp)
            Box(
                Modifier
                    .heightIn(min = 44.dp)
                    .clip(forma)
                    .then(if (enfocado) Modifier.background(c.campo).border(2.dp, c.marcaVivo, forma) else Modifier)
                    .padding(horizontal = 4.dp),
                contentAlignment = Alignment.Center,
            ) { campo() }
        }
        BotonCircularCarga(Iconos.Mas, "Subir el peso de la serie ${i + 1}", "kg-mas-${i + 1}", lado = 44.dp, tamanoIcono = 18.dp) { motor.cambiarCarga(lugar) { it.moverKg(i, 1) } }
    }
}
