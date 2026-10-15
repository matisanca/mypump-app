package com.pumpteam.mypump.entreno

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.annotation.VisibleForTesting
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.Archivo
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.reglas.BarraDescanso
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin
import kotlinx.coroutines.delay

// El descanso entre series (SES-04), siempre a mano: una isla arriba de la barra de pestañas, también desde las otras
// pestañas (como en iOS). El tiempo lo lleva el motor (`BarraDescanso`, anclado a una fecha de fin): esto solo lo pinta.

/**
 * El reloj del descanso (lo corre la raíz, arriba de las pestañas): mientras se ve la barra, un tick cada 250 ms. La vez
 * que termina, el háptico y el pitido. A los 2 s del fin el motor la cierra solo.
 *
 * Con la app en segundo plano el reloj sigue mientras el proceso vive, pero el que avisa es la notificación del fin del
 * descanso (D8, `avisos/AvisosEnLaApp`): el pitido no suena encima.
 */
@Composable
fun RelojDescanso(motor: ModeloEntreno) {
    val b by motor.descanso.collectAsStateWithLifecycle()
    val vista = LocalView.current
    val ciclo = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(motor, b.visible) {
        if (!b.visible) return@LaunchedEffect
        while (motor.descanso.value.visible) {
            if (motor.tickDescanso() && ciclo.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                // El háptico del sistema (el "éxito" de iOS): no pide permisos.
                vista.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.LONG_PRESS)
                SonidoDescanso.reproducir()
            }
            delay(250)
        }
    }
}

/** La isla del descanso: anillo con lo que falta, el tiempo, −15 / +15 y saltar. Al terminar, verde hasta que se cierra. */
@Composable
fun BarraDescansoEntreno(motor: ModeloEntreno, modifier: Modifier = Modifier) {
    val b by motor.descanso.collectAsStateWithLifecycle()
    AnimatedVisibility(
        visible = b.visible,
        modifier = modifier,
        enter = slideInVertically { it } + fadeIn(),
        exit = slideOutVertically { it } + fadeOut(),
    ) {
        ContenidoDescanso(motor, b)
    }
}

@Composable
private fun ContenidoDescanso(motor: ModeloEntreno, b: BarraDescanso) {
    val c = MyPump.colores
    val listo = b.listo
    // `porcentaje` es lo que ya pasó; el anillo muestra lo que falta.
    val falta = if (listo) 1.0 else (1 - (b.porcentaje ?: 0.0) / 100).coerceIn(0.0, 1.0)
    // La barra tiene alto fijo, como la de pestañas: la letra se topea (el `.dynamicTypeSize(...xLarge)` de iOS).
    val escala = LocalDensity.current.fontScale
    val tope = min(escala, 1.3f) / escala
    val fondo = if (listo) c.exito.copy(alpha = 0.16f).compositeOver(c.tarjeta) else c.tarjeta
    Row(
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .padding(bottom = 8.dp)
            .fillMaxWidth()
            .clip(CircleShape)
            .background(fondo)
            .border(1.dp, c.borde, CircleShape)
            .padding(start = 14.dp, end = 4.dp, top = 4.dp, bottom = 4.dp)
            .testTag("descanso"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        AnilloProgreso(falta, Modifier.size(32.dp), grosor = 3.5.dp, color = if (listo) c.exito else c.marcaVivo) {
            Icon(
                if (listo) Iconos.Tilde else Iconos.Temporizador,
                contentDescription = null,
                tint = if (listo) c.exito else c.texto,
                modifier = Modifier.size(14.dp),
            )
        }
        Column(
            Modifier
                .weight(1f)
                // TalkBack lee esto en vez de los dos textos.
                .semantics(mergeDescendants = true) { contentDescription = if (listo) "Descanso terminado" else "Descanso, quedan ${b.texto}" }
                .testTag("descanso-estado"),
        ) {
            Text(
                if (listo) "¡A la próxima serie!" else "Descanso ${b.textoObjetivo.replace(" objetivo", "")}",
                style = Letras.caption2.copy(fontWeight = FontWeight.SemiBold, fontSize = (11 * tope).sp),
                color = if (listo) c.exito else c.textoSecundario,
                maxLines = 1,
                modifier = Modifier.testTag("descanso-rotulo"),
            )
            Text(
                b.texto,
                style = Letras.cifras.copy(fontFamily = Archivo, fontWeight = FontWeight.W700, fontSize = (20 * tope).sp),
                color = if (listo) c.exito else c.texto,
                maxLines = 1,
                modifier = Modifier.testTag("descanso-tiempo"),
            )
        }
        BotonDescanso("−15", "Restar 15 segundos", !listo, tope, Modifier.testTag("descanso-menos")) { motor.ajustarDescanso(-15) }
        BotonDescanso("+15", "Sumar 15 segundos", !listo, tope, Modifier.testTag("descanso-mas")) { motor.ajustarDescanso(15) }
        Box(
            Modifier
                .size(44.dp)
                .clickable(enabled = !listo, role = Role.Button) { motor.saltarDescanso() }
                .semantics { contentDescription = "Saltar descanso" }
                .testTag("descanso-saltar"),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(34.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
                Icon(Iconos.Saltar, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun BotonDescanso(texto: String, descripcion: String, habilitado: Boolean, tope: Float, modifier: Modifier, alTocar: () -> Unit) {
    val c = MyPump.colores
    Box(
        modifier
            .size(width = 44.dp, height = 40.dp)
            .clip(CircleShape)
            .clickable(enabled = habilitado, role = Role.Button, onClick = alTocar)
            .clearAndSetSemantics { contentDescription = descripcion },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            texto,
            style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold, fontSize = (15 * tope).sp).merge(Letras.cifras),
            color = if (habilitado) c.texto else c.textoTerciario,
        )
    }
}

/**
 * El pitido del fin del descanso: dos tonos cortos (880 Hz y 1320 Hz, el mismo de iOS). Va como sonido del sistema
 * (`USAGE_ASSISTANCE_SONIFICATION`) y SIN pedir el foco de audio: se mezcla con la música del cliente en vez de cortarla
 * o bajarla (el `.ambient` + `.mixWithOthers` de iOS, SES-05), y con el teléfono en silencio o vibración no suena.
 */
object SonidoDescanso {
    /** Cuántas veces sonó (para las pruebas: en el emulador no hay oído). */
    @VisibleForTesting
    @Volatile
    var reproducciones = 0
        private set

    private var pista: AudioTrack? = null

    fun reproducir() {
        reproducciones++
        try {
            val p = pista ?: crear().also { pista = it }
            if (p.playState != AudioTrack.PLAYSTATE_STOPPED) p.stop()
            p.reloadStaticData()
            p.play()
        } catch (_: Exception) {
            // Sin audio (un teléfono raro, el emulador sin salida): el háptico igual avisa.
            pista?.release()
            pista = null
        }
    }

    private fun crear(): AudioTrack {
        val muestras = pitido()
        val t = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(FRECUENCIA)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(muestras.size * 2)
            .build()
        t.write(muestras, 0, muestras.size)
        return t
    }

    private const val FRECUENCIA = 44_100

    /** 880 Hz por 120 ms, 60 ms de silencio y 1320 Hz por 160 ms, al 35 % y con rampas para que no haga clic (el WAV de iOS). */
    fun pitido(): ShortArray {
        val muestras = ArrayList<Short>()
        fun tono(hz: Double, segundos: Double) {
            val n = (FRECUENCIA * segundos).toInt()
            for (i in 0 until n) {
                val rampa = minOf(1.0, i / 400.0, (n - i) / 400.0)
                muestras += (sin(2 * PI * hz * i / FRECUENCIA) * 0.35 * rampa * Short.MAX_VALUE).toInt().toShort()
            }
        }
        fun silencio(segundos: Double) = repeat((FRECUENCIA * segundos).toInt()) { muestras += 0 }
        tono(880.0, 0.12)
        silencio(0.06)
        tono(1320.0, 0.16)
        return muestras.toShortArray()
    }
}
