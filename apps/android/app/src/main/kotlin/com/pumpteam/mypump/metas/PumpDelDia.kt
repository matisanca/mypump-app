package com.pumpteam.mypump.metas

import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.semantics.paneTitle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.activity.compose.BackHandler
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.reducirMovimiento
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.reglas.PumpDelDia
import com.pumpteam.mypump.reglas.RitmoPeso
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlinx.coroutines.delay

// «Pump del día» (2.3.0), gemelo de PumpDelDiaVistas.swift y TorsoLleno.swift: el torso del logo que se llena con los
// pasos de hoy, la semana en torsitos y «Pump lleno» una vez por día. Todo detrás de la palanca `metas_pasos`.

// ── El torso ──

/** Los trazos del logo (`public/icons/logo.svg`) en la grilla de 512; el primero es el contorno cerrado. */
private val TRAZOS = listOf(
    "M110,195C130,165 175,145 210,150L256,178L302,150C337,145 382,165 402,195L402,250C395,270 380,280 365,282L350,282" +
        "L340,320L350,360L332,405L296,432L256,442L216,432L180,405L162,360L172,320L162,282L147,282C132,280 117,270 110,250Z",
    "M210,195C195,215 195,245 220,265L250,275",
    "M302,195C317,215 317,245 292,265L262,275",
    "M256,282L256,405",
    "M200,312L312,312",
    "M195,348L317,348",
    "M190,385L322,385",
)
private val CONTORNO: Path by lazy { PathParser().parsePathString(TRAZOS[0]).toPath() }
private val DIBUJO: List<Path> by lazy { TRAZOS.map { PathParser().parsePathString(it).toPath() } }

/**
 * El torso que se llena de verde desde la cintura, con una ola suave arriba (quieta con las animaciones apagadas). Lleno,
 * el dibujo pasa al color sobre la marca, como el ícono. [detalle] en false: solo la silueta (los torsitos de la semana).
 */
@Composable
fun TorsoLleno(fraccion: Float, lado: Dp, modifier: Modifier = Modifier, vivo: Boolean = true, detalle: Boolean = true) {
    val c = MyPump.colores
    val reducir = reducirMovimiento()
    val nivel by animateFloatAsState(fraccion.coerceIn(0f, 1f), if (reducir) tween(0) else spring(dampingRatio = 0.75f, stiffness = Spring.StiffnessLow), label = "nivel")
    val ola = vivo && !reducir && fraccion in 0.001f..0.999f
    // La ola se mueve unos segundos al aparecer o al cambiar los pasos y se queda quieta (batería).
    val faseAnim = remember { Animatable(0f) }
    LaunchedEffect(fraccion, ola) {
        if (!ola) return@LaunchedEffect
        faseAnim.snapTo(0f)
        faseAnim.animateTo((2 * PI * 2).toFloat(), tween(5600, easing = LinearEasing))
    }
    val fase = if (ola) faseAnim.value else 0f
    val gris = c.textoSecundario.copy(alpha = 0.45f)
    Canvas(modifier.size(lado).clearAndSetSemantics {}) {
        dibujarTorso(nivel, fase, if (ola) size.minDimension * 0.025f else 0f, c.campo, c.marcaVivo, c.marca, gris, c.sobreMarca, detalle)
    }
}

private fun DrawScope.dibujarTorso(
    nivel: Float, fase: Float, amplitud: Float, vacio: Color, arriba: Color, abajo: Color, trazo: Color, trazoLleno: Color, detalle: Boolean,
) {
    val alto = size.minDimension * 0.94f
    val escala = alto / 292f
    val dx = center.x - 256f * escala
    val dy = center.y - 296f * escala
    val base = center.y + alto / 2
    val y = if (nivel >= 1f) -2f else base - nivel * alto
    val olaPath = Path().apply {
        moveTo(0f, size.height)
        lineTo(0f, y)
        val pasos = 24
        for (i in 0..pasos) {
            val x = size.width * i / pasos
            lineTo(x, y + amplitud * sin(i.toFloat() / pasos * 2 * PI.toFloat() + fase))
        }
        lineTo(size.width, size.height)
        close()
    }
    val grosor = max(1.4f * density, size.minDimension * 0.028f) / escala
    translate(dx, dy) {
        scale(escala, escala, pivot = Offset.Zero) {
            drawPath(CONTORNO, vacio)
        }
    }
    // El verde, recortado a la silueta (la ola se mide en píxeles de la vista).
    val silueta = Path().apply { addPath(CONTORNO); transform(androidx.compose.ui.graphics.Matrix().apply { translate(dx, dy); scale(escala, escala) }) }
    clipPath(silueta) { drawPath(olaPath, Brush.verticalGradient(listOf(arriba, abajo), startY = y, endY = base)) }
    if (detalle) {
        translate(dx, dy) {
            scale(escala, escala, pivot = Offset.Zero) {
                val s = Stroke(width = grosor, cap = StrokeCap.Round, join = StrokeJoin.Round)
                DIBUJO.forEach { drawPath(it, trazo, style = s) }
            }
        }
        clipRect(top = y) {
            translate(dx, dy) {
                scale(escala, escala, pivot = Offset.Zero) {
                    val s = Stroke(width = grosor, cap = StrokeCap.Round, join = StrokeJoin.Round)
                    DIBUJO.forEach { drawPath(it, trazoLleno, style = s) }
                }
            }
        }
    }
}

// ── La tarjeta ──

/** El estado del «Pump del día» para la pantalla, o null (palanca apagada, sin meta o sin cuenta). */
@Composable
fun estadoPump(modelo: ModeloApp): Pair<PumpDelDia.Vista, Boolean>? {
    val palanca by modelo.palanca.collectAsStateWithLifecycle()
    val dieta by modelo.dieta.collectAsStateWithLifecycle()
    val salud by modelo.salud.collectAsStateWithLifecycle()
    val filas = salud?.salud?.collectAsStateWithLifecycle()?.value
    val conectado = salud?.conectado?.collectAsStateWithLifecycle()?.value
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    // La demo con historial trae su meta y sus pasos inventados; sin historial, nada (como antes).
    val demo by modelo.demoHistorial.collectAsStateWithLifecycle()
    if (esDemo && demo == null) return null
    // Lo leído arriba es para recomponer cuando cambie; la cuenta la hace el modelo.
    @Suppress("UNUSED_VARIABLE") val dependencias = listOf(palanca, dieta, filas, conectado, demo)
    return modelo.pumpDelDia()
}

/** Lo que va en Entreno (y en Salud): la tarjeta solo con la palanca, una meta de pasos y una cuenta. */
@Composable
fun PumpDelDiaDe(modelo: ModeloApp, modifier: Modifier = Modifier, enSalud: Boolean = false) {
    val e = estadoPump(modelo) ?: return
    TarjetaPumpDelDia(e.first, e.second, modifier, enSalud)
}

@Composable
fun TarjetaPumpDelDia(vista: PumpDelDia.Vista, conectado: Boolean, modifier: Modifier = Modifier, enSalud: Boolean = false) {
    val c = MyPump.colores
    val navegacion = LocalNavegacion.current
    val tocable = conectado && !enSalud
    val pasados = vista.semana.filter { it.estado != PumpDelDia.EstadoDia.FUTURO }
    val hechos = pasados.count { it.estado == PumpDelDia.EstadoDia.CUMPLIDO }
    val leido = PumpDelDia.accesible(vista) + " Esta semana, $hechos de ${pasados.size} días con la meta."
        // En Salud la línea de la meta y el promedio también se lee (la tarjeta junta todo en una sola lectura).
        .plus(if (enSalud) " " + PumpDelDia.lineaSalud(vista.meta, vista.promedio7) + "." else "")
    Column(
        modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .clip(RoundedCornerShape(Radio.tarjeta))
            .then(if (tocable) Modifier.clickable { navegacion?.irAMiSalud(com.pumpteam.mypump.reglas.MiSalud.Bloque.RECUPERACION) } else Modifier)
            .padding(Espacio.m)
            .then(if (conectado) Modifier.clearAndSetSemantics { contentDescription = leido } else Modifier)
            .testTag("pump-del-dia"),
        verticalArrangement = Arrangement.spacedBy(Espacio.m),
    ) {
        // Con letra muy grande, el torso arriba y el texto abajo (FlowRow lo baja solo).
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.m), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
            TorsoLleno(if (conectado) vista.fraccion.toFloat() else 0f, 76.dp, Modifier.align(Alignment.CenterVertically))
            Column(Modifier.align(Alignment.CenterVertically).widthIn(min = 180.dp).weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (conectado) Numeros(vista) else SinSalud(vista, enSalud)
            }
        }
        if (conectado) {
            SemanaPump(vista.semana, vista.fraccion.toFloat())
            if (enSalud) {
                Text(PumpDelDia.lineaSalud(vista.meta, vista.promedio7), style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
            }
        }
    }
}

@Composable
private fun Ceja(texto: String) {
    Text(
        texto.uppercase(), style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 0.8.sp, fontWeight = FontWeight.SemiBold),
        color = MyPump.colores.textoSecundario, maxLines = 1,
    )
}

@Composable
private fun Numeros(vista: PumpDelDia.Vista) {
    val c = MyPump.colores
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) { Ceja(PumpDelDia.NOMBRE) }
        PumpDelDia.racha(vista.racha)?.let {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("pump-racha")) {
                Icon(Iconos.Fuego, contentDescription = null, tint = c.alerta, modifier = Modifier.size(14.dp))
                Spacer(Modifier.size(3.dp))
                Text(it, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold), color = c.alerta, maxLines = 1)
            }
        }
    }
    FlowRow(verticalArrangement = Arrangement.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(PumpDelDia.numeroPasos(vista.pasosHoy), style = Numeros.grande, color = c.texto, maxLines = 1)
        Text(
            PumpDelDia.deMeta(vista), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
            color = c.textoSecundario, maxLines = 1, modifier = Modifier.align(Alignment.Bottom).padding(bottom = 5.dp),
        )
    }
    Text(
        PumpDelDia.estado(vista),
        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = if (vista.cumplido) FontWeight.SemiBold else FontWeight.Normal),
        color = if (vista.cumplido) c.marcaTexto else c.textoSecundario,
    )
}

@Composable
private fun SinSalud(vista: PumpDelDia.Vista, enSalud: Boolean) {
    val c = MyPump.colores
    val navegacion = LocalNavegacion.current
    Ceja(PumpDelDia.NOMBRE)
    Text(PumpDelDia.sinSalud(vista.meta), style = MaterialTheme.typography.titleMedium, color = c.texto)
    Text(PumpDelDia.CONECTAR, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
    if (!enSalud) {
        BotonSecundario(
            PumpDelDia.CONECTAR_BOTON, { navegacion?.irAMiSalud(com.pumpteam.mypump.reglas.MiSalud.Bloque.RECUPERACION) },
            Modifier.padding(top = 4.dp).testTag("pump-conectar"), compacto = true, tono = c.marcaTexto,
        )
    }
}

/** La semana de lunes a domingo en torsitos: lleno el día con la meta, a medio llenar hoy, vacío el que no llegó. */
@Composable
fun SemanaPump(semana: List<PumpDelDia.Dia>, fraccionHoy: Float, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val hoy = FechaLocal.hoy()
    Row(modifier.fillMaxWidth().clearAndSetSemantics {}) {
        semana.forEach { d ->
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val f = when (d.estado) {
                    PumpDelDia.EstadoDia.CUMPLIDO -> 1f
                    PumpDelDia.EstadoDia.HOY -> fraccionHoy
                    else -> 0f
                }
                val alfa = when (d.estado) {
                    PumpDelDia.EstadoDia.FUTURO -> 0.35f
                    PumpDelDia.EstadoDia.SIN_DATO -> 0.6f
                    else -> 1f
                }
                Box(Modifier.size(26.dp)) {
                    TorsoLleno(f, 26.dp, Modifier.alpha(alfa), vivo = false, detalle = false)
                }
                val esHoy = d.fecha == hoy
                Text(
                    d.inicial, style = MaterialTheme.typography.labelSmall.copy(fontWeight = if (esHoy) FontWeight.Bold else FontWeight.Medium),
                    color = if (esHoy) c.marcaTexto else c.textoSecundario, maxLines = 1,
                )
            }
        }
    }
}

// ── Ritmo de peso ──

/** El ritmo que buscamos, debajo de la media de 7 días. Sin juicios: la tendencia tal cual y, si va al ritmo, se dice. */
@Composable
fun RitmoPesoLinea(modelo: ModeloApp?, serie: List<PesoCorporal.Punto>, modifier: Modifier = Modifier) {
    val m = modelo ?: return
    val palanca by m.palanca.collectAsStateWithLifecycle()
    val dieta by m.dieta.collectAsStateWithLifecycle()
    val demo by m.demoHistorial.collectAsStateWithLifecycle()
    @Suppress("UNUSED_VARIABLE") val dependencias = listOf(palanca, dieta, demo)
    val ritmo = m.metas()?.ritmoKgSemana ?: return
    RitmoPesoCaja(RitmoPeso.resumen(ritmo, serie, FechaLocal.hoy()), modifier)
}

@Composable
fun RitmoPesoCaja(r: RitmoPeso.Resumen, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Column(
        modifier
            .fillMaxWidth()
            .background(c.marcaSuave, RoundedCornerShape(Radio.control))
            .padding(12.dp)
            .semantics(mergeDescendants = true) {}
            .testTag("ritmo-peso"),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(r.meta, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = c.marcaTexto)
        r.tendencia?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario) }
        if (r.enRitmo) Text(RitmoPeso.EN_RITMO, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium), color = c.texto)
    }
}

// ── La celebración ──

/**
 * «Pump lleno»: el torso termina de llenarse, late como un bombeo (con hápticos del sistema, sin permiso de vibración),
 * saltan chispas verdes y doradas y aparece el día con la racha. Con las animaciones apagadas, todo quieto y un háptico.
 */
@Composable
fun CelebracionPump(vista: PumpDelDia.Vista, rachaCompartida: Boolean = false, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val reducir = reducirMovimiento()
    val vistaAndroid = LocalView.current
    var nivel by remember { mutableStateOf(if (reducir) 1f else 0.8f) }
    var bombeo by remember { mutableStateOf(reducir) }
    var textos by remember { mutableStateOf(reducir) }
    var inicioChispas by remember { mutableStateOf<Long?>(null) }
    val escala by animateFloatAsState(if (bombeo || reducir) 1f else 0.9f, spring(dampingRatio = 0.45f, stiffness = Spring.StiffnessMediumLow), label = "bombeo")
    val halo by animateFloatAsState(if (bombeo) 1f else 0f, tween(if (reducir) 0 else 450), label = "halo")
    LaunchedEffect(Unit) {
        if (reducir) {
            vistaAndroid.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
            return@LaunchedEffect
        }
        delay(250)
        nivel = 1f
        repeat(3) {
            vistaAndroid.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            delay(220)
        }
        vistaAndroid.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        bombeo = true
        inicioChispas = withFrameNanos { it }
        delay(140)
        vistaAndroid.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        delay(180)
        textos = true
    }
    Box(
        Modifier
            .fillMaxSize()
            .background(c.fondo.copy(alpha = 0.96f))
            .background(Brush.radialGradient(listOf(c.marcaVivo.copy(alpha = 0.22f * halo), Color.Transparent), radius = 1400f))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
            .testTag("pump-celebracion"),
    ) {
        Column(
            Modifier.fillMaxSize().systemBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = Espacio.l, vertical = Espacio.l),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Espacio.l),
        ) {
            Spacer(Modifier.height(Espacio.xl))
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(300.dp)) {
                Canvas(Modifier.size(300.dp)) {
                    drawCircle(Brush.radialGradient(listOf(c.marcaVivo.copy(alpha = 0.45f * halo), Color.Transparent), radius = size.minDimension / 2), radius = size.minDimension / 2)
                    if (!reducir) drawCircle(c.marcaVivo.copy(alpha = 0.6f * (1 - halo)), radius = size.minDimension * 0.38f * (0.7f + 0.65f * halo), style = Stroke(3.dp.toPx()))
                }
                TorsoLleno(nivel, 200.dp, Modifier.scale(escala))
                inicioChispas?.let { Chispas(it) }
            }
            AnimatedVisibility(textos, enter = fadeIn(tween(300)), exit = fadeOut()) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                    Text(
                        PumpDelDia.LLENO, style = Numeros.gigante.copy(fontSize = 46.sp, lineHeight = 52.sp), color = c.marcaTexto,
                        modifier = Modifier.semantics { heading(); liveRegion = LiveRegionMode.Polite },
                    )
                    Text(PumpDelDia.celebracion(vista.meta), style = MaterialTheme.typography.titleMedium, color = c.texto, textAlign = TextAlign.Center)
                    PumpDelDia.celebracionRacha(vista.racha)?.let {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Iconos.Fuego, contentDescription = null, tint = c.alerta, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.size(4.dp))
                            Text(it, style = MaterialTheme.typography.titleSmall, color = c.alerta)
                        }
                    }
                    // Logros (2.3.0): la racha quedó para que Mati la vea (solo con el permiso dado y un hito).
                    if (rachaCompartida) {
                        Text(
                            com.pumpteam.mypump.reglas.ReglasWins.RACHA_CON_PERMISO,
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                            color = c.marcaTexto, textAlign = TextAlign.Center, modifier = Modifier.testTag("pump-racha-compartida"),
                        )
                    }
                }
            }
            if (textos) SemanaPump(vista.semana, vista.fraccion.toFloat(), Modifier.padding(horizontal = Espacio.s))
            Spacer(Modifier.height(Espacio.l))
            if (textos) BotonMarca(PumpDelDia.SEGUIR, alCerrar, Modifier.widthIn(max = 520.dp).testTag("pump-seguir"))
        }
    }
}

private data class Chispa(val angulo: Float, val velocidad: Float, val tamano: Float, val giro: Float, val color: Int, val placa: Boolean)

private val CHISPAS: List<Chispa> by lazy {
    // Pseudoaleatorio fijo: el mismo dibujo en cada celebración (y en las capturas). Mismo generador que iOS.
    var x = -0x61c8864680b583ebL
    fun azar(): Float { x = x xor (x shl 13); x = x xor (x ushr 7); x = x xor (x shl 17); return ((x.toULong() % 10_000uL).toFloat()) / 10_000f }
    (0 until 44).map {
        Chispa((-PI / 2 + (azar() - 0.5) * PI * 1.9).toFloat(), 320 + azar() * 360, 6 + azar() * 8, (azar() - 0.5f) * 14, (azar() * 4).toInt(), azar() > 0.45f)
    }
}

@Composable
private fun Chispas(inicio: Long) {
    val c = MyPump.colores
    var ahora by remember { mutableStateOf(inicio) }
    LaunchedEffect(inicio) {
        while (ahora - inicio < 1_800_000_000L) ahora = withFrameNanos { it }
    }
    val colores = listOf(c.marcaVivo, c.marca, Color(0xFFFACB39), Color.White)
    Canvas(Modifier.size(640.dp, 760.dp).clearAndSetSemantics {}) {
        val s = (ahora - inicio) / 1e9f
        if (s >= 1.8f) return@Canvas
        val d = density
        for (ch in CHISPAS) {
            val px = center.x + cos(ch.angulo) * ch.velocidad * s * d
            val py = center.y + (sin(ch.angulo) * ch.velocidad * s + 0.5f * 900 * s * s) * d
            val alfa = max(0f, 1 - max(0f, s - 0.9f) / 0.9f)
            val w = ch.tamano * d
            val h = if (ch.placa) w else w / 3
            translate(px, py) {
                rotate(Math.toDegrees((ch.giro * s).toDouble()).toFloat(), pivot = Offset.Zero) {
                    drawRoundRect(colores[ch.color].copy(alpha = alfa), topLeft = Offset(-w / 2, -h / 2), size = Size(w, h),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(if (ch.placa) w * 0.3f else d))
                }
            }
        }
    }
}

/**
 * En la raíz, arriba de las pestañas: mira el «Pump del día» cuando cambian los pasos o el día, y celebra una vez por día
 * y por cuenta. Con la app en segundo plano no se mira nada (Android no lee Salud sin permiso de fondo): se celebra al volver.
 */
@Composable
fun CelebracionPumpRaiz(modelo: ModeloApp) {
    val e = estadoPump(modelo)
    // La fecha que se está celebrando sobrevive a recrear la Activity (girar, modo oscuro): el día ya quedó marcado y,
    // si se perdiera, esa celebración no volvería.
    var mostrandoDia by rememberSaveable { mutableStateOf<String?>(null) }
    var rachaCompartida by rememberSaveable { mutableStateOf(false) }
    val hoy = FechaLocal.hoy()
    // Solo con la app al frente: un delay que termina en segundo plano no marca el día (se celebra al volver).
    val ciclo = LocalLifecycleOwner.current.lifecycle
    val alFrente = ciclo.currentStateFlow.collectAsState().value.isAtLeast(Lifecycle.State.RESUMED)
    val clave = e?.let { "$hoy|${it.first.pasosHoy}|${it.first.meta}|${it.second}|$alFrente" }
    LaunchedEffect(clave) {
        val (v, conectado) = e ?: return@LaunchedEffect
        if (!alFrente || !conectado || mostrandoDia != null || !modelo.debeCelebrarPump(v, hoy)) return@LaunchedEffect
        // Un respiro para que se vea la tarjeta llenarse antes.
        delay(900)
        if (!ciclo.currentState.isAtLeast(Lifecycle.State.RESUMED)) return@LaunchedEffect
        if (FechaLocal.hoy() != hoy || !modelo.debeCelebrarPump(v, hoy)) return@LaunchedEffect
        modelo.marcarPumpCelebrado(hoy)
        // Logros: una racha que es un hito, con la función prendida y el permiso, queda en la cola (y la celebración lo dice).
        rachaCompartida = !modelo.esDemo.value && modelo.wins.value?.encolarRacha(v.racha, v.meta, hoy) == true
        mostrandoDia = hoy
    }
    val mostrando = if (mostrandoDia != null) e?.first else null
    if (mostrando != null) BackHandler { mostrandoDia = null }
    AnimatedVisibility(mostrando != null, enter = fadeIn(tween(200)), exit = fadeOut(tween(250))) {
        Box(Modifier.semantics { paneTitle = PumpDelDia.LLENO }) {
            mostrando?.let { CelebracionPump(it, rachaCompartida) { mostrandoDia = null } }
        }
    }
}

