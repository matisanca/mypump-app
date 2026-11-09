package com.pumpteam.mypump.entreno

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
    val haptico = LocalHapticFeedback.current

    // El háptico de éxito cada vez que se confirma una serie.
    var confirmadasAntes by remember { mutableIntStateOf(s.confirmadas) }
    LaunchedEffect(s.confirmadas) {
        if (s.confirmadas > confirmadasAntes) haptico.performHapticFeedback(HapticFeedbackType.Confirm)
        confirmadasAntes = s.confirmadas
    }

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
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text("CARGA", style = Letras.ceja, color = c.textoSecundario, modifier = Modifier.weight(1f).semantics { heading() })
            s.cargaUltimaVez?.let { Text("La vez pasada ${KgTexto.de(it)} kg", style = Letras.caption, color = c.textoSecundario) }
        }
        if (s.mismoPeso) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                BotonRedondo(Iconos.Menos, "Bajar la carga", "carga-menos", habilitado = s.carga != null, lado = 48.dp) {
                    foco.clearFocus()
                    motor.cambiarCarga(lugar) { it.moverCarga(-1) }
                }
                CampoCarga(motor, lugar, s, Modifier.weight(1f))
                BotonRedondo(Iconos.Mas, "Subir la carga", "carga-mas", habilitado = s.carga != null, lado = 48.dp) {
                    foco.clearFocus()
                    motor.cambiarCarga(lugar) { it.moverCarga(1) }
                }
            }
        } else {
            Text("Cada serie lleva su peso: ajustalo en la lista.", style = Letras.subtitulo, color = c.textoSecundario)
        }
        BannerAumento(motor, lugar, s)
        if (s.hechasConOtraCarga > 0) BannerHechas(motor, lugar, s)
        if (s.ultimaVezMixta && s.mismoPeso && s.confirmadas == 0) {
            Text("La vez pasada una serie fue con otro peso. Si querés repetirlo, destildá abajo.", style = Letras.caption, color = c.textoSecundario)
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Mismo peso en todas las series",
                style = Letras.subtitulo.copy(fontWeight = FontWeight.Medium),
                color = c.texto,
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
        textStyle = estilo.copy(color = c.texto),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { foco.clearFocus() }),
        cursorBrush = SolidColor(c.marcaTexto),
        modifier = modifier.onFocusChanged { enfocado = it.isFocused }.semantics { contentDescription = etiqueta },
        decorationBox = { campo -> decorar(enfocado, campo) },
    )
}

@Composable
private fun CampoCarga(motor: ModeloEntreno, lugar: String, s: CargaSimple, modifier: Modifier) {
    val c = MyPump.colores
    CampoKilos(
        valor = KgTexto.de(s.carga),
        etiqueta = "Carga en kilos",
        alCambiar = { texto -> motor.cambiarCarga(lugar) { it.fijarCarga(KgTexto.numero(texto)) } },
        estilo = Numeros.grande.merge(Letras.cifras).copy(textAlign = TextAlign.End),
        modifier = modifier.testTag("carga-valor"),
    ) { _, campo ->
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
            Box(Modifier.widthIn(min = 40.dp, max = 150.dp), contentAlignment = Alignment.CenterEnd) {
                if (s.carga == null) Text("—", style = Numeros.grande, color = c.textoTerciario, modifier = Modifier.clearAndSetSemantics {})
                campo()
            }
            Spacer(Modifier.width(6.dp))
            Text("kg", style = MaterialTheme.typography.titleMedium, color = c.textoSecundario, modifier = Modifier.clearAndSetSemantics {})
        }
    }
}

@Composable
private fun BannerAumento(motor: ModeloEntreno, lugar: String, s: CargaSimple) {
    val c = MyPump.colores
    when (val a = s.aumento) {
        is CargaSimple.Aumento.Sugerido -> Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(Radio.control)).background(c.marcaSuave).padding(Espacio.s),
            verticalArrangement = Arrangement.spacedBy(Espacio.xs),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Icon(Iconos.Tendencia, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(16.dp))
                Text("Esta semana bajan las reps: toca subir", style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.marcaTexto)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                BotonMarca(
                    "Subir a ${KgTexto.de(a.hasta)} kg",
                    alTocar = { motor.cambiarCarga(lugar) { it.aceptarAumento() } },
                    modifier = Modifier.weight(1f).testTag("aumento-subir"),
                    compacto = true,
                )
                BotonSecundario(
                    "Dejar ${KgTexto.de(a.desde)} kg",
                    alTocar = { motor.cambiarCarga(lugar) { it.descartarAumento() } },
                    modifier = Modifier.weight(1f).testTag("aumento-dejar"),
                    compacto = true,
                )
            }
        }
        is CargaSimple.Aumento.Aceptado -> Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Iconos.Tilde, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(5.dp))
            Text(
                if (s.confirmadas > 0) "Subiste a ${KgTexto.de(a.hasta)} kg en las que faltan" else "Subiste a ${KgTexto.de(a.hasta)} kg en todas las series",
                style = Letras.caption,
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
                style = if (enLista) MaterialTheme.typography.titleMedium else Letras.titulo3,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            Text(
                "${s.confirmadas} de ${s.series.size}",
                style = Letras.subtitulo.copy(fontWeight = FontWeight.Medium).merge(Letras.cifras),
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
        s.series.indices.forEach { FilaCarga(motor, lugar, it, s) }
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
    val etiqueta = etiquetaFila(i, s)
    val base = Modifier
        .fillMaxWidth()
        .heightIn(min = 44.dp)
        .clip(RoundedCornerShape(10.dp))
        .background(if (activa) c.marcaSuave.copy(alpha = c.marcaSuave.alpha * 0.6f) else Color.Transparent)
        .testTag("fila-serie-${i + 1}")
    val semantica = when {
        h.confirmada -> base.clickable(role = Role.Button) { alcance.launch { motor.editarSerie(lugar, i) } }.clearAndSetSemantics { contentDescription = etiqueta }
        s.mismoPeso -> base.clearAndSetSemantics { contentDescription = etiqueta }
        else -> base   // con peso por serie, adentro están el campo y sus botones
    }
    Row(
        semantica.padding(horizontal = Espacio.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(
            Modifier.size(28.dp).clip(CircleShape).background(if (h.confirmada) c.marca else if (activa) c.marcaSuave else c.campo).clearAndSetSemantics {},
            contentAlignment = Alignment.Center,
        ) {
            if (h.confirmada) {
                Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(14.dp))
            } else {
                Text("${i + 1}", style = Letras.caption.copy(fontWeight = FontWeight.Bold).merge(Letras.cifras), color = if (activa) c.marcaTexto else c.textoSecundario)
            }
        }
        val fuerte = activa || h.confirmada
        Text(
            s.reps(i)?.let { "$it reps" } ?: "—",
            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = if (fuerte) FontWeight.SemiBold else FontWeight.Normal).merge(Letras.cifras),
            color = if (fuerte) c.texto else c.textoSecundario,
        )
        Spacer(Modifier.weight(1f))
        if (!s.sinKg) {
            if (!s.mismoPeso && !h.confirmada) {
                KgPorSerie(motor, lugar, i, s)
            } else {
                Text(
                    h.kg?.let { "${KgTexto.de(it)} kg" } ?: "—",
                    style = MaterialTheme.typography.bodyLarge.merge(Letras.cifras),
                    color = if (h.confirmada) c.texto else c.textoSecundario,
                )
            }
        }
        if (h.confirmada) {
            Icon(Iconos.Lapiz, contentDescription = null, tint = if (enCorreccion) c.marcaTexto else c.textoSecundario, modifier = Modifier.size(15.dp))
        }
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
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        BotonRedondo(Iconos.Menos, "Bajar el peso de la serie ${i + 1}", "kg-menos-${i + 1}") { motor.cambiarCarga(lugar) { it.moverKg(i, -1) } }
        CampoKilos(
            valor = KgTexto.de(s.series[i].kg),
            etiqueta = "Peso de la serie ${i + 1} en kilos",
            alCambiar = { texto -> motor.cambiarCarga(lugar) { it.fijarKg(i, KgTexto.numero(texto)) } },
            estilo = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center).merge(Letras.cifras),
            modifier = Modifier.width(60.dp).testTag("kg-serie-${i + 1}"),
        ) { enfocado, campo ->
            val forma = RoundedCornerShape(8.dp)
            Box(
                Modifier
                    .heightIn(min = 40.dp)
                    .clip(forma)
                    .background(c.campo)
                    .then(if (enfocado) Modifier.border(2.dp, c.marcaVivo, forma) else Modifier)
                    .padding(horizontal = 4.dp),
                contentAlignment = Alignment.Center,
            ) { campo() }
        }
        BotonRedondo(Iconos.Mas, "Subir el peso de la serie ${i + 1}", "kg-mas-${i + 1}") { motor.cambiarCarga(lugar) { it.moverKg(i, 1) } }
    }
}
