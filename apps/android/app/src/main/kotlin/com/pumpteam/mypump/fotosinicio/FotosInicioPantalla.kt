package com.pumpteam.mypump.fotosinicio

import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.layout.ContentScale
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloFotosInicio
import com.pumpteam.mypump.datos.PendienteFotoInicio
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.ImagenRemota
import com.pumpteam.mypump.diseno.LocalRellenoInferior
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.fotos.BotonFoto
import com.pumpteam.mypump.fotos.ReduccionFoto
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.EstadoFotosInicio
import com.pumpteam.mypump.reglas.FotosInicio
import com.pumpteam.mypump.reglas.SiluetasFotosInicio
import com.pumpteam.mypump.reglas.TextosFotosInicio as T
import java.io.File
import java.time.OffsetDateTime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Todo lo que cambia en el modelo: leerlo acá hace que la pantalla que lo llama se redibuje. */
private data class Vista(
    val estado: EstadoFotosInicio?,
    val cola: List<PendienteFotoInicio>,
    val subiendo: String?,
    val urls: Map<String, String>,
    val aviso: FotosInicio.Aviso?,
    val notaPendiente: String?,
)

@Composable
private fun observar(m: ModeloFotosInicio): Vista {
    val estado by m.estado.collectAsStateWithLifecycle()
    val cola by m.cola.collectAsStateWithLifecycle()
    val subiendo by m.subiendo.collectAsStateWithLifecycle()
    val urls by m.urls.collectAsStateWithLifecycle()
    val aviso by m.aviso.collectAsStateWithLifecycle()
    val nota by m.notaPendiente.collectAsStateWithLifecycle()
    return Vista(estado, cola, subiendo, urls, aviso, nota)
}

// ── 1. La tarjeta de Revisión y la fila de Mis datos ──

/** Arriba de todo en Revisión. Sin cuenta, con la palanca apagada o sin `habilitado: true`, no existe. */
@Composable
fun TarjetaFotosInicioDe(modelo: ModeloApp, modifier: Modifier = Modifier, soloSiFaltan: Boolean = false) {
    val f by modelo.fotosInicio.collectAsStateWithLifecycle()
    val m = f ?: return
    val v = observar(m)
    if (v.estado == null) return
    // En Entreno (lo primero que se ve al abrir la app) va mientras falte alguna; en Revisión, siempre.
    if (soloSiFaltan && m.faltan.isEmpty()) return
    val c = MyPump.colores
    val navegacion = LocalNavegacion.current
    val listas = m.listas
    Column(
        modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .clip(RoundedCornerShape(Radio.tarjeta))
            .clickable(role = Role.Button) {
                // La pantalla vive en Revisión: desde Entreno se pasa a esa pestaña con la pantalla ya abierta.
                navegacion?.pestana = com.pumpteam.mypump.raiz.Pestana.REVISION
                navegacion?.fotosInicio = true
            }
            .padding(Espacio.m)
            .testTag("fotos-inicio-tarjeta"),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Box(Modifier.size(42.dp).background(c.marcaSuave, CircleShape), contentAlignment = Alignment.Center) {
                Icon(if (listas) Iconos.TildeEnCirculo else Iconos.Camara, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(T.tarjetaTitulo, style = MaterialTheme.typography.titleMedium, color = c.texto)
                Text(if (listas) T.tarjetaLista else T.tarjetaBajada, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
                if (!listas) Text(T.cuenta(m.hechas), style = MaterialTheme.typography.labelLarge, color = c.textoSecundario)
            }
            if (listas) Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
        }
        // Un botón grande y con texto, como en iOS: que se vea que es lo que hay que tocar (regla de Mati).
        if (!listas) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 50.dp)
                    .background(c.marca, CircleShape)
                    .padding(horizontal = Espacio.m, vertical = Espacio.s)
                    .testTag("fotos-inicio-tarjeta-boton"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espacio.s, Alignment.CenterHorizontally),
            ) {
                Icon(Iconos.Camara, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(20.dp))
                Text(if (m.hechas == 0) T.tarjetaEmpezar else T.tarjetaSeguir, style = MaterialTheme.typography.titleMedium, color = c.sobreMarca)
            }
        }
    }
}

/** ¿Va la fila «Mis fotos de inicio» en Mis datos? Solo con `habilitado: true`. */
@Composable
fun fotosInicioVisible(modelo: ModeloApp): Boolean {
    val f by modelo.fotosInicio.collectAsStateWithLifecycle()
    val m = f ?: return false
    val estado by m.estado.collectAsStateWithLifecycle()
    return estado != null
}

// ── La pantalla ──

private const val A_POSE = "pose:"
private const val A_REVISAR = "revisar:"

@Composable
fun FotosInicioPantalla(m: ModeloFotosInicio, alVolver: () -> Unit, directo: Boolean = false) {
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
    // Las miniaturas firmadas: al abrir y cada vez que aparece una foto nueva en el servidor.
    val ids = v.estado?.fotos?.map { it.id }
    LaunchedEffect(ids) { if (!ids.isNullOrEmpty()) m.firmar() }

    // `directo` (la tarjeta): abre ya en la pose que falta, con el resumen atrás; el segundo toque es la foto (regla de Mati:
    // nada a más de dos toques). Desde Mis datos, el resumen.
    var destino by rememberSaveable { mutableStateOf(if (directo) m.faltan.firstOrNull()?.let { A_POSE + it } ?: "" else "") }
    // La foto que se está revisando: no sobrevive a la muerte del proceso (se vuelve a la pose).
    var preparada by remember { mutableStateOf<FotoPreparada?>(null) }
    BackHandler(enabled = destino.isNotEmpty()) {
        destino = if (destino.startsWith(A_REVISAR) && destino.removePrefix(A_REVISAR) != FotosInicio.MOTIVACION) A_POSE + destino.removePrefix(A_REVISAR) else ""
        preparada = null
    }
    val revisando = destino.takeIf { it.startsWith(A_REVISAR) }?.removePrefix(A_REVISAR)
    val pose = destino.takeIf { it.startsWith(A_POSE) }?.removePrefix(A_POSE)?.let(FotosInicio::pose)
    LaunchedEffect(revisando, preparada) {
        if (revisando != null && preparada == null) destino = FotosInicio.pose(revisando)?.let { A_POSE + it.clave } ?: ""
    }
    val titulo = when {
        pose != null -> pose.nombre
        revisando == FotosInicio.MOTIVACION -> T.motivacionTitulo
        revisando != null -> FotosInicio.pose(revisando)?.nombre ?: T.tarjetaTitulo
        else -> T.tarjetaTitulo
    }
    val alPreparar: (String, FotoPreparada) -> Unit = { clave, p ->
        preparada = p
        destino = A_REVISAR + clave
    }
    MarcoPantalla(
        titulo,
        alVolver = {
            if (destino.isEmpty()) {
                alVolver()
            } else {
                destino = if (revisando != null && revisando != FotosInicio.MOTIVACION) A_POSE + revisando else ""
                preparada = null
            }
        },
    ) { relleno ->
        val p = preparada
        when {
            v.estado == null -> Unit
            pose != null -> PoseFotoInicio(pose, relleno, alPreparar)
            revisando != null && p != null -> RevisarFotoInicio(
                m, revisando, p, relleno,
                alPreparar = alPreparar,
                alUsar = { siguiente ->
                    preparada = null
                    destino = siguiente?.let { A_POSE + it } ?: ""
                },
            )
            revisando != null -> Unit
            else -> ResumenFotosInicio(m, relleno, alAbrirPose = { destino = A_POSE + it }, alPreparar = alPreparar, alListo = alVolver)
        }
    }
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

/** Texto suave de error o estado, siempre con el mismo aspecto. */
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

// ── 2. El resumen ──

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ResumenFotosInicio(
    m: ModeloFotosInicio,
    relleno: PaddingValues,
    alAbrirPose: (String) -> Unit,
    alPreparar: (String, FotoPreparada) -> Unit,
    alListo: () -> Unit,
) {
    val v = observar(m)
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    DisposableEffect(Unit) { onDispose { m.limpiarAviso() } }
    var errorMotivacion by remember { mutableStateOf<String?>(null) }
    Desplazable(relleno) {
        Row(horizontalArrangement = Arrangement.spacedBy(Espacio.xs), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.semantics(mergeDescendants = true) {}) {
            Icon(Iconos.Candado, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
            Text(T.privacidad, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.weight(1f))
        }
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            if (m.listas) {
                Text(T.listoTitulo, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.semantics { heading() })
                Text(T.listoBajada, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
            } else if (m.faltan.isNotEmpty()) {
                Text(T.faltan(m.faltan.size), style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.semantics { heading() })
            }
            when (v.aviso) {
                FotosInicio.Aviso.RECHAZADA -> Nota(T.fotoRechazada, Modifier.testTag("fotos-inicio-aviso"), alerta = true)
                FotosInicio.Aviso.TOPE -> Nota(T.motivacionTope, Modifier.testTag("fotos-inicio-aviso"), alerta = true)
                null -> Unit
            }
            if (v.cola.isNotEmpty() && v.subiendo == null) Nota(T.sinSenal)
        }

        // Las tres poses.
        Tarjeta(relleno = 0.dp, espaciado = 0.dp) {
            FotosInicio.poses.forEachIndexed { i, p ->
                if (i > 0) Separador(sangria = 80.dp)
                FilaPose(m, p, v.urls) { alAbrirPose(p.clave) }
            }
        }

        // Antes de sacarlas.
        Tarjeta(espaciado = Espacio.xs) {
            Text(T.consejosTitulo, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.semantics { heading() })
            for (consejo in FotosInicio.consejos) {
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                    Icon(Iconos.Tilde, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.padding(top = 2.dp).size(16.dp))
                    Text(consejo, style = MaterialTheme.typography.bodyMedium, color = c.texto, modifier = Modifier.weight(1f))
                }
            }
        }

        // El físico que te motiva (opcional).
        Tarjeta(espaciado = Espacio.s) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Text(T.motivacionTitulo, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.weight(1f, fill = false).semantics { heading() })
                Text(T.opcional, style = MaterialTheme.typography.labelMedium, color = c.textoSecundario)
            }
            Text(T.motivacionBajada, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
            val fotos = m.motivacion
            if (fotos.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.s), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    for (f in fotos) {
                        key(f.id) {
                            MiniaturaMotivacion(f, v.urls[f.id]) {
                                alcance.launch {
                                    errorMotivacion = when (m.borrarMotivacion(f.id)) {
                                        ModeloFotosInicio.Salida.SIN_SENAL -> T.borrarSinSenal
                                        else -> null
                                    }
                                }
                            }
                        }
                    }
                }
            }
            errorMotivacion?.let { Nota(it, alerta = true) }
            if (m.puedeAgregarMotivacion) {
                BotonFotoInicio(
                    pose = FotosInicio.MOTIVACION,
                    texto = T.motivacionAgregar,
                    etiqueta = "fotos-inicio-motivacion-agregar",
                    primario = false,
                    alPreparar = { alPreparar(FotosInicio.MOTIVACION, it) },
                )
            } else {
                Nota(T.motivacionTope, Modifier.testTag("fotos-inicio-motivacion-tope"))
            }
            NotaMotivacion(m, v)
        }

        BotonMarca(T.listoBoton, alTocar = alListo, modifier = Modifier.fillMaxWidth().testTag("fotos-inicio-listo"))
    }
}

private fun textoEstado(e: ModeloFotosInicio.EstadoPose): String = when (e) {
    ModeloFotosInicio.EstadoPose.FALTA -> T.falta
    ModeloFotosInicio.EstadoPose.SUBIENDO -> T.subiendo
    ModeloFotosInicio.EstadoPose.ESPERANDO -> T.esperandoSenal
    ModeloFotosInicio.EstadoPose.LISTA -> T.lista
}

@Composable
private fun FilaPose(m: ModeloFotosInicio, p: FotosInicio.Pose, urls: Map<String, String>, alTocar: () -> Unit) {
    val c = MyPump.colores
    val estado = m.estadoPose(p.clave)
    val foto = m.foto(p.clave)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 96.dp)
            .clickable(role = Role.Button, onClick = alTocar)
            .padding(horizontal = Espacio.m, vertical = Espacio.xs)
            .semantics(mergeDescendants = true) {}
            .testTag("fotos-inicio-pose-${p.clave}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(Modifier.size(width = 52.dp, height = 80.dp).clip(RoundedCornerShape(Radio.miniatura)).background(c.campo), contentAlignment = Alignment.Center) {
            val local = foto?.archivoLocal
            when {
                local != null -> MiniaturaLocal(local)
                foto != null -> ImagenRemota(urls[foto.id], 80.dp, Modifier.fillMaxSize()) { Silueta(p.clave, Modifier.padding(4.dp).fillMaxSize()) }
                else -> Silueta(p.clave, Modifier.padding(4.dp).fillMaxSize())
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(p.nombre, style = MaterialTheme.typography.bodyLarge, color = c.texto)
            Text(
                textoEstado(estado),
                style = MaterialTheme.typography.bodySmall,
                color = when (estado) {
                    ModeloFotosInicio.EstadoPose.LISTA -> c.marcaTexto
                    ModeloFotosInicio.EstadoPose.FALTA -> c.textoSecundario
                    else -> c.alerta
                },
                modifier = Modifier.testTag("fotos-inicio-estado-${p.clave}"),
            )
        }
        if (estado == ModeloFotosInicio.EstadoPose.LISTA) {
            Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
        } else {
            Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
        }
    }
}

private val LADO_MINIATURA = 96.dp

@Composable
private fun MiniaturaMotivacion(foto: ModeloFotosInicio.VistaFoto, url: String?, borrar: () -> Unit) {
    val c = MyPump.colores
    Column(Modifier.widthIn(max = LADO_MINIATURA), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(LADO_MINIATURA).clip(RoundedCornerShape(Radio.control)).background(c.campo).testTag("fotos-inicio-motivacion-foto")) {
            val local = foto.archivoLocal
            if (local != null) {
                MiniaturaLocal(local)
            } else {
                ImagenRemota(url, LADO_MINIATURA, Modifier.fillMaxSize()) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Icon(Iconos.Foto, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(24.dp))
                    }
                }
            }
            Box(
                Modifier.align(Alignment.TopEnd).size(48.dp).clickable(role = Role.Button, onClick = borrar).semantics { contentDescription = T.borrarFoto }.testTag("fotos-inicio-motivacion-borrar"),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(26.dp).background(c.tarjeta, CircleShape), contentAlignment = Alignment.Center) {
                    Icon(Iconos.Cerrar, contentDescription = null, tint = c.texto, modifier = Modifier.size(14.dp))
                }
            }
        }
        if (foto.subiendo || foto.esperando) {
            Text(if (foto.subiendo) T.subiendo else T.esperandoSenal, style = MaterialTheme.typography.labelSmall, color = c.textoSecundario)
        }
    }
}

@Composable
private fun NotaMotivacion(m: ModeloFotosInicio, v: Vista) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    var nota by rememberSaveable { mutableStateOf(v.notaPendiente ?: v.estado?.nota ?: "") }
    var resultado by remember { mutableStateOf<String?>(null) }
    var mandando by remember { mutableStateOf(false) }
    val guardada = v.notaPendiente == null && FotosInicio.notaRecortada(nota) == (v.estado?.nota ?: "")
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        BasicTextField(
            value = nota,
            onValueChange = {
                // Hasta 300, contadas como el servidor (un emoji cuenta uno).
                nota = if (it.codePointCount(0, it.length) <= FotosInicio.MAX_NOTA) it else it.substring(0, it.offsetByCodePoints(0, FotosInicio.MAX_NOTA))
                resultado = null
            },
            minLines = 3,
            maxLines = 6,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
            cursorBrush = SolidColor(c.marcaTexto),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = T.motivacionNota }.testTag("fotos-inicio-nota"),
            decorationBox = { campo ->
                Box(Modifier.heightIn(min = 48.dp).background(c.campo, RoundedCornerShape(Radio.control)).padding(Espacio.s), contentAlignment = Alignment.TopStart) {
                    if (nota.isEmpty()) Text(T.motivacionNota, style = MaterialTheme.typography.bodyLarge, color = c.textoTerciario)
                    campo()
                }
            },
        )
        Text(
            "${nota.codePointCount(0, nota.length)}/${FotosInicio.MAX_NOTA}",
            style = MaterialTheme.typography.bodySmall,
            color = c.textoSecundario,
            textAlign = TextAlign.End,
            modifier = Modifier.fillMaxWidth(),
        )
        val r = resultado ?: v.notaPendiente?.let { T.notaSinSenal }
        r?.let { Nota(it, Modifier.testTag("fotos-inicio-nota-resultado")) }
        BotonMarca(
            T.motivacionGuardar,
            alTocar = {
                mandando = true
                alcance.launch {
                    try {
                        resultado = when (m.guardarNota(nota)) {
                            ModeloFotosInicio.Salida.OK -> T.motivacionGuardada
                            ModeloFotosInicio.Salida.SIN_SENAL -> T.notaSinSenal
                            ModeloFotosInicio.Salida.ERROR -> T.notaError
                            else -> null
                        }
                        nota = FotosInicio.notaRecortada(nota)
                    } finally {
                        mandando = false
                    }
                }
            },
            modifier = Modifier.fillMaxWidth().testTag("fotos-inicio-nota-guardar"),
            habilitado = !guardada,
            cargando = mandando,
        )
    }
}

// ── 3. La pose ──

@Composable
private fun PoseFotoInicio(pose: FotosInicio.Pose, relleno: PaddingValues, alPreparar: (String, FotoPreparada) -> Unit) {
    val c = MyPump.colores
    Desplazable(relleno) {
        Box(
            Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m).testTag("fotos-inicio-silueta"),
            contentAlignment = Alignment.Center,
        ) {
            Silueta(pose.clave, Modifier.widthIn(max = 180.dp).fillMaxWidth().aspectRatio((SiluetasFotosInicio.ANCHO / SiluetasFotosInicio.ALTO).toFloat()))
        }
        Text(pose.instruccion, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.testTag("fotos-inicio-instruccion"))
        Nota(T.privacidad)
        BotonFotoInicio(pose.clave, T.botonFoto, "fotos-inicio-foto", primario = true, alPreparar = { alPreparar(pose.clave, it) })
    }
}

// ── 4. Revisar ──

@Composable
private fun RevisarFotoInicio(
    m: ModeloFotosInicio,
    pose: String,
    p: FotoPreparada,
    relleno: PaddingValues,
    alPreparar: (String, FotoPreparada) -> Unit,
    alUsar: (siguiente: String?) -> Unit,
) {
    val c = MyPump.colores
    var error by remember(p) { mutableStateOf<String?>(null) }
    val vistaPrevia by produceState<ImageBitmap?>(null, p) {
        value = withContext(Dispatchers.Default) {
            try {
                BitmapFactory.decodeByteArray(p.jpeg, 0, p.jpeg.size, BitmapFactory.Options().apply { inSampleSize = 2 })?.asImageBitmap()
            } catch (_: Throwable) {
                null
            }
        }
    }
    fun usar() {
        when (m.encolar(pose, p.jpeg, p.tomadaEn, p.medida)) {
            ModeloFotosInicio.Foto.GUARDADA -> {
                m.drenarEnFondo()
                alUsar(if (pose == FotosInicio.MOTIVACION) null else FotosInicio.siguiente(pose, m.faltan))
            }
            ModeloFotosInicio.Foto.TOPE -> error = T.motivacionTope
            ModeloFotosInicio.Foto.NO_SE_GUARDO -> error = T.noSeGuardo
        }
    }
    Desplazable(relleno) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(p.ancho.toFloat() / p.alto.coerceAtLeast(1)).clip(RoundedCornerShape(Radio.tarjeta)).background(c.campo).testTag("fotos-inicio-vista-previa"),
        ) {
            vistaPrevia?.let { Image(it, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize()) }
        }
        if (p.problemas.isEmpty()) {
            Row(
                Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}.testTag("fotos-inicio-bien"),
                horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
                Text(T.seVeBien, style = MaterialTheme.typography.titleMedium, color = c.texto)
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs), modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }) {
                for (problema in p.problemas) {
                    Row(
                        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}.testTag("fotos-inicio-problema-${problema.clave}"),
                        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
                    ) {
                        Icon(Iconos.Alerta, contentDescription = null, tint = c.alerta, modifier = Modifier.padding(top = 2.dp).size(20.dp))
                        Text(FotosInicio.texto(problema, p.dias), style = MaterialTheme.typography.bodyLarge, color = c.texto, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        error?.let { Nota(it, alerta = true) }
        val bloquea = FotosInicio.bloquea(p.problemas)
        if (p.problemas.isEmpty()) {
            BotonMarca(T.botonUsar, alTocar = ::usar, modifier = Modifier.fillMaxWidth().testTag("fotos-inicio-usar"))
            BotonFotoInicio(pose, T.botonOtra, "fotos-inicio-otra", primario = false, alPreparar = { alPreparar(pose, it) })
        } else {
            BotonFotoInicio(pose, T.botonOtra, "fotos-inicio-otra", primario = true, alPreparar = { alPreparar(pose, it) })
            if (!bloquea) CapsulaBoton(T.botonUsarIgual, primario = false, Modifier.clickable(role = Role.Button, onClick = ::usar).testTag("fotos-inicio-usar-igual"))
        }
    }
}

// ── El botón de foto ──

/**
 * «Sacar o elegir foto» (y «Sacar otra», «Agregar foto»): la cámara o la galería con [BotonFoto], y la foto ya preparada
 * para revisar. En el modo de prueba ([Entorno.fotosInicioDePrueba]) arma una foto de mentira con ese aspecto.
 */
@Composable
private fun BotonFotoInicio(pose: String, texto: String, etiqueta: String, primario: Boolean, alPreparar: (FotoPreparada) -> Unit) {
    val alcance = LocalAlcanceApp.current
    var ilegible by remember { mutableStateOf(false) }
    var preparando by remember { mutableStateOf(false) }
    fun preparar(jpeg: ByteArray?, tomada: OffsetDateTime?) {
        preparando = true
        alcance.launch {
            val p = try {
                withContext(Dispatchers.Default) { jpeg?.let { PreparacionFotoInicio.preparar(pose, it, tomada) } }
            } finally {
                preparando = false
            }
            ilegible = p == null
            if (p != null) alPreparar(p)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        val dePrueba = Entorno.fotosInicioDePrueba
        if (dePrueba != null) {
            CapsulaBoton(
                texto, primario,
                Modifier.clickable(enabled = !preparando, role = Role.Button) {
                    preparando = true
                    alcance.launch {
                        val jpeg = withContext(Dispatchers.Default) {
                            // El escenario al tocar, no el de la última composición: la prueba lo cambia entre una foto y otra.
                            ReduccionFoto.jpeg(FotoSinteticaFotosInicio.jpeg(Entorno.fotosInicioDePrueba ?: dePrueba), FotosInicio.MAX_PX, FotosInicio.CALIDAD)
                        }
                        preparar(jpeg, null)
                    }
                }.testTag(etiqueta),
                icono = true,
            )
        } else {
            BotonFoto(
                clave = "fotos-inicio-$pose",
                maxPx = FotosInicio.MAX_PX,
                calidad = FotosInicio.CALIDAD,
                alElegir = { preparar(it, null) },
                alElegirConFecha = { jpeg, tomada -> preparar(jpeg, tomada) },
                modifier = Modifier.fillMaxWidth(),
                habilitado = !preparando,
            ) {
                CapsulaBoton(texto, primario, Modifier.testTag(etiqueta), icono = true)
            }
        }
        if (ilegible) Nota(T.ilegible, alerta = true)
    }
}

/** El aspecto de los botones de la marca, para lo que se toca por fuera (el menú de la foto, o un clic propio). */
@Composable
private fun CapsulaBoton(texto: String, primario: Boolean, modifier: Modifier = Modifier, icono: Boolean = false) {
    val c = MyPump.colores
    val tinta = if (primario) c.sobreMarca else c.texto
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .background(if (primario) c.marca else c.campo, CircleShape)
            .padding(horizontal = Espacio.m, vertical = Espacio.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs, Alignment.CenterHorizontally),
    ) {
        if (icono) Icon(Iconos.Camara, contentDescription = null, tint = tinta, modifier = Modifier.size(20.dp))
        Text(texto, style = MaterialTheme.typography.titleMedium, color = tinta, textAlign = TextAlign.Center)
    }
}

// ── Las siluetas y las miniaturas ──

/** La silueta de referencia de la pose, dibujada con los trazos comunes ([SiluetasFotosInicio]) y los colores del tema. */
@Composable
fun Silueta(pose: String, modifier: Modifier = Modifier) {
    val s = SiluetasFotosInicio.de(pose) ?: return
    val c = MyPump.colores
    val contorno = remember(s) { trazado(s.contorno) }
    val detalle = remember(s) { trazado(s.detalle) }
    val relleno = c.marcaSuave
    val linea = c.marcaTexto
    // Decorativa: el nombre de la pose lo dice el texto de al lado.
    Canvas(modifier) {
        val escala = minOf(size.width / SiluetasFotosInicio.ANCHO.toFloat(), size.height / SiluetasFotosInicio.ALTO.toFloat())
        val dx = (size.width - SiluetasFotosInicio.ANCHO.toFloat() * escala) / 2
        val dy = (size.height - SiluetasFotosInicio.ALTO.toFloat() * escala) / 2
        translate(dx, dy) {
            scale(escala, escala, pivot = Offset.Zero) {
                val grosor = 1.6f
                drawPath(contorno, relleno)
                drawPath(contorno, linea, style = Stroke(width = grosor))
                drawPath(detalle, linea.copy(alpha = 0.7f), style = Stroke(width = grosor * 0.8f))
            }
        }
    }
}

private fun trazado(trazo: String): Path = Path().apply {
    for (o in SiluetasFotosInicio.ordenes(trazo)) {
        when (o) {
            is SiluetasFotosInicio.Orden.Mover -> moveTo(o.x.toFloat(), o.y.toFloat())
            is SiluetasFotosInicio.Orden.Curva -> cubicTo(o.x1.toFloat(), o.y1.toFloat(), o.x2.toFloat(), o.y2.toFloat(), o.x.toFloat(), o.y.toFloat())
            SiluetasFotosInicio.Orden.Cerrar -> close()
        }
    }
}

/** La foto del disco, reducida fuera del hilo principal. */
@Composable
private fun MiniaturaLocal(archivo: File) {
    val imagen by produceState<ImageBitmap?>(null, archivo) {
        value = withContext(Dispatchers.IO) {
            try {
                BitmapFactory.decodeFile(archivo.path, BitmapFactory.Options().apply { inSampleSize = 8 })?.asImageBitmap()
            } catch (_: Exception) {
                null
            }
        }
    }
    imagen?.let { Image(it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
}
