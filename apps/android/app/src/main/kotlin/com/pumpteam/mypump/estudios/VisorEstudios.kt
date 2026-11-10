package com.pumpteam.mypump.estudios

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color as ColorAndroid
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.activity.compose.BackHandler
import com.pumpteam.mypump.datos.ModeloEstudios
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.LocalRellenoInferior
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.reglas.Estudios
import com.pumpteam.mypump.reglas.TextosEstudios as T
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Lo que se pidió abrir: una orden o un estudio propio. */
internal data class Abierto(val clase: String, val id: String, val titulo: String)

/**
 * Los documentos bajados para ver. Viven en un temporal de la caché propia mientras la pantalla está abierta: al cerrar se
 * sueltan los lectores y se borran los archivos. Nunca se le pasan a otra app.
 */
private class Documentos(private val carpeta: File) {
    sealed interface Hoja {
        val proporcion: Float
    }

    private class HojaPdf(val lector: PdfRenderer, val indice: Int, override val proporcion: Float) : Hoja
    private class HojaImagen(val archivo: File, override val proporcion: Float) : Hoja

    private val lectores = ArrayList<Pair<PdfRenderer, ParcelFileDescriptor>>()
    private val archivos = ArrayList<File>()
    private var cerrado = false
    val hojas = ArrayList<Hoja>()

    fun nuevoArchivo(mime: String): File {
        carpeta.mkdirs()
        return File(carpeta, "${UUID.randomUUID()}" + if (mime == Estudios.MIME_PDF) ".pdf" else ".img").also { synchronized(this) { archivos += it } }
    }

    /** Suma las hojas de un archivo ya bajado. Devuelve si se pudo leer. */
    fun abrir(archivo: File, mime: String): Boolean = synchronized(this) {
        if (cerrado) return false
        try {
            val esPdf = mime == Estudios.MIME_PDF || archivo.inputStream().use { e -> ByteArray(5).also { e.read(it) } }.let(Estudios::esPdf)
            if (esPdf) {
                val descriptor = ParcelFileDescriptor.open(archivo, ParcelFileDescriptor.MODE_READ_ONLY)
                val lector = try {
                    PdfRenderer(descriptor)
                } catch (e: Exception) {
                    descriptor.close()
                    throw e
                }
                lectores += lector to descriptor
                for (i in 0 until lector.pageCount) {
                    lector.openPage(i).use { p -> hojas += HojaPdf(lector, i, (p.width.toFloat() / p.height.toFloat()).coerceIn(0.2f, 5f)) }
                }
                lector.pageCount > 0
            } else {
                val medidas = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(archivo.path, medidas)
                if (medidas.outWidth <= 0 || medidas.outHeight <= 0) return false
                hojas += HojaImagen(archivo, (medidas.outWidth.toFloat() / medidas.outHeight.toFloat()).coerceIn(0.2f, 5f))
                true
            }
        } catch (_: Exception) {
            // Un PDF con clave o roto, o una imagen que no se puede leer.
            false
        }
    }

    /** La hoja dibujada a [anchoPx]. Una a la vez: el lector de PDF del sistema no deja dos páginas abiertas. */
    fun dibujar(hoja: Hoja, anchoPx: Int): ImageBitmap? = synchronized(this) {
        if (cerrado || anchoPx <= 0) return null
        try {
            when (hoja) {
                is HojaPdf -> hoja.lector.openPage(hoja.indice).use { p ->
                    val alto = (anchoPx / hoja.proporcion).toInt().coerceAtLeast(1)
                    val mapa = Bitmap.createBitmap(anchoPx, alto, Bitmap.Config.ARGB_8888)
                    mapa.eraseColor(ColorAndroid.WHITE)
                    p.render(mapa, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    mapa.asImageBitmap()
                }
                is HojaImagen -> {
                    val medidas = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(hoja.archivo.path, medidas)
                    var muestra = 1
                    while (medidas.outWidth / (muestra * 2) >= anchoPx) muestra *= 2
                    BitmapFactory.decodeFile(hoja.archivo.path, BitmapFactory.Options().apply { inSampleSize = muestra })?.asImageBitmap()
                }
            }
        } catch (_: Throwable) {
            null
        }
    }

    fun cerrar() = synchronized(this) {
        cerrado = true
        for ((lector, descriptor) in lectores) {
            try {
                lector.close()
            } catch (_: Exception) {
            }
            try {
                descriptor.close()
            } catch (_: Exception) {
            }
        }
        lectores.clear()
        hojas.clear()
        archivos.forEach { it.delete() }
        archivos.clear()
    }
}

private sealed interface EstadoVisor {
    data object Cargando : EstadoVisor
    data object Error : EstadoVisor
    data class Listo(val documentos: Documentos) : EstadoVisor
}

/**
 * Una orden o un estudio propio, DENTRO de la app: se piden las URL (duran 10 minutos y no se guardan), se baja a un
 * temporal y se dibuja acá, hoja por hoja. Al cerrar no queda nada en el teléfono.
 */
@Composable
internal fun VisorEstudios(m: ModeloEstudios, abierto: Abierto, alCerrar: () -> Unit) {
    val contexto = LocalContext.current
    val c = MyPump.colores
    var intento by remember { mutableStateOf(0) }
    var estado by remember { mutableStateOf<EstadoVisor>(EstadoVisor.Cargando) }
    val documentos = remember(abierto, intento) { Documentos(ArchivosEstudios.paraVer(contexto)) }
    DisposableEffect(documentos) { onDispose { documentos.cerrar() } }
    BackHandler(onBack = alCerrar)

    LaunchedEffect(documentos) {
        estado = EstadoVisor.Cargando
        val bien = when (val r = m.urls(abierto.clase, abierto.id)) {
            is ModeloEstudios.Apertura.Ok -> {
                var todos = true
                for (remoto in r.archivos) {
                    val destino = documentos.nuevoArchivo(remoto.mime)
                    val leido = withContext(Dispatchers.IO) { m.bajar(remoto, destino) && documentos.abrir(destino, remoto.mime) }
                    if (!leido) {
                        todos = false
                        break
                    }
                }
                todos && documentos.hojas.isNotEmpty()
            }
            else -> false
        }
        estado = if (bien) EstadoVisor.Listo(documentos) else EstadoVisor.Error
    }

    MarcoPantalla(abierto.titulo, alVolver = alCerrar) { relleno ->
        when (val e = estado) {
            EstadoVisor.Cargando -> Box(Modifier.fillMaxSize().padding(relleno).testTag("estudios-visor-cargando"), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = c.marcaVivo)
            }
            EstadoVisor.Error -> Column(
                Modifier.fillMaxSize().padding(relleno).padding(horizontal = Espacio.xl),
                verticalArrangement = Arrangement.spacedBy(Espacio.m, Alignment.CenterVertically),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Iconos.Documento, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(44.dp))
                Text(
                    T.noSePudoAbrir,
                    style = MaterialTheme.typography.titleMedium,
                    color = c.texto,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("estudios-visor-error"),
                )
                BotonSecundario(T.probarDeNuevo, alTocar = { intento++ }, compacto = true, tono = c.marcaTexto, modifier = Modifier.testTag("estudios-visor-reintentar"))
            }
            is EstadoVisor.Listo -> Hojas(e.documentos, relleno)
        }
    }
}

/** Las hojas una debajo de la otra. Se agranda con dos dedos o con dos toques, y agrandado se mueve para los costados. */
@Composable
private fun Hojas(documentos: Documentos, relleno: PaddingValues) {
    val hojas = remember(documentos) { documentos.hojas.toList() }
    var escala by remember { mutableFloatStateOf(1f) }
    val densidad = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxSize().padding(top = relleno.calculateTopPadding())) {
        val base = maxWidth
        // El dibujo se hace una vez, con el doble de puntos que la pantalla (hasta 2200): al agrandar se sigue leyendo.
        val anchoPx = with(densidad) { (base.toPx() * 2f).toInt().coerceIn(1, 2200) }
        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    awaitEachGesture {
                        do {
                            val evento = awaitPointerEvent(PointerEventPass.Initial)
                            if (evento.changes.count { it.pressed } >= 2) {
                                val zoom = evento.calculateZoom()
                                if (zoom != 1f) escala = (escala * zoom).coerceIn(1f, 4f)
                                evento.changes.forEach { it.consume() }
                            }
                        } while (evento.changes.any { it.pressed })
                    }
                }
                .pointerInput(Unit) { detectTapGestures(onDoubleTap = { escala = if (escala > 1f) 1f else 2f }) }
                .horizontalScroll(rememberScrollState())
                .testTag("estudios-visor"),
        ) {
            LazyColumn(
                Modifier.width(base * escala).fillMaxHeight(),
                contentPadding = PaddingValues(start = Espacio.xs, end = Espacio.xs, top = Espacio.xs, bottom = Espacio.xl + LocalRellenoInferior.current),
                verticalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                itemsIndexed(hojas) { i, hoja ->
                    val imagen by produceState<ImageBitmap?>(null, hoja, anchoPx) {
                        value = withContext(Dispatchers.IO) { documentos.dibujar(hoja, anchoPx) }
                    }
                    Box(
                        // El papel es blanco también en oscuro: es un documento, no una pantalla de la app.
                        Modifier.fillMaxWidth().aspectRatio(hoja.proporcion).clip(RoundedCornerShape(6.dp)).background(Color.White).testTag("estudios-visor-hoja"),
                        contentAlignment = Alignment.Center,
                    ) {
                        val lista = imagen
                        if (lista != null) {
                            Image(lista, contentDescription = T.paginaDe(i + 1, hojas.size), contentScale = ContentScale.FillWidth, modifier = Modifier.fillMaxSize())
                        } else {
                            CircularProgressIndicator(Modifier.size(24.dp), color = Color(0xFF1D9330), strokeWidth = 2.5.dp)
                        }
                    }
                }
            }
        }
    }
}
