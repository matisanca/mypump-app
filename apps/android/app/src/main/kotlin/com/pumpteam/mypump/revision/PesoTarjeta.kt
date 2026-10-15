package com.pumpteam.mypump.revision

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.keyframes
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloRevision
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Inter
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.entreno.Ceja
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.salud.curvaMonotona
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/**
 * Peso corporal (REV-07, gemela de `PesoTarjeta.swift`): la media de 7 días es lo que importa, así que va grande; el
 * gráfico muestra los pesos del día tenues y la media como línea con degradado. Abajo, la carga del día (30-300 kg, por
 * la cola) y la tendencia contra la semana pasada. Las cuentas son las de la web (`PesoCorporal`). El gráfico es un
 * Canvas: no hay librería de gráficos.
 */
@Composable
fun PesoTarjeta(revision: ModeloRevision?, modifier: Modifier = Modifier) {
    val alcance = LocalAlcanceApp.current
    val tactil = LocalHapticFeedback.current
    val foco = LocalFocusManager.current
    val filas = revision?.salud?.collectAsStateWithLifecycle()?.value ?: emptyList()
    val fecha = revision?.fecha?.collectAsStateWithLifecycle()?.value
    val serie = remember(filas) { PesoCorporal.serie(filas) }
    val hoy = FechaLocal.hoy()
    val media7 = PesoCorporal.media(serie, hoy, 7)
    val deltaG = PesoCorporal.deltaSemanal(serie, hoy)
    val pesoDeHoy = serie.lastOrNull { it.fecha == hoy }
    var entrada by rememberSaveable { mutableStateOf("") }
    var invalido by remember { mutableStateOf(false) }
    var precargado by rememberSaveable { mutableStateOf(false) }
    var diaDeLaEntrada by rememberSaveable { mutableStateOf(fecha) }
    val sacudida = remember { Animatable(0f) }
    var errores by remember { mutableIntStateOf(0) }
    val c = MyPump.colores

    // Un "no" con la cabeza: el campo se sacude. Va en la composición (tiene el reloj de los cuadros); en el alcance de
    // la app la animación no tiene con qué medir el tiempo y se cae.
    LaunchedEffect(errores) {
        if (errores == 0) return@LaunchedEffect
        sacudida.snapTo(0f)
        sacudida.animateTo(
            0f,
            keyframes {
                durationMillis = 350
                6f at 45
                -6f at 130
                6f at 215
                -3f at 290
            },
        )
    }

    // Si ya cargó el de hoy, el campo lo muestra para corregirlo (como la web).
    LaunchedEffect(pesoDeHoy?.kg) {
        if (precargado || pesoDeHoy == null) return@LaunchedEffect
        precargado = true
        entrada = PesoCorporal.kg(pesoDeHoy.kg)
    }
    // Día nuevo: el peso de ayer no es el de hoy (antes un toque lo guardaba como el de hoy: revisión del 14-oct).
    LaunchedEffect(fecha) {
        if (fecha == null || fecha == diaDeLaEntrada) return@LaunchedEffect
        diaDeLaEntrada = fecha
        entrada = pesoDeHoy?.let { PesoCorporal.kg(it.kg) } ?: ""
        precargado = pesoDeHoy != null
        invalido = false
    }

    fun guardar() {
        val texto = entrada
        val r = revision ?: return
        alcance.launch {
            if (r.guardarPeso(texto)) {
                foco.clearFocus()
                PesoCorporal.leer(texto)?.let { entrada = PesoCorporal.kg(it) }
                tactil.performHapticFeedback(HapticFeedbackType.Confirm)
            } else {
                invalido = true
                errores += 1
                tactil.performHapticFeedback(HapticFeedbackType.Reject)
            }
        }
    }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        EncabezadoSeccion("Peso corporal")
        Tarjeta(Modifier.animateContentSize(), espaciado = Espacio.m) {
            Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Ceja("Media de 7 días")
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(media7?.let(PesoCorporal::kg) ?: "—", style = Numeros.grande, modifier = Modifier.testTag("media-7"))
                    Text(
                        "kg",
                        style = MaterialTheme.typography.titleLarge.copy(fontFamily = Inter),
                        fontWeight = FontWeight.SemiBold,
                        color = c.textoSecundario,
                        modifier = Modifier.padding(bottom = 3.dp),
                    )
                }
                if (deltaG != null) {
                    // El color es neutro: subir o bajar no es bueno ni malo sin el objetivo, y el rango objetivo no se le
                    // muestra al cliente (lo interpreta Mati).
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(
                            if (deltaG > 0) IconosRevision.Sube else if (deltaG < 0) IconosRevision.Baja else IconosRevision.Igual,
                            contentDescription = null,
                            tint = c.textoSecundario,
                            modifier = Modifier.size(16.dp),
                        )
                        Text(
                            buildAnnotatedString {
                                append("Esta semana: ")
                                withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = c.texto)) { append(PesoCorporal.textoDelta(deltaG)) }
                                append(" vs la semana pasada")
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = c.textoSecundario,
                            modifier = Modifier.testTag("delta-peso"),
                        )
                    }
                } else if (serie.isNotEmpty()) {
                    Text("Cargá tu peso unos días más para ver la tendencia semanal.", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
                }
            }

            if (serie.size >= 2) GraficoPeso(serie)

            Separador()

            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                    BasicTextField(
                        value = entrada,
                        onValueChange = {
                            entrada = it
                            invalido = false
                        },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyLarge.merge(Letras.cifras).copy(color = c.texto, fontWeight = FontWeight.SemiBold),
                        cursorBrush = SolidColor(c.marcaTexto),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { if (entrada.isNotBlank()) guardar() }),
                        modifier = Modifier
                            .weight(1f)
                            .offset { IntOffset(sacudida.value.dp.roundToPx(), 0) }
                            .semantics { contentDescription = "kg de hoy" }
                            .testTag("peso-hoy"),
                        decorationBox = { campo ->
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = 44.dp)
                                    .clip(CircleShape)
                                    .background(c.campo)
                                    // 0.dp sería el borde de pelo (1 px), no "sin borde".
                                    .then(if (invalido) Modifier.border(1.5.dp, c.peligro, CircleShape) else Modifier)
                                    .padding(horizontal = 14.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Box(Modifier.weight(1f)) {
                                    if (entrada.isEmpty()) {
                                        Text("kg de hoy", style = MaterialTheme.typography.bodyLarge, color = c.textoTerciario, modifier = Modifier.clearAndSetSemantics {})
                                    }
                                    campo()
                                }
                                Text("kg", style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario, modifier = Modifier.clearAndSetSemantics {})
                            }
                        },
                    )
                    BotonMarca(
                        if (pesoDeHoy != null) "Corregir" else "Guardar",
                        alTocar = ::guardar,
                        compacto = true,
                        habilitado = entrada.isNotBlank() && revision != null,
                        modifier = Modifier.testTag("guardar-peso"),
                    )
                }
                Text(
                    if (invalido) "Tiene que estar entre 30 y 300 kg." else "En ayunas al despertar, siempre en la misma condición.",
                    style = Letras.caption,
                    color = if (invalido) c.peligro else c.textoSecundario,
                    modifier = Modifier.testTag("pie-peso"),
                )
            }
        }
    }
}

private val ES_AR: Locale = Locale.forLanguageTag("es-AR")

/**
 * Los últimos días de peso: la media de 7 días como línea con degradado (curva monótona, como `.monotone` de Charts), el
 * peso de cada día como punto tenue y el último punto de la media marcado. Fechas cada 7 días abajo y 3 valores a la
 * derecha, como el gráfico de iOS.
 */
@Composable
private fun GraficoPeso(serie: List<PesoCorporal.Punto>) {
    val c = MyPump.colores
    val medidor = rememberTextMeasurer()
    val estiloEje = Letras.caption2.copy(color = c.textoSecundario)
    val puntos = remember(serie) {
        serie.zip(PesoCorporal.lineaMedia(serie)).mapNotNull { (p, m) -> DiaCalendario.numero(p.fecha)?.let { Triple(it, p.kg, m.kg) } }
    }
    if (puntos.size < 2) return
    val formatoDia = remember { DateTimeFormatter.ofPattern("d MMM", ES_AR) }
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(168.dp)
            .semantics { contentDescription = "Peso de los últimos ${puntos.size} días, con la media de 7 días" }
            .testTag("grafico-peso"),
    ) {
        val valores = puntos.flatMap { listOf(it.second, it.third) }
        val minimo = valores.min() - 0.3
        val maximo = valores.max() + 0.3
        val marcas = marcasY(minimo, maximo)
        val etiquetasY = marcas.map { medidor.measure(Formato.decimal(it), estiloEje) }
        val anchoEtiquetas = (etiquetasY.maxOfOrNull { it.size.width } ?: 0) + 6.dp.toPx()
        val altoEje = medidor.measure("30 sept", estiloEje).size.height + 6.dp.toPx()
        val izquierda = 4.dp.toPx()
        val derecha = size.width - anchoEtiquetas
        val arriba = 6.dp.toPx()
        val abajo = size.height - altoEje
        val d0 = puntos.first().first
        val d1 = puntos.last().first
        fun x(d: Long): Float = izquierda + if (d1 == d0) (derecha - izquierda) / 2 else ((derecha - izquierda) * (d - d0) / (d1 - d0).toFloat())
        fun y(v: Double): Float = arriba + ((abajo - arriba) * (1 - (v - minimo) / (maximo - minimo))).toFloat()

        // La grilla punteada con sus valores a la derecha.
        val punteado = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 4.dp.toPx()))
        marcas.forEachIndexed { i, v ->
            val yy = y(v)
            drawLine(c.textoSecundario.copy(alpha = 0.4f), Offset(izquierda, yy), Offset(derecha, yy), strokeWidth = 0.5.dp.toPx(), pathEffect = punteado)
            val t = etiquetasY[i]
            drawText(t, topLeft = Offset(derecha + 6.dp.toPx(), (yy - t.size.height / 2f).coerceIn(0f, size.height - t.size.height)))
        }
        // Las fechas, una por semana desde la primera. Si no entran sin pisarse (60 días en un teléfono angosto), cada dos
        // semanas, cada tres…: lo que hace Charts en iOS, que esconde las que chocan.
        val fechas = HashMap<Long, Pair<Float, TextLayoutResult>>()
        fun fecha(d: Long) = fechas.getOrPut(d) {
            val t = medidor.measure(formatoDia.format(LocalDate.ofEpochDay(d)).replace(".", ""), estiloEje)
            (x(d) - t.size.width / 2f).coerceIn(0f, derecha - t.size.width) to t
        }
        val separacion = 8.dp.toPx()
        fun entran(paso: Long): Boolean {
            var finAnterior = Float.NEGATIVE_INFINITY
            for (d in d0..d1 step paso) {
                val (xx, t) = fecha(d)
                if (xx < finAnterior + separacion) return false
                finAnterior = xx + t.size.width
            }
            return true
        }
        val paso = generateSequence(7L) { it + 7 }.first { it > d1 - d0 || entran(it) }
        for (d in d0..d1 step paso) {
            val (xx, t) = fecha(d)
            drawText(t, topLeft = Offset(xx, abajo + 6.dp.toPx()))
        }

        val linea = puntos.map { Offset(x(it.first), y(it.third)) }
        val relleno = curvaMonotona(linea).apply {
            lineTo(linea.last().x, abajo)
            lineTo(linea.first().x, abajo)
            close()
        }
        drawPath(relleno, Brush.verticalGradient(listOf(c.marcaVivo.copy(alpha = 0.28f), c.marcaVivo.copy(alpha = 0f)), startY = arriba, endY = abajo))
        drawPath(curvaMonotona(linea), c.marcaVivo, style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        for (p in puntos) drawCircle(c.textoSecundario.copy(alpha = 0.45f), radius = 2.4.dp.toPx(), center = Offset(x(p.first), y(p.second)))
        val ultimo = linea.last()
        drawCircle(c.tarjeta, radius = 5.4.dp.toPx(), center = ultimo)
        drawCircle(c.marcaVivo, radius = 3.6.dp.toPx(), center = ultimo)
    }
}

/** Unos 3 valores redondos para el eje (de a 0,1, 0,2, 0,25, 0,5, 1, 2… kg). */
internal fun marcasY(minimo: Double, maximo: Double, cuantas: Int = 3): List<Double> {
    if (maximo <= minimo) return listOf(minimo)
    val crudo = (maximo - minimo) / cuantas
    val magnitud = 10.0.pow(floor(log10(crudo)))
    val paso = listOf(1.0, 2.0, 2.5, 5.0, 10.0).map { it * magnitud }.first { it >= crudo - 1e-12 }
    val primero = ceil(minimo / paso - 1e-9) * paso
    return generateSequence(primero) { it + paso }.takeWhile { it <= maximo + 1e-9 }.map { (it / paso).roundToInt() * paso }.toList()
}
