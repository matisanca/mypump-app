package com.pumpteam.mypump.entreno

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.key
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.AvanceSegmentos
import com.pumpteam.mypump.diseno.BotonAccion
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.DatoHeroe
import com.pumpteam.mypump.diseno.Heroe
import com.pumpteam.mypump.diseno.Letra
import com.pumpteam.mypump.diseno.apoyo
import com.pumpteam.mypump.diseno.BotonVolver
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.LocalRellenoInferior
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.raiz.BannerRevision
import com.pumpteam.mypump.fotosinicio.TarjetaFotosInicioDe
import com.pumpteam.mypump.gimnasio.TarjetaGimnasioDe
import com.pumpteam.mypump.guia.TarjetaVideollamadaEntreno
import com.pumpteam.mypump.guia.TarjetaGuiaDe
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.Js
import com.pumpteam.mypump.reglas.NormalizacionRutina
import com.pumpteam.mypump.reglas.Progresiones
import com.pumpteam.mypump.reglas.ReglasEjercicio
import com.pumpteam.mypump.reglas.ReglasGuia
import com.pumpteam.mypump.reglas.SemanaEntreno
import com.pumpteam.mypump.reglas.TextosEntreno
import com.pumpteam.mypump.reglas.TiempoEntreno
import com.pumpteam.mypump.respaldo.OrigenRespaldo
import com.pumpteam.mypump.respaldo.PieRespaldo
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * El día del motor (ListaEntreno de EntrenoView.swift): arriba "DÍA n · SEMANA x DE y", el nombre, cuántos ejercicios y
 * el anillo; el selector de días, los avisos de progresión o calibración, el cronómetro, los bloques con sus ejercicios,
 * el resumen o la tarjeta de cierre, y avanzar de semana o empezar el bloque nuevo. Al bajar, el nombre pasa chico a la
 * barra de arriba.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListaEntreno(
    motor: ModeloEntreno,
    v: VistaEntreno,
    deEjemplo: Boolean,
    modelo: ModeloApp,
    preguntador: Preguntador,
    desplazamiento: ScrollState,
    alAbrir: (String) -> Unit,
    alCompletarDia: (ModeloEntreno.DiaCompletado) -> Unit,
) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    var cerrando by rememberSaveable { mutableStateOf(false) }
    var recargando by remember { mutableStateOf(false) }
    var altoCabecera by remember { mutableIntStateOf(Int.MAX_VALUE) }
    val d = v.dia.dia
    val titulo = Bonito.titulo(d.nombre).ifEmpty { "Día ${motor.numero(d)}" }
    val tituloEnBarra by remember { derivedStateOf { desplazamiento.value > altoCabecera } }
    val comportamiento = TopAppBarDefaults.pinnedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(comportamiento.nestedScrollConnection),
        containerColor = c.fondo,
        topBar = { BarraEntreno(titulo, "Semana ${motor.semanaMostrada} de ${motor.totalMostrado}", tituloEnBarra, comportamiento) },
        // El panel de la carga va fuera de la lista: deslizar el dial no puede mover la pantalla. Con el ejercicio ya cerrado
        // sigue mientras se pueda deshacer la última serie.
        bottomBar = {
            val deshacible by motor.deshacible.collectAsStateWithLifecycle()
            val lugar = v.dia.expandido ?: deshacible?.lugar
            if (lugar != null && motor.tarjeta(lugar)?.filas?.isNotEmpty() == true) {
                key(lugar) { PanelCarga(motor, lugar, preguntador) }
            }
        },
    ) { relleno ->
        PullToRefreshBox(
            isRefreshing = recargando,
            onRefresh = {
                recargando = true
                alcance.launch {
                    try {
                        // Como Dieta, la carga entera: trae la rutina si Mati la republicó (hallazgo 6 del 15-oct).
                        modelo.refrescarEntreno()
                    } finally {
                        recargando = false
                    }
                }
            },
            // Abajo no se recorta: la lista sigue por detrás del panel (sus esquinas y el Deshacer flotante dejan verla) y el
            // lugar del panel va como relleno al final.
            modifier = Modifier.padding(top = relleno.calculateTopPadding()).fillMaxSize(),
        ) {
            Column(
                modifier = Modifier.fillMaxSize().verticalScroll(desplazamiento).testTag("entreno-lista"),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    modifier = Modifier
                        .widthIn(max = AnchoLectura)
                        .fillMaxWidth()
                        .padding(horizontal = Espacio.m)
                        // Al final, lo que tapa la barra de pestañas flotante: lo último queda arriba de ella.
                        // (con el panel de la carga, ese lugar ya lo descuenta el Scaffold).
                        .padding(top = Espacio.xxs, bottom = Espacio.xl + relleno.calculateBottomPadding().takeIf { it > 0.dp }.let { it ?: LocalRellenoInferior.current }),
                    verticalArrangement = Arrangement.spacedBy(Espacio.l),
                ) {
                    // «Tu guía» mientras falta ver algo: verde y primera, arriba de todo, como iOS (revisión del 4-nov, hallazgo 5).
                    // La videollamada fija arriba (2.3.0), desde que se agenda hasta que termina (aunque la tarjeta de la
                    // guía esté oculta); con la palanca `elegir_horario`, «Agendá tu videollamada».
                    TarjetaVideollamadaEntreno(modelo)
                    // Un estudio pedido o una orden nueva (10-nov): después de la entrega de ahora (tiene hora) y antes de
                    // la guía. El mismo orden en iOS.
                    com.pumpteam.mypump.estudios.TarjetaEstudiosInicioDe(modelo)
                    TarjetaGuiaDe(modelo, solo = ReglasGuia.EstiloTarjeta.DESTACADA)
                    TarjetaFotosInicioDe(modelo, soloSiFaltan = true)
                    TarjetaGimnasioDe(modelo)
                    com.pumpteam.mypump.novedades.TarjetaNovedadDe(modelo)
                    // Los días arriba de la tarjeta principal: se elige el día y la tarjeta lo muestra.
                    // Con un solo día no hay nada que elegir: la web no lo muestra (`renderDayPicker`).
                    if (motor.dias.size > 1) SelectorDias(motor, v)
                    // Hasta dónde llega la cabecera (con la tarjeta arriba, no es solo su alto): el título pasa a la barra después.
                    Cabecera(
                        motor, v, titulo,
                        alCerrarDia = { cerrando = true },
                        modifier = Modifier.onGloballyPositioned { altoCabecera = (it.positionInParent().y + it.size.height).toInt() },
                    )
                    if (deEjemplo) {
                        // Con cuenta y un motor de ejemplo (Mati todavía no publicó el plan): el aviso de la web (ACC-08).
                        AvisoTenido(
                            Iconos.Alerta,
                            AnnotatedString(Bonito.sinEmoji(TextosEntreno.DEMO).replace("Modo demo — ", "")),
                            tono = c.alerta,
                            modifier = Modifier.testTag("aviso-demo"),
                        )
                    }
                    // Con todo visto, la compacta en su lugar de siempre.
                    TarjetaGuiaDe(modelo, solo = ReglasGuia.EstiloTarjeta.COMPACTA)
                    BannerRevision(modelo)
                    // «Pump del día» (2.3.0): solo con la palanca `metas_pasos` y una meta de pasos en el plan.
                    com.pumpteam.mypump.metas.PumpDelDiaDe(modelo)
                    // El contrato sin firmar: un renglón que lleva a Documentos (no frena nada).
                    com.pumpteam.mypump.misdatos.AvisoContratoPendiente(modelo)
                    if (motor.vacio) {
                        DiaVacio()
                    } else {
                        CuerpoDia(motor, v, preguntador, alAbrir, alCompletarDia, alCerrarDia = { cerrando = true })
                    }
                    PieRespaldo(OrigenRespaldo.ENTRENO, Modifier.padding(top = Espacio.xs))
                }
            }
        }
    }
    if (cerrando) HojaCerrarDia(modelo, motor, v, alCerrar = { cerrando = false })
}

/** La barra de arriba: vacía mientras se ve la cabecera; al bajar, el título (y la semana) en chico. Con [alVolver], la flecha. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BarraEntreno(
    titulo: String,
    subtitulo: String?,
    tituloVisible: Boolean,
    comportamiento: TopAppBarScrollBehavior,
    alVolver: (() -> Unit)? = null,
) {
    val c = MyPump.colores
    val alfa by animateFloatAsState(if (tituloVisible) 1f else 0f, tween(200), label = "titulo")
    CenterAlignedTopAppBar(
        title = {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .graphicsLayer { alpha = alfa }
                    // Escondido no se lee (está la cabecera).
                    .then(if (tituloVisible) Modifier else Modifier.clearAndSetSemantics {}),
            ) {
                Text(titulo, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (subtitulo != null) Text(subtitulo, style = Letras.caption2.copy(fontWeight = FontWeight.Medium), color = c.textoSecundario)
            }
        },
        navigationIcon = { if (alVolver != null) BotonVolver(alVolver, Modifier.padding(start = Espacio.xs)) },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = c.fondo,
            scrolledContainerColor = c.tarjeta,
            titleContentColor = c.texto,
            navigationIconContentColor = c.marcaTexto,
            actionIconContentColor = c.marcaTexto,
        ),
        expandedHeight = 52.dp,
        scrollBehavior = comportamiento,
    )
}

// ── Cabecera ──

/**
 * La tarjeta principal del día (la firma de Entreno, igual en claro y en oscuro): el nombre, cómo voy (hechos, tiempo y lo
 * que resta, con un segmento por ejercicio) y el botón del día o el reloj de la sesión. Antes eran cuatro bloques sueltos.
 */
@Composable
private fun Cabecera(motor: ModeloEntreno, v: VistaEntreno, titulo: String, alCerrarDia: () -> Unit, modifier: Modifier = Modifier) {
    val d = v.dia.dia
    val total = motor.totalEjercicios
    val hechos = motor.hechos
    val cerrado = v.dia.diaFinalizado || motor.hecho(d)
    val escala = LocalDensity.current.fontScale
    var tic by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            tic++
        }
    }
    val minutos = remember(tic / 30, v) { motor.minutos }
    Heroe(modifier.testTag("entreno-cabecera")) {
        val c = MyPump.colores
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Ceja("Día ${motor.numero(d)} · Semana ${motor.semanaMostrada} de ${motor.totalMostrado}", Modifier.testTag("entreno-semana"))
            if (escala >= 1.3f) {
                // Con letra grande el nombre del día baja de renglón en vez de achicarse.
                Text(titulo, style = Letras.tituloDia.copy(fontSize = 34.sp, lineHeight = 40.sp), color = c.texto, maxLines = 3, modifier = Modifier.semantics { heading() }.testTag("entreno-titulo"))
            } else {
                BasicText(
                    titulo,
                    style = Letras.tituloDia.copy(color = c.texto),
                    maxLines = 1,
                    autoSize = TextAutoSize.StepBased(minFontSize = 24.sp, maxFontSize = 40.sp),
                    modifier = Modifier.semantics { heading() }.testTag("entreno-titulo"),
                )
            }
        }
        Column(
            Modifier.clearAndSetSemantics { contentDescription = "$hechos de $total ejercicios hechos" }.testTag("avance-dia"),
            verticalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                DatoHeroe("$hechos/$total", "Hechos", Modifier.weight(1f).testTag("entreno-hechos"))
                DatoHeroe(minutos?.let { "$it min" } ?: "—", "Tiempo", Modifier.weight(1f))
                DatoHeroe("${total - hechos} ej", "Restan", Modifier.weight(1f))
            }
            AvanceSegmentos(total, hechos, alto = 6.dp)
        }
        if (cerrado) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Iconos.Verificado, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                Text(
                    "Día cerrado esta semana",
                    style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold),
                    color = c.marcaTexto,
                    modifier = Modifier.testTag("entreno-cantidad"),
                )
            }
        }
        // Con el día cerrado o todo hecho no hay cronómetro (está la tarjeta de cierre).
        if (!motor.vacio && !motor.todoHecho) Cronometro(motor, remember(tic, v) { motor.cronometro() }, alCerrarDia)
    }
}

// ── Selector de días ──

/**
 * Cápsulas con "DÍA n" y la primera palabra del nombre (ENT-01). La elegida va invertida; las cerradas esta semana llevan
 * el tilde de marca y las que tienen comentarios de Mati sin leer, el globo (los dos a la vez, como la web).
 */
@Composable
private fun SelectorDias(motor: ModeloEntreno, v: VistaEntreno) {
    val desplazamiento = rememberScrollState()
    val posiciones = remember { mutableStateMapOf<String, Pair<Int, Int>>() }
    var anchoVisible by remember { mutableIntStateOf(0) }
    val activo = v.dia.dia.id
    // La elegida queda centrada (como `scrollTo(id, anchor: .center)`).
    LaunchedEffect(activo, anchoVisible, posiciones[activo]) {
        val (x, ancho) = posiciones[activo] ?: return@LaunchedEffect
        if (anchoVisible == 0) return@LaunchedEffect
        desplazamiento.animateScrollTo((x + ancho / 2 - anchoVisible / 2).coerceIn(0, desplazamiento.maxValue))
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .onSizeChanged { anchoVisible = it.width }
            .horizontalScroll(desplazamiento)
            .padding(vertical = 6.dp)
            .testTag("selector-dias"),
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        for (d in motor.dias) {
            BotonDia(
                motor,
                d,
                activo = d.id == activo,
                hecho = d.id != null && d.id in v.completados,
                mensajes = v.comentarios.sinLeerDia(d),
                modifier = Modifier.onPlaced { l -> d.id?.let { posiciones[it] = l.positionInParent().x.toInt() to l.size.width } },
            )
        }
    }
}

@Composable
private fun BotonDia(motor: ModeloEntreno, d: Dia, activo: Boolean, hecho: Boolean, mensajes: Int, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val haptico = LocalHapticFeedback.current
    val corto = Bonito.titulo(motor.nombreCorto(d)).ifEmpty { "Día" }
    val forma = CircleShape
    val descripcion = buildString {
        append("Día ${motor.numero(d)}, $corto")
        if (hecho) append(", cerrado esta semana")
        if (mensajes > 0) append(", $mensajes comentarios sin leer")
    }
    Box(modifier.padding(top = 6.dp, end = 6.dp)) {
        Column(
            modifier = Modifier
                .defaultMinSize(minWidth = 70.dp, minHeight = 44.dp)
                .clip(forma)
                .background(c.tarjeta)
                // La selección es un anillo verde, como la serie actual de la carga: el negro es de la tarjeta principal.
                .border(if (activo) 2.dp else 1.dp, if (activo) c.marca else c.borde, forma)
                .clickable(role = Role.Tab) {
                    val id = d.id ?: return@clickable
                    if (activo) return@clickable
                    haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
                    alcance.launch { motor.cambiarDia(id) }
                }
                .padding(vertical = Espacio.xs, horizontal = 18.dp)
                .semantics {
                    contentDescription = descripcion
                    selected = activo
                }
                .testTag("dia-${d.id}"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(1.dp),
        ) {
            Text(
                "DÍA ${motor.numero(d)}",
                style = Letras.caption2.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp),
                color = if (activo) c.marcaTexto else c.apoyo,
                maxLines = 1,
            )
            Text(corto, style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.texto, maxLines = 1)
        }
        Row(Modifier.align(Alignment.TopEnd).offset(x = 6.dp, y = (-6).dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            if (mensajes > 0) {
                Box(Modifier.size(18.dp).clip(CircleShape).background(c.peligro), contentAlignment = Alignment.Center) {
                    Icon(Iconos.Burbuja, contentDescription = null, tint = Color.White, modifier = Modifier.size(9.dp))
                }
            }
            if (hecho) {
                Box(Modifier.size(16.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
                    Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(10.dp))
                }
            }
        }
    }
}

// ── El cuerpo del día ──

@Composable
private fun CuerpoDia(
    motor: ModeloEntreno,
    v: VistaEntreno,
    preguntador: Preguntador,
    alAbrir: (String) -> Unit,
    alCompletarDia: (ModeloEntreno.DiaCompletado) -> Unit,
    alCerrarDia: () -> Unit,
) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    var trabajando by remember { mutableStateOf(false) }
    val banner = motor.banner
    // «Empezar entrenamiento» y el reloj van en la tarjeta principal, antes de los carteles (U3, auditoría del 10/11).
    if (banner.cambian > 0) {
        AvisoTenido(
            Iconos.Tendencia,
            buildAnnotatedString {
                append("Esta semana ")
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                    append(if (banner.cambian == 1) "1 ejercicio cambia" else "${banner.cambian} ejercicios cambian")
                }
                append(" carga o volumen. Mirá el detalle al abrir cada uno.")
            },
            modifier = Modifier.testTag("banner-progresion"),
        )
    } else if (banner.calibracion) {
        AvisoTenido(
            Iconos.Mira,
            AnnotatedString("Semana de calibración. Llevá cada serie al fallo y encontrá tu peso real. Las reps son una guía, si te salen más o menos está perfecto."),
            modifier = Modifier.testTag("banner-calibracion"),
        )
    }

    // F1 (auditoría 10/11): sin respuesta del servidor, las series se pintan con lo guardado en el teléfono.
    val sinConfirmar by motor.seriesSinConfirmar.collectAsStateWithLifecycle()
    if (sinConfirmar) {
        AvisoTenido(
            Iconos.SinNube,
            AnnotatedString("Sin conexión. Ves las series guardadas en este teléfono."),
            modifier = Modifier.testTag("aviso-series-guardadas"),
        )
    }

    var primero = 1
    for (b in motor.bloques) {
        BloqueEjercicios(motor, v, b, primero, preguntador, alAbrir, alCompletarDia)
        primero += b.ejercicios.size
    }

    if (motor.todoHecho) TarjetaCierre(motor, v, alCerrarDia) else ResumenSesion(motor, alCerrarDia)

    if (motor.puedeAvanzar) {
        // "Pasar a Semana N" con la confirmación de la web (cambia si el día está incompleto). Si no salió, "Recargar".
        BotonConIcono(
            Bonito.boton(motor.botonAvanzar),
            Iconos.FlechaDerecha,
            principal = false,
            iconoAlFinal = true,
            tono = c.marcaTexto,
            cargando = trabajando,
            modifier = Modifier.testTag("avanzar-semana"),
            alTocar = {
                alcance.launch {
                    val p = motor.preguntaAvanzar ?: return@launch
                    if (!preguntador.preguntar(p)) return@launch
                    trabajando = true
                    try {
                        val r = motor.avanzarSemana()
                        if (r is ModeloEntreno.ResultadoAvance.Error && preguntador.preguntar(r.pregunta) && r.pregunta.confirmar == "Recargar") {
                            motor.recargar()
                        }
                    } finally {
                        trabajando = false
                    }
                }
            },
        )
    } else if (motor.puedeEmpezarBloque) {
        // ENT-15
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            BotonConIcono(
                Bonito.boton(Bonito.sinEmoji(SemanaEntreno.BOTON_BLOQUE_NUEVO)),
                Iconos.Chispas,
                cargando = trabajando,
                modifier = Modifier.testTag("empezar-bloque"),
                alTocar = {
                    alcance.launch {
                        if (!preguntador.preguntar(SemanaEntreno.preguntaBloqueNuevo)) return@launch
                        trabajando = true
                        try {
                            val r = motor.empezarBloqueNuevo()
                            if (r is ModeloEntreno.ResultadoAvance.Error && preguntador.preguntar(r.pregunta) && r.pregunta.confirmar == "Recargar") {
                                motor.recargar()
                            }
                        } finally {
                            trabajando = false
                        }
                    }
                },
            )
            Text(SemanaEntreno.DETALLE_BLOQUE_NUEVO, style = Letras.caption.copy(fontSize = 13.sp), color = c.textoSecundario, textAlign = TextAlign.Center)
        }
    }
}

/** Dentro de la tarjeta principal: "Empezar entrenamiento", la sesión en curso con su tiempo, o "Sin cerrar" con más de 6 h (SES-03). */
@Composable
private fun Cronometro(motor: ModeloEntreno, cronometro: TiempoEntreno.Cronometro?, alCerrarDia: () -> Unit) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val haptico = LocalHapticFeedback.current
    when (cronometro) {
        TiempoEntreno.Cronometro.Empezar -> Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
            BotonAccion(
                TextosEntreno.EMPEZAR,
                icono = Iconos.Play,
                modifier = Modifier.testTag("empezar-entrenamiento"),
                alTocar = {
                    haptico.performHapticFeedback(HapticFeedbackType.Confirm)
                    alcance.launch { motor.empezar() }
                },
            )
            Text(
                "Arranca el cronómetro de la sesión. O empezá directo: corre solo con tu primera serie.",
                style = Letras.caption.copy(fontSize = 13.sp, lineHeight = 18.sp),
                color = c.textoSecundario,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        is TiempoEntreno.Cronometro.EnCurso ->
            CronometroSesion(cronometro.texto, if (cronometro.porBoton) null else "Arrancó con tu primera serie", alCerrarDia)
        TiempoEntreno.Cronometro.SinCerrar -> Column(Modifier.fillMaxWidth().testTag("sin-cerrar"), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Icon(Iconos.Reloj, contentDescription = null, tint = c.alerta, modifier = Modifier.size(20.dp))
                Text("Sin cerrar", style = MaterialTheme.typography.titleMedium, color = c.texto)
            }
            Text("Quedó abierta de antes. No te preocupes, no perdiste nada.", style = Letras.subtitulo, color = c.textoSecundario)
            BotonSecundario(
                "Empezar de nuevo",
                alTocar = { motor.reiniciarCronometro() },
                tono = c.marcaTexto,
                modifier = Modifier.testTag("empezar-de-nuevo"),
            )
        }
        null -> {}
    }
}

/** La sesión en curso: punto que late, "EN CURSO", el tiempo como número grande de la tarjeta, y "Cerrar". */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CronometroSesion(texto: String, detalle: String?, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val reducir = reducirMovimiento()
    FlowRow(
        modifier = Modifier.fillMaxWidth().testTag("cronometro"),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
                if (!reducir) {
                    val pulso = rememberInfiniteTransition(label = "pulso")
                    val f by pulso.animateFloat(0f, 1f, infiniteRepeatable(tween(1_400, easing = FastOutLinearInEasing), RepeatMode.Restart), label = "late")
                    Box(
                        Modifier
                            .size(10.dp)
                            .scale(1f + 1.2f * f)
                            .graphicsLayer { alpha = 1f - f }
                            // El anillo que late se apaga con `alpha` de la capa: el color va lleno (en oscuro, verde lleno o nada).
                            .border(2.dp, c.marcaVivo, CircleShape),
                    )
                }
                Box(Modifier.size(10.dp).clip(CircleShape).background(c.marcaVivo))
            }
            Column(Modifier.semantics(mergeDescendants = true) {}) {
                Ceja("En curso")
                Text(texto, style = Letra.heroe.copy(fontSize = 44.sp, lineHeight = 48.sp), color = c.texto, maxLines = 1, modifier = Modifier.testTag("cronometro-tiempo"))
                if (detalle != null) Text(detalle, style = Letras.caption, color = c.textoSecundario)
            }
        }
        BotonConIcono("Cerrar", Iconos.Bandera, alTocar = alCerrar, principal = false, compacto = true, modifier = Modifier.align(Alignment.CenterVertically).defaultMinSize(minHeight = 48.dp))
    }
}

/** Un bloque: "BLOQUE 1 · Espalda · 0/3" y sus ejercicios en una sola tarjeta, separados por líneas como una lista. */
@Composable
private fun BloqueEjercicios(
    motor: ModeloEntreno,
    v: VistaEntreno,
    b: ModeloEntreno.BloqueDelDia,
    primerNumero: Int,
    preguntador: Preguntador,
    alAbrir: (String) -> Unit,
    alCompletarDia: (ModeloEntreno.DiaCompletado) -> Unit,
) {
    val c = MyPump.colores
    val total = b.ejercicios.size
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.s), modifier = Modifier.testTag("bloque-${b.indice}")) {
        Column(Modifier.padding(horizontal = 4.dp).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Ceja("Bloque ${b.indice}")
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Text(
                    if (b.nombre.isEmpty()) "Bloque ${b.indice}" else Bonito.enOracion(b.nombre),
                    style = Letras.titulo3,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                Text(
                    "${b.hechos}/$total",
                    style = Letras.subtitulo.copy(fontWeight = FontWeight.Medium).merge(Letras.cifras),
                    color = if (b.hechos == total) c.marcaTexto else c.textoSecundario,
                )
            }
        }
        Column(Modifier.fillMaxWidth().superficieTarjeta()) {
            b.ejercicios.forEachIndexed { j, e ->
                // Con la clave, al cambiar de día el ejercicio de esa posición es otro: sin ella heredaba la animación del que
                // estaba abierto y el del día nuevo se veía abierto mientras se cerraba solo.
                key(e.id) {
                    // Tocar un ejercicio lo abre ahí mismo, como la card de la web (Mati, 15-oct); la página del ejercicio
                    // queda para la técnica y los comentarios ("Técnica y notas").
                    val abierto = v.dia.expandido == e.id
                    val aLaVista = remember(e.id) { BringIntoViewRequester() }
                    var tamano by remember(e.id) { mutableStateOf(IntSize.Zero) }
                    val barra = with(LocalDensity.current) { LocalRellenoInferior.current.toPx() }
                    // Al abrirse (tocado, o el siguiente cuando se completa uno) la lista baja hasta él: abierto abajo de todo
                    // quedaba fuera de la pantalla. Si entra entero no se mueve; si no, queda arriba la fila con su nombre. Lo
                    // de abajo cuenta la barra de pestañas, que flota encima: si no, «Terminé este ejercicio» quedaba tapado.
                    LaunchedEffect(abierto) {
                        if (abierto) {
                            delay(320)   // lo que tarda en abrirse
                            aLaVista.bringIntoView(Rect(0f, 0f, tamano.width.toFloat(), tamano.height + barra))
                        }
                    }
                    Column(Modifier.onSizeChanged { tamano = it }.bringIntoViewRequester(aLaVista)) {
                        FilaEjercicio(motor, v, e, primerNumero + j)
                        AnimatedVisibility(visible = abierto, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                            EjercicioEnLista(motor, v, e.id, preguntador, alAbrir, alCompletarDia)
                        }
                    }
                }
                if (j < total - 1) Separador(sangria = 90.dp)
            }
        }
    }
}

/**
 * La card cerrada de un ejercicio (ENT-10): miniatura con su número o estado, sustitución (fijada o solo hoy), "Manual",
 * comentarios sin leer, la pauta de la semana en chips, puntos por serie, y la última vez y el récord (o "Primera vez").
 * TalkBack lee "Ejercicio n: nombre" y, como valor, todo eso (el `accessibilityValue` de iOS).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilaEjercicio(motor: ModeloEntreno, v: VistaEntreno, ejercicio: Ejercicio, numero: Int) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val lugar = ejercicio.id
    val ef = motor.efectivo(ejercicio)
    val pauta = Progresiones.pauta(ef.ejercicio, motor.semana)
    val nombre = NombreEjercicio(ef.ejercicio.nombre)
    val estado = v.dia.estado(lugar)
    val series = v.dia.ejercicios[lugar]?.series ?: emptyList()
    val hechas = series.count { it.confirmada }
    val manual = estado == "completo_sin_datos" && v.dia.meta[lugar]?.manual == true
    val mensajes = v.comentarios.sinLeer(lugar)
    val tipo = ef.ejercicio.tipo
    // La cinta, la bici o el elíptico también con `tipo: "calentamiento"` o sin tipo (reporte del 4-nov).
    val cardio = ReglasEjercicio.esCardio(ef.ejercicio)
    val porTiempo = cardio || pauta.series == null
    val descanso = v.dia.descanso(lugar)
    val ahora = remember(v) { java.time.Instant.now() }
    // Lo que va por tiempo no tiene última vez ni récord: unas cargas viejas en su clave (la cinta registrada como serie)
    // mostraban «Última: 60 kg × 10» en la cinta.
    val ultima = if (porTiempo) null else v.dia.ultimaVez(lugar, ahora)
    val record = if (porTiempo) null else v.dia.record(lugar)
    val buscando = lugar in v.cargandoHistorial
    val valor = CardAccesible.valor(
        estado, hechas, series.size, ef.sustituido, ef.fijado, manual, mensajes, tipo, pauta, descanso, ultima, record, buscando,
        cardio = cardio,
    )
    // La flecha apunta abajo con el ejercicio abierto en la lista: tocar la fila lo abre y lo cierra ahí mismo.
    val giro by animateFloatAsState(if (v.dia.expandido == lugar) 90f else 0f, label = "flecha-$lugar")
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClickLabel = if (v.dia.expandido == lugar) "Cerrar" else "Abrir acá") { alcance.launch { motor.tocarCard(lugar) } }
            .padding(horizontal = Espacio.m, vertical = 14.dp)
            .semantics {
                contentDescription = "Ejercicio $numero: ${ef.ejercicio.nombre}"
                stateDescription = valor
            }
            .testTag("ejercicio-$lugar"),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Box {
                Miniatura(ef.ejercicio.imagenes?.concentric ?: ef.ejercicio.imagenes?.eccentric, tipo, 60.dp)
                MarcaNumero(numero, estado, Modifier.offset(x = (-7).dp, y = (-7).dp))
            }
            if (series.size > 1 && !cardio) PuntosSeries(series.size, hechas)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(nombre.principal, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), color = c.texto)
            nombre.detalle?.let { Text(it, style = Letras.subtitulo, color = c.textoSecundario) }
            FlowRow(
                modifier = Modifier.padding(top = 5.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (ef.sustituido) InsigniaSustitucion(ef.fijado, Modifier.testTag("insignia-sustitucion"))
                if (manual) ChipDato("Manual", icono = Iconos.Mano)
                if (mensajes > 0) ChipDato("$mensajes", icono = Iconos.Burbuja, tono = c.peligro)
                val calentamiento = ReglasEjercicio.tipoNormalizado(tipo) == "calentamiento"
                if (calentamiento || cardio) ChipDato(if (calentamiento) "Calent." else "Cardio", icono = Iconos.Fuego, tono = c.alerta)
                // Sin duración en el plan no va el «—»: el tiempo ya está en el nombre («10 min»).
                if (porTiempo) pauta.reps?.let { ChipDato(it) } else ChipDato("${pauta.series} × ${pauta.reps ?: "—"}")
                ChipDato(TiempoEntreno.fmtTiempo(descanso.toDouble()), icono = Iconos.Temporizador)
            }
            // El cardio y lo que va por tiempo no tienen "última vez" que buscar.
            Historial(ultima?.let { it.valor to it.cuando }, record, porTiempo, buscando, Modifier.padding(top = 4.dp))
        }
        Icon(
            Iconos.Chevron,
            contentDescription = null,
            tint = c.textoTerciario,
            modifier = Modifier.align(Alignment.CenterVertically).size(20.dp).graphicsLayer { rotationZ = giro },
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Historial(ultima: Pair<String, String>?, record: String?, porTiempo: Boolean, buscando: Boolean, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    when {
        ultima != null || record != null -> FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(Espacio.xs), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (ultima != null) {
                // En gris secundario y el valor en el color del texto: en terciario no se leía en el gimnasio (como iOS,
                // auditoría de accesibilidad del 15-oct).
                Text(
                    buildAnnotatedString {
                        append("Última: ")
                        withStyle(SpanStyle(color = c.texto)) { append(Bonito.partir(ultima.first).first) }
                        append(" · ${ultima.second}")
                    },
                    style = Letras.caption,
                    color = c.textoSecundario,
                )
            }
            if (record != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Iconos.Trofeo, contentDescription = null, tint = c.record, modifier = Modifier.size(12.dp))
                    Text(Bonito.partir(record).first, style = Letras.caption.copy(fontWeight = FontWeight.SemiBold), color = c.record)
                }
            }
        }
        porTiempo -> {}
        buscando -> Text("Buscando tu última vez…", style = Letras.caption, color = c.textoSecundario, modifier = modifier)
        else -> Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(Iconos.Chispas, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(12.dp))
            Text("Primera vez con este ejercicio", style = Letras.caption, color = c.textoSecundario)
        }
    }
}

/** El número del ejercicio en la esquina de la miniatura; tilde de marca cuando está completo. */
@Composable
private fun MarcaNumero(numero: Int, estado: String, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val fondo = if (estado == "completo") c.marca else c.tarjeta
    Box(
        modifier = modifier
            .size(22.dp)
            .clip(CircleShape)
            .background(fondo)
            .border(1.dp, c.borde, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        when (estado) {
            "completo" -> Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(13.dp))
            "completo_sin_datos" -> Icon(Iconos.Tilde, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(13.dp))
            "saltado" -> Icon(Iconos.Menos, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(13.dp))
            else -> Text("$numero", style = Letras.caption2.copy(fontWeight = FontWeight.Bold).merge(Letras.cifras), color = c.texto)
        }
    }
}

/** Todo hecho o el día cerrado: "Sesión completa" o "Día cerrado", cuántos quedaron listos, el resumen y, si falta, cerrarla. */
@Composable
private fun TarjetaCierre(motor: ModeloEntreno, v: VistaEntreno, alCerrarDia: () -> Unit) {
    val c = MyPump.colores
    val r = motor.resumen
    val finalizado = v.dia.diaFinalizado
    Tarjeta(Modifier.testTag("tarjeta-cierre"), espaciado = Espacio.m) {
        Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Icon(if (finalizado) Iconos.Verificado else Iconos.Chispas, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(14.dp))
                Ceja(if (finalizado) "Día cerrado" else "Sesión completa")
            }
            Text("${motor.hechos}/${motor.totalEjercicios} ejercicios listos", style = Letras.titulo3)
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            CeldaResumen("Series", "${r.series}", Modifier.weight(1f))
            SeparadorVertical()
            CeldaResumen("Volumen", "${Js.texto(r.volumenRedondeado)} kg", Modifier.weight(1f))
            SeparadorVertical()
            CeldaResumen("Duración", motor.minutos?.let { "$it min" } ?: "—", Modifier.weight(1f))
        }
        if (finalizado) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Espacio.xs, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Iconos.NubeGuardada, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                Text("Tu sesión de hoy quedó guardada.", style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold))
            }
        } else {
            BotonConIcono("Terminar el entrenamiento de hoy", Iconos.Bandera, alTocar = alCerrarDia, modifier = Modifier.testTag("cerrar-sesion"))
        }
    }
}

/** El pie mientras se entrena: cerrar el día (habilitado con la sesión iniciada). Hechos, tiempo y lo que resta van en la tarjeta principal. */
@Composable
private fun ResumenSesion(motor: ModeloEntreno, alCerrarDia: () -> Unit) {
    Box(Modifier.fillMaxWidth().testTag("resumen-sesion")) {
        BotonConIcono(
            "Terminar el entrenamiento de hoy",
            Iconos.Bandera,
            alTocar = alCerrarDia,
            principal = false,
            habilitado = motor.cierreHabilitado,
            modifier = Modifier.testTag("cerrar-sesion"),
        )
    }
}

/** ENT-16 */
@Composable
private fun DiaVacio() {
    val c = MyPump.colores
    Column(
        Modifier.fillMaxWidth().padding(vertical = Espacio.l).testTag("dia-vacio"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Icon(Iconos.Pesa, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(44.dp))
        Text("Día sin ejercicios", style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Text(TextosEntreno.DIA_VACIO, style = Letras.subtitulo, color = c.textoSecundario, textAlign = TextAlign.Center)
    }
}
