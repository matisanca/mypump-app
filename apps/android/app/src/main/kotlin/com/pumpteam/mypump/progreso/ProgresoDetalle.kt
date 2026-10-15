package com.pumpteam.mypump.progreso

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.datos.TarjetaProgreso
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.Inter
import com.pumpteam.mypump.diseno.LocalRellenoInferior
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.BarraEntreno
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.entreno.NombreEjercicio
import com.pumpteam.mypump.salud.curvaMonotona
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * El detalle de un ejercicio en Progreso (PRO-04, ProgresoDetalleView.swift): el tope y la progresión arriba, el máximo
 * por sesión en un gráfico con la marca del tope y, abajo, los últimos 8 registros (fecha, peso, reps, RIR) como la web.
 * Tocar o arrastrar el gráfico muestra el valor de esa sesión. Atrás (o la flecha) vuelve a la lista.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProgresoDetalle(t: TarjetaProgreso, alVolver: () -> Unit) {
    val c = MyPump.colores
    val nombre = NombreEjercicio(t.nombre)
    val sesiones = remember(t.filas) { VistaProgreso.sesiones(t.filas) }
    val comportamiento = TopAppBarDefaults.pinnedScrollBehavior()
    Scaffold(
        modifier = Modifier.nestedScroll(comportamiento.nestedScrollConnection).testTag("progreso-detalle"),
        containerColor = c.fondo,
        topBar = { BarraEntreno(nombre.principal, null, tituloVisible = true, comportamiento = comportamiento, alVolver = alVolver) },
    ) { relleno ->
        Column(
            Modifier.padding(relleno).fillMaxSize().verticalScroll(rememberScrollState()).testTag("progreso-detalle-contenido"),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier
                    .widthIn(max = AnchoLectura)
                    .fillMaxWidth()
                    .padding(horizontal = Espacio.m)
                    .padding(top = Espacio.xs, bottom = Espacio.xl + LocalRellenoInferior.current),
                verticalArrangement = Arrangement.spacedBy(Espacio.l),
            ) {
                Encabezado(t, nombre)
                if (sesiones.size >= 2 && VistaProgreso.conPeso(t)) GraficoMaximos(sesiones, t.resumen.tope)
                if (t.filas.isNotEmpty()) Registros(t)
            }
        }
    }
}

/** "DORSAL ANCHO · TOP", el tope en grande con el PR, y la progresión (o por qué no hay). TalkBack lo lee de una vez. */
@Composable
private fun Encabezado(t: TarjetaProgreso, nombre: NombreEjercicio) {
    val c = MyPump.colores
    val r = t.resumen
    val conPeso = VistaProgreso.conPeso(t)
    val ceja = nombre.detalle?.let { "$it · Top" } ?: "Top"
    val explicacion = when {
        !conPeso -> "Con el peso del cuerpo, el progreso está en las repeticiones."
        r.variacion == null -> "Hace falta otra sesión para ver la progresión."
        else -> null
    }
    val progresion = "de progresión en las últimas ${r.serie.size} sesiones"
    val descripcion = buildString {
        append("$ceja: ")
        append(if (conPeso) "${VistaProgreso.kg(r.tope)} kilos" else "peso corporal")
        if (r.esPR) append(", récord personal")
        append(", ")
        append(explicacion ?: "${VistaProgreso.variacion(r.variacion ?: 0.0)} $progresion")
    }
    Column(
        Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { contentDescription = descripcion }
            .testTag("progreso-encabezado"),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Text(ceja.uppercase(), style = Letras.ceja, color = c.textoSecundario)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.Bottom) {
                if (conPeso) {
                    Text(VistaProgreso.kg(r.tope), style = Numeros.gigante.merge(Letras.cifras), color = c.texto, modifier = Modifier.alignByBaseline())
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "kg",
                        style = MaterialTheme.typography.titleLarge.copy(fontFamily = Inter, fontWeight = FontWeight.SemiBold, fontSize = 22.sp),
                        color = c.textoSecundario,
                        modifier = Modifier.alignByBaseline(),
                    )
                } else {
                    Text("Peso corporal", style = MaterialTheme.typography.headlineSmall.copy(fontFamily = Inter, fontWeight = FontWeight.Bold, fontSize = 28.sp), color = c.texto)
                }
            }
            if (r.esPR) InsigniaPR(accesible = false)
        }
        if (explicacion != null) {
            Text(explicacion, style = Letras.subtitulo, color = c.textoSecundario)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                PildoraVariacion(r.variacion)
                Text(progresion, style = Letras.subtitulo, color = c.textoSecundario)
            }
        }
    }
}

/**
 * El máximo de cada sesión en el tiempo (el eje de las fechas es proporcional, como el de Charts): el área en degradé, la
 * curva, los puntos (el del tope en el color del récord), la línea punteada del tope con su rótulo y las marcas de los
 * dos ejes. Mientras se toca o se arrastra, la sesión más cercana con su peso y su fecha.
 */
@Composable
private fun GraficoMaximos(sesiones: List<VistaProgreso.Sesion>, tope: Double) {
    val c = MyPump.colores
    val medidor = rememberTextMeasurer()
    val trofeo = rememberVectorPainter(Iconos.Trofeo)
    val haptico = LocalHapticFeedback.current
    var elegida by remember(sesiones) { mutableStateOf<Int?>(null) }
    var tam by remember { mutableStateOf(IntSize.Zero) }
    val estiloEje = Letras.caption2.copy(color = c.textoSecundario).merge(Letras.cifras)
    val estiloTope = Letras.caption2.copy(fontWeight = FontWeight.Bold, color = c.record)
    val linea = c.marcaVivo
    val rejilla = c.textoSecundario.copy(alpha = 0.4f)

    val minimo = sesiones.minOf { it.kg }
    val maximo = sesiones.maxOf { it.kg }
    // Como iOS: un margen de un 30 % del rango (un kilo como mínimo) arriba y abajo.
    val margen = max((maximo - minimo) * 0.3, 1.0)
    val lo = minimo - margen
    val hi = maximo + margen
    val marcasY = remember(lo, hi) { VistaProgreso.marcas(lo, hi) }
    val desde = sesiones.first().dia
    val dias = ChronoUnit.DAYS.between(desde, sesiones.last().dia).toDouble().coerceAtLeast(1.0)
    // Tres fechas en el eje: al medio de cada tercio del período, sin repetir (como las marcas de Charts, nunca en el borde).
    val marcasX = remember(sesiones) {
        listOf(1.0 / 6, 0.5, 5.0 / 6)
            .map { f -> desde.plusDays((dias * f).roundToInt().toLong()) }
            .distinct()
    }

    // Dónde cae cada cosa en el lienzo (en px): las etiquetas del eje de los kilos van a la derecha, las fechas abajo.
    val densidad = LocalDensity.current
    val anchoEjeY = with(densidad) { 34.dp.toPx() }
    val relleno = with(densidad) { 14.dp.toPx() }
    val arriba = with(densidad) { 6.dp.toPx() }
    val altoFechas = with(densidad) { 24.dp.toPx() }
    fun derechaPlano(ancho: Float) = ancho - anchoEjeY
    fun x(d: LocalDate, ancho: Float): Float =
        relleno + (ChronoUnit.DAYS.between(desde, d) / dias).toFloat() * (derechaPlano(ancho) - 2 * relleno)
    fun y(kg: Double, alto: Float): Float = arriba + ((1 - (kg - lo) / (hi - lo)).toFloat()) * (alto - altoFechas - arriba)

    fun elegir(px: Float) {
        if (tam.width == 0) return
        val i = sesiones.indices.minByOrNull { abs(x(sesiones[it].dia, tam.width.toFloat()) - px) } ?: return
        if (i != elegida) {
            elegida = i
            haptico.performHapticFeedback(HapticFeedbackType.SegmentTick)
        }
    }

    Tarjeta(Modifier.testTag("progreso-grafico")) {
        Text("Máximo por sesión", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Box(
            Modifier
                .fillMaxWidth()
                .height(230.dp)
                .onSizeChanged { tam = it }
                .semantics { contentDescription = VistaProgreso.graficoAccesible(sesiones, tope) }
                .pointerInput(sesiones) {
                    awaitEachGesture {
                        val abajo = awaitFirstDown(requireUnconsumed = false)
                        elegir(abajo.position.x)
                        while (true) {
                            val evento = awaitPointerEvent()
                            val cambio = evento.changes.firstOrNull { it.id == abajo.id } ?: break
                            if (!cambio.pressed) break
                            // Lo horizontal es del gráfico; lo vertical sigue desplazando la pantalla.
                            val d = cambio.positionChange()
                            if (abs(d.x) > abs(d.y)) cambio.consume()
                            elegir(cambio.position.x)
                        }
                        elegida = null
                    }
                },
        ) {
            Canvas(Modifier.fillMaxSize()) {
                val ancho = size.width
                val alto = size.height
                val derecha = derechaPlano(ancho)
                val piso = alto - altoFechas
                val punteada = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 4.dp.toPx()))

                // Las marcas de los kilos: la rejilla punteada y el número a la derecha.
                for (m in marcasY) {
                    val yy = y(m, alto)
                    drawLine(rejilla, Offset(0f, yy), Offset(derecha, yy), strokeWidth = 0.5.dp.toPx(), pathEffect = punteada)
                    val r = medidor.measure(VistaProgreso.kg(m), estiloEje)
                    drawText(r, topLeft = Offset(derecha + 6.dp.toPx(), yy - r.size.height / 2f))
                }
                // Las fechas.
                for (d in marcasX) {
                    val r = medidor.measure(VistaProgreso.fechaCorta(d), estiloEje)
                    val xx = (x(d, ancho) - r.size.width / 2f).coerceIn(0f, max(0f, derecha - r.size.width))
                    drawText(r, topLeft = Offset(xx, piso + 6.dp.toPx()))
                }

                val puntos = sesiones.map { Offset(x(it.dia, ancho), y(it.kg, alto)) }
                val curva = curvaMonotona(puntos)
                val area = curvaMonotona(puntos).apply {
                    lineTo(puntos.last().x, piso)
                    lineTo(puntos.first().x, piso)
                    close()
                }
                drawPath(area, Brush.verticalGradient(listOf(linea.copy(alpha = 0.3f), linea.copy(alpha = 0f)), startY = y(maximo, alto), endY = piso))
                drawPath(curva, linea, style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))

                // El tope: la línea punteada y "🏆 Tope 58 kg" arriba, a la izquierda.
                val yTope = y(tope, alto)
                drawLine(
                    c.record.copy(alpha = 0.8f), Offset(0f, yTope), Offset(derecha, yTope),
                    strokeWidth = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())),
                )
                val rotulo = medidor.measure("Tope ${VistaProgreso.kg(tope)} kg", estiloTope)
                val lado = 11.dp.toPx()
                val yRotulo = yTope - 4.dp.toPx() - rotulo.size.height
                translate(0f, yRotulo + (rotulo.size.height - lado) / 2f) {
                    with(trofeo) { draw(Size(lado, lado), colorFilter = ColorFilter.tint(c.record)) }
                }
                drawText(rotulo, topLeft = Offset(lado + 4.dp.toPx(), yRotulo))

                for ((i, s) in sesiones.withIndex()) {
                    val esTope = s.kg == tope
                    drawCircle(if (esTope) c.record else linea, radius = (if (esTope) 4.7f else 3.1f).dp.toPx(), center = puntos[i])
                }
                // La sesión elegida: una línea vertical.
                elegida?.let { i ->
                    val xx = puntos[i].x
                    drawLine(c.textoSecundario.copy(alpha = 0.4f), Offset(xx, arriba), Offset(xx, piso), strokeWidth = 1.dp.toPx())
                }
            }
            elegida?.let { i -> Globo(sesiones[i], centro = x(sesiones[i].dia, tam.width.toFloat())) }
        }
    }
}

/** El valor de la sesión elegida, arriba del gráfico y centrado en ella (sin salirse de los bordes). */
@Composable
private fun Globo(s: VistaProgreso.Sesion, centro: Float) {
    val c = MyPump.colores
    val forma = RoundedCornerShape(12.dp)
    Column(
        Modifier
            .layout { medible, restricciones ->
                val p = medible.measure(restricciones.copy(minWidth = 0, minHeight = 0))
                layout(restricciones.maxWidth, restricciones.maxHeight) {
                    val xx = (centro.roundToInt() - p.width / 2).coerceIn(0, max(0, restricciones.maxWidth - p.width))
                    p.place(xx, 0)
                }
            }
            .shadow(8.dp, forma, ambientColor = Color(0x22000000), spotColor = Color(0x22000000))
            .clip(forma)
            .background(c.tarjeta)
            .border(1.dp, c.borde, forma)
            .padding(horizontal = 10.dp, vertical = 6.dp)
            .testTag("progreso-globo"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("${VistaProgreso.kg(s.kg)} kg", style = Numeros.chico.merge(Letras.cifras), color = c.texto)
        Text(VistaProgreso.fechaCorta(s.dia), style = Letras.caption2, color = c.textoSecundario)
    }
}

/** Los últimos 8 registros, del más nuevo al más viejo (como el detalle de la web), con el tope marcado. */
@Composable
private fun Registros(t: TarjetaProgreso) {
    val c = MyPump.colores
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Text("Últimos registros", style = Letras.titulo3, modifier = Modifier.padding(horizontal = 4.dp).semantics { heading() })
        Column(Modifier.fillMaxWidth().superficieTarjeta().testTag("progreso-tabla")) {
            FilaRegistro(listOf("Fecha", "Peso", "Reps", "RIR"), encabezado = true)
            t.filas.take(8).forEachIndexed { i, r ->
                val kg = r.pesoKg ?: 0.0
                FilaRegistro(
                    listOf(
                        VistaProgreso.fechaCorta(r.registradoEn),
                        if (kg > 0) "${VistaProgreso.kg(kg)} kg" else "—",
                        r.reps?.toString() ?: "—",
                        r.rir?.toString() ?: "—",
                    ),
                    encabezado = false,
                    destacada = kg > 0 && kg == t.resumen.tope,
                    fondo = if (i % 2 == 0) Color.Transparent else c.campo.copy(alpha = c.campo.alpha * 0.5f),
                    modifier = Modifier.testTag("progreso-registro-$i"),
                )
            }
        }
    }
}

@Composable
private fun FilaRegistro(
    celdas: List<String>,
    encabezado: Boolean,
    modifier: Modifier = Modifier,
    destacada: Boolean = false,
    fondo: Color = Color.Transparent,
) {
    val c = MyPump.colores
    Row(
        modifier
            .fillMaxWidth()
            .background(fondo)
            .padding(horizontal = Espacio.m, vertical = if (encabezado) 10.dp else 12.dp)
            .semantics(mergeDescendants = true) { if (destacada) stateDescription = "Tope" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        celdas.forEachIndexed { i, texto ->
            Row(
                Modifier.weight(1f),
                horizontalArrangement = if (i == 0) Arrangement.Start else Arrangement.spacedBy(4.dp, Alignment.End),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (i == 1 && destacada) Icon(Iconos.Trofeo, contentDescription = null, tint = c.record, modifier = Modifier.size(12.dp))
                if (encabezado) {
                    Text(
                        texto.uppercase(),
                        style = Letras.caption.copy(fontWeight = FontWeight.SemiBold),
                        color = c.textoSecundario,
                        maxLines = 1,
                        // TalkBack lee "Reps", no "R, E, P, S".
                        modifier = Modifier.semantics { contentDescription = texto },
                    )
                } else {
                    Text(texto, style = Letras.subtitulo.merge(Letras.cifras), color = c.texto, maxLines = 1)
                }
            }
        }
    }
}
