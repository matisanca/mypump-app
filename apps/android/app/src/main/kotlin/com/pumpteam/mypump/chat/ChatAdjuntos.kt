package com.pumpteam.mypump.chat

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.BurbujaChat
import com.pumpteam.mypump.datos.ModeloChat
import com.pumpteam.mypump.datos.archivo
import com.pumpteam.mypump.diseno.Alerta
import com.pumpteam.mypump.diseno.BotonAlerta
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.fotos.BotonFoto
import com.pumpteam.mypump.guia.AudioDudaEntorno
import com.pumpteam.mypump.guia.GrabadorAudio
import com.pumpteam.mypump.guia.GrabadorMediaRecorder
import com.pumpteam.mypump.modelos.AdjuntoChat
import com.pumpteam.mypump.reglas.ReglasChatAdjuntos
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Fotos y audios en el chat con Mati (2.3.0), gemelo de ChatAdjuntosView.swift. Solo aparece con la palanca `chat_adjuntos`
// prendida y el cliente habilitado. Nada en la pantalla dice qué pasa con el archivo después: para el cliente es una foto o
// un audio que le llega a Mati, como por WhatsApp.

// ── La foto o el audio dentro de la burbuja ──

@Composable
internal fun AdjuntoEnBurbuja(
    m: BurbujaChat,
    a: AdjuntoChat,
    chat: ModeloChat?,
    reproductor: ReproductorChat,
    forma: androidx.compose.ui.graphics.Shape,
    verFoto: (ImageBitmap) -> Unit,
) {
    val c = MyPump.colores
    val mio = !m.esDelCoach
    if (a.borrado) {
        Row(
            Modifier
                .background(if (mio) c.marca.copy(alpha = 0.75f) else c.tarjeta, forma)
                .padding(horizontal = 14.dp, vertical = 9.dp)
                .testTag("chat-adjunto-no-disponible"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(if (a.tipo == AdjuntoChat.Tipo.FOTO) Iconos.Foto else Microfono, contentDescription = null, tint = if (mio) c.sobreMarca else c.textoSecundario, modifier = Modifier.size(16.dp))
            Text(ReglasChatAdjuntos.TEXTO_NO_DISPONIBLE, style = Letras.subtitulo.copy(fontStyle = FontStyle.Italic), color = if (mio) c.sobreMarca else c.textoSecundario)
        }
        return
    }
    when (a.tipo) {
        AdjuntoChat.Tipo.FOTO -> FotoEnBurbuja(m, a, chat, verFoto)
        AdjuntoChat.Tipo.AUDIO -> AudioEnBurbuja(m, a, chat, reproductor, forma)
    }
}

@Composable
private fun FotoEnBurbuja(m: BurbujaChat, a: AdjuntoChat, chat: ModeloChat?, ver: (ImageBitmap) -> Unit) {
    val c = MyPump.colores
    var imagen by remember(a.id) { mutableStateOf<ImageBitmap?>(null) }
    var intento by remember(a.id) { mutableStateOf(0) }
    val sinBajarTodos = chat?.sinBajar?.collectAsStateWithLifecycle()?.value ?: emptySet()
    val sinBajar = a.id in sinBajarTodos
    LaunchedEffect(a.id, intento) {
        if (imagen != null || chat == null) return@LaunchedEffect
        val f = chat.archivo(a) ?: return@LaunchedEffect
        // Una miniatura del tamaño de la burbuja: 30 fotos de 1600 px enteras en memoria serían ~300 MB.
        imagen = withContext(Dispatchers.Default) { miniatura(f, 900) }
    }
    val forma = RoundedCornerShape(18.dp)
    val ancho = 228.dp
    val alto = imagen?.let { i -> (ancho * (i.height.toFloat() / max(1, i.width))).coerceIn(ancho * 0.56f, ancho * 1.33f) } ?: (ancho * 0.75f)
    Box(
        Modifier
            .size(ancho, alto)
            .clip(forma)
            .border(1.dp, c.borde, forma)
            .background(c.campo)
            .clickable(role = Role.Button, onClickLabel = "verla grande") {
                val i = imagen
                if (i != null) ver(i) else if (sinBajar) intento++
            }
            .semantics { contentDescription = ReglasChatAdjuntos.TEXTO_FOTO_ACCESIBLE }
            .testTag("chat-foto"),
        contentAlignment = Alignment.Center,
    ) {
        val i = imagen
        if (i != null) {
            Image(i, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else if (sinBajar) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(Espacio.m)) {
                Icon(Iconos.Actualizar, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(22.dp))
                Text(ReglasChatAdjuntos.TEXTO_NO_CARGA, style = Letras.caption, color = c.textoSecundario)
            }
        } else {
            CircularProgressIndicator(color = c.textoSecundario, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
        }
        if (m.pendiente && !m.fallo) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp, modifier = Modifier.size(32.dp))
            }
        }
    }
}

private fun miniatura(f: File, maxPx: Int): ImageBitmap? = runCatching {
    val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(f.absolutePath, o)
    var muestra = 1
    while (max(o.outWidth, o.outHeight) / (muestra * 2) >= maxPx) muestra *= 2
    BitmapFactory.decodeFile(f.absolutePath, BitmapFactory.Options().apply { inSampleSize = muestra })?.asImageBitmap()
}.getOrNull()

@Composable
private fun AudioEnBurbuja(m: BurbujaChat, a: AdjuntoChat, chat: ModeloChat?, reproductor: ReproductorChat, forma: androidx.compose.ui.graphics.Shape) {
    val c = MyPump.colores
    val mio = !m.esDelCoach
    val alcance = rememberCoroutineScope()
    var cargando by remember { mutableStateOf(false) }
    var noSeEscucha by remember(a.id) { mutableStateOf(false) }
    val suena = reproductor.idSonando == a.id
    val total = max(a.duracion ?: reproductor.duracion(a.id) ?: 0.0, 0.0)
    val avance = if (reproductor.idCargado == a.id && total > 0) min(1.0, reproductor.actual / total) else 0.0
    val frente = if (mio) c.sobreMarca else c.marcaTexto
    Row(
        Modifier
            .width(232.dp)
            .alpha(if (m.pendiente && !m.fallo) 0.6f else 1f)
            .background(if (mio) c.marca else c.tarjeta, forma)
            .then(if (mio) Modifier else Modifier.border(1.dp, c.borde, forma))
            .padding(start = 10.dp, end = 14.dp, top = 9.dp, bottom = 9.dp)
            .semantics(mergeDescendants = true) { contentDescription = ReglasChatAdjuntos.textoAudioAccesible(total) }
            .testTag("chat-audio"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(
            Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(if (mio) c.sobreMarca.copy(alpha = 0.2f) else c.marca.copy(alpha = 0.14f))
                .clickable(enabled = !noSeEscucha && chat != null, role = Role.Button) {
                    if (suena) {
                        reproductor.pausar()
                    } else {
                        alcance.launch {
                            cargando = true
                            val f = chat?.archivo(a)
                            cargando = false
                            // Android reproduce m4a, ogg y webm; si igual no abre, se dice en vez de un botón que no anda.
                            if (f != null && !reproductor.alternar(a.id, f)) noSeEscucha = true
                        }
                    }
                }
                .semantics { contentDescription = if (suena) ReglasChatAdjuntos.TEXTO_PAUSAR else ReglasChatAdjuntos.TEXTO_REPRODUCIR }
                .testTag("chat-audio-play"),
            contentAlignment = Alignment.Center,
        ) {
            if (cargando) CircularProgressIndicator(color = frente, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
            else Icon(if (suena) Pausa else Iconos.Play, contentDescription = null, tint = frente, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            if (noSeEscucha) {
                Text(ReglasChatAdjuntos.TEXTO_NO_SE_ESCUCHA, style = Letras.caption, color = if (mio) c.sobreMarca else c.textoSecundario)
            } else {
                BarraAudio(avance, frente, Modifier.fillMaxWidth().height(22.dp))
                Text(
                    ReglasChatAdjuntos.duracion(if (suena) max(0.0, total - reproductor.actual) else total),
                    style = Letras.caption.merge(Letras.cifras),
                    color = if (mio) c.sobreMarca.copy(alpha = 0.85f) else c.textoSecundario,
                )
            }
        }
    }
}

private val ALTURAS = floatArrayOf(0.35f, 0.6f, 0.9f, 0.55f, 0.75f, 0.4f, 0.95f, 0.7f, 0.5f, 0.85f, 0.45f, 0.65f, 1f, 0.6f, 0.4f, 0.8f,
    0.55f, 0.9f, 0.5f, 0.7f, 0.35f, 0.6f, 0.85f, 0.45f, 0.7f, 0.5f, 0.3f)

/** La onda del audio: barras fijas (no hay que analizar el archivo) que se pintan a medida que avanza. */
@Composable
private fun BarraAudio(avance: Double, color: Color, modifier: Modifier) {
    Canvas(modifier) {
        val n = ALTURAS.size
        val paso = size.width / n
        val ancho = paso * 0.55f
        for (i in 0 until n) {
            val h = max(3.dp.toPx(), size.height * ALTURAS[i])
            drawRoundRect(
                color = color.copy(alpha = if (i.toDouble() / n < avance) 1f else 0.35f),
                topLeft = Offset(i * paso, (size.height - h) / 2),
                size = Size(ancho, h),
                cornerRadius = CornerRadius(ancho / 2),
            )
        }
    }
}

// ── El reproductor del chat (uno a la vez) ──

@Stable
internal class ReproductorChat {
    var idSonando by mutableStateOf<String?>(null)
        private set
    var idCargado by mutableStateOf<String?>(null)
        private set
    var actual by mutableDoubleStateOf(0.0)
        private set
    private var player: MediaPlayer? = null
    private val duraciones = HashMap<String, Double>()
    private var tics: kotlinx.coroutines.Job? = null
    private val alcance = kotlinx.coroutines.MainScope()

    fun duracion(id: String): Double? = duraciones[id]

    /** false si el archivo no se puede reproducir. */
    fun alternar(id: String, f: File): Boolean {
        if (idSonando == id) {
            pausar()
            return true
        }
        if (idCargado != id || player == null) {
            soltarPlayer()
            val p = runCatching {
                MediaPlayer().apply {
                    setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    setDataSource(f.absolutePath)
                    prepare()
                    setOnCompletionListener {
                        idSonando = null
                        actual = 0.0
                        tics?.cancel()
                    }
                }
            }.getOrNull() ?: return false
            player = p
            idCargado = id
            actual = 0.0
            duraciones[id] = p.duration / 1000.0
        }
        player?.start()
        idSonando = id
        tics?.cancel()
        tics = alcance.launch {
            while (isActive) {
                delay(200)
                actual = (player?.currentPosition ?: 0) / 1000.0
            }
        }
        return true
    }

    fun pausar() {
        runCatching { player?.pause() }
        idSonando = null
        tics?.cancel()
    }

    private fun soltarPlayer() {
        tics?.cancel()
        runCatching { player?.release() }
        player = null
    }

    fun soltar() {
        pausar()
        soltarPlayer()
        idCargado = null
        actual = 0.0
    }
}

// ── La foto grande ──

@Composable
internal fun VisorFoto(imagen: ImageBitmap, alCerrar: () -> Unit) {
    var escala by remember { mutableStateOf(1f) }
    var desplazamiento by remember { mutableStateOf(Offset.Zero) }
    Dialog(onDismissRequest = alCerrar, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black).testTag("chat-visor")) {
            Image(
                imagen,
                contentDescription = ReglasChatAdjuntos.TEXTO_FOTO_ACCESIBLE,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        detectTransformGestures { _, mov, zoom, _ ->
                            escala = (escala * zoom).coerceIn(1f, 5f)
                            desplazamiento = if (escala > 1f) desplazamiento + mov else Offset.Zero
                        }
                    }
                    .pointerInput(Unit) {
                        detectTapGestures(onDoubleTap = {
                            if (escala > 1f) {
                                escala = 1f
                                desplazamiento = Offset.Zero
                            } else {
                                escala = 2.5f
                            }
                        })
                    }
                    .graphicsLayer {
                        scaleX = escala
                        scaleY = escala
                        translationX = desplazamiento.x
                        translationY = desplazamiento.y
                    },
            )
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .statusBarsPadding()
                    .padding(Espacio.m)
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.18f))
                    .clickable(role = Role.Button, onClick = alCerrar)
                    .semantics { contentDescription = ReglasChatAdjuntos.TEXTO_CERRAR }
                    .testTag("chat-visor-cerrar"),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Iconos.Cerrar, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
            }
        }
    }
}

// ── Grabar manteniendo apretado ──

/**
 * El micrófono del chat: mientras se mantiene apretado graba; al soltar se manda; deslizando a la izquierda se cancela. A
 * los 2 minutos se corta solo y se manda. Con TalkBack se toca una vez para empezar y otra para mandar.
 */
@Stable
internal class GrabacionChat(private val contexto: Context, private val alTerminar: (File, Double) -> Unit) {
    var grabando by mutableStateOf(false)
        private set
    var segundos by mutableDoubleStateOf(0.0)
        private set
    var cancelando by mutableStateOf(false)
        private set
    var porToque by mutableStateOf(false)
        private set
    var aviso by mutableStateOf<String?>(null)
    var maximo = ReglasChatAdjuntos.AUDIO_MAXIMO

    private val grabador: GrabadorAudio = AudioDudaEntorno.grabador?.invoke(contexto) ?: GrabadorMediaRecorder(contexto)
    private var archivo: File? = null
    private var inicio = 0L
    private var reloj: kotlinx.coroutines.Job? = null
    private val alcance = kotlinx.coroutines.MainScope()

    fun tienePermiso(): Boolean = AudioDudaEntorno.permiso
        ?: (ContextCompat.checkSelfPermission(contexto, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)

    fun empezar(porToque: Boolean = false): Boolean {
        if (grabando) return false
        val f = File(contexto.cacheDir, "chat-${System.nanoTime()}.m4a")
        try {
            grabador.empezar(f) { alcance.launch { terminar(mandar = true) } }
        } catch (_: Exception) {
            f.delete()
            aviso = "El micrófono lo está usando otra app. Cerrala y probá de nuevo."
            return false
        }
        archivo = f
        inicio = System.currentTimeMillis()
        segundos = 0.0
        cancelando = false
        this.porToque = porToque
        grabando = true
        reloj = alcance.launch {
            while (isActive && grabando) {
                delay(100)
                segundos = (System.currentTimeMillis() - inicio) / 1000.0
                if (segundos >= maximo) {
                    terminar(mandar = true)
                    return@launch
                }
            }
        }
        return true
    }

    fun mover(dxDp: Float) {
        if (!grabando || porToque) return
        cancelando = -dxDp > ReglasChatAdjuntos.DESLIZAR_PARA_CANCELAR_DP
    }

    fun terminar(mandar: Boolean) {
        if (!grabando) return
        reloj?.cancel()
        val s = (System.currentTimeMillis() - inicio) / 1000.0
        val quedo = grabador.detener()
        grabando = false
        porToque = false
        val enviar = mandar && !cancelando && quedo
        cancelando = false
        val f = archivo ?: return
        archivo = null
        if (enviar) alTerminar(f, min(s, maximo)) else f.delete()
    }

    fun soltar() {
        if (grabando) terminar(mandar = true)
    }
}

/** La barra que reemplaza al campo mientras se graba: el punto rojo, el tiempo y «Deslizá para cancelar». */
@Composable
internal fun BarraGrabando(g: GrabacionChat, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val latido by rememberInfiniteTransition(label = "latido").animateFloat(1f, 0.25f, infiniteRepeatable(tween(700), RepeatMode.Reverse), label = "punto")
    Row(
        modifier
            .heightIn(min = 44.dp)
            .superficieTarjeta(radio = 22.dp)
            .padding(horizontal = Espacio.m)
            .testTag("chat-grabando"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(Modifier.size(10.dp).alpha(latido).background(c.peligro, CircleShape))
        Text(
            ReglasChatAdjuntos.duracion(g.segundos),
            style = Letras.subtitulo.merge(Letras.cifras).copy(fontWeight = FontWeight.SemiBold),
            color = c.texto,
            modifier = Modifier.semantics { contentDescription = "Grabando, ${ReglasChatAdjuntos.duracionHablada(g.segundos)}" },
        )
        Spacer(Modifier.weight(1f))
        when {
            g.porToque -> Text(
                ReglasChatAdjuntos.TEXTO_CANCELAR,
                style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold),
                color = c.peligro,
                modifier = Modifier
                    .heightIn(min = 44.dp)
                    .clickable(role = Role.Button) { g.terminar(mandar = false) }
                    .padding(horizontal = 4.dp, vertical = 12.dp)
                    .testTag("chat-grabar-cancelar"),
            )
            g.segundos >= ReglasChatAdjuntos.AUDIO_AVISO -> Text(ReglasChatAdjuntos.TEXTO_QUEDAN_DIEZ, style = Letras.caption.copy(fontWeight = FontWeight.SemiBold), color = c.peligro)
            else -> Text("‹ " + ReglasChatAdjuntos.TEXTO_DESLIZAR_PARA_CANCELAR, style = Letras.caption, color = if (g.cancelando) c.peligro else c.textoSecundario, maxLines = 1)
        }
    }
}

/** El botón del micrófono (con el campo vacío ocupa el lugar de Enviar, como en WhatsApp). */
@Composable
internal fun BotonMicrofono(g: GrabacionChat, pedirPermiso: () -> Unit) {
    val c = MyPump.colores
    val haptico = LocalHapticFeedback.current
    val densidad = LocalDensity.current
    val graba = g.grabando
    Box(
        Modifier
            .scale(if (graba && !g.porToque) 1.3f else 1f)
            .size(44.dp)
            .then(if (graba) Modifier.background(if (g.cancelando) c.peligro else c.marca, CircleShape) else Modifier.superficieTarjeta(radio = 22.dp))
            .pointerInput(g) {
                awaitEachGesture {
                    val abajo = awaitFirstDown()
                    if (g.porToque) return@awaitEachGesture
                    if (!g.tienePermiso()) {
                        pedirPermiso()
                        return@awaitEachGesture
                    }
                    if (!g.empezar()) return@awaitEachGesture
                    haptico.performHapticFeedback(HapticFeedbackType.LongPress)
                    var dx = 0f
                    while (true) {
                        val e = awaitPointerEvent()
                        val p = e.changes.firstOrNull { it.id == abajo.id } ?: break
                        dx = p.position.x - abajo.position.x
                        g.mover(with(densidad) { dx.toDp().value })
                        if (!p.pressed) break
                    }
                    g.terminar(mandar = true)
                }
            }
            .semantics {
                role = Role.Button
                contentDescription = if (graba) ReglasChatAdjuntos.TEXTO_MANDAR_AUDIO_ACCESIBLE else ReglasChatAdjuntos.TEXTO_GRABAR_ACCESIBLE
                if (!graba) stateDescription = ReglasChatAdjuntos.AYUDA_GRABAR_ACCESIBLE
                // TalkBack: un toque doble empieza y otro manda.
                onClick {
                    if (graba) g.terminar(mandar = true) else if (g.tienePermiso()) g.empezar(porToque = true) else pedirPermiso()
                    true
                }
            }
            .testTag("chat-microfono"),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            if (graba && g.porToque) Iconos.FlechaArriba else Microfono,
            contentDescription = null,
            tint = if (graba) c.sobreMarca else c.marcaTexto,
            modifier = Modifier.size(20.dp),
        )
    }
}

/** El permiso del micrófono: se pide al primer toque; negado, se ofrece ir a Ajustes. */
@Composable
internal fun rememberPedirMicrofono(): Pair<() -> Unit, @Composable () -> Unit> {
    val contexto = LocalContext.current
    var negado by remember { mutableStateOf(false) }
    val lanzador = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> if (!ok) negado = true }
    val pedir: () -> Unit = { if (AudioDudaEntorno.permiso == false) negado = true else lanzador.launch(Manifest.permission.RECORD_AUDIO) }
    val alerta: @Composable () -> Unit = {
        if (negado) {
            Alerta(
                titulo = ReglasChatAdjuntos.TEXTO_SIN_MICROFONO,
                botones = listOf(
                    BotonAlerta(ReglasChatAdjuntos.TEXTO_CANCELAR, cancelar = true) { negado = false },
                    BotonAlerta(ReglasChatAdjuntos.TEXTO_ABRIR_AJUSTES) {
                        negado = false
                        contexto.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", contexto.packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    },
                ),
                alDescartar = { negado = false },
            )
        }
    }
    return pedir to alerta
}

/** El botón de la foto, a la izquierda del campo: «Sacar foto» o «Elegir de la galería». */
@Composable
internal fun BotonFotoChat(alElegir: (ByteArray) -> Unit) {
    val c = MyPump.colores
    BotonFoto(
        clave = "chat",
        maxPx = ReglasChatAdjuntos.FOTO_LADO_MAXIMO,
        calidad = ReglasChatAdjuntos.FOTO_CALIDAD / 100.0,
        alElegir = alElegir,
        modifier = Modifier.semantics { contentDescription = ReglasChatAdjuntos.TEXTO_ADJUNTAR }.testTag("chat-foto-boton"),
    ) {
        Box(Modifier.size(44.dp).superficieTarjeta(radio = 22.dp), contentAlignment = Alignment.Center) {
            Icon(Iconos.Camara, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
        }
    }
}

/** mic (Material Icons, Apache 2.0). */
internal val Microfono: ImageVector by lazy {
    ImageVector.Builder(name = "Microfono", defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
        .apply {
            addPath(
                pathData = addPathNodes(
                    "M12,14c1.66,0 2.99,-1.34 2.99,-3L15,5c0,-1.66 -1.34,-3 -3,-3S9,3.34 9,5v6c0,1.66 1.34,3 3,3zM17.3,11c0,3 -2.54,5.1 -5.3,5.1S6.7,14 6.7,11H5c0,3.41 2.72,6.23 6,6.72V21h2v-3.28c3.28,-0.48 6,-3.3 6,-6.72h-1.7z",
                ),
                fill = SolidColor(Color.Black),
            )
        }
        .build()
}

/** pause (Material Icons, Apache 2.0). */
private val Pausa: ImageVector by lazy {
    ImageVector.Builder(name = "Pausa", defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
        .apply { addPath(pathData = addPathNodes("M6,19h4V5H6v14zM14,5v14h4V5h-4z"), fill = SolidColor(Color.Black)) }
        .build()
}
