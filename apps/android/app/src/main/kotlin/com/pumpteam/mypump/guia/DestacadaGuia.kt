package com.pumpteam.mypump.guia

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalAccessibilityManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.acceso.Onboarding
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.vidrio
import com.pumpteam.mypump.entreno.reducirMovimiento
import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.raiz.Navegacion
import com.pumpteam.mypump.raiz.Pestana
import com.pumpteam.mypump.reglas.ReglasGuia
import com.pumpteam.mypump.reglas.ReglasNovedad
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// «Tu guía» bien destacada (Mati, 4/11 a la tarde; ~/Developer/nativa-evidencia/guia/GUIA_DESTACADA.md): para el cliente
// nuevo la guía es lo primero. La bienvenida de la primera vez, la tarjeta verde que manda en Entreno (con «Ocultar» y
// «Deshacer») hasta ver todo, y después la compacta de siempre ([TarjetaGuia]).

/**
 * El fondo de la tarjeta destacada: el verde de la marca un poco más hondo (el `marcaTexto` claro). El #1D9330 del logo con
 * texto blanco da 4,0:1 y la etiqueta y la línea de avance son letra chica: este da 5,5:1. El mismo en claro y en oscuro
 * (sobre negro se ve igual de protagonista, y el blanco encima sigue leyéndose).
 */
val VerdeGuia = Color(0xFF157A28)

/**
 * La tarjeta verde arriba de Entreno mientras falta ver algo: «EMPEZÁ POR ACÁ», el título, el avance, la barra blanca, el
 * botón blanco y, arriba a la derecha, «Ocultar» (48 dp de toque). Tocar la tarjeta también abre la guía.
 */
@Composable
fun TarjetaGuiaDestacada(
    resumen: ResumenGuia,
    pulso: Boolean,
    alAbrir: () -> Unit,
    alOcultar: () -> Unit,
    modifier: Modifier = Modifier,
    /** Con novedad (2.2.0): «NOVEDAD EN TU GUÍA», el mismo verde, y el avance de los nuevos solamente. */
    novedad: ReglasNovedad.Tarjeta? = null,
) {
    val texto = novedad?.let(ReglasNovedad::textoTarjeta) ?: ReglasGuia.textoDestacada(resumen)
    val boton = if (novedad != null) ReglasNovedad.BOTON else ReglasGuia.botonDestacada(resumen)
    val etiquetaArriba = if (novedad != null) "NOVEDAD EN TU GUÍA" else "EMPEZÁ POR ACÁ"
    val fraccion = novedad?.fraccion ?: ReglasGuia.fraccion(resumen)
    val forma = RoundedCornerShape(Radio.tarjeta)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(forma)
            .background(VerdeGuia)
            // TalkBack lee la tarjeta entera de una (la etiqueta, el título y el avance); «Ocultar» y el botón, aparte.
            .semantics { contentDescription = (if (novedad != null) "Novedad en tu guía. " else "Empezá por acá. Tu guía. ") + texto }
            .clickable(onClickLabel = "Abrir tu guía", role = Role.Button, onClick = alAbrir)
            .testTag("tarjeta-guia")
            .padding(start = Espacio.m + 2.dp, end = Espacio.xs, top = Espacio.xs, bottom = Espacio.m + 2.dp),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                etiquetaArriba,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.08.em,
                color = Color.White,
                modifier = Modifier.weight(1f).padding(top = Espacio.xs).testTag(if (novedad != null) "guia-novedad" else "guia-empeza-por-aca").clearAndSetSemantics {},
            )
            TextButton(
                onClick = alOcultar,
                modifier = Modifier
                    .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
                    .semantics { contentDescription = "Ocultar tu guía de Entreno" }
                    .testTag("tarjeta-guia-ocultar"),
                colors = ButtonDefaults.textButtonColors(contentColor = Color.White.copy(alpha = 0.92f)),
            ) {
                Text("Ocultar", style = MaterialTheme.typography.labelLarge)
            }
        }
        Row(
            modifier = Modifier.padding(end = Espacio.s),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.s + 4.dp),
        ) {
            IconoPlayConPulso(pulso)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Tu guía", style = MaterialTheme.typography.titleLarge, color = Color.White)
                Text(texto, style = MaterialTheme.typography.bodyMedium, color = Color.White, modifier = Modifier.testTag("tarjeta-guia-texto"))
            }
        }
        LinearProgressIndicator(
            progress = { fraccion.coerceIn(0f, 1f) },
            modifier = Modifier.padding(end = Espacio.s).fillMaxWidth().height(6.dp).clip(CircleShape).clearAndSetSemantics {},
            color = Color.White,
            trackColor = Color.White.copy(alpha = 0.28f),
            strokeCap = StrokeCap.Round,
            gapSize = 0.dp,
            drawStopIndicator = {},
        )
        Button(
            onClick = alAbrir,
            modifier = Modifier.padding(end = Espacio.s).fillMaxWidth().defaultMinSize(minHeight = 52.dp).testTag("tarjeta-guia-ver"),
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = VerdeGuia),
            elevation = null,
        ) {
            Text(boton, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        }
    }
}

/**
 * El play en un círculo blanco. Con [pulso] (la primera sesión, sin «Quitar animaciones»), un brillo suave alrededor que late
 * tres veces y se queda quieto: llama la atención sin molestar.
 */
@Composable
private fun IconoPlayConPulso(pulso: Boolean) {
    val reducir = reducirMovimiento()
    val anillo = remember { Animatable(0f) }
    LaunchedEffect(pulso, reducir) {
        if (!pulso || reducir) return@LaunchedEffect
        delay(600)
        repeat(3) {
            anillo.snapTo(0f)
            anillo.animateTo(1f, tween(1_400, easing = FastOutSlowInEasing))
            delay(250)
        }
        anillo.snapTo(0f)
    }
    Box(Modifier.size(52.dp), contentAlignment = Alignment.Center) {
        val t = anillo.value
        if (t > 0f) {
            Box(
                Modifier
                    .size(52.dp)
                    .graphicsLayer {
                        val e = 0.85f + 0.35f * t
                        scaleX = e
                        scaleY = e
                        alpha = (1f - t) * 0.55f
                    }
                    .clip(CircleShape)
                    .background(Color.White),
            )
        }
        Box(Modifier.size(44.dp).clip(CircleShape).background(Color.White), contentAlignment = Alignment.Center) {
            Icon(Iconos.Play, contentDescription = null, tint = VerdeGuia, modifier = Modifier.size(24.dp))
        }
    }
}

/**
 * El aviso de «Ocultar»: «La encontrás en Mis datos» con «Deshacer», la pastilla de vidrio de la app (como AvisoGuardado),
 * abajo. Dura 6 s, más si TalkBack lo pide. Lo dispara [Navegacion.avisoGuiaOculta].
 */
@Composable
fun AvisoGuiaOculta(navegacion: Navegacion, modelo: ModeloApp, modifier: Modifier = Modifier, separacion: androidx.compose.ui.unit.Dp = 0.dp) {
    val vez = navegacion.avisoGuiaOculta
    var visible by remember { mutableStateOf(false) }
    val accesibilidad = LocalAccessibilityManager.current
    LaunchedEffect(vez) {
        if (vez == 0) return@LaunchedEffect
        visible = true
        delay(accesibilidad?.calculateRecommendedTimeoutMillis(6_000, containsIcons = false, containsText = true, containsControls = true) ?: 6_000)
        visible = false
    }
    val c = MyPump.colores
    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = slideInVertically { it } + fadeIn(),
        exit = slideOutVertically { it } + fadeOut(),
    ) {
        // [separacion] va adentro: con el aviso oculto no deja un hueco abajo.
        Box(Modifier.fillMaxWidth().padding(horizontal = Espacio.m).padding(bottom = separacion), contentAlignment = Alignment.Center) {
            Row(
                Modifier
                    .widthIn(max = 520.dp)
                    .vidrio(CircleShape, elevacion = 12.dp)
                    .border(1.dp, c.borde, CircleShape)
                    .semantics { liveRegion = LiveRegionMode.Polite }
                    .testTag("aviso-guia-oculta")
                    .padding(start = 18.dp, end = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    "La encontrás en Mis datos",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = c.texto,
                    modifier = Modifier.weight(1f, fill = false).padding(vertical = 12.dp),
                )
                TextButton(
                    onClick = {
                        modelo.guia.value?.ocultarDeEntreno(false)
                        visible = false
                    },
                    modifier = Modifier.defaultMinSize(minWidth = 48.dp, minHeight = 48.dp).testTag("aviso-guia-deshacer"),
                    colors = ButtonDefaults.textButtonColors(contentColor = c.marcaTexto),
                ) {
                    Text("Deshacer", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

/**
 * La bienvenida de la primera vez ([ReglasGuia.mostrarBienvenida]): una hoja grande con el play, «Hola Tomás», el texto de
 * Mati, «Ver mi guía» y «Más tarde». Sale después de la hoja de permisos (si está pendiente, espera a que termine) y se marca
 * vista al aparecer, así nunca sale dos veces. No llama a `entregas_app_get`: usa el resumen y la caché; el get sale al abrir
 * la guía.
 */
@Composable
fun BienvenidaGuiaDe(modelo: ModeloApp, navegacion: Navegacion) {
    val fase by modelo.fase.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val g = modelo.guia.collectAsStateWithLifecycle().value
    val resumen = g?.resumen?.collectAsStateWithLifecycle()?.value
    val oculta = g?.ocultaAMano?.collectAsStateWithLifecycle()?.value ?: false
    val vista = g?.bienvenidaVista?.collectAsStateWithLifecycle()?.value
    val info by modelo.info.collectAsStateWithLifecycle()
    var mostrando by rememberSaveable { mutableStateOf(false) }
    // Lo que se ve queda fijo mientras la hoja está abierta (el resumen puede cambiar por debajo).
    var fijo by remember { mutableStateOf<Pair<String, String>?>(null) }

    // Solo estando en Entreno, como iOS (revisión del 4-nov, hallazgo 18): es donde está la tarjeta que la abre.
    val enEntreno = navegacion.pestana == Pestana.ENTRENO
    val candidata = fase == ModeloApp.Fase.LISTO && vista == false && enEntreno &&
        ReglasGuia.mostrarBienvenida(resumen, oculta, yaVista = false, esDemo = esDemo || modelo.token == null)
    LaunchedEffect(candidata) {
        if (!candidata || mostrando) return@LaunchedEffect
        // Primero la hoja de permisos de la primera vez (GEN-06), si le falta: no se apilan dos hojas.
        delay(1_500)
        while (Onboarding.pendiente(modelo.preferencias)) delay(400)
        delay(500)
        val m = modelo.guia.value ?: return@LaunchedEffect
        val r = m.resumen.value
        if (m.bienvenidaVista.value != false || !ReglasGuia.mostrarBienvenida(r, m.ocultaAMano.value, false, modelo.esDemo.value)) return@LaunchedEffect
        if (navegacion.guia || navegacion.guiaEnMisDatos || navegacion.pestana != Pestana.ENTRENO) return@LaunchedEffect
        m.marcarBienvenidaVista()
        mostrando = true
    }
    if (!mostrando) return
    val r = resumen
    val textos = fijo ?: r?.let { ReglasGuia.saludoBienvenida(g?.guia?.value?.nombrePila, info?.nombre) to ReglasGuia.textoBienvenida(it) }?.also { fijo = it }
    if (textos == null) {
        mostrando = false
        return
    }
    BienvenidaGuia(
        saludo = textos.first,
        texto = textos.second,
        alVer = {
            mostrando = false
            navegacion.pestana = Pestana.ENTRENO
            navegacion.guia = true
        },
        alCerrar = { mostrando = false },
    )
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun BienvenidaGuia(saludo: String, texto: String, alVer: () -> Unit, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcance = rememberCoroutineScope()
    fun cerrarY(accion: () -> Unit) {
        alcance.launch { hoja.hide() }.invokeOnCompletion { accion() }
    }
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("guia-bienvenida"),
    ) {
        // A todo el alto; con la letra muy grande se desplaza (nada se corta) y los botones quedan al final.
        BoxWithConstraints(Modifier.fillMaxSize().navigationBarsPadding()) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .heightIn(min = maxHeight)
                .padding(horizontal = Espacio.l, vertical = Espacio.m),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Spacer(Modifier.height(Espacio.l))
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(96.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
                Icon(Iconos.Play, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(48.dp))
            }
            Spacer(Modifier.height(Espacio.l))
            Text(
                saludo,
                style = MaterialTheme.typography.headlineMedium,
                color = c.texto,
                textAlign = TextAlign.Center,
                modifier = Modifier.semantics { heading() }.testTag("guia-bienvenida-saludo"),
            )
            Spacer(Modifier.height(Espacio.s))
            Text(
                texto,
                style = MaterialTheme.typography.bodyLarge,
                color = c.textoSecundario,
                textAlign = TextAlign.Center,
                modifier = Modifier.widthIn(max = 460.dp).testTag("guia-bienvenida-texto"),
            )
            }
            Column(Modifier.padding(top = Espacio.xl).widthIn(max = 460.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                BotonMarca("Ver mi guía", alTocar = { cerrarY(alVer) }, modifier = Modifier.testTag("guia-bienvenida-ver"))
                Spacer(Modifier.height(Espacio.xs))
                TextButton(
                    onClick = { cerrarY(alCerrar) },
                    modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).testTag("guia-bienvenida-despues"),
                    colors = ButtonDefaults.textButtonColors(contentColor = c.marcaTexto),
                ) {
                    Text("Más tarde", style = MaterialTheme.typography.titleSmall)
                }
            }
        }
        }
    }
}
