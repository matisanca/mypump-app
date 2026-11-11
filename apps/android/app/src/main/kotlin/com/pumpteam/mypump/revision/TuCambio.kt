package com.pumpteam.mypump.revision

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.FotoPendiente
import com.pumpteam.mypump.datos.ModeloFotos
import com.pumpteam.mypump.datos.ModeloFotosInicio
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.ImagenRemota
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.apoyo
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.reglas.TuCambio
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** La imagen de una foto de «Tu cambio»: la URL firmada, el archivo de la cola de inicio o el JPEG de la cola de progreso. */
internal sealed interface ImagenTuCambio {
    data class Url(val url: String) : ImagenTuCambio
    data class Archivo(val archivo: File) : ImagenTuCambio
    data class Datos(val dataUrl: String) : ImagenTuCambio
}

/**
 * De dónde salen las fotos de «Tu cambio» (gemela de `FuentesTuCambio` de iOS): las de progreso (servidor y cola) y las de
 * inicio guiadas, más el peso para el pie. Solo lo que la app ya lee; ninguna llamada nueva.
 */
internal class FuentesTuCambio(
    val fotos: ModeloFotos?,
    val inicio: ModeloFotosInicio?,
    val peso: List<PesoCorporal.Punto>,
    val entradas: List<Pair<String, String>>,
    val fechasInicio: Map<String, String>,
    private val pendientes: Map<String, FotoPendiente>,
    private val urls: Map<String, String>,
    private val urlsInicio: Map<String, String>,
) {
    fun vista(pose: String): TuCambio.Vista =
        TuCambio.vista(entradas, fechasInicio, fotos?.semanaActual ?: FotosProgreso.lunes(com.pumpteam.mypump.reglas.FechaLocal.hoy()), pose, peso)

    fun imagen(foto: TuCambio.Foto?, pose: String): ImagenTuCambio? {
        foto ?: return null
        return when (foto.origen) {
            TuCambio.Origen.INICIO -> {
                val v = inicio?.foto(pose) ?: return null
                v.archivoLocal?.let { ImagenTuCambio.Archivo(it) } ?: urlsInicio[v.id]?.let { ImagenTuCambio.Url(it) }
            }
            TuCambio.Origen.PROGRESO -> {
                val clave = "${foto.semana}|$pose"
                // La que espera subir es la más nueva (reemplaza a la del servidor).
                pendientes[clave]?.let { ImagenTuCambio.Datos(it.dataUrl) } ?: urls[clave]?.let { ImagenTuCambio.Url(it) }
            }
        }
    }

    /** Las URLs firmadas de las dos fuentes (cada modelo guarda las suyas 50 minutos). */
    suspend fun firmar() {
        if (fotos != null && entradas.isNotEmpty()) fotos.firmar()
        if (inicio != null && fechasInicio.isNotEmpty()) inicio.firmar()
    }
}

/** Las fuentes, siguiendo a los dos modelos. */
@Composable
internal fun recordarFuentesTuCambio(fotos: ModeloFotos, inicio: ModeloFotosInicio?, peso: List<PesoCorporal.Punto>): FuentesTuCambio {
    val deProgreso by fotos.fotos.collectAsStateWithLifecycle()
    val pendientes by fotos.pendientes.collectAsStateWithLifecycle()
    val urls by fotos.urls.collectAsStateWithLifecycle()
    val estadoInicio = inicio?.estado?.collectAsStateWithLifecycle()?.value
    val colaInicio = inicio?.cola?.collectAsStateWithLifecycle()?.value ?: emptyList()
    val urlsInicio = inicio?.urls?.collectAsStateWithLifecycle()?.value ?: emptyMap()
    return remember(fotos, inicio, peso, deProgreso, pendientes, urls, estadoInicio, colaInicio, urlsInicio) {
        val entradas = deProgreso.map { it.semanaLunes to it.pose } + pendientes.values.map { FotosProgreso.lunes(it.fecha) to it.pose }
        val fechas = HashMap<String, String>()
        if (estadoInicio != null) {
            for ((p, _) in FotosProgreso.poses) {
                val iso = colaInicio.lastOrNull { it.pose == p }?.tomadaEn ?: estadoInicio.foto(p)?.tomadaEn
                iso?.let { TuCambio.fechaLocal(it) }?.let { fechas[p] = it }
            }
        }
        FuentesTuCambio(fotos, inicio, peso, entradas, fechas, pendientes, urls, urlsInicio)
    }
}

/**
 * «Tu cambio» en Revisión (detrás de `check_guiado`), debajo de la tarjeta del check: la semana 1 al lado de la última,
 * por pose, con el pie de siempre. Tocarla abre el comparador a pantalla completa. Sin ningún botón de compartir: las
 * fotos son privadas.
 */
@Composable
internal fun TarjetaTuCambio(fuentes: FuentesTuCambio, modifier: Modifier = Modifier) {
    var pose by rememberSaveable { mutableStateOf(TuCambio.POSE_INICIAL) }
    var comparador by rememberSaveable { mutableStateOf(false) }
    val v = fuentes.vista(pose)
    val c = MyPump.colores
    LaunchedEffect(fuentes.entradas.size, fuentes.fechasInicio.size) { fuentes.firmar() }

    Tarjeta(modifier.testTag("tucambio-tarjeta"), espaciado = Espacio.m) {
        Text(
            TuCambio.TITULO,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = c.texto,
            modifier = Modifier.semantics { heading() },
        )
        if (v.modo == TuCambio.Modo.PAR) {
            SelectorPoseTuCambio(pose) { pose = it }
            // Tocar las fotos abre el comparador; para TalkBack cada foto es su propio elemento y el camino es el botón.
            ParTuCambio(v, fuentes, Modifier.clickable(onClickLabel = TuCambio.BOTON_VER) { comparador = true })
            v.pie?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = c.texto,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().testTag("tucambio-pie"),
                )
            }
            BotonSecundario(TuCambio.BOTON_VER, alTocar = { comparador = true }, tono = c.marcaTexto, modifier = Modifier.testTag("tucambio-ver"))
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(Espacio.m), verticalAlignment = Alignment.Top) {
                if (v.antes != null) {
                    MarcoTuCambio(
                        fuentes.imagen(v.antes, v.pose), v.rotuloAntes, v.accesibleAntes, TuCambio.sinFoto(v.pose),
                        Modifier.widthIn(max = 150.dp).weight(1f).testTag("tucambio-antes"),
                    )
                }
                Text(
                    v.texto ?: "",
                    style = MaterialTheme.typography.bodyLarge,
                    color = c.apoyo,
                    modifier = Modifier.weight(1f).testTag("tucambio-espera"),
                )
            }
        }
    }

    if (comparador) {
        GaleriaFotos(fuentes.fotos, fuentes.fotos?.fotos?.value ?: emptyList(), fuentes.fotos?.urls?.value ?: emptyMap(), fuentes.peso,
            alCerrar = { comparador = false }, tuCambio = fuentes, poseInicial = pose)
    }
}

/** La semana 1 y la última, lado a lado (también con letra grande: es una comparación). */
@Composable
internal fun ParTuCambio(v: TuCambio.Vista, fuentes: FuentesTuCambio, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        MarcoTuCambio(fuentes.imagen(v.antes, v.pose), v.rotuloAntes, v.accesibleAntes, TuCambio.sinFoto(v.pose), Modifier.weight(1f).testTag("tucambio-antes"))
        MarcoTuCambio(fuentes.imagen(v.despues, v.pose), v.rotuloDespues, v.accesibleDespues, TuCambio.sinFoto(v.pose), Modifier.weight(1f).testTag("tucambio-despues"))
    }
}

/** Frente / Perfil / Espalda: tres botones grandes con texto (48 de alto); el elegido, verde lleno. Con letra grande se apilan. */
@Composable
internal fun SelectorPoseTuCambio(pose: String, alElegir: (String) -> Unit) {
    val c = MyPump.colores
    val apilados = LocalDensity.current.fontScale >= 1.5f
    val boton: @Composable (String, String, Modifier) -> Unit = { clave, etiqueta, m ->
        val elegida = pose == clave
        Box(
            m
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(50))
                .background(if (elegida) c.marca else c.campo)
                .selectable(selected = elegida, role = Role.Tab) { alElegir(clave) }
                .padding(horizontal = Espacio.s, vertical = Espacio.xs)
                .testTag("tucambio-pose-$clave"),
            contentAlignment = Alignment.Center,
        ) {
            Text(etiqueta, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = if (elegida) c.sobreMarca else c.texto)
        }
    }
    if (apilados) {
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) { for ((k, e) in FotosProgreso.poses) boton(k, e, Modifier.fillMaxWidth()) }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) { for ((k, e) in FotosProgreso.poses) boton(k, e, Modifier.weight(1f)) }
    }
}

/** Una foto vertical 3:4 con su rótulo debajo. Sin foto: el marco gris con «Sin foto de perfil». */
@Composable
internal fun MarcoTuCambio(imagen: ImagenTuCambio?, rotulo: String, accesible: String, vacio: String, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Column(
        modifier.clearAndSetSemantics { contentDescription = accesible },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(3f / 4f).clip(RoundedCornerShape(Radio.control)).background(c.campo),
            contentAlignment = Alignment.Center,
        ) {
            when (imagen) {
                null -> Text(vacio, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, textAlign = TextAlign.Center, modifier = Modifier.padding(Espacio.xs))
                is ImagenTuCambio.Url -> ImagenRemota(
                    imagen.url,
                    lado = 360.dp,
                    modifier = Modifier.fillMaxSize(),
                    mientrasCarga = {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(20.dp), color = c.textoSecundario, strokeWidth = 2.dp)
                        }
                    },
                ) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Icon(Iconos.Foto, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(24.dp))
                    }
                }
                else -> ImagenLocalTuCambio(imagen)
            }
        }
        Text(rotulo, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = c.texto, textAlign = TextAlign.Center)
    }
}

/** La foto que todavía está en el teléfono, decodificada achicada fuera del hilo principal. */
@Composable
private fun ImagenLocalTuCambio(imagen: ImagenTuCambio) {
    val bitmap by produceState<ImageBitmap?>(null, imagen) {
        value = withContext(Dispatchers.IO) {
            val opciones = BitmapFactory.Options().apply { inSampleSize = 2 }
            runCatching {
                when (imagen) {
                    is ImagenTuCambio.Archivo -> BitmapFactory.decodeFile(imagen.archivo.path, opciones)
                    is ImagenTuCambio.Datos -> {
                        val b = Base64.decode(imagen.dataUrl.substringAfter(','), Base64.DEFAULT)
                        BitmapFactory.decodeByteArray(b, 0, b.size, opciones)
                    }
                    is ImagenTuCambio.Url -> null
                }?.asImageBitmap()
            }.getOrNull()
        }
    }
    val b = bitmap
    if (b != null) Image(b, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
    else Box(Modifier.fillMaxSize().background(MyPump.colores.campo))
}

/** «Antes y ahora» de la galería con la regla de «Tu cambio»: el selector grande y las dos fotos de la pose. */
@Composable
internal fun ComparadorTuCambio(fuentes: FuentesTuCambio, pose: String, alElegir: (String) -> Unit) {
    val v = fuentes.vista(pose)
    Tarjeta(Modifier.testTag("tucambio-comparador"), espaciado = Espacio.m) {
        com.pumpteam.mypump.diseno.EncabezadoSeccion("Antes y ahora", detalle = v.pie)
        SelectorPoseTuCambio(pose, alElegir)
        ParTuCambio(v, fuentes)
    }
}

/** «Listo» del check guiado: el par de frente, solo con las dos fotos. */
@Composable
internal fun ParListoTuCambio(fuentes: FuentesTuCambio?) {
    fuentes ?: return
    val v = fuentes.vista(TuCambio.POSE_INICIAL)
    if (v.modo != TuCambio.Modo.PAR || v.antes == null || v.despues == null) return
    LaunchedEffect(Unit) { fuentes.firmar() }
    val c = MyPump.colores
    Column(
        Modifier.widthIn(max = 360.dp).fillMaxWidth().padding(top = Espacio.m).testTag("cg-listo-tucambio"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Text(TuCambio.LISTO_TITULO, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = c.texto, modifier = Modifier.semantics { heading() })
        ParTuCambio(v, fuentes)
        v.pie?.let { Text(it, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = c.texto, modifier = Modifier.testTag("cg-listo-pie")) }
    }
}
