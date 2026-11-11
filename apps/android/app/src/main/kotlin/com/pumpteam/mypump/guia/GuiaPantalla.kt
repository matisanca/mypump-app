package com.pumpteam.mypump.guia

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import java.time.ZoneId

import android.view.View
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import com.pumpteam.mypump.datos.ModeloGuia
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.ReglasAgenda
import com.pumpteam.mypump.reglas.ReglasDolor
import com.pumpteam.mypump.reglas.ReglasGuia
import com.pumpteam.mypump.reglas.ReglasNovedad
import com.pumpteam.mypump.reglas.ReglasVideo
import com.pumpteam.mypump.reglas.ReglasReproductor
import com.pumpteam.mypump.reglas.SuplementacionVista
import kotlinx.coroutines.launch

/** Ancho desde el que va a dos columnas (tablet, o un teléfono grande apaisado): el reproductor fijo y la lista al lado. */
private val DOS_COLUMNAS = 720.dp

/** La clave del campo de las dudas para la videollamada (los de video van por el id del clip). */
private const val LLAMADA = "__llamada__"

/**
 * «Tu guía» (espec §4): la cabecera, el reproductor con su duda, los capítulos plegables, las dudas para la videollamada y
 * la suplementación. Pide `entregas_app_get` al abrirse (y nunca en segundo plano). Si la cuenta deja de tener guía
 * (`ok: false`, token revocado) la sección se cierra sola, sin mensaje.
 */
@Composable
fun GuiaPantalla(modelo: ModeloGuia, control: ControlReproductor, alVolver: () -> Unit, elegirHorario: Boolean = false) {
    val guia by modelo.guia.collectAsStateWithLifecycle()
    val estado by modelo.estado.collectAsStateWithLifecycle()
    val desdeCache by modelo.desdeCache.collectAsStateWithLifecycle()
    val pendientes by modelo.pendientes.collectAsStateWithLifecycle()
    val avisos by modelo.avisos.collectAsStateWithLifecycle()
    val resumenServidor by modelo.resumen.collectAsStateWithLifecycle()
    val ocultaAMano by modelo.ocultaAMano.collectAsStateWithLifecycle()
    val completaEn by modelo.completaEn.collectAsStateWithLifecycle()
    val audios by modelo.audios.items.collectAsStateWithLifecycle()
    val agenda by modelo.agenda.agenda.collectAsStateWithLifecycle()
    val reservando by modelo.agenda.reservando.collectAsStateWithLifecycle()
    val avisoAgenda by modelo.agenda.aviso.collectAsStateWithLifecycle()
    val agendaGuardada by modelo.agenda.desdeCache.collectAsStateWithLifecycle()
    val alcance = LocalAlcanceApp.current
    // La agenda de la entrega (2.2.0): al abrir y cada vez que vuelve a primer plano con la guía a la vista; con la reserva
    // pendiente, cada 5 s hasta 60 s. Fuera de la vista no consulta.
    val ciclo = LocalLifecycleOwner.current
    LaunchedEffect(modelo, ciclo) { ciclo.repeatOnLifecycle(Lifecycle.State.RESUMED) { modelo.agenda.seguir() } }
    // Las dudas en audio (`entregas_019`): la grabación sigue al bajar la lista y se frena en segundo plano.
    AudioDudaAlrededor(modelo.audios, control)

    LaunchedEffect(modelo) { modelo.abrir() }
    LaunchedEffect(modelo, guia) { guia?.let { control.usar(modelo, it) } }
    LaunchedEffect(estado) { if (estado == ModeloGuia.Estado.NO_HAY) alVolver() }
    // Salir de la guía (o cambiar de pestaña) frena el video; girar el teléfono no (la Activity se arma de nuevo y la
    // guía vuelve a componerse, pero el reproductor vive en el ViewModel y sigue).
    val actividad = LocalContext.current.actividad()
    DisposableEffect(Unit) { onDispose { if (actividad?.isChangingConfigurations != true) control.pausar() } }
    BackHandler(enabled = control.pantallaCompleta) { control.pantallaCompleta = false }

    val textos = rememberSaveable(saver = SaverMapa) { mutableStateMapOf() }
    val mensajes = remember { mutableStateMapOf<String, Pair<String, Boolean>>() }
    val enviando = remember { mutableStateListOf<String>() }
    val despues = ReglasGuia.yaPaso(guia?.fechaEntrega)
    // Lo que volvió de las dudas: «Listo», o el texto de vuelta al campo con «No se pudo guardar».
    LaunchedEffect(avisos) {
        for (a in avisos) {
            val clave = a.video ?: LLAMADA
            when (a) {
                is ModeloGuia.AvisoDuda.Guardada -> mensajes[clave] = textoListo(a.video == null, despues) to false
                is ModeloGuia.AvisoDuda.Rechazada -> {
                    textos[clave] = devolverAlCampo(a.texto, textos[clave])
                    mensajes[clave] = (if (a.video == null) "No se pudo guardar, probá de nuevo o mandámela por el chat." else "No se pudo guardar, probá de nuevo.") to true
                }
            }
            modelo.avisoVisto(a)
        }
    }

    MarcoPantalla("Tu guía", alVolver = alVolver, modifier = Modifier.testTag("guia-pantalla")) { relleno ->
        val g = guia
        when {
            g != null -> ContenidoGuia(
                guia = g,
                control = control,
                relleno = relleno,
                desdeCache = desdeCache,
                pendientes = pendientes,
                textos = textos,
                mensajes = mensajes,
                puedeSumarLlamada = modelo.puedeSumarDudaLlamada(),
                accionEntreno = ReglasGuia.accionEntreno(resumenServidor, ocultaAMano, completaEn = completaEn),
                alAccionEntreno = modelo::ocultarDeEntreno,
                transcriptos = audios.filter { it.estado == com.pumpteam.mypump.datos.ModeloAudioDudas.Estado.TRANSCRIPTO }.mapNotNull { it.texto },
                hayAudios = audios.isNotEmpty(),
                audioLlamada = { despuesAudio, m -> AudioDudaLlamada(modelo.audios, despuesAudio, m) },
                // Sin la agenda del servidor (antes de la 021, o `ok: false`), nada de esto: la guía de la 2.1.0.
                agendaPie = agenda?.let { a ->
                    { m, irAlProximo ->
                        val faltan = ReglasAgenda.faltanAMostrar(a, g)
                        val vista = ReglasAgenda.vista(a, faltan, reservando != null)
                        Column(m, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                            if (faltan > 0 && (vista == ReglasAgenda.Vista.BLOQUEADA || vista == ReglasAgenda.Vista.NO_AUTORIZADA)) {
                                ContadorObligatorios(faltan, irAlProximo)
                            }
                            TarjetaAgenda(
                                agenda = a,
                                vista = vista,
                                faltan = faltan,
                                aviso = avisoAgenda,
                                desdeCache = agendaGuardada,
                                esDemo = modelo.agenda.esDemo,
                                zona = ZoneId.systemDefault(),
                                alIrAlProximo = irAlProximo,
                                alReservar = { f -> alcance.launch { modelo.agenda.reservar(f) } },
                                modeloAgenda = modelo.agenda,
                                elegirHorario = elegirHorario,
                            )
                        }
                    }
                },
                alEnviarDuda = { video, texto ->
                    val clave = video ?: LLAMADA
                    // Un doble toque no la manda dos veces: el campo se vacía ya (el botón queda apagado) y, mientras se
                    // encola, otro toque no hace nada. Si no se pudo encolar, el texto vuelve al campo.
                    if (clave !in enviando) {
                        enviando += clave
                        mensajes.remove(clave)
                        textos[clave] = ""
                        alcance.launch {
                            try {
                                val ok = if (video == null) modelo.enviarDudaLlamada(texto) else modelo.enviarDudaVideo(video, texto)
                                if (!ok) textos[clave] = devolverAlCampo(texto, textos[clave])
                            } finally {
                                enviando -= clave
                            }
                        }
                    }
                },
            )
            estado == ModeloGuia.Estado.SIN_RED -> EstadoVacio(
                icono = Iconos.SinWifi,
                titulo = "No pudimos traer tu guía",
                texto = "Necesitás conexión para abrirla la primera vez. Probá de nuevo cuando tengas señal.",
                modifier = Modifier.padding(relleno).testTag("guia-sin-red"),
                accion = { BotonSecundario("Reintentar", alTocar = { alcance.launch { modelo.abrir() } }, compacto = true) },
            )
            else -> Box(Modifier.padding(relleno).fillMaxSize().testTag("guia-cargando"), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = MyPump.colores.marca)
            }
        }
    }
    if (control.pantallaCompleta) PantallaCompleta(control)
}

private fun textoListo(llamada: Boolean, despues: Boolean): String = when {
    despues -> "Listo, me llega y te contesto."
    llamada -> "Listo, la vemos en la videollamada."
    else -> "Listo, me llega antes de la videollamada."
}

private val SaverMapa = listSaver<SnapshotStateMap<String, String>, String>(
    save = { m -> m.entries.flatMap { listOf(it.key, it.value) } },
    restore = { l -> mutableStateMapOf<String, String>().apply { l.chunked(2).forEach { (k, v) -> put(k, v) } } },
)

private val SaverConjunto = listSaver<SnapshotStateList<String>, String>(
    save = { it.toList() },
    restore = { mutableStateListOf<String>().apply { addAll(it) } },
)

/** Lo que va en la lista, en orden: así se sabe en qué posición está el reproductor o la fila del video que suena. */
private sealed interface Entrada {
    val clave: String

    data object SinRed : Entrada { override val clave = "sin-red" }
    data object Cabecera : Entrada { override val clave = "cabecera" }
    data object Reproductor : Entrada { override val clave = "reproductor" }
    data class Bloque(val bloque: ReglasGuia.Bloque) : Entrada { override val clave = "bloque-${bloque.clave}" }
    data class Dolor(val vista: ReglasDolor.Vista, val bloque: ReglasGuia.Bloque?) : Entrada { override val clave = "dolor" }
    data class ParteDolor(val indice: Int, val parte: ReglasDolor.Parte, val bloque: ReglasGuia.Bloque?) : Entrada {
        override val clave = "dolor-parte-$indice"
    }
    data object Llamada : Entrada { override val clave = "llamada" }
    data object Suplementacion : Entrada { override val clave = "suplementacion" }
    data object Agenda : Entrada { override val clave = "agenda" }
    data object Fin : Entrada { override val clave = "fin" }
}

@Composable
private fun ContenidoGuia(
    guia: Guia,
    control: ControlReproductor,
    relleno: PaddingValues,
    desdeCache: Boolean,
    pendientes: List<ModeloGuia.DudaPendiente>,
    textos: SnapshotStateMap<String, String>,
    mensajes: Map<String, Pair<String, Boolean>>,
    puedeSumarLlamada: Boolean,
    accionEntreno: ReglasGuia.AccionEntreno,
    alAccionEntreno: (ocultar: Boolean) -> Unit,
    alEnviarDuda: (video: String?, texto: String) -> Unit,
    transcriptos: List<String> = emptyList(),
    hayAudios: Boolean = false,
    audioLlamada: (@Composable (despues: Boolean, Modifier) -> Unit)? = null,
    /** La agenda al final (2.2.0), con «Ir al próximo video». null: el servidor no la tiene y no se muestra nada nuevo. */
    agendaPie: (@Composable (Modifier, irAlProximo: (() -> Unit)?) -> Unit)? = null,
) {
    // Los nuevos arriba, en «Novedad» (2.2.0); sin nuevos, el orden y los capítulos de siempre.
    val clips = remember(guia) { ReglasNovedad.ordenDeLaLista(guia) }
    val bloques = remember(clips) { ReglasNovedad.bloques(clips) }
    // «Lo que más te importa» y sus partes. Sin `dolor`, `reparto.resto` son todos los capítulos.
    val vistaDolor = remember(guia) { ReglasDolor.vista(guia.dolor) }
    val reparto = remember(bloques, vistaDolor) { ReglasDolor.reparto(bloques, vistaDolor) }
    val hayDudas = guia.dudasLlamada.isNotEmpty() || guia.clips.any { !it.duda.isNullOrEmpty() } || pendientes.isNotEmpty() || hayAudios
    val intro = remember(guia, hayDudas) { ReglasDolor.introduccion(guia, hayDudas) }
    // La etiqueta «Para ver antes de la entrega», solo con la agenda del servidor.
    val paraLaEntrega = remember(guia, agendaPie != null) {
        if (agendaPie == null) emptySet() else ReglasAgenda.obligatorios(guia).mapTo(HashSet()) { it.id }
    }
    val resumen = remember(guia) { ResumenGuia.de(guia) }
    val suple = remember(guia) { guia.suplementacion?.let(SuplementacionVista::armar) }
    val despues = ReglasGuia.yaPaso(guia.fechaEntrega)
    // Los capítulos abiertos: el del video que suena siempre; los demás, como los deje el cliente.
    val abiertos = rememberSaveable(saver = SaverConjunto) { mutableStateListOf() }
    val expandidas = rememberSaveable(saver = SaverConjunto) { mutableStateListOf() }
    val bloqueActual = bloques.firstOrNull { control.actual in it.indices }?.clave ?: clips.getOrNull(control.actual)?.bloque ?: "Videos"
    LaunchedEffect(bloqueActual) { if (bloqueActual !in abiertos) abiertos += bloqueActual }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        // El alto visible (sin la barra de arriba ni las pestañas): el tope del 60 % de los videos verticales.
        CompositionLocalProvider(LocalAltoVisible provides maxHeight.value) {
        val dosColumnas = maxWidth >= DOS_COLUMNAS
        // Un teléfono girado: el video a pantalla completa, como hace el sistema con los videos.
        val telefonoApaisado = !dosColumnas && maxWidth > maxHeight
        // `porGiro` vive en el control (el ViewModel): al girar, la Activity se arma de nuevo y un remember se perdía, y al
        // volver a vertical quedaba trabado en pantalla completa.
        LaunchedEffect(telefonoApaisado) {
            if (telefonoApaisado && control.clipActual != null) {
                control.porGiro = true
                control.pantallaCompleta = true
            } else if (!telefonoApaisado && control.porGiro) {
                control.porGiro = false
                control.pantallaCompleta = false
            }
        }

        val lista = rememberLazyListState()
        val alcance = LocalAlcanceApp.current
        val conAgenda = agendaPie != null
        val entradas = remember(reparto, vistaDolor, desdeCache, suple, dosColumnas, conAgenda) {
            buildList {
                if (desdeCache) add(Entrada.SinRed)
                add(Entrada.Cabecera)
                // Como en la web: en el teléfono, arriba del reproductor.
                vistaDolor?.let { v ->
                    add(Entrada.Dolor(v, reparto.principal))
                    v.partes.forEachIndexed { i, p -> add(Entrada.ParteDolor(i, p, reparto.partes.getOrNull(i))) }
                }
                if (!dosColumnas) add(Entrada.Reproductor)
                // Como la web (4/11): primero «Tu app», el recuadro de dudas para la videollamada y después los demás capítulos.
                // La novedad (2.2.0) va arriba de todo.
                reparto.resto.filter { it.esNovedad }.forEach { add(Entrada.Bloque(it)) }
                val (deLaApp, resto) = reparto.resto.filterNot { it.esNovedad }.partition { ReglasGuia.esTuApp(it.titulo) }
                deLaApp.forEach { add(Entrada.Bloque(it)) }
                add(Entrada.Llamada)
                resto.forEach { add(Entrada.Bloque(it)) }
                if (suple != null) add(Entrada.Suplementacion)
                // La agenda de la entrega, al final de todo (2.2.0).
                if (conAgenda) add(Entrada.Agenda)
                add(Entrada.Fin)
            }
        }
        // Tocar una fila en el teléfono sube al reproductor (en la tablet está siempre a la vista).
        var mostrarVolver by remember { mutableStateOf(false) }
        LaunchedEffect(control.elegido) {
            if (control.elegido > 0 && !dosColumnas) {
                val i = entradas.indexOf(Entrada.Reproductor)
                if (i >= 0) lista.animateScrollToItem(i)
                mostrarVolver = true
            }
        }
        // Con la placa (otro video), si el reproductor quedó arriba de la pantalla, vuelve a la vista.
        LaunchedEffect(control.pasado) {
            if (control.pasado > 0 && !dosColumnas) {
                val i = entradas.indexOf(Entrada.Reproductor)
                val visible = lista.layoutInfo.visibleItemsInfo.firstOrNull { it.index == i }
                if (i >= 0 && (visible == null || visible.offset < 0)) lista.animateScrollToItem(i)
            }
        }
        val volverALaLista: () -> Unit = {
            mostrarVolver = false
            val i = entradas.indexOfFirst {
                val b = when (it) {
                    is Entrada.Bloque -> it.bloque
                    is Entrada.Dolor -> it.bloque
                    is Entrada.ParteDolor -> it.bloque
                    else -> null
                }
                b != null && control.actual in b.indices
            }
            if (i >= 0) alcance.launch { lista.animateScrollToItem(i) }
        }
        // «Ver por qué»: el video del suplemento se abre debajo de él, con su duda (como pack.html, A5).
        val porQue = PorQueSuplemento(
            abierto = control.porQue,
            clip = { id -> guia.clip(id) },
            alternar = control::alternarPorQue,
            contenido = { clip ->
                VideoDelSuplemento(
                    control = control,
                    clip = clip,
                    despues = despues,
                    texto = textos[clip.id] ?: "",
                    alCambiar = { textos[clip.id] = it },
                    mensaje = mensajes[clip.id],
                    pendientes = pendientes.filter { it.video == clip.id }.map { it.texto },
                    alEnviar = { alEnviarDuda(clip.id, it) },
                )
            },
        )
        val tarjetaReproductor: @Composable (Modifier) -> Unit = { m ->
            TarjetaReproductor(
                control = control,
                despues = despues,
                textos = textos,
                mensajes = mensajes,
                pendientes = pendientes,
                alEnviarDuda = alEnviarDuda,
                volverALaLista = if (!dosColumnas && mostrarVolver) volverALaLista else null,
                modifier = m,
            )
        }

        val listaGuia: @Composable (Modifier) -> Unit = { m ->
            LazyColumn(
                state = lista,
                modifier = m.testTag("guia-lista"),
                contentPadding = PaddingValues(
                    start = Espacio.m,
                    end = Espacio.m,
                    top = if (dosColumnas) 0.dp else Espacio.xxs,
                    bottom = relleno.calculateBottomPadding() + Espacio.xl,
                ),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                entradasGuia(
                    entradas = entradas,
                    guia = guia,
                    clips = clips,
                    resumen = resumen,
                    suple = suple,
                    control = control,
                    despues = despues,
                    abiertos = abiertos,
                    expandidas = expandidas,
                    textos = textos,
                    mensajes = mensajes,
                    pendientes = pendientes,
                    puedeSumarLlamada = puedeSumarLlamada,
                    accionEntreno = accionEntreno,
                    alAccionEntreno = alAccionEntreno,
                    alEnviarDuda = alEnviarDuda,
                    transcriptos = transcriptos,
                    audioLlamada = audioLlamada,
                    porQue = porQue,
                    reproductor = tarjetaReproductor,
                    paraLaEntrega = paraLaEntrega,
                    intro = intro,
                    alPaso = { paso ->
                        val i = entradas.indexOf(if (paso.id == "videos") Entrada.Reproductor else Entrada.Llamada)
                        if (i >= 0) alcance.launch { lista.animateScrollToItem(i) } else volverALaLista()
                    },
                    agendaPie = agendaPie?.let { pie ->
                        { m ->
                            val proximo = ReglasAgenda.proximoQueFalta(guia, clips)?.let { c -> clips.indexOf(c) }?.takeIf { it >= 0 }
                            pie(m, proximo?.let { i -> { control.reproducir(i) } })
                        }
                    },
                )
            }
        }

        if (dosColumnas) {
            Row(
                Modifier.fillMaxSize().padding(top = relleno.calculateTopPadding()).padding(horizontal = Espacio.m),
                horizontalArrangement = Arrangement.spacedBy(Espacio.m),
            ) {
                Column(
                    Modifier
                        .weight(0.56f)
                        .fillMaxHeight()
                        .verticalScroll(rememberScrollState())
                        .padding(bottom = relleno.calculateBottomPadding() + Espacio.xl),
                ) { tarjetaReproductor(Modifier) }
                listaGuia(Modifier.weight(0.44f).fillMaxHeight())
            }
        } else {
            listaGuia(Modifier.fillMaxSize().padding(top = relleno.calculateTopPadding()))
        }
    }
    }
}

private fun LazyListScope.entradasGuia(
    entradas: List<Entrada>,
    guia: Guia,
    clips: List<com.pumpteam.mypump.modelos.ClipGuia>,
    resumen: ResumenGuia?,
    suple: SuplementacionVista.Vista?,
    control: ControlReproductor,
    despues: Boolean,
    abiertos: SnapshotStateList<String>,
    expandidas: SnapshotStateList<String>,
    textos: SnapshotStateMap<String, String>,
    mensajes: Map<String, Pair<String, Boolean>>,
    pendientes: List<ModeloGuia.DudaPendiente>,
    puedeSumarLlamada: Boolean,
    accionEntreno: ReglasGuia.AccionEntreno,
    alAccionEntreno: (ocultar: Boolean) -> Unit,
    alEnviarDuda: (String?, String) -> Unit,
    transcriptos: List<String>,
    audioLlamada: (@Composable (despues: Boolean, Modifier) -> Unit)?,
    porQue: PorQueSuplemento,
    reproductor: @Composable (Modifier) -> Unit,
    paraLaEntrega: Set<String> = emptySet(),
    intro: ReglasDolor.Introduccion? = null,
    alPaso: (ReglasDolor.Paso) -> Unit = {},
    agendaPie: (@Composable (Modifier) -> Unit)? = null,
) {
    val ancho = Modifier.widthIn(max = 700.dp).fillMaxWidth()
    // El capítulo plegable, suelto o adentro de un recuadro de «Lo que más te importa».
    val capitulo: @Composable (ReglasGuia.Bloque, String?, Modifier) -> Unit = { b, titulo, m ->
        val abierto = b.clave in abiertos
        val vistos = b.indices.count { clips[it].visto }
        Column(m.padding(bottom = if (abierto) Espacio.xs else 0.dp)) {
            EncabezadoBloque(
                b, vistos, abierto,
                alTocar = { if (abierto) abiertos.remove(b.clave) else abiertos.add(b.clave) },
                titulo = titulo ?: b.titulo,
            )
            if (abierto) {
                for (i in b.indices) {
                    val c = clips[i]
                    FilaClip(
                        clip = c,
                        actual = i == control.actual,
                        expandida = c.id in expandidas,
                        alTocar = { control.reproducir(i) },
                        alExpandir = { if (c.id in expandidas) expandidas.remove(c.id) else expandidas.add(c.id) },
                        paraLaEntrega = c.id in paraLaEntrega,
                    )
                }
            }
        }
    }
    for (e in entradas) {
        item(key = e.clave) {
            when (e) {
                Entrada.SinRed -> AvisoSinRed(ancho.padding(bottom = Espacio.s))
                Entrada.Cabecera -> CabeceraGuia(ReglasGuia.saludo(guia), ReglasGuia.lineaCabecera(guia), resumen, ancho.padding(bottom = Espacio.s), intro, alPaso)
                Entrada.Reproductor -> reproductor(ancho.padding(bottom = Espacio.s))
                is Entrada.Bloque -> capitulo(e.bloque, null, ancho.padding(top = Espacio.xs).superficieTarjeta())
                is Entrada.Dolor -> TarjetaDolor(
                    titulo = ReglasDolor.TITULO_BLOQUE,
                    subtitulo = e.vista.subtitulo,
                    parrafos = e.vista.parrafos,
                    etiqueta = "guia-dolor",
                    modifier = ancho.padding(bottom = Espacio.s),
                    videos = e.bloque?.let { b -> { capitulo(b, ReglasDolor.TITULO_VIDEOS, Modifier) } },
                )
                is Entrada.ParteDolor -> TarjetaDolor(
                    titulo = e.parte.titulo,
                    subtitulo = null,
                    parrafos = e.parte.parrafos,
                    etiqueta = "guia-parte-${e.indice}",
                    modifier = ancho.padding(bottom = Espacio.s),
                    videos = e.bloque?.let { b -> { capitulo(b, ReglasDolor.TITULO_VIDEOS, Modifier) } },
                )
                Entrada.Llamada -> DudasLlamada(
                    guia = guia,
                    despues = despues,
                    texto = textos[LLAMADA] ?: "",
                    alCambiar = { textos[LLAMADA] = it },
                    mensaje = mensajes[LLAMADA],
                    pendientes = pendientes.filter { it.video == null }.map { it.texto },
                    puedeSumar = puedeSumarLlamada,
                    alEnviar = { alEnviarDuda(null, it) },
                    transcriptos = transcriptos,
                    audio = audioLlamada,
                    modifier = ancho.padding(top = Espacio.m),
                )
                Entrada.Suplementacion -> suple?.let { SuplementacionGuia(it, porQue, ancho.padding(top = Espacio.m)) }
                Entrada.Agenda -> agendaPie?.invoke(ancho.padding(top = Espacio.m))
                Entrada.Fin -> Column(ancho) {
                    Text(
                        "Si algún video no te carga o tenés algo para contarme" + (if (despues) "" else " antes de la videollamada") + ", escribime por el chat.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MyPump.colores.textoSecundario,
                        modifier = Modifier.padding(top = Espacio.m, start = 4.dp, end = 4.dp).testTag("guia-fin"),
                    )
                    AccionEntrenoPie(accionEntreno, alAccionEntreno, Modifier.padding(top = Espacio.s))
                }
            }
        }
    }
}

/**
 * «Quitar de Entreno» (la tarjeta sale antes de tiempo y la guía queda en Mis datos) o, ya quitada y dentro de las 48 h,
 * «Volver a mostrar en Entreno». Discreta, al pie: un texto que se toca, sin cartel.
 */
@Composable
private fun AccionEntrenoPie(accion: ReglasGuia.AccionEntreno, alTocar: (ocultar: Boolean) -> Unit, modifier: Modifier = Modifier) {
    val (texto, ayuda, etiqueta) = when (accion) {
        ReglasGuia.AccionEntreno.NINGUNA -> return
        ReglasGuia.AccionEntreno.QUITAR -> Triple("Quitar de Entreno", "La guía queda en Mis datos", "guia-quitar-entreno")
        ReglasGuia.AccionEntreno.VOLVER_A_MOSTRAR -> Triple("Volver a mostrar en Entreno", "Ahora la encontrás en Mis datos", "guia-volver-entreno")
    }
    val c = MyPump.colores
    Column(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(role = Role.Button, onClickLabel = texto) { alTocar(accion == ReglasGuia.AccionEntreno.QUITAR) }
            .padding(horizontal = 4.dp, vertical = Espacio.xs)
            .testTag(etiqueta),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(texto, style = MaterialTheme.typography.bodyMedium, color = c.marcaTexto)
        Text(ayuda, style = MaterialTheme.typography.bodySmall, color = c.textoTerciario)
    }
}

@Composable
private fun AvisoSinRed(modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Row(
        modifier.testTag("guia-desde-cache").semantics { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(Iconos.SinWifi, contentDescription = null, tint = c.alerta, modifier = Modifier.padding(start = 4.dp))
        Text("Sin conexión. Estás viendo tu guía guardada", style = MaterialTheme.typography.labelLarge, color = c.alerta)
    }
}

/**
 * La tarjeta del reproductor: el video con la proporción del clip ([CajaVideo]; con la placa o «Necesitás conexión» encima), el número y el título, los
 * botones, lo que dice el video (qué hacer y para qué) y su duda.
 */
@Composable
private fun TarjetaReproductor(
    control: ControlReproductor,
    despues: Boolean,
    textos: SnapshotStateMap<String, String>,
    mensajes: Map<String, Pair<String, Boolean>>,
    pendientes: List<ModeloGuia.DudaPendiente>,
    alEnviarDuda: (String?, String) -> Unit,
    volverALaLista: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val c = MyPump.colores
    val clip = control.clipActual
    Column(modifier.fillMaxWidth().superficieTarjeta().testTag("guia-reproductor")) {
        // La proporción de lo que se ve: la del archivo y, si trae las franjas metidas, solo la zona útil.
        val proporcion = proporcionDe(control.player, clip?.id)
        val recorte = recorteDe(clip?.url, clip?.id)
        CajaVideo(ReglasVideo.proporcionVisible(proporcion, recorte)) {
            if (!control.pantallaCompleta) VistaVideo(control, Modifier.fillMaxSize(), recorte = recorte)
            CapasVideo(control)
        }
        if (clip == null) {
            Text(
                "Todavía no hay videos para ver.",
                style = MaterialTheme.typography.bodyMedium,
                color = c.textoSecundario,
                modifier = Modifier.padding(Espacio.m),
            )
            return@Column
        }
        Column(Modifier.padding(start = Espacio.m, end = Espacio.m, top = Espacio.s), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                (if (control.esDeSuplemento) clip.bloque?.trim() ?: "Tu suplementación"
                else ReglasReproductor.textoNumero(control.actual, control.deLaLista, clip.bloque)).uppercase(),
                style = MaterialTheme.typography.labelMedium,
                color = c.marcaTexto,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.testTag("guia-numero"),
            )
            Text(
                clip.titulo,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.semantics { heading() }.testTag("guia-titulo"),
            )
        }
        FlowRow(Modifier.padding(horizontal = Espacio.xs)) {
            if (control.hayAnterior) BotonTexto("Anterior", control::anterior, Modifier.testTag("guia-anterior"), descripcion = "Video anterior")
            if (control.haySiguiente) BotonTexto("Siguiente", control::siguiente, Modifier.testTag("guia-siguiente"), descripcion = "Siguiente video")
            BotonTexto(
                "Velocidad " + ReglasReproductor.textoVelocidad(control.velocidad),
                control::cambiarVelocidad,
                Modifier.testTag("guia-velocidad"),
            )
            if (volverALaLista != null) BotonTexto("Volver a la lista", volverALaLista, Modifier.testTag("guia-volver-lista"))
        }
        val (hacer, paraQue) = ReglasGuia.partesMotivo(clip.motivo)
        Column(Modifier.padding(start = Espacio.m, end = Espacio.m, bottom = Espacio.m), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            if (hacer != null || paraQue != null) {
                Box(Modifier.fillMaxWidth().padding(vertical = 2.dp).background(c.separador).padding(top = 1.dp))
                hacer?.let { TextoRotulado("Qué hacer.", it, tonoTexto = c.texto) }
                paraQue?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario) }
            }
            Box(Modifier.fillMaxWidth().padding(vertical = 2.dp).background(c.separador).padding(top = 1.dp))
            DudaVideo(
                video = clip.id,
                yaDejo = clip.duda,
                despues = despues,
                texto = textos[clip.id] ?: "",
                alCambiar = { textos[clip.id] = it },
                mensaje = mensajes[clip.id],
                pendientes = pendientes.filter { it.video == clip.id }.map { it.texto },
                alEnviar = { alEnviarDuda(clip.id, it) },
            )
        }
    }
}

/** La placa y «Necesitás conexión», arriba del video (en la tarjeta y en la pantalla completa). */
@Composable
private fun CapasVideo(control: ControlReproductor) {
    control.placa?.let { PlacaGuia(it, alTocar = control::cerrarPlaca) }
    control.falla?.let { if (control.placa == null) SinConexionVideo(it, alReintentar = control::reintentar) }
}

/** La vista de Media3 con sus controles (reproducir, la barra, la pantalla completa). Una sola a la vez tiene el reproductor. */
@OptIn(UnstableApi::class)
@Composable
private fun VistaVideo(control: ControlReproductor, modifier: Modifier = Modifier, completa: Boolean = false, recorte: ReglasVideo.Recuadro? = null) =
    VistaMedia3(
        recorte = recorte,
        player = control.player,
        etiqueta = if (completa) "guia-video-completo" else "guia-video",
        alPantallaCompleta = { control.pantallaCompleta = it },
        completa = completa,
        modifier = modifier,
    )

/** El video de un suplemento («Ver por qué»): el reproductor chico y, abajo, la duda de ese video. */
@Composable
private fun VideoDelSuplemento(
    control: ControlReproductor,
    clip: com.pumpteam.mypump.modelos.ClipGuia,
    despues: Boolean,
    texto: String,
    alCambiar: (String) -> Unit,
    mensaje: Pair<String, Boolean>?,
    pendientes: List<String>,
    alEnviar: (String) -> Unit,
) {
    Column(Modifier.fillMaxWidth().testTag("guia-porque-${clip.id}"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        val proporcion = proporcionDe(control.porQuePlayer, clip.id)
        val recorte = recorteDe(clip.url, clip.id)
        CajaVideo(ReglasVideo.proporcionVisible(proporcion, recorte)) {
          Box(Modifier.fillMaxSize().clip(RoundedCornerShape(10.dp)).testTag("guia-video-porque-caja")) {
            VistaMedia3(recorte = recorte, player = control.porQuePlayer, etiqueta = "guia-video-porque", alPantallaCompleta = null, completa = false, modifier = Modifier.fillMaxSize())
            control.fallaPorQue?.let { SinConexionVideo(it, alReintentar = control::reintentarPorQue) }
          }
        }
        DudaVideo(
            video = clip.id,
            yaDejo = clip.duda,
            despues = despues,
            texto = texto,
            alCambiar = alCambiar,
            mensaje = mensaje,
            pendientes = pendientes,
            alEnviar = alEnviar,
            sufijo = "-porque",
        )
    }
}

/** La vista de Media3 con sus controles. Sin [alPantallaCompleta], no muestra el botón de pantalla completa. */
@OptIn(UnstableApi::class)
@Composable
private fun VistaMedia3(
    player: androidx.media3.common.Player?,
    etiqueta: String,
    alPantallaCompleta: ((Boolean) -> Unit)?,
    completa: Boolean,
    modifier: Modifier = Modifier,
    recorte: ReglasVideo.Recuadro? = null,
) {
    AndroidView(
        factory = { ctx ->
            (android.view.LayoutInflater.from(ctx).inflate(com.pumpteam.mypump.R.layout.guia_reproductor, null) as PlayerView).apply {
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                setShowPreviousButton(false)
                setShowNextButton(false)
                setShowSubtitleButton(false)
                setShowShuffleButton(false)
                // La caja ya tiene la proporción del clip: FIT no recorta ni deforma, y sin el fondo negro del obturador
                // (mientras carga se ve el fondo de la tarjeta, no una franja negra).
                resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
                setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
                setBackgroundColor(android.graphics.Color.TRANSPARENT)
                if (alPantallaCompleta != null) {
                    setFullscreenButtonClickListener { alPantallaCompleta(it) }
                    setFullscreenButtonState(completa)
                }
                contentDescription = "Video de tu guía"
                // El recorte de la zona útil se vuelve a aplicar cada vez que cambia el tamaño (el marco o la vista).
                val alCambiar = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> aplicarRecorte(this, tag as? ReglasVideo.Recuadro) }
                addOnLayoutChangeListener(alCambiar)
                findViewById<View>(androidx.media3.ui.R.id.exo_content_frame)?.addOnLayoutChangeListener(alCambiar)
            }
        },
        update = { v ->
            if (v.player !== player) v.player = player
            v.tag = recorte
            aplicarRecorte(v, recorte)
        },
        onRelease = { v -> v.player = null },
        modifier = modifier.testTag(etiqueta),
    )
}

/** Pantalla completa: el video sobre todo (también sobre la barra de pestañas) y sin las barras del sistema. */
@Composable
private fun PantallaCompleta(control: ControlReproductor) {
    Dialog(
        onDismissRequest = { control.pantallaCompleta = false },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        val ventana = (LocalView.current.parent as? DialogWindowProvider)?.window
        val vista = LocalView.current
        DisposableEffect(ventana) {
            val w = ventana
            if (w != null) {
                WindowCompat.setDecorFitsSystemWindows(w, false)
                val ctrl = WindowCompat.getInsetsController(w, vista)
                ctrl.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                ctrl.hide(WindowInsetsCompat.Type.systemBars())
            }
            onDispose { }
        }
        Box(Modifier.fillMaxSize().background(Color.Black).testTag("guia-pantalla-completa"), contentAlignment = Alignment.Center) {
            // La proporción del clip también acá: lo más grande que entra sin deformarse.
            val proporcion = proporcionDe(control.player, control.clipActual?.id)
            val recorte = recorteDe(control.clipActual?.url, control.clipActual?.id)
            val prop = ReglasVideo.proporcionVisible(proporcion, recorte)
            BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                val (ancho, alto) = ReglasVideo.completa(prop, maxWidth.value, maxHeight.value)
                Box(Modifier.size(ancho.dp, alto.dp).clipToBounds().testTag("guia-video-completo-caja")) {
                    VistaVideo(control, Modifier.fillMaxSize(), completa = true, recorte = recorte)
                    CapasVideo(control)
                }
            }
        }
    }
}

/** La duda de este video: lo que ya dejó arriba, el campo y «Enviar duda». */
@Composable
private fun DudaVideo(
    video: String,
    yaDejo: String?,
    despues: Boolean,
    texto: String,
    alCambiar: (String) -> Unit,
    mensaje: Pair<String, Boolean>?,
    pendientes: List<String>,
    alEnviar: (String) -> Unit,
    sufijo: String = "",
) {
    val c = MyPump.colores
    Column(Modifier.fillMaxWidth().testTag("duda-video$sufijo"), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Text("¿Te quedó alguna duda de este video?", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        if (yaDejo != null) YaDejaste("Ya me dejaste", yaDejo.split('\n').filter { it.isNotBlank() }, Modifier.testTag("duda-ya-$video"))
        if (pendientes.isNotEmpty()) YaDejaste("Enviando…", pendientes, enviando = true)
        CampoDuda(
            texto = texto,
            alCambiar = alCambiar,
            placeholder = "Escribila acá y me llega" + if (despues) "" else " antes de la videollamada",
            descripcion = "Tu duda de este video",
            etiqueta = "duda-campo$sufijo",
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            BotonMarca(
                "Enviar duda",
                alTocar = { alEnviar(texto) },
                compacto = true,
                habilitado = ReglasGuia.dudaValida(texto) != null,
                modifier = Modifier.testTag("duda-enviar$sufijo"),
            )
            mensaje?.let { (m, error) ->
                Text(
                    m,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (error) c.peligro else c.textoSecundario,
                    modifier = Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Polite }.testTag("duda-mensaje$sufijo"),
                )
            }
        }
    }
}

/** El recuadro de la web para la videollamada: la lista, el campo y el tope de 30. */
@Composable
private fun DudasLlamada(
    guia: Guia,
    despues: Boolean,
    texto: String,
    alCambiar: (String) -> Unit,
    mensaje: Pair<String, Boolean>?,
    pendientes: List<String>,
    puedeSumar: Boolean,
    alEnviar: (String) -> Unit,
    modifier: Modifier = Modifier,
    transcriptos: List<String> = emptyList(),
    audio: (@Composable (despues: Boolean, Modifier) -> Unit)? = null,
) {
    val c = MyPump.colores
    // La transcripción de un audio entra después como una duda más: se saltea la que ya se ve en «Esto es lo que entendí».
    val ya = com.pumpteam.mypump.reglas.ReglasAudioDuda.sinTranscriptas(guia.dudasLlamada.map { it.texto }, transcriptos)
    val acento = c.marca
    Row(
        modifier
            .superficieTarjeta()
            // El borde verde a la izquierda de la web (`.llamada`).
            .drawBehind { drawRect(acento, size = Size(6.dp.toPx(), size.height)) }
            .testTag("guia-llamada"),
    ) {
        Column(Modifier.padding(start = Espacio.m + 10.dp, end = Espacio.m + 4.dp, top = Espacio.m, bottom = Espacio.m).weight(1f), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Text(
                if (despues) "¿Te quedó algo para preguntarme?" else "¿Qué querés que hablemos en la videollamada?",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                if (despues) "Me llega y te contesto. Podés dejar varias." else "Me llega antes de la videollamada. Podés dejar varias.",
                style = MaterialTheme.typography.bodySmall,
                color = c.textoSecundario,
            )
            if (ya.isNotEmpty()) {
                YaDejaste(if (ya.size == 1) "Ya me dejaste esta" else "Ya me dejaste estas ${ya.size}", ya, Modifier.testTag("llamada-ya"))
            }
            if (pendientes.isNotEmpty()) YaDejaste("Enviando…", pendientes, enviando = true)
            if (puedeSumar) {
                CampoDuda(
                    texto = texto,
                    alCambiar = alCambiar,
                    placeholder = if (despues) "Tu pregunta" else "Por ejemplo, algo que no entendiste del plan o que querés cambiar",
                    descripcion = "Tu duda para la videollamada",
                    minLineas = 3,
                    etiqueta = "llamada-campo",
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    mensaje?.let { (m, error) ->
                        Text(
                            m,
                            style = MaterialTheme.typography.bodySmall,
                            color = if (error) c.peligro else c.textoSecundario,
                            modifier = Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Polite }.testTag("llamada-mensaje"),
                        )
                    } ?: Box(Modifier.weight(1f))
                    BotonMarca("Enviar", alTocar = { alEnviar(texto) }, compacto = true, habilitado = ReglasGuia.dudaValida(texto) != null, modifier = Modifier.testTag("llamada-enviar"))
                }
            } else {
                Text(
                    "Ya dejaste ${ReglasGuia.TOPE_DUDAS_LLAMADA}, el máximo. Las vemos en la videollamada.",
                    style = MaterialTheme.typography.bodySmall,
                    color = c.textoSecundario,
                    modifier = Modifier.testTag("llamada-tope"),
                )
            }
            audio?.invoke(despues, Modifier)
        }
    }
}

/**
 * Una duda que no se guardó vuelve al campo y nunca se pierde: si el cliente ya escribió otra cosa, va adelante de lo
 * que hay, separada por una línea en blanco.
 */
internal fun devolverAlCampo(rechazada: String, actual: String?): String =
    if (actual.isNullOrBlank()) rechazada else rechazada + "\n\n" + actual

private tailrec fun android.content.Context.actividad(): android.app.Activity? = when (this) {
    is android.app.Activity -> this
    is android.content.ContextWrapper -> baseContext.actividad()
    else -> null
}
