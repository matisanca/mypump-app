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
import androidx.compose.foundation.lazy.rememberLazyListState
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
import com.pumpteam.mypump.diseno.Segmentado
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.rellenoInferior
import com.pumpteam.mypump.diseno.sinAbajo
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.progreso.FuerzaSegmento
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
 * Salud (2.1, S1): la quinta pestaña, donde estaba Progreso. Arriba un control segmentado con Recuperación, Fuerza y
 * Cuerpo; arranca en Recuperación y queda el último elegido mientras viva la app ([LocalNavegacion]). Un aviso o un link
 * eligen el segmento (`progress` → Fuerza, el viejo `myday` → Recuperación).
 *
 * - Recuperación: el score (con motivos, confianza y tendencia), la salud (sueño, corazón, actividad) y Mi reloj, que
 *   antes estaban en Revisión. En la demo no hay cuenta: lo dice.
 * - Fuerza: el volumen por músculo de la semana y lo que era Progreso (el detalle de un ejercicio tapa la pestaña).
 * - Cuerpo: el peso (con la carga del día), las fotos por semana y el check de la semana, de solo lectura: se suben en
 *   Revisión.
 */
@Composable
fun SaludPantalla(modelo: ModeloApp, alVolver: (() -> Unit)? = null) {
    val navegacion = LocalNavegacion.current
    val segmento = navegacion?.segmentoSalud ?: SegmentoSalud.RECUPERACION
    val progreso by modelo.progreso.collectAsStateWithLifecycle()
    val tarjetas = progreso?.tarjetas?.collectAsStateWithLifecycle()?.value.orEmpty()
    // El ejercicio abierto en Fuerza (su id). Sobrevive a cambiar de pestaña y a rotar, como la pila de iOS.
    var abierto by rememberSaveable { mutableStateOf<String?>(null) }
    // Abrir Salud de nuevo (la tarjeta o un aviso) arranca en la lista, no en el ejercicio que había quedado abierto.
    val aperturas = navegacion?.aperturasSalud ?: 0
    var aperturaVista by rememberSaveable { mutableStateOf(aperturas) }
    if (aperturas != aperturaVista) {
        aperturaVista = aperturas
        abierto = null
    }
    // Afuera de la lista: al volver del detalle queda donde estaba.
    val estadoLista = rememberLazyListState()
    val elegida = abierto?.takeIf { segmento == SegmentoSalud.FUERZA }?.let { id -> tarjetas.firstOrNull { it.id == id } }
    BackHandler(enabled = elegida != null) { abierto = null }

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
        label = "salud",
    ) { t ->
        if (t != null) {
            ProgresoDetalle(t, alVolver = { abierto = null })
        } else {
            MarcoPantalla("Salud", modifier = Modifier.testTag("salud-pantalla"), alVolver = alVolver) { relleno ->
                Column(Modifier.padding(relleno.sinAbajo()).fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Column(
                        Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(horizontal = Espacio.m).padding(bottom = Espacio.xs),
                        verticalArrangement = Arrangement.spacedBy(Espacio.s),
                    ) {
                        // Como la web, arriba de todas las escenas menos Revisión (GEN-03). Sin pendientes no ocupa lugar.
                        BannerRevision(modelo)
                        Segmentado(
                            opciones = SegmentoSalud.entries.map { it.titulo },
                            elegida = segmento.ordinal,
                            alElegir = { i -> navegacion?.segmentoSalud = SegmentoSalud.entries[i] },
                            modifier = Modifier.testTag("salud-segmentos"),
                            etiquetaPrueba = { i -> SegmentoSalud.entries[i].etiqueta },
                        )
                    }
                    Box(Modifier.weight(1f).fillMaxWidth()) {
                        when (segmento) {
                            SegmentoSalud.RECUPERACION -> RecuperacionSegmento(modelo)
                            SegmentoSalud.FUERZA -> FuerzaSegmento(modelo, estadoLista, alAbrir = { abierto = it })
                            SegmentoSalud.CUERPO -> CuerpoSegmento(modelo)
                        }
                    }
                }
            }
        }
    }
}

/** Lo que se desplaza en Recuperación y Cuerpo: a lo ancho de lectura, con lo que tapa la barra de pestañas al final. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Desplazable(etiqueta: String, alRecargar: (suspend () -> Unit)?, contenido: @Composable () -> Unit) {
    val alcance = LocalAlcanceApp.current
    var recargando by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = recargando,
        onRefresh = {
            val r = alRecargar ?: return@PullToRefreshBox   // la demo no toca la red
            recargando = true
            alcance.launch {
                try {
                    r()
                } finally {
                    recargando = false
                }
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) {
        Column(
            // Con el teclado abierto (el peso del día) lo que se desplaza se achica y el campo queda a la vista.
            Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).testTag(etiqueta),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier
                    .widthIn(max = AnchoLectura)
                    .fillMaxWidth()
                    .padding(horizontal = Espacio.m)
                    .padding(top = Espacio.xs, bottom = Espacio.xl + rellenoInferior()),
                verticalArrangement = Arrangement.spacedBy(Espacio.xl),
            ) { contenido() }
        }
    }
}

/** Recuperación: el score y la salud (del reloj o del teléfono) y Mi reloj. Sin cuenta (la demo), un estado vacío. */
@Composable
private fun RecuperacionSegmento(modelo: ModeloApp) {
    val salud by modelo.salud.collectAsStateWithLifecycle()
    var detalle by rememberSaveable { mutableStateOf(false) }
    val s = salud
    val demoHistorial by modelo.demoHistorial.collectAsStateWithLifecycle()
    if (s == null && demoHistorial != null) {
        // La demo con historial: el «Pump del día» con sus pasos inventados, y lo demás como siempre en la demo.
        Desplazable("recuperacion-lista", alRecargar = null) {
            com.pumpteam.mypump.metas.PumpDelDiaDe(modelo, enSalud = true)
            EstadoVacio(
                icono = Iconos.Reloj,
                titulo = "Sin datos en la demo",
                texto = "La recuperación sale de tu reloj o de tu teléfono. En la demo no hay datos.",
                modifier = Modifier.testTag("recuperacion-vacia"),
            )
        }
        return
    }
    if (s == null) {
        EstadoVacio(
            icono = Iconos.Reloj,
            titulo = "Sin datos en la demo",
            texto = "La recuperación sale de tu reloj o de tu teléfono. En la demo no hay datos.",
            modifier = Modifier.padding(bottom = rellenoInferior()).testTag("recuperacion-vacia"),
        )
        return
    }
    Desplazable("recuperacion-lista", alRecargar = { s.cargar() }) {
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
            com.pumpteam.mypump.metas.PumpDelDiaDe(modelo, enSalud = true)
            CardRecuperacion(s, alVerTodo = { detalle = true })
            CardSalud(s)
        }
        // Oura y WHOOP según lo que ofrezca el servidor (sin relojes para ofrecer, no ocupa lugar).
        MiReloj(s, Modifier.testTag("seccion-reloj"))
        PieRespaldo(OrigenRespaldo.RECUPERACION)
    }
    if (detalle) {
        PantallaSuperpuesta(alCerrar = { detalle = false }) {
            SaludDetallePantalla(s, alVolver = { detalle = false })
        }
    }
}

/** Cuerpo: el peso (lo único que se carga acá: el del día), las fotos por semana y el check de la semana. */
@Composable
private fun CuerpoSegmento(modelo: ModeloApp) {
    val revision by modelo.revision.collectAsStateWithLifecycle()
    val fotos by modelo.fotos.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val r = revision
    val f = fotos
    Desplazable(
        "cuerpo-lista",
        alRecargar = if (esDemo) null else suspend {
            coroutineScope {
                launch { r?.cargarRevision() }
                launch { f?.cargar() }
            }
            Unit
        },
    ) {
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
