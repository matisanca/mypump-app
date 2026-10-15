package com.pumpteam.mypump.entreno

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.Alerta
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.BotonAlerta
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.ImagenRemota
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.abrirEnNavegador
import com.pumpteam.mypump.diseno.rellenoInferior
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.EstadosEjercicio
import com.pumpteam.mypump.reglas.IndiceComentarios
import com.pumpteam.mypump.reglas.NotaProgresion
import com.pumpteam.mypump.reglas.Pauta
import com.pumpteam.mypump.reglas.TextosEntreno
import java.time.ZoneId
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * La card abierta de un ejercicio (ENT-11) como pantalla (EjercicioView.swift): el movimiento, la pauta de la semana, la
 * nota de progresión, la variante, la tabla de series, la última vez y el récord a superar, sustituir / comentar / video,
 * cómo se hace, los comentarios con Mati y marcar completo, "Terminé este ejercicio" o reabrir. Con el ejercicio hecho,
 * "Siguiente: … →" (D13: no se abre solo). Lo que se usa en el gimnasio va primero: la pauta y la tabla quedan a la vista
 * sin desplazar.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun EjercicioPantalla(
    motor: ModeloEntreno,
    v: VistaEntreno,
    lugar: String,
    preguntador: Preguntador,
    alVolver: () -> Unit,
    alAbrir: (String) -> Unit,
    alCompletarDia: (ModeloEntreno.DiaCompletado) -> Unit,
) {
    val alcance = LocalAlcanceApp.current
    // Al entrar, la card queda abierta: pide el historial y marca leídos los comentarios (SES-08). Si el motor ya la abrió
    // (la siguiente pendiente, D13), igual se piden y se marcan: el cliente la está mirando. Al volver queda abierta en la
    // lista de Entreno, donde se carga (15-oct).
    DisposableEffect(lugar) {
        if (motor.dia.value.expandido != lugar) {
            alcance.launch { motor.tocarCard(lugar) }
        } else {
            alcance.launch { motor.marcarLeidos(lugar) }
            alcance.launch { motor.pedirHistorial(lugar) }
        }
        onDispose {}
    }
    val t = remember(v, lugar) { motor.tarjeta(lugar) }
    if (t == null) {
        MarcoPantalla("Ejercicio", alVolver = alVolver) { relleno ->
            EstadoVacio(
                icono = Iconos.Pesa,
                titulo = "Este ejercicio ya no está en el día",
                texto = "Volvé a la lista para ver el día actualizado.",
                modifier = Modifier.padding(relleno),
            )
        }
        return
    }

    val c = MyPump.colores
    val nombre = NombreEjercicio(t.efectivo.ejercicio.nombre)
    val desplazamiento = rememberScrollState()
    val comportamiento = TopAppBarDefaults.pinnedScrollBehavior()
    var altoEncabezado by remember { mutableIntStateOf(Int.MAX_VALUE) }
    val tituloEnBarra by remember { derivedStateOf { desplazamiento.value > altoEncabezado } }
    var sustituyendo by rememberSaveable { mutableStateOf(false) }
    val alcanceUi = rememberCoroutineScope()
    val pedirMovimiento = remember { BringIntoViewRequester() }
    val pedirComentarios = remember { BringIntoViewRequester() }
    val focoComentario = remember { FocusRequester() }

    Scaffold(
        modifier = Modifier.nestedScroll(comportamiento.nestedScrollConnection),
        containerColor = c.fondo,
        topBar = { BarraEntreno(nombre.principal, null, tituloEnBarra, comportamiento, alVolver) },
    ) { relleno ->
        Column(
            modifier = Modifier
                .padding(relleno)
                .fillMaxSize()
                .imePadding()
                .verticalScroll(desplazamiento)
                .testTag("ejercicio-pantalla"),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = AnchoLectura)
                    .fillMaxWidth()
                    .padding(horizontal = Espacio.m)
                    // Al final, lo que tapa la barra de pestañas flotante (con el teclado abierto, nada: la tapa él).
                    .padding(top = Espacio.xxs, bottom = Espacio.xl + rellenoInferior()),
                verticalArrangement = Arrangement.spacedBy(Espacio.l),
            ) {
                Encabezado(t, Modifier.onSizeChanged { altoEncabezado = it.height }) {
                    alcanceUi.launch { pedirMovimiento.bringIntoView() }
                }
                MetricasPauta(t.pauta, t.descanso, t.efectivo.ejercicio.tipo)
                t.nota?.let { NotaSemana(it) }
                if (t.filas.isNotEmpty()) TablaSeries(motor, v, lugar, t, preguntador, alCompletarDia)
                ASuperar(t, buscando = lugar in v.cargandoHistorial)
                Acciones(
                    t,
                    alSustituir = { sustituyendo = true },
                    alComentar = {
                        alcanceUi.launch {
                            pedirComentarios.bringIntoView()
                            focoComentario.requestFocus()
                        }
                    },
                )
                ComoSeHace(t, Modifier.bringIntoViewRequester(pedirMovimiento))
                Comentarios(motor, lugar, t, focoComentario, Modifier.bringIntoViewRequester(pedirComentarios))
                Cierre(motor, v, lugar, t, preguntador, alAbrir, alCompletarDia)
            }
        }
    }
    if (sustituyendo) HojaSustituir(motor, v, lugar, alCerrar = { sustituyendo = false })
}

// ── Secciones ──

/** Nombre y músculo, con el movimiento en chico al lado (tocarlo lleva a las fotos grandes), y si está sustituido, de qué. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Encabezado(t: ModeloEntreno.Tarjeta, modifier: Modifier = Modifier, alVerMovimiento: () -> Unit) {
    val c = MyPump.colores
    val ef = t.efectivo
    val nombre = NombreEjercicio(ef.ejercicio.nombre)
    val inicio = ef.ejercicio.imagenes?.eccentric
    val pico = ef.ejercicio.imagenes?.concentric
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            if (inicio != null || pico != null) {
                Box(
                    Modifier
                        .size(84.dp)
                        .clickable(onClickLabel = "Ver cómo se hace", onClick = alVerMovimiento)
                        .clearAndSetSemantics {
                            contentDescription = "Ver cómo se hace"
                            role = Role.Button
                        },
                ) {
                    ImagenesMovimiento(inicio, pico, compacto = true)
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(nombre.principal, style = Letras.titulo2, modifier = Modifier.semantics { heading() }.testTag("ejercicio-nombre"))
                nombre.detalle?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario) }
            }
        }
        if (ef.sustituido) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                InsigniaSustitucion(ef.fijado, Modifier.testTag("insignia-sustitucion"))
                Text(
                    "En lugar de ${NombreEjercicio(ef.nombreOriginal ?: "").principal}",
                    style = Letras.caption.copy(fontSize = 13.sp),
                    color = c.textoSecundario,
                    maxLines = 2,
                    modifier = Modifier.testTag("en-lugar-de"),
                )
            }
        }
        if (t.manual || t.sinLeer > 0) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (t.manual) ChipDato("Marcado a mano", icono = Iconos.Mano)
                if (t.sinLeer > 0) ChipDato("${t.sinLeer} de Mati", icono = Iconos.Burbuja, tono = c.marcaTexto)
            }
        }
    }
}

/** La pauta de la semana como métricas, no como chips: series × reps, RIR y descanso, con el número en Archivo. */
@Composable
private fun MetricasPauta(pauta: Pauta, descanso: String, tipo: String?) {
    val c = MyPump.colores
    data class Metrica(val titulo: String, val valor: String, val detalle: String? = null)
    val metricas = buildList {
        pauta.reps?.let { r ->
            val s = pauta.series
            if (s != null && tipo != "cardio") add(Metrica("Series × reps", "$s × $r")) else add(Metrica("Duración", r))
        }
        pauta.rir?.let { rir ->
            val (principal, detalle) = partirParentesis(rir)
            add(Metrica("RIR", principal, detalle))
        }
        if (descanso.isNotEmpty() && descanso != "0:00") add(Metrica("Descanso", descanso))
    }
    if (metricas.isEmpty()) return
    val letraGrande = LocalDensity.current.fontScale >= 1.3f
    Column(Modifier.fillMaxWidth().superficieTarjeta().padding(14.dp).testTag("metricas"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        if (letraGrande) {
            // Con letra grande, una métrica por renglón: rótulo a la izquierda, número a la derecha.
            for (m in metricas) {
                Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
                    Text(m.titulo, style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.textoSecundario, modifier = Modifier.weight(1f))
                    Column(horizontalAlignment = Alignment.End) {
                        Text(m.valor, style = Numeros.mediano.merge(Letras.cifras), color = c.texto)
                        m.detalle?.let { Text(it, style = Letras.caption, color = c.textoSecundario) }
                    }
                }
            }
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                metricas.forEachIndexed { i, m ->
                    if (i > 0) SeparadorVertical(alto = 44.dp)
                    Column(
                        Modifier.weight(1f).semantics(mergeDescendants = true) {},
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        Ceja(m.titulo)
                        Text(m.valor, style = Numeros.mediano.merge(Letras.cifras), color = c.texto, maxLines = 1, textAlign = TextAlign.Center)
                        m.detalle?.let { Text(it, style = Letras.caption2.copy(fontWeight = FontWeight.Medium), color = c.textoSecundario, textAlign = TextAlign.Center) }
                    }
                }
            }
        }
    }
}

/** "0 (al fallo)" → ("0", "al fallo"). Sin paréntesis, entero. */
internal fun partirParentesis(s: String): Pair<String, String?> {
    val abre = s.indexOf('(')
    if (!s.endsWith(")") || abre < 0) return s to null
    val principal = s.substring(0, abre).trim()
    val detalle = s.substring(abre + 1, s.length - 1).trim()
    return (principal.ifEmpty { s }) to detalle.ifEmpty { null }
}

/** La nota de la semana contra la anterior (ENT-07) o la de calibración. */
@Composable
private fun NotaSemana(nota: NotaProgresion) {
    val c = MyPump.colores
    val rotulo = if (nota.cambia) "Cambio de la semana" else if (nota.calibracion) "Semana 1" else "Esta semana"
    val icono = if (nota.cambia) Iconos.Tendencia else if (nota.calibracion) Iconos.Mira else Iconos.Calendario
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.control + 4.dp))
            .background(if (nota.cambia) c.marcaSuave else c.tarjeta)
            .padding(Espacio.m)
            .semantics(mergeDescendants = true) {}
            .testTag("nota-semana"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Icon(icono, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(15.dp))
            Text(rotulo, style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.marcaTexto)
        }
        Text(nota.texto, style = Letras.subtitulo, color = c.texto)
    }
}

/** "Última vez (…)" y "Récord a superar". Sin historial no va nada: la primera vez ya la explica la tabla (la calibración). */
@Composable
private fun ASuperar(t: ModeloEntreno.Tarjeta, buscando: Boolean) {
    val c = MyPump.colores
    val u = t.ultimaVez
    val r = t.record
    if (u != null || r != null) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            if (u != null) {
                val (principal, detalle) = Bonito.partir(u.valor)
                Dato(
                    "Última vez",
                    principal,
                    listOfNotNull(u.cuando, detalle).joinToString(" · "),
                    Iconos.Calendario,
                    Modifier.weight(1f).testTag("ultima-vez"),
                )
            }
            if (r != null) {
                val (principal, detalle) = Bonito.partir(r)
                Dato("Récord a superar", principal, detalle ?: "mejor serie", Iconos.Trofeo, Modifier.weight(1f).testTag("record"), tono = c.record)
            }
        }
    } else if (t.filas.isNotEmpty() && !t.sinKg && buscando) {
        Row(
            Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
        ) {
            CircularProgressIndicator(Modifier.size(18.dp), color = c.marcaTexto, strokeWidth = 2.dp)
            Text("Buscando tu última vez…", style = Letras.subtitulo, color = c.textoSecundario)
        }
    }
}

/** Sustituir (o cambiar el sustituto), comentar y el video. */
@Composable
private fun Acciones(t: ModeloEntreno.Tarjeta, alSustituir: () -> Unit, alComentar: () -> Unit) {
    val c = MyPump.colores
    val contexto = LocalContext.current
    val puede = t.puedeSustituir || t.efectivo.sustituido
    val tipo = t.efectivo.ejercicio.tipo
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            AccionTarjeta(
                if (t.efectivo.sustituido) "Cambiar" else "Sustituir",
                Iconos.Intercambio,
                habilitada = puede,
                alTocar = alSustituir,
                modifier = Modifier.weight(1f).testTag("sustituir"),
            )
            AccionTarjeta("Comentar", Iconos.Burbuja, alTocar = alComentar, modifier = Modifier.weight(1f).testTag("comentar"))
            t.efectivo.ejercicio.videoUrl?.takeIf { it.startsWith("http") }?.let { url ->
                AccionTarjeta("Video", Iconos.Video, alTocar = { abrirEnNavegador(contexto, url) }, modifier = Modifier.weight(1f).testTag("video"))
            }
        }
        if (!puede && tipo != "calentamiento" && tipo != "cardio") {
            Text(TextosEntreno.SIN_VARIANTES, style = Letras.caption, color = c.textoSecundario, modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
}

/** Botón de acción en tarjeta: ícono arriba, rótulo abajo (como las acciones de Contactos). Deshabilitado se ve apagado. */
@Composable
private fun AccionTarjeta(texto: String, icono: ImageVector, alTocar: () -> Unit, modifier: Modifier = Modifier, habilitada: Boolean = true) {
    val c = MyPump.colores
    Column(
        modifier = modifier
            .defaultMinSize(minHeight = 64.dp)
            .superficieTarjeta(radio = Radio.control + 4.dp)
            .clickable(enabled = habilitada, role = Role.Button, onClick = alTocar)
            .graphicsLayer { alpha = if (habilitada) 1f else 0.45f }
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        Icon(icono, contentDescription = null, tint = if (habilitada) c.marcaTexto else c.textoSecundario, modifier = Modifier.size(22.dp))
        Text(texto, style = Letras.caption.copy(fontWeight = FontWeight.SemiBold), color = c.texto)
    }
}

/**
 * Los botones del ejercicio abierto en la lista: el ícono y el texto en un renglón, de 44 de alto. Los apilados de la
 * página ([AccionTarjeta]) ocupaban casi el doble, y abierto en la lista cada renglón cuenta.
 */
@Composable
private fun AccionEnFila(texto: String, icono: ImageVector, alTocar: () -> Unit, modifier: Modifier = Modifier, habilitada: Boolean = true) {
    val c = MyPump.colores
    Row(
        modifier = modifier
            .defaultMinSize(minHeight = 44.dp)
            .superficieTarjeta(radio = Radio.control + 4.dp)
            .clickable(enabled = habilitada, role = Role.Button, onClick = alTocar)
            .graphicsLayer { alpha = if (habilitada) 1f else 0.45f }
            .padding(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icono, contentDescription = null, tint = if (habilitada) c.marcaTexto else c.textoSecundario, modifier = Modifier.size(18.dp))
        Text(texto, style = MaterialTheme.typography.labelLarge, color = c.texto, textAlign = TextAlign.Center)
    }
}

/** Las fotos grandes del movimiento y la nota técnica de Mati, juntas. */
@Composable
private fun ComoSeHace(t: ModeloEntreno.Tarjeta, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val inicio = t.efectivo.ejercicio.imagenes?.eccentric
    val pico = t.efectivo.ejercicio.imagenes?.concentric
    val hayFotos = inicio != null || pico != null
    val notas = t.efectivo.ejercicio.notasTecnica?.takeIf { it.isNotEmpty() }
    if (!hayFotos && notas == null) return
    Column(modifier.testTag("como-se-hace"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Text("Cómo se hace", style = Letras.titulo3, modifier = Modifier.padding(horizontal = 4.dp).semantics { heading() })
        Column(
            Modifier.fillMaxWidth().superficieTarjeta().padding(if (hayFotos) 10.dp else Espacio.m),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
        ) {
            if (hayFotos) ImagenesMovimiento(inicio, pico)
            if (notas != null) {
                Column(
                    Modifier.padding(horizontal = if (hayFotos) 4.dp else 0.dp).semantics(mergeDescendants = true) {},
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Icon(Iconos.Cita, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(15.dp))
                        Text("Nota técnica de Mati", style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.textoSecundario)
                    }
                    Text(notas, style = MaterialTheme.typography.bodyLarge, color = c.texto)
                }
            }
        }
    }
}

/**
 * Las dos fotos del catálogo (inicio y pico) alternándose: se ve el recorrido sin video. Con "Quitar animaciones" no se
 * alternan solas; el selector de abajo elige cuál ver (y frena la alternancia).
 */
@Composable
fun ImagenesMovimiento(inicio: String?, pico: String?, modifier: Modifier = Modifier, compacto: Boolean = false) {
    val c = MyPump.colores
    var fase by rememberSaveable { mutableIntStateOf(0) }
    var automatico by rememberSaveable { mutableStateOf(true) }
    val reducir = reducirMovimiento()
    val ambas = inicio != null && pico != null
    LaunchedEffect(automatico, reducir, ambas) {
        if (!automatico || reducir || !ambas) return@LaunchedEffect
        while (true) {
            delay(1_600)
            fase = 1 - fase
        }
    }
    val radio = if (compacto) Radio.miniatura + 6.dp else Radio.tarjeta - 10.dp
    val forma = RoundedCornerShape(radio)
    val lado: Dp = if (compacto) 84.dp else 600.dp
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(if (compacto) 1f else 1.5f)
            .clip(forma)
            .background(Color.White)
            .border(1.dp, c.borde, forma)
            .then(if (compacto) Modifier else Modifier.semantics { contentDescription = "Fotos del movimiento: inicio y pico" }),
    ) {
        val urls = listOf(inicio, pico)
        for (i in 0..1) {
            val u = urls[i]
            if (u != null) {
                val alfa by animateFloatAsState(if (fase == i || !ambas) 1f else 0f, tween(450), label = "foto$i")
                ImagenRemota(u, lado, Modifier.fillMaxSize().graphicsLayer { alpha = alfa }) {
                    Box(Modifier.fillMaxSize().background(c.campo), contentAlignment = Alignment.Center) {
                        Icon(Iconos.Foto, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(if (compacto) 22.dp else 36.dp))
                    }
                }
            }
        }
        if (!compacto && ambas) {
            Row(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(Espacio.s)
                    .clip(CircleShape)
                    .background(c.tarjeta.copy(alpha = 0.92f))
                    .padding(3.dp),
            ) {
                listOf("Inicio", "Pico").forEachIndexed { i, rotulo ->
                    Text(
                        rotulo,
                        style = Letras.caption.copy(fontWeight = FontWeight.SemiBold),
                        color = if (fase == i) c.sobreMarca else c.texto,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(if (fase == i) c.marca else Color.Transparent)
                            .clickable(role = Role.Tab) {
                                automatico = false
                                fase = i
                            }
                            .semantics { selected = fase == i }
                            .padding(horizontal = 14.dp, vertical = 8.dp)
                            .testTag("foto-$rotulo"),
                    )
                }
            }
        }
    }
}

/** Los comentarios con Mati sobre este ejercicio (SES-08): van directo, no por la cola. */
@Composable
private fun Comentarios(motor: ModeloEntreno, lugar: String, t: ModeloEntreno.Tarjeta, foco: FocusRequester, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val focoManager = LocalFocusManager.current
    var comentario by rememberSaveable(lugar) { mutableStateOf("") }
    var enviando by remember { mutableStateOf(false) }
    var fallo by remember { mutableStateOf(false) }
    val vacio = comentario.isBlank()
    fun comentar() {
        val texto = comentario
        focoManager.clearFocus()
        enviando = true
        alcance.launch {
            val ok = motor.comentar(lugar, texto)
            enviando = false
            if (ok) comentario = "" else fallo = true
        }
    }
    Column(modifier.testTag("comentarios"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Text("Comentarios", style = Letras.titulo3, modifier = Modifier.padding(horizontal = 4.dp).semantics { heading() })
        Column(Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
            if (t.comentarios.isEmpty()) {
                Text(TextosEntreno.SIN_COMENTARIOS, style = Letras.subtitulo, color = c.textoSecundario)
            } else {
                for (cm in t.comentarios) {
                    val deMati = cm.autor == "coach"
                    Column(
                        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
                        horizontalAlignment = if (deMati) Alignment.Start else Alignment.End,
                        verticalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        SelectionContainer {
                            Text(
                                cm.contenido,
                                style = Letras.subtitulo,
                                color = if (deMati) c.texto else c.sobreMarca,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(if (deMati) c.campo else c.marca)
                                    .padding(horizontal = 12.dp, vertical = 8.dp),
                            )
                        }
                        Text(
                            "${if (deMati) "Mati" else "Vos"} · ${IndiceComentarios.fecha(cm.createdAt, ZoneId.systemDefault())}",
                            style = Letras.caption2,
                            color = c.textoSecundario,
                        )
                    }
                }
            }
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                BasicTextField(
                    value = comentario,
                    onValueChange = { comentario = it },
                    maxLines = 4,
                    textStyle = Letras.subtitulo.copy(color = c.texto),
                    cursorBrush = SolidColor(c.marcaTexto),
                    modifier = Modifier
                        .weight(1f)
                        .focusRequester(foco)
                        .semantics { contentDescription = "Comentario para Mati" }
                        .testTag("campo-comentario"),
                    decorationBox = { campo ->
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 44.dp)
                                .clip(RoundedCornerShape(20.dp))
                                .background(c.campo)
                                .padding(horizontal = 14.dp, vertical = 11.dp),
                            contentAlignment = Alignment.CenterStart,
                        ) {
                            if (comentario.isEmpty()) {
                                Text(
                                    "Escribí una nota… (ej: hice plano con mancuernas porque la máquina estaba ocupada)",
                                    style = Letras.subtitulo,
                                    color = c.textoTerciario,
                                    modifier = Modifier.clearAndSetSemantics {},
                                )
                            }
                            campo()
                        }
                    },
                )
                val puede = !vacio && !enviando && !motor.demo
                Box(
                    Modifier
                        .size(44.dp)
                        .clickable(enabled = puede, role = Role.Button) { comentar() }
                        .semantics { contentDescription = "Enviar comentario" }
                        .testTag("enviar-comentario"),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(40.dp).clip(CircleShape).background(if (vacio) c.campo else c.marca), contentAlignment = Alignment.Center) {
                        if (enviando) {
                            CircularProgressIndicator(Modifier.size(18.dp), color = c.sobreMarca, strokeWidth = 2.dp)
                        } else {
                            Icon(Iconos.FlechaArriba, contentDescription = null, tint = if (vacio) c.textoSecundario else c.sobreMarca, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
        }
    }
    if (fallo) {
        Alerta(
            titulo = "No se pudo enviar",
            mensaje = TextosEntreno.COMENTARIO_FALLO,
            botones = listOf(BotonAlerta("OK") { fallo = false }),
            alDescartar = { fallo = false },
        )
    }
}

/**
 * Marcar completo (con todas las series), "Terminé este ejercicio" o reabrir. Con el ejercicio hecho, el siguiente
 * pendiente a un toque (ENT-17 con D13: "Siguiente: … →" en vez de abrirse solo).
 */
@Composable
private fun Cierre(
    motor: ModeloEntreno,
    v: VistaEntreno,
    lugar: String,
    t: ModeloEntreno.Tarjeta,
    preguntador: Preguntador,
    alAbrir: (String) -> Unit,
    alCompletarDia: (ModeloEntreno.DiaCompletado) -> Unit,
    enLista: Boolean = false,
) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val haptico = LocalHapticFeedback.current
    val terminal = t.estado in EstadosEjercicio.terminales
    val todas = t.filas.isNotEmpty() && t.confirmadas == t.filas.size
    var eraTerminal by remember { mutableStateOf(terminal) }
    LaunchedEffect(terminal) {
        if (terminal && !eraTerminal) haptico.performHapticFeedback(HapticFeedbackType.Confirm)
        eraTerminal = terminal
    }
    fun terminar() {
        alcance.launch { motor.terminar(lugar) { preguntador.preguntar(it) }?.let(alCompletarDia) }
    }

    @Composable
    fun TermineTexto() {
        TextButton(onClick = ::terminar, modifier = Modifier.heightIn(min = 44.dp).testTag("termine-ejercicio")) {
            Text(
                buildAnnotatedString { withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append("Terminé este ejercicio") } },
                style = Letras.subtitulo,
                color = c.marcaTexto,
            )
        }
    }
    Column(
        Modifier.fillMaxWidth().padding(top = Espacio.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        if (terminal) {
            // En la lista no hace falta «Siguiente»: el motor ya abre el que sigue, ahí abajo.
            val sig = v.dia.expandido?.takeIf { it != lugar && !enLista }
            val e = sig?.let { v.dia.ejercicio(it) }
            if (sig != null && e != null) {
                BotonConIcono(
                    "Siguiente: ${NombreEjercicio(motor.efectivo(e).ejercicio.nombre).principal}",
                    Iconos.FlechaDerecha,
                    iconoAlFinal = true,
                    alTocar = { alAbrir(sig) },
                    modifier = Modifier.testTag("siguiente-ejercicio"),
                )
            }
            BotonConIcono(
                "Reabrir ejercicio",
                Iconos.Lapiz,
                principal = false,
                alTocar = { alcance.launch { motor.reabrir(lugar) } },
                modifier = Modifier.testTag("reabrir-ejercicio"),
            )
        } else if (enLista && !todas) {
            // Abierto en la lista, como en iOS: solo «Terminé este ejercicio». El botón apagado de «Confirmá las series
            // para completar» ocupaba un renglón sin hacer nada.
            TermineTexto()
        } else if (t.filas.isEmpty()) {
            // Sin series (cardio, por tiempo): se marca hecho directamente.
            BotonConIcono("Terminé este ejercicio", Iconos.Tilde, alTocar = ::terminar, modifier = Modifier.testTag("termine-ejercicio"))
        } else {
            BotonConIcono(
                if (todas) "Marcar ejercicio completo" else "Confirmá las series para completar",
                Iconos.Tilde,
                habilitado = todas,
                alTocar = { alcance.launch { motor.marcarCompleto(lugar)?.let(alCompletarDia) } },
                modifier = Modifier.testTag("marcar-completo"),
            )
            if (!enLista) TermineTexto()
        }
    }
}

/**
 * El ejercicio abierto adentro de la lista de Entreno, como la card de la web (Mati, 15-oct: ir a otra página por cada
 * ejercicio empeoraba el uso): la tabla de series, sustituir, la página del ejercicio para la técnica, el video y los
 * comentarios, y el cierre. Al completarlo, el motor abre el siguiente pendiente. El de `EntrenoView.swift`.
 */
@Composable
internal fun EjercicioEnLista(
    motor: ModeloEntreno,
    v: VistaEntreno,
    lugar: String,
    preguntador: Preguntador,
    alAbrir: (String) -> Unit,
    alCompletarDia: (ModeloEntreno.DiaCompletado) -> Unit,
) {
    val t = remember(v, lugar) { motor.tarjeta(lugar) } ?: return
    val c = MyPump.colores
    var sustituyendo by rememberSaveable(lugar) { mutableStateOf(false) }
    Column(
        Modifier
            .fillMaxWidth()
            .background(c.campo.copy(alpha = c.campo.alpha * 0.35f))
            .padding(bottom = Espacio.s)
            .testTag("ejercicio-abierto-$lugar"),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        TablaSeries(motor, v, lugar, t, preguntador, alCompletarDia, enLista = true)
        // Con la letra muy grande, uno debajo del otro: en un renglón partían las palabras («Sus-tituir»).
        val apilados = LocalDensity.current.fontScale > 1.35f
        val sustituir: @Composable (Modifier) -> Unit = { m ->
            AccionEnFila(
                if (t.efectivo.sustituido) "Cambiar" else "Sustituir",
                Iconos.Intercambio,
                habilitada = t.puedeSustituir || t.efectivo.sustituido,
                alTocar = { sustituyendo = true },
                modifier = m.testTag("sustituir"),
            )
        }
        val tecnica: @Composable (Modifier) -> Unit = { m ->
            AccionEnFila("Técnica y notas", Iconos.Libro, alTocar = { alAbrir(lugar) }, modifier = m.testTag("tecnica-y-notas"))
        }
        if (apilados) {
            Column(Modifier.fillMaxWidth().padding(horizontal = Espacio.m), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                sustituir(Modifier.fillMaxWidth())
                tecnica(Modifier.fillMaxWidth())
            }
        } else {
            Row(Modifier.fillMaxWidth().padding(horizontal = Espacio.m), horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                sustituir(Modifier.weight(1f))
                tecnica(Modifier.weight(1f))
            }
        }
        Box(Modifier.padding(horizontal = Espacio.m)) { Cierre(motor, v, lugar, t, preguntador, alAbrir, alCompletarDia, enLista = true) }
    }
    if (sustituyendo) HojaSustituir(motor, v, lugar, alCerrar = { sustituyendo = false })
}
