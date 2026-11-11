package com.pumpteam.mypump.entreno

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloFeedback
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Segmentado
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.EjercicioEfectivo
import com.pumpteam.mypump.reglas.FiguraCuerpo
import com.pumpteam.mypump.reglas.ReglasMolestia
import com.pumpteam.mypump.reglas.TextosFeedback as T
import java.util.UUID
import kotlinx.coroutines.launch

// «Me duele» por ejercicio (2.3.0, palanca `me_duele`). Gemelo de MeDueleView.swift: los mismos textos, el mismo dibujo y el
// mismo recorrido. No escribe comentarios: es un aviso aparte que le llega a Mati.

/** ¿Se ofrece «Me duele» en este ejercicio? Con la palanca apagada o sin el servidor nuevo, nunca. Ni en calentamiento ni en cardio. */
@Composable
internal fun ofreceMeDuele(feedback: ModeloFeedback?, lugar: String, tipo: String?): Boolean {
    val f = feedback ?: return false
    val estado by f.estado.collectAsStateWithLifecycle()
    val e = estado ?: return false
    // Con una molestia ya avisada se corrige desde su tarjeta.
    return e.dueleHabilitado && e.molestia(lugar)?.abierta != true && tipo != "calentamiento" && tipo != "cardio"
}

/** El nombre que lee quien cambia el ejercicio: el que está haciendo y, si lo sustituyó, también el del plan. */
internal fun nombreParaAvisar(e: EjercicioEfectivo): String {
    val original = e.nombreOriginal
    if (!e.sustituido || original.isNullOrEmpty() || original == e.ejercicio.nombre) return e.ejercicio.nombre
    return "${e.ejercicio.nombre} (en lugar de $original)"
}

// ── En la página del ejercicio ──

/**
 * Lo que «Me duele» deja a la vista en el ejercicio: la molestia avisada (o ya revisada) y «Cambiar». Sin molestia, nada: el
 * botón vive en la fila de acciones. Con la palanca apagada o sin el servidor nuevo, no existe.
 */
@Composable
internal fun EstadoMolestia(feedback: ModeloFeedback?, lugar: String, alAbrir: () -> Unit) {
    val f = feedback ?: return
    val estado by f.estado.collectAsStateWithLifecycle()
    val e = estado ?: return
    if (!e.dueleHabilitado) return
    val m = e.molestia(lugar) ?: return
    val c = MyPump.colores
    val tono = if (m.abierta) c.alerta else c.exito
    Row(
        Modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .padding(start = 14.dp, top = 10.dp, bottom = 10.dp, end = if (m.abierta) 6.dp else 14.dp)
            .testTag(if (m.abierta) "duele-avisada" else "duele-resuelta"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(tono.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
            Icon(if (m.abierta) Iconos.Curita else Iconos.TildeEnCirculo, contentDescription = null, tint = tono, modifier = Modifier.size(22.dp))
        }
        Column(Modifier.weight(1f).padding(vertical = 4.dp).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(if (m.abierta) T.dueleAvisada else T.dueleResuelta, style = Letras.subtitulo, fontWeight = FontWeight.SemiBold, color = c.texto)
            Text(
                if (m.abierta) "${m.nombreZona}. ${T.dueleListo}" else "${m.nombreZona}.",
                style = Letras.subtitulo,
                color = c.textoSecundario,
                modifier = Modifier.testTag("duele-estado-detalle"),
            )
        }
        if (m.abierta) {
            Box(
                Modifier
                    .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
                    .clip(CircleShape)
                    .clickable(role = Role.Button, onClick = alAbrir)
                    .padding(horizontal = 10.dp)
                    .testTag("duele-cambiar"),
                contentAlignment = Alignment.Center,
            ) {
                Text(T.dueleCambiar, style = Letras.subtitulo, fontWeight = FontWeight.SemiBold, color = c.marcaTexto)
            }
        }
    }
}

// ── La hoja ──

private val GuardaBorrador: Saver<ReglasMolestia.Borrador, Any> = listSaver(
    save = { listOf(it.zona, it.lado, it.desde, it.cuando, it.tipo, it.intensidad, it.nota) },
    restore = { ReglasMolestia.Borrador(it[0] as String?, it[1] as String?, it[2] as String?, it[3] as String?, it[4] as String?, it[5] as Int?, it[6] as String) },
)

/**
 * «Me duele»: dónde (el dibujo), desde cuándo, en qué parte del movimiento, cómo es y cuánto. Un solo envío; si ya había una
 * abierta para este ejercicio, la corrige.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
internal fun HojaMeDuele(modelo: ModeloFeedback, lugar: String, ejercicioNombre: String, diaId: String?, version: String?, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val alcanceApp = LocalAlcanceApp.current
    val alcanceHoja = rememberCoroutineScope()
    val foco = LocalFocusManager.current
    val toque = LocalHapticFeedback.current
    // Lo que ya avisó, tomado una vez al abrir: corregir abre con eso y repite su id.
    val previa = remember(lugar) { modelo.molestia(lugar)?.takeIf { it.abierta } }
    var borrador by rememberSaveable(lugar, stateSaver = GuardaBorrador) { mutableStateOf(previa?.let { ReglasMolestia.Borrador.de(it) } ?: ReglasMolestia.Borrador()) }
    var vista by rememberSaveable(lugar) { mutableStateOf(previa?.let { FiguraCuerpo.vista(it.zona) } ?: FiguraCuerpo.Vista.FRENTE) }
    // El mismo id en cada reintento: el servidor no duplica.
    val id = rememberSaveable(lugar) { previa?.id ?: UUID.randomUUID().toString() }
    val corrige = rememberSaveable(lugar) { previa != null }
    var enviando by remember { mutableStateOf(false) }
    var enviada by rememberSaveable(lugar) { mutableStateOf(false) }
    var fallo by rememberSaveable(lugar) { mutableStateOf<String?>(null) }
    val enviandoAhora by rememberUpdatedState(enviando)
    // Mientras viaja, la hoja no se cierra arrastrando: el aviso tiene que decir si llegó.
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { !enviandoAhora })

    fun cerrar() {
        if (enviando) return
        foco.clearFocus()
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    fun enviar() {
        if (!borrador.completa || enviando) return
        enviando = true
        fallo = null
        foco.clearFocus()
        val b = borrador
        alcanceApp.launch {
            val r = modelo.avisar(id, lugar, ejercicioNombre, diaId, b, version)
            enviando = false
            when (r) {
                ModeloFeedback.Salida.OK -> {
                    toque.performHapticFeedback(HapticFeedbackType.LongPress)
                    enviada = true
                }
                ModeloFeedback.Salida.SIN_SENAL -> fallo = T.dueleSinRed
                ModeloFeedback.Salida.TOPE -> fallo = T.dueleTope
                ModeloFeedback.Salida.ERROR -> fallo = T.dueleError
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = { if (!enviando) alCerrar() },
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-me-duele"),
    ) {
        EncabezadoHoja(T.dueleTitulo, cancelar = AccionHoja(T.cerrar, "duele-cerrar", habilitada = !enviando, alTocar = ::cerrar))
        AnimatedContent(enviada, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "me-duele") { lista ->
            if (lista) {
                Recibido(fuerte = ReglasMolestia.esFuerte(borrador.intensidad ?: 0), alCerrar = ::cerrar)
            } else {
                Column(Modifier.fillMaxWidth().imePadding(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Column(
                        Modifier
                            .weight(1f, fill = false)
                            .verticalScroll(rememberScrollState())
                            .widthIn(max = AnchoLectura)
                            .fillMaxWidth()
                            .padding(horizontal = Espacio.m)
                            .padding(top = Espacio.xs, bottom = Espacio.l),
                        verticalArrangement = Arrangement.spacedBy(Espacio.l),
                    ) {
                        Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(NombreEjercicio(ejercicioNombre).principal, style = Letras.titulo2, color = c.texto, modifier = Modifier.semantics { heading() })
                            Text(T.dueleIntro, style = Letras.subtitulo, color = c.textoSecundario)
                        }
                        Donde(borrador, vista, alCambiarVista = { vista = it }) { nuevo ->
                            borrador = nuevo
                            fallo = null
                        }
                        Pregunta(T.dueleDesde, ReglasMolestia.desde, borrador.desde, "duele-desde") { borrador = borrador.copy(desde = it); fallo = null }
                        Pregunta(T.dueleCuando, ReglasMolestia.cuando, borrador.cuando, "duele-cuando") { borrador = borrador.copy(cuando = it); fallo = null }
                        Pregunta(T.dueleTipo, ReglasMolestia.tipo, borrador.tipo, "duele-tipo") { borrador = borrador.copy(tipo = it); fallo = null }
                        Cuanto(borrador.intensidad) {
                            borrador = borrador.copy(intensidad = it)
                            fallo = null
                        }
                        Tarjeta {
                            Box(Modifier.fillMaxWidth().heightIn(min = 72.dp).clip(RoundedCornerShape(Radio.control)).background(c.campo).padding(Espacio.s)) {
                                if (borrador.nota.isEmpty()) {
                                    Text(T.dueleNota, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario, modifier = Modifier.clearAndSetSemantics {})
                                }
                                BasicTextField(
                                    value = borrador.nota,
                                    onValueChange = { borrador = borrador.copy(nota = ReglasMolestia.nota(it)) },
                                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
                                    cursorBrush = SolidColor(c.marcaTexto),
                                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                                    maxLines = 5,
                                    modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).testTag("duele-nota").semantics { contentDescription = T.dueleNota },
                                )
                            }
                        }
                    }
                    Pie(completa = borrador.completa, enviando = enviando, corrige = corrige, fallo = fallo, alEnviar = ::enviar)
                }
            }
        }
    }
}

/** Lo que queda fijo abajo: qué falta o qué falló, y el botón. */
@Composable
private fun Pie(completa: Boolean, enviando: Boolean, corrige: Boolean, fallo: String?, alEnviar: () -> Unit) {
    val c = MyPump.colores
    Column(
        Modifier
            .fillMaxWidth()
            .background(c.fondo)
            .navigationBarsPadding()
            .widthIn(max = AnchoLectura)
            .padding(horizontal = Espacio.m)
            .padding(top = Espacio.s, bottom = Espacio.xs),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (fallo != null) {
            Row(
                Modifier.semantics(mergeDescendants = true) {}.testTag("duele-fallo"),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Iconos.Alerta, contentDescription = null, tint = c.alerta, modifier = Modifier.size(18.dp))
                Text(fallo, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = c.alerta)
            }
        } else if (!completa) {
            Text(T.dueleFalta, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario, textAlign = TextAlign.Center, modifier = Modifier.testTag("duele-falta"))
        }
        BotonMarca(if (corrige) T.dueleCorregir else T.dueleEnviar, alTocar = alEnviar, habilitado = completa, cargando = enviando, modifier = Modifier.testTag("duele-enviar"))
    }
}

/** «Ya me llegó». Desde «Mucho», también la línea de dejar el ejercicio por hoy. */
@Composable
private fun Recibido(fuerte: Boolean, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val entrada = remember { Animatable(0.6f) }
    LaunchedEffect(Unit) { entrada.animateTo(1f, spring(dampingRatio = 0.5f, stiffness = 380f)) }
    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(Espacio.l)
            .testTag("duele-recibido"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Espacio.m),
    ) {
        Spacer(Modifier.height(Espacio.l))
        Icon(
            Iconos.TildeEnCirculo,
            contentDescription = null,
            tint = c.marca,
            modifier = Modifier.size(64.dp).graphicsLayer {
                scaleX = entrada.value
                scaleY = entrada.value
            },
        )
        Text(T.dueleListoTitulo, style = Letras.titulo2, color = c.texto, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Text(T.dueleListo, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario, textAlign = TextAlign.Center)
            if (fuerte) {
                Text(
                    T.dueleListoFuerte,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = c.textoSecundario,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.testTag("duele-listo-fuerte"),
                )
            }
        }
        Spacer(Modifier.height(Espacio.l))
        BotonMarca(T.listo, alTocar = alCerrar, modifier = Modifier.widthIn(max = AnchoLectura).testTag("duele-listo"))
    }
}

// ── Piezas ──

@Composable
private fun TituloPregunta(texto: String) {
    Text(texto, style = MaterialTheme.typography.titleMedium, color = MyPump.colores.texto, modifier = Modifier.semantics { heading() })
}

/** Una pregunta de una sola respuesta, en su tarjeta. */
@Composable
private fun Pregunta(titulo: String, opciones: List<ReglasMolestia.Opcion>, elegida: String?, prefijo: String, alElegir: (String) -> Unit) {
    Tarjeta {
        TituloPregunta(titulo)
        Opciones(opciones, elegida, prefijo, alElegir = alElegir)
    }
}

/** Las opciones como píldoras que saltan de renglón: con letra grande no se corta nada. Cada una, de 48 de alto. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Opciones(
    opciones: List<ReglasMolestia.Opcion>,
    elegida: String?,
    prefijo: String,
    modifier: Modifier = Modifier,
    centradas: Boolean = false,
    alElegir: (String) -> Unit,
) {
    val c = MyPump.colores
    val toque = LocalHapticFeedback.current
    FlowRow(
        modifier.fillMaxWidth().selectableGroup(),
        horizontalArrangement = Arrangement.spacedBy(8.dp, if (centradas) Alignment.CenterHorizontally else Alignment.Start),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        for (o in opciones) {
            val si = elegida == o.id
            val fondo by animateColorAsState(if (si) c.marca else c.campo, label = "opcion")
            Box(
                Modifier
                    .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
                    .clip(CircleShape)
                    .background(fondo)
                    .selectable(selected = si, role = Role.RadioButton) {
                        toque.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        alElegir(o.id)
                    }
                    .padding(horizontal = 16.dp, vertical = 10.dp)
                    .testTag("$prefijo-${o.id}"),
                contentAlignment = Alignment.Center,
            ) {
                Text(o.texto, style = Letras.subtitulo, fontWeight = FontWeight.SemiBold, color = if (si) c.sobreMarca else c.texto, textAlign = TextAlign.Center)
            }
        }
    }
}

/** El dibujo: tocar una parte da la zona y el lado de una vez. */
@Composable
private fun Donde(borrador: ReglasMolestia.Borrador, vista: FiguraCuerpo.Vista, alCambiarVista: (FiguraCuerpo.Vista) -> Unit, alCambiar: (ReglasMolestia.Borrador) -> Unit) {
    val c = MyPump.colores
    Tarjeta {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            TituloPregunta(T.dueleDonde)
            Text(T.dueleDondeAyuda, style = Letras.subtitulo, color = c.textoSecundario)
        }
        Segmentado(
            listOf(T.dueleFrente, T.dueleEspalda),
            elegida = FiguraCuerpo.Vista.entries.indexOf(vista),
            alElegir = { alCambiarVista(FiguraCuerpo.Vista.entries[it]) },
            // De 48 de alto para el dedo, como el resto de la hoja.
            modifier = Modifier.height(48.dp).testTag("duele-vista"),
            etiquetaPrueba = { "duele-vista-${FiguraCuerpo.Vista.entries[it].clave}" },
        )
        DibujoCuerpo(vista, borrador.zona, borrador.lado) { p ->
            val z = p.zona ?: return@DibujoCuerpo
            val l = p.lado ?: return@DibujoCuerpo
            // Con «los dos» elegido, tocar el otro lado de la misma zona no lo deshace.
            if (borrador.zona == z && borrador.lado == "ambos" && l != "centro") return@DibujoCuerpo
            alCambiar(borrador.copy(zona = z, lado = l))
        }
        borrador.nombreZona?.let { nombre ->
            Row(
                Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(Espacio.xs, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marca, modifier = Modifier.size(20.dp))
                Text(nombre, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.testTag("duele-zona"))
            }
            if (borrador.lado != "centro") {
                Opciones(
                    ReglasMolestia.ladosParaElegir,
                    borrador.lado,
                    "duele-lado",
                    modifier = Modifier.semantics { contentDescription = T.dueleLado },
                    centradas = true,
                ) { alCambiar(borrador.copy(lado = it)) }
            }
        }
    }
}

/** La escala simple: cuatro escalones, cada uno con su medidor. Con la letra grande, uno debajo del otro. */
@Composable
private fun Cuanto(intensidad: Int?, alElegir: (Int) -> Unit) {
    val c = MyPump.colores
    val toque = LocalHapticFeedback.current
    val apilados = LocalDensity.current.fontScale > 1.3f
    val escalon: @Composable (Int, ReglasMolestia.Nivel, Modifier) -> Unit = { n, nivel, m ->
        val si = intensidad == nivel.id
        val fondo by animateColorAsState(if (si) c.marca else c.campo, label = "nivel")
        Column(
            m
                .defaultMinSize(minHeight = 76.dp)
                .clip(RoundedCornerShape(Radio.control))
                .background(fondo)
                .selectable(selected = si, role = Role.RadioButton) {
                    toque.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    alElegir(nivel.id)
                }
                .padding(vertical = 12.dp, horizontal = 4.dp)
                .semantics { contentDescription = nivel.texto }
                .testTag("duele-nivel-${nivel.id}"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        ) {
            Medidor(n + 1, ReglasMolestia.niveles.size, si)
            Text(
                nivel.texto,
                style = Letras.caption,
                fontWeight = FontWeight.SemiBold,
                color = if (si) c.sobreMarca else c.texto,
                textAlign = TextAlign.Center,
                modifier = Modifier.clearAndSetSemantics {},
            )
        }
    }
    Tarjeta {
        TituloPregunta(T.dueleCuanto)
        if (apilados) {
            Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                ReglasMolestia.niveles.forEachIndexed { n, nivel -> escalon(n, nivel, Modifier.fillMaxWidth()) }
            }
        } else {
            Row(Modifier.fillMaxWidth().selectableGroup(), horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                ReglasMolestia.niveles.forEachIndexed { n, nivel -> escalon(n, nivel, Modifier.weight(1f)) }
            }
        }
    }
}

/** Barras que crecen: una, dos, tres o cuatro encendidas. */
@Composable
private fun Medidor(nivel: Int, de: Int, encendido: Boolean) {
    val c = MyPump.colores
    Row(Modifier.height(22.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom) {
        for (n in 1..de) {
            val color = when {
                n <= nivel -> if (encendido) c.sobreMarca else c.marca
                encendido -> c.sobreMarca.copy(alpha = 0.3f)
                else -> c.texto.copy(alpha = 0.14f)
            }
            Box(Modifier.width(5.dp).height((6 + n * 4).dp).clip(CircleShape).background(color))
        }
    }
}

/** El alto del dibujo en pantalla. */
private val AltoDibujo = 340.dp

/**
 * La figura, dibujada con las piezas compartidas. El dedo usa un blanco más generoso que el dibujo ([FiguraCuerpo.pieza]); para
 * TalkBack cada parte es un botón con su nombre («Hombro derecho») y su estado de elegida.
 */
@Composable
private fun DibujoCuerpo(vista: FiguraCuerpo.Vista, zona: String?, lado: String?, alTocar: (FiguraCuerpo.Pieza) -> Unit) {
    val c = MyPump.colores
    val toque = LocalHapticFeedback.current
    val piezas = FiguraCuerpo.piezas(vista)
    val tocar by rememberUpdatedState(alTocar)
    fun elegida(p: FiguraCuerpo.Pieza): Boolean = p.zona != null && p.zona == zona && (lado == "ambos" || p.lado == lado)

    BoxWithConstraints(Modifier.fillMaxWidth().height(AltoDibujo).testTag("duele-dibujo"), contentAlignment = Alignment.TopCenter) {
        val escala = minOf(maxWidth.value / FiguraCuerpo.ANCHO.toFloat(), maxHeight.value / FiguraCuerpo.ALTO.toFloat())
        val ancho = (FiguraCuerpo.ANCHO * escala).dp
        val alto = (FiguraCuerpo.ALTO * escala).dp
        Box(
            Modifier
                .size(ancho, alto)
                .pointerInput(vista) {
                    detectTapGestures { punto ->
                        val porUnidad = size.width / FiguraCuerpo.ANCHO
                        // Un margen más ancho que el de la regla: el dedo en un teléfono chico tapa más que una pieza.
                        FiguraCuerpo.pieza(vista, punto.x / porUnidad, punto.y / porUnidad, margen = 10.0)?.let {
                            toque.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            tocar(it)
                        }
                    }
                },
        ) {
            // Colores opacos (el gris ya mezclado con la tarjeta): donde dos piezas se pisan no queda una mancha más oscura.
            val normal = c.texto.copy(alpha = 0.16f).compositeOver(c.tarjeta)
            val cabeza = c.texto.copy(alpha = 0.08f).compositeOver(c.tarjeta)
            val halo = c.marca.copy(alpha = 0.35f).compositeOver(c.tarjeta)
            Canvas(Modifier.fillMaxSize().clearAndSetSemantics {}) {
                val u = size.width / FiguraCuerpo.ANCHO.toFloat()
                // Primero el cuerpo y encima lo elegido, con su halo.
                for (p in piezas) if (!elegida(p)) pieza(p, u, if (p.zona == null) cabeza else normal)
                for (p in piezas) if (elegida(p)) {
                    pieza(p, u, halo, crece = 3.dp.toPx())
                    pieza(p, u, c.marca)
                }
            }
            // Una caja por parte, en el orden del dibujo: lo que lee y activa TalkBack, y lo que buscan las pruebas.
            for (p in piezas) {
                val z = p.zona ?: continue
                val m = p.marco
                val si = elegida(p)
                Box(
                    Modifier
                        .offset((m.x * escala).dp, (m.y * escala).dp)
                        .size((m.ancho * escala).dp, (m.alto * escala).dp)
                        .semantics {
                            contentDescription = ReglasMolestia.nombreZona(z, p.lado ?: "centro")
                            role = Role.Button
                            selected = si
                            onClick {
                                tocar(p)
                                true
                            }
                        }
                        .testTag("duele-pieza-${vista.clave}-${p.id}"),
                )
            }
        }
    }
}

/** Una pieza en el lienzo: [u] son los píxeles por unidad del dibujo y [crece] la agranda (el halo de la elegida). */
private fun DrawScope.pieza(p: FiguraCuerpo.Pieza, u: Float, color: Color, crece: Float = 0f) {
    val a = p.a
    fun v(i: Int) = a[i].toFloat() * u
    when (p.forma) {
        FiguraCuerpo.Forma.ELIPSE -> drawOval(color, topLeft = Offset(v(0) - v(2) - crece, v(1) - v(3) - crece), size = Size(2 * (v(2) + crece), 2 * (v(3) + crece)))
        FiguraCuerpo.Forma.CAJA -> drawRoundRect(
            color,
            topLeft = Offset(v(0) - crece, v(1) - crece),
            size = Size(v(2) + 2 * crece, v(3) + 2 * crece),
            cornerRadius = CornerRadius(v(4) + crece),
        )
        FiguraCuerpo.Forma.CAPSULA -> drawLine(color, Offset(v(0), v(1)), Offset(v(2), v(3)), strokeWidth = 2 * (v(4) + crece), cap = StrokeCap.Round)
    }
}
