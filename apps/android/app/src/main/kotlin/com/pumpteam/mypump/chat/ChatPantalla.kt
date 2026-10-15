package com.pumpteam.mypump.chat

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusManager
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.BurbujaChat
import com.pumpteam.mypump.datos.HiloChat
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloChat
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.Archivo
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.entreno.reducirMovimiento
import com.pumpteam.mypump.progreso.BloqueEsqueleto
import com.pumpteam.mypump.progreso.esqueleto
import com.pumpteam.mypump.raiz.BannerRevision
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import kotlin.math.abs
import kotlin.math.min
import kotlinx.coroutines.launch

/**
 * El chat con Mati (CHA-01…06), gemelo de ChatView.swift: las burbujas a los costados agrupadas por autor (la colita y la
 * hora en la última del grupo; D12: el autor queda para TalkBack), separadores Hoy / Ayer / fecha, "Ver mensajes
 * anteriores" de a 30, "enviando…" y "no salió → Reintentar", y el compositor abajo. Todo sale de `ModeloChat`; en la
 * demo, el hilo vacío y nada se manda.
 *
 * Mientras se ve, el chat está abierto (CHA-04): el sondeo va cada 15 s y lo que llega de Mati queda leído. Al entrar se
 * marca leído lo que había, así baja el badge de la pestaña.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatPantalla(modelo: ModeloApp) {
    val chat by modelo.chat.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val alcance = LocalAlcanceApp.current
    val ch = chat
    DisposableEffect(ch) {
        if (ch != null) {
            ch.abierto = true
            // Si el hilo no se trajo nunca (sin red al arrancar, o la cuenta todavía cargando), se trae ya; y lo de Mati
            // queda leído.
            alcance.launch { ch.alAbrir() }
        }
        onDispose { ch?.abierto = false }
    }
    val hilo = ch?.hilo?.collectAsStateWithLifecycle()?.value ?: HiloChat(hayMas = false)
    val cargando = ch?.cargando?.collectAsStateWithLifecycle()?.value ?: false
    val sinTraer = ch?.sinTraer?.collectAsStateWithLifecycle()?.value ?: false
    // CHA-02: lo que se está escribiendo vive acá, no en el modelo: un mensaje que llega no lo pisa. Sobrevive a cambiar
    // de pestaña y a rotar.
    var texto by rememberSaveable { mutableStateOf("") }
    val haptico = LocalHapticFeedback.current
    val demo = esDemo || ch?.demo == true
    val puedeEnviar = ch != null && !ch.demo && TextosChat.sePuedeMandar(texto)
    // Afuera de la conversación: sobrevive al esqueleto. Con algo más viejo tapado arriba (`reverseLayout`: hacia adelante es
    // hacia arriba), la barra toma el color de la tarjeta, como la de iOS cuando el contenido pasa por debajo.
    val estadoLista = rememberLazyListState()
    val tapado by remember { derivedStateOf { estadoLista.canScrollForward } }

    fun enviar() {
        val c = ch ?: return
        if (!puedeEnviar) return
        val mensaje = texto
        texto = ""
        haptico.performHapticFeedback(HapticFeedbackType.ContextClick)
        // La burbuja aparece ya ("enviando…") y el mensaje sale por la cola (CHA-03).
        alcance.launch { c.enviar(mensaje) }
    }

    Scaffold(
        modifier = Modifier.testTag("chat-pantalla"),
        containerColor = MyPump.colores.fondo,
        topBar = { BarraChat(tapado) },
    ) { relleno ->
        Column(Modifier.padding(relleno).fillMaxSize().imePadding()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (cargando && hilo.mensajes.isEmpty()) {
                    EsqueletoChat()
                } else {
                    Conversacion(modelo, ch, hilo, cargando, sinTraer, estadoLista)
                }
            }
            Compositor(
                texto = texto,
                alCambiar = { texto = it },
                demo = demo,
                puedeEnviar = puedeEnviar,
                alEnviar = ::enviar,
            )
        }
    }
}

/**
 * La barra de arriba: el avatar de Mati, "Mati" y "Tu coach", al medio, como el título de iOS. Con mensajes tapados abajo
 * de ella ([tapado]) toma el color de la tarjeta.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BarraChat(tapado: Boolean) {
    val c = MyPump.colores
    val fondo by animateColorAsState(if (tapado) c.tarjeta else c.fondo, label = "barra")
    CenterAlignedTopAppBar(
        title = {
            Row(
                Modifier.semantics(mergeDescendants = true) { heading() },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                AvatarMati(30.dp)
                Column {
                    Text("Mati", style = MaterialTheme.typography.titleMedium)
                    Text("Tu coach", style = Letras.caption2, color = c.textoSecundario)
                }
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = fondo,
            scrolledContainerColor = fondo,
            titleContentColor = c.texto,
        ),
        expandedHeight = 56.dp,
    )
}

/**
 * La conversación anclada abajo (como Mensajes): lo más nuevo abajo de todo y, arriba, el banner de Revisión, el
 * encabezado y "Ver mensajes anteriores". Lo nuevo (de Mati o lo que se acaba de mandar) se ve sin buscarlo. Arrastrar la
 * lista cierra el teclado.
 */
@Composable
private fun Conversacion(modelo: ModeloApp, ch: ModeloChat?, hilo: HiloChat, cargando: Boolean, sinTraer: Boolean, estadoLista: LazyListState) {
    val alcance = LocalAlcanceApp.current
    val reducir = reducirMovimiento()
    val filas = remember(hilo.mensajes) { TextosChat.filas(hilo.mensajes).asReversed() }
    val foco = LocalFocusManager.current
    val cerrarTeclado = remember(foco) { CerrarTecladoAlArrastrar(foco) }

    val ultimo = hilo.mensajes.lastOrNull()?.id
    LaunchedEffect(ultimo) {
        if (ultimo == null) return@LaunchedEffect
        if (reducir) estadoLista.scrollToItem(0) else estadoLista.animateScrollToItem(0)
    }

    // `reverseLayout`: el índice 0 es lo de abajo de todo (el mensaje más nuevo).
    LazyColumn(
        state = estadoLista,
        reverseLayout = true,
        modifier = Modifier.fillMaxSize().nestedScroll(cerrarTeclado).testTag("chat-lista"),
        contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xxs, bottom = Espacio.s),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        items(filas, key = { it.clave }, contentType = { if (it is FilaHilo.Dia) "dia" else "mensaje" }) { f ->
            val ancho = Modifier.widthIn(max = AnchoLectura).fillMaxWidth().then(if (reducir) Modifier else Modifier.animateItem())
            when (f) {
                is FilaHilo.Dia -> SeparadorDia(f.texto, ancho)
                is FilaHilo.Mensaje -> Burbuja(
                    f.burbuja,
                    conCola = f.cierraGrupo,
                    hora = f.hora,
                    alReintentar = { alcance.launch { ch?.reintentar(f.burbuja.id) } },
                    modifier = ancho.padding(top = if (f.iniciaGrupo) Espacio.s else 2.dp),
                )
            }
        }
        if (ch != null && !ch.demo && hilo.hayMas && hilo.mensajes.isNotEmpty()) {
            item(key = "anteriores") {
                Box(Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(bottom = Espacio.xs), contentAlignment = Alignment.Center) {
                    BotonSecundario(
                        if (cargando) "Cargando…" else "Ver mensajes anteriores",
                        alTocar = { alcance.launch { ch.cargar(masViejos = true) } },
                        compacto = true,
                        tono = MyPump.colores.marcaTexto,
                        habilitado = !cargando,
                        modifier = Modifier.testTag("chat-anteriores"),
                    )
                }
            }
        }
        item(key = "encabezado") {
            Encabezado(
                vacio = hilo.mensajes.isEmpty(),
                sinTraer = sinTraer,
                porRed = ch?.sinTraerPorRed ?: true,
                cargando = cargando,
                alReintentar = { alcance.launch { ch?.cargar() } },
                modifier = Modifier.widthIn(max = AnchoLectura).fillMaxWidth(),
            )
        }
        // Como la web, arriba de todas las escenas menos Revisión (GEN-03). Sin pendientes no ocupa lugar.
        item(key = "banner") { BannerRevision(modelo, Modifier.widthIn(max = AnchoLectura).padding(top = Espacio.s)) }
    }
}

/** Arrastrar la conversación con el dedo cierra el teclado (`scrollDismissesKeyboard` de iOS); un mensaje que llega, no. */
private class CerrarTecladoAlArrastrar(private val foco: FocusManager) : NestedScrollConnection {
    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        if (source == NestedScrollSource.UserInput && abs(available.y) > 0f) foco.clearFocus()
        return Offset.Zero
    }
}

/**
 * El comienzo de la conversación. Con mensajes, una línea discreta (el avatar ya está en la barra, como en Mensajes); sin
 * mensajes, el avatar grande y para qué sirve el chat.
 */
@Composable
private fun Encabezado(
    vacio: Boolean,
    sinTraer: Boolean,
    porRed: Boolean,
    cargando: Boolean,
    alReintentar: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = MyPump.colores
    val motivo = if (porRed) "Sin conexión. Lo que escribas se manda solo cuando vuelva la señal."
    else "El servicio no responde. Lo que escribas se manda solo cuando vuelva."
    if (vacio && sinTraer) {
        // Sin red y sin haber traído nunca el hilo: no es que no haya mensajes.
        Column(
            modifier.padding(top = Espacio.xxl, bottom = Espacio.l).testTag("chat-sin-traer"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Espacio.xs),
        ) {
            Icon(Iconos.SinWifi, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(28.dp))
            Text(
                "No pudimos traer los mensajes",
                style = MaterialTheme.typography.titleMedium,
                color = c.texto,
                modifier = Modifier.padding(top = 4.dp).semantics { heading() },
            )
            Text(
                motivo,
                style = Letras.subtitulo,
                color = c.textoSecundario,
                textAlign = TextAlign.Center,
            )
            BotonMarca(
                "Reintentar",
                alTocar = alReintentar,
                compacto = true,
                habilitado = !cargando,
                modifier = Modifier.padding(top = Espacio.xs).testTag("chat-reintentar"),
            )
        }
    } else if (sinTraer) {
        // Hay burbujas (lo que se escribió sin señal) pero el hilo de antes nunca llegó: se sigue diciendo, más chico.
        Row(
            modifier.padding(top = Espacio.m, bottom = Espacio.xs).testTag("chat-sin-traer"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.xs, Alignment.CenterHorizontally),
        ) {
            Icon(Iconos.SinWifi, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(16.dp))
            Text("No pudimos traer los mensajes anteriores", style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
            TextButton(onClick = alReintentar, enabled = !cargando, modifier = Modifier.testTag("chat-reintentar")) { Text("Reintentar") }
        }
    } else if (vacio) {
        Column(
            modifier.padding(top = Espacio.xxl, bottom = Espacio.l).testTag("chat-vacio"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Espacio.xs),
        ) {
            AvatarMati(72.dp)
            Text(
                "Escribile a Mati",
                style = Letras.titulo2,
                color = c.texto,
                modifier = Modifier.padding(top = 4.dp).semantics { heading() },
            )
            Text(
                "Contale cómo venís, qué te costó esta semana o lo que necesites. Te contesta acá mismo.",
                style = Letras.subtitulo,
                color = c.textoSecundario,
                textAlign = TextAlign.Center,
            )
        }
    } else {
        Text(
            "Escribile a Mati cuando quieras. Te responde acá.",
            style = MaterialTheme.typography.bodySmall,
            color = c.textoSecundario,
            textAlign = TextAlign.Center,
            modifier = modifier.padding(top = Espacio.m, bottom = Espacio.xs).testTag("chat-encabezado"),
        )
    }
}

/** "Hoy", "Ayer" o "Lunes, 12 de octubre", arriba del primer mensaje del día. */
@Composable
private fun SeparadorDia(texto: String, modifier: Modifier = Modifier) {
    Text(
        texto,
        style = Letras.caption.copy(fontWeight = FontWeight.SemiBold),
        color = MyPump.colores.textoSecundario,
        textAlign = TextAlign.Center,
        modifier = modifier.padding(top = Espacio.l, bottom = Espacio.xs).semantics { heading() },
    )
}

/**
 * Una burbuja: las del cliente a la derecha en lima y las de Mati a la izquierda en la tarjeta (la IA llega como
 * `autor='coach'` y se ve igual, CHA-05). Las que todavía no salieron se ven más tenues con "enviando…"; las que la cola
 * abandonó, con "no salió" y Reintentar (el texto nunca se pierde). TalkBack lee "Vos: …" o "Mati: …" y el estado.
 */
@Composable
private fun Burbuja(m: BurbujaChat, conCola: Boolean, hora: String?, alReintentar: () -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val mio = !m.esDelCoach
    val forma = remember(mio, conCola) { FormaBurbuja(mia = mio, conCola = conCola) }
    val estado = when {
        m.fallo -> "No salió"
        m.pendiente -> "Enviando"
        else -> null
    }
    Column(
        modifier
            .padding(start = if (mio) 56.dp else 0.dp, end = if (mio) 0.dp else 56.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = "${if (mio) "Vos" else "Mati"}: ${m.contenido}"
                if (estado != null) stateDescription = estado
            },
        horizontalAlignment = if (mio) Alignment.End else Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Box(
            Modifier
                .alpha(if (m.pendiente && !m.fallo) 0.6f else 1f)
                .background(if (mio) c.marca else c.tarjeta, forma)
                .then(if (mio) Modifier else Modifier.border(1.dp, c.borde, forma))
                .padding(horizontal = 14.dp, vertical = 9.dp),
        ) {
            SelectionContainer {
                Text(m.contenido, style = MaterialTheme.typography.bodyLarge, color = if (mio) c.sobreMarca else c.texto)
            }
        }
        when {
            m.fallo -> Row(
                Modifier.padding(horizontal = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Iconos.Error, contentDescription = null, tint = c.peligro, modifier = Modifier.size(13.dp))
                Text("no salió", style = Letras.caption, color = c.peligro)
                Box(
                    Modifier
                        .defaultMinSize(minHeight = 32.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .clickable(role = Role.Button, onClick = alReintentar)
                        .padding(horizontal = 4.dp)
                        .testTag("chat-reintentar"),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Reintentar", style = Letras.caption.copy(fontWeight = FontWeight.SemiBold), color = c.marcaTexto)
                }
            }
            m.pendiente -> Row(
                Modifier.padding(horizontal = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(Iconos.Reloj, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(11.dp))
                Text("enviando…", style = Letras.caption2, color = c.textoTerciario)
            }
            hora != null -> Text(hora, style = Letras.caption2.merge(Letras.cifras), color = c.textoTerciario, modifier = Modifier.padding(horizontal = 6.dp))
        }
    }
}

/**
 * La burbuja: esquinas redondeadas y, en la última del grupo, la colita que sale de la esquina de abajo del lado de quien
 * habla (los mismos trazos que `FormaBurbuja` de iOS, en dp).
 */
private class FormaBurbuja(private val mia: Boolean, private val conCola: Boolean) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val radio = min(with(density) { 18.dp.toPx() }, size.height / 2)
        val caja = Path().apply { addRoundRect(RoundRect(Rect(Offset.Zero, size), CornerRadius(radio))) }
        if (!conCola) return Outline.Generic(caja)
        fun p(v: Float) = with(density) { v.dp.toPx() }
        val cola = Path()
        val (x, y) = size.width to size.height
        if (mia) {
            cola.moveTo(x - p(12f), y - p(12f))
            cola.quadraticTo(x - p(4f), y - p(1f), x + p(5f), y)
            cola.quadraticTo(x - p(8f), y + p(1f), x - p(18f), y - p(1f))
        } else {
            cola.moveTo(p(12f), y - p(12f))
            cola.quadraticTo(p(4f), y - p(1f), -p(5f), y)
            cola.quadraticTo(p(8f), y + p(1f), p(18f), y - p(1f))
        }
        cola.close()
        return Outline.Generic(Path.combine(PathOperation.Union, caja, cola))
    }
}

/** El avatar de Mati: la "M" en Archivo sobre el lima de la marca. TalkBack no lo lee (el nombre está al lado). */
@Composable
fun AvatarMati(lado: Dp, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    // La letra mide lo mismo con cualquier tamaño de letra del teléfono: el círculo no crece con ella.
    val tamLetra = with(LocalDensity.current) { (lado * 0.46f).toSp() }
    Box(
        modifier
            .size(lado)
            .clip(CircleShape)
            .background(Brush.verticalGradient(listOf(lerp(c.marca, Color.White, 0.18f), c.marca)))
            .border(1.dp, c.borde, CircleShape)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Text("M", style = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W800, fontSize = tamLetra), color = c.sobreMarca)
    }
}

/**
 * El compositor: el campo de 1 a 5 líneas y Enviar. CHA-02: pasados los 900 caracteres aparece el contador, en rojo desde
 * los 1000; por encima de 1000 Enviar se apaga (no se recorta mientras se escribe, como iOS: nunca sale más de 1000, como
 * el `maxlength` de la web). En la demo, Enviar apagado y el aviso.
 */
@Composable
private fun Compositor(texto: String, alCambiar: (String) -> Unit, demo: Boolean, puedeEnviar: Boolean, alEnviar: () -> Unit) {
    val c = MyPump.colores
    val n = remember(texto) { TextosChat.caracteres(texto) }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (demo) {
            Row(
                Modifier.semantics(mergeDescendants = true) {}.testTag("chat-demo"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Icon(Iconos.Chispas, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(13.dp))
                Text("En la demo los mensajes no se envían.", style = Letras.caption, color = c.textoSecundario)
            }
        }
        Row(
            Modifier.widthIn(max = AnchoLectura).fillMaxWidth(),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
        ) {
            BasicTextField(
                value = texto,
                onValueChange = alCambiar,
                minLines = 1,
                maxLines = 5,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
                cursorBrush = SolidColor(c.marcaTexto),
                modifier = Modifier
                    .weight(1f)
                    .semantics { contentDescription = "Escribile a Mati" }
                    .testTag("chat-campo"),
                decorationBox = { campo ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 44.dp)
                            .superficieTarjeta(radio = 22.dp)
                            .padding(horizontal = Espacio.m, vertical = 11.dp),
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        Box(Modifier.weight(1f)) {
                            if (texto.isEmpty()) {
                                Text("Escribile a Mati…", style = MaterialTheme.typography.bodyLarge, color = c.textoTerciario, modifier = Modifier.clearAndSetSemantics {})
                            }
                            campo()
                        }
                        if (n > TextosChat.AVISO) {
                            Text(
                                TextosChat.contador(n),
                                style = Letras.caption2.merge(Letras.cifras),
                                color = if (n >= TextosChat.LIMITE) c.peligro else c.textoSecundario,
                                modifier = Modifier
                                    .padding(start = 6.dp, bottom = 2.dp)
                                    .semantics { contentDescription = TextosChat.contadorAccesible(n) }
                                    .testTag("chat-contador"),
                            )
                        }
                    }
                },
            )
            BotonEnviar(puedeEnviar, alEnviar)
        }
    }
}

/** Enviar: el círculo lima con la flecha cuando hay algo para mandar; apagado, gris sobre la tarjeta. */
@Composable
private fun BotonEnviar(habilitado: Boolean, alEnviar: () -> Unit) {
    val c = MyPump.colores
    val fondo by animateColorAsState(if (habilitado) c.marca else c.tarjeta, label = "enviar")
    val flecha by animateColorAsState(if (habilitado) c.sobreMarca else c.textoSecundario, label = "flecha")
    Box(
        Modifier
            .size(44.dp)
            .then(if (habilitado) Modifier.clip(CircleShape) else Modifier.superficieTarjeta(radio = 22.dp))
            .background(fondo, CircleShape)
            .clickable(enabled = habilitado, role = Role.Button, onClick = alEnviar)
            .semantics { contentDescription = "Enviar" }
            .testTag("chat-enviar"),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Iconos.FlechaArriba, contentDescription = null, tint = flecha, modifier = Modifier.size(20.dp))
    }
}

/** El esqueleto mientras llega el hilo por primera vez: el avatar, una línea y burbujas a los dos lados. */
@Composable
private fun EsqueletoChat() {
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = Espacio.m)
            // La etiqueta antes: `esqueleto` limpia la semántica de lo que viene después.
            .testTag("chat-cargando")
            .esqueleto(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        BloqueEsqueleto(64.dp, 64.dp, Modifier.padding(top = Espacio.l), forma = CircleShape)
        BloqueEsqueleto(220.dp, 14.dp)
        repeat(5) { i ->
            Box(Modifier.widthIn(max = AnchoLectura).fillMaxWidth(), contentAlignment = if (i % 2 == 0) Alignment.CenterStart else Alignment.CenterEnd) {
                BloqueEsqueleto(if (i % 2 == 0) 240.dp else 150.dp, 38.dp, forma = RoundedCornerShape(18.dp))
            }
        }
    }
}
