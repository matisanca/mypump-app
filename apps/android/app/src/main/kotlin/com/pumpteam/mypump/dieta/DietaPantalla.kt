package com.pumpteam.mypump.dieta

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Punto
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.Macros
import com.pumpteam.mypump.modelos.TipoDia
import com.pumpteam.mypump.raiz.BannerRevision
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.SwapLocal
import com.pumpteam.mypump.respaldo.OrigenRespaldo
import com.pumpteam.mypump.respaldo.PieRespaldo
import com.pumpteam.mypump.respaldo.RenglonFuentes
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.launch

/**
 * Dieta en modo lectura (DIE-01..04, DietaView.swift): el objetivo del día con sus macros y el respaldo científico, y cada
 * comida con sus opciones A/B/C/D (se combinan entre comidas) y los alimentos de la opción elegida. Sin "Comí / Salté"
 * (D10). Los reemplazos, la porción casera y las comidas libres son la etapa que sigue: un reemplazo hecho en otro lado
 * igual se ve (con su marca).
 */
@Composable
fun DietaPantalla(modelo: ModeloApp) {
    val fase by modelo.fase.collectAsStateWithLifecycle()
    val dieta by modelo.dieta.collectAsStateWithLifecycle()
    val tipoDia by modelo.tipoDiaFlow.collectAsStateWithLifecycle()
    val swaps by modelo.swaps.collectAsStateWithLifecycle()
    val sinRedEn by modelo.sinRedEn.collectAsStateWithLifecycle()
    // DIE-04: la opción elegida vive en memoria (y sobrevive a cambiar de pestaña o rotar); al abrir la app vuelve a A.
    var opciones by rememberSaveable { mutableStateOf(mapOf<String, Int>()) }
    val comidas = remember(dieta, tipoDia) { modelo.comidasDelDia }
    val objetivo = remember(dieta, tipoDia) { modelo.objetivo }
    val tipos = dieta?.estructura?.tiposDia.orEmpty()
    val alcance = LocalAlcanceApp.current
    var recargando by remember { mutableStateOf(false) }
    fun recargar() {
        alcance.launch {
            recargando = true
            try {
                modelo.cargar()
            } finally {
                recargando = false
            }
        }
    }

    MarcoPantalla(
        "Dieta",
        acciones = {
            if (tipos.size > 1) SelectorTipoDia(tipos, elegido = tipoDia ?: tipos[0].id, alElegir = { modelo.tipoDia = it })
        },
    ) { relleno ->
        Box(Modifier.padding(relleno).fillMaxSize()) {
            when {
                fase == ModeloApp.Fase.LISTO && comidas.isNotEmpty() -> {
                    val elegidas = totalElegido(modelo, comidas, opciones, swaps)
                    Recargable(recargando, ::recargar) {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize().testTag("dieta-lista"),
                            contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xxs, bottom = Espacio.xl),
                            verticalArrangement = Arrangement.spacedBy(Espacio.m),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            item(key = "cabecera") { Cabecera(objetivo, elegidas, Modifier.widthIn(max = AnchoLectura)) }
                            item(key = "banner") { BannerRevision(modelo, Modifier.widthIn(max = AnchoLectura)) }
                            itemsIndexed(comidas, key = { i, c -> "$i-${c.id}" }) { n, c ->
                                val o = min(opciones[c.id] ?: 0, max(c.opciones.size - 1, 0))
                                TarjetaComida(
                                    modelo = modelo,
                                    comida = c,
                                    numero = n + 1,
                                    opcion = o,
                                    swaps = swaps,
                                    alElegir = { opciones = opciones + (c.id to it) },
                                    modifier = Modifier.widthIn(max = AnchoLectura),
                                )
                            }
                            item(key = "pie") { PieRespaldo(OrigenRespaldo.DIETA, Modifier.widthIn(max = AnchoLectura).padding(top = Espacio.xxs)) }
                        }
                    }
                }
                fase == ModeloApp.Fase.LISTO && ModeloApp.Parte.DIETA in sinRedEn ->
                    EstadoVacio(
                        icono = Iconos.SinWifi,
                        titulo = "No pudimos traer tu dieta",
                        texto = "Se cortó la conexión. Probá de nuevo cuando tengas señal.",
                        accion = { BotonSecundario("Reintentar", alTocar = ::recargar, compacto = true, cargando = recargando) },
                    )
                fase == ModeloApp.Fase.LISTO ->
                    // D11: sin una dieta usable no se muestra la de ejemplo como si fuera del cliente.
                    Recargable(recargando, ::recargar) {
                        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 80.dp)) {
                            EstadoVacio(
                                icono = Iconos.Cubiertos,
                                titulo = "Todavía no hay plan de comidas",
                                texto = "Cuando Mati publique tu dieta, la vas a ver acá.",
                                modifier = Modifier.testTag("dieta-vacia"),
                            )
                        }
                    }
                fase == ModeloApp.Fase.CARGANDO ->
                    CircularProgressIndicator(Modifier.align(Alignment.Center), color = MyPump.colores.marcaTexto)
                fase == ModeloApp.Fase.SIN_SERVICIO ->
                    EstadoVacio(
                        icono = Iconos.SinWifi,
                        titulo = "Sin conexión",
                        texto = "No pudimos traer tu plan. Probá de nuevo cuando tengas señal.",
                        accion = { BotonSecundario("Reintentar", alTocar = ::recargar, compacto = true, cargando = recargando) },
                    )
                else ->
                    EstadoVacio(icono = Iconos.Link, titulo = "Entrá con tu link", texto = "Abrí el link que te pasó Mati para ver tu plan.")
            }
        }
    }
}

/** Tirar para actualizar (en la demo no hace nada: no hay red). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Recargable(recargando: Boolean, alRecargar: () -> Unit, contenido: @Composable () -> Unit) {
    PullToRefreshBox(isRefreshing = recargando, onRefresh = alRecargar, modifier = Modifier.fillMaxSize()) { contenido() }
}

/** Cuánto suman las opciones elegidas (con los reemplazos), para "Con las opciones elegidas". */
private fun totalElegido(modelo: ModeloApp, comidas: List<Comida>, opciones: Map<String, Int>, @Suppress("UNUSED_PARAMETER") swaps: Map<String, SwapLocal>): Macros =
    ModeloApp.sumar(
        comidas.flatMap { c ->
            val o = min(opciones[c.id] ?: 0, max(c.opciones.size - 1, 0))
            (c.opciones.getOrNull(o)?.alimentos ?: emptyList()).mapIndexed { i, a -> modelo.efectivo(a, c.id, o, i).alimento }
        },
    )

/** DIE-01: el tipo de día (entreno/descanso) en dietas con `tipos_dia`; se guarda para todo el teléfono (`mypump_tipo_dia`). */
@Composable
private fun SelectorTipoDia(tipos: List<TipoDia>, elegido: String, alElegir: (String) -> Unit) {
    var abierto by remember { mutableStateOf(false) }
    val actual = tipos.firstOrNull { it.id == elegido } ?: tipos[0]
    Box {
        TextButton(onClick = { abierto = true }, modifier = Modifier.testTag("tipo-dia")) {
            Icon(Iconos.Calendario, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(actual.nombre ?: actual.id, fontWeight = FontWeight.SemiBold)
        }
        DropdownMenu(expanded = abierto, onDismissRequest = { abierto = false }) {
            for (t in tipos) {
                DropdownMenuItem(
                    text = { Text(t.nombre ?: t.id, fontWeight = if (t.id == actual.id) FontWeight.SemiBold else FontWeight.Normal) },
                    onClick = {
                        alElegir(t.id)
                        abierto = false
                    },
                    leadingIcon = {
                        if (t.id == actual.id) Icon(Iconos.Verificado, contentDescription = null, tint = MyPump.colores.marcaTexto, modifier = Modifier.size(18.dp))
                    },
                    modifier = Modifier.testTag("tipo-dia-${t.id}"),
                )
            }
        }
    }
}

/**
 * El objetivo del día (no lo consumido: desde D10 no se marcan comidas). El anillo reparte las kcal objetivo entre
 * proteínas, carbos y grasas; abajo, cuánto suman las opciones elegidas y el respaldo (DIE-03).
 */
@Composable
private fun Cabecera(objetivo: Macros, elegidas: Macros, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val kcalP = (objetivo.prot ?: 0.0) * 4
    val kcalC = (objetivo.carb ?: 0.0) * 4
    val kcalG = (objetivo.fat ?: 0.0) * 9
    val total = max(kcalP + kcalC + kcalG, 1.0)
    val kcalObjetivo = objetivo.kcal ?: 0.0
    val delta = if (kcalObjetivo > 0) ((elegidas.kcal ?: 0.0) - kcalObjetivo) / kcalObjetivo * 100 else 0.0
    val macros = listOf(
        Triple("Proteínas", objetivo.prot, kcalP / total) to c.proteina,
        Triple("Carbos", objetivo.carb, kcalC / total) to c.carbohidrato,
        Triple("Grasas", objetivo.fat, kcalG / total) to c.grasa,
    )
    Tarjeta(modifier.testTag("dieta-cabecera"), espaciado = Espacio.m) {
        // Anillo y macros lado a lado si entran; si no (pantallas angostas, letra grande), uno arriba del otro con los
        // macros en tres columnas. El ancho que hace falta crece con la escala de la letra (el `ViewThatFits` de iOS).
        val escala = LocalDensity.current.fontScale
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            if (maxWidth >= 320.dp * max(1f, escala)) {
                Row(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    AnilloMacros(objetivo, macros.map { it.first.third to it.second })
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        for ((m, color) in macros) FilaMacro(m.first, m.second, m.third, color)
                    }
                }
            } else {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    AnilloMacros(objetivo, macros.map { it.first.third to it.second })
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        for ((m, color) in macros) ColumnaMacro(m.first, m.second, m.third, color, Modifier.weight(1f))
                    }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("opciones-elegidas")) {
            val dentro = abs(delta) <= 5
            Icon(
                if (dentro) Iconos.Verificado else Iconos.Alerta,
                contentDescription = null,
                tint = if (dentro) c.exito else c.alerta,
                modifier = Modifier.size(18.dp),
            )
            Text(
                buildAnnotatedString {
                    append("Con las opciones elegidas: ")
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("${Formato.miles(elegidas.kcal)} kcal") }
                    // Con espacio duro: el "%)" no queda solo en el renglón de abajo.
                    if (abs(delta) >= 0.5) append(" (${if (delta > 0) "+" else ""}${Formato.entero(delta)} %)")
                },
                style = MaterialTheme.typography.bodySmall,
            )
        }
        RenglonFuentes()
    }
}

@Composable
private fun AnilloMacros(objetivo: Macros, partes: List<Pair<Double, Color>>) {
    val c = MyPump.colores
    Box(
        modifier = Modifier.size(132.dp).semantics(mergeDescendants = true) {
            contentDescription = "${Formato.miles(objetivo.kcal)} kilocalorías por día"
        },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val grosor = 14.dp.toPx()
            val lado = size.minDimension - grosor
            val esquina = Offset((size.width - lado) / 2, (size.height - lado) / 2)
            drawArc(c.campo, 0f, 360f, useCenter = false, topLeft = esquina, size = Size(lado, lado), style = Stroke(grosor))
            var acumulado = 0.0
            val hueco = 0.012
            for ((fraccion, color) in partes) {
                if (fraccion <= 0) continue
                val desde = acumulado + hueco / 2
                val hasta = acumulado + max(fraccion - hueco / 2, hueco / 2)
                drawArc(
                    color,
                    startAngle = (-90 + desde * 360).toFloat(),
                    sweepAngle = ((hasta - desde) * 360).toFloat(),
                    useCenter = false,
                    topLeft = esquina,
                    size = Size(lado, lado),
                    style = Stroke(grosor, cap = StrokeCap.Butt),
                )
                acumulado += fraccion
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 18.dp)) {
            BasicText(
                Formato.miles(objetivo.kcal),
                style = Numeros.grande.copy(color = c.texto),
                maxLines = 1,
                autoSize = TextAutoSize.StepBased(minFontSize = 20.sp, maxFontSize = 36.sp),
            )
            Text("kcal por día", style = MaterialTheme.typography.labelSmall, color = c.textoSecundario)
        }
    }
}

@Composable
private fun FilaMacro(nombre: String, gramos: Double?, porcentaje: Double, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Punto(color)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(nombre, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
            Text("${Formato.entero(porcentaje * 100)} % de las kcal", style = MaterialTheme.typography.labelSmall, color = MyPump.colores.textoSecundario, maxLines = 1)
        }
        Text("${Formato.entero(gramos)} g", style = Numeros.mediano, maxLines = 1)
    }
}

/** Un macro en columna (cabecera angosta): nombre, gramos grandes y el porcentaje de las kcal. */
@Composable
private fun ColumnaMacro(nombre: String, gramos: Double?, porcentaje: Double, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(color.copy(alpha = 0.08f))
            .padding(10.dp)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Punto(color, 8.dp)
            Text(nombre, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = MyPump.colores.textoSecundario, maxLines = 1)
        }
        Text("${Formato.entero(gramos)} g", style = Numeros.mediano, maxLines = 1)
        Text("${Formato.entero(porcentaje * 100)} % kcal", style = MaterialTheme.typography.labelSmall, color = MyPump.colores.textoSecundario, maxLines = 1)
    }
}

/** Una comida: encabezado con su total, el selector de opción (DIE-04) y los alimentos de la opción elegida. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TarjetaComida(
    modelo: ModeloApp,
    comida: Comida,
    numero: Int,
    opcion: Int,
    @Suppress("UNUSED_PARAMETER") swaps: Map<String, SwapLocal>,
    alElegir: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = MyPump.colores
    val alimentos = (comida.opciones.getOrNull(opcion)?.alimentos ?: emptyList()).mapIndexed { i, a -> a to modelo.efectivo(a, comida.id, opcion, i) }
    val total = ModeloApp.sumar(alimentos.map { it.second.alimento })
    val nombreOpcion = comida.opciones.getOrNull(opcion)?.nombre ?: letra(opcion)
    Tarjeta(modifier.testTag("comida-${comida.id}"), espaciado = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
            Box(Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(c.marcaSuave), contentAlignment = Alignment.Center) {
                Icon(iconoComida(comida.nombre), contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(comida.nombre ?: "Comida $numero", style = MaterialTheme.typography.titleMedium.copy(fontSize = 20.sp, lineHeight = 25.sp))
                Text(
                    "Opción $nombreOpcion · ${alimentos.size} ${if (alimentos.size == 1) "alimento" else "alimentos"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = c.textoSecundario,
                    modifier = Modifier.testTag("resumen-${comida.id}"),
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(Formato.miles(total.kcal), style = Numeros.mediano)
                Text("kcal", style = MaterialTheme.typography.labelSmall, color = c.textoSecundario)
            }
        }
        if (comida.opciones.size > 1) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Opción", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = c.textoSecundario)
                SingleChoiceSegmentedButtonRow(Modifier.weight(1f)) {
                    comida.opciones.forEachIndexed { i, op ->
                        SegmentedButton(
                            selected = i == opcion,
                            onClick = { alElegir(i) },
                            shape = SegmentedButtonDefaults.itemShape(i, comida.opciones.size),
                            icon = {},
                            colors = SegmentedButtonDefaults.colors(
                                activeContainerColor = MaterialTheme.colorScheme.secondaryContainer,
                                activeContentColor = c.texto,
                                inactiveContainerColor = Color.Transparent,
                                inactiveContentColor = c.texto,
                                activeBorderColor = c.borde,
                                inactiveBorderColor = c.borde,
                            ),
                            modifier = Modifier.testTag("opcion-${comida.id}-$i"),
                        ) { Text(op.nombre ?: letra(i), fontWeight = if (i == opcion) FontWeight.SemiBold else FontWeight.Normal) }
                    }
                }
            }
        }
        Column {
            alimentos.forEachIndexed { i, (original, efectivo) ->
                FilaAlimento(original, efectivo.alimento, efectivo.sustituido, Modifier.testTag("alimento-${comida.id}-$i"))
                if (i < alimentos.size - 1) Separador()
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(c.campo.copy(alpha = c.campo.alpha * 0.6f))
                .padding(horizontal = 12.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("TOTAL", style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.5.sp), fontWeight = FontWeight.SemiBold, color = c.textoSecundario, modifier = Modifier.weight(1f))
            MacroMini("P", total.prot, c.proteina)
            MacroMini("C", total.carb, c.carbohidrato)
            MacroMini("G", total.fat, c.grasa)
        }
    }
}

/** Un alimento de la opción elegida: nombre (con la marca si está reemplazado), cantidad, kcal y macros (`renderFood`). */
@Composable
private fun FilaAlimento(original: Alimento, mostrado: Alimento, sustituido: Boolean, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Column(modifier.fillMaxWidth().padding(vertical = 10.dp).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(mostrado.nombre, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f, fill = false))
            if (sustituido) {
                Box(
                    Modifier
                        .size(20.dp)
                        .clip(CircleShape)
                        .background(c.marca)
                        .semantics { contentDescription = "Reemplazado; el del plan es ${original.nombre}" },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Iconos.Intercambio, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(13.dp))
                }
            }
        }
        Text(
            "${FormatoDieta.cantidad(mostrado.qty, mostrado.unidad)} · ${Formato.miles(mostrado.kcal)} kcal",
            style = MaterialTheme.typography.bodyMedium,
            color = c.textoSecundario,
        )
        Text(FormatoDieta.macros(mostrado, c.proteina, c.carbohidrato, c.grasa), style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
    }
}

@Composable
private fun MacroMini(letra: String, valor: Double?, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Punto(color, 7.dp)
        Text(letra, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MyPump.colores.textoSecundario)
        Text("${Formato.entero(valor)} g", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Medium))
    }
}

private fun letra(i: Int): String = if (i in 0..25) ('A' + i).toString() else "?"

/** El ícono de cada comida por su nombre (como `iconoComida` de iOS). */
private fun iconoComida(nombre: String?): ImageVector {
    val n = (nombre ?: "").lowercase()
    return when {
        "desayuno" in n -> Iconos.Amanecer
        "almuerzo" in n -> Iconos.Sol
        "merienda" in n -> Iconos.Taza
        "cena" in n -> Iconos.Luna
        "pre" in n || "post" in n || "entreno" in n -> Iconos.Rayo
        "colaci" in n || "snack" in n -> Iconos.Hoja
        else -> Iconos.Cubiertos
    }
}

/** Cómo se escriben cantidades y macros en Dieta (FormatoDieta de iOS). */
object FormatoDieta {
    /**
     * "2 unidades", "110 g", "1 rebanada": la web imprime `qty unit` crudo ("2 unidad"); acá se pluraliza solo lo que es
     * palabra (las unidades reales de los planes: g, unidad, rebanada, ml, vianda, cuchara, scoop).
     */
    fun cantidad(q: Double?, u: String?): String {
        val unidad = u ?: "g"
        if (q == null) return unidad
        return "${Formato.decimal(q)} ${if (q == 1.0) unidad else plural(unidad)}"
    }

    fun plural(u: String): String {
        val l = u.lowercase()
        if (l in setOf("g", "gr", "kg", "ml", "l", "cc", "mg", "oz") || l.endsWith(".") || u.length <= 2) return u
        if (l.endsWith("s")) return u
        if (l.endsWith("ón")) return u.dropLast(2) + "ones"
        if (l.endsWith("on")) return u + "es"
        if (l.isNotEmpty() && l.last() in "aeiouáéó") return u + "s"
        if (l.endsWith("d") || l.endsWith("r") || l.endsWith("l") || l.endsWith("n")) return u + "es"
        return u + "s"
    }

    /** "P 15,1 · C 0,8 · G 11,4", con la letra en el color del macro (como el anillo de arriba). */
    fun macros(a: Alimento, proteina: Color, carbohidrato: Color, grasa: Color): AnnotatedString = buildAnnotatedString {
        fun parte(letra: String, v: Double?, color: Color) {
            withStyle(SpanStyle(color = color, fontWeight = FontWeight.Bold)) { append(letra) }
            append(" ${Formato.decimal(v ?: 0.0)}")
        }
        parte("P", a.prot, proteina)
        append("  ·  ")
        parte("C", a.carb, carbohidrato)
        append("  ·  ")
        parte("G", a.fat, grasa)
    }
}
