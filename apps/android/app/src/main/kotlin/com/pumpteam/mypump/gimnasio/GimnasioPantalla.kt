package com.pumpteam.mypump.gimnasio

import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.BorradorGimnasio
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloCasa
import com.pumpteam.mypump.datos.ModeloGimnasio
import com.pumpteam.mypump.datos.PendienteGimnasio
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
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
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.Casa
import com.pumpteam.mypump.reglas.EstadoGimnasio
import com.pumpteam.mypump.reglas.Gimnasio
import com.pumpteam.mypump.reglas.ItemGimnasio
import com.pumpteam.mypump.reglas.PreguntaGimnasio
import com.pumpteam.mypump.reglas.TextosGimnasio as T
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Todo lo que cambia en el modelo: leerlo acá hace que la pantalla que lo llama se redibuje. */
private data class Vista(
    val estado: EstadoGimnasio?,
    val cola: List<PendienteGimnasio>,
    val subiendo: String?,
    val urls: Map<String, String>,
    val avisoFoto: Gimnasio.AvisoFoto?,
    val avisoEnvio: ModeloGimnasio.AvisoEnvio?,
    val subidasEnvio: Int,
    val totalEnvio: Int,
    val borrador: BorradorGimnasio,
)

@Composable
private fun observar(m: ModeloGimnasio): Vista {
    val estado by m.estado.collectAsStateWithLifecycle()
    val cola by m.cola.collectAsStateWithLifecycle()
    val subiendo by m.subiendo.collectAsStateWithLifecycle()
    val urls by m.urls.collectAsStateWithLifecycle()
    val avisoFoto by m.avisoFoto.collectAsStateWithLifecycle()
    val avisoEnvio by m.avisoEnvio.collectAsStateWithLifecycle()
    val subidas by m.subidasEnvio.collectAsStateWithLifecycle()
    val total by m.totalEnvio.collectAsStateWithLifecycle()
    val borrador by m.borrador.collectAsStateWithLifecycle()
    return Vista(estado, cola, subiendo, urls, avisoFoto, avisoEnvio, subidas, total, borrador)
}

/** La tarjeta «Tu gimnasio» arriba en Entreno. Sin cuenta, con la palanca apagada o sin el servidor nuevo, no existe. */
@Composable
fun TarjetaGimnasioDe(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val g by modelo.gimnasio.collectAsStateWithLifecycle()
    val m = g ?: return
    observar(m)
    // Con un borrador de casa la tarjeta no habla de zonas ni de fotos.
    val casa by modelo.casa.collectAsStateWithLifecycle()
    val estadoCasa = casa?.estado?.collectAsStateWithLifecycle()?.value
    if (!m.tarjetaVisible) return
    val c = MyPump.colores
    val navegacion = LocalNavegacion.current
    // «¿Entrenás en casa? Tocá acá»: mientras no entrene en casa y se pueda cambiar, un botón grande que lleva al interruptor.
    val ofrecerCasa = estadoCasa?.let { Casa.interruptor(it) }?.let { !it.prendido && it.sePuedeMover } == true
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
    Row(
        Modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .clip(RoundedCornerShape(Radio.tarjeta))
            .clickable(role = Role.Button) { navegacion?.gimnasio = true }
            .padding(Espacio.m)
            .testTag("gimnasio-tarjeta"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(Modifier.size(42.dp).background(c.marcaSuave, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Iconos.Pesa, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(T.tarjetaTitulo, style = MaterialTheme.typography.titleMedium, color = c.texto)
            Text(
                if (Casa.pantalla(estadoCasa) == Casa.Pantalla.LISTA) Casa.Textos.LISTA_TITULO else detalleTarjeta(m),
                style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario,
            )
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
    if (ofrecerCasa) {
        BotonSecundario(Casa.Textos.TARJETA, alTocar = { navegacion?.gimnasio = true }, modifier = Modifier.fillMaxWidth().testTag("casa-tarjeta"), tono = c.marcaTexto)
    }
    }
}

private fun detalleTarjeta(m: ModeloGimnasio): String = when (m.pantalla) {
    Gimnasio.Pantalla.ZONAS -> if (m.faltantes.isEmpty()) T.revisarYEnviar else T.faltanZonas(m.faltantes.size)
    Gimnasio.Pantalla.RECIBIDO -> T.recibido
    Gimnasio.Pantalla.PREGUNTAS -> T.confirmarTarjeta
    else -> T.inicioBajada
}

private const val A_REVISAR = "revisar"
private const val A_YA_NO_ESTA = "ya-no-esta"
private const val A_ZONA = "zona:"

/**
 * Lo que va arriba de todo en la raíz de Mi gimnasio (el interruptor «Entreno en casa»), dentro de lo que se desplaza: con la
 * letra más grande no le saca lugar fijo a la pantalla. null: no hay (palanca `casa` apagada, o no es la raíz).
 */
internal val LocalCabezaGimnasio = compositionLocalOf<(@Composable () -> Unit)?> { null }

/**
 * Elige la pantalla según lo que diga el servidor (`CONTRATO_APP.md`, sección 4). Con [casa] habilitada (palanca `casa`,
 * `cola-b/CONTRATO_APP.md`, sección 3) suma el interruptor «Entreno en casa» y, en casa, la lista en lugar de las zonas.
 */
@Composable
fun GimnasioPantalla(m: ModeloGimnasio, alVolver: () -> Unit, casa: ModeloCasa? = null) {
    val v = observar(m)
    val estadoCasa = casa?.estado?.collectAsStateWithLifecycle()?.value
    val pantallaCasa = Casa.pantalla(estadoCasa)
    // Al volver de una muerte del proceso el estado todavía no está: se decide después de preguntar.
    var preguntado by remember { mutableStateOf(false) }
    LaunchedEffect(m) {
        if (m.palancaRecordada) {
            m.refrescar()
            // Entrenar en casa: junto con el gimnasio, y solo con su palanca.
            if (casa?.palancaRecordada == true) casa.refrescar()
            m.drenarEnFondo()
        }
        preguntado = true
    }
    LaunchedEffect(preguntado, v.estado == null) { if (preguntado && v.estado == null) alVolver() }

    var destino by rememberSaveable { mutableStateOf("") }
    // Si la carga pasó a otra etapa, se vuelve a la raíz: lo que importa es lo que dice ella.
    val etapa = "${m.pantalla}-${v.borrador.envio != null}-$pantallaCasa"
    var etapaVista by rememberSaveable { mutableStateOf(etapa) }
    if (etapa != etapaVista) {
        etapaVista = etapa
        destino = ""
    }
    BackHandler(enabled = destino.isNotEmpty()) { destino = "" }

    val zona = destino.takeIf { it.startsWith(A_ZONA) }?.removePrefix(A_ZONA)?.let { k -> Gimnasio.zonas.firstOrNull { it.clave == k } }
    val titulo = when {
        zona != null -> zona.nombre
        destino == A_REVISAR -> T.revisarTitulo
        destino == A_YA_NO_ESTA -> T.yaNoEsta
        else -> T.tarjetaTitulo
    }
    MarcoPantalla(titulo, alVolver = { if (destino.isNotEmpty()) destino = "" else alVolver() }) { relleno ->
        when {
            v.estado == null -> Unit
            zona != null -> ZonaGimnasio(m, zona, relleno)
            destino == A_REVISAR -> RevisarGimnasio(m, relleno)
            destino == A_YA_NO_ESTA -> YaNoEstaGimnasio(m, relleno)
            v.borrador.envio != null -> EnviandoGimnasio(m, relleno)
            else -> {
                // La raíz: con casa habilitada, el interruptor arriba de todo (salvo en las preguntas, que van de a una).
                val cabeza: (@Composable () -> Unit)? = if (casa != null && estadoCasa != null) ({ InterruptorCasa(casa) }) else null
                CompositionLocalProvider(LocalCabezaGimnasio provides cabeza) {
                    when {
                        casa != null && pantallaCasa == Casa.Pantalla.LISTA -> CasaLista(casa, relleno)
                        casa != null && pantallaCasa == Casa.Pantalla.VIGENTE -> CasaVigente(casa, relleno)
                        else -> when (m.pantalla) {
                            Gimnasio.Pantalla.INICIO -> ArranqueGimnasio(m, relleno)
                            Gimnasio.Pantalla.ZONAS -> ZonasGimnasio(m, relleno, alAbrir = { destino = it })
                            Gimnasio.Pantalla.RECIBIDO -> RecibidoGimnasio(relleno)
                            Gimnasio.Pantalla.PREGUNTAS -> PreguntasGimnasio(m, relleno)
                            Gimnasio.Pantalla.LISTO -> ListoGimnasio(m, relleno, alAbrir = { destino = it })
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun Desplazable(relleno: PaddingValues, contenido: @Composable ColumnScope.() -> Unit) {
    val cabeza = LocalCabezaGimnasio.current
    Column(
        Modifier
            .padding(relleno)
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Espacio.m)
            .padding(top = Espacio.s, bottom = Espacio.xl + LocalRellenoInferior.current),
        verticalArrangement = Arrangement.spacedBy(Espacio.m),
    ) {
        cabeza?.invoke()
        contenido()
    }
}

/** Texto suave de error o estado, siempre con el mismo aspecto. */
@Composable
internal fun NotaGimnasio(texto: String, modifier: Modifier = Modifier, alerta: Boolean = false) {
    val c = MyPump.colores
    Text(
        texto,
        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
        color = if (alerta) c.alerta else c.textoSecundario,
        modifier = modifier.fillMaxWidth().then(if (alerta) Modifier.semantics { liveRegion = LiveRegionMode.Polite } else Modifier),
    )
}

@Composable
private fun AvisoFoto(aviso: Gimnasio.AvisoFoto?) {
    if (aviso != null) NotaGimnasio(if (aviso == Gimnasio.AvisoFoto.TOPE) T.tope else T.fotoRechazada, Modifier.testTag("gimnasio-aviso-foto"), alerta = true)
}

/** Por qué no salió lo enviado. */
@Composable
private fun AvisoEnvio(aviso: ModeloGimnasio.AvisoEnvio?) {
    val texto = when (aviso) {
        is ModeloGimnasio.AvisoEnvio.Faltan -> T.faltanZonas(aviso.zonas.size)
        ModeloGimnasio.AvisoEnvio.SinNovedad -> T.sinNovedad
        ModeloGimnasio.AvisoEnvio.Error -> T.errorGenerico
        null -> return
    }
    NotaGimnasio(texto, Modifier.testTag("gimnasio-aviso-envio"), alerta = true)
}

private fun textoDe(s: ModeloGimnasio.Salida): String? = when (s) {
    ModeloGimnasio.Salida.OK -> null
    ModeloGimnasio.Salida.SIN_SENAL -> T.sinSenal
    else -> T.errorGenerico
}

/** Sin carga abierta no hay nada que leer: abre una sola y sigue a las zonas. Solo se queda acá si no se pudo. */
@Composable
private fun ArranqueGimnasio(m: ModeloGimnasio, relleno: PaddingValues) {
    val alcance = LocalAlcanceApp.current
    var error by remember { mutableStateOf<String?>(null) }
    var ocupado by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        try {
            if (m.abierta == null) error = textoDe(m.empezar()) ?: T.sinSenal.takeIf { m.abierta == null }
        } finally {
            ocupado = false
        }
    }
    val mensaje = error
    if (mensaje == null) {
        Box(Modifier.fillMaxSize().padding(relleno).testTag("gimnasio-arrancando"), contentAlignment = Alignment.Center) {
            if (ocupado) CircularProgressIndicator()
        }
    } else {
        Desplazable(relleno) {
            NotaGimnasio(mensaje, alerta = true)
            BotonMarca(
                T.botonReintentar,
                alTocar = {
                    ocupado = true
                    alcance.launch {
                        try {
                            if (m.abierta == null) error = textoDe(m.empezar()) ?: T.sinSenal.takeIf { m.abierta == null }
                        } finally {
                            ocupado = false
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth().testTag("gimnasio-reintentar"),
                habilitado = !ocupado,
            )
        }
    }
}

@Composable
private fun ZonasGimnasio(m: ModeloGimnasio, relleno: PaddingValues, alAbrir: (String) -> Unit) {
    val v = observar(m)
    val c = MyPump.colores
    Desplazable(relleno) {
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            if (m.abierta?.modo == "completa" && m.faltantes.isNotEmpty()) {
                Text(T.faltanZonas(m.faltantes.size), style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.semantics { heading() })
            }
            NotaGimnasio(T.consejoPermiso)
            AvisoFoto(v.avisoFoto)
            AvisoEnvio(v.avisoEnvio)
        }
        Tarjeta(relleno = 0.dp, espaciado = 0.dp) {
            Gimnasio.zonas.forEachIndexed { i, z ->
                if (i > 0) Separador(sangria = 48.dp)
                FilaZona(m, z, (v.avisoEnvio as? ModeloGimnasio.AvisoEnvio.Faltan)?.zonas?.contains(z.clave) == true) { alAbrir(A_ZONA + z.clave) }
            }
        }
        BotonMarca(T.revisarYEnviar, alTocar = { alAbrir(A_REVISAR) }, modifier = Modifier.fillMaxWidth().testTag("gimnasio-revisar"))
    }
}

private fun detalleZona(m: ModeloGimnasio, clave: String): String {
    val n = m.fotos(clave).size
    return when {
        n > 0 -> T.cuentaFotos(n)
        clave in m.noHay -> T.noHayCorto
        clave == Gimnasio.ZONA_OPCIONAL -> T.opcional
        else -> T.sinFotos
    }
}

@Composable
private fun FilaZona(m: ModeloGimnasio, z: Gimnasio.Zona, falta: Boolean, alTocar: () -> Unit) {
    val c = MyPump.colores
    val lista = m.fotos(z.clave).isNotEmpty() || z.clave in m.noHay
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = alTocar).padding(horizontal = Espacio.m, vertical = Espacio.xs).testTag("gimnasio-zona-${z.clave}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Marca(lista)
        Column(Modifier.weight(1f)) {
            Text(z.nombre, style = MaterialTheme.typography.bodyLarge, color = c.texto)
            Text(detalleZona(m, z.clave), style = MaterialTheme.typography.bodySmall, color = if (falta) c.alerta else c.textoSecundario)
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

/** El círculo de hecho o pendiente. Decorativo: el estado lo dice la fila. */
@Composable
internal fun Marca(hecha: Boolean) {
    val c = MyPump.colores
    if (hecha) {
        Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
    } else {
        Box(Modifier.size(22.dp).padding(2.dp).background(c.textoTerciario, CircleShape).padding(2.dp).background(c.tarjeta, CircleShape))
    }
}

@Composable
private fun BotonAgregarFoto(claveBoton: String, puede: Boolean, alElegir: (ByteArray) -> Unit) {
    val c = MyPump.colores
    BotonFoto(
        clave = claveBoton,
        maxPx = Gimnasio.MAX_PX,
        calidad = Gimnasio.CALIDAD,
        alElegir = alElegir,
        modifier = Modifier.fillMaxWidth(),
        habilitado = puede,
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 54.dp).background(if (puede) c.marca else c.textoTerciario, CircleShape).padding(horizontal = Espacio.m, vertical = Espacio.xs).testTag("gimnasio-agregar-foto"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.xs, Alignment.CenterHorizontally),
        ) {
            Icon(Iconos.Camara, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(20.dp))
            Text(T.agregarFoto, style = MaterialTheme.typography.titleMedium, color = c.sobreMarca, textAlign = TextAlign.Center)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ZonaGimnasio(m: ModeloGimnasio, zona: Gimnasio.Zona, relleno: PaddingValues) {
    val v = observar(m)
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    var error by remember { mutableStateOf<String?>(null) }
    val fotos = m.fotos(zona.clave)
    val noHay = zona.clave in m.noHay
    DisposableEffect(zona.clave) { onDispose { m.limpiarAvisoFoto() } }

    LaunchedEffect(fotos.size) {
        val a = m.abierta ?: return@LaunchedEffect
        val ids = fotos.filter { it.archivoLocal == null }.map { it.id }
        if (ids.isNotEmpty()) m.firmar(a.id, ids)
    }

    Desplazable(relleno) {
        Column(Modifier.semantics(mergeDescendants = true) {}.testTag("gimnasio-consejo"), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Text(zona.pedido, style = MaterialTheme.typography.titleMedium, color = c.texto)
            Text(T.consejoCamara, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        }
        if (fotos.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.s), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                for (f in fotos) {
                    key(f.id) {
                        MiniaturaFoto(f, v.urls[f.id]) {
                            alcance.launch { error = textoDe(m.borrarFoto(f.id)) }
                        }
                    }
                }
            }
        }
        AvisoFoto(v.avisoFoto)
        error?.let { NotaGimnasio(it, alerta = true) }
        BotonAgregarFoto("gimnasio-${zona.clave}", m.puedeAgregar) { jpeg ->
            when (m.agregar(zona.clave, jpeg)) {
                ModeloGimnasio.Foto.GUARDADA -> {
                    error = null
                    m.drenarEnFondo()
                }
                ModeloGimnasio.Foto.TOPE -> error = T.tope
                ModeloGimnasio.Foto.NO_SE_GUARDO -> error = T.noSeGuardo
            }
        }
        if (zona.clave != Gimnasio.ZONA_OPCIONAL && m.abierta?.modo == "completa" && fotos.isEmpty()) {
            OpcionFila(T.noHay, noHay, "gimnasio-no-hay") { m.marcarNoHay(zona.clave, !noHay) }
        }
    }
}

private val LADO_MINIATURA = 104.dp

@Composable
private fun MiniaturaFoto(foto: ModeloGimnasio.VistaFoto, url: String?, borrar: () -> Unit) {
    val c = MyPump.colores
    Box(Modifier.size(LADO_MINIATURA).clip(RoundedCornerShape(Radio.control)).background(c.campo)) {
        val local = foto.archivoLocal
        if (local != null) {
            MiniaturaLocal(local)
        } else {
            ImagenRemota(url, LADO_MINIATURA, Modifier.fillMaxSize()) { MarcadorFoto() }
        }
        if (foto.subiendo || foto.esperando) {
            Text(
                if (foto.subiendo) T.subiendo else T.esperandoSenal,
                style = MaterialTheme.typography.labelSmall,
                color = Color.White,
                maxLines = 2,
                textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Color.Black.copy(alpha = 0.55f)).padding(4.dp),
            )
        }
        Box(
            Modifier.align(Alignment.TopEnd).size(48.dp).clickable(role = Role.Button, onClick = borrar).semantics { contentDescription = T.borrarFoto }.testTag("gimnasio-borrar-foto"),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(26.dp).background(Color.Black.copy(alpha = 0.6f), CircleShape), contentAlignment = Alignment.Center) {
                Icon(Iconos.Cerrar, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
            }
        }
    }
}

@Composable
private fun MarcadorFoto() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Icon(Iconos.Foto, contentDescription = null, tint = MyPump.colores.textoTerciario, modifier = Modifier.size(24.dp))
    }
}

/** La foto del disco, reducida fuera del hilo principal: en una zona puede haber varias de 1600 px. */
@Composable
private fun MiniaturaLocal(archivo: File) {
    val imagen by produceState<ImageBitmap?>(null, archivo) {
        value = withContext(Dispatchers.IO) {
            try {
                BitmapFactory.decodeFile(archivo.path, BitmapFactory.Options().apply { inSampleSize = 4 })?.asImageBitmap()
            } catch (_: Exception) {
                null
            }
        }
    }
    imagen?.let { Image(it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
}

@Composable
private fun Campo(
    valor: String,
    alCambiar: (String) -> Unit,
    marcador: String,
    etiqueta: String,
    modifier: Modifier = Modifier,
    minLineas: Int = 1,
    maxLineas: Int = 1,
    teclado: KeyboardOptions = KeyboardOptions.Default,
) {
    val c = MyPump.colores
    BasicTextField(
        value = valor,
        onValueChange = alCambiar,
        minLines = minLineas,
        maxLines = maxLineas,
        singleLine = maxLineas == 1,
        keyboardOptions = teclado,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
        cursorBrush = SolidColor(c.marcaTexto),
        modifier = modifier.fillMaxWidth().semantics { contentDescription = marcador }.testTag(etiqueta),
        decorationBox = { campo ->
            Box(Modifier.heightIn(min = 48.dp).background(c.campo, RoundedCornerShape(Radio.control)).padding(Espacio.s), contentAlignment = Alignment.CenterStart) {
                if (valor.isEmpty()) Text(marcador, style = MaterialTheme.typography.bodyLarge, color = c.textoTerciario)
                campo()
            }
        },
    )
}

@Composable
private fun RevisarGimnasio(m: ModeloGimnasio, relleno: PaddingValues) {
    val v = observar(m)
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    var nota by rememberSaveable { mutableStateOf(v.borrador.nota) }
    Desplazable(relleno) {
        Tarjeta(espaciado = Espacio.xs) {
            for (z in Gimnasio.zonas) {
                Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    Text(z.nombre, style = MaterialTheme.typography.bodyMedium, color = c.texto, modifier = Modifier.weight(1f))
                    Text(detalleZona(m, z.clave), style = MaterialTheme.typography.bodyMedium, color = if (z.clave in m.faltantes) c.alerta else c.textoSecundario)
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Campo(
                nota,
                alCambiar = {
                    nota = Gimnasio.notaRecortada(it)
                    m.fijarNota(nota)
                },
                marcador = T.notaPlaceholder,
                etiqueta = "gimnasio-nota",
                minLineas = 3,
                maxLineas = 6,
            )
            Text("${nota.length}/${Gimnasio.MAX_NOTA}", style = MaterialTheme.typography.bodySmall, color = c.textoSecundario, textAlign = TextAlign.End, modifier = Modifier.fillMaxWidth())
        }
        if (m.faltantes.isNotEmpty()) NotaGimnasio(T.faltanZonas(m.faltantes.size), Modifier.testTag("gimnasio-faltan"), alerta = true)
        AvisoEnvio(v.avisoEnvio)
        BotonMarca(
            T.botonEnviar,
            alTocar = {
                m.fijarNota(nota)
                alcance.launch { m.enviarCarga() }
            },
            modifier = Modifier.fillMaxWidth().testTag("gimnasio-enviar"),
            habilitado = m.puedeEnviar,
        )
    }
}

@Composable
private fun Centrado(relleno: PaddingValues, etiqueta: String, contenido: @Composable ColumnScope.() -> Unit) {
    val cabeza = LocalCabezaGimnasio.current
    if (cabeza != null) {
        // Con el interruptor de casa arriba: él primero y el mensaje debajo, todo en el mismo desplazamiento.
        Column(
            Modifier.padding(relleno).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = Espacio.m)
                .padding(top = Espacio.s, bottom = Espacio.xl + LocalRellenoInferior.current),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
        ) {
            cabeza()
            Column(
                Modifier.fillMaxWidth().padding(Espacio.s).testTag(etiqueta),
                verticalArrangement = Arrangement.spacedBy(Espacio.m),
                horizontalAlignment = Alignment.CenterHorizontally,
                content = contenido,
            )
        }
        return
    }
    Column(
        Modifier.padding(relleno).fillMaxSize().verticalScroll(rememberScrollState()).padding(Espacio.l).testTag(etiqueta),
        verticalArrangement = Arrangement.spacedBy(Espacio.m, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
        content = contenido,
    )
}

@Composable
private fun EnviandoGimnasio(m: ModeloGimnasio, relleno: PaddingValues) {
    val v = observar(m)
    val c = MyPump.colores
    Centrado(relleno, "gimnasio-enviando") {
        CircularProgressIndicator(color = c.marcaTexto)
        if (v.cola.isNotEmpty()) {
            Text(
                T.subiendoFotos(v.subidasEnvio, maxOf(v.totalEnvio, v.subidasEnvio + v.cola.size)),
                style = MaterialTheme.typography.titleMedium,
                color = c.texto,
                textAlign = TextAlign.Center,
            )
        }
        Text(T.enviandoSeguir, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, textAlign = TextAlign.Center)
        BotonSecundario(T.volverAEditar, alTocar = { m.cancelarEnvio() }, modifier = Modifier.testTag("gimnasio-volver-editar"))
    }
}

@Composable
private fun RecibidoGimnasio(relleno: PaddingValues) {
    val c = MyPump.colores
    Centrado(relleno, "gimnasio-recibido") {
        Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(48.dp))
        Text(T.recibido, style = MaterialTheme.typography.titleMedium, color = c.texto, textAlign = TextAlign.Center)
    }
}

@Composable
private fun ListoGimnasio(m: ModeloGimnasio, relleno: PaddingValues, alAbrir: (String) -> Unit) {
    observar(m)
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    var error by remember { mutableStateOf<String?>(null) }
    val vigente = m.vigente
    val titulo = when (vigente?.resultado) {
        "sin_cambios" -> T.sinCambios
        "adaptada", "plan_nuevo" -> Gimnasio.fechaCorta(vigente.publicadoEn)?.let(T::adaptadoPorMati)
        else -> null
    }
    fun empezar(modo: String) {
        alcance.launch { error = textoDe(m.empezar(modo)) }
    }
    Desplazable(relleno) {
        titulo?.let { Text(it, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.testTag("gimnasio-resultado")) }
        error?.let { NotaGimnasio(it, alerta = true) }
        for (z in Gimnasio.zonas) {
            val equipos = vigente?.equipos.orEmpty().filter { it.zona == z.clave }
            if (equipos.isEmpty()) continue
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Text(z.nombre, style = MaterialTheme.typography.labelLarge, color = c.textoSecundario, modifier = Modifier.semantics { heading() })
                Tarjeta(espaciado = Espacio.xs) {
                    for (e in equipos) {
                        Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                            Text(e.nombre, style = MaterialTheme.typography.bodyLarge, color = c.texto, modifier = Modifier.weight(1f))
                            if (e.cantidad > 1) Text("×${e.cantidad}", style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
                        }
                    }
                }
            }
        }
        BotonSecundario(T.faltaAlgo, alTocar = { empezar("parcial") }, modifier = Modifier.fillMaxWidth().testTag("gimnasio-falta-algo"))
        BotonSecundario(T.yaNoEsta, alTocar = { alAbrir(A_YA_NO_ESTA) }, modifier = Modifier.fillMaxWidth().testTag("gimnasio-ya-no-esta"))
        BotonSecundario(T.cambieDeGimnasio, alTocar = { empezar("completa") }, modifier = Modifier.fillMaxWidth().testTag("gimnasio-cambie"))
    }
}

@Composable
private fun YaNoEstaGimnasio(m: ModeloGimnasio, relleno: PaddingValues) {
    observar(m)
    val alcance = LocalAlcanceApp.current
    var marcados by rememberSaveable { mutableStateOf(emptyList<String>()) }
    var error by remember { mutableStateOf<String?>(null) }
    Desplazable(relleno) {
        Text(T.marcarLoQueNoEsta, style = MaterialTheme.typography.titleMedium, color = MyPump.colores.texto, modifier = Modifier.semantics { heading() })
        for (e in m.vigente?.equipos.orEmpty()) {
            OpcionFila(e.nombre, e.tipo in marcados, "gimnasio-quitar-${e.tipo}") {
                marcados = if (e.tipo in marcados) marcados - e.tipo else marcados + e.tipo
            }
        }
        error?.let { NotaGimnasio(it, alerta = true) }
        BotonMarca(
            T.botonEnviar,
            alTocar = {
                val elegidos = marcados
                alcance.launch {
                    val r = m.empezar("parcial")
                    if (r != ModeloGimnasio.Salida.OK || m.abierta?.modo != "parcial") {
                        error = if (r == ModeloGimnasio.Salida.SIN_SENAL) T.sinSenal else T.errorGenerico
                        return@launch
                    }
                    for (t in elegidos) if (t !in m.borrador.value.quitar) m.alternarQuitar(t)
                    m.enviarCarga()
                }
            },
            modifier = Modifier.fillMaxWidth().testTag("gimnasio-enviar-quitar"),
            habilitado = marcados.isNotEmpty(),
        )
    }
}

/** Una opción para tocar: en casilla (varias a la vez) o en botón de radio (una sola). */
@Composable
private fun OpcionFila(texto: String, marcada: Boolean, etiqueta: String, unica: Boolean = false, accion: () -> Unit) {
    val c = MyPump.colores
    val seleccion = if (unica) {
        Modifier.selectable(selected = marcada, role = Role.RadioButton, onClick = accion)
    } else {
        Modifier.toggleable(value = marcada, role = Role.Checkbox, onValueChange = { accion() })
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(Radio.control)).background(c.campo).then(seleccion).padding(Espacio.s).testTag(etiqueta),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Marca(marcada)
        Text(texto, style = MaterialTheme.typography.bodyLarge, color = c.texto, modifier = Modifier.weight(1f))
    }
}

/** Una pregunta por pantalla: con 18 juntas no se contesta ninguna. */
@Composable
private fun PreguntasGimnasio(m: ModeloGimnasio, relleno: PaddingValues) {
    val v = observar(m)
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    var indice by rememberSaveable { mutableStateOf(0) }
    val ps = m.abierta?.preguntas.orEmpty()
    if (ps.isEmpty()) {
        RecibidoGimnasio(relleno)
        return
    }
    val i = indice.coerceIn(0, ps.size - 1)
    Column(Modifier.padding(relleno).fillMaxSize().imePadding()) {
        Column(Modifier.padding(horizontal = Espacio.m).padding(top = Espacio.s), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Text(T.preguntaDe(i + 1, ps.size), style = MaterialTheme.typography.labelLarge, color = c.marcaTexto, modifier = Modifier.testTag("gimnasio-numero-pregunta"))
            LinearProgressIndicator(progress = { (i + 1f) / ps.size }, color = c.marcaTexto, trackColor = c.campo, modifier = Modifier.fillMaxWidth())
            val n = Gimnasio.fotosPedidas(ps, v.borrador.respuestas)
            if (n > 0) NotaGimnasio(T.necesitamosFotos(n), Modifier.testTag("gimnasio-necesitamos"))
            AvisoFoto(v.avisoFoto)
            if (v.avisoEnvio != null) NotaGimnasio(T.errorGenerico, alerta = true)
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(Espacio.m), verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
            key(ps[i].id) { PreguntaVista(m, ps[i]) }
        }
        Row(Modifier.padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m + LocalRellenoInferior.current), horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            if (i > 0) BotonSecundario(T.anterior, alTocar = { indice = i - 1 }, modifier = Modifier.weight(1f).testTag("gimnasio-anterior"))
            if (i < ps.size - 1) {
                BotonMarca(T.siguiente, alTocar = { indice = i + 1 }, modifier = Modifier.weight(1f).testTag("gimnasio-siguiente"))
            } else {
                BotonMarca(T.botonEnviar, alTocar = { alcance.launch { m.enviarRespuestas() } }, modifier = Modifier.weight(1f).testTag("gimnasio-enviar-respuestas"))
            }
        }
    }
}

private val NO_SE = ValorJson.Texto("no_se")

@Composable
private fun ColumnScope.PreguntaVista(m: ModeloGimnasio, p: PreguntaGimnasio) {
    val v = observar(m)
    val valor = v.borrador.respuestas[p.id]
    val noSe = valor == NO_SE
    val c = MyPump.colores

    LaunchedEffect(p.id) {
        val a = m.abierta ?: return@LaunchedEffect
        val ids = p.fotos + p.items.flatMap { it.fotos }
        if (ids.isNotEmpty()) m.firmar(a.id, ids)
    }

    Text(p.texto, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = c.texto, modifier = Modifier.semantics { heading() })
    FotosDeReferencia(p.fotos, v.urls)
    when (p.clase) {
        PreguntaGimnasio.Clase.ELEGIR -> Elegir(m, p, valor)
        PreguntaGimnasio.Clase.NUMERO -> Numero(m, p, valor, noSe)
        PreguntaGimnasio.Clase.CONFIRMAR -> for (item in p.items) ItemConfirmar(m, p, item, valor, v.urls)
        PreguntaGimnasio.Clase.FOTO -> PedirFoto(m, p, valor, v)
        PreguntaGimnasio.Clase.DESCONOCIDA -> Unit
    }
    if (p.clase != PreguntaGimnasio.Clase.FOTO && p.clase != PreguntaGimnasio.Clase.CONFIRMAR) {
        OpcionFila(T.noSe, noSe, "gimnasio-no-se", unica = !p.multiple) { m.responder(p.id, if (noSe) null else NO_SE) }
    }
}

@Composable
private fun FotosDeReferencia(ids: List<String>, urls: Map<String, String>) {
    if (ids.isEmpty()) return
    val lado = 110.dp
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        for (id in ids) {
            Box(Modifier.size(lado).clip(RoundedCornerShape(Radio.control)).background(MyPump.colores.campo)) {
                ImagenRemota(urls[id], lado, Modifier.fillMaxSize()) { MarcadorFoto() }
            }
        }
    }
}

@Composable
private fun Elegir(m: ModeloGimnasio, p: PreguntaGimnasio, valor: ValorJson?) {
    if (p.multiple) {
        NotaGimnasio(T.marcarTodas)
        val actuales = (valor as? ValorJson.Lista)?.elementos.orEmpty().mapNotNull { it.comoTexto }.toSet()
        for (o in p.opciones) {
            OpcionFila(o.texto, o.valor in actuales, "gimnasio-opcion-${o.valor}") {
                // Lo de este momento, no lo del último dibujo: dos toques seguidos no se pisan.
                val ahora = (m.borrador.value.respuestas[p.id] as? ValorJson.Lista)?.elementos.orEmpty().mapNotNull { it.comoTexto }.toSet()
                val s = if (o.valor in ahora) ahora - o.valor else ahora + o.valor
                m.responder(p.id, ValorJson.Lista(p.opciones.map { it.valor }.filter { it in s }.map { ValorJson.Texto(it) }))
            }
        }
    } else {
        for (o in p.opciones) {
            val marcada = valor == ValorJson.Texto(o.valor)
            OpcionFila(o.texto, marcada, "gimnasio-opcion-${o.valor}", unica = true) {
                m.responder(p.id, if (marcada) null else ValorJson.Texto(o.valor))
            }
        }
    }
}

@Composable
private fun Numero(m: ModeloGimnasio, p: PreguntaGimnasio, valor: ValorJson?, noSe: Boolean) {
    val inicial = (valor as? ValorJson.Numero)?.comoNumero?.let { n -> if (n == Math.rint(n)) n.toInt().toString() else n.toString().replace('.', ',') } ?: ""
    var kilos by rememberSaveable { mutableStateOf(inicial) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Campo(
            kilos,
            alCambiar = { s ->
                kilos = s
                val n = Gimnasio.kilos(s)
                if (n != null) m.responder(p.id, ValorJson.Numero(n)) else if (!noSe) m.responder(p.id, null)
            },
            marcador = T.elegirKilos,
            etiqueta = "gimnasio-kilos",
            modifier = Modifier.weight(1f),
            teclado = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        )
        Text(p.unidad ?: T.kg, style = MaterialTheme.typography.bodyLarge, color = MyPump.colores.textoSecundario)
    }
    if (kilos.isNotEmpty() && Gimnasio.kilos(kilos) == null) NotaGimnasio(T.kilosInvalidos, alerta = true)
}

@Composable
private fun ItemConfirmar(m: ModeloGimnasio, p: PreguntaGimnasio, item: ItemGimnasio, valor: ValorJson?, urls: Map<String, String>) {
    val c = MyPump.colores
    Tarjeta(relleno = Espacio.s, espaciado = Espacio.xs) {
        Text(item.texto, style = MaterialTheme.typography.titleMedium, color = c.texto)
        FotosDeReferencia(item.fotos, urls)
        Row(Modifier.selectableGroup(), horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            for ((v, texto) in listOf("si" to T.si, "no" to T.no, "no_se" to T.noSe)) {
                val mapa = (valor as? ValorJson.Objeto)?.campos.orEmpty()
                val marcada = mapa[item.tipo] == ValorJson.Texto(v)
                Box(
                    Modifier
                        .weight(1f)
                        .heightIn(min = 48.dp)
                        .clip(CircleShape)
                        .background(if (marcada) c.marca else c.campo)
                        .selectable(selected = marcada, role = Role.RadioButton) {
                            val ahora = (m.borrador.value.respuestas[p.id] as? ValorJson.Objeto)?.campos.orEmpty()
                            val nuevo = if (ahora[item.tipo] == ValorJson.Texto(v)) ahora - item.tipo else ahora + (item.tipo to ValorJson.Texto(v))
                            m.responder(p.id, if (nuevo.isEmpty()) null else ValorJson.Objeto(nuevo))
                        }
                        .semantics { contentDescription = "${item.texto}: $texto" }
                        .padding(Espacio.xs)
                        .testTag("gimnasio-${item.tipo}-$v"),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(texto, style = MaterialTheme.typography.labelLarge, color = if (marcada) c.sobreMarca else c.texto, textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun PedirFoto(m: ModeloGimnasio, p: PreguntaGimnasio, valor: ValorJson?, v: Vista) {
    NotaGimnasio(T.consejoCamara)
    val enCola = v.cola.firstOrNull { it.pregunta == p.id }
    if (valor == ValorJson.Texto("subida")) {
        NotaGimnasio(
            when {
                enCola == null -> T.cuentaFotos(1)
                v.subiendo == enCola.id -> T.subiendo
                else -> T.esperandoSenal
            },
        )
    }
    BotonAgregarFoto("gimnasio-p-${p.id}", true) { jpeg ->
        if (m.agregar(p.zona ?: Gimnasio.ZONA_OPCIONAL, jpeg, p.id) == ModeloGimnasio.Foto.GUARDADA) m.drenarEnFondo()
    }
    val noPuedo = valor == ValorJson.Texto("no_puedo")
    OpcionFila(T.noPuedoFoto, noPuedo, "gimnasio-no-puedo", unica = true) { m.responder(p.id, if (noPuedo) null else ValorJson.Texto("no_puedo")) }
}
