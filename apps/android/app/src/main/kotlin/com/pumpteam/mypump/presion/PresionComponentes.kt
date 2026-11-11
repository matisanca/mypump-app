package com.pumpteam.mypump.presion

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.reglas.Presion
import com.pumpteam.mypump.reglas.TextosPresion
import java.time.LocalDate
import java.time.format.TextStyle as EstiloFecha
import java.util.Locale
import kotlinx.coroutines.delay

internal typealias TP = TextosPresion.T
internal typealias NP = TextosPresion.N

/** Tiempos de las esperas. Las pruebas de interfaz los acortan con [segundosDePrueba]; en la app siempre es 0. */
object TiemposPresion {
    @Volatile var segundosDePrueba: Int = 0

    fun ms(s: Int): Long = (if (segundosDePrueba > 0) minOf(segundosDePrueba, s) else s) * 1000L
}

/** Con la letra del sistema agrandada lo que va lado a lado se apila. */
@Composable
internal fun letraGrande(): Boolean = LocalDensity.current.fontScale >= 1.3f

/**
 * El marco de cada pantalla de presión: arriba, el título y un botón con texto para salir; el contenido scrollea entero (con la
 * letra más grande nada se corta) y, si hay [pie], el botón principal queda fijo por encima del teclado.
 */
@Composable
internal fun MarcoPresion(
    titulo: String,
    salir: String,
    alSalir: () -> Unit,
    etiqueta: String,
    etiquetaSalir: String = "presion-cerrar-seccion",
    pie: (@Composable ColumnScope.() -> Unit)? = null,
    contenido: @Composable ColumnScope.() -> Unit,
) {
    val c = MyPump.colores
    Column(
        Modifier
            .fillMaxSize()
            .background(c.fondo)
            // Lo que haya debajo no recibe toques.
            .pointerInput(Unit) { detectTapGestures { } }
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .testTag(etiqueta),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(horizontal = Espacio.m, vertical = Espacio.xs)) {
            BotonSecundario(salir, alSalir, Modifier.defaultMinSize(minHeight = 48.dp).testTag(etiquetaSalir), compacto = true, tono = c.marcaTexto)
            Text(
                titulo,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = c.texto,
                modifier = Modifier.fillMaxWidth().padding(top = Espacio.xs).semantics { heading() },
            )
        }
        Column(
            Modifier.weight(1f).widthIn(max = AnchoLectura).fillMaxWidth().verticalScroll(rememberScrollState()).padding(Espacio.m),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
            content = contenido,
        )
        if (pie != null) {
            Column(
                Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(horizontal = Espacio.m, vertical = Espacio.xs),
                verticalArrangement = Arrangement.spacedBy(Espacio.xs),
                content = pie,
            )
        }
    }
}

/** El botón principal: uno por pantalla, ancho completo, 56 dp como mínimo y siempre con texto. */
@Composable
internal fun BotonPresion(texto: String, etiqueta: String, modifier: Modifier = Modifier, habilitado: Boolean = true, cargando: Boolean = false, alTocar: () -> Unit) {
    BotonMarca(texto, alTocar, modifier.heightIn(min = 56.dp).testTag(etiqueta), habilitado = habilitado, cargando = cargando)
}

/** El secundario, debajo, también con texto y del mismo alto. */
@Composable
internal fun BotonPresionSecundario(texto: String, etiqueta: String, modifier: Modifier = Modifier, alTocar: () -> Unit) {
    BotonSecundario(texto, alTocar, modifier.heightIn(min = 56.dp).testTag(etiqueta))
}

/** Texto de lectura: nunca se corta, siempre a la izquierda. */
@Composable
internal fun TextoPresion(texto: String, modifier: Modifier = Modifier, estilo: TextStyle = MaterialTheme.typography.bodyLarge, secundario: Boolean = false, fuerte: Boolean = false) {
    val c = MyPump.colores
    Text(
        texto,
        style = estilo,
        fontWeight = if (fuerte) FontWeight.SemiBold else null,
        color = if (secundario) c.textoSecundario else c.texto,
        textAlign = TextAlign.Start,
        modifier = modifier.fillMaxWidth(),
    )
}

@Composable
internal fun TituloPresion(texto: String, modifier: Modifier = Modifier) {
    Text(
        texto,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        color = MyPump.colores.texto,
        modifier = modifier.fillMaxWidth().semantics { heading() },
    )
}

/** Pasos numerados, con el número en un círculo como las referencias de los dibujos. Una idea por fila. */
@Composable
internal fun PasosPresion(pasos: List<String>, modifier: Modifier = Modifier, desde: Int = 1) {
    val c = MyPump.colores
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        pasos.forEachIndexed { i, p ->
            Row(
                Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "${i + desde}. $p" },
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                verticalAlignment = Alignment.Top,
            ) {
                Box(Modifier.defaultMinSize(28.dp, 28.dp).clip(CircleShape).background(c.campo), contentAlignment = Alignment.Center) {
                    Text("${i + desde}", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = c.texto, modifier = Modifier.padding(horizontal = 6.dp))
                }
                TextoPresion(p, Modifier.weight(1f))
            }
        }
    }
}

/** Sí y No: mismo tamaño y mismo color, ninguno marcado de entrada. El elegido se rellena igual sea cual sea. */
@Composable
internal fun SiNoPresion(valor: Boolean?, id: String, modifier: Modifier = Modifier, elegir: (Boolean) -> Unit) {
    val c = MyPump.colores
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        for (v in listOf(true, false)) {
            val elegido = valor == v
            Box(
                Modifier
                    .defaultMinSize(minWidth = 72.dp, minHeight = 48.dp)
                    .clip(RoundedCornerShape(Radio.control))
                    .background(if (elegido) c.texto else c.campo)
                    .selectable(selected = elegido, role = Role.RadioButton, onClick = { elegir(v) })
                    .padding(horizontal = Espacio.s, vertical = Espacio.xs)
                    .testTag("$id-${if (v) "si" else "no"}"),
                contentAlignment = Alignment.Center,
            ) {
                Text(if (v) TP.si else TP.no, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = if (elegido) c.fondo else c.texto)
            }
        }
    }
}

/** Una pregunta con Sí y No: se lee «Dolor de pecho. Sí. No.». Con letra grande los botones bajan debajo del texto. */
@Composable
internal fun FilaSiNoPresion(texto: String, valor: Boolean?, id: String, elegir: (Boolean) -> Unit) {
    if (letraGrande()) {
        Column(Modifier.fillMaxWidth().padding(vertical = Espacio.xxs).testTag(id), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            TextoPresion(texto)
            SiNoPresion(valor, id, elegir = elegir)
        }
    } else {
        Row(
            Modifier.fillMaxWidth().padding(vertical = Espacio.xxs).testTag(id),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            TextoPresion(texto, Modifier.weight(1f))
            SiNoPresion(valor, id, elegir = elegir)
        }
    }
}

/** La lista de alarma con Sí y No en cada fila (la espera de una toma de 180/120 y su recordatorio). */
@Composable
internal fun ListaAlarmaPresion(respuestas: Map<String, Boolean>, responder: (String, Boolean) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        for (codigo in Presion.alarma) {
            FilaSiNoPresion(TextosPresion.sintomas[codigo] ?: codigo, respuestas[codigo], "presion-alarma-$codigo") { responder(codigo, it) }
            if (codigo != Presion.alarma.last()) Separador()
        }
    }
}

/** Lo dice el lector de pantalla, si hay uno prendido. */
@Composable
internal fun rememberAnuncio(): (String) -> Unit {
    val vista = LocalView.current
    return remember(vista) { { texto: String -> vista.announceForAccessibility(texto) } }
}

/**
 * El temporizador. Guarda la hora de fin y no cuenta ticks: al volver del fondo muestra lo que falta de verdad. El lector de
 * pantalla lo anuncia al empezar ([voz]) y al terminar ([vozFin]), no cada segundo.
 */
@Composable
internal fun TemporizadorPresion(finMs: Long, voz: String, vozFin: String, alTerminar: () -> Unit) {
    val c = MyPump.colores
    val anunciar = rememberAnuncio()
    val terminar by rememberUpdatedState(alTerminar)
    var ahora by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(finMs) {
        if (finMs > System.currentTimeMillis()) anunciar(voz)
        // Mira la hora cada rato: si la app estuvo en el fondo, al volver ya sabe si terminó.
        while (finMs > System.currentTimeMillis()) {
            ahora = System.currentTimeMillis()
            delay(250)
        }
        ahora = System.currentTimeMillis()
        anunciar(vozFin)
        terminar()
    }
    val falta = maxOf(0L, (finMs - ahora + 999) / 1000)
    Tarjeta {
        Text(
            "%d:%02d".format(Locale.ROOT, falta / 60, falta % 60),
            style = Numeros.gigante.copy(fontSize = 48.sp, lineHeight = 54.sp),
            color = c.texto,
            textAlign = TextAlign.Center,
            maxLines = 1,
            softWrap = false,
            modifier = Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = voz }.testTag("presion-temporizador"),
        )
    }
}

/** El texto de guardia, numerado. Lo decide el teléfono y se muestra aunque no haya red. Sin colores de riesgo. */
@Composable
internal fun GuardiaPresion(porSintomas: Boolean, alCerrar: () -> Unit) {
    val anunciar = rememberAnuncio()
    val contexto = LocalContext.current
    val textos = if (porSintomas) TP.guardiaSintomas else TP.guardiaPresion
    LaunchedEffect(porSintomas) {
        CentroAvisos.cancelarRepetirPresion(contexto)
        anunciar(textos[0])
    }
    MarcoPresion(NP.titulo, NP.cerrar, alCerrar, etiqueta = "presion-guardia", etiquetaSalir = "presion-guardia-salir") {
        Tarjeta(Modifier.testTag(if (porSintomas) "presion-guardia-sintomas" else "presion-guardia-presion")) { PasosPresion(textos) }
        BotonPresion(NP.cerrar, "presion-guardia-cerrar", alTocar = alCerrar)
    }
}

/** Un dibujo del catálogo con sus referencias numeradas debajo. */
@Composable
internal fun LaminaPresion(dibujo: String, alt: String, textos: List<String>) {
    Tarjeta {
        DibujoPresion(dibujo, alt, Modifier.widthIn(max = 420.dp).fillMaxWidth().align(Alignment.CenterHorizontally))
        PasosPresion(textos)
    }
}

/**
 * Un campo con su rótulo arriba. [grande]: los de la alta, la baja y el pulso, con números de 36 sp. Solo deja escribir lo que
 * corresponde al teclado (dígitos, o dígitos con coma o punto).
 */
@Composable
internal fun CampoPresion(
    rotulo: String,
    valor: String,
    id: String,
    modifier: Modifier = Modifier,
    teclado: KeyboardType = KeyboardType.Text,
    grande: Boolean = false,
    mayusculas: Boolean = false,
    ayuda: String? = null,
    foco: FocusRequester? = null,
    accion: ImeAction = ImeAction.Next,
    alAccion: (() -> Unit)? = null,
    largoMaximo: Int = 120,
    habilitado: Boolean = true,
    /** Más de una: un campo de texto libre, que crece hasta esas líneas. */
    lineas: Int = 1,
    alCambiar: (String) -> Unit,
) {
    val c = MyPump.colores
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espacio.xxs)) {
        Text(rotulo, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = c.texto)
        BasicTextField(
            value = valor,
            onValueChange = { nuevo ->
                val limpio = when (teclado) {
                    KeyboardType.Number -> nuevo.filter { it.isDigit() }
                    KeyboardType.Decimal -> nuevo.filter { it.isDigit() || it == ',' || it == '.' }
                    else -> nuevo
                }
                alCambiar(limpio.take(largoMaximo))
            },
            textStyle = (if (grande) Numeros.grande else MaterialTheme.typography.titleMedium).copy(color = c.texto),
            enabled = habilitado,
            singleLine = lineas <= 1,
            maxLines = maxOf(1, lineas),
            cursorBrush = SolidColor(c.marcaTexto),
            keyboardOptions = KeyboardOptions(
                keyboardType = teclado,
                imeAction = accion,
                capitalization = if (mayusculas) KeyboardCapitalization.Characters else if (lineas > 1) KeyboardCapitalization.Sentences else if (teclado == KeyboardType.Text) KeyboardCapitalization.Words else KeyboardCapitalization.None,
                autoCorrectEnabled = false,
            ),
            keyboardActions = if (alAccion != null) KeyboardActions(onAny = { alAccion() }) else KeyboardActions.Default,
            modifier = Modifier
                .fillMaxWidth()
                .then(if (foco != null) Modifier.focusRequester(foco) else Modifier)
                .clip(RoundedCornerShape(Radio.control))
                .background(c.campo)
                .semantics { contentDescription = rotulo }
                .testTag(id),
            decorationBox = { campo ->
                Box(Modifier.heightIn(min = if (grande) 64.dp else 52.dp).padding(horizontal = Espacio.s, vertical = Espacio.xs), contentAlignment = Alignment.CenterStart) { campo() }
            },
        )
        if (ayuda != null) Text(ayuda, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
    }
}

internal object NumeroPresion {
    /** «35,5» o «35.5». */
    fun decimal(s: String): Double? = s.trim().replace(',', '.').takeIf { it.isNotEmpty() }?.toDoubleOrNull()?.takeIf { it.isFinite() }

    fun texto(d: Double?): String = when {
        d == null -> ""
        d == Math.rint(d) -> d.toLong().toString()
        else -> "%.1f".format(Locale.ROOT, d).replace('.', ',')
    }

    private val es = Locale.forLanguageTag("es-AR")

    /** El día «AAAA-MM-DD» como «lun 9/11». */
    fun dia(fecha: String): String = try {
        val d = LocalDate.parse(fecha.take(10))
        "${d.dayOfWeek.getDisplayName(EstiloFecha.SHORT, es).replace(".", "")} ${d.dayOfMonth}/${d.monthValue}"
    } catch (_: Exception) {
        fecha
    }

    fun diaCorto(fecha: String): String = try {
        val d = LocalDate.parse(fecha.take(10))
        "${d.dayOfMonth}/${d.monthValue}"
    } catch (_: Exception) {
        fecha
    }
}
