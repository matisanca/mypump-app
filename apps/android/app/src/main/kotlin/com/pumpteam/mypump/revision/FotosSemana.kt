package com.pumpteam.mypump.revision

import com.pumpteam.mypump.diseno.sinAbajo
import com.pumpteam.mypump.diseno.Segmentado
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloFotos
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.ImagenRemota
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.fotos.BotonFoto
import com.pumpteam.mypump.fotos.ReduccionFoto
import com.pumpteam.mypump.modelos.FotoProgreso
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.salud.PantallaSuperpuesta
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.launch

/**
 * Fotos de la semana (REV-02…05, gemela de `FotosSemana.swift`): frente, perfil y espalda desde la cámara o la galería
 * (JPEG de 900 px a 0,7, sin ubicación: [ReduccionFoto]). Cada lugar es un marco vertical; con la foto subida muestra la
 * miniatura firmada (`/progreso/urls`, que el modelo guarda 50 minutos). La cola es la de [ModeloFotos]: sin señal la foto
 * queda guardada y se sube sola, y con 3 esperando no entra otra. En la demo ([modelo] null) no se sube nada.
 */
@Composable
fun FotosSemana(modelo: ModeloFotos?, peso: List<PesoCorporal.Punto>, modifier: Modifier = Modifier) {
    val alcance = LocalAlcanceApp.current
    val tactil = LocalHapticFeedback.current
    val fotos = modelo?.fotos?.collectAsStateWithLifecycle()?.value ?: emptyList()
    val pendientes = modelo?.pendientes?.collectAsStateWithLifecycle()?.value ?: emptyMap()
    val urls = modelo?.urls?.collectAsStateWithLifecycle()?.value ?: emptyMap()
    val subiendo = modelo?.subiendo?.collectAsStateWithLifecycle()?.value ?: emptySet()
    val semana = modelo?.semanaActual ?: FotosProgreso.lunes(FechaLocal.hoy())
    val hechas = remember(fotos, pendientes, semana) {
        FotosProgreso.posesDeLaSemana(fotos, pendientes.values.map { it.pose to it.fecha }, semana)
    }
    val semanas = remember(fotos) { FotosProgreso.semanas(fotos) }
    val racha = remember(fotos) { FotosProgreso.racha(fotos) }
    var mensaje by remember { mutableStateOf<String?>(null) }
    var galeria by rememberSaveable { mutableStateOf(false) }
    // Con letra de accesibilidad, los tres marcos pasan a ser filas (no entran las palabras).
    val enFilas = LocalDensity.current.fontScale >= 1.5f
    val c = MyPump.colores

    // Las miniaturas y la galería van con URLs firmadas (duran 1 h; se piden de nuevo a los 50 min).
    LaunchedEffect(modelo, fotos.size) { if (modelo != null && fotos.isNotEmpty()) modelo.firmar() }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        EncabezadoSeccion("Fotos de la semana", detalle = if (hechas.size == 3) "Completas" else "${hechas.size}/3")
        Tarjeta(Modifier.animateContentSize(), espaciado = Espacio.m) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Iconos.Candado, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.padding(top = 2.dp).size(14.dp))
                Text(
                    buildAnnotatedString {
                        append("Mismo lugar, misma luz, en ayunas. Las ve ")
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("solo Mati") }
                        append(": no se publican ni salen de la app.")
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = c.textoSecundario,
                )
            }

            val lugares: @Composable (Modifier) -> Unit = { m ->
                for ((pose, etiqueta) in FotosProgreso.poses) {
                    val clave = "$semana|$pose"
                    val estado = EstadoPose(
                        lista = pose in hechas,
                        subiendo = clave in subiendo,
                        esperando = clave in pendientes,
                        miniatura = urls[clave],
                    )
                    val marco = @Composable { MarcoPose(pose, etiqueta, estado, enFilas) }
                    if (modelo != null) {
                        BotonFoto(
                            clave = pose,
                            maxPx = ReduccionFoto.LADO_PROGRESO,
                            calidad = ReduccionFoto.CALIDAD_PROGRESO,
                            alElegir = { jpeg ->
                                alcance.launch {
                                    val r = modelo.subir(pose, jpeg)
                                    mensaje = r.texto
                                    tactil.performHapticFeedback(
                                        if (r == ModeloFotos.Resultado.Guardada) HapticFeedbackType.Confirm else HapticFeedbackType.Reject,
                                    )
                                    // Reemplazar una foto de la semana no cambia cuántas hay: sin firmar de nuevo quedaba la
                                    // miniatura vieja (visto contra la base real). Cada firma es otra URL, así que tampoco
                                    // sale la vieja de la memoria.
                                    if (r == ModeloFotos.Resultado.Guardada) modelo.firmar()
                                }
                            },
                            modifier = m,
                            habilitado = !estado.subiendo,
                            contenido = marco,
                        )
                    } else {
                        Box(m.clickable { mensaje = "En la demo las fotos no se guardan." }) { marco() }
                    }
                }
            }
            if (enFilas) {
                Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) { lugares(Modifier.fillMaxWidth()) }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) { lugares(Modifier.weight(1f)) }
            }

            mensaje?.let { m ->
                val problema = m.startsWith("No") || m.startsWith("Esa") || m.startsWith("Hay")
                Text(
                    m,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                    color = if (problema) c.alerta else c.marcaTexto,
                    modifier = Modifier.testTag("mensaje-fotos"),
                )
            }

            if (racha >= 2) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Iconos.Fuego, contentDescription = null, tint = c.alerta, modifier = Modifier.size(18.dp))
                    Text("$racha semanas seguidas registradas", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                }
            }

            if (semanas.isEmpty()) {
                Text(
                    "Con la primera foto arranca tu historial. Mismo lugar y misma luz cada semana: así la comparación muestra tu cambio y no el del ambiente.",
                    style = Letras.caption,
                    color = c.textoSecundario,
                )
            } else {
                BotonSecundario(
                    "Ver mis fotos · ${semanas.size} semana${if (semanas.size == 1) "" else "s"}",
                    alTocar = { galeria = true },
                    compacto = true,
                    tono = c.marcaTexto,
                    modifier = Modifier.testTag("ver-mis-fotos"),
                )
                if (semanas.size < 4) {
                    val faltan = 4 - semanas.size
                    Text(
                        "El comparador antes/después se abre en $faltan semana${if (faltan > 1) "s" else ""} más.",
                        style = Letras.caption,
                        color = c.textoSecundario,
                    )
                }
            }
        }
    }

    if (galeria) GaleriaFotos(modelo, fotos, urls, peso, alCerrar = { galeria = false })
}

/** Cómo está un lugar de la semana: con la foto (y su miniatura, si ya se firmó), subiendo o esperando señal. */
private data class EstadoPose(val lista: Boolean, val subiendo: Boolean, val esperando: Boolean, val miniatura: String?) {
    val detalle: String
        get() = when {
            subiendo -> "Subiendo…"
            esperando -> "Esperando señal"
            lista -> "Lista"
            else -> "Agregar"
        }
}

/**
 * Marco vertical punteado con la cámara; subiendo, con la ruedita; con la foto, la miniatura y el tilde de marca. Con
 * [enFila], la versión horizontal para letra grande. Para TalkBack es un solo elemento: "Foto de frente, lista".
 */
@Composable
private fun MarcoPose(pose: String, nombre: String, estado: EstadoPose, enFila: Boolean) {
    val c = MyPump.colores
    val forma = RoundedCornerShape(Radio.control + 4.dp)
    val borde = if (estado.lista) c.marcaVivo.copy(alpha = 0.6f) else c.textoSecundario.copy(alpha = 0.35f)
    val semantica = Modifier
        .testTag("foto-$pose")
        .clearAndSetSemantics {
            contentDescription = "Foto de ${nombre.lowercase()}${if (estado.lista) ", lista" else ""}"
            stateDescription = estado.detalle
        }
    val contorno = Modifier.drawBehind {
        val ancho = 1.5.dp.toPx()
        val radio = (Radio.control + 4.dp).toPx()
        drawRoundRect(
            color = borde,
            topLeft = Offset(ancho / 2, ancho / 2),
            size = Size(size.width - ancho, size.height - ancho),
            cornerRadius = CornerRadius(radio - ancho / 2),
            style = Stroke(width = ancho, pathEffect = if (estado.lista) null else PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx()))),
        )
    }
    if (enFila) {
        Row(
            semantica.fillMaxWidth().clip(forma).background(c.campo.copy(alpha = c.campo.alpha * 0.5f)).then(contorno).padding(Espacio.s),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            IconoPose(estado)
            Column {
                Text(nombre, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text(estado.detalle, style = Letras.caption2, color = c.textoSecundario)
            }
        }
        return
    }
    // El marco pone el tamaño (un tercio del ancho, 3:4); la foto va detrás y no lo empuja.
    Box(semantica.fillMaxWidth().aspectRatio(3f / 4f).clip(forma).background(c.campo.copy(alpha = c.campo.alpha * 0.5f))) {
        val url = estado.miniatura
        if (url != null) {
            ImagenRemota(url, lado = 200.dp, modifier = Modifier.fillMaxSize()) { Box(Modifier.fillMaxSize().background(c.campo)) }
            Text(
                nombre,
                style = Letras.caption,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                maxLines = 1,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f))))
                    .padding(start = 4.dp, end = 4.dp, top = 14.dp, bottom = 8.dp),
            )
            Box(
                Modifier.align(Alignment.TopEnd).padding(8.dp).size(22.dp).clip(CircleShape).background(c.marca),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(14.dp))
            }
        } else {
            Column(
                Modifier.align(Alignment.Center).padding(horizontal = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                IconoPose(estado)
                Text(nombre, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(estado.detalle, style = Letras.caption2, color = c.textoSecundario, maxLines = 1)
            }
        }
        // El borde va encima de la miniatura (sin participar del tamaño del marco).
        Box(Modifier.matchParentSize().then(contorno))
    }
}

@Composable
private fun IconoPose(estado: EstadoPose) {
    val c = MyPump.colores
    Box(
        Modifier.size(42.dp).clip(CircleShape).background(if (estado.lista) c.marca else c.marcaSuave),
        contentAlignment = Alignment.Center,
    ) {
        when {
            estado.subiendo -> CircularProgressIndicator(Modifier.size(20.dp), color = c.marcaTexto, strokeWidth = 2.dp)
            estado.lista -> Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(20.dp))
            estado.esperando -> Icon(IconosRevision.NubeSubir, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
            else -> Icon(Iconos.Camara, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
        }
    }
}

/**
 * Mis fotos por semana (REV-04) y, desde las 4 semanas, el comparador antes/después con el cambio de peso (antes compara
 * luz y retención de líquido, no cambios reales). Una pantalla entera por encima de Revisión, como la hoja de iOS.
 */
@Composable
private fun GaleriaFotos(
    modelo: ModeloFotos?,
    fotos: List<FotoProgreso>,
    urls: Map<String, String>,
    peso: List<PesoCorporal.Punto>,
    alCerrar: () -> Unit,
) {
    val semanas = remember(fotos) { FotosProgreso.semanas(fotos) }
    LaunchedEffect(Unit) { modelo?.firmar() }
    PantallaSuperpuesta(alCerrar = alCerrar) {
        MarcoPantalla(
            "Mis fotos",
            alVolver = alCerrar,
            acciones = {
                TextButton(onClick = alCerrar, modifier = Modifier.testTag("galeria-listo")) {
                    Text("Listo", color = MyPump.colores.marcaTexto, fontWeight = FontWeight.SemiBold)
                }
            },
        ) { relleno ->
            Column(
                Modifier.padding(relleno.sinAbajo()).fillMaxSize().verticalScroll(rememberScrollState()).testTag("galeria-fotos"),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(Espacio.m).padding(bottom = relleno.calculateBottomPadding()),
                    verticalArrangement = Arrangement.spacedBy(Espacio.l),
                ) {
                    val primera = semanas.firstOrNull()
                    val ultima = semanas.lastOrNull()
                    if (semanas.size >= 4 && primera != null && ultima != null) Comparador(primera, ultima, fotos, urls, peso)
                    for (s in semanas.reversed()) {
                        Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                            Text("Semana del ${fechaLarga(s)}", style = Letras.titulo3, modifier = Modifier.padding(horizontal = 4.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                                for ((p, etiqueta) in FotosProgreso.poses) FotoDeLaGaleria(s, p, etiqueta, fotos, urls, Modifier.weight(1f))
                            }
                        }
                    }
                    Spacer(Modifier.size(Espacio.l))
                }
            }
        }
    }
}

@Composable
private fun Comparador(primera: String, ultima: String, fotos: List<FotoProgreso>, urls: Map<String, String>, peso: List<PesoCorporal.Punto>) {
    var pose by rememberSaveable { mutableStateOf("frente") }
    val c = MyPump.colores
    Tarjeta(Modifier.testTag("comparador")) {
        EncabezadoSeccion("Antes y ahora", detalle = FotosProgreso.resumenComparador(primera, ultima, peso))
        Segmentado(
            opciones = FotosProgreso.poses.map { it.second },
            elegida = FotosProgreso.poses.indexOfFirst { it.first == pose },
            alElegir = { pose = FotosProgreso.poses[it].first },
        )
        Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            FotoDeLaGaleria(primera, pose, fechaLarga(primera), fotos, urls, Modifier.weight(1f))
            FotoDeLaGaleria(ultima, pose, fechaLarga(ultima), fotos, urls, Modifier.weight(1f))
        }
    }
}

@Composable
private fun FotoDeLaGaleria(semana: String, pose: String, rotulo: String, fotos: List<FotoProgreso>, urls: Map<String, String>, modifier: Modifier) {
    val c = MyPump.colores
    val url = urls["$semana|$pose"]
    val hay = fotos.any { it.semanaLunes == semana && it.pose == pose }
    Column(
        modifier.clearAndSetSemantics { contentDescription = "$rotulo${if (hay) "" else ", sin foto"}" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(3f / 4f).clip(RoundedCornerShape(Radio.control)).background(c.campo),
            contentAlignment = Alignment.Center,
        ) {
            if (url != null) {
                // La ruedita, solo mientras se baja: si la foto no se pudo traer queda el ícono (una ruedita para siempre era
                // una espera sin fin).
                ImagenRemota(
                    url,
                    lado = 320.dp,
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
            } else {
                Icon(if (hay) Iconos.Foto else Iconos.Camara, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(24.dp))
            }
        }
        Text(rotulo, style = Letras.caption, color = c.textoSecundario)
    }
}

private val ES_AR: Locale = Locale.forLanguageTag("es-AR")

/** "12 de octubre" (el lunes de una semana). */
internal fun fechaLarga(lunes: String): String {
    val n = DiaCalendario.numero(lunes) ?: return lunes
    return DateTimeFormatter.ofPattern("d 'de' MMMM", ES_AR).format(LocalDate.ofEpochDay(n))
}
