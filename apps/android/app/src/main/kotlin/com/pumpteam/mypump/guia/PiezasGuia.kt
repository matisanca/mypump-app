package com.pumpteam.mypump.guia

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.updateTransition
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.modelos.ClipGuia
import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.reglas.ReglasGuia
import com.pumpteam.mypump.reglas.ReglasReproductor
import com.pumpteam.mypump.reglas.SuplementacionVista

/**
 * Las piezas de «Tu guía», sin estado propio: la tarjeta de inicio, la cabecera, los capítulos y sus filas, la placa, las
 * dudas y la suplementación. Siguen la visual de la web del 4/11 (`pack.html`) con los componentes de la app.
 */

/** La tarjeta arriba de Entreno (la pestaña de inicio): solo con guía, con el avance. Tocarla abre la sección. */
@Composable
fun TarjetaGuia(resumen: ResumenGuia, alAbrir: () -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val texto = ReglasGuia.textoTarjeta(resumen)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .superficieTarjeta(radio = Radio.control + 6.dp)
            .clickable(onClickLabel = "Abrir tu guía", role = Role.Button, onClick = alAbrir)
            .semantics(mergeDescendants = true) { contentDescription = "Tu guía. $texto" }
            .padding(Espacio.s)
            .testTag("tarjeta-guia"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        // Con todo visto (la compacta que no molesta), el tilde en lugar del play.
        val completa = resumen.vistos >= resumen.total
        Box(Modifier.size(40.dp).clip(CircleShape).background(c.marca).then(if (completa) Modifier.testTag("tarjeta-guia-completa") else Modifier), contentAlignment = Alignment.Center) {
            Icon(if (completa) Iconos.Tilde else Iconos.Play, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Tu guía", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(texto, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
            BarraAvance(ReglasGuia.fraccion(resumen), Modifier.padding(top = 2.dp))
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

@Composable
fun BarraAvance(fraccion: Float, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    LinearProgressIndicator(
        progress = { fraccion.coerceIn(0f, 1f) },
        modifier = modifier.fillMaxWidth().height(6.dp).clip(CircleShape).clearAndSetSemantics {},
        color = c.marca,
        trackColor = c.campo,
        strokeCap = StrokeCap.Round,
        gapSize = 0.dp,
        drawStopIndicator = {},
    )
}

/** «Hola Tomás», una línea y el avance. */
@Composable
fun CabeceraGuia(saludo: String, linea: String, resumen: ResumenGuia?, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Column(
        modifier = modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .padding(horizontal = Espacio.m + 4.dp, vertical = Espacio.m + 2.dp)
            .testTag("guia-cabecera"),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Text(saludo, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
        Text(linea, style = MaterialTheme.typography.bodyLarge)
        Text("Mati", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        if (resumen != null) {
            Spacer(Modifier.height(4.dp))
            Text(ReglasGuia.textoAvance(resumen), style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.testTag("guia-avance"))
            BarraAvance(ReglasGuia.fraccion(resumen))
        }
    }
}

/** El encabezado de un capítulo plegable: título, «8 videos, unos 3 minutos» y la flechita. */
@Composable
fun EncabezadoBloque(bloque: ReglasGuia.Bloque, vistos: Int, abierto: Boolean, alTocar: () -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val estado = if (abierto) "abierto" else "cerrado"
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClickLabel = if (abierto) "Plegar" else "Desplegar", onClick = alTocar)
            .semantics(mergeDescendants = true) {
                heading()
                stateDescription = estado
            }
            .padding(horizontal = Espacio.m + 4.dp, vertical = Espacio.s)
            .testTag("bloque-${bloque.titulo}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(bloque.titulo, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(
                bloque.resumen + if (vistos > 0) ", viste $vistos" else "",
                style = MaterialTheme.typography.bodySmall,
                color = c.textoSecundario,
            )
        }
        Icon(
            Iconos.Chevron,
            contentDescription = null,
            tint = c.textoSecundario,
            modifier = Modifier.size(20.dp).rotate(if (abierto) 270f else 90f),
        )
    }
}

/**
 * Una fila: el ícono (play, visto o el que suena), solo la pregunta y la duración a la derecha. Tocarla reproduce. El
 * «para qué» va plegado bajo la flechita, que es un botón aparte.
 */
@Composable
fun FilaClip(
    clip: ClipGuia,
    actual: Boolean,
    expandida: Boolean,
    alTocar: () -> Unit,
    alExpandir: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = MyPump.colores
    val (hacer, paraQue) = ReglasGuia.partesMotivo(clip.motivo)
    val tieneMotivo = hacer != null || paraQue != null
    val estado = when {
        actual -> "suena ahora"
        clip.visto -> "visto"
        else -> "sin ver"
    }
    Column(modifier.fillMaxWidth().background(if (actual) c.marcaSuave else Color.Transparent)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 56.dp)
                    .clickable(enabled = clip.sePuedeVer, role = Role.Button, onClickLabel = "Reproducir", onClick = alTocar)
                    .semantics(mergeDescendants = true) {
                        contentDescription = clip.titulo + ". " + (if (clip.sePuedeVer) ReglasGuia.duracionHablada(clip.minutos) else "Lo estoy subiendo")
                        stateDescription = estado
                    }
                    .padding(start = Espacio.m + 4.dp, end = if (tieneMotivo) 0.dp else Espacio.m, top = 10.dp, bottom = 10.dp)
                    .testTag("clip-${clip.id}"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            ) {
                IconoClip(clip, actual)
                Text(
                    clip.titulo,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (clip.sePuedeVer) c.texto else c.textoSecundario,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    if (clip.sePuedeVer) ReglasGuia.duracion(clip.minutos) else "Lo estoy subiendo",
                    style = MaterialTheme.typography.bodyMedium,
                    color = c.textoSecundario,
                    textAlign = TextAlign.End,
                    modifier = Modifier.widthIn(min = 36.dp),
                )
            }
            if (tieneMotivo) {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .clickable(role = Role.Button, onClick = alExpandir)
                        .semantics {
                            contentDescription = "Para qué es este video"
                            stateDescription = if (expandida) "desplegado" else "plegado"
                        }
                        .testTag("motivo-${clip.id}"),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Iconos.Chevron, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(18.dp).rotate(if (expandida) 270f else 90f))
                }
            }
        }
        if (expandida && tieneMotivo) {
            Column(
                Modifier.padding(start = 56.dp, end = Espacio.m + 4.dp, bottom = Espacio.s).testTag("motivo-abierto-${clip.id}"),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                paraQue?.let { TextoRotulado("Para qué.", it) }
                hacer?.let { TextoRotulado("Qué hacer.", it) }
            }
        }
    }
}

@Composable
private fun IconoClip(clip: ClipGuia, actual: Boolean) {
    val c = MyPump.colores
    val lado = 24.dp
    when {
        clip.visto -> Box(Modifier.size(lado).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
            Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(16.dp))
        }
        actual -> Box(Modifier.size(lado).clip(CircleShape).background(c.marcaTexto), contentAlignment = Alignment.Center) {
            Icon(Iconos.Play, contentDescription = null, tint = c.tarjeta, modifier = Modifier.size(13.dp))
        }
        else -> Box(Modifier.size(lado).border(2.dp, if (clip.sePuedeVer) c.textoSecundario else c.borde, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Iconos.Play, contentDescription = null, tint = if (clip.sePuedeVer) c.textoSecundario else c.borde, modifier = Modifier.size(11.dp))
        }
    }
}

/** «Para qué.» en verde y el texto (como `<b>Para qué.</b>` de la web). */
@Composable
fun TextoRotulado(rotulo: String, texto: String, modifier: Modifier = Modifier, tonoTexto: Color = MyPump.colores.textoSecundario) {
    val c = MyPump.colores
    Text(
        buildAnnotatedString {
            withStyle(SpanStyle(color = c.marcaTexto, fontWeight = FontWeight.SemiBold)) { append(rotulo) }
            append(" ")
            withStyle(SpanStyle(color = tonoTexto)) { append(texto) }
        },
        style = MaterialTheme.typography.bodyMedium,
        modifier = modifier,
    )
}

/**
 * La placa de «Otro tema» sobre el reproductor: el número, el bloque y el título, con la barrita que se llena en 2,6 s.
 * Tocarla la cierra (y arranca el video).
 */
@Composable
fun PlacaGuia(placa: ControlReproductor.Placa, alTocar: () -> Unit, modifier: Modifier = Modifier) {
    var arrancada by remember(placa) { mutableStateOf(false) }
    LaunchedEffect(placa) { arrancada = true }
    val t = updateTransition(arrancada, label = "placa")
    val avance by t.animateFloat(transitionSpec = { tween(ReglasReproductor.PLACA_MS.toInt(), easing = LinearEasing) }, label = "cuenta") { if (it) 1f else 0f }
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFF111814))
            .clickable(onClickLabel = "Empezar el video", role = Role.Button, onClick = alTocar)
            .semantics { liveRegion = LiveRegionMode.Polite }
            .padding(horizontal = 20.dp, vertical = 14.dp)
            .testTag("guia-placa"),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            ReglasReproductor.textoPlaca(placa.indice, placa.total).uppercase(),
            color = Color(0xFFA8DAB5),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.8.sp,
        )
        placa.bloque?.let { Text(it, color = Color(0xFFDADCE0), fontSize = 14.sp, modifier = Modifier.padding(top = 2.dp)) }
        Text(
            placa.titulo,
            color = Color.White,
            fontSize = 20.sp,
            lineHeight = 25.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 8.dp),
        )
        Box(Modifier.padding(top = 14.dp).fillMaxWidth().height(3.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.2f))) {
            Box(Modifier.fillMaxWidth(avance).height(3.dp).background(Color(0xFF5BB974)))
        }
    }
}

/** Sin red: el reproductor lo dice, y se puede reintentar. La lista se sigue viendo. */
@Composable
fun SinConexionVideo(falla: FallaVideo, alReintentar: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().background(Color(0xFF111814)).padding(Espacio.m).testTag("guia-sin-conexion-video"),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (falla == FallaVideo.SIN_RED) Icon(Iconos.SinWifi, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
        Text(
            if (falla == FallaVideo.SIN_RED) "Necesitás conexión para ver el video" else "No se pudo cargar el video",
            color = Color.White,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = Espacio.xs),
        )
        TextButton(onClick = alReintentar, modifier = Modifier.heightIn(min = 48.dp).testTag("guia-reintentar-video")) {
            Text("Reintentar", color = Color(0xFFA8DAB5), fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Un botón de texto verde de la fila del reproductor («Anterior», «Siguiente», «Velocidad 1x»), de 48 de alto. */
@Composable
fun BotonTexto(texto: String, alTocar: () -> Unit, modifier: Modifier = Modifier, descripcion: String? = null) {
    val c = MyPump.colores
    TextButton(
        onClick = alTocar,
        modifier = modifier.heightIn(min = 48.dp).then(if (descripcion != null) Modifier.semantics { contentDescription = descripcion } else Modifier),
    ) {
        Text(texto, color = c.marcaTexto, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
    }
}

/** El campo de una duda: hasta 1000 caracteres, con el contador cuando se acerca al tope. */
@Composable
fun CampoDuda(
    texto: String,
    alCambiar: (String) -> Unit,
    placeholder: String,
    descripcion: String,
    modifier: Modifier = Modifier,
    minLineas: Int = 2,
    etiqueta: String? = null,
) {
    val c = MyPump.colores
    Column(modifier) {
        BasicTextField(
            value = texto,
            onValueChange = { alCambiar(it.take(ReglasGuia.MAX_DUDA)) },
            minLines = minLineas,
            maxLines = 8,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
            cursorBrush = SolidColor(c.marcaTexto),
            // Sin contentDescription: tapaba lo escrito y TalkBack no lo leía. La etiqueta va como un texto del campo (como
            // el label de Material), que TalkBack lee junto con lo escrito o, vacío, como pista.
            modifier = Modifier.fillMaxWidth().then(if (etiqueta != null) Modifier.testTag(etiqueta) else Modifier),
            decorationBox = { campo ->
                Box(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .clip(RoundedCornerShape(Radio.control))
                        .background(c.campo)
                        .border(1.dp, c.borde, RoundedCornerShape(Radio.control))
                        .padding(horizontal = Espacio.s, vertical = 10.dp),
                ) {
                    // La etiqueta, sin lugar en pantalla (lo visible es la pregunta de arriba y el ejemplo de adentro).
                    Text(descripcion, modifier = Modifier.size(0.dp))
                    if (texto.isEmpty()) {
                        Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = c.textoTerciario)
                    }
                    campo()
                }
            },
        )
        if (texto.length > ReglasGuia.MAX_DUDA - 200) {
            Text(
                "${texto.length} de ${ReglasGuia.MAX_DUDA}",
                style = MaterialTheme.typography.labelSmall,
                color = c.textoSecundario,
                modifier = Modifier.align(Alignment.End).padding(top = 2.dp),
            )
        }
    }
}

/** Lo que ya dejó (o lo que está saliendo), en un recuadro gris. */
@Composable
fun YaDejaste(rotulo: String, textos: List<String>, modifier: Modifier = Modifier, enviando: Boolean = false) {
    val c = MyPump.colores
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.miniatura))
            .background(c.campo)
            .padding(horizontal = Espacio.s, vertical = Espacio.xs),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(rotulo, style = MaterialTheme.typography.labelMedium, color = if (enviando) c.textoSecundario else c.marcaTexto, fontWeight = FontWeight.SemiBold)
        for (t in textos) Text(t, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
    }
}

/** «Tu suplementación» por momento del día, como «Tu día» del PDF. [alVerPorQue] reproduce el clip del ítem. */
@Composable
fun SuplementacionGuia(v: SuplementacionVista.Vista, porQue: PorQueSuplemento?, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Column(
        modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .padding(horizontal = Espacio.m + 4.dp, vertical = Espacio.m)
            .testTag("guia-suplementacion"),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Text(v.titulo, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        v.accion?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
        for ((i, m) in v.momentos.withIndex()) {
            if (i > 0 || v.accion != null) SeparadorFino()
            Text(
                m.titulo,
                style = MaterialTheme.typography.titleSmall,
                color = c.marcaTexto,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 4.dp).semantics { heading() },
            )
            for (f in m.filas) FilaSuplemento(f, porQue)
        }
        if (v.sigue != null || v.sale.isNotEmpty()) SeparadorFino()
        v.sigue?.let { TextoRotulado("Sigue igual.", it, tonoTexto = c.texto) }
        if (v.sale.isNotEmpty()) {
            TextoRotulado("Dejás de tomar.", v.sale.joinToString(", ") { it.nombre }, tonoTexto = c.texto)
            for (s in v.sale) {
                s.porQue?.let { Text("${s.nombre}. $it", style = MaterialTheme.typography.bodySmall, color = c.textoSecundario) }
                for (d in s.detalle) TextoConNegritas(d)
            }
        }
    }
}

@Composable
private fun SeparadorFino() {
    Box(Modifier.fillMaxWidth().padding(vertical = 4.dp).height(1.dp).background(MyPump.colores.separador))
}

@Composable
private fun FilaSuplemento(f: SuplementacionVista.Fila, porQue: PorQueSuplemento?) {
    val c = MyPump.colores
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp).testTag("suple-${f.nombre}"), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(f.nombre) }
                    if (f.nuevo) withStyle(SpanStyle(color = c.marcaTexto, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)) { append("  nuevo") }
                    if (f.opcional) withStyle(SpanStyle(color = c.textoSecundario, fontSize = 12.sp)) { append("  opcional") }
                },
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f),
            )
            f.cantidad?.let {
                Spacer(Modifier.width(Espacio.s))
                Text(it, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.End, modifier = Modifier.widthIn(max = 160.dp))
            }
        }
        f.nota?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario) }
        f.porQue?.let { TextoRotulado("Por qué.", it, tonoTexto = c.texto) }
        for (d in f.detalle) TextoConNegritas(d, Modifier.padding(start = 2.dp))
        val clip = f.videoId?.let { porQue?.clip?.invoke(it) }?.takeIf { it.url != null }
        if (clip != null && porQue != null) {
            val abierto = porQue.abierto == clip.id
            OutlinedButton(
                onClick = { porQue.alternar(clip.id) },
                shape = RoundedCornerShape(50),
                border = BorderStroke(1.dp, c.marcaTexto),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 12.dp, end = 14.dp),
                modifier = Modifier
                    .padding(top = 4.dp)
                    .heightIn(min = 44.dp)
                    .semantics {
                        contentDescription = if (abierto) "Cerrar el video de ${f.nombre}" else "Ver por qué, video de ${f.nombre}"
                        stateDescription = (if (abierto) "abierto" else "cerrado") + if (clip.visto) ", visto" else ""
                    }
                    .testTag("ver-por-que-${clip.id}"),
            ) {
                when {
                    abierto -> Box(Modifier.size(9.dp).background(c.marcaTexto, RoundedCornerShape(1.dp)))
                    clip.visto -> Box(Modifier.size(16.dp).background(c.marca, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Iconos.Tilde, contentDescription = null, tint = Color.White, modifier = Modifier.size(11.dp))
                    }
                    else -> Icon(Iconos.Play, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(12.dp))
                }
                Spacer(Modifier.width(8.dp))
                Text(
                    if (abierto) "Cerrar el video" else ReglasGuia.rotuloPorQue(clip.minutos),
                    color = c.marcaTexto,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            if (abierto) Box(Modifier.padding(top = Espacio.s)) { porQue.contenido(clip) }
        }
    }
}

/**
 * «Ver por qué» de la suplementación (como pack.html, A5): el video del suplemento se abre debajo, en un reproductor chico,
 * con su duda. [abierto] es el clip abierto; [contenido] dibuja el reproductor y la duda de ese clip.
 */
class PorQueSuplemento(
    val abierto: String?,
    val clip: (String) -> ClipGuia?,
    val alternar: (String) -> Unit,
    val contenido: @Composable (ClipGuia) -> Unit,
)

/** Un texto con *negrita* de Markdown (el detalle de la suplementación). */
@Composable
fun TextoConNegritas(x: String, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Text(
        buildAnnotatedString {
            for ((t, negrita) in SuplementacionVista.tramos(x)) {
                if (negrita) withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = c.texto)) { append(t) } else append(t)
            }
        },
        style = MaterialTheme.typography.bodySmall,
        color = c.textoSecundario,
        modifier = modifier,
    )
}
