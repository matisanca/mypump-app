package com.pumpteam.mypump.tecnica

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloTecnica
import com.pumpteam.mypump.datos.PendienteTecnica
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.LocalRellenoInferior
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.NombreEjercicio
import com.pumpteam.mypump.fotos.ProveedorFotos
import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.CorreccionTecnica
import com.pumpteam.mypump.reglas.DevolucionTecnica
import com.pumpteam.mypump.reglas.EnvioTecnica
import com.pumpteam.mypump.reglas.EstadoTecnica
import com.pumpteam.mypump.reglas.Gimnasio
import com.pumpteam.mypump.reglas.Tecnica
import com.pumpteam.mypump.reglas.TextosTecnica as T
import kotlinx.coroutines.launch

private fun textoDe(a: ModeloTecnica.Aviso): String = when (a) {
    is ModeloTecnica.Aviso.Rechazo -> a.rechazo.texto
    ModeloTecnica.Aviso.EnCurso -> T.enCurso
    ModeloTecnica.Aviso.TopeSemanal -> T.topeSemanal
    ModeloTecnica.Aviso.Error -> T.errorGenerico
}

/** Todo lo que cambia en el modelo: leerlo acá hace que la pantalla que lo llama se redibuje. */
private data class Vista(val estado: EstadoTecnica?, val pendiente: PendienteTecnica?, val subiendo: Boolean, val aviso: ModeloTecnica.Aviso?)

@Composable
private fun observar(m: ModeloTecnica): Vista {
    val estado by m.estado.collectAsStateWithLifecycle()
    val cola by m.cola.collectAsStateWithLifecycle()
    val subiendo by m.subiendo.collectAsStateWithLifecycle()
    val aviso by m.aviso.collectAsStateWithLifecycle()
    return Vista(estado, cola.pendiente, subiendo, aviso)
}

@Composable
private fun Nota(texto: String, modifier: Modifier = Modifier, alerta: Boolean = false) {
    val c = MyPump.colores
    Text(
        texto,
        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
        color = if (alerta) c.alerta else c.textoSecundario,
        modifier = modifier.fillMaxWidth().then(if (alerta) Modifier.semantics { liveRegion = LiveRegionMode.Polite } else Modifier),
    )
}

@Composable
private fun Desplazable(relleno: PaddingValues, contenido: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .padding(relleno)
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Espacio.m)
            .padding(top = Espacio.s, bottom = Espacio.xl + LocalRellenoInferior.current),
        verticalArrangement = Arrangement.spacedBy(Espacio.m),
        content = contenido,
    )
}

// ── Entradas ──

/** «Mandar mi técnica» en el detalle del ejercicio. Con la palanca apagada o sin el servidor nuevo, no existe. */
@Composable
fun BotonMandarTecnica(m: ModeloTecnica?, ejercicio: Ejercicio, alAbrir: (slug: String, nombre: String) -> Unit) {
    val x = m ?: return
    val estado by x.estado.collectAsStateWithLifecycle()
    if (estado == null) return
    BotonSecundario(T.entradaEjercicio, alTocar = { alAbrir(Tecnica.slug(ejercicio), ejercicio.nombre) }, modifier = Modifier.fillMaxWidth().testTag("tecnica-mandar-ejercicio"))
}

private const val A_ELEGIR = "elegir"
private const val A_ENVIAR = "enviar:"
private const val A_DEVOLUCION = "devolucion:"
private const val A_VIDEO = "video:"

/** «Mi técnica» en Mis datos: lo mandado, su estado y la devolución. */
@Composable
fun TecnicaPantalla(m: ModeloTecnica, modelo: ModeloApp, alVolver: () -> Unit) {
    val v = observar(m)
    // Al volver de una muerte del proceso el estado todavía no está: se decide después de preguntar.
    var preguntado by remember { mutableStateOf(false) }
    LaunchedEffect(m) {
        if (m.palancaRecordada) {
            m.refrescar()
            m.drenarEnFondo()
        }
        preguntado = true
    }
    LaunchedEffect(preguntado, v.estado == null) { if (preguntado && v.estado == null) alVolver() }

    // Una pila chica: la devolución y el video de una devolución.
    var destino by rememberSaveable { mutableStateOf("") }
    var nombreEnvio by rememberSaveable { mutableStateOf("") }
    val volver: () -> Unit = {
        destino = when {
            destino.startsWith(A_VIDEO) -> A_DEVOLUCION + destino.removePrefix(A_VIDEO).substringAfter('|')
            destino.startsWith(A_ENVIAR) -> A_ELEGIR
            else -> ""
        }
    }
    BackHandler(enabled = destino.isNotEmpty()) { volver() }

    when {
        destino == A_ELEGIR -> ElegirEjercicio(modelo, volver) { slug, nombre ->
            nombreEnvio = nombre
            destino = A_ENVIAR + slug
        }
        destino.startsWith(A_ENVIAR) -> EnviarTecnicaPantalla(m, destino.removePrefix(A_ENVIAR), nombreEnvio, alVolver = volver, alTerminar = { destino = "" })
        destino.startsWith(A_VIDEO) -> {
            val (s, id) = destino.removePrefix(A_VIDEO).split('|', limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            VideoTecnica(m, id, s.toDoubleOrNull() ?: 0.0, volver)
        }
        destino.startsWith(A_DEVOLUCION) -> {
            val id = destino.removePrefix(A_DEVOLUCION)
            val e = v.estado?.visibles?.firstOrNull { it.id == id }
            val dev = e?.devolucion
            if (e != null && dev != null) {
                DevolucionPantalla(m, e, dev, volver) { s -> destino = "$A_VIDEO$s|$id" }
            } else {
                LaunchedEffect(Unit) { destino = "" }
            }
        }
        else -> MarcoPantalla(T.entradaMisDatos, alVolver = alVolver) { relleno ->
            ListaTecnica(m, v, relleno, alElegir = { destino = A_ELEGIR }, alAbrir = { destino = A_DEVOLUCION + it })
        }
    }
}

@Composable
private fun FilaEnvio(titulo: String, detalle: String, modifier: Modifier = Modifier, alerta: Boolean = false, alTocar: (() -> Unit)? = null) {
    val c = MyPump.colores
    Row(
        modifier.fillMaxWidth().superficieTarjeta()
            .then(if (alTocar != null) Modifier.clickable(role = Role.Button, onClick = alTocar) else Modifier)
            .padding(Espacio.m),
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = MaterialTheme.typography.titleMedium, color = c.texto)
            Text(detalle, style = MaterialTheme.typography.bodyMedium, color = if (alerta) c.alerta else c.textoSecundario)
        }
        if (alTocar != null) Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun ListaTecnica(m: ModeloTecnica, v: Vista, relleno: PaddingValues, alElegir: () -> Unit, alAbrir: (String) -> Unit) {
    val puede = v.estado != null && v.pendiente == null && v.estado.enRevision == null
    val envios = v.estado?.visibles ?: emptyList()
    Desplazable(relleno) {
        v.aviso?.let { Nota(textoDe(it), Modifier.testTag("tecnica-aviso-envio"), alerta = true) }
        if (puede) {
            BotonMarca(T.entradaEjercicio, alTocar = {
                m.limpiarAviso()
                alElegir()
            }, modifier = Modifier.fillMaxWidth().testTag("tecnica-mandar"))
        }
        v.pendiente?.let { p -> FilaEnvio(p.nombre, if (v.subiendo) T.subiendo else T.esperandoSenal, Modifier.testTag("tecnica-fila-pendiente")) }
        envios.forEach { e ->
            when (e.estado) {
                EnvioTecnica.Estado.PUBLICADO -> FilaEnvio(
                    e.nombre,
                    Gimnasio.fechaCorta(e.publicadoEn)?.let(T::revisadoEl) ?: (e.devolucion?.credito ?: ""),
                    Modifier.testTag("tecnica-fila-publicado"),
                    alTocar = { alAbrir(e.id) },
                )
                EnvioTecnica.Estado.RECHAZADO -> FilaEnvio(e.nombre, e.rechazoTexto ?: T.rechazoIlegible, Modifier.testTag("tecnica-fila-rechazado"), alerta = true)
                else -> {
                    FilaEnvio(e.nombre, T.recibido, Modifier.testTag("tecnica-fila-enviado"))
                    if (e.tieneVideo) SacarVideo(m, e.id)
                }
            }
        }
        if (envios.isEmpty() && v.pendiente == null) Nota(T.sinEnvios, Modifier.testTag("tecnica-vacio"))
    }
}

@Composable
private fun ElegirEjercicio(modelo: ModeloApp, alVolver: () -> Unit, alElegir: (slug: String, nombre: String) -> Unit) {
    val c = MyPump.colores
    val rutina by modelo.rutina.collectAsStateWithLifecycle()
    val entreno by modelo.entreno.collectAsStateWithLifecycle()
    val ejercicios = remember(rutina, entreno) {
        val motor = entreno
        Tecnica.ejerciciosParaElegir(rutina?.estructura?.dias ?: emptyList()) { ex -> motor?.efectivo(ex)?.ejercicio ?: ex }
    }
    MarcoPantalla(T.elegirEjercicio, alVolver = alVolver) { relleno ->
        Desplazable(relleno) {
            if (ejercicios.isEmpty()) Nota(T.sinEjercicios)
            ejercicios.forEachIndexed { i, e ->
                Row(
                    Modifier.fillMaxWidth().superficieTarjeta()
                        .clickable(role = Role.Button) { alElegir(Tecnica.slug(e), e.nombre) }
                        .heightIn(min = 44.dp)
                        .padding(Espacio.s + 4.dp)
                        .testTag("tecnica-ejercicio-$i"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(e.nombre, color = c.texto, modifier = Modifier.weight(1f))
                    Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

// ── Enviar ──

/** La cámara del teléfono, con el mismo tope que la app, sin pedir el permiso CAMERA (el video lo graba la app de cámara). */
private class GrabarVideo : ActivityResultContracts.CaptureVideo() {
    override fun createIntent(context: Context, input: Uri): Intent = super.createIntent(context, input).putExtra(MediaStore.EXTRA_DURATION_LIMIT, 75).putExtra(MediaStore.EXTRA_VIDEO_QUALITY, 1)
}

/** El aviso (una sola vez), el consejo, el video, la nota y «Enviar a Mati». Lo que sigue lo cuenta la cola. */
@Composable
fun EnviarTecnicaPantalla(m: ModeloTecnica, slug: String, nombre: String, alVolver: () -> Unit, alTerminar: (() -> Unit)? = null) {
    val v = observar(m)
    val contexto = LocalContext.current
    var mandado by rememberSaveable { mutableStateOf(false) }
    // Al volver de una muerte del proceso se llega acá sin haber pasado por la entrada: la palanca se mira igual.
    var preguntado by remember { mutableStateOf(false) }
    LaunchedEffect(m) {
        if (m.palancaRecordada) {
            m.refrescar()
            m.drenarEnFondo()
        }
        preguntado = true
    }
    LaunchedEffect(preguntado, v.estado == null, mandado) { if (preguntado && v.estado == null && !mandado) alVolver() }
    MarcoPantalla(NombreEjercicio(nombre).principal, alVolver = alVolver) { relleno ->
        val puede = v.estado != null && v.pendiente == null && v.estado.enRevision == null
        when {
            mandado && v.pendiente == null && v.aviso == null -> Recibido(relleno, alTerminar)
            v.pendiente != null -> Enviando(m, v.subiendo, relleno, alCancelar = { mandado = false }, alNoCancelar = { mandado = true })
            v.estado == null && !mandado -> Unit   // se va en el LaunchedEffect de arriba
            !puede && !mandado -> Box(Modifier.padding(relleno).fillMaxSize().padding(Espacio.l), contentAlignment = Alignment.Center) {
                Nota(T.enCurso, Modifier.testTag("tecnica-en-curso"))
            }
            m.necesitaAviso -> AvisoTerceros(m, relleno)
            else -> Formulario(m, v, slug, nombre, relleno, alMandado = { mandado = true })
        }
    }
    LaunchedEffect(contexto) { CompresorVideo.barrer(contexto) }
}

@Composable
private fun AvisoTerceros(m: ModeloTecnica, relleno: PaddingValues) {
    val c = MyPump.colores
    Desplazable(relleno) {
        Row(
            Modifier.fillMaxWidth().background(c.marcaSuave, RoundedCornerShape(Radio.control)).padding(Espacio.s).testTag("tecnica-aviso"),
            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            Icon(Iconos.Candado, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
            Text(T.avisoTerceros, style = MaterialTheme.typography.bodyMedium, color = c.texto, modifier = Modifier.weight(1f))
        }
        BotonMarca(T.avisoBoton, alTocar = { m.aceptarAviso() }, modifier = Modifier.fillMaxWidth().testTag("tecnica-aviso-ok"))
    }
}

@Composable
private fun Formulario(m: ModeloTecnica, v: Vista, slug: String, nombre: String, relleno: PaddingValues, alMandado: () -> Unit) {
    val c = MyPump.colores
    val contexto = LocalContext.current
    val alcance = rememberCoroutineScope()
    var video by remember { mutableStateOf<CompresorVideo.Listo?>(null) }
    var preparando by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var nota by rememberSaveable { mutableStateOf("") }
    var menu by remember { mutableStateOf(false) }
    val hayCamara = remember { contexto.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }
    val actual by rememberUpdatedState(video)
    DisposableEffect(Unit) { onDispose { actual?.archivo?.delete() } }

    fun preparar(uri: Uri, temporal: java.io.File?) {
        error = null
        m.limpiarAviso()
        preparando = true
        alcance.launch {
            val r = CompresorVideo.preparar(contexto, uri, v.estado?.topes ?: m.topes)
            temporal?.delete()
            preparando = false
            video?.archivo?.delete()
            video = null
            when (r) {
                is CompresorVideo.Resultado.Ok -> video = r.listo
                is CompresorVideo.Resultado.Rechazado -> error = r.rechazo.texto
            }
        }
    }

    val galeria = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { preparar(it, null) } }
    val camara = rememberLauncherForActivityResult(GrabarVideo()) { ok ->
        val a = ProveedorFotos.archivoVideo(contexto)
        if (ok && a.length() > 0) preparar(ProveedorFotos.uri(contexto, a), a) else a.delete()
    }
    fun abrirGaleria() = galeria.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
    fun abrirCamara() {
        val (a, uri) = ProveedorFotos.paraElVideo(contexto)
        try {
            camara.launch(uri)
        } catch (_: ActivityNotFoundException) {
            a.delete()
            abrirGaleria()
        }
    }

    Desplazable(relleno) {
        Text(T.consejo, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.testTag("tecnica-consejo"))
        v.aviso?.let { Nota(textoDe(it), Modifier.testTag("tecnica-aviso-envio"), alerta = true) }
        error?.let { Nota(it, Modifier.testTag("tecnica-error"), alerta = true) }
        if (preparando) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 54.dp).testTag("tecnica-preparando"),
                horizontalArrangement = Arrangement.spacedBy(Espacio.s, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(Modifier.size(20.dp), color = c.marcaTexto, strokeWidth = 2.dp)
                Text(T.preparando, style = MaterialTheme.typography.bodyMedium, color = c.texto)
            }
        } else {
            video?.let { l ->
                Row(Modifier.fillMaxWidth().testTag("tecnica-video-listo"), horizontalArrangement = Arrangement.spacedBy(Espacio.xs), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
                    Text(T.videoListo(Math.round(l.duracion).toInt()), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = c.marcaTexto)
                }
            }
            Box {
                val tocar = { if (hayCamara) menu = true else abrirGaleria() }
                if (video == null) {
                    BotonMarca(T.agregarVideo, alTocar = tocar, modifier = Modifier.fillMaxWidth().testTag("tecnica-agregar-video"))
                } else {
                    BotonSecundario(T.cambiarVideo, alTocar = tocar, modifier = Modifier.fillMaxWidth().testTag("tecnica-agregar-video"))
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, containerColor = c.tarjeta) {
                    DropdownMenuItem(text = { Text(T.grabarVideo) }, onClick = {
                        menu = false
                        abrirCamara()
                    }, modifier = Modifier.testTag("tecnica-grabar"))
                    DropdownMenuItem(text = { Text(T.elegirGaleria) }, onClick = {
                        menu = false
                        abrirGaleria()
                    }, modifier = Modifier.testTag("tecnica-galeria"))
                }
            }
        }
        Box(
            Modifier.fillMaxWidth().heightIn(min = 72.dp)
                .clip(RoundedCornerShape(Radio.control)).background(c.campo).padding(Espacio.s),
        ) {
            if (nota.isEmpty()) Text(T.notaPregunta, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
            BasicTextField(
                value = nota,
                onValueChange = { nota = Tecnica.nota(it) },
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
                cursorBrush = SolidColor(c.marcaTexto),
                modifier = Modifier.fillMaxWidth().testTag("tecnica-nota").semantics { contentDescription = T.notaPregunta },
            )
        }
        BotonMarca(
            T.botonEnviar,
            alTocar = {
                val l = video ?: return@BotonMarca
                when (m.encolar(l.archivo, slug, nombre, nota)) {
                    ModeloTecnica.Encolar.GUARDADO -> {
                        video = null
                        alMandado()
                        m.drenarEnFondo()
                    }
                    ModeloTecnica.Encolar.OCUPADO -> error = T.enCurso
                    ModeloTecnica.Encolar.NO_SE_GUARDO -> error = T.noSeGuardo
                }
            },
            modifier = Modifier.fillMaxWidth().testTag("tecnica-enviar"),
            habilitado = video != null && !preparando,
        )
    }
}

@Composable
private fun Enviando(m: ModeloTecnica, subiendo: Boolean, relleno: PaddingValues, alCancelar: () -> Unit, alNoCancelar: () -> Unit) {
    val c = MyPump.colores
    // En el alcance de la app: esta pantalla se va apenas sale de la cola, y el borrador del servidor se tiene que cerrar igual.
    val alcance = LocalAlcanceApp.current
    Column(
        Modifier.padding(relleno).fillMaxSize().verticalScroll(rememberScrollState()).padding(Espacio.l),
        verticalArrangement = Arrangement.spacedBy(Espacio.m, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator(color = c.marcaTexto)
        Text(if (subiendo) T.subiendo else T.esperandoSenal, style = MaterialTheme.typography.titleMedium, color = c.texto, textAlign = TextAlign.Center, modifier = Modifier.testTag("tecnica-enviando"))
        Text(T.enviandoSeguir, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, textAlign = TextAlign.Center)
        if (!subiendo) {
            BotonSecundario(T.cancelarEnvio, alTocar = {
                // Antes de sacarlo de la cola: si no, se ve un instante «Recibido».
                alCancelar()
                alcance.launch { if (!m.cancelarPendiente()) alNoCancelar() }
            }, modifier = Modifier.fillMaxWidth().testTag("tecnica-cancelar"))
        }
    }
}

@Composable
private fun Recibido(relleno: PaddingValues, alTerminar: (() -> Unit)?) {
    val c = MyPump.colores
    Column(
        Modifier.padding(relleno).fillMaxSize().verticalScroll(rememberScrollState()).padding(Espacio.l),
        verticalArrangement = Arrangement.spacedBy(Espacio.m, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(48.dp))
        Text(T.recibido, style = MaterialTheme.typography.titleMedium, color = c.texto, textAlign = TextAlign.Center, modifier = Modifier.testTag("tecnica-recibido"))
        if (alTerminar != null) BotonSecundario(T.otroRecibido, alTocar = alTerminar, modifier = Modifier.fillMaxWidth().testTag("tecnica-listo"))
    }
}

// ── Devolución ──

@Composable
private fun Seccion(titulo: String, modifier: Modifier = Modifier, contenido: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Text(titulo, style = MaterialTheme.typography.titleMedium, color = MyPump.colores.texto, modifier = Modifier.semantics { heading() })
        contenido()
    }
}

@Composable
private fun Bloque(titulo: String, texto: String) {
    if (texto.isEmpty()) return
    val c = MyPump.colores
    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(titulo, style = MaterialTheme.typography.labelMedium, color = c.textoSecundario)
        Text(texto, style = MaterialTheme.typography.bodyMedium, color = c.texto)
    }
}

@Composable
private fun Correccion(c: CorreccionTecnica, tieneVideo: Boolean, alVer: (Double) -> Unit) {
    Tarjeta(espaciado = Espacio.xs) {
        Text(c.titulo, style = MaterialTheme.typography.titleMedium, color = MyPump.colores.texto)
        Bloque(T.queSeVe, c.queSeVe)
        Bloque(T.porQueImporta, c.porQue)
        Bloque(T.comoHacerlo, c.comoCorregir)
        val momento = c.momentoS
        if (momento != null && tieneVideo) {
            BotonSecundario(T.verEnElVideo, alTocar = { alVer(momento) }, modifier = Modifier.fillMaxWidth().testTag("tecnica-ver-en-video"))
        }
    }
}

@Composable
private fun DevolucionPantalla(m: ModeloTecnica, envio: EnvioTecnica, d: DevolucionTecnica, alVolver: () -> Unit, alVerVideo: (Double) -> Unit) {
    val c = MyPump.colores
    MarcoPantalla(T.tituloDevolucion(d.ejercicio ?: envio.nombre), alVolver = alVolver) { relleno ->
        Desplazable(relleno) {
            Text(
                Gimnasio.fechaCorta(envio.publicadoEn)?.let(T::revisadoEl) ?: d.credito,
                style = MaterialTheme.typography.bodyMedium,
                color = c.textoSecundario,
                modifier = Modifier.testTag("tecnica-credito"),
            )
            // Sin correcciones no quiere decir que esté bien si no se pudo ver o hace falta otro video.
            if (d.correcciones.isEmpty() && d.noEvaluable.isEmpty() && d.otroVideo == null) Text(T.sinCorrecciones, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.testTag("tecnica-sin-correcciones"))
            if (d.bien.isNotEmpty()) {
                Seccion(T.loQueEstaBien, Modifier.testTag("tecnica-bien")) {
                    d.bien.forEach { b ->
                        Row(horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                            Icon(Iconos.Tilde, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                            Text(b, style = MaterialTheme.typography.bodyLarge, color = c.texto, modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
            if (d.correcciones.isNotEmpty()) {
                Seccion(T.paraCorregir, Modifier.testTag("tecnica-correcciones")) { d.correcciones.forEach { Correccion(it, envio.tieneVideo, alVerVideo) } }
            }
            if (d.noEvaluable.isNotEmpty()) {
                Seccion(T.noSePudoVer) {
                    d.noEvaluable.forEach { n ->
                        Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(n.que, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = c.texto)
                            Text(n.motivo, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
                        }
                    }
                }
            }
            d.otroVideo?.takeIf { it.isNotEmpty() }?.let { como -> Seccion(T.mandameOtro, Modifier.testTag("tecnica-otro-video")) { Text(como, style = MaterialTheme.typography.bodyLarge, color = c.texto) } }
            if (envio.tieneVideo) SacarVideo(m, envio.id)
        }
    }
}

/** «Sacar mi video»: el aviso promete que se puede cuando quiera, también mientras está en revisión. */
@Composable
private fun SacarVideo(m: ModeloTecnica, id: String) {
    val alcance = rememberCoroutineScope()
    var confirma by rememberSaveable { mutableStateOf(false) }
    var nota by remember { mutableStateOf<String?>(null) }
    nota?.let { Nota(it, alerta = true) }
    BotonSecundario(T.sacarVideo, alTocar = { confirma = true }, modifier = Modifier.fillMaxWidth().testTag("tecnica-sacar"), tono = MyPump.colores.alerta)
    if (confirma) {
        com.pumpteam.mypump.diseno.Alerta(
            titulo = T.sacarConfirma,
            mensaje = T.sacarDetalle,
            botones = listOf(
                com.pumpteam.mypump.diseno.BotonAlerta(T.cancelar, etiqueta = "tecnica-sacar-no") { confirma = false },
                com.pumpteam.mypump.diseno.BotonAlerta(T.sacarVideo, destructivo = true, etiqueta = "tecnica-sacar-si") {
                    confirma = false
                    alcance.launch {
                        nota = when (m.sacarVideo(id)) {
                            ModeloTecnica.Salida.OK -> null
                            ModeloTecnica.Salida.OCUPADO -> T.sacarOcupado
                            ModeloTecnica.Salida.SIN_SENAL -> T.sinSenal
                            ModeloTecnica.Salida.ERROR -> T.errorGenerico
                        }
                    }
                },
            ),
            alDescartar = { confirma = false },
        )
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun VideoTecnica(m: ModeloTecnica, id: String, desde: Double, alVolver: () -> Unit) {
    val contexto = LocalContext.current
    var url by remember { mutableStateOf<String?>(null) }
    var fallo by remember { mutableStateOf(false) }
    LaunchedEffect(id) {
        url = m.urlVideo(id)
        fallo = url == null
    }
    MarcoPantalla(T.verEnElVideo, alVolver = alVolver) { relleno ->
        Box(Modifier.padding(relleno).fillMaxSize().testTag("tecnica-video"), contentAlignment = Alignment.Center) {
            val u = url
            when {
                u != null -> {
                    val player = remember(u) {
                        ExoPlayer.Builder(contexto).build().apply {
                            setMediaItem(MediaItem.fromUri(u))
                            seekTo((desde * 1000).toLong())
                            prepare()
                            playWhenReady = true
                        }
                    }
                    DisposableEffect(player) { onDispose { player.release() } }
                    AndroidView(factory = { PlayerView(it).apply { this.player = player } }, modifier = Modifier.fillMaxSize())
                }
                fallo -> Nota(T.errorVideo, Modifier.padding(Espacio.l), alerta = true)
                else -> CircularProgressIndicator(color = MyPump.colores.marcaTexto)
            }
        }
    }
}
