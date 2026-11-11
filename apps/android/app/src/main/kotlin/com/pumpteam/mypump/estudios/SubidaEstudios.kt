package com.pumpteam.mypump.estudios

import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloEstudios
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.fotos.ProveedorFotos
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.Estudios
import com.pumpteam.mypump.reglas.TextosEstudios as T
import java.io.File
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * La hoja de subida: el alumno junta fotos (cámara o selector de fotos) y PDF (selector de archivos), varias de una vez, y
 * los manda juntos. Ningún selector pide permisos: MyPump ve solo lo que el alumno elige, y la foto la saca la app de
 * cámara. Con [pedidoId] el envío responde a un estudio pendiente («Subir resultado»).
 *
 * Lo elegido y lo que se está convirtiendo viven en el modelo ([ModeloEstudios.borrador]): rotar el teléfono no pierde
 * nada. Si Android cierra la app con la cámara abierta, la hoja vuelve con lo que esta pantalla recordaba.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
internal fun SubidaEstudios(m: ModeloEstudios, pedidoId: String?, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val contexto = LocalContext.current
    val alcance = LocalAlcanceApp.current
    val alcanceHoja = rememberCoroutineScope()
    val estado by m.estado.collectAsStateWithLifecycle()
    val topeArchivos = estado?.topeArchivos ?: Estudios.TOPE_ARCHIVOS
    val topeMb = estado?.topeMb ?: Estudios.TOPE_MB

    val archivos by m.borrador.collectAsStateWithLifecycle()
    val preparando by m.preparando.collectAsStateWithLifecycle()
    var nota by rememberSaveable { mutableStateOf<String?>(null) }
    val hayCamara = remember { contexto.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }

    // Con archivos elegidos, deslizar hacia abajo (o tocar afuera, o «atrás») no los tira por accidente: se sale con «Cancelar».
    val libre = rememberUpdatedState(archivos.isEmpty() && preparando == 0)
    val aProposito = remember { mutableStateOf(false) }
    val dejarCerrar = remember { { valor: SheetValue -> valor != SheetValue.Hidden || aProposito.value || libre.value } }
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = dejarCerrar)

    // Lo que esta pantalla recuerda de la hoja (ruta y tipo de cada archivo), por si Android cierra la app.
    var recordados by rememberSaveable { mutableStateOf(ArrayList<String>()) }
    var alDia by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (m.borrador.value.isEmpty() && recordados.isNotEmpty()) {
            val guardados = recordados.chunked(2).filter { it.size == 2 }.map { ModeloEstudios.Nuevo(File(it[0]), it[1]) }
            withContext(Dispatchers.IO) { m.restaurarBorrador(guardados) }
        }
        // Restos de otra vez (Android cerró la app con la hoja abierta, o mientras se convertía una foto): se borran al
        // abrir. Con una conversión en curso (se rotó el teléfono) no se toca nada.
        if (m.preparando.value == 0) {
            val restos = ArchivosEstudios.restos(contexto, m.borrador.value.map { it.archivo.absolutePath }.toSet())
            withContext(Dispatchers.IO) { restos.forEach { it.delete() } }
        }
        alDia = true
    }
    LaunchedEffect(archivos, alDia) {
        if (alDia) recordados = ArrayList(archivos.flatMap { listOf(it.archivo.absolutePath, it.mime) })
    }

    fun cerrar(descartar: Boolean) {
        aProposito.value = true
        if (descartar) m.descartarBorrador()
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    // En el alcance de la app y contra el modelo: si Android recrea la pantalla mientras se convierte, la foto no se pierde.
    fun sumar(uris: List<Uri>, pdf: Boolean, temporal: File? = null) {
        if (uris.isEmpty()) {
            temporal?.delete()
            return
        }
        val resolver = contexto.contentResolver
        val reserva = m.reservar(uris.size)
        val entran = uris.take(reserva.entran)
        nota = if (entran.size < uris.size) T.topeArchivos(topeArchivos) else null
        if (entran.isEmpty()) {
            temporal?.delete()
            return
        }
        alcance.launch {
            try {
                for (uri in entran) {
                    val r = withContext(Dispatchers.IO) {
                        val r = try {
                            if (pdf) ArchivosEstudios.pdf(contexto, resolver, uri, topeMb) else ArchivosEstudios.foto(contexto, resolver, uri, topeMb)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (_: Exception) {
                            ArchivosEstudios.Resultado.Ilegible
                        }
                        // El lugar apartado se devuelve siempre, haya salido bien o no.
                        m.sumarAlBorrador(reserva.hoja, (r as? ArchivosEstudios.Resultado.Listo)?.let { ModeloEstudios.Nuevo(it.archivo, it.mime) })
                        r
                    }
                    when (r) {
                        is ArchivosEstudios.Resultado.Listo -> Unit
                        ArchivosEstudios.Resultado.Ilegible -> nota = T.archivoRechazado
                        ArchivosEstudios.Resultado.MuyPesado -> nota = T.pesaDeMas(topeMb)
                    }
                }
            } finally {
                // La foto cruda de la cámara (con sus metadatos) no queda, tampoco si esto se corta.
                temporal?.delete()
            }
        }
    }

    val camara = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val archivo = ProveedorFotos.archivo(contexto, ArchivosEstudios.CLAVE_CAMARA)
        val unica = ArchivosEstudios.unicaDeCamara(contexto)
        if (ok && archivo.length() > 0 && archivo.renameTo(unica)) sumar(listOf(ProveedorFotos.uri(contexto, unica)), pdf = false, temporal = unica) else archivo.delete()
    }
    val fotos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(Estudios.TOPE_ARCHIVOS)) { sumar(it, pdf = false) }
    val documentos = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { sumar(it, pdf = true) }

    fun siHayLugar(abrir: () -> Unit) {
        if (Estudios.restan(archivos.size + preparando, topeArchivos) == 0) nota = T.topeArchivos(topeArchivos) else abrir()
    }

    fun abrirFotos() = siHayLugar {
        try {
            fotos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        } catch (_: ActivityNotFoundException) {
            nota = T.archivoRechazado
        }
    }

    fun abrirCamara() = siHayLugar {
        val (archivo, uri) = ProveedorFotos.paraLaCamara(contexto, ArchivosEstudios.CLAVE_CAMARA)
        try {
            camara.launch(uri)
        } catch (_: ActivityNotFoundException) {
            // Un teléfono con cámara pero sin app que la abra: el selector de fotos.
            archivo.delete()
            abrirFotos()
        }
    }

    fun abrirPdf() = siHayLugar {
        try {
            documentos.launch(arrayOf(Estudios.MIME_PDF))
        } catch (_: ActivityNotFoundException) {
            nota = T.archivoRechazado
        }
    }

    fun enviar() {
        if (m.enviarBorrador(pedidoId)) {
            m.drenarEnFondo()
            cerrar(descartar = false)
        } else {
            nota = T.noSePudoGuardar
        }
    }

    ModalBottomSheet(
        // Solo llega acá con la hoja vacía (con algo elegido no se deja cerrar sin «Cancelar»).
        onDismissRequest = {
            m.descartarBorrador()
            alCerrar()
        },
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-subir-estudio"),
    ) {
        EncabezadoHoja(
            if (pedidoId != null) T.subirResultado else T.subirUnEstudio,
            cancelar = AccionHoja(T.cancelar, "estudios-cancelar-subida") { cerrar(descartar = true) },
        )
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = Espacio.m)
                .padding(top = Espacio.xs, bottom = Espacio.l),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
        ) {
            Column(Modifier.padding(horizontal = Espacio.xxs), verticalArrangement = Arrangement.spacedBy(Espacio.xxs)) {
                Text(T.guiaSubida, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
                Text(T.topeArchivos(topeArchivos), style = MaterialTheme.typography.bodySmall, color = c.textoSecundario, modifier = Modifier.testTag("estudios-tope"))
            }

            Tarjeta(relleno = 0.dp, espaciado = 0.dp) {
                if (hayCamara) {
                    Opcion(Iconos.Camara, T.sacarFotos, "estudios-sacar-fotos", ::abrirCamara)
                    Separador(sangria = 64.dp)
                }
                Opcion(Iconos.Foto, T.elegirFotos, "estudios-elegir-fotos", ::abrirFotos)
                Separador(sangria = 64.dp)
                Opcion(Iconos.Documento, T.elegirPdf, "estudios-elegir-pdf", ::abrirPdf)
            }

            if (archivos.isNotEmpty() || preparando > 0) {
                Tarjeta(relleno = 0.dp, espaciado = 0.dp, modifier = Modifier.testTag("estudios-archivos")) {
                    var fotosVistas = 0
                    var pdfVistos = 0
                    archivos.forEachIndexed { i, b ->
                        val nombre = if (b.esPdf) T.pdfN(++pdfVistos) else T.fotoN(++fotosVistas)
                        if (i > 0) Separador(sangria = 76.dp)
                        FilaBorrador(b, nombre) {
                            m.quitarDelBorrador(b)
                            nota = null
                        }
                    }
                    if (preparando > 0) {
                        if (archivos.isNotEmpty()) Separador(sangria = 76.dp)
                        Box(Modifier.fillMaxWidth().heightIn(min = 64.dp).testTag("estudios-preparando"), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(24.dp), color = c.marcaVivo, strokeWidth = 2.5.dp)
                        }
                    }
                }
            }

            nota?.let {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = Espacio.xxs).semantics { liveRegion = LiveRegionMode.Polite }.testTag("estudios-nota-subida"),
                    horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
                ) {
                    Icon(Iconos.Alerta, contentDescription = null, tint = c.alerta, modifier = Modifier.padding(top = 1.dp).size(18.dp))
                    Text(it, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium), color = c.alerta)
                }
            }

            BotonMarca(
                T.enviarArchivos(archivos.size.coerceAtLeast(1)),
                alTocar = ::enviar,
                modifier = Modifier.testTag("estudios-enviar"),
                habilitado = archivos.isNotEmpty() && preparando == 0,
            )
        }
    }
}

@Composable
private fun Opcion(icono: ImageVector, texto: String, etiqueta: String, alTocar: () -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clickable(role = Role.Button, onClick = alTocar)
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .testTag(etiqueta),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(Modifier.size(36.dp).background(c.marcaSuave, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icono, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
        }
        Text(texto, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.weight(1f))
        Icon(Iconos.Mas, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun FilaBorrador(b: ModeloEstudios.Elegido, nombre: String, alQuitar: () -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = Espacio.m, vertical = Espacio.xs).testTag("estudios-archivo"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        val forma = RoundedCornerShape(Radio.miniatura)
        Box(Modifier.size(48.dp).clip(forma).background(c.campo), contentAlignment = Alignment.Center) {
            val miniatura = if (b.esPdf) null else miniatura(b.archivo.absolutePath)
            if (miniatura != null) {
                Image(miniatura, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(48.dp))
            } else {
                Icon(if (b.esPdf) Iconos.Documento else Iconos.Foto, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(24.dp))
            }
        }
        Text(nombre, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.weight(1f))
        BotonSecundario(
            T.quitar,
            alTocar = alQuitar,
            compacto = true,
            modifier = Modifier.semantics { contentDescription = "${T.quitar} $nombre" }.testTag("estudios-quitar"),
        )
    }
}

/** La foto en chico, decodificada sin cargarla entera. */
@Composable
private fun miniatura(ruta: String): ImageBitmap? {
    val imagen by produceState<ImageBitmap?>(null, ruta) {
        value = withContext(Dispatchers.IO) {
            try {
                val medidas = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(ruta, medidas)
                var muestra = 1
                while (maxOf(medidas.outWidth, medidas.outHeight) / (muestra * 2) >= 160) muestra *= 2
                BitmapFactory.decodeFile(ruta, BitmapFactory.Options().apply { inSampleSize = muestra })?.asImageBitmap()
            } catch (_: Throwable) {
                null
            }
        }
    }
    return imagen
}
