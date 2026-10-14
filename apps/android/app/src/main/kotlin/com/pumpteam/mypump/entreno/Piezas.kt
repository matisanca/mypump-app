package com.pumpteam.mypump.entreno

import android.provider.Settings
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.ImagenRemota
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta

// Las piezas de Entreno que no son de una sola pantalla (Componentes.swift y lo de EntrenoView.swift que se comparte).

/** Las letras de Entreno con los tamaños de iOS (caption 12, caption2 11, subheadline 15, title3 20…). */
object Letras {
    /** Dígitos de ancho fijo (`monospacedDigit`). */
    private const val CIFRAS = "tnum"

    val ceja: TextStyle
        @Composable @ReadOnlyComposable get() = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp)
    val caption: TextStyle
        @Composable @ReadOnlyComposable get() = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, lineHeight = 16.sp)
    val caption2: TextStyle
        @Composable @ReadOnlyComposable get() = MaterialTheme.typography.bodySmall.copy(fontSize = 11.sp, lineHeight = 13.sp)
    val subtitulo: TextStyle
        @Composable @ReadOnlyComposable get() = MaterialTheme.typography.bodyMedium
    val titulo3: TextStyle
        @Composable @ReadOnlyComposable get() = MaterialTheme.typography.titleLarge.copy(fontFamily = null, fontWeight = FontWeight.Bold, fontSize = 20.sp, lineHeight = 25.sp)
    val titulo2: TextStyle
        @Composable @ReadOnlyComposable get() = MaterialTheme.typography.titleLarge.copy(fontFamily = null, fontWeight = FontWeight.Bold, fontSize = 22.sp, lineHeight = 28.sp)
    val cifras: TextStyle get() = TextStyle(fontFeatureSettings = CIFRAS)

    /** El título del día ("Tirón"), en Archivo como `Font.tituloDia`. */
    val tituloDia: TextStyle get() = Numeros.grande.copy(fontWeight = FontWeight.W800, fontSize = 40.sp, lineHeight = 46.sp)
}

/** La "ceja" que va arriba de un título: chica, en mayúsculas, espaciada y gris. TalkBack lee el texto sin mayúsculas. */
@Composable
fun Ceja(texto: String, modifier: Modifier = Modifier, color: Color = MyPump.colores.textoSecundario) {
    Text(texto.uppercase(), style = Letras.ceja, color = color, modifier = modifier.semantics { contentDescription = texto })
}

/** Píldora chica de dato ("4 × 6-8", "RIR 1-2", "3:00"). Con un tono de color, el fondo se tiñe del mismo. */
@Composable
fun ChipDato(texto: String, modifier: Modifier = Modifier, icono: ImageVector? = null, tono: Color? = null) {
    val c = MyPump.colores
    val color = tono ?: c.textoSecundario
    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(if (tono == null) c.campo else tono.copy(alpha = 0.14f))
            .padding(horizontal = 9.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (icono != null) Icon(icono, contentDescription = null, tint = color, modifier = Modifier.size(12.dp))
        Text(texto, style = Letras.caption.copy(fontWeight = FontWeight.SemiBold).merge(Letras.cifras), color = color, maxLines = 1)
    }
}

/** "Fijado" (vale para las próximas semanas) o "Solo hoy". */
@Composable
fun InsigniaSustitucion(fijado: Boolean, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(c.marcaSuave)
            .padding(horizontal = 7.dp, vertical = 3.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = if (fijado) "Sustitución fijada para las próximas semanas" else "Sustituido solo por hoy"
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(if (fijado) Iconos.Candado else Iconos.Intercambio, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(11.dp))
        Text(if (fijado) "Fijado" else "Solo hoy", style = Letras.caption2.copy(fontWeight = FontWeight.Bold), color = c.marcaTexto, maxLines = 1)
    }
}

/** Anillo de progreso con pista (como los de Actividad). El centro es libre. */
@Composable
fun AnilloProgreso(
    fraccion: Double,
    modifier: Modifier = Modifier,
    grosor: Dp = 8.dp,
    color: Color = MyPump.colores.marcaVivo,
    pista: Color = MyPump.colores.campo,
    centro: @Composable BoxScope.() -> Unit = {},
) {
    val animada by animateFloatAsState(fraccion.toFloat().coerceIn(0f, 1f), label = "anillo")
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val g = grosor.toPx()
            val lado = size.minDimension - g
            val esquina = Offset((size.width - lado) / 2, (size.height - lado) / 2)
            drawArc(pista, 0f, 360f, useCenter = false, topLeft = esquina, size = Size(lado, lado), style = Stroke(g))
            // En cero no se dibuja nada: la tapa redonda de un trazo vacío queda como un punto suelto.
            if (animada > 0.001f) {
                drawArc(color, -90f, animada * 360f, useCenter = false, topLeft = esquina, size = Size(lado, lado), style = Stroke(g, cap = StrokeCap.Round))
            }
        }
        centro()
    }
}

/** Un dato con su rótulo: "Última vez · 58 kg × 9 · hace 13 días". El valor va en Archivo. */
@Composable
fun Dato(titulo: String, valor: String, detalle: String?, icono: ImageVector, modifier: Modifier = Modifier, tono: Color = MyPump.colores.textoSecundario) {
    val c = MyPump.colores
    Column(
        modifier = modifier.superficieTarjeta().padding(14.dp).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.size(13.dp))
            Text(titulo, style = Letras.caption.copy(fontWeight = FontWeight.SemiBold), color = tono)
        }
        BasicText(
            valor,
            style = Numeros.mediano.copy(color = c.texto).merge(Letras.cifras),
            maxLines = 1,
            autoSize = TextAutoSize.StepBased(minFontSize = 15.sp, maxFontSize = 22.sp),
        )
        if (detalle != null) Text(detalle, style = Letras.caption, color = c.textoSecundario)
    }
}

/** Aviso teñido arriba del día ("Esta semana 7 ejercicios cambian carga o volumen"). */
@Composable
fun AvisoTenido(icono: ImageVector, texto: AnnotatedString, modifier: Modifier = Modifier, tono: Color = MyPump.colores.marcaTexto) {
    val c = MyPump.colores
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.control + 4.dp))
            .background(if (tono == c.marcaTexto) c.marcaSuave else tono.copy(alpha = 0.12f))
            .padding(Espacio.m)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.padding(top = 1.dp).size(18.dp))
        Text(texto, style = Letras.subtitulo, color = c.texto)
    }
}

/** Miniatura del ejercicio (la foto del catálogo) o, si no hay, un ícono del tipo sobre gris. */
@Composable
fun Miniatura(url: String?, tipo: String?, lado: Dp, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val forma = RoundedCornerShape(Radio.miniatura)
    Box(modifier.size(lado).clip(forma).border(1.dp, c.borde, forma)) {
        ImagenRemota(url, lado, Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().background(c.campo), contentAlignment = Alignment.Center) {
                Icon(
                    if (tipo == "cardio") Iconos.Correr else Iconos.Pesa,
                    contentDescription = null,
                    tint = c.textoTerciario,
                    modifier = Modifier.size(lado * 0.4f),
                )
            }
        }
    }
}

/** Un punto por serie: lleno las confirmadas (lo que muestra la tarjeta cerrada de la web). */
@Composable
fun PuntosSeries(total: Int, hechas: Int, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Row(
        modifier = modifier.semantics { contentDescription = "$hechas de $total series" },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (i in 0 until maxOf(total, 0)) {
            val ancho by animateDpAsState(if (i < hechas) 10.dp else 6.dp, label = "punto")
            Box(Modifier.width(ancho).height(6.dp).clip(CircleShape).background(if (i < hechas) c.marcaVivo else c.campo))
        }
    }
}

/** Una celda de los resúmenes ("SERIES 12"). */
@Composable
fun CeldaResumen(titulo: String, valor: String, modifier: Modifier = Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Ceja(titulo)
        BasicText(
            valor,
            style = Numeros.chico.copy(color = MyPump.colores.texto).merge(Letras.cifras),
            maxLines = 1,
            autoSize = TextAutoSize.StepBased(minFontSize = 12.sp, maxFontSize = 17.sp),
        )
    }
}

/** Una línea vertical entre celdas. */
@Composable
fun SeparadorVertical(alto: Dp = 36.dp) {
    Box(Modifier.width(1.dp).height(alto).background(MyPump.colores.borde))
}

/**
 * "Quitar animaciones" de Accesibilidad (el Reducir movimiento de iOS, GEN-08): con la escala de animaciones en 0, lo que
 * se mueve solo (el pulso de "En curso", las fotos que se alternan) queda quieto.
 */
@Composable
fun reducirMovimiento(): Boolean {
    val contexto = LocalContext.current
    return remember(contexto) {
        Settings.Global.getFloat(contexto.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/**
 * Botón con ícono, en las dos formas de la app: el principal (lima con texto negro) y el secundario (gris). El ícono va
 * adelante ("▶ Empezar entrenamiento") o al final ("Siguiente: Remo →").
 */
@Composable
fun BotonConIcono(
    texto: String,
    icono: ImageVector?,
    alTocar: () -> Unit,
    modifier: Modifier = Modifier,
    principal: Boolean = true,
    iconoAlFinal: Boolean = false,
    habilitado: Boolean = true,
    compacto: Boolean = false,
    tono: Color? = null,
    cargando: Boolean = false,
) {
    val c = MyPump.colores
    val colores = if (principal) {
        ButtonDefaults.buttonColors(
            containerColor = c.marca,
            contentColor = c.sobreMarca,
            disabledContainerColor = if (cargando) c.marca else c.campo,
            disabledContentColor = if (cargando) c.sobreMarca else c.textoSecundario,
        )
    } else {
        ButtonDefaults.buttonColors(
            containerColor = c.campo,
            contentColor = tono ?: c.texto,
            disabledContainerColor = c.campo,
            disabledContentColor = c.textoSecundario,
        )
    }
    Button(
        onClick = alTocar,
        enabled = habilitado && !cargando,
        modifier = modifier
            .then(if (compacto) Modifier else Modifier.fillMaxWidth())
            .defaultMinSize(minHeight = if (compacto) 44.dp else 54.dp),
        shape = CircleShape,
        colors = colores,
        elevation = if (principal) ButtonDefaults.buttonElevation() else null,
        contentPadding = PaddingValues(horizontal = if (compacto) 16.dp else 20.dp, vertical = 8.dp),
    ) {
        if (cargando) {
            CircularProgressIndicator(Modifier.size(20.dp), color = if (principal) c.sobreMarca else c.marcaTexto, strokeWidth = 2.5.dp)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (icono != null && !iconoAlFinal) Icon(icono, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(
                    texto,
                    style = if (compacto) MaterialTheme.typography.labelLarge else MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (icono != null && iconoAlFinal) Icon(icono, contentDescription = null, modifier = Modifier.size(18.dp))
            }
        }
    }
}
