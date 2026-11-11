package com.pumpteam.mypump.salud

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloFotos
import com.pumpteam.mypump.datos.ModeloRevision
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.rellenoInferior
import com.pumpteam.mypump.diseno.sinAbajo
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.progreso.FuerzaContenido
import com.pumpteam.mypump.progreso.ProgresoDetalle
import com.pumpteam.mypump.raiz.AnclaRevision
import com.pumpteam.mypump.raiz.BannerRevision
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.raiz.SegmentoSalud
import com.pumpteam.mypump.reglas.CheckinSemanal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.respaldo.OrigenRespaldo
import com.pumpteam.mypump.respaldo.PieRespaldo
import com.pumpteam.mypump.revision.GaleriaFotos
import com.pumpteam.mypump.revision.MiReloj
import com.pumpteam.mypump.revision.PesoTarjeta
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * «Mi progreso» (simplificar, OK de Mati del 11/11; antes «Salud», con Recuperación, Fuerza y Cuerpo en tres botones de
 * arriba que a los mayores les costaban): todo en UNA columna, con un título por sección. Se abre desde «Tu progreso» de
 * Revisión y desde la Recuperación de Mi salud, arriba (Recuperación primero); el aviso `progress` y «Fuerza» bajan a
 * Fuerza ([Navegacion.segmentoSalud] dice a qué sección ir). Nada de la recuperación se saca. Tirar hacia abajo recarga todo.
 *
 * - Recuperación: el score (con motivos, confianza y tendencia), la salud (sueño, corazón, actividad) y Mi reloj. En la
 *   demo no hay cuenta: lo dice.
 * - Fuerza: el volumen por músculo de la semana y cada ejercicio (el detalle de un ejercicio tapa la pantalla).
 * - Cuerpo: el peso (con la carga del día), las fotos por semana y el check de la semana, de solo lectura: se suben en
 *   Revisión.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SaludPantalla(modelo: ModeloApp, alVolver: (() -> Unit)? = null) {
    val navegacion = LocalNavegacion.current
    val segmento = navegacion?.segmentoSalud ?: SegmentoSalud.RECUPERACION
    val progreso by modelo.progreso.collectAsStateWithLifecycle()
    val tarjetas = progreso?.tarjetas?.collectAsStateWithLifecycle()?.value.orEmpty()
    // El ejercicio abierto en Fuerza (su id). Sobrevive a cambiar de pestaña y a rotar, como la pila de iOS.
    var abierto by rememberSaveable { mutableStateOf<String?>(null) }
    // Abrir Mi progreso de nuevo (la tarjeta o un aviso) arranca en la lista, en la sección pedida.
    val aperturas = navegacion?.aperturasSalud ?: 0
    var aperturaVista by rememberSaveable { mutableStateOf(aperturas) }
    if (aperturas != aperturaVista) {
        aperturaVista = aperturas
        abierto = null
    }
    // Afuera de la lista: al volver del detalle queda donde estaba.
    val desplazamiento = rememberScrollState()
    val elegida = abierto?.let { id -> tarjetas.firstOrNull { it.id == id } }
    BackHandler(enabled = elegida != null) { abierto = null }
    // Al volver del detalle, la lista queda donde estaba: al reaparecer se mide de a poco y el desplazamiento se recortaba
    // (se volvía a Recuperación). Se anota al abrir y se repone cuando la lista vuelve a tener ese largo.
    var volverA by rememberSaveable { mutableStateOf(-1) }
    LaunchedEffect(elegida != null) {
        if (elegida != null) {
            volverA = desplazamiento.value
        } else if (volverA >= 0) {
            val a = volverA
            withTimeoutOrNull(3_000) { snapshotFlow { desplazamiento.maxValue }.first { it >= a } }
            desplazamiento.scrollTo(a)
            volverA = -1
        }
    }
    // Dónde empieza cada sección (en lo que se desplaza), para bajar a la pedida.
    val inicios = remember { mutableStateMapOf<SegmentoSalud, Int>() }
    val reducir = com.pumpteam.mypump.entreno.reducirMovimiento()
    // El salto se hace una vez por apertura: rotar (o volver del detalle) no vuelve a mover la lista.
    val pedido = "$aperturas-${segmento.name}"
    var saltoHecho by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(pedido) {
        if (saltoHecho == pedido) return@LaunchedEffect
        saltoHecho = pedido
        if (segmento == SegmentoSalud.RECUPERACION) {
            desplazamiento.scrollTo(0)
            return@LaunchedEffect
        }
        // La sección puede tardar en medirse (la pantalla recién abre): se espera un poco.
        val y = withTimeoutOrNull(5_000) { snapshotFlow { inicios[segmento] }.filterNotNull().first() } ?: return@LaunchedEffect
        if (reducir) desplazamiento.scrollTo(y) else desplazamiento.animateScrollTo(y)
        // Lo de arriba puede crecer después (la recuperación llega con la app recién abierta, por un aviso): durante unos
        // segundos la sección se sigue, mientras la persona no haya movido la lista.
        var donde = desplazamiento.value
        withTimeoutOrNull(4_000) {
            snapshotFlow { inicios[segmento] }.filterNotNull().collect { nuevo ->
                if (desplazamiento.isScrollInProgress || desplazamiento.value != donde) return@collect
                desplazamiento.scrollTo(nuevo)
                donde = desplazamiento.value
            }
        }
    }
    val alcance = LocalAlcanceApp.current
    var recargando by remember { mutableStateOf(false) }
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()

    AnimatedContent(
        targetState = elegida,
        contentKey = { it?.id },
        transitionSpec = {
            if (targetState != null) {
                (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it / 4 } + fadeOut())
            } else {
                (slideInHorizontally { -it / 4 } + fadeIn()) togetherWith (slideOutHorizontally { it } + fadeOut())
            }
        },
        label = "mi-progreso",
    ) { t ->
        if (t != null) {
            ProgresoDetalle(t, alVolver = { abierto = null })
        } else {
            MarcoPantalla(TITULO_MI_PROGRESO, modifier = Modifier.testTag("salud-pantalla"), alVolver = alVolver) { relleno ->
                PullToRefreshBox(
                    isRefreshing = recargando,
                    onRefresh = {
                        if (esDemo) return@PullToRefreshBox   // la demo no toca la red
                        recargando = true
                        alcance.launch {
                            try {
                                coroutineScope {
                                    modelo.salud.value?.let { s -> launch { s.cargar() } }
                                    modelo.revision.value?.let { r -> launch { r.cargarRevision() } }
                                    modelo.fotos.value?.let { f -> launch { f.cargar() } }
                                    launch { modelo.cargarProgreso() }
                                }
                            } finally {
                                recargando = false
                            }
                        }
                    },
                    modifier = Modifier.padding(relleno.sinAbajo()).fillMaxSize(),
                ) {
                    Column(
                        // Con el teclado abierto (el peso del día) lo que se desplaza se achica y el campo queda a la vista.
                        Modifier.fillMaxSize().imePadding().verticalScroll(desplazamiento).testTag("mi-progreso-lista"),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Column(
                            Modifier
                                .widthIn(max = AnchoLectura)
                                .fillMaxWidth()
                                .padding(horizontal = Espacio.m)
                                .padding(top = Espacio.xs, bottom = Espacio.xl + rellenoInferior()),
                            verticalArrangement = Arrangement.spacedBy(Espacio.xl),
                        ) {
                            // Como la web, arriba de todas las escenas menos Revisión (GEN-03). Sin pendientes no ocupa lugar.
                            BannerRevision(modelo)
                            for (seccion in SegmentoSalud.entries) {
                                Column(
                                    Modifier.fillMaxWidth().onGloballyPositioned { inicios[seccion] = it.positionInParent().y.toInt() },
                                    verticalArrangement = Arrangement.spacedBy(Espacio.m),
                                ) {
                                    Text(
                                        seccion.titulo,
                                        style = MaterialTheme.typography.headlineSmall,
                                        fontWeight = FontWeight.Bold,
                                        color = MyPump.colores.texto,
                                        modifier = Modifier.padding(horizontal = 4.dp).semantics { heading() }.testTag("mi-progreso-${seccion.name.lowercase()}"),
                                    )
                                    when (seccion) {
                                        SegmentoSalud.RECUPERACION -> RecuperacionContenido(modelo)
                                        SegmentoSalud.FUERZA -> FuerzaContenido(modelo, alAbrir = { abierto = it })
                                        SegmentoSalud.CUERPO -> CuerpoContenido(modelo)
                                    }
                                }
                            }
                            PieRespaldo(OrigenRespaldo.RECUPERACION)
                        }
                    }
                }
            }
        }
    }
}

/** El título de la pantalla (la pestaña vieja se llamaba «Salud»). */
const val TITULO_MI_PROGRESO = "Mi progreso"

/** Recuperación: el score y la salud (del reloj o del teléfono) y Mi reloj. Sin cuenta (la demo), un estado vacío. */
@Composable
private fun RecuperacionContenido(modelo: ModeloApp) {
    val salud by modelo.salud.collectAsStateWithLifecycle()
    var detalle by rememberSaveable { mutableStateOf(false) }
    val s = salud
    val demoHistorial by modelo.demoHistorial.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxWidth().testTag("recuperacion-lista"), verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
        if (s == null) {
            // La demo con historial: el «Pump del día» con sus pasos inventados, y lo demás como siempre en la demo.
            if (demoHistorial != null) com.pumpteam.mypump.metas.PumpDelDiaDe(modelo, enSalud = true)
            EstadoVacio(
                icono = Iconos.Reloj,
                titulo = "Sin datos en la demo",
                texto = "La recuperación sale de tu reloj o de tu teléfono. En la demo no hay datos.",
                modifier = Modifier.testTag("recuperacion-vacia"),
            )
        } else {
            com.pumpteam.mypump.metas.PumpDelDiaDe(modelo, enSalud = true)
            CardRecuperacion(s, alVerTodo = { detalle = true })
            CardSalud(s)
            // Oura y WHOOP según lo que ofrezca el servidor (sin relojes para ofrecer, no ocupa lugar).
            MiReloj(s, Modifier.testTag("seccion-reloj"))
        }
    }
    if (s != null && detalle) {
        PantallaSuperpuesta(alCerrar = { detalle = false }) {
            SaludDetallePantalla(s, alVolver = { detalle = false })
        }
    }
}

/** Cuerpo: el peso (lo único que se carga acá: el del día), las fotos por semana y el check de la semana. */
@Composable
private fun CuerpoContenido(modelo: ModeloApp) {
    val revision by modelo.revision.collectAsStateWithLifecycle()
    val fotos by modelo.fotos.collectAsStateWithLifecycle()
    val r = revision
    val f = fotos
    Column(Modifier.fillMaxWidth().testTag("cuerpo-lista"), verticalArrangement = Arrangement.spacedBy(Espacio.xl)) {
        PesoTarjeta(r, Modifier.testTag("seccion-peso"), modelo = modelo)
        FotosPorSemana(f, r)
        CheckDeLaSemana(r)
    }
}

/**
 * «Fotos por semana»: la racha, cuántas semanas hay y la galería con el comparador (la de Revisión). Las fotos se suben
 * en Revisión: sin fotos, lleva ahí.
 */
@Composable
private fun FotosPorSemana(modelo: ModeloFotos?, revision: ModeloRevision?) {
    val c = MyPump.colores
    val navegacion = LocalNavegacion.current
    val fotos = modelo?.fotos?.collectAsStateWithLifecycle()?.value.orEmpty()
    val urls = modelo?.urls?.collectAsStateWithLifecycle()?.value.orEmpty()
    val filasDePeso = revision?.salud?.collectAsStateWithLifecycle()?.value.orEmpty()
    val peso = remember(filasDePeso) { PesoCorporal.serie(filasDePeso) }
    val semanas = remember(fotos) { FotosProgreso.semanas(fotos) }
    val racha = remember(fotos) { FotosProgreso.racha(fotos) }
    var galeria by rememberSaveable { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().testTag("cuerpo-fotos"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        EncabezadoSeccion("Fotos por semana", detalle = if (semanas.isEmpty()) null else "${semanas.size} semana${if (semanas.size == 1) "" else "s"}")
        Tarjeta(espaciado = Espacio.s) {
            if (semanas.isEmpty()) {
                Text("Las fotos se suben desde Revisión.", style = Letras.subtitulo, color = c.textoSecundario)
                BotonSecundario(
                    "Ir a Revisión",
                    alTocar = { navegacion?.irARevision(AnclaRevision.FOTOS) },
                    compacto = true,
                    tono = c.marcaTexto,
                    modifier = Modifier.testTag("cuerpo-ir-fotos"),
                )
            } else {
                Row(
                    Modifier.fillMaxWidth().clearAndSetSemantics {
                        contentDescription = "${semanas.size} semana${if (semanas.size == 1) "" else "s"} con fotos" +
                            if (racha >= 2) ", $racha semanas seguidas" else ""
                    },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    if (racha >= 2) {
                        Icon(Iconos.Fuego, contentDescription = null, tint = c.alerta, modifier = Modifier.size(16.dp))
                        Text("$racha semanas seguidas", style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.texto)
                    } else {
                        Text(
                            "${semanas.size} semana${if (semanas.size == 1) "" else "s"} con fotos",
                            style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold),
                            color = c.texto,
                        )
                    }
                }
                Text(
                    if (semanas.size >= 4) "Antes y después con el cambio de peso, en la galería." else {
                        val faltan = 4 - semanas.size
                        "El comparador antes/después se abre en $faltan semana${if (faltan > 1) "s" else ""} más."
                    },
                    style = Letras.caption,
                    color = c.textoSecundario,
                )
                BotonSecundario(
                    "Ver mis fotos",
                    alTocar = { galeria = true },
                    compacto = true,
                    tono = c.marcaTexto,
                    modifier = Modifier.testTag("cuerpo-ver-fotos"),
                )
            }
        }
    }
    // Las miniaturas de la galería van con URLs firmadas.
    LaunchedEffect(modelo, fotos.size) { if (modelo != null && fotos.isNotEmpty()) modelo.firmar() }
    if (galeria) GaleriaFotos(modelo, fotos, urls, peso, alCerrar = { galeria = false })
}

/** «Tu check de la semana», de solo lectura: las cuatro escalas y la nota. Se manda desde Revisión. */
@Composable
private fun CheckDeLaSemana(revision: ModeloRevision?) {
    val c = MyPump.colores
    val navegacion = LocalNavegacion.current
    val check = revision?.checkin?.collectAsStateWithLifecycle()?.value
    val enviado = (check?.valores?.get("energia") ?: 0) > 0
    Column(Modifier.fillMaxWidth().testTag("cuerpo-check"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        EncabezadoSeccion("Tu check de la semana", detalle = if (enviado) "Enviado" else null)
        Tarjeta(espaciado = 12.dp) {
            if (!enviado || check == null) {
                Text("Todavía no mandaste el check de esta semana.", style = Letras.subtitulo, color = c.textoSecundario)
                BotonSecundario(
                    "Ir a Revisión",
                    alTocar = { navegacion?.irARevision(AnclaRevision.CHECK) },
                    compacto = true,
                    tono = c.marcaTexto,
                    modifier = Modifier.testTag("cuerpo-ir-check"),
                )
            } else {
                for (m in CheckinSemanal.metricas) {
                    val v = check.valores[m.clave] ?: 0
                    Row(
                        Modifier.fillMaxWidth().testTag("cuerpo-check-${m.clave}").clearAndSetSemantics { contentDescription = "${m.etiqueta}: $v de 5" },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(m.etiqueta, style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.texto, modifier = Modifier.weight(1f))
                        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                            repeat(5) { i ->
                                Box(Modifier.size(8.dp).clip(CircleShape).background(if (i < v) c.marcaVivo else c.campo))
                            }
                        }
                        Text("$v/5", style = Letras.caption.merge(Letras.cifras), color = c.textoSecundario, modifier = Modifier.padding(start = 10.dp).widthIn(min = 26.dp))
                    }
                }
                if (check.nota.isNotBlank()) {
                    Text(check.nota, style = Letras.subtitulo.copy(fontStyle = FontStyle.Italic), color = c.textoSecundario, modifier = Modifier.testTag("cuerpo-check-nota"))
                }
            }
        }
    }
}
