package com.pumpteam.mypump.progreso

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.volumenPorMusculo
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.VolumenMusculo

/**
 * El volumen por músculo (2.1, S2) de la app, recalculado cuando cambia lo que lo arma: el historial de Progreso, la
 * rutina, lo confirmado en Entreno (el día, con sus sustituciones, y la fecha real de cada serie), el catálogo y la fecha.
 */
@Composable
fun rememberVolumenMusculo(modelo: ModeloApp): VolumenMusculo.Resumen {
    val progreso by modelo.progreso.collectAsStateWithLifecycle()
    val historial = progreso?.historialPorClave?.collectAsStateWithLifecycle()?.value
    val rutina by modelo.rutina.collectAsStateWithLifecycle()
    val entreno by modelo.entreno.collectAsStateWithLifecycle()
    val dia = entreno?.dia?.collectAsStateWithLifecycle()?.value
    val catalogo = entreno?.catalogo?.collectAsStateWithLifecycle()?.value
    val fechas = entreno?.fechasSeries?.collectAsStateWithLifecycle()?.value
    val hoy = FechaLocal.hoy()
    return remember(historial, rutina, entreno, dia, catalogo, fechas, hoy) { modelo.volumenPorMusculo() }
}

/** La etiqueta de prueba de una fila: `volumen-chest`; sin músculo, `volumen-sin`. */
internal fun etiquetaVolumen(f: VolumenMusculo.Fila, prefijo: String = "volumen"): String = "$prefijo-${f.musculo ?: "sin"}"

/**
 * «Series por músculo» (Salud → Fuerza): una fila por músculo con una barra fina contra el máximo de las dos semanas
 * (la semana pasada como barra tenue de fondo), el número de esta semana y «N la pasada». Cada fila es una sola unidad
 * para TalkBack (`Fila.textoAccesible`). Liviana, como la preparación de Entreno: letra chica, sin cajas adentro.
 */
/** Lo que dice la tarjeta sin filas: sin series, trayendo el historial o sin red. */
const val VACIO_SIN_SERIES = VolumenMusculo.VACIO_SIN_SERIES
const val VACIO_CARGANDO = VolumenMusculo.VACIO_CARGANDO
const val VACIO_SIN_RED = VolumenMusculo.VACIO_SIN_RED

@Composable
fun CardVolumenMusculo(resumen: VolumenMusculo.Resumen, modifier: Modifier = Modifier, vacio: String = VACIO_SIN_SERIES) {
    val c = MyPump.colores
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        EncabezadoSeccion("Series por músculo", detalle = "esta semana")
        Tarjeta(Modifier.testTag("volumen-musculo"), espaciado = 14.dp) {
            if (resumen.filas.isEmpty()) {
                Text(vacio, style = Letras.subtitulo, color = c.textoSecundario)
            } else {
                val tope = resumen.tope.coerceAtLeast(1)
                for (f in resumen.filas) FilaVolumen(f, tope)
            }
            Text(
                "Series efectivas registradas, de lunes a domingo. La preparación no cuenta.",
                style = Letras.caption,
                color = c.textoTerciario,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}

@Composable
private fun FilaVolumen(f: VolumenMusculo.Fila, tope: Int) {
    val c = MyPump.colores
    val grande = LocalDensity.current.fontScale >= 1.3f
    Row(
        Modifier
            .fillMaxWidth()
            // La etiqueta antes: `clearAndSetSemantics` borra la semántica de lo que viene después.
            .testTag(etiquetaVolumen(f))
            .clearAndSetSemantics { contentDescription = f.textoAccesible },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.m),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                f.nombre,
                style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold),
                color = if (f.musculo == null) c.textoSecundario else c.texto,
                maxLines = if (grande) Int.MAX_VALUE else 1,
            )
            Barra(f.semana / tope.toFloat(), f.anterior / tope.toFloat())
        }
        Column(Modifier.widthIn(min = 64.dp), horizontalAlignment = Alignment.End) {
            Text("${f.semana}", style = Numeros.mediano.merge(Letras.cifras), color = c.texto, textAlign = TextAlign.End)
            Text("${f.anterior} la pasada", style = Letras.caption, color = c.textoSecundario, textAlign = TextAlign.End)
        }
    }
}

/** Una barra fina: la semana pasada tenue de fondo y esta semana en el verde de la marca encima. */
@Composable
private fun Barra(semana: Float, anterior: Float) {
    val c = MyPump.colores
    Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(c.campo)) {
        if (anterior > 0f) {
            Box(Modifier.fillMaxWidth(anterior.coerceIn(0f, 1f)).fillMaxHeight().clip(CircleShape).background(c.marcaVivo.copy(alpha = 0.22f)))
        }
        if (semana > 0f) {
            Box(Modifier.fillMaxWidth(semana.coerceIn(0f, 1f)).fillMaxHeight().clip(CircleShape).background(c.marcaVivo))
        }
    }
}

/** «Pecho, 3 series hoy, 8 en la semana». */
internal fun textoAccesibleHoy(f: VolumenMusculo.Fila): String = "${f.nombre}, ${VolumenMusculo.series(f.hoy)} hoy, ${f.semana} en la semana"

/**
 * «Series por músculo hoy» del cierre del día: los músculos con series hoy (más series primero), con lo de hoy y lo de la
 * semana. Sin series hoy no ocupa lugar.
 */
@Composable
fun SeccionVolumenHoy(resumen: VolumenMusculo.Resumen, modifier: Modifier = Modifier) {
    if (resumen.totalHoy <= 0) return
    val c = MyPump.colores
    Column(modifier.fillMaxWidth().testTag("volumen-hoy"), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Text("Series por músculo hoy", style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.textoSecundario)
        Column(Modifier.fillMaxWidth().superficieTarjeta()) {
            val filas = resumen.filasDeHoy
            filas.forEachIndexed { i, f ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp)
                        .testTag(etiquetaVolumen(f, "volumen-hoy"))
                        .clearAndSetSemantics { contentDescription = textoAccesibleHoy(f) },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(f.nombre, style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.texto, modifier = Modifier.weight(1f))
                    Column(horizontalAlignment = Alignment.End) {
                        Text("${f.hoy} hoy", style = Letras.subtitulo.merge(Letras.cifras).copy(fontWeight = FontWeight.SemiBold), color = c.marcaTexto)
                        Text("${f.semana} en la semana", style = Letras.caption.merge(Letras.cifras), color = c.textoSecundario)
                    }
                }
                if (i < filas.size - 1) Separador(sangria = 14.dp)
            }
        }
    }
}
